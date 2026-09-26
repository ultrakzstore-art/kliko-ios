import AVFoundation
import CoreVideo
import UIKit

/// Этап записи ролика — подпись под полосой хода.
enum ЭтапЗаписиРолика: Equatable {
    case кадры
    case рендер
    case сборка
}

/// Готовый ролик: файл .mp4 во временной папке и есть ли в нём звук.
struct ГотовыйРолик: Equatable {
    let файл: URL
    let соЗвуком: Bool
}

/**
 Запись ролика: кадры рисует РисовальщикРолика (та же функция, что превью), AVAssetWriter кодирует их в H.264
 1080 × 1920, 30 кадров в секунду, 9 Мбит/с, ключевой кадр каждые 60 — как VideoEncoder сайта. Звук (ЗвукРолика, AAC)
 кладётся второй дорожкой через AVMutableComposition без перекодирования видео. Звук не вышел — ролик без звука, не
 ошибка (как у сайта).

 Работа идёт вне главной нити (nonisolated async); отмена — отменой задачи (Task.cancel), файл тогда удаляется.
 */
enum ЭкспортРолика {
    enum Сбой: Error {
        case запись
    }

    static func сделать(_ рисовальщик: РисовальщикРолика, звук: Bool, громкость: Double,
                        ход обновить: @escaping @MainActor @Sendable (Double, ЭтапЗаписиРолика) -> Void) async throws -> ГотовыйРолик {
        await обновить(0.02, .кадры)
        let видео = try await записатьВидео(рисовальщик, обновить: обновить)
        try Task.checkCancellation()
        guard звук else { return ГотовыйРолик(файл: видео, соЗвуком: false) }
        await обновить(0.95, .сборка)
        guard let дорожка = ЗвукРолика.записать(рисовальщик.ход, громкость: громкость) else {
            return ГотовыйРолик(файл: видео, соЗвуком: false)
        }
        defer { try? FileManager.default.removeItem(at: дорожка) }
        try Task.checkCancellation()
        if let вместе = await склеить(видео, дорожка) {
            try? FileManager.default.removeItem(at: видео)
            return ГотовыйРолик(файл: вместе, соЗвуком: true)
        }
        return ГотовыйРолик(файл: видео, соЗвуком: false)
    }

    private static func новыйАдрес() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("kliko-reel-\(UUID().uuidString).mp4")
    }

    private static func записатьВидео(_ рисовальщик: РисовальщикРолика,
                                      обновить: @escaping @MainActor @Sendable (Double, ЭтапЗаписиРолика) -> Void) async throws -> URL {
        let ширина = ТаймлайнРолика.ширина
        let высота = ТаймлайнРолика.высота
        let кадровВСекунду = ТаймлайнРолика.кадровВСекунду
        let адрес = новыйАдрес()
        let писатель = try AVAssetWriter(outputURL: адрес, fileType: .mp4)
        let сжатие: [String: Any] = [
            AVVideoAverageBitRateKey: ТаймлайнРолика.битрейт,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: 60,
            AVVideoExpectedSourceFrameRateKey: Int(кадровВСекунду)
        ]
        let настройки: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: ширина,
            AVVideoHeightKey: высота,
            AVVideoCompressionPropertiesKey: сжатие
        ]
        let вход = AVAssetWriterInput(mediaType: .video, outputSettings: настройки)
        вход.expectsMediaDataInRealTime = false
        let атрибуты: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: ширина,
            kCVPixelBufferHeightKey as String: высота,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        let адаптер = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: вход, sourcePixelBufferAttributes: атрибуты)
        guard писатель.canAdd(вход) else { throw Сбой.запись }
        писатель.add(вход)
        guard писатель.startWriting() else { throw Сбой.запись }
        писатель.startSession(atSourceTime: .zero)

        let пространство = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let раскладка = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let кадров = Int((рисовальщик.ход.всего * Double(кадровВСекунду)).rounded())
        do {
            for номер in 0..<кадров {
                try Task.checkCancellation()
                var ждали = 0
                while !вход.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 3_000_000)
                    ждали += 1
                    if ждали > 4000 { throw Сбой.запись }
                }
                guard let пул = адаптер.pixelBufferPool else { throw Сбой.запись }
                var сырой: CVPixelBuffer? = nil
                CVPixelBufferPoolCreatePixelBuffer(nil, пул, &сырой)
                guard let буфер = сырой else { throw Сбой.запись }
                CVPixelBufferLockBaseAddress(буфер, [])
                if let контекст = CGContext(data: CVPixelBufferGetBaseAddress(буфер), width: ширина, height: высота,
                                            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(буфер),
                                            space: пространство, bitmapInfo: раскладка) {
                    let время = Double(номер) / Double(кадровВСекунду)
                    рисовальщик.нарисовать(в: контекст, время: время, масштаб: 1)
                }
                CVPixelBufferUnlockBaseAddress(буфер, [])
                let момент = CMTime(value: CMTimeValue(номер), timescale: кадровВСекунду)
                guard адаптер.append(буфер, withPresentationTime: момент) else { throw Сбой.запись }
                if номер % 4 == 0 {
                    await обновить(0.02 + Double(номер) / Double(max(1, кадров)) * 0.9, .рендер)
                }
            }
        } catch {
            писатель.cancelWriting()
            try? FileManager.default.removeItem(at: адрес)
            throw error
        }
        вход.markAsFinished()
        await писатель.finishWriting()
        guard писатель.status == .completed else {
            try? FileManager.default.removeItem(at: адрес)
            throw Сбой.запись
        }
        return адрес
    }

    /// Видео и звук — в один .mp4 без перекодирования (Passthrough). nil — не вышло.
    private static func склеить(_ видео: URL, _ звук: URL) async -> URL? {
        let композиция = AVMutableComposition()
        let активВидео = AVURLAsset(url: видео)
        let активЗвука = AVURLAsset(url: звук)
        do {
            guard let дорожкаВидео = try await активВидео.loadTracks(withMediaType: .video).first,
                  let дорожкаЗвука = try await активЗвука.loadTracks(withMediaType: .audio).first,
                  let цельВидео = композиция.addMutableTrack(withMediaType: .video,
                                                             preferredTrackID: kCMPersistentTrackID_Invalid),
                  let цельЗвука = композиция.addMutableTrack(withMediaType: .audio,
                                                             preferredTrackID: kCMPersistentTrackID_Invalid)
            else { return nil }
            let длительность = try await активВидео.load(.duration)
            let длительностьЗвука = try await активЗвука.load(.duration)
            try цельВидео.insertTimeRange(CMTimeRange(start: .zero, duration: длительность), of: дорожкаВидео, at: .zero)
            let хватит = CMTimeMinimum(длительность, длительностьЗвука)
            try цельЗвука.insertTimeRange(CMTimeRange(start: .zero, duration: хватит), of: дорожкаЗвука, at: .zero)
        } catch {
            return nil
        }
        guard let сессия = AVAssetExportSession(asset: композиция, presetName: AVAssetExportPresetPassthrough) else {
            return nil
        }
        let итог = новыйАдрес()
        сессия.outputURL = итог
        сессия.outputFileType = .mp4
        сессия.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (продолжение: CheckedContinuation<Void, Never>) in
            сессия.exportAsynchronously {
                продолжение.resume()
            }
        }
        guard сессия.status == .completed else {
            try? FileManager.default.removeItem(at: итог)
            return nil
        }
        return итог
    }
}

import AVFoundation

/**
 «Фирменный звук Kliko» студии роликов сайта. Готовых треков-файлов у сайта нет: звук собирается на месте
 (OfflineAudioContext, 48 кГц, стерео) из тех же нот, что и здесь:
   · заставка — «динь-дон» ми (659,25 Гц) и си (987,77 Гц) треугольной волной и тихий обертон синусом;
   · смена каждого фото — «вжух» (шум сквозь полосовой фильтр, частота растёт 500 → 2400 Гц) и короткий звон 1318,5 Гц;
   · концовка — «вжух» пошире (400 → 3600 Гц) и мажорное арпеджио ми – соль-диез – си с обертоном.
 Громкость общая 0,9 и мягкий срез выше 9 кГц — как у сайта. Здесь ещё множитель громкости из студии (0…1).

 Пишется AAC 128 кбит/с в .m4a (AVAudioFile), потом кладётся дорожкой в ролик.
 */
enum ЗвукРолика {
    static let частота: Double = 48_000

    /// Файл звука .m4a на весь ролик. nil — не получилось (ролик тогда без звука, как у сайта).
    static func записать(_ ход: ТаймлайнРолика, громкость: Double) -> URL? {
        let выборки = синтез(ход, громкость: громкость)
        let адрес = FileManager.default.temporaryDirectory.appendingPathComponent("kliko-snd-\(UUID().uuidString).m4a")
        let ок = сохранить(выборки, в: адрес)
        if !ок { try? FileManager.default.removeItem(at: адрес) }
        return ок ? адрес : nil
    }

    /// Файл закрывается, когда AVAudioFile уходит из памяти, — поэтому запись в своей функции.
    private static func сохранить(_ выборки: [Float], в адрес: URL) -> Bool {
        let настройки: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: частота,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        guard let файл = try? AVAudioFile(forWriting: адрес, settings: настройки, commonFormat: .pcmFormatFloat32,
                                          interleaved: false) else { return false }
        let формат = файл.processingFormat
        let порция = 8192
        var начало = 0
        while начало < выборки.count {
            let сколько = min(порция, выборки.count - начало)
            guard let буфер = AVAudioPCMBuffer(pcmFormat: формат, frameCapacity: AVAudioFrameCount(сколько)),
                  let каналы = буфер.floatChannelData else { return false }
            буфер.frameLength = AVAudioFrameCount(сколько)
            let всегоКаналов = Int(формат.channelCount)
            for канал in 0..<всегоКаналов {
                let цель = каналы[канал]
                for i in 0..<сколько { цель[i] = выборки[начало + i] }
            }
            do {
                try файл.write(from: буфер)
            } catch {
                return false
            }
            начало += сколько
        }
        return true
    }

    // MARK: Синтез

    /// Моно-выборки на весь ролик (оба канала одинаковые — у сайта тоже).
    static func синтез(_ ход: ТаймлайнРолика, громкость: Double) -> [Float] {
        let длина = Int((ход.всего * частота).rounded(.up))
        var звук = [Float](repeating: 0, count: max(1, длина))
        func нота(_ t: Double, _ f: Double, _ d: Double, _ пик: Double, синус: Bool = false) {
            тон(&звук, начало: t, частота: f, длительность: d, пик: пик, синус: синус)
        }
        func вжух(_ t: Double, _ d: Double, _ f0: Double, _ f1: Double, _ пик: Double) {
            шум(&звук, начало: t, длительность: d, от: f0, до: f1, пик: пик)
        }
        нота(0.06, 659.25, 0.3, 0.5)
        нота(0.2, 987.77, 0.42, 0.5)
        нота(0.2, 1975.5, 0.18, 0.12, синус: true)
        if ход.фото > 1 {
            for s in 1..<ход.фото {
                let d = ход.заставка + Double(s) * ход.наФото
                вжух(d - 0.16, 0.42, 500, 2400, 0.2)
                нота(d + 0.02, 1318.5, 0.12, 0.1, синус: true)
            }
        }
        let u = ход.заставка + Double(ход.фото) * ход.наФото
        вжух(u - 0.1, 0.7, 400, 3600, 0.24)
        нота(u + 0.15, 659.25, 1.1, 0.42)
        нота(u + 0.3, 830.61, 1.1, 0.4)
        нота(u + 0.45, 987.77, 1.4, 0.42)
        нота(u + 0.6, 1975.5, 0.9, 0.14, синус: true)

        /* Общая громкость и срез 9 кГц (lowpass-биквад). */
        let общая = Float(0.9 * max(0, min(1, громкость)))
        var срез = Биквад.низкие(9000, q: 0.7071, частота: частота)
        for i in 0..<звук.count {
            let v = срез.шаг(звук[i] * общая)
            звук[i] = max(-1, min(1, v))
        }
        return звук
    }

    /// Огибающая сайта: 0,0001 → пик за 12 мс (экспонента) → 0,0001 к концу.
    private static func огибающая(_ t: Double, _ длительность: Double, _ пик: Double, атака: Double) -> Double {
        let тихо = 0.0001
        if t <= 0 { return тихо }
        if t < атака { return тихо * pow(пик / тихо, t / атака) }
        if t < длительность {
            let доля = (t - атака) / max(0.0001, длительность - атака)
            return пик * pow(тихо / пик, доля)
        }
        return тихо
    }

    private static func тон(_ звук: inout [Float], начало: Double, частота f: Double, длительность: Double, пик: Double,
                            синус: Bool) {
        let первая = max(0, Int(начало * частота))
        let последняя = min(звук.count, Int((начало + длительность + 0.05) * частота))
        guard первая < последняя else { return }
        for i in первая..<последняя {
            let t = Double(i) / частота - начало
            let фаза = (f * t).truncatingRemainder(dividingBy: 1)
            let волна = синус ? sin(2 * Double.pi * фаза) : 4 * abs(фаза - 0.5) - 1
            звук[i] += Float(волна * огибающая(t, длительность, пик, атака: 0.012))
        }
    }

    /// Шум сквозь полосовой фильтр (Q 1,1) с частотой, растущей по экспоненте; огибающая — пик на 35 % длительности.
    private static func шум(_ звук: inout [Float], начало: Double, длительность: Double, от f0: Double, до f1: Double,
                            пик: Double) {
        let первая = max(0, Int(начало * частота))
        let последняя = min(звук.count, Int((начало + длительность + 0.05) * частота))
        guard первая < последняя else { return }
        var полоса = Биквад.полоса(f0, q: 1.1, частота: частота)
        var зерно: UInt32 = 0x9E3779B9
        for i in первая..<последняя {
            let t = Double(i) / частота - начало
            if (i - первая) % 32 == 0 {
                let доля = max(0, min(1, t / длительность))
                полоса = полоса.сНастройкой(Биквад.полоса(f0 * pow(f1 / f0, доля), q: 1.1, частота: частота))
            }
            зерно = зерно &* 1_664_525 &+ 1_013_904_223
            let белый = Double(зерно >> 8) / Double(1 << 24) * 2 - 1
            let фильтр = полоса.шаг(Float(белый))
            звук[i] += фильтр * Float(огибающая(t, длительность, пик, атака: 0.35 * длительность))
        }
    }
}

/// Биквад RBJ (как BiquadFilterNode): коэффициенты и память двух прошлых отсчётов.
private struct Биквад {
    var b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    var x1: Double = 0, x2: Double = 0, y1: Double = 0, y2: Double = 0

    static func низкие(_ f: Double, q: Double, частота: Double) -> Биквад {
        let w = 2 * Double.pi * f / частота
        let альфа = sin(w) / (2 * q)
        let c = cos(w)
        let a0 = 1 + альфа
        return Биквад(b0: (1 - c) / 2 / a0, b1: (1 - c) / a0, b2: (1 - c) / 2 / a0, a1: -2 * c / a0, a2: (1 - альфа) / a0)
    }

    static func полоса(_ f: Double, q: Double, частота: Double) -> Биквад {
        let w = 2 * Double.pi * min(f, частота * 0.45) / частота
        let альфа = sin(w) / (2 * q)
        let a0 = 1 + альфа
        return Биквад(b0: альфа / a0, b1: 0, b2: -альфа / a0, a1: -2 * cos(w) / a0, a2: (1 - альфа) / a0)
    }

    /// Новые коэффициенты с прежней памятью — частота меняется без щелчков.
    func сНастройкой(_ другой: Биквад) -> Биквад {
        var итог = другой
        итог.x1 = x1
        итог.x2 = x2
        итог.y1 = y1
        итог.y2 = y2
        return итог
    }

    mutating func шаг(_ x: Float) -> Float {
        let xd = Double(x)
        let y = b0 * xd + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = xd
        y2 = y1
        y1 = y
        return Float(y)
    }
}

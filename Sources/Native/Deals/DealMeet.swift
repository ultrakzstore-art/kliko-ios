import AVFoundation
import SwiftUI
import UIKit
import Vision
import VisionKit

/**
 ЛИЧНАЯ ВСТРЕЧА С QR — СВОЙ БЛОК (hovMeetPanel, hovQRShow, hovQRDraw, hovQRSchedule, hovQRLink сайта; карта §9.8,
 CAB @568187–573700).

 Этапы «Встретились · Продавец показал код · Готово», место встречи с «Построить маршрут к месту встречи».
   · Продавец: «Показать код передачи» → chat.php?action=meet_qr {deal_id} → meet{qr, qr_left}. QR ведёт на
     /kz/<язык>/cabinet.php?meet=<qr>, под ним «Код обновится через N с» (истёк — «Код истёк — обновляем…»); код
     запрашивается заново за 10 с до конца, пока он на экране (ПередачаСделкиМодель). «Отправить ссылку покупателю» —
     системный лист «Поделиться» (ссылка живёт минуту, как и код).
   · Покупатель: «Ждём, пока продавец откроет код передачи…» → «Продавец показывает код — наведите камеру…»;
     «Сканировать код» — своя камера (VisionKit): QR → токен → «Вы точно получили товар?» → meet_scan {token}, тот же
     запрос, что у ссылки ?meet= (ЗаданияДенегСделок). locked — «Слишком много неверных попыток. Дальше — только через
     спор.»
 Пока код не показан (qr_on и shown_at пусты), способ можно сменить (handover_cancel); покупателю, если встречу выбрал
 продавец, — «Способ выбрал продавец. Решаете вы…».
 */
struct БлокВстречи: View {
    let сделка: Сделка
    let встреча: ВстречаСделки
    @ObservedObject var передача: ПередачаСделкиМодель
    let действие: (НажатиеСделки) -> Void

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    private var я: Bool { встреча.роль.isEmpty ? сделка.продавец : встреча.роль == "seller" }
    /// done — 3, код открыт — 2, иначе 1.
    private var этап: Int { встреча.статус == "done" ? 3 : (встреча.кодОткрыт ? 2 : 1) }
    /// c сайта: код ещё ни разу не показывали — способ можно сменить.
    private var вНачале: Bool { !встреча.кодОткрыт && !встреча.показывали }

    var body: some View {
        БлокСделки {
            ЗаголовокБлокаСделки(текст: СделкиText.т("meet_t"), символ: "person.2")
            ЭтапыПередачи(подписи: [т("meet_s1"), т("meet_s2"), т("meet_s3")], этап: этап)
            место
            содержимое
        }
    }

    /// «Место: …» и маршрут к месту встречи (hovRouteBtns).
    @ViewBuilder
    private var место: some View {
        let адрес = встреча.адресМеста
        if !адрес.isEmpty || встреча.точкаМеста != nil {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(Theme.зелёный)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                (Text(т("meet_place") + " ") + Text(адрес.isEmpty ? т("meet_place_pin") : адрес).bold())
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
            }
            КнопкаСделки(СделкиText.т("hnd_route") + " " + т("meet_to_place"), вид: .вторая,
                         символ: "point.topleft.down.to.point.bottomright.curvepath") {
                действие(.маршрут(адрес: адрес, точка: встреча.точкаМеста))
            }
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        if встреча.статус == "done" {
            ЗаметкаСделки(Text(т("meet_done")), вид: .хорошо, символ: "checkmark.circle")
        } else if я {
            продавцу
        } else {
            покупателю
        }
    }

    // MARK: - Продавец

    /// t.qr сайта: код из ответа meet_qr (своя модель) или из сделки.
    private var кодНаЭкране: String? {
        if let свой = передача.кодВстречи?.код { return свой }
        return встреча.код.isEmpty ? nil : встреча.код
    }

    @ViewBuilder
    private var продавцу: some View {
        if let код = кодНаЭкране {
            КодВстречиПродавца(код: код, встреча: встреча, передача: передача)
            КнопкаСделки(т("meet_link"), вид: .вторая, символ: "link") { отправитьСсылку(код) }
            ПодписьСделки(т("meet_link_s"))
        } else {
            ПодписьСделки(т("meet_intro"))
            КнопкаСделки(т("meet_open"), вид: .главная, символ: "qrcode", доступна: !передача.идёт) {
                передача.показатьКод()
            }
        }
        КнопкаСменыСпособа(продавец: true,
                           можно: вНачале && КнопкаСменыСпособа.разрешено(роль: "seller", выбрал: встреча.начал),
                           показатьЗамок: вНачале, действие: действие)
    }

    /// hovQRLink: «Подтвердите получение по сделке: <ссылка>» — системный лист «Поделиться».
    @MainActor
    private func отправитьСсылку(_ код: String) {
        let адрес = КодВстречиПродавца.адрес(код)
        guard !адрес.isEmpty else { return }
        ПоделитьсяСайта.системныйЛист([т("meet_link_txt") + адрес])
    }

    // MARK: - Покупатель

    @ViewBuilder
    private var покупателю: some View {
        if встреча.заперта {
            ЗаметкаСделки(Text(т("meet_locked")), вид: .плохо, символ: "lock")
        } else {
            ЗаметкаСделки(Text(т(встреча.кодОткрыт ? "meet_ready" : "meet_wait")),
                          вид: встреча.кодОткрыт ? .хорошо : .предупреждение,
                          символ: встреча.кодОткрыт ? "checkmark.circle" : "hourglass")
            /* Своя камера: QR с экрана продавца → meet_scan {token} после «Вы точно получили товар?». */
            КнопкаСделки(т("meet_scan"), вид: встреча.кодОткрыт ? .главная : .вторая, символ: "qrcode.viewfinder",
                         доступна: !передача.идёт) {
                передача.лист = .сканер(встреча: true)
            }
            ПодписьСделки(т("meet_scan_s"))
            ПодписьСделки(т("meet_check"))
            КтоВыбралСпособ(роль: "buyer", выбрал: встреча.начал, вНачале: вНачале)
            КнопкаСменыСпособа(продавец: false, можно: вНачале, показатьЗамок: false, действие: действие)
        }
    }
}

/// .hov-qr сайта: белая карточка — QR, «Покажите экран покупателю…», отсчёт до обновления кода.
struct КодВстречиПродавца: View {
    let код: String
    let встреча: ВстречаСделки
    @ObservedObject var передача: ПередачаСделкиМодель

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    /// hovQRDraw: /kz/<язык>/cabinet.php?meet=<qr>.
    static func адрес(_ код: String) -> String {
        Config.страницаСайта("cabinet.php?meet=" + СделкиAPI.вАдрес(код))?.absoluteString ?? ""
    }

    var body: some View {
        VStack(spacing: 10) {
            КартинкаQRПередачи(текст: Self.адрес(код), подпись: т("meet_qr_a11y"))
                .frame(maxWidth: 230)
            Text(т("meet_show"))
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(Color(uiColor: Theme.hex(0x5B6B62)))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 1)) { контекст in
                Text(осталось(контекст.date))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color(uiColor: Theme.hex(0x8A9A91)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
        .onAppear { передача.кодНаЭкранеПоявился(встреча) }
        .onDisappear { передача.остановитьКод() }
    }

    /// «Код обновится через N с»; вышло время — «Код истёк — обновляем…».
    private func осталось(_ сейчас: Date) -> String {
        let сек: Int
        if let до = передача.кодВстречи?.до {
            сек = Int(до.timeIntervalSince(сейчас).rounded(.down))
        } else {
            сек = встреча.кодСек > 0 ? встреча.кодСек : 60
        }
        if сек <= 0 { return т("meet_stale") }
        return ПередачаText.т("meet_left", n: String(сек))
    }
}

// MARK: - Своя камера для QR передачи (VisionKit)

/**
 Сканер QR встречи и листка посылки. Камера читает только QR; прочитан адрес kliko.kz с ?meet= (или ?parcel=) —
 лист уезжает, дальше вопрос «Вы точно получили товар?». Чужой код — подсказка внизу, камера читает дальше. Камеры нет
 или доступ не дан — пояснение: системная камера откроет ту же ссылку в приложении.
 */
struct СканерКодаСделки: View {
    let встреча: Bool
    @ObservedObject var передача: ПередачаСделкиМодель

    @State private var проверили = false
    @State private var прочитан = false
    @State private var подсказка: String? = nil

    /// Явный init: сканер открывает слой карточки из другого файла.
    init(встреча: Bool, передача: ПередачаСделкиМодель) {
        self.встреча = встреча
        self.передача = передача
    }

    private func т(_ ключ: String) -> String { ПередачаText.т(ключ) }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()
                if проверили {
                    if КамераQRСделки.можно {
                        КамераQRСделки(найден: { прочитать($0) })
                            .ignoresSafeArea()
                    } else {
                        нетКамеры
                    }
                } else {
                    SiteSpinner()
                }
                if проверили && КамераQRСделки.можно {
                    Text(подсказка ?? т("scan_h"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.62), in: RoundedRectangle(cornerRadius: Theme.Радиус.ms,
                                                                                  style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                }
            }
            .navigationTitle(т("scan_t"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(СделкиText.т("close")) { передача.лист = nil }
                }
            }
        }
        .tint(Theme.акцент)
        .task {
            /* Доступ к камере спрашиваем здесь: без него VisionKit считает сканер недоступным. */
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            проверили = true
        }
    }

    private var нетКамеры: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera")
                .font(.system(size: 34))
                .foregroundStyle(Color.white.opacity(0.8))
                .accessibilityHidden(true)
            Text(т("scan_na"))
                .font(.system(size: 15))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            КнопкаСделки(СделкиText.т("close"), вид: .вторая) { передача.лист = nil }
        }
        .padding(24)
    }

    private func прочитать(_ текст: String) {
        guard !прочитан else { return }
        if let токен = ПередачаСделкиМодель.токен(из: текст, встреча: встреча) {
            прочитан = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            передача.отсканирован(токен: токен, встреча: встреча)
        } else {
            подсказка = т(встреча ? "scan_wrong" : "scan_wrong_prc")
        }
    }
}

/// DataScannerViewController (iOS 16+): только QR, одна метка, подсветка найденного.
struct КамераQRСделки: UIViewControllerRepresentable {
    let найден: (String) -> Void

    /// Устройство умеет и доступ к камере дан.
    @MainActor
    static var можно: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let сканер = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                               qualityLevel: .balanced,
                                               recognizesMultipleItems: false,
                                               isHighFrameRateTrackingEnabled: false,
                                               isPinchToZoomEnabled: true,
                                               isGuidanceEnabled: true,
                                               isHighlightingEnabled: true)
        сканер.delegate = context.coordinator
        return сканер
    }

    func updateUIViewController(_ сканер: DataScannerViewController, context: Context) {
        context.coordinator.найден = найден
        guard !сканер.isScanning else { return }
        /* Экран ещё может въезжать: запуск — на следующем обороте, повторный вызов безвреден. */
        Task { @MainActor in
            if !сканер.isScanning { try? сканер.startScanning() }
        }
    }

    static func dismantleUIViewController(_ сканер: DataScannerViewController, coordinator: Координатор) {
        сканер.stopScanning()
    }

    func makeCoordinator() -> Координатор {
        Координатор(найден: найден)
    }

    @MainActor
    final class Координатор: NSObject, DataScannerViewControllerDelegate {
        var найден: (String) -> Void

        init(найден: @escaping (String) -> Void) {
            self.найден = найден
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for вещь in addedItems {
                if case .barcode(let код) = вещь, let текст = код.payloadStringValue {
                    найден(текст)
                    return
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case .barcode(let код) = item, let текст = код.payloadStringValue {
                найден(текст)
            }
        }
    }
}

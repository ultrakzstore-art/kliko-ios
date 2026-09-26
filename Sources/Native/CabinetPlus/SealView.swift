import SwiftUI
import UIKit
import PhotosUI

/**
 «ПЕЧАТЬ И ПОДПИСЬ» — СВОИМ ЭКРАНОМ (sealPick / sealDraw / sealSendFile / sealSave модуля js/cabinet-business.min.js,
 блок .cmp-seal страницы кабинета; владелец: «кабинет полностью SwiftUI»).

 Три картинки компании — печать, подпись руководителя, подпись бухгалтера (+ ФИО бухгалтера) и «Ставить печать и подпись
 в документы» (seal_auto). Текущие значения — из const CAB_COMPANY страницы кабинета (stamp, sign, sign_acc — data URL
 PNG, accountant, seal_auto).
   · картинка — POST cabinet.php?action=save_seal multipart {csrf, kind: stamp | sign | sign_acc, auto, b64 (PNG без
     «data:image/png;base64,»)}; печать — не больше 600×600, подпись — 900×300 (_sealShrink), файл до ~380 КБ;
   · «Убрать», ФИО бухгалтера, «Ставить в документы» — POST save_seal JSON {csrf, stamp? | sign? | sign_acc?,
     accountant, auto};
   · ответ need_otp — подтверждение eGov (otpStepOpen «seal», ссылка «company»): своё окно ОкноEGov, затем тот же запрос
     ещё раз, как колбэк сайта.
 «Расписаться» — своё полотно: подпись пальцем без фона, как .seal-pad сайта (линия 2,2 пт, #0f172a).
 */
@MainActor
final class ПечатьМодель: ObservableObject {
    enum Состояние: Equatable { case идёт, готово, нуженВход, ошибка(String) }

    @Published private(set) var состояние: Состояние = .идёт
    @Published private(set) var картинки: [String: UIImage] = [:]
    @Published var бухгалтер = ""
    @Published var вДокументы = false
    @Published private(set) var занято = false
    @Published var eGov: ЗапросEGov? = nil
    @Published private(set) var плашка: String? = nil
    private var повторить: (() -> Void)? = nil
    private var скрыть: Task<Void, Never>? = nil

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    func показать(_ текст: String) {
        withAnimation(.easeOut(duration: 0.2)) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        скрыть?.cancel()
        скрыть = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self?.плашка = nil }
        }
    }

    private static func картинка(_ dataURL: String) -> UIImage? {
        guard let запятая = dataURL.firstIndex(of: ",") else { return nil }
        let base64 = String(dataURL[dataURL.index(after: запятая)...])
        guard let данные = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) else { return nil }
        return UIImage(data: данные)
    }

    func загрузить() async {
        do {
            let страница = try await КабинетСайта.страницаКабинета(ждать: true)
            if страница.состояние.вошёл == false {
                состояние = .нуженВход
                return
            }
            let к = РазборJSON.после("const CAB_COMPANY", в: Array(страница.html.utf8))
            var найдено: [String: UIImage] = [:]
            for вид in ["stamp", "sign", "sign_acc"] {
                if let текст = к?[вид]?.текст, !текст.isEmpty, let картинка = Self.картинка(текст) {
                    найдено[вид] = картинка
                }
            }
            картинки = найдено
            бухгалтер = к?["accountant"]?.текст ?? ""
            вДокументы = к?["seal_auto"]?.да ?? false
            состояние = .готово
        } catch {
            if состояние != .готово { состояние = .ошибка(т("no_conn")) }
        }
    }

    /// _sealDone: ok — «сохранены»; need_otp — eGov и повтор; иначе текст сервера.
    private func итог(_ j: [String: Any]?, повтор: @escaping () -> Void) -> Bool {
        guard let j else {
            показать(т("err_generic"))
            return false
        }
        if МоиОбъявленияAPI.да(j["ok"]) {
            показать(т("seal_saved"))
            return true
        }
        if МоиОбъявленияAPI.да(j["need_otp"]) {
            повторить = повтор
            let назначение = МоиОбъявленияAPI.строка(j["purpose"])
            eGov = ЗапросEGov(назначение: назначение.isEmpty ? "seal" : назначение, ссылка: "company",
                              заголовок: т("seal_otp_t"), подсказка: т("seal_otp_h"), после: .оплатить)
            return false
        }
        показать(ЗапросыКабинета.текстОшибки(j))
        return false
    }

    /// eGov пройден — тот же запрос ещё раз.
    func послеEGov() {
        eGov = nil
        guard let повтор = повторить else { return }
        повторить = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            повтор()
        }
    }

    /// sealSendFile: картинка вида stamp | sign | sign_acc.
    func отправить(_ картинка: UIImage, вид: String) {
        let большая = вид == "stamp" ? CGSize(width: 600, height: 600) : CGSize(width: 900, height: 300)
        guard let png = Self.уменьшить(картинка, до: большая) else {
            показать(т("seal_bad"))
            return
        }
        guard !занято else { return }
        занято = true
        if !вДокументы { вДокументы = true }
        let авто = вДокументы
        Task { @MainActor in
            defer { self.занято = false }
            do {
                let j = try await ИмпортAPI.форма("cabinet.php?action=save_seal",
                                                  поля: ["kind": вид, "auto": авто ? "1" : "0",
                                                         "b64": png.base64EncodedString()])
                if self.итог(j, повтор: { [weak self] in self?.отправить(картинка, вид: вид) }) {
                    self.картинки[вид] = UIImage(data: png)
                }
            } catch {
                self.показать(self.т("no_conn"))
            }
        }
    }

    /// sealSave: «Убрать» (вид), ФИО бухгалтера и «Ставить в документы».
    func сохранить(убрать вид: String? = nil) {
        guard !занято else { return }
        занято = true
        var тело: [String: Any] = ["accountant": бухгалтер, "auto": вДокументы ? 1 : 0]
        if let вид { тело[вид] = "" }
        Task { @MainActor in
            defer { self.занято = false }
            do {
                let j = try await МоиОбъявленияAPI.отправить("cabinet.php?action=save_seal", тело: тело)
                if self.итог(j, повтор: { [weak self] in self?.сохранить(убрать: вид) }), let вид {
                    self.картинки[вид] = nil
                }
            } catch {
                self.показать(self.т("no_conn"))
            }
        }
    }

    /// _sealShrink: вписать в рамку, PNG; больше ~380 КБ — ещё раз на 70 %, до трёх раз.
    private static func уменьшить(_ картинка: UIImage, до рамки: CGSize) -> Data? {
        var рамка = рамки
        for _ in 0..<4 {
            let ш = max(картинка.size.width, 1)
            let в = max(картинка.size.height, 1)
            let к = min(1, рамка.width / ш, рамка.height / в)
            let размер = CGSize(width: max(1, (ш * к).rounded()), height: max(1, (в * к).rounded()))
            let формат = UIGraphicsImageRendererFormat.default()
            формат.scale = 1
            формат.opaque = false
            let готовая = UIGraphicsImageRenderer(size: размер, format: формат).image { _ in
                картинка.draw(in: CGRect(origin: .zero, size: размер))
            }
            guard let png = готовая.pngData() else { return nil }
            if png.count <= 389_120 { return png }
            рамка = CGSize(width: (рамка.width * 0.7).rounded(), height: (рамка.height * 0.7).rounded())
        }
        return nil
    }
}

/// Обёртка запроса eGov для .sheet(item:).
private struct ОкноEGovПечати: Identifiable {
    let запрос: ЗапросEGov
    var id: String { запрос.назначение + ":" + запрос.ссылка }
}

/// Вид для полотна подписи (.sheet(item:)).
private struct ПолотноДля: Identifiable {
    let вид: String
    var id: String { вид }
}

struct ЭкранПечатиИПодписи: View {
    let открыть: (URL) -> Void

    @StateObject private var модель = ПечатьМодель()
    @State private var полотно: ПолотноДля? = nil
    @State private var выборФото: PhotosPickerItem? = nil
    @State private var видФото = "stamp"
    @State private var выборОткрыт = false
    @State private var входОткрыт = false

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var body: some View {
        Group {
            switch модель.состояние {
            case .идёт:
                ЗагрузкаБизнеса()
            case .нуженВход:
                ПустоСайта(значок: "person.crop.circle", заголовок: CabinetText.т("signed_out"),
                           кнопка: CabinetText.т("login"), действие: { входОткрыт = true })
            case .ошибка(let текст):
                ПустоСайта(значок: "wifi.exclamationmark", заголовок: текст, кнопка: т("retry"),
                           действие: { Task { await модель.загрузить() } })
            case .готово:
                содержимое
            }
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(т("seal_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await модель.загрузить() }
        .overlay(alignment: .bottom) {
            if let текст = модель.плашка { ПлашкаКошелька(текст: текст) }
        }
        .photosPicker(isPresented: $выборОткрыт, selection: $выборФото, matching: .images)
        .onChange(of: выборФото) { _, элемент in
            guard let элемент else { return }
            let вид = видФото
            Task { @MainActor in
                defer { выборФото = nil }
                guard let данные = try? await элемент.loadTransferable(type: Data.self),
                      let картинка = UIImage(data: данные) else {
                    модель.показать(т("seal_bad"))
                    return
                }
                модель.отправить(картинка, вид: вид)
            }
        }
        .sheet(item: $полотно) { п in
            ПолотноПодписи(заголовок: т(п.вид == "sign_acc" ? "seal_draw_acc" : "seal_draw_t")) { картинка in
                полотно = nil
                модель.отправить(картинка, вид: п.вид)
            } закрыть: {
                полотно = nil
            }
        }
        .sheet(item: Binding(get: { модель.eGov.map { ОкноEGovПечати(запрос: $0) } },
                             set: { if $0 == nil { модель.eGov = nil } })) { окно in
            ОкноEGov(запрос: окно.запрос, готово: { модель.послеEGov() }, закрыть: { модель.eGov = nil })
        }
        .sheet(isPresented: $входОткрыт) {
            ЭкранВхода(eGovВключён: true, открыть: { ПереходыКабинета.открыть($0) }, вошли: {
                Task { await модель.загрузить() }
            })
        }
    }

    private var содержимое: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ЗаметкаБизнеса(т("seal_use_h"), тон: .инфо, значок: "signature")
                блок("stamp", заголовок: т("seal_stamp"), подсказка: т("seal_stamp_h"), расписаться: false)
                блок("sign", заголовок: т("seal_sign"), подсказка: т("seal_sign_h"), расписаться: true)
                блок("sign_acc", заголовок: т("seal_sign_acc"), подсказка: nil, расписаться: true)
                КарточкаБизнеса(т("seal_acc_fio"), значок: "person.text.rectangle") {
                    ПолеРаздела(подпись: т("seal_acc_fio"), текст: $модель.бухгалтер, подсказка: "ФИО")
                    КнопкаРаздела(подпись: т("save"), значок: "checkmark", занято: модель.занято) { модель.сохранить() }
                }
                КарточкаБизнеса(т("seal_auto"), значок: "doc.badge.gearshape") {
                    Toggle(т("seal_auto"), isOn: Binding(get: { модель.вДокументы }, set: { новое in
                        модель.вДокументы = новое
                        модель.сохранить()
                    }))
                    .tint(Theme.акцент)
                    .disabled(модель.занято)
                    Text(т("seal_auto_h"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func блок(_ вид: String, заголовок: String, подсказка: String?, расписаться: Bool) -> some View {
        КарточкаБизнеса(заголовок, значок: вид == "stamp" ? "seal" : "signature") {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .fill(Color.white)
                if let картинка = модель.картинки[вид] {
                    Image(uiImage: картинка)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .accessibilityLabel(заголовок)
                } else {
                    Text(т("seal_empty"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.45))
                }
            }
            .frame(height: вид == "stamp" ? 150 : 100)
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
            HStack(spacing: 6) {
                if расписаться {
                    КнопкаРаздела(подпись: т("seal_draw"), значок: "scribble", вид: .главная, занято: модель.занято) {
                        полотно = ПолотноДля(вид: вид)
                    }
                }
                КнопкаРаздела(подпись: т("seal_upload"), значок: "photo", занято: модель.занято) {
                    видФото = вид
                    выборОткрыт = true
                }
                if модель.картинки[вид] != nil {
                    КнопкаРаздела(подпись: т("seal_clear"), значок: "xmark", вид: .плохо) {
                        модель.сохранить(убрать: вид)
                    }
                }
            }
            if let подсказка {
                Text(подсказка)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Полотно подписи (.seal-pad)

private struct ПолотноПодписи: View {
    let заголовок: String
    let готово: (UIImage) -> Void
    let закрыть: () -> Void

    @State private var штрихи: [[CGPoint]] = []
    @State private var размер: CGSize = .zero
    @State private var пусто = false

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { гео in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .fill(Color.white)
                        Rectangle()
                            .fill(Color(white: 0.8))
                            .frame(height: 1)
                            .padding(.horizontal, 24)
                            .padding(.bottom, гео.size.height * 0.28)
                        ПутьПодписи(штрихи: штрихи)
                            .stroke(Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255),
                                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { ж in
                                if ж.translation == .zero || штрихи.isEmpty {
                                    штрихи.append([ж.location])
                                } else {
                                    штрихи[штрихи.count - 1].append(ж.location)
                                }
                            }
                            .onEnded { _ in штрихи.append([]) }
                    )
                    .onAppear { размер = гео.size }
                    .onChange(of: гео.size) { _, новый in размер = новый }
                }
                .frame(height: 220)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                }
                .accessibilityLabel(заголовок)
                Text(пусто ? т("seal_draw_empty") : т("seal_draw_h"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(пусто ? КраскаОбъявлений.плохоТекст : Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    КнопкаРаздела(подпись: т("seal_draw_ok"), значок: "checkmark", вид: .главная) { принять() }
                    КнопкаРаздела(подпись: т("seal_draw_clr"), значок: "eraser") {
                        штрихи = []
                        пусто = false
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(заголовок)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CabinetText.т("cancel")) { закрыть() }
                }
            }
        }
        .interactiveDismissDisabled()
    }

    /// sealDrawDone: пустое полотно — «Холст пустой»; иначе PNG без фона.
    private func принять() {
        let точек = штрихи.reduce(0) { $0 + $1.count }
        guard точек > 1, размер.width > 0, размер.height > 0 else {
            пусто = true
            return
        }
        let вид = ПутьПодписи(штрихи: штрихи)
            .stroke(Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .frame(width: размер.width, height: размер.height)
        let рендер = ImageRenderer(content: вид)
        рендер.scale = 2
        рендер.isOpaque = false
        guard let картинка = рендер.uiImage else {
            пусто = true
            return
        }
        готово(картинка)
    }
}

private struct ПутьПодписи: Shape {
    let штрихи: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var путь = Path()
        for штрих in штрихи {
            guard let первая = штрих.first else { continue }
            путь.move(to: первая)
            if штрих.count == 1 {
                путь.addLine(to: CGPoint(x: первая.x + 0.5, y: первая.y + 0.5))
            }
            for точка in штрих.dropFirst() {
                путь.addLine(to: точка)
            }
        }
        return путь
    }
}

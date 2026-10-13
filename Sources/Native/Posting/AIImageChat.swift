import SwiftUI
import PhotosUI
import UIKit

/**
 ОКНО «ОБЪЯВЛЕНИЕ С ИИ» (владелец 13.10.2026: «генератор изображения как в чате»; «фото + описание + мощная подача с
 оформлением»).

 Полноэкранный лист поверх подачи. Сверху — шапка («✕», «Объявление с ИИ», сколько картинок осталось сегодня, «…» с
 «Удалить диалог»), посередине — лента как в мессенджере (пузыри человека справа, ответы ИИ — карточки слева), внизу —
 подсказки-чипы и поле ввода со скрепкой (своё фото — правка). Пустой чат — «Что продаёте?» с примерами (режим А) или
 фото вещи и «Что сделать с фото?» (режим Б). Тема — светлая и тёмная, как у подачи (КраскаПодачи); тексты —
 Dynamic Type; «Уменьшение движения» — без бегущего сияния и проявления. Состояние — МодельЧатаИИФото, ответы ИИ —
 AIImageChatParts.swift.
 */
struct ЭкранЧатаИИФото: View {
    let закрыть: () -> Void
    @StateObject private var модель: МодельЧатаИИФото
    @State private var выбранное: PhotosPickerItem? = nil
    @State private var вопросЗакрыть = false
    @State private var вопросУдалить = false

    init(подача: ПодачаМодель, вход: ВходЧатаИИФото, закрыть: @escaping () -> Void) {
        self.закрыть = закрыть
        _модель = StateObject(wrappedValue: МодельЧатаИИФото(подача: подача, вход: вход))
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            ШапкаЧатаИИФото(модель: модель, закрыть: { нажатьЗакрыть() }, удалить: { вопросУдалить = true })
            содержимое
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(модель.экран)
                .transition(.opacity)
        }
        .background(ФонПодачи())
        .overlay(alignment: .bottom) { весть }
        .sheet(isPresented: $модель.согласие, onDismiss: { модель.отказатьсяОтСогласия() }) {
            ЛистСогласияИИФото(модель: модель)
        }
        .photosPicker(isPresented: $модель.выбратьФото, selection: $выбранное, matching: .images)
        .onChange(of: выбранное) { _, новое in
            guard let новое else { return }
            выбранное = nil
            Task { @MainActor in
                guard let данные = try? await новое.loadTransferable(type: Data.self) else {
                    модель.показатьВесть(т("aim_photo_fail"))
                    return
                }
                guard данные.count <= ОбработкаФото.предел else {
                    модель.показатьВесть(ПодачаText.т("ph_big"))
                    return
                }
                модель.принятьФото(данные: данные)
            }
        }
        .alert(модель.запрет?.заголовок ?? "", isPresented: запретНаЭкране, presenting: модель.запрет) { _ in
            Button(т("aim_ok"), role: .cancel) {}
        } message: { з in
            Text(з.текст)
        }
        .confirmationDialog(т("aim_close_q"), isPresented: $вопросЗакрыть, titleVisibility: .visible) {
            Button(т("aim_close_keep")) { закрыть() }
            Button(т("aim_close_delete"), role: .destructive) { модель.удалитьДиалог(потом: закрыть) }
            Button(т("aim_cancel"), role: .cancel) {}
        } message: {
            Text(т("aim_close_s"))
        }
        .confirmationDialog(т("aim_delete_q"), isPresented: $вопросУдалить, titleVisibility: .visible) {
            Button(т("aim_delete_yes"), role: .destructive) { модель.удалитьДиалог() }
            Button(т("aim_cancel"), role: .cancel) {}
        } message: {
            Text(т("aim_delete_s"))
        }
        .onAppear {
            модель.закрытьОкно = закрыть
            модель.открыт()
        }
        .onDisappear { модель.закрыть() }
        .onChange(of: модель.экран) { _, _ in
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    private var запретНаЭкране: Binding<Bool> {
        Binding(get: { модель.запрет != nil }, set: { показан in
            if !показан { модель.запрет = nil }
        })
    }

    /// «✕»: диалог есть — спросить, оставить ли его на сутки (вернуться можно) или удалить сразу.
    private func нажатьЗакрыть() {
        if модель.естьДиалог && !модель.реплики.isEmpty && модель.экран == .чат {
            вопросЗакрыть = true
        } else {
            закрыть()
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.экран {
        case .чат:
            ЛентаЧатаИИФото(модель: модель)
        case .вход:
            ЗаглушкаЧатаИИФото(значок: "person.crop.circle.badge.checkmark", заголовок: т("aim_login_t"),
                                текст: т("aim_login_s"), кнопка: т("aim_login"), значокКнопки: "person.fill") {
                ВходПоверх.показать(готово: { модель.послеВхода() })
            }
        case .скоро:
            ЗаглушкаЧатаИИФото(значок: "hourglass", заголовок: т("aim_soon_t"), текст: т("aim_soon_s"),
                                кнопка: т("aim_ok"), значокКнопки: "checkmark", действие: закрыть)
        }
    }

    @ViewBuilder
    private var весть: some View {
        if let текст = модель.весть {
            Text(текст)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color(red: 15 / 255, green: 23 / 255, blue: 18 / 255),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 120)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Шапка

/// «✕» слева, «Объявление с ИИ» и остаток картинок по центру, «…» с «Удалить диалог» справа.
struct ШапкаЧатаИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото
    let закрыть: () -> Void
    let удалить: () -> Void
    @ObservedObject private var готовность = ГотовностьИИФото.shared

    init(модель: МодельЧатаИИФото, закрыть: @escaping () -> Void, удалить: @escaping () -> Void) {
        self.модель = модель
        self.закрыть = закрыть
        self.удалить = удалить
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    /// «Осталось ИИ-картинок сегодня: N»; текстовых ходов — только когда их меньше 5.
    private var подпись: String? {
        guard let с = готовность.сведения else { return nil }
        var части: [String] = []
        if let осталось = с.осталось { части.append(String(format: т("aim_left"), осталось)) }
        if let текст = с.текстОсталось, текст < 5 { части.append(String(format: т("aim_left_text"), текст)) }
        return части.isEmpty ? nil : части.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 8) {
            кнопка(значок: "xmark", подпись: т("aim_close"), действие: закрыть)
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(КраскаПодачи.хорошоТекст)
                        .accessibilityHidden(true)
                    Text(т("aim_title"))
                        .foregroundStyle(КраскаПодачи.текст)
                }
                .font(.headline.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                if let подпись {
                    Text(подпись)
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Menu {
                Button(т("aim_delete"), systemImage: "trash", role: .destructive, action: удалить)
                    .disabled(!модель.естьДиалог)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(КраскаПодачи.текст)
                    .frame(width: 44, height: 44)
                    .background(КраскаПодачи.поле, in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel(т("aim_more_actions"))
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(КраскаПодачи.карточка.opacity(0.92).ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(КраскаПодачи.линия)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    private func кнопка(значок: String, подпись: String, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Image(systemName: значок)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(КраскаПодачи.текст)
                .frame(width: 44, height: 44)
                .background(КраскаПодачи.поле, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .accessibilityLabel(подпись)
    }
}

// MARK: - Лента

struct ЛентаЧатаИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото

    init(модель: МодельЧатаИИФото) {
        self.модель = модель
    }

    private static let низ = "aim_bottom"

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { прокрутка in
                ScrollView {
                    /* Не Lazy: реплик немного (до 30 ходов), а проявление картинки не должно повторяться при прокрутке. */
                    VStack(alignment: .leading, spacing: 16) {
                        if модель.реплики.isEmpty {
                            if модель.загружаемИсторию {
                                HStack {
                                    Spacer()
                                    SiteSpinner()
                                    Spacer()
                                }
                                .padding(.top, 60)
                            } else {
                                ПустойЧатИИФото(модель: модель)
                            }
                        }
                        ForEach(модель.реплики) { реплика in
                            РепликаИИФотоВид(модель: модель, реплика: реплика,
                                             полная: реплика.id == модель.последнийЧерновик)
                                .id(реплика.id)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(Self.низ)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: модель.сдвиг) { _, _ in
                    withAnimation(ДвижениеСайта.прокрутка) { прокрутка.scrollTo(Self.низ, anchor: .bottom) }
                }
            }
            ПолеЧатаИИФото(модель: модель)
        }
    }
}

// MARK: - Пустой чат

/// Режим А — «Что продаёте?» и примеры; режим Б — фото вещи и «Что сделать с фото?».
struct ПустойЧатИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото
    @State private var появилось = false
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения

    init(модель: МодельЧатаИИФото) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    var body: some View {
        VStack(spacing: 14) {
            if модель.режим == .edit {
                фотоВещи
            } else {
                значок
            }
            Text(т(модель.режим == .edit ? "aim_edit_t" : "aim_empty_t"))
                .font(.title2.weight(.heavy))
                .foregroundStyle(КраскаПодачи.текст)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(т(модель.режим == .edit ? "aim_edit_s" : "aim_empty_s"))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if модель.режим == .draft {
                примеры
                ЗаметкаПодачи(т("aim_empty_note"), тон: .серый, значок: "info.circle")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .opacity(появилось || тихо ? 1 : 0)
        .offset(y: появилось || тихо ? 0 : 14)
        .onAppear {
            guard !появилось else { return }
            withAnimation(ДвижениеСайта.мягко(.spring(response: 0.5, dampingFraction: 0.8))) { появилось = true }
        }
    }

    private var значок: some View {
        Image(systemName: "wand.and.stars")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 76, height: 76)
            .background(LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            .shadow(color: Color(uiColor: Theme.hex(0x0F5132, 0.3)), radius: 12, y: 6)
            .symbolEffect(.bounce, value: появилось)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var фотоВещи: some View {
        if let фото = модель.фото {
            Image(uiImage: фото)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                        .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
                }
                .accessibilityLabel(т("aim_your_photo"))
        } else if модель.готовимФото {
            ЗаглушкаИИФото(прогресс: 0, подпись: т("aim_preparing"), квадрат: true, проценты: false)
                .frame(maxWidth: 260)
        } else {
            КнопкаЧатаИИФото(т("aim_pick_photo"), значок: "photo.on.rectangle", главная: true) {
                модель.выбратьФото = true
            }
        }
    }

    /// Примеры просьб — в поле (человек может дописать: «б/у, 16/512, серый»).
    private var примеры: some View {
        ПотокЧипов(зазор: 8) {
            ForEach(["aim_ex_1", "aim_ex_2", "aim_ex_3"], id: \.self) { ключ in
                Button {
                    модель.вставитьПример(т(ключ))
                } label: {
                    Text(т(ключ))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(КраскаПодачи.хорошоТекст)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(КраскаПодачи.хорошоФон, in: Capsule())
                        .overlay { Capsule().strokeBorder(КраскаПодачи.хорошоТекст.opacity(0.25), lineWidth: 1) }
                }
                .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
                .accessibilityHint(т("aim_ex_hint"))
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Поле ввода

/// Чипы-подсказки, вложение (своё фото или «Правим эту»), поле с счётчиком, скрепка и «Отправить».
struct ПолеЧатаИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото
    @FocusState private var фокус: Bool

    init(модель: МодельЧатаИИФото) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    private var заглушка: String {
        if модель.режим == .edit { return т("aim_ph_edit") }
        return т(модель.естьДиалог ? "aim_ph_more" : "aim_ph_draft")
    }

    /// Пустое поле допустимо в правке (с фото — «сделай каталожно»), в черновике — только в начатом диалоге.
    private var можноОтправить: Bool {
        guard !модель.идёт, !модель.готовимФото else { return false }
        let пусто = модель.ввод.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if модель.режим == .edit { return модель.фото != nil || модель.основа != nil || модель.естьДиалог }
        return !пусто
    }

    /// Скрепка — своё фото для правки: режим правки включён и вид объявления его разрешает.
    private var можноФото: Bool {
        ГотовностьИИФото.shared.правкаДоступна(вид: модель.подача.видИИФото)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !модель.чипы.isEmpty && !модель.идёт { чипы }
            if модель.фото != nil || модель.основа != nil { вложения }
            строка
            if модель.ввод.count > модель.пределТекста - 60 {
                Text(String(format: т("aim_counter"), модель.ввод.count, модель.пределТекста))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(модель.ввод.count >= модель.пределТекста ? Theme.скидкаТекст : Theme.текстВторой)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(КраскаПодачи.карточка.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(КраскаПодачи.линия)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .onChange(of: модель.вПоле) { _, _ in фокус = true }
        .onChange(of: модель.ввод) { _, новое in
            if новое.count > модель.пределТекста { модель.ввод = String(новое.prefix(модель.пределТекста)) }
        }
    }

    private var чипы: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(модель.чипы) { чип in
                    Button {
                        модель.нажатьЧип(чип)
                    } label: {
                        Text(чип.подпись)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(КраскаПодачи.хорошоТекст)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(КраскаПодачи.хорошоФон, in: Capsule())
                            .overlay { Capsule().strokeBorder(КраскаПодачи.хорошоТекст.opacity(0.25), lineWidth: 1) }
                    }
                    .buttonStyle(НажатиеКнопкиФото(сжатие: 0.94))
                    .accessibilityHint(т(чип.вставка == nil ? "aim_chip_send_hint" : "aim_chip_insert_hint"))
                }
            }
            .padding(.vertical, 1)
        }
    }

    /// Миниатюра своего фото или картинки «Править эту» с «✕».
    private var вложения: some View {
        HStack(spacing: 10) {
            if let основа = модель.основа {
                миниатюра(основа, подпись: т("aim_editing_this"), убрать: { модель.снятьОснову() })
            } else if let фото = модель.фото {
                миниатюра(фото, подпись: т("aim_your_photo"), убрать: { модель.убратьФото() })
            }
            Spacer(minLength: 0)
        }
    }

    private func миниатюра(_ картинка: UIImage, подпись: String, убрать: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(uiImage: картинка)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                .accessibilityHidden(true)
            Text(подпись)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(КраскаПодачи.текст)
                .lineLimit(1)
            Button(action: убрать) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(т("aim_remove") + ": " + подпись)
        }
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .padding(.vertical, 4)
        .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }

    private var строка: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if можноФото {
                Button {
                    модель.выбратьФото = true
                } label: {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(КраскаПодачи.хорошоТекст)
                        .frame(width: 44, height: 44)
                        .background(КраскаПодачи.хорошоФон, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
                .disabled(модель.идёт || модель.готовимФото)
                .accessibilityLabel(т("aim_attach"))
            }
            TextField(заглушка, text: $модель.ввод, axis: .vertical)
                .lineLimit(1...5)
                .font(.body)
                .foregroundStyle(КраскаПодачи.текст)
                .focused($фокус)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(фокус ? КраскаПодачи.хорошоТекст.opacity(0.6) : КраскаПодачи.линия, lineWidth: 1)
                }
                .accessibilityLabel(т("aim_field_a11y"))
            Button {
                модель.отправить()
            } label: {
                ZStack {
                    if модель.идёт {
                        SiteSpinner.белый
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 44, height: 44)
                .background(можноОтправить || модель.идёт ? Theme.зелёный2 : Theme.текстВторой.opacity(0.4), in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
            .disabled(!можноОтправить)
            .accessibilityLabel(т(модель.идёт ? "aim_sending" : "aim_send"))
        }
    }
}

// MARK: - Согласие

/**
 Перед первым запросом (App Review 5.1.2(i)): кто обработает текст и кто — фото и картинки (ai_text и ai из info),
 сколько хранится, что не для обучения, как удалить, и что картинки ИИ в объявлении помечаются. «Согласен» — на этого
 человека и этих поставщиков (МодельЧатаИИФото.предметСогласия); общая формулировка — только до закрытия окна.
 */
struct ЛистСогласияИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото
    @ObservedObject private var готовность = ГотовностьИИФото.shared

    init(модель: МодельЧатаИИФото) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    private var ктоТекст: String {
        let кто = модель.ктоОбработает
        if кто.картинки == кто.текст { return String(format: т("aim_consent_same"), кто.текст) }
        return String(format: т("aim_consent_both"), кто.текст, кто.картинки)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                    .frame(width: 48, height: 48)
                    .background(КраскаПодачи.хорошоФон, in: Circle())
                    .accessibilityHidden(true)
                Text(т("aim_consent_t"))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(КраскаПодачи.текст)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    пункт("person.badge.shield.checkmark", ктоТекст)
                    пункт("clock.arrow.circlepath", т("aim_consent_keep"))
                    пункт("tag", т("aim_consent_mark"))
                }
            }
            VStack(spacing: 10) {
                ЗелёнаяКнопкаФото(заголовок: т("aim_consent_yes"), значок: "checkmark") { модель.согласиться() }
                Button(т("aim_consent_no")) { модель.отказатьсяОтСогласия() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(20)
        .background(КраскаПодачи.карточка.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func пункт(_ значок: String, _ текст: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: значок)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(текст)
                .font(.subheadline)
                .foregroundStyle(КраскаПодачи.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - «Войдите», «Скоро»

struct ЗаглушкаЧатаИИФото: View {
    let значок: String
    let заголовок: String
    let текст: String
    let кнопка: String
    let значокКнопки: String
    let действие: () -> Void

    init(значок: String, заголовок: String, текст: String, кнопка: String, значокКнопки: String,
         действие: @escaping () -> Void) {
        self.значок = значок
        self.заголовок = заголовок
        self.текст = текст
        self.кнопка = кнопка
        self.значокКнопки = значокКнопки
        self.действие = действие
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: значок)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                    .frame(width: 80, height: 80)
                    .background(КраскаПодачи.хорошоФон, in: Circle())
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(КраскаПодачи.текст)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(текст)
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
                ЗелёнаяКнопкаФото(заголовок: кнопка, значок: значокКнопки, действие: действие)
            }
            .padding(.horizontal, 32)
            .padding(.top, 70)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
    }
}

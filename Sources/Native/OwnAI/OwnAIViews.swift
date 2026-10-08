import SwiftUI
import UIKit
import SafariServices
import AuthenticationServices

/**
 «СВОЙ ИИ» — ЭКРАН И ТОЧКИ ВХОДА (как cabOwnAi() сайта: шестерёнка → «Объявления» → «Свой ИИ»; ссылка в карточке
 «Доступно» под «Kliko AI-ассистент»). Всё — только при own_ai.on == true; иначе ни строки, ни ссылки.

 Экран сверху вниз: что это и что пойдёт через свой ИИ (ассистент в чате по объявлению и проверка объявлений — всегда
 Kliko AI); плашка последней ошибки (err_text); Premium — «Действует до … · осталось N дн.» или покупка App Store товаром
 kz.kliko.app.ownai.month (кнопка — только когда товар загружен из StoreKit, иначе «Покупки временно недоступны»; ни
 кошелька, ни пробного периода в приложении); подключение — поставщик (own_ai.providers и «Определить автоматически»),
 ключ (SecureField, «Вставить» — системная PasteButton без запроса доступа к буферу), «Подключить», «Войти через
 OpenRouter» (если own_ai.login); подключено — поставщик, маска «•••• abcd», модель (own_ai_models / own_ai_model),
 «Использовать свой ИИ», «Проверить подключение», «Отключить» с подтверждением.
 Ключ в приложении не хранится: поле очищается сразу по «Подключить» и при уходе с экрана.
 */
struct ЭкранСвоегоИИ: View {
    let закрыть: () -> Void
    @ObservedObject private var модель = СвойИИМодель.shared
    @State private var загружено = false
    @State private var поставщик = "auto"
    @State private var ключ = ""
    /// Действие, которое сейчас идёт: connect, models, model, test, use, off, or.
    @State private var занято: String? = nil
    @State private var итог: String? = nil
    @State private var итогТон: ЗаметкаБизнеса.Тон = .серый
    @State private var модели: [String] = []
    /// need_premium в ответе — блок Premium выделен, экран к нему прокручен.
    @State private var выделитьПремиум = false
    @State private var спроситьОтключение = false

    init(закрыть: @escaping () -> Void) {
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { СвойИИText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { прокрутка in
                ScrollView {
                    содержимое
                        .padding(16)
                }
                .onChange(of: выделитьПремиум) { _, стало in
                    guard стало else { return }
                    withAnimation(ДвижениеСайта.смена) { прокрутка.scrollTo("oai_premium", anchor: .top) }
                }
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("oai_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("oai_close")) { закрыть() }
                        .tint(Theme.акцент)
                }
            }
        }
        .alert(т("oai_off_q"), isPresented: $спроситьОтключение) {
            Button(т("oai_off"), role: .destructive) { отключить() }
            Button(т("oai_cancel"), role: .cancel) {}
        } message: {
            Text(т("oai_off_s"))
        }
        .task {
            await модель.обновить()
            загружено = true
        }
        .onDisappear { ключ = "" }
    }

    // MARK: Содержимое

    @ViewBuilder
    private var содержимое: some View {
        if let с = модель.состояние, с.вкл {
            VStack(alignment: .leading, spacing: 12) {
                пояснение
                if !с.ошибка.isEmpty || !с.текстОшибки.isEmpty {
                    ЗаметкаБизнеса(с.текстОшибки.isEmpty ? т("oai_err_t") : с.текстОшибки, тон: .плохо,
                                   значок: "exclamationmark.triangle")
                }
                блокПремиум(с.премиум)
                    .id("oai_premium")
                if с.подключён {
                    блокПодключено(с)
                } else {
                    блокПодключения(с)
                }
            }
        } else if !загружено {
            VStack(spacing: 10) {
                SiteSpinner()
                Text(т("oai_loading")).foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 60)
        } else {
            заглушка
        }
    }

    /// Не загрузилось (сеть) — «Повторить»; загрузилось, а раздела нет (on: false, нет сессии) — одна строка.
    private var заглушка: some View {
        VStack(spacing: 14) {
            Text(модель.неЗагрузилось ? т("oai_load_fail") : т("oai_unavail"))
                .font(.system(size: 15))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if модель.неЗагрузилось {
                КнопкаБизнеса(подпись: т("oai_retry"), второстепенная: true) {
                    Task { @MainActor in await модель.обновить() }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var пояснение: some View {
        КарточкаБизнеса(т("oai_title"), значок: "key") {
            Text(т("oai_what"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            Text(т("oai_list_t"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.текст)
            ForEach(["oai_f1", "oai_f2", "oai_f3", "oai_f4", "oai_f5", "oai_f6", "oai_f7"], id: \.self) { к in
                Label {
                    Text(т(к))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                }
            }
            ЗаметкаБизнеса(т("oai_keep"), тон: .инфо, значок: "sparkles")
            Text(т("oai_safe"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Premium

    private func блокПремиум(_ п: ПремиумСвоегоИИ) -> some View {
        КарточкаБизнеса(т("oai_prem_t"), значок: "crown") {
            if п.действует {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: т("oai_prem_until"), Self.дата(п.до)))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if п.пробный { МеткаБизнеса(текст: т("oai_prem_trial")) }
                }
                if п.осталосьДней > 0 {
                    Text(String(format: т("oai_prem_left"), п.осталосьДней))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
            } else {
                ЗаметкаБизнеса(т(п.закончился ? "oai_prem_ended" : "oai_prem_need"),
                               тон: выделитьПремиум ? .предупреждение : .серый, значок: "lock")
                /* Только App Store (3.1.1): товар загружен — кнопка окна покупки; нет — «Покупки временно недоступны». */
                ВходПокупкиApple(услуга: .свойИИ, подпись: ПокупкиAppleText.подписьУслуги(.свойИИ)) {
                    ЛистУслугиApple.показать(.свойИИ)
                }
            }
        }
        .overlay {
            if выделитьПремиум && !п.действует {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.акцент, lineWidth: 2)
            }
        }
    }

    /// «7 ноября 2026 г.» — ISO 8601 сервера; не разобралась — как пришла.
    static func дата(_ строка: String) -> String {
        let чистая = строка.trimmingCharacters(in: .whitespaces)
        var найдено = ISO8601DateFormatter().date(from: чистая)
        if найдено == nil {
            let разбор = DateFormatter()
            разбор.locale = Locale(identifier: "en_US_POSIX")
            разбор.timeZone = TimeZone(identifier: "Asia/Almaty")
            for шаблон in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd"] where найдено == nil {
                разбор.dateFormat = шаблон
                найдено = разбор.date(from: чистая)
            }
        }
        guard let готовая = найдено else { return чистая }
        let вывод = DateFormatter()
        вывод.locale = Locale(identifier: Locale.preferredLanguages.first ?? "ru")
        вывод.dateStyle = .long
        вывод.timeStyle = .none
        return вывод.string(from: готовая)
    }

    // MARK: Подключение (ключа нет)

    private func блокПодключения(_ с: СостояниеСвоегоИИ) -> some View {
        КарточкаБизнеса(т("oai_conn_t"), значок: "link") {
            HStack(spacing: 8) {
                Text(т("oai_prov_t"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 4)
                Picker(т("oai_prov_t"), selection: $поставщик) {
                    Text(т("oai_prov_auto")).tag("auto")
                    ForEach(с.поставщики) { п in
                        Text(п.подпись).tag(п.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(Theme.акцент)
            }
            if с.поставщики.contains(where: { $0.id == "gemini" }) {
                Text(т("oai_prov_gemini"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            полеКлюча
            КнопкаБизнеса(подпись: т("oai_connect"), занято: занято == "connect") { подключить() }
                .disabled(занято != nil || ключ.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if с.входOpenRouter {
                КнопкаБизнеса(подпись: т("oai_or"), занято: занято == "or", второстепенная: true) { войтиOpenRouter() }
                    .disabled(занято != nil)
                Text(т("oai_or_note"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            итогБлок
        }
    }

    /// Ключ: скрытое поле и системная «Вставить» (PasteButton — без окна «Разрешить вставку»).
    private var полеКлюча: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(т("oai_key_t"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.текст)
            HStack(spacing: 8) {
                SecureField(т("oai_key_ph"), text: $ключ)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 15))
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                PasteButton(payloadType: String.self) { строки in
                    let текст = (строки.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { @MainActor in ключ = текст }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.roundedRectangle)
                .tint(Theme.акцент)
                .accessibilityLabel(т("oai_paste"))
            }
        }
    }

    // MARK: Подключено

    private func блокПодключено(_ с: СостояниеСвоегоИИ) -> some View {
        КарточкаБизнеса(т("oai_conn_t"), значок: "checkmark.seal") {
            строкаСведений(т("oai_prov_t"), с.имяПоставщика + (с.через == "openrouter" ? " · " + т("oai_via_or") : ""))
            if с.через != "openrouter" || !с.хвост.isEmpty {
                строкаСведений(т("oai_key_mask"), с.маска)
            }
            выборМодели(с)
            Toggle(isOn: Binding(get: { с.использовать }, set: { новое in переключить(новое) })) {
                Text(т("oai_use"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текст)
            }
            .tint(Theme.акцент)
            .disabled(занято != nil)
            if !с.использовать {
                Text(т("oai_use_s"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            КнопкаБизнеса(подпись: т("oai_test"), занято: занято == "test", второстепенная: true) { проверить() }
                .disabled(занято != nil)
            итогБлок
            Button(role: .destructive) {
                спроситьОтключение = true
            } label: {
                Text(т("oai_off"))
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .disabled(занято != nil)
        }
        .task(id: с.подключён) {
            if модели.isEmpty { await загрузитьМодели() }
        }
    }

    private func строкаСведений(_ подпись: String, _ значение: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(подпись)
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 4)
            Text(значение)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    /// Модель: список own_ai_models, выбор — own_ai_model. Пусто — «Выберите модель».
    private func выборМодели(_ с: СостояниеСвоегоИИ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(т("oai_model_t"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                Spacer(minLength: 4)
                if занято == "models" || занято == "model" {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.акцент)
                }
                Menu {
                    ForEach(модели, id: \.self) { имя in
                        Button {
                            сменитьМодель(имя)
                        } label: {
                            if имя == с.модель {
                                Label(имя, systemImage: "checkmark")
                            } else {
                                Text(имя)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(с.модель.isEmpty ? т("oai_model_pick") : с.модель)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Theme.акцент)
                }
                .disabled(модели.isEmpty || занято != nil)
            }
            if с.модель.isEmpty {
                ЗаметкаБизнеса(т("oai_model_need"), тон: .предупреждение, значок: "exclamationmark.circle")
            }
        }
    }

    @ViewBuilder
    private var итогБлок: some View {
        if let итог {
            ЗаметкаБизнеса(итог, тон: итогТон, значок: итогТон == .хорошо ? "checkmark.circle" : "exclamationmark.triangle")
        }
    }

    // MARK: Действия — только по нажатию

    private func показатьИтог(_ текст: String, _ тон: ЗаметкаБизнеса.Тон) {
        итог = текст
        итогТон = тон
        UIAccessibility.post(notification: .announcement, argument: текст)
    }

    /// Отказ: готовый текст сервера; need_premium — выделить Premium.
    private func разобрать(_ ответ: СвойИИAPI.Ответ) {
        switch ответ {
        case .готово:
            break
        case .отказ(let текст, _, let нуженПремиум):
            показатьИтог(текст, .плохо)
            if нуженПремиум { выделитьПремиум = true }
        case .нуженВход:
            показатьИтог(т("oai_need_login"), .плохо)
        case .сеть:
            показатьИтог(т("oai_no_conn"), .плохо)
        }
    }

    /// own_ai_connect {provider, key}. Поле очищается до запроса: ключ живёт только в теле этого запроса.
    private func подключить() {
        let значение = ключ.trimmingCharacters(in: .whitespacesAndNewlines)
        ключ = ""
        guard !значение.isEmpty, занято == nil else { return }
        занято = "connect"
        итог = nil
        выделитьПремиум = false
        let кто = поставщик
        Task { @MainActor in
            let ответ = await СвойИИAPI.выполнить("own_ai_connect", ["provider": кто, "key": значение])
            занято = nil
            if case .готово(let j) = ответ {
                модели = Self.строки(j["models"])
                показатьИтог(т("oai_connected"), .хорошо)
            } else {
                разобрать(ответ)
            }
        }
    }

    private func загрузитьМодели() async {
        guard занято == nil else { return }
        занято = "models"
        let ответ = await СвойИИAPI.выполнить("own_ai_models")
        занято = nil
        if case .готово(let j) = ответ {
            модели = Self.строки(j["models"])
        } else if case .отказ(let текст, _, let нуженПремиум) = ответ {
            /* Без Premium список не нужен: о Premium скажет его блок, отдельной ошибки не показываем. */
            if !нуженПремиум { показатьИтог(текст, .плохо) }
        }
    }

    private func сменитьМодель(_ имя: String) {
        guard занято == nil, имя != модель.состояние?.модель else { return }
        занято = "model"
        итог = nil
        Task { @MainActor in
            let ответ = await СвойИИAPI.выполнить("own_ai_model", ["model": имя])
            занято = nil
            if case .готово = ответ {
                показатьИтог(т("oai_model_saved"), .хорошо)
            } else {
                разобрать(ответ)
            }
        }
    }

    private func проверить() {
        guard занято == nil else { return }
        занято = "test"
        итог = nil
        Task { @MainActor in
            let ответ = await СвойИИAPI.выполнить("own_ai_test")
            занято = nil
            if case .готово = ответ {
                показатьИтог(т("oai_test_ok"), .хорошо)
            } else {
                разобрать(ответ)
            }
        }
    }

    private func переключить(_ вкл: Bool) {
        guard занято == nil else { return }
        занято = "use"
        итог = nil
        Task { @MainActor in
            let ответ = await СвойИИAPI.выполнить("own_ai_use", ["on": вкл])
            занято = nil
            if case .готово = ответ {
                показатьИтог(т(вкл ? "oai_use_on" : "oai_use_off"), вкл ? .хорошо : .инфо)
            } else {
                разобрать(ответ)
            }
        }
    }

    private func отключить() {
        guard занято == nil else { return }
        занято = "off"
        итог = nil
        Task { @MainActor in
            let ответ = await СвойИИAPI.выполнить("own_ai_disconnect")
            занято = nil
            if case .готово = ответ {
                модели = []
                показатьИтог(т("oai_off_done"), .инфо)
            } else {
                разобрать(ответ)
            }
        }
    }

    /// own_ai_or_start → url → OpenRouter; после закрытия окна — own_ai_state.
    private func войтиOpenRouter() {
        guard занято == nil else { return }
        занято = "or"
        итог = nil
        Task { @MainActor in
            let ответ = await СвойИИAPI.выполнить("own_ai_or_start")
            занято = nil
            guard case .готово(let j) = ответ else {
                разобрать(ответ)
                return
            }
            guard let адрес = ВходOpenRouter.адрес(МоиОбъявленияAPI.строка(j["url"])) else {
                показатьИтог(т("oai_fail"), .плохо)
                return
            }
            ВходOpenRouter.открыть(адрес) {
                Task { @MainActor in await СвойИИМодель.shared.обновить() }
            }
        }
    }

    /// models: массив строк-id.
    static func строки(_ значение: Any?) -> [String] {
        var итог: [String] = []
        for элемент in (значение as? [Any]) ?? [] {
            let имя = МоиОбъявленияAPI.строка(элемент).trimmingCharacters(in: .whitespacesAndNewlines)
            if !имя.isEmpty && !итог.contains(имя) { итог.append(имя) }
        }
        return итог
    }
}

// MARK: - Вход через OpenRouter

/**
 own_ai_or_start отдаёт адрес OpenRouter. Колбэк в схему приложения (callback_url kliko://…) — ASWebAuthenticationSession
 со схемой kliko; колбэк на сайт (https) — SFSafariViewController: человек входит, сайт сохраняет ключ, «Готово» закрывает
 окно. В обоих случаях после закрытия экран перечитывает own_ai_state — подключилось или нет, скажет сервер.
 */
@MainActor
enum ВходOpenRouter {
    private static var сессия: ASWebAuthenticationSession? = nil
    private static var якорь: ЯкорьПодключенияСоцсети? = nil
    private static var посредник: ПосредникOpenRouter? = nil
    /// Что сделать, когда окно закроется (экран перечитает own_ai_state). Одно окно за раз.
    private static var послеЗакрытия: (() -> Void)? = nil

    /// Только https: openrouter.ai или сам kliko.kz (если сервер ведёт через свою страницу).
    static func адрес(_ строка: String) -> URL? {
        guard let адрес = URL(string: строка.trimmingCharacters(in: .whitespacesAndNewlines)),
              адрес.scheme?.lowercased() == "https",
              let хост = адрес.host?.lowercased() else { return nil }
        let свои = ["openrouter.ai", "kliko.kz"]
        guard свои.contains(where: { хост == $0 || хост.hasSuffix("." + $0) }) else { return nil }
        return адрес
    }

    static func открыть(_ адрес: URL, закрыто: @escaping () -> Void) {
        послеЗакрытия = закрыто
        if возвратВПриложение(адрес) {
            листом(адрес)
        } else {
            safari(адрес)
        }
    }

    /// Окно закрыто (колбэк, «Отмена», «Готово») — один раз.
    static func закончить() {
        сессия = nil
        якорь = nil
        посредник = nil
        let действие = послеЗакрытия
        послеЗакрытия = nil
        действие?()
    }

    /// callback_url (или redirect_uri) в адресе — в схему kliko://.
    private static func возвратВПриложение(_ адрес: URL) -> Bool {
        let поля = URLComponents(url: адрес, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let возврат = поля.first(where: { $0.name == "callback_url" || $0.name == "redirect_uri" })?.value ?? ""
        return URL(string: возврат)?.scheme?.lowercased() == "kliko"
    }

    private static func листом(_ адрес: URL) {
        let окна = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let окно = окна.first(where: { $0.isKeyWindow }) ?? окна.first else {
            safari(адрес)
            return
        }
        let лист = ASWebAuthenticationSession(url: адрес, callbackURLScheme: "kliko", completionHandler: обработчик())
        let я = ЯкорьПодключенияСоцсети(окно: окно)
        лист.presentationContextProvider = я
        сессия = лист
        якорь = я
        if !лист.start() {
            сессия = nil
            якорь = nil
            safari(адрес)
        }
    }

    /// Обработчик вне главного актора: система может позвать его с любой нити — дальше на главной. Ничего не захватывает.
    nonisolated private static func обработчик() -> @Sendable (URL?, Error?) -> Void {
        return { _, _ in
            Task { @MainActor in ВходOpenRouter.закончить() }
        }
    }

    private static func safari(_ адрес: URL) {
        guard let верх = ПоверхВсего.верхний() else {
            закончить()
            return
        }
        let окно = SFSafariViewController(url: адрес)
        окно.dismissButtonStyle = .done
        let п = ПосредникOpenRouter()
        окно.delegate = п
        посредник = п
        верх.present(окно, animated: true)
    }
}

/// «Готово» в окне OpenRouter (SFSafariViewController).
final class ПосредникOpenRouter: NSObject, SFSafariViewControllerDelegate {
    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        MainActor.assumeIsolated {
            ВходOpenRouter.закончить()
        }
    }
}

// MARK: - Окно отказа своего ИИ

/// Готовый текст сервера и действия: «Настройки своего ИИ»; для key/funds/model/gone — «Выключить свой ИИ».
struct ЛистОтказаСвоегоИИ: View {
    let отказ: ОтказСвоегоИИ
    let закрыть: () -> Void
    @State private var выключаем = false
    @State private var итог: String? = nil

    init(отказ: ОтказСвоегоИИ, закрыть: @escaping () -> Void) {
        self.отказ = отказ
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { СвойИИText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: "key")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(КраскаОбъявлений.предупреждениеТекст)
                    .frame(width: 60, height: 60)
                    .background(Theme.мята, in: Circle())
                    .accessibilityHidden(true)
                Text(т("oai_fail_t"))
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(отказ.текст)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let итог {
                    ЗаметкаБизнеса(итог, тон: .инфо, значок: "info.circle")
                }
                КнопкаБизнеса(подпись: т("oai_settings")) {
                    закрыть()
                    ОкноСвоегоИИ.открытьПосле()
                }
                if отказ.можноВыключить && итог == nil {
                    КнопкаБизнеса(подпись: т("oai_disable"), занято: выключаем, второстепенная: true) { выключить() }
                }
                Button(т("oai_close")) { закрыть() }
                    .font(.system(size: 15, weight: .semibold))
                    .tint(Theme.акцент)
                    .padding(.top, 2)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
    }

    private func выключить() {
        guard !выключаем else { return }
        выключаем = true
        Task { @MainActor in
            let текст = await СвойИИМодель.shared.выключить()
            выключаем = false
            итог = текст
            UIAccessibility.post(notification: .announcement, argument: текст)
        }
    }
}

// MARK: - Точки входа

/// Строка «Свой ИИ · вкл/выкл» в разделе «Объявления» настроек кабинета — только при own_ai.on.
struct СтрокаСвоегоИИ: View {
    @ObservedObject private var модель = СвойИИМодель.shared

    init() {}

    var body: some View {
        if модель.вкл {
            Button {
                ОкноСвоегоИИ.открыть()
            } label: {
                HStack {
                    ПодписьСтрокиКабинета(СвойИИText.т("oai_title") + " · "
                                          + СвойИИText.т(модель.активен ? "oai_on_short" : "oai_off_short"),
                                          значок: "key")
                    Spacer(minLength: 8)
                    СтрелкаСтрокиКабинета()
                }
            }
            .полямиСтрокиКабинета()
        }
    }
}

/// Ссылка «Свой ИИ» под «Kliko AI-ассистент» в карточке «Доступно» — только при own_ai.on.
struct СсылкаСвоегоИИ: View {
    @ObservedObject private var модель = СвойИИМодель.shared

    init() {}

    var body: some View {
        if модель.вкл {
            Button {
                ОкноСвоегоИИ.открыть()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "key")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(модель.активен ? СвойИИText.т("oai_title") + " · " + СвойИИText.т("oai_on_short")
                                        : СвойИИText.т("oai_link"))
                        .font(.system(size: 13, weight: .semibold))
                        .underline()
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.акцент)
                .padding(.leading, 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

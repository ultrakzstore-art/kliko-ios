import SwiftUI

/**
 KLIKO AI-ПОДСКАЗКИ ОТВЕТА В ПЕРЕПИСКЕ (владелец 07.10.2026: «Kliko AI-подсказки прямо в чате в iOS»; «когда Kliko AI
 выключен — предлагать в переписке, что есть такая фича, с настоящим образцом, как это работает»).

 Сайт (chat.php, опт-ин «по кнопке ✨»):
   · POST chat.php?action=ai_replies {cid} — чат по объявлению (лид продавца и чат покупателя) — без csrf, как
     kcAiReplies / acwAiReplies сайта;
   · POST chat.php?action=ai_replies_dm {tid} — личная переписка (_dmTplFetchAi кабинета);
   · ответ {ok: true, replies: [3 строки]} | {ok: false, ai_off: true} (Kliko AI выключен на сайте) | {ok: false,
     limit: 1} (дневной лимит подсказок airep_daily) | {ok: false, busy: true} (чаще раза в 2 секунды) | {error: auth |
     not_found | access | empty | ai}; «Свой ИИ» — {ok: false, own_ai: "<код>", error: готовый текст}.
 Транспорт — КабинетСайта (ИнбоксAPI.отправитьБезТокена): fetch самой страницы сайта, как соседние запросы кабинета.

 Как у сайта: подсказка только встаёт в поле ввода и ничего не отправляет сама; варианты — тремя чипами над полем
 (DM сайта — «Kliko AI-подсказки» над шаблонами). busy — тихий повтор через 2 секунды; иная ошибка — «Не удалось —
 попробуйте ещё раз». Когда Kliko AI недоступен (ai_off, limit) или подсказывать ещё не по чему, вместо тишины сайта —
 окно с образцом: пример переписки и три чипа (настоящие строки шаблонов сайта, ACW_SUGG «актуальн» в
 inc/active_chat_pin.php), как это работает и кнопка покупки пакета Kliko AI через App Store — только когда
 Config.цифровыеПокупки и товар пакета загружен из StoreKit (ДоступПокупкиApple); иначе — только «Понятно». Ссылок на
 оплату на сайте нет. Один раз — карточка-знакомство в новой переписке (запоминается на телефоне).

 Рубильник — Config.подсказкиИИЧата.
 */
@MainActor
enum ИИПодсказкиAPI {
    /// Какой чат: по объявлению (chat.php, cid) или личная переписка (dm, tid).
    enum Чат {
        case объявление
        case личный
    }

    enum Итог: Equatable {
        case варианты([String])
        /// ai_off — Kliko AI выключен на сайте.
        case выключен
        /// limit — дневной лимит подсказок исчерпан.
        case лимит
        /// busy — чаще раза в 2 секунды.
        case занято
        /// empty — подсказывать не по чему (сообщений нет).
        case пусто
        /// Отказ своего ИИ («Свой ИИ», own_ai:"<код>" и готовый текст) — не молча: окно с действиями.
        case свойИИ(ОтказСвоегоИИ)
        case сбой
    }

    static func запросить(_ чат: Чат, номер: String) async -> Итог {
        let чистый = номер.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty else { return .пусто }
        let хвост: String
        let тело: [String: Any]
        switch чат {
        case .объявление:
            хвост = "chat.php?action=ai_replies"
            тело = ["cid": чистый]
        case .личный:
            хвост = "chat.php?action=ai_replies_dm"
            тело = ["tid": чистый]
        }
        do {
            let j = try await ИнбоксAPI.отправитьБезТокена(хвост, тело: тело)
            return разобрать(j)
        } catch {
            return .сбой
        }
    }

    nonisolated static func разобрать(_ j: [String: Any]) -> Итог {
        if !да(j["ok"]), let отказ = ОтказСвоегоИИ.из(j) { return .свойИИ(отказ) }
        if да(j["ok"]) {
            let строки = (j["replies"] as? [Any] ?? []).compactMap { элемент -> String? in
                guard let s = элемент as? String else { return nil }
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : t
            }
            return строки.isEmpty ? .сбой : .варианты(Array(строки.prefix(3)))
        }
        if да(j["ai_off"]) { return .выключен }
        if да(j["limit"]) { return .лимит }
        if да(j["busy"]) { return .занято }
        if (j["error"] as? String) == "empty" { return .пусто }
        return .сбой
    }

    private nonisolated static func да(_ значение: Any?) -> Bool {
        if let b = значение as? Bool { return b }
        if let n = значение as? NSNumber { return n.intValue != 0 }
        if let s = значение as? String { return s == "1" || s.lowercased() == "true" }
        return false
    }
}

/// Состояние подсказок одного экрана переписки: запрос по «✨», чипы над полем, окно-образец, знакомство.
@MainActor
final class ИИПодсказкиЧата: ObservableObject {
    enum Состояние: Equatable {
        case нет
        case грузим
        case варианты([String])
        case сбой
    }

    /// Почему показано окно-образец.
    enum Повод {
        /// Знакомство: подсказывать ещё не по чему или «Как это работает».
        case знакомство
        /// ai_off.
        case выключен
        /// limit.
        case лимит

        /// Кнопки пакета Kliko AI нет нигде: сервер выдаёт подсказки без проверки подписки — покупка пакета не снимет ни
        /// выключение Kliko AI, ни дневной лимит подсказок (airep_daily), а обещать то, чего покупка не даст, нельзя
        /// (App Review 3.1.1 / 2.3). Вернуть — когда сервер начнёт учитывать пакет в лимите подсказок.
        var предлагаетПакет: Bool {
            switch self {
            case .знакомство, .выключен, .лимит: return false
            }
        }
    }

    @Published private(set) var состояние: Состояние = .нет
    /// Карточка-знакомство над полем (один раз на телефоне).
    @Published private(set) var знакомство = false

    let чат: ИИПодсказкиAPI.Чат
    private var задача: Task<Void, Never>? = nil
    private static let ключЗнакомства = "klikoAIHintsIntroShown"

    init(чат: ИИПодсказкиAPI.Чат) {
        self.чат = чат
    }

    var грузим: Bool { состояние == .грузим }

    /// «✨»: номер — cid / tid; естьПереписка — в ленте есть хоть одно сообщение (сайту есть по чему подсказывать).
    func нажали(номер: String, естьПереписка: Bool) {
        guard Config.подсказкиИИЧата, состояние != .грузим else { return }
        знакомство = false
        let чистый = номер.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !чистый.isEmpty, естьПереписка else {
            ИИПодсказкиЧата.показатьОбразец(.знакомство, пусто: true)
            return
        }
        состояние = .грузим
        задача?.cancel()
        let чат = self.чат
        задача = Task { @MainActor [weak self] in
            var итог = await ИИПодсказкиAPI.запросить(чат, номер: чистый)
            var повторов = 0
            while итог == .занято && повторов < 2 {
                повторов += 1
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                if Task.isCancelled { return }
                итог = await ИИПодсказкиAPI.запросить(чат, номер: чистый)
            }
            guard let self, !Task.isCancelled else { return }
            switch итог {
            case .варианты(let строки):
                self.состояние = .варианты(строки)
            case .выключен:
                self.состояние = .нет
                ИИПодсказкиЧата.показатьОбразец(.выключен, пусто: false)
            case .лимит:
                self.состояние = .нет
                ИИПодсказкиЧата.показатьОбразец(.лимит, пусто: false)
            case .пусто:
                self.состояние = .нет
                ИИПодсказкиЧата.показатьОбразец(.знакомство, пусто: true)
            case .свойИИ(let отказ):
                self.состояние = .нет
                ОкноСвоегоИИ.показатьОтказ(отказ)
            case .занято, .сбой:
                self.состояние = .сбой
            }
        }
    }

    /// Чип выбран — варианты убираем, текст ставит экран в поле.
    func выбрали() {
        состояние = .нет
    }

    func скрыть() {
        задача?.cancel()
        состояние = .нет
        знакомство = false
    }

    /// Новая переписка загружена: один раз на телефоне — карточка-знакомство над полем.
    func проверитьЗнакомство(новая: Bool) {
        guard Config.подсказкиИИЧата, новая, !знакомство, состояние == .нет else { return }
        let хранилище = UserDefaults.standard
        guard !хранилище.bool(forKey: ИИПодсказкиЧата.ключЗнакомства) else { return }
        хранилище.set(true, forKey: ИИПодсказкиЧата.ключЗнакомства)
        знакомство = true
    }

    func закрытьЗнакомство() {
        знакомство = false
    }

    /// Окно-образец поверх переписки (половина экрана, тянется вверх).
    static func показатьОбразец(_ повод: Повод, пусто: Bool = false) {
        ПоверхВсего.показать(большой: false) { закрыть in
            ОбразецИИПодсказок(повод: повод, пусто: пусто, закрыть: закрыть)
        }
    }
}

// MARK: - Кнопка «✨» у поля ввода

/// «✨» внутри поля ввода, перед «Отправить»; пока Kliko AI подбирает — кружок.
struct КнопкаИИПодсказок: View {
    @ObservedObject var ии: ИИПодсказкиЧата
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            ZStack {
                if ии.грузим {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.акцент)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.акцент)
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(ии.грузим)
        .accessibilityLabel(ИИПодсказкиText.т("btn"))
    }
}

// MARK: - Полоса над полем: варианты, «подбираю», сбой, знакомство

struct ПолосаИИПодсказок: View {
    @ObservedObject var ии: ИИПодсказкиЧата
    /// Переписка загружена и своих сообщений в ней ещё нет — повод для знакомства.
    let новая: Bool
    /// Выбранный вариант — в поле ввода (не отправляется).
    let вставить: (String) -> Void
    /// «Не удалось — попробуйте ещё раз» нажали — повторить запрос.
    let повторить: () -> Void

    private func т(_ ключ: String) -> String { ИИПодсказкиText.т(ключ) }

    var body: some View {
        содержимое
            .animation(ДвижениеСайта.смена, value: ии.состояние)
            .animation(ДвижениеСайта.смена, value: ии.знакомство)
            .onAppear { ии.проверитьЗнакомство(новая: новая) }
            .onChange(of: новая) { _, стало in ии.проверитьЗнакомство(новая: стало) }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch ии.состояние {
        case .грузим:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.акцент)
                Text(т("loading"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
        case .варианты(let строки):
            варианты(строки)
        case .сбой:
            Button(action: повторить) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(т("failed"))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.цвет(0x991B1B, 0xFF8A8F))
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        case .нет:
            if ии.знакомство {
                карточкаЗнакомства
            }
        }
    }

    private func варианты(_ строки: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
                Text(т("head").uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .kerning(0.4)
                Spacer(minLength: 0)
                Button {
                    ии.скрыть()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 28, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(т("hide"))
            }
            .foregroundStyle(Theme.акцент)
            .padding(.horizontal, 14)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(строки.enumerated()), id: \.offset) { _, строка in
                        ЧипИИПодсказки(текст: строка, активен: true) {
                            ии.выбрали()
                            вставить(строка)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.top, 8)
    }

    private var карточкаЗнакомства: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 30, height: 30)
                .background(Theme.акцент.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(т("intro_t"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(т("intro_s"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    ии.закрытьЗнакомство()
                    ИИПодсказкиЧата.показатьОбразец(.знакомство)
                } label: {
                    Text(т("how"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Button {
                ии.закрытьЗнакомство()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(т("close"))
        }
        .padding(10)
        .background(Theme.акцент.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.акцент.opacity(0.25), lineWidth: 1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }
}

/// Чип варианта (.lcm-tpl-pchip с кромкой --acc-on у «Kliko AI-подсказок» сайта). Неактивный — образец в окне.
struct ЧипИИПодсказки: View {
    let текст: String
    let активен: Bool
    var действие: () -> Void = {}

    var body: some View {
        Button(action: действие) {
            Text(текст)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.поверхность, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Theme.акцент, lineWidth: 1)
                }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .allowsHitTesting(активен)
        .accessibilityHint(активен ? ИИПодсказкиText.т("chip_hint") : "")
    }
}

// MARK: - Окно-образец

/// Kliko AI недоступен или подсказывать ещё не по чему: что это, образец переписки с тремя вариантами, как работает.
/// Кнопка пакета Kliko AI — только покупкой App Store и только с загруженным товаром; иначе — «Понятно».
struct ОбразецИИПодсказок: View {
    let повод: ИИПодсказкиЧата.Повод
    let пусто: Bool
    let закрыть: () -> Void
    @ObservedObject private var покупки = ПокупкиApple.shared

    private func т(_ ключ: String) -> String { ИИПодсказкиText.т(ключ) }

    private var можноКупить: Bool {
        Config.цифровыеПокупки && повод.предлагаетПакет && покупки.можноКупить(.пакетИИ)
    }

    private var заголовок: String {
        switch повод {
        case .знакомство: return т("t_intro")
        case .выключен: return т("t_off")
        case .лимит: return т("t_limit")
        }
    }

    private var пояснение: String {
        switch повод {
        case .знакомство: return т(пусто ? "s_empty" : "s_intro")
        case .выключен: return т("s_off")
        case .лимит: return т("s_limit")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                шапка
                образец
                какРаботает
                кнопки
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .background(Theme.поверхность)
        .task { await покупки.подгрузить() }
    }

    private var шапка: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(LinearGradient(colors: [Theme.зелёный2, Theme.зелёныйЯркий], startPoint: .topLeading,
                                           endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(заголовок)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                Text(пояснение)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var образец: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(т("sample").uppercased())
                .font(.system(size: 11, weight: .heavy))
                .kerning(0.4)
                .foregroundStyle(Theme.текстВторой)
            VStack(alignment: .leading, spacing: 3) {
                Text(т("sample_who"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                HStack {
                    ОблакоКабинета(текст: т("sample_peer"), время: "", моё: false)
                    Spacer(minLength: 48)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
                Text(т("head").uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .kerning(0.4)
            }
            .foregroundStyle(Theme.акцент)
            VStack(alignment: .leading, spacing: 6) {
                ЧипИИПодсказки(текст: т("sample_1"), активен: false)
                ЧипИИПодсказки(текст: т("sample_2"), активен: false)
                ЧипИИПодсказки(текст: т("sample_3"), активен: false)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.полеПереписки, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.кромкаПоляПереписки, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var какРаботает: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("how"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.текст)
            шаг(1, т("how_1"))
            шаг(2, т("how_2"))
            шаг(3, т("how_3"))
            Text(т("how_note"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func шаг(_ номер: Int, _ текст: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(номер))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.акцент)
                .frame(width: 22, height: 22)
                .background(Theme.акцент.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var кнопки: some View {
        VStack(spacing: 10) {
            if можноКупить {
                КнопкаПокупкиApple(подпись: т("buy"), значок: ВидУслугиApple.пакетИИ.значок) {
                    закрыть()
                    ЛистУслугиApple.показать(.пакетИИ)
                }
            }
            Button(action: закрыть) {
                Text(т("ok"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(можноКупить ? Theme.акцент : Color.white)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .fill(можноКупить ? Color.clear : Theme.пузырьМой)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .strokeBorder(можноКупить ? Theme.линия : Color.clear, lineWidth: 1.5)
                    }
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        }
        .padding(.top, 4)
    }
}

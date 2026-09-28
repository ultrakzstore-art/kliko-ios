import SwiftUI
import UIKit
import WebKit

/**
 НАТИВНЫЙ ПОТОК eGov — ВИДЫ, ЗАПРОСЫ, МОДЕЛЬ (владелец: «флоу eGov так же сделай в SwiftUI»).

 Что делает сайт (js/cabinet.min.js: bioKycOpen, bioFlowStart, _bioPollTick, otpStepOpen, otpStepStart, _osPollTick;
 inline-скрипт гостевого cabinet.php: egovAuthOpen, egovLoginConfirmOpen, _egPollTick; карта кабинета §2.4, §2.5, §7):
   1. своя форма: ИИН и номер, привязанный в eGov (у вошедшего — из CAB_USER), у гостя — согласие с условиями;
   2. своя сверка «Проверьте данные» (только верификация, boostConfirm сайта);
   3. POST создания → session_id;
   4. ЧУЖОЙ ШАГ: iframe https://remote.biometric.kz/flow/<session_id>?locale=kz|ru|en — там человек вводит код из SMS
      и проходит проверку лица камерой. Код мы не видим (bio_sec_note), адреса возврата нет, итог узнаём только опросом;
   5. опрос раз в 3 с, после первой минуты раз в 6 с, окно 300 с; внеочередной опрос — на postMessage от biometric.kz
      и на возврат во вкладку;
   6. свой итог: «Поздравляем!» или «Не удалось» с причиной по reason / error.
 Здесь всё то же, кроме iframe: на шаге 4 — компактный лист с WKWebView (ЛистБиометрииEgov), остальное — SwiftUI.
 Приложения eGov Mobile, QR-кода и ввода кода у нас сайт не использует — их и здесь нет.
 */
enum ВидПотокаEgov: Equatable {
    /// Гость: вход, регистрация или восстановление по ИИН (cabinet.php flow_login_create / flow_login_result).
    case вход(телефон: String)
    /// Гость с верным паролем и защитой входа (login_egov_create / login_egov_result), полей нет.
    case подтверждениеВхода
    /// Вошедший: верификация (kyc.php flow_create / flow_result); сделка — return_deal сайта.
    case верификация(сделка: String)
    /// Вошедший: шаг опасного действия (cabinet.php otp_step_create / otp_step_check).
    case шаг(назначение: String, ссылка: String, заголовок: String, подсказка: String)

    /// Запросы гостевой страницы: токен — const CSRF гостя.
    var гость: Bool {
        switch self {
        case .вход, .подтверждениеВхода: return true
        case .верификация, .шаг: return false
        }
    }

    /// Нужны ли поля ИИН и номера.
    var сПолями: Bool {
        if case .подтверждениеВхода = self { return false }
        return true
    }

    var создание: String {
        switch self {
        case .вход: return "cabinet.php?action=flow_login_create"
        case .подтверждениеВхода: return "cabinet.php?action=login_egov_create"
        case .верификация: return "kyc.php?action=flow_create"
        case .шаг: return "cabinet.php?action=otp_step_create"
        }
    }

    var итог: String {
        switch self {
        case .вход: return "cabinet.php?action=flow_login_result"
        case .подтверждениеВхода: return "cabinet.php?action=login_egov_result"
        case .верификация: return "kyc.php?action=flow_result"
        case .шаг: return "cabinet.php?action=otp_step_check"
        }
    }

    /// Тело опроса без csrf (его кладёт транспорт).
    var телоИтога: [String: Any] {
        if case .шаг(let назначение, let ссылка, _, _) = self {
            return ["purpose": назначение, "ref": ссылка]
        }
        return [:]
    }

    var заголовок: String {
        switch self {
        case .вход, .верификация: return ТекстыEgov.т("title_kyc")
        case .подтверждениеВхода: return ТекстыEgov.т("title_confirm")
        case .шаг(_, _, let заголовок, _): return заголовок.isEmpty ? ТекстыEgov.т("otp_title") : заголовок
        }
    }

    var подсказка: String {
        switch self {
        case .вход: return ТекстыEgov.т("hint_login")
        case .подтверждениеВхода: return ТекстыEgov.т("confirm_s")
        case .верификация: return ТекстыEgov.т("hint_kyc")
        case .шаг(_, _, _, let подсказка): return подсказка.isEmpty ? ТекстыEgov.т("otp_hint") : подсказка
        }
    }
}

// MARK: - Запросы

/// Транспорт потока: вошедшему — МоиОбъявленияAPI.отправить (токен кабинета и повтор на «csrf»), гостю — токен гостевой
/// страницы. Оба идут через КабинетСайта.вызвать: куки той же сессии, к которой сервер привязал поток.
@MainActor
enum ЗапросыEgov {
    enum Сбой: Equatable {
        /// Обрыв, нет связи.
        case сеть
        /// Не JSON (страница ошибки хостинга, фатал); код HTTP, если известен.
        case плохой(код: Int)
    }

    enum Ответ {
        case данные([String: Any])
        case сбой(Сбой)
    }

    /// const CSRF гостевой страницы: читается один раз на поток, на «csrf» — заново.
    private static var токенГостя = ""

    static func сброситьГостя() {
        токенГостя = ""
    }

    static func отправить(_ хвост: String, тело: [String: Any], гость: Bool) async -> Ответ {
        do {
            if !гость {
                return .данные(try await МоиОбъявленияAPI.отправить(хвост, тело: тело))
            }
            var повторили = false
            while true {
                if токенГостя.isEmpty {
                    токенГостя = try await КабинетСайта.состояние().csrf
                }
                guard !токенГостя.isEmpty else { return .сбой(.плохой(код: 0)) }
                var полное = тело
                полное["csrf"] = токенГостя
                let ответ = try await КабинетСайта.вызвать(хвост, метод: "POST", тело: полное)
                guard let j = ответ.json else { return .сбой(.плохой(код: ответ.код)) }
                if строка(j["error"]) == "csrf" && !повторили {
                    повторили = true
                    токенГостя = ""
                    continue
                }
                return .данные(j)
            }
        } catch let сбой as КабинетСайта.Сбой {
            switch сбой {
            case .сеть: return .сбой(.сеть)
            case .приложение: return .сбой(.плохой(код: 0))
            }
        } catch {
            return .сбой(.сеть)
        }
    }

    // MARK: Разбор значений — как JS

    nonisolated static func да(_ значение: Any?) -> Bool {
        МоиОбъявленияAPI.да(значение)
    }

    nonisolated static func строка(_ значение: Any?) -> String {
        МоиОбъявленияAPI.строка(значение)
    }

    /// e.ok === false сайта: нет ключа — не false.
    nonisolated static func явноНет(_ значение: Any?) -> Bool {
        if let число = значение as? NSNumber { return число.intValue == 0 }
        if let текст = значение as? String { return текст == "false" || текст == "0" }
        return false
    }

    // MARK: Тексты ошибок — _bioErrText, _bioStartErr, _bioFailText сайта

    /// Причина провала по reason, иначе по error.
    static func причина(_ j: [String: Any]) -> String {
        let ошибка = строка(j["error"])
        let reason = строка(j["reason"])
        let известные: Set<String> = ["face", "otp", "mcdb", "document", "expired", "generic_face"]
        if известные.contains(reason) { return ТекстыEgov.т("fail_" + reason) }
        switch ошибка {
        case "csrf": return ТекстыEgov.т("page_stale")
        case "auth": return ТекстыEgov.т("need_login")
        case "server": return ТекстыEgov.т("srv_err")
        default: break
        }
        if ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка) { return ТекстыEgov.т("not_passed") }
        return ошибка
    }

    /// Сбой запуска: csrf / auth / server — как причина, прочий код — общий текст, иначе текст сервера.
    static func ошибкаЗапуска(_ j: [String: Any]) -> String {
        let ошибка = строка(j["error"])
        if ошибка == "csrf" || ошибка == "auth" || ошибка == "server" { return причина(j) }
        if ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка) { return ТекстыEgov.т("start_fail") }
        return ошибка
    }

    /// Сбой транспорта с «Тех. деталь: HTTP <код> | net».
    static func текстСбоя(_ сбой: Сбой) -> String {
        switch сбой {
        case .сеть:
            return ТекстыEgov.т("net_fail") + "\n\n" + ТекстыEgov.т("tech") + ": net"
        case .плохой(let код):
            return ТекстыEgov.т("srv_err") + "\n\n" + ТекстыEgov.т("tech") + ": HTTP " + String(код)
        }
    }
}

// MARK: - Модель

enum ЭтапПотокаEgov: Equatable {
    case форма
    /// «Проверьте данные» — только верификация.
    case сверка
    case запуск
    /// Экран eGov открыт, идёт опрос.
    case ожидание
    case успех
    case ошибка(заголовок: String, текст: String, повтор: Bool)
}

@MainActor
final class МодельПотокаEgov: ObservableObject {
    /// Окно подтверждения сайта: BIO_WINDOW = 300 с.
    static let окно = 300

    let вид: ВидПотокаEgov
    @Published var иин = ""
    @Published var телефон = ""
    @Published var согласие = false
    @Published private(set) var этап: ЭтапПотокаEgov = .форма
    @Published private(set) var ошибкаФормы: String? = nil
    @Published private(set) var осталось = 300
    @Published private(set) var адресEgov: URL? = nil
    /// Лист с экраном biometric.kz поверх потока.
    @Published var листEgov = false
    @Published var вебГрузится = true
    @Published private(set) var текстУспеха = ""

    /// true — удача (вызывающий доделывает своё), false — закрыли.
    var конец: ((Bool) -> Void)? = nil

    private var таймер: Task<Void, Never>? = nil
    private var поколение = 0
    private var занят = false
    private var плохих = 0
    private var сетевых = 0
    private var закончен = false
    private var заполнено = false

    /// WKWebView экрана eGov живёт в модели: закрыли лист и открыли снова — та же страница, без нового SMS.
    private(set) var вебEgov: WKWebView? = nil
    private var делегатEgov: ДелегатБиометрииEgov? = nil

    init(вид: ВидПотокаEgov) {
        self.вид = вид
        if case .вход(let номер) = вид, !номер.isEmpty {
            телефон = НомерКЗ.формат(номер)
        }
    }

    // MARK: Шаг индикатора: 0 — данные, 1 — eGov, 2 — готово

    var номерШага: Int {
        switch этап {
        case .форма, .сверка, .запуск: return 0
        case .ожидание, .ошибка: return 1
        case .успех: return 2
        }
    }

    var сбой: Bool {
        if case .ошибка = этап { return true }
        return false
    }

    /// Пока идёт проверка, лист не смахивается.
    var идётПроверка: Bool {
        этап == .запуск || этап == .ожидание
    }

    // MARK: Подготовка

    /// CAB_USER.iin и CAB_USER.phone страницы кабинета — как сайт заполняет окно (bioKycOpen, otpStepOpen).
    func подготовить() async {
        if вид.гость { ЗапросыEgov.сброситьГостя() }
        guard !заполнено, !вид.гость else { return }
        заполнено = true
        guard let страница = try? await КабинетСайта.страницаКабинета() else { return }
        let html = страница.html
        guard let начало = html.range(of: "const CAB_USER = {") else { return }
        let хвост = String(html[начало.upperBound...].prefix(6000))
        if иин.isEmpty, let r = хвост.range(of: #"\biin:\s*"[0-9]{12}""#, options: .regularExpression) {
            иин = String(НомерКЗ.цифры(String(хвост[r])).suffix(12))
        }
        if телефон.isEmpty, let r = хвост.range(of: #"\bphone:\s*"[+0-9 ()\-]{10,24}""#, options: .regularExpression) {
            let кусок = String(хвост[r])
            if let кавычка = кусок.firstIndex(of: "\"") {
                let значение = String(кусок[кусок.index(after: кавычка)...]).replacingOccurrences(of: "\"", with: "")
                телефон = НомерКЗ.формат(значение)
            }
        }
    }

    // MARK: Поля

    /// ИИН: только цифры, не больше 12 (oninput сайта).
    func правкаИИН(было: String, стало: String) {
        let чистое = String(НомерКЗ.цифры(стало).prefix(12))
        if чистое != стало { иин = чистое }
    }

    /// Номер — маской сайта при вводе (та же, что у экрана входа).
    func правкаНомера(было: String, стало: String) {
        let верное = ЭкранВхода.ввод(было: было, стало: стало)
        if верное != стало { телефон = верное }
    }

    /// value.replace(/[^\d+]/g, "") сайта; «+7 » без номера — пусто.
    private var номерДляЗапроса: String {
        guard НомерКЗ.цифры(телефон).count > 1 else { return "" }
        return String(телефон.filter { $0 == "+" || ($0.isASCII && $0.isNumber) })
    }

    var номерНаСверке: String {
        let цифры = НомерКЗ.цифры(телефон)
        return цифры.count > 10 ? "+" + цифры : цифры
    }

    // MARK: Кнопки формы

    /// «Продолжить»: проверки сайта, у верификации — сверка, потом запуск.
    func продолжить() {
        guard этап == .форма || этап == .сверка else { return }
        ошибкаФормы = nil
        if вид.сПолями {
            guard иин.count == 12 else {
                ошибкаФормы = ТекстыEgov.т("need_iin")
                return
            }
            let всего = НомерКЗ.цифры(телефон).count
            let цифр = всего > 1 ? всего : 0
            if case .вход = вид {
                /* Гостю номер можно не вводить (восстановление по ИИН), но если введён — полностью. */
                guard цифр == 0 || цифр >= 10 else {
                    ошибкаФормы = ТекстыEgov.т("need_phone")
                    return
                }
                guard согласие else {
                    ошибкаФормы = ТекстыEgov.т("need_agree")
                    return
                }
            } else {
                guard цифр >= 10 else {
                    ошибкаФормы = ТекстыEgov.т("need_phone")
                    return
                }
            }
        }
        if case .верификация = вид, этап == .форма {
            этап = .сверка
            return
        }
        запустить()
    }

    /// «Изменить» на сверке.
    func кФорме() {
        остановитьОкно()
        листEgov = false
        этап = .форма
    }

    private func телоСоздания() -> [String: Any] {
        switch вид {
        case .вход:
            return ["iin": иин, "phone": номерДляЗапроса, "agree": true]
        case .подтверждениеВхода:
            return [:]
        case .верификация:
            return ["iin": иин, "phone": номерДляЗапроса]
        case .шаг(let назначение, let ссылка, _, _):
            return ["purpose": назначение, "ref": ссылка, "iin": иин, "phone": номерДляЗапроса]
        }
    }

    /// Создание потока: один повтор через 3,5 с при обрыве или не-JSON (_bioPost с retry сайта).
    private func запустить() {
        этап = .запуск
        let хвост = вид.создание
        let тело = телоСоздания()
        let гость = вид.гость
        Task { @MainActor [weak self] in
            var ответ = await ЗапросыEgov.отправить(хвост, тело: тело, гость: гость)
            if case .сбой = ответ {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                guard let живая = self, живая.этап == .запуск else { return }
                ответ = await ЗапросыEgov.отправить(хвост, тело: тело, гость: гость)
            }
            guard let self, self.этап == .запуск else { return }
            self.принятьСоздание(ответ)
        }
    }

    private func принятьСоздание(_ ответ: ЗапросыEgov.Ответ) {
        switch ответ {
        case .сбой(let сбой):
            неЗапустился(ЗапросыEgov.текстСбоя(сбой))
        case .данные(let j):
            let сессия = ЗапросыEgov.строка(j["session_id"])
            if ЗапросыEgov.да(j["ok"]) && !сессия.isEmpty, let адрес = МодельПотокаEgov.адресEgov(сессия) {
                адресEgov = адрес
                сброситьВеб()
                этап = .ожидание
                листEgov = true
                запуститьОкно()
                return
            }
            if case .вход = вид, ЗапросыEgov.да(j["need_phone"]) {
                этап = .форма
                ошибкаФормы = ТекстыEgov.т("need_phone")
                return
            }
            if ЗапросыEgov.да(j["iin_taken"]) {
                let текст = ЗапросыEgov.строка(j["error"])
                провал(заголовок: ТекстыEgov.т("iin_taken_t"),
                       текст: текст.isEmpty || КабинетСайта.машинныйКод(текст) ? ТекстыEgov.т("iin_taken") : текст,
                       повтор: false)
                return
            }
            var текст = ЗапросыEgov.ошибкаЗапуска(j)
            let деталь = ЗапросыEgov.строка(j["diag"])
            if !деталь.isEmpty { текст += "\n\n" + ТекстыEgov.т("tech") + ": " + деталь }
            неЗапустился(текст)
        }
    }

    /// Гостю — строка ошибки под кнопкой (_egErr), вошедшему — окно «Не удалось» с «Повторить» (bioAlert).
    private func неЗапустился(_ текст: String) {
        if вид.гость {
            этап = .форма
            ошибкаФормы = текст
        } else {
            провал(заголовок: ТекстыEgov.т("alert_title"), текст: текст, повтор: true)
        }
    }

    private static func адресEgov(_ сессия: String) -> URL? {
        let часть = сессия.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? сессия
        return URL(string: "https://remote.biometric.kz/flow/" + часть + "?locale=" + ТекстыEgov.языкEgov)
    }

    // MARK: Окно и опрос

    /// Отсчёт 300 с; опрос каждые 3 с, с последних 240 с — каждые 6 с (_bioTick, _bioPollTick).
    private func запуститьОкно() {
        остановитьОкно()
        осталось = МодельПотокаEgov.окно
        плохих = 0
        сетевых = 0
        занят = false
        поколение += 1
        let моё = поколение
        таймер = Task { @MainActor [weak self] in
            var доОпроса = 3
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled, self.поколение == моё, self.этап == .ожидание else { return }
                self.осталось -= 1
                if self.осталось <= 0 {
                    self.провал(заголовок: ТекстыEgov.т("alert_title"), текст: ТекстыEgov.т("timeout"), повтор: true)
                    return
                }
                доОпроса -= 1
                if доОпроса <= 0 {
                    доОпроса = self.осталось > МодельПотокаEgov.окно - 60 ? 3 : 6
                    self.опросить()
                }
            }
        }
    }

    /// Внеочередной опрос: postMessage от biometric.kz, лист eGov закрыли, приложение вернулось на экран.
    func толкнуть() {
        guard этап == .ожидание else { return }
        сетевых = 0
        опросить()
    }

    private func опросить() {
        guard этап == .ожидание, !занят else { return }
        занят = true
        let моё = поколение
        let хвост = вид.итог
        let тело = вид.телоИтога
        let гость = вид.гость
        Task { @MainActor [weak self] in
            let ответ = await ЗапросыEgov.отправить(хвост, тело: тело, гость: гость)
            guard let self, self.поколение == моё else { return }
            self.занят = false
            guard self.этап == .ожидание else { return }
            self.разобрать(ответ)
        }
    }

    private func разобрать(_ ответ: ЗапросыEgov.Ответ) {
        switch ответ {
        case .сбой(let сбой):
            switch сбой {
            case .сеть:
                /* Как у сайта: сбои сети считаются, только пока экран виден. */
                guard UIApplication.shared.applicationState == .active else { return }
                сетевых += 1
                if сетевых >= 5 {
                    провал(заголовок: ТекстыEgov.т("alert_title"), текст: ЗапросыEgov.текстСбоя(сбой), повтор: true)
                }
            case .плохой:
                сетевых = 0
                плохих += 1
                if плохих >= 3 {
                    провал(заголовок: ТекстыEgov.т("alert_title"), текст: ЗапросыEgov.текстСбоя(сбой), повтор: true)
                }
            }
        case .данные(let j):
            плохих = 0
            сетевых = 0
            if ЗапросыEgov.явноНет(j["ok"]) && !ЗапросыEgov.да(j["pending"]) {
                провал(заголовок: ТекстыEgov.т("alert_title"), текст: ЗапросыEgov.причина(j), повтор: true)
                return
            }
            guard ЗапросыEgov.да(j["ok"]) else { return }
            if ЗапросыEgov.да(j["verified"]) {
                удача(существующий: ЗапросыEgov.да(j["existing"]))
                return
            }
            if ЗапросыEgov.да(j["final"]) {
                провал(заголовок: ТекстыEgov.т("alert_title"), текст: ЗапросыEgov.причина(j), повтор: true)
            }
        }
    }

    // MARK: Итог

    private func удача(существующий: Bool) {
        остановитьОкно()
        листEgov = false
        ОткликСайта.успех()
        switch вид {
        case .шаг:
            текстУспеха = ТекстыEgov.т("step_ok")
            этап = .успех
            /* Сайт сразу зовёт колбэк действия: короткая галочка — и дальше. */
            закончитьПозже(удача: true, через: 900_000_000)
        case .вход, .подтверждениеВхода:
            let новый = !существующий && вид != .подтверждениеВхода
            текстУспеха = ТекстыEgov.т(новый ? "ok_new" : "ok_login")
            этап = .успех
            закончитьПозже(удача: true, через: 1_200_000_000)
        case .верификация:
            текстУспеха = ТекстыEgov.т("succ_msg")
            этап = .успех
        }
    }

    private func провал(заголовок: String, текст: String, повтор: Bool) {
        остановитьОкно()
        листEgov = false
        ОткликСайта.предупреждение()
        этап = .ошибка(заголовок: заголовок, текст: текст, повтор: повтор)
    }

    /// «Повторить»: снова форма (гостю и шагу — с тем, что введено).
    func повторить() {
        кФорме()
    }

    /// Закрыть кнопкой: после удачи — это удача (верификация уже прошла).
    func закрыть() {
        закончить(удача: этап == .успех)
    }

    /// «Готово» на экране успеха.
    func готово() {
        закончить(удача: true)
    }

    private func закончитьПозже(удача: Bool, через паузу: UInt64) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: паузу)
            self?.закончить(удача: удача)
        }
    }

    private func закончить(удача: Bool) {
        guard !закончен else { return }
        закончен = true
        остановить()
        конец?(удача)
    }

    private func остановитьОкно() {
        таймер?.cancel()
        таймер = nil
        поколение += 1
        занят = false
    }

    /// Экран ушёл: опрос стоп, страница eGov — пустая.
    func остановить() {
        остановитьОкно()
        листEgov = false
        сброситьВеб()
    }

    // MARK: WKWebView экрана eGov

    /// Одна страница на запуск потока: новый session_id — новая страница.
    func веб() -> WKWebView {
        if let вебEgov { return вебEgov }
        let делегат = ДелегатБиометрииEgov(модель: self)
        let веб = ВебБиометрииEgov.создать(делегат: делегат)
        if let адресEgov { веб.load(URLRequest(url: адресEgov)) }
        делегатEgov = делегат
        вебEgov = веб
        return веб
    }

    private func сброситьВеб() {
        guard let веб = вебEgov else { return }
        веб.stopLoading()
        веб.navigationDelegate = nil
        веб.uiDelegate = nil
        веб.configuration.userContentController.removeScriptMessageHandler(forName: ВебБиометрииEgov.имяСигнала)
        вебEgov = nil
        делегатEgov = nil
        вебГрузится = true
    }
}

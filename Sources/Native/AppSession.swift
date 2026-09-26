import Foundation
import UIKit
import WebKit

/**
 ЕДИНОЕ СОСТОЯНИЕ ВХОДА — ВИТРИНА И КАБИНЕТ ВИДЯТ ОДНО И ТО ЖЕ (TestFlight 1.10, владелец: «витрина и кабинет не
 общаются между собой — зашёл или вышел. Видно в баннерах: просит регу через eGov, хотя я зашёл уже»).

 Почему так было. «Гость или вошёл» решал каждый экран сам и только на своём показе: кабинет держал своё @State (по
 SiteSession и странице кабинета), чат и заявки — ответ сервера «нужен вход», избранное и подписки — свою отметку.
 Витрина не спрашивала вовсе: слайды баннера главной (БаннерГлавной, ЛистСлайдаГлавной) перенесены со снимка главной
 гостя, и кнопка «Регистрация продавца через eGov» стояла в них для всех. Вход своим экраном перезагружает страницу под
 слоем, выход на сайте — мост klikoLogout и bye=1: ни то, ни другое не доходило до уже открытых нативных экранов.

 Теперь одно место — СессияПриложения.shared (@MainActor, ObservableObject):
   · вошёл, id, имя, продавецПодтверждён (IS_VERIFIED / CAB_IS_VERIFIED / CAB_USER.verified кабинета), магазин
     (IS_SHOP), eGovВключён (BIO_ON); смена — растёт при каждой смене человека (вход, выход, другой аккаунт);
   · сверяется: при старте и возврате приложения (didBecomeActive), после каждой загрузки страницы сайта (WebContainer,
     с отсрочкой — много загрузок подряд дают одну сверку), после входа и регистрации своим экраном
     (КабинетСайта.послеВхода), с каждой прочитанной страницы кабинета (КабинетСайта.состояние / страницаКабинета —
     её читают кабинет, объявления, сделки, кошелёк), после eGov (возврат на kliko.kz с чужой страницы);
   · выход (мост klikoLogout, нативная кнопка, ВыходНачисто) — сразу гость, и ответ, начатый до выхода, не примется
     (поколение).

 Правила баннеров (.mh-bn / .hp-p главной, карта кабинета §1.7.1 и сводка ?go=): гостю — «Регистрация продавца через
 eGov» (?egov=1 — окно eGov гостевой страницы; ?go=egov у гостя ничего не делает), вошедшему без проверки — «Пройти
 верификацию» (?go=egov → requestVerification), проверенному продавцу — «Разместить объявление» (?go=add). Проверенному
 регистрацию через eGov не показываем никогда.

 Подсказка на холодный старт (вошёл и проверен — два признака, без номера и имени) лежит в UserDefaults, чтобы до
 загрузки страницы витрина не просила регистрацию у вошедшего; выход её стирает.
 */
@MainActor
final class СессияПриложения: ObservableObject {
    static let shared = СессияПриложения()

    /// Что видит человек на баннерах и листах витрины.
    enum Роль: Equatable {
        case гость
        case вошёл
        case продавец
    }

    /// nil — ещё не знаем (страница не загрузилась, подсказки нет).
    @Published private(set) var вошёл: Bool? = nil
    /// KlikoUser.id вошедшего («u<12 hex>»); у гостя пусто.
    @Published private(set) var id: String = ""
    /// CAB_USER.name — если страница кабинета его уже отдала.
    @Published private(set) var имя: String = ""
    /// Прошёл eGov-верификацию (IS_VERIFIED кабинета).
    @Published private(set) var продавецПодтверждён: Bool = false
    /// IS_SHOP кабинета.
    @Published private(set) var магазин: Bool = false
    /// BIO_ON кабинета: eGov настроен.
    @Published private(set) var eGovВключён: Bool = true
    /// Растёт при каждой смене человека: вход, выход, другой аккаунт. Экранам гостя — повод перечитать себя.
    @Published private(set) var смена: Int = 0

    var роль: Роль {
        guard вошёл == true else { return .гость }
        return продавецПодтверждён ? .продавец : .вошёл
    }

    /// Растёт при выходе: ответ, начатый до выхода, не примется.
    private(set) var поколение = 0
    private var отложенное: Task<Void, Never>? = nil
    /// Следующая сверка обязана перечитать страницу кабинета (вход, выход, eGov, переход на cabinet.php).
    private var нуженКабинет = false
    /// Когда признаки кабинета (проверка, магазин) последний раз сверены — и для кого.
    private var кабинетСверен: Date? = nil
    private var кабинетДля = ""
    /// Прошлая страница была не на kliko.kz (eGov, банк) — вернулись: перечитать кабинет.
    private var былаЧужая = false
    private var наблюдатель: NSObjectProtocol? = nil

    private static let ключПодсказки = "kliko.session.hint"
    /// Признаки кабинета на витрине не видны: берём их со страницы кабинета не чаще раза в 10 минут на человека.
    private static let срокКабинета: TimeInterval = 600

    private init() {
        if let подсказка = UserDefaults.standard.dictionary(forKey: Self.ключПодсказки),
           (подсказка["in"] as? Bool) == true {
            вошёл = true
            продавецПодтверждён = (подсказка["v"] as? Bool) ?? false
        }
        наблюдатель = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                            object: nil, queue: .main) { _ in
            Task { @MainActor in СессияПриложения.shared.запросить() }
        }
        if WebBridge.shared.isLoaded { запросить(через: 0.1) }
    }

    // MARK: - Поводы

    /// Отложенная сверка: поводы подряд (загрузка страницы, возврат в приложение) сливаются в одну.
    func запросить(кабинет: Bool = false, через секунды: Double = 0.6) {
        if кабинет { нуженКабинет = true }
        отложенное?.cancel()
        let пауза = UInt64(max(0, секунды) * 1_000_000_000)
        отложенное = Task { @MainActor in
            try? await Task.sleep(nanoseconds: пауза)
            guard !Task.isCancelled else { return }
            await СессияПриложения.shared.сверить()
        }
    }

    /// WebContainer: страница загрузилась. Кабинет, возврат с eGov или банка — сверка с кабинетом.
    func страницаЗагрузилась(_ адрес: URL?) {
        guard let адрес else { return }
        let хост = (адрес.host ?? "").lowercased()
        let наСайте = хост == "kliko.kz" || хост == "www.kliko.kz"
        guard наСайте else {
            былаЧужая = true
            return
        }
        let путь = адрес.path.lowercased()
        let кабинет = путь.range(of: "/cabinet(\\.php)?/?$", options: .regularExpression) != nil
        /* bye=1 — страница выхода: гость уже выставлен мостом klikoLogout; сверка подтвердит. */
        if (адрес.query ?? "").contains("bye=1") { вышел() }
        запросить(кабинет: кабинет || былаЧужая)
        былаЧужая = false
    }

    /// Вход или регистрация своим экраном: сервер ответил ok — вошёл сразу, признаки — со страницы кабинета.
    func вошёлСвоимЭкраном(uid: String) {
        let прежний = id
        вошёл = true
        if !uid.isEmpty { id = uid }
        if прежний != id || прежний.isEmpty { смена += 1 }
        запомнитьПодсказку()
        /* Страница под слоем перезагружается (послеВхода): кабинет — после неё. */
        запросить(кабинет: true, через: 1.2)
    }

    /// Выход — мост klikoLogout, нативная кнопка, ВыходНачисто, страница bye=1. Сразу гость, всё прежнее — прочь.
    func вышел() {
        поколение += 1
        отложенное?.cancel()
        отложенное = nil
        кабинетСверен = nil
        кабинетДля = ""
        UserDefaults.standard.removeObject(forKey: Self.ключПодсказки)
        let был = вошёл != false || !id.isEmpty
        if вошёл != false { вошёл = false }
        if !id.isEmpty { id = "" }
        if !имя.isEmpty { имя = "" }
        if продавецПодтверждён { продавецПодтверждён = false }
        if магазин { магазин = false }
        if был { смена += 1 }
    }

    // MARK: - Страница кабинета (КабинетСайта.состояние)

    /**
     Что напечатала страница кабинета — её читают кабинет, объявления, сделки, кошелёк и сама сверка. поколение — снятое
     до запроса: выход, случившийся, пока страница шла, её ответ отменяет.
     */
    func принять(_ страница: КабинетСайта.Состояние, поколение снятое: Int) {
        guard снятое == поколение, let известно = страница.вошёл else { return }
        guard известно else {
            вышелПоСтранице()
            return
        }
        применитьВход(id: страница.uid)
        if !страница.имя.isEmpty, имя != страница.имя { имя = страница.имя }
        if продавецПодтверждён != страница.верифицирован { продавецПодтверждён = страница.верифицирован }
        if магазин != страница.магазин { магазин = страница.магазин }
        if eGovВключён != страница.eGovВключён { eGovВключён = страница.eGovВключён }
        кабинетСверен = Date()
        кабинетДля = id
        запомнитьПодсказку()
    }

    // MARK: - Сверка

    /// Страница под слоем говорит сама; признаки кабинета на витрине не видны — тогда страница кабинета (не чаще срока).
    func сверить() async {
        let снятое = поколение
        if нуженКабинет {
            /* Вход, выход, eGov: страница под слоем могла остаться прежней — свежее спросить сам кабинет. Страница ещё
               грузится (вход её перезагружает) — просьба остаётся до следующей сверки (её позовёт загрузка). Ответ
               кабинета уже принят внутри КабинетСайта.состояние. */
            if let кабинет = try? await КабинетСайта.состояние(ждать: false), кабинет.вошёл != nil {
                if снятое == поколение { нуженКабинет = false }
                return
            }
        }
        let страница = await Self.прочитатьСтраницу()
        guard снятое == поколение else { return }
        guard let страница, let известно = страница.вошёл else { return }
        guard известно else {
            вышелПоСтранице()
            return
        }
        применитьВход(id: страница.id)
        if !страница.имя.isEmpty, имя != страница.имя { имя = страница.имя }
        if let проверен = страница.проверен {
            /* Страница кабинета: признаки на ней самой. */
            if продавецПодтверждён != проверен { продавецПодтверждён = проверен }
            if let м = страница.магазин, магазин != м { магазин = м }
            if let bio = страница.eGov, eGovВключён != bio { eGovВключён = bio }
            кабинетСверен = Date()
            кабинетДля = id
            запомнитьПодсказку()
            return
        }
        запомнитьПодсказку()
        let свежо = кабинетДля == id && (кабинетСверен.map { Date().timeIntervalSince($0) < Self.срокКабинета } ?? false)
        if !свежо {
            /* Ответ принимает сам КабинетСайта.состояние (с поколением, снятым до запроса). */
            _ = try? await КабинетСайта.состояние(ждать: false)
        }
    }

    /// Вошёл (возможно, другим аккаунтом): другой номер — признаки прежнего прочь.
    private func применитьВход(id новый: String) {
        let другой = !новый.isEmpty && !id.isEmpty && новый != id
        let было = вошёл
        if другой {
            имя = ""
            продавецПодтверждён = false
            магазин = false
            кабинетСверен = nil
            кабинетДля = ""
        }
        if вошёл != true { вошёл = true }
        if !новый.isEmpty, id != новый { id = новый }
        if было != true || другой { смена += 1 }
    }

    /// Страница сказала «гость» (выход на другом устройстве, сессия истекла): то же, что выход, без стирания данных —
    /// их стирает ВыходНачисто по своей дороге.
    private func вышелПоСтранице() {
        guard вошёл != false || !id.isEmpty else { return }
        вышел()
    }

    private func запомнитьПодсказку() {
        guard вошёл == true else { return }
        UserDefaults.standard.set(["in": true, "v": продавецПодтверждён], forKey: Self.ключПодсказки)
    }

    // MARK: - Страница под слоем

    private struct ПризнакиСтраницы {
        let вошёл: Bool?
        let id: String
        let имя: String
        /// nil — страница не кабинет, признаков проверки на ней нет.
        let проверен: Bool?
        let магазин: Bool?
        let eGov: Bool?
    }

    /**
     Те же признаки входа, что SiteSession.состояние (непустой KlikoUser.id, _MK_AUTH витрины, __ULX_GUEST кабинета), и
     признаки кабинета, если это он: IS_VERIFIED (запасные — CAB_IS_VERIFIED, CAB_USER.verified), IS_SHOP, BIO_ON,
     CAB_USER.name. const и let верхнего уровня не свойства window — только по имени, через typeof (ReferenceError до
     объявления ловит try).
     */
    private static let скриптСтраницы = """
    (function(){try{
    var u=window.KlikoUser,id=(u&&u.id!=null)?String(u.id):'';
    var a=(typeof _MK_AUTH!=='undefined')?((_MK_AUTH&&_MK_AUTH!=='0')?1:0):-1;
    var g=(typeof window.__ULX_GUEST==='boolean')?(window.__ULX_GUEST?1:0):-1;
    var v=(id||a===1||g===0)?1:((u||a===0||g===1)?0:-1);
    var m=id;if(!m&&v===1){try{m=localStorage.getItem('ulx_me_id')||'';}catch(e){}}
    function f(x){return x===true?1:(x===false?0:-1);}
    var cu=null;try{cu=(typeof CAB_USER!=='undefined'&&CAB_USER)?CAB_USER:null;}catch(e){}
    var ver=-1;try{if(typeof IS_VERIFIED!=='undefined')ver=f(IS_VERIFIED);}catch(e){}
    if(ver<0){try{if(typeof CAB_IS_VERIFIED!=='undefined')ver=f(CAB_IS_VERIFIED);}catch(e){}}
    if(ver<0&&cu&&typeof cu.verified==='boolean')ver=f(cu.verified);
    var sh=-1;try{if(typeof IS_SHOP!=='undefined')sh=f(IS_SHOP);}catch(e){}
    var bio=-1;try{if(typeof BIO_ON!=='undefined')bio=f(BIO_ON);}catch(e){}
    var n=(cu&&cu.name!=null)?String(cu.name):'';
    return JSON.stringify({v:v,m:String(m||''),ver:ver,sh:sh,bio:bio,n:n});
    }catch(e){return '{}';}})()
    """

    private static func прочитатьСтраницу() async -> ПризнакиСтраницы? {
        guard let web = WebBridge.shared.webView, WebBridge.shared.isLoaded, !web.isLoading else { return nil }
        guard let адрес = web.url, let хост = адрес.host?.lowercased(), хост == "kliko.kz" || хост == "www.kliko.kz" else {
            return nil
        }
        guard let строка = try? await web.evaluateJavaScript(скриптСтраницы) as? String,
              let данные = строка.data(using: .utf8),
              let словарь = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else {
            return nil
        }
        func признак(_ ключ: String) -> Bool? {
            switch (словарь[ключ] as? NSNumber)?.intValue ?? -1 {
            case 1: return true
            case 0: return false
            default: return nil
            }
        }
        let вошёл = признак("v")
        let номер = ((словарь["m"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let имя = ((словарь["n"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ПризнакиСтраницы(вошёл: вошёл, id: вошёл == true ? номер : "", имя: вошёл == true ? имя : "",
                                проверен: признак("ver"), магазин: признак("sh"), eGov: признак("bio"))
    }
}

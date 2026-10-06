import Foundation
import WebKit

/**
 ОСНОВА КАБИНЕТА: СОСТОЯНИЕ СТРАНИЦЫ, ВХОД, РЕГИСТРАЦИЯ, ВЫХОД, СЕАНС — ЭТАП 40 (владелец 26.09.2026: «всё одно и то же,
 просто код разный»).

 Всё по карте кабинета (/tmp/claude-0/cabinet-map.md, §0–§1, §8.2) — тела запросов и порядок ответов те же, что у
 гостевой страницы cabinet.php (doLogin, doQuickRegister) и у кабинета вошедшего (klikoLogout, termsRenewGate).

 🔴 ЗАПРОСЫ — ИЗНУТРИ WKWEBVIEW, А НЕ URLSESSION. Вход создаёт сессию: сервер отвечает Set-Cookie (kliko_cab, по снимку
 __SESS_SNAP), и эти куки нужны сразу всем — странице под нативным слоем, мосту пушей, нативным запросам (SiteSession.куки
 читает хранилище WebKit). Было два пути:
   · URLSession, потом переложить Set-Cookie в WKWebsiteDataStore.default().httpCookieStore. Кук HttpOnly/Secure/SameSite
     с их сроками пришлось бы собирать заново из заголовков (HTTPCookie.cookies(withResponseHeaderFields:) теряет часть
     атрибутов), setCookie асинхронен и доходит до сетевого процесса WebKit не сразу — следующий запрос страницы мог уйти
     со старой гостевой кукой; а гостевую сессию, к которой привязан CSRF входа, пришлось бы сначала вынести из WebKit
     в URLSession. Три места, где сессии могут разойтись.
   · fetch в самой странице (callAsyncJavaScript). Куки ставит и читает сам WebKit, в том же хранилище, что и у страницы:
     гостевая кука, на которую выдан токен, уходит с запросом входа, новая кука сессии ложится туда же и сразу видна
     всем. Origin и Referer настоящие (сервер их проверяет — «Ошибка источника запроса», §0.4), тело то же, что шлёт сайт.
   Выбран второй. 28.09.2026 первый путь добавлен за рубильником Config.нативнаяСессия (выключен):
   НативныйТранспортКабинета (NativeCabinetTransport.swift) с запасным ходом сюда же, если сессию не узнали.
   Скрипт идёт в отдельном мире (.defaultClient): скрипты страницы не видят ни номера, ни пароля и не
   могут подменить fetch; общие у миров только DOM, куки и localStorage — ровно то, что нужно. Номер и пароль передаются
   аргументами, а не вклеиваются в текст скрипта: никакой символ пароля не станет кодом.

 Страница под нативным слоем должна быть страницей kliko.kz: у другой (платёжный шлюз, eGov) — чужой источник. Тогда
 сначала грузим главную сайта и ждём её (страницаСайта).

 CSRF (§0.2): отдельного API нет, токен читается со страницы кабинета — GET /kz/<язык>/cabinet.php: у вошедшего
 window.KlikoCsrf, у гостя — const CSRF / window.__UIP_CSRF (KlikoCsrf у гостя пустой). После входа страница
 перечитывается (токен, по-видимому, меняется — INFERRED в карте). На «csrf» не денежный запрос повторяется один раз со
 свежим токеном (§8.0.3); денежных здесь нет.
 */
@MainActor
enum КабинетСайта {

    enum Сбой: Error, Equatable {
        /// fetch бросил TypeError или страница сайта недоступна — «Нет соединения», как у сайта.
        case сеть
        /// Любое другое исключение или не-JSON — «Ошибка приложения. Обновите страницу и попробуйте ещё раз».
        case приложение
    }

    /// Что сервер вписал в страницу кабинета (§0.7): API «кто я» у сайта нет.
    struct Состояние: Equatable {
        /// nil — страница не сказала (не кабинет, ошибка сервера).
        var вошёл: Bool?
        /// KlikoUser.id вошедшего («u<12 hex>»); у гостя пусто.
        var uid: String = ""
        /// Токен сессии: KlikoCsrf || const CSRF || __UIP_CSRF.
        var csrf: String = ""
        /// CAB_USER.name — как его показывает шапка кабинета сайта.
        var имя: String = ""
        /// const BIO_ON: вход и восстановление через eGov включены (от него зависит текст «Восстановить доступ»).
        var eGovВключён: Bool = true
        /// window.__TERMS_RENEW: новая редакция соглашения ждёт согласия (§1.6).
        var новоеСоглашение: Bool = false
        /// window.__TERMS_VER — «Редакция от …».
        var редакция: String = ""
        /// window.__TERMS_WHAT — что изменилось.
        var чтоИзменилось: [String] = []
        /// Этап 41: const IS_SHOP — магазин: на карточке «Моих объявлений» есть склад (advStockHTML).
        var магазин: Bool = false
        /// Этап 41: const IS_VERIFIED — прошёл eGov-верификацию.
        var верифицирован: Bool = false
        /// Этап 41: const ADV_STATUS_LABEL — подпись зелёного значка опубликованного («Одобрено»). Сервер может её сменить
        /// («Активно», «В продаже»), поэтому берём со страницы, а не из словаря (карта §3.5).
        var подписьОдобрено: String = ""
        /// Этап 41: window.CAB_AI — Kliko AI в карточке «Доступно» над списком объявлений.
        var ии: КвотаИИ? = nil
    }

    /// window.CAB_AI (U @167865): квота Kliko AI и её подписи — сервер пишет их сам, на языке страницы.
    struct КвотаИИ: Equatable {
        var показать: Bool = false
        var оплачено: Bool = false
        var бесплатно: Bool = false
        var лимит: Int = 0
        var осталось: Int = 0
        var верифицирован: Bool = false
        /// «Kliko AI-ассистент», «Безлимит», «Осталось», «Верификация», «Пакет Kliko AI», free_t / free_s.
        var название: String = ""
        var безлимит: String = ""
        var осталосьПодпись: String = ""
        var кнопкаВерификации: String = ""
        var кнопкаПакета: String = ""
        var бесплатноЗаголовок: String = ""
        var бесплатноПодпись: String = ""
    }

    // MARK: - Состояние страницы кабинета

    /**
     GET /kz/<язык>/cabinet.php с куками сессии и разбор того, что напечатал сервер. ждать = false — страница под слоем
     сейчас грузится или не на сайте: не ждём, а сразу «не удалось» (кабинет перечитывает состояние на каждом показе и
     не должен висеть). ждать = true — после входа и перед записью: ждём страницу до 15 с.
     */
    static func состояние(ждать: Bool = true) async throws -> Состояние {
        /* Скорость: экраны, спросившие разом (кабинет, мои объявления, сделки, значки на запуске), ждут одну страницу
           кабинета, а не качают её каждый свою. Ответ не запоминается: следующий вопрос — снова свежая страница. */
        if let идёт = состояниеВПути[ждать], идёт.сессия == СессияПриложения.shared.поколение {
            return try await идёт.задача.value
        }
        номерСостояния += 1
        let номер = номерСостояния
        let задача = Task<Состояние, Error> { try await КабинетСайта.состояниеСети(ждать: ждать) }
        состояниеВПути[ждать] = (номер: номер, сессия: СессияПриложения.shared.поколение, задача: задача)
        defer { if состояниеВПути[ждать]?.номер == номер { состояниеВПути[ждать] = nil } }
        return try await задача.value
    }

    /// Скорость: чтение страницы кабинета в пути — по ждать; номер — чтобы не убрать чужое, более новое; сессия —
    /// поколение СессияПриложения: начатое до выхода из аккаунта новому вопросу не отдаём.
    private static var состояниеВПути: [Bool: (номер: Int, сессия: Int, задача: Task<Состояние, Error>)] = [:]
    private static var номерСостояния = 0

    private static func состояниеСети(ждать: Bool) async throws -> Состояние {
        let поколение = СессияПриложения.shared.поколение
        let ответ = try await запрос(путь("cabinet.php"), ждать: ждать)
        guard ответ.код > 0, ответ.код < 500 else { throw Сбой.сеть }
        let с = разобрать(ответ.текст)
        /* TestFlight 1.10: каждая прочитанная страница кабинета — в общее состояние входа (витрина видит то же). */
        СессияПриложения.shared.принять(с, поколение: поколение)
        return с
    }

    /**
     Этап 42: та же страница кабинета, но и её текст целиком. Мастеру подачи нужны значения, которые сервер печатает
     только в неё (CAB_PREF_GEO, CAB_PREF_HOURS, TRUST_SETS, PROMO_CFG, MK_ESCROW_MIN, адреса js/cats-<язык>.js и
     js/cab-refs.js, карта §0.7). Второй раз страницу ради них не качаем.
     */
    static func страницаКабинета(ждать: Bool = true) async throws -> (состояние: Состояние, html: String) {
        /* Этап 45: ждать = false — вкладка «Кабинет» берёт отсюда и колокольчик (список уведомлений есть только в HTML
           страницы, §6.3.1) и CHAT_PINS, не уводя страницу под слоем на главную. */
        let поколение = СессияПриложения.shared.поколение
        let ответ = try await запрос(путь("cabinet.php"), ждать: ждать)
        guard ответ.код > 0, ответ.код < 500 else { throw Сбой.сеть }
        let с = разобрать(ответ.текст)
        СессияПриложения.shared.принять(с, поколение: поколение)
        return (с, ответ.текст)
    }

    // MARK: - Этап 42: загрузка фото объявления (upload_photo, карта §2.4.3)

    /// Итог загрузки: HTTP-код последней попытки и ответ сервера. Все три попытки без ответа — json с ok:false.
    struct ОтветЗагрузки {
        let код: Int
        let json: [String: Any]
    }

    /**
     uploadImageSmart сайта: три попытки подряд, пока одна не вернёт ok (или prohibited / foreign): multipart с imgb64
     (dataURL), multipart с файлом photo.jpg, JSON {csrf, image_b64}. После удачи первой — миниатюра тем же адресом
     (multipart imgb64 + thumb_for = имя файла из url), ответ миниатюры не нужен, как у сайта. Картинка и токен идут
     аргументами скрипта, а не текстом: ни байт фото, ни токен не станут кодом. Путь — /kz/<язык>/cabinet.php (§0.3).
     */
    static func загрузитьФото(картинка: String, миниатюра: String, токен: String) async throws -> ОтветЗагрузки {
        /* Config.нативнаяСессия: те же попытки через URLSession; не узнали сессию — прежним путём, ниже. */
        if Config.нативнаяСессия,
           let итог = await НативныйТранспортКабинета.загрузитьФото(путь("cabinet.php?action=upload_photo"),
                                                                    картинка: картинка, миниатюра: миниатюра,
                                                                    токен: токен) {
            return ОтветЗагрузки(код: итог.код, json: итог.json)
        }
        let web = try await страницаСайта(ждать: true)
        let аргументы: [String: Any] = ["p": путь("cabinet.php?action=upload_photo"), "c": токен, "d": картинка,
                                        "th": миниатюра]
        let сырой: String = try await withCheckedThrowingContinuation { (продолжение: CheckedContinuation<String, Error>) in
            web.callAsyncJavaScript(скриптЗагрузки, arguments: аргументы, in: nil, in: .defaultClient) { итог in
                switch итог {
                case .success(let значение):
                    продолжение.resume(returning: (значение as? String) ?? "")
                case .failure(let ошибка):
                    продолжение.resume(throwing: ошибка)
                }
            }
        }
        guard let данные = сырой.data(using: .utf8),
              let объект = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else {
            throw Сбой.приложение
        }
        let код = (объект["s"] as? NSNumber)?.intValue ?? 0
        let ответ = (объект["o"] as? [String: Any]) ?? ["ok": false, "error": ""]
        return ОтветЗагрузки(код: код, json: ответ)
    }

    /// Тело скрипта загрузки: p — путь, c — токен, d — dataURL фото, th — dataURL миниатюры (пусто — без неё).
    private static let скриптЗагрузки = """
    let code = 0, err = '';
    const opts = (body, json) => {
      const o = {method: 'POST', body: body, credentials: 'same-origin', cache: 'no-store'};
      if (json) { o.headers = {'Content-Type': 'application/json'}; }
      return o;
    };
    const read = async (r) => { try { return JSON.parse(await r.text()); } catch (e) { return null; } };
    const toBlob = (du) => {
      const i = du.indexOf(',');
      const head = du.slice(5, i);
      const type = head.split(';')[0] || 'image/jpeg';
      const s = atob(du.slice(i + 1));
      const a = new Uint8Array(s.length);
      for (let k = 0; k < s.length; k++) { a[k] = s.charCodeAt(k); }
      return new Blob([a], {type: type});
    };
    try {
      const f = new FormData();
      f.append('csrf', c);
      f.append('imgb64', d);
      const r = await fetch(p, opts(f, false));
      code = r.status;
      if (r.ok) {
        const o = await read(r);
        if (o && o.ok && o.url && th) {
          try {
            const n = String(o.url).split('/').pop();
            if (n) {
              const g = new FormData();
              g.append('csrf', c);
              g.append('imgb64', th);
              g.append('thumb_for', n);
              await fetch(p, opts(g, false));
            }
          } catch (e) {}
        }
        if (o && (o.ok || o.prohibited || o.foreign)) { return JSON.stringify({s: code, o: o}); }
        if (o && o.error) { err = String(o.error); }
      }
    } catch (e) {}
    try {
      const f = new FormData();
      f.append('csrf', c);
      const b = toBlob(d);
      f.append('photo', b, b.type === 'image/webp' ? 'photo.webp' : 'photo.jpg');
      const r = await fetch(p, opts(f, false));
      code = r.status;
      if (r.ok) {
        const o = await read(r);
        if (o && (o.ok || o.prohibited || o.foreign)) { return JSON.stringify({s: code, o: o}); }
        if (o && o.error) { err = String(o.error); }
      }
    } catch (e) {}
    try {
      const r = await fetch(p, opts(JSON.stringify({csrf: c, image_b64: d}), true));
      code = r.status;
      if (r.ok) {
        const o = await read(r);
        if (o && (o.ok || o.prohibited)) { return JSON.stringify({s: code, o: o}); }
        if (o && o.error) { err = String(o.error); }
      }
    } catch (e) {}
    return JSON.stringify({s: code, o: {ok: false, error: err}});
    """

    // MARK: - Вход (§1.2.1)

    enum ИтогВхода: Equatable {
        case вошёл
        /// Пароль верный, но включена защита входа: подтвердить через eGov (§1.2.5) — окно на странице сайта.
        case нуженEgov
        /// Аккаунт удалён — окно «Аккаунт удалён» с причиной.
        case удалён(причина: String)
        /// Текст сервера как есть или «Ошибка входа».
        case ошибка(String)
    }

    /// POST cabinet.php?action=login {csrf, phone, password}. Номер — значение поля с маской, как шлёт сайт (сервер сам
    /// приводит к цифрам), оба значения обрезаны по краям (.trim() сайта). Только по нажатию «Войти».
    static func войти(телефон: String, пароль: String) async throws -> ИтогВхода {
        var повторили = false
        while true {
            let страница = try await состояние()
            if страница.вошёл == true {
                /* Пока человек набирал пароль, вход уже случился (на странице сайта, в другой вкладке): второй вход
                   не нужен, сессия есть. */
                await послеВхода(uid: страница.uid)
                return .вошёл
            }
            guard !страница.csrf.isEmpty else { throw Сбой.приложение }
            let тело: [String: Any] = [
                "csrf": страница.csrf,
                "phone": телефон.trimmingCharacters(in: .whitespacesAndNewlines),
                "password": пароль.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
            let ответ = try await запрос(путь("cabinet.php?action=login"), метод: "POST", тело: тело)
            guard let j = ответ.json else { throw Сбой.приложение }
            if да(j["ok"]) {
                await послеВхода(uid: строка(j["uid"]))
                return .вошёл
            }
            if да(j["deleted"]) { return .удалён(причина: строка(j["reason"])) }
            if да(j["need_egov"]) { return .нуженEgov }
            let ошибка = строка(j["error"])
            /* Токен устарел (страница была открыта давно) — один раз с новым, как велит §8.0.3. */
            if ошибка == "csrf" && !повторили {
                повторили = true
                continue
            }
            return .ошибка(текстОшибки(ошибка, запасной: ВходText.т("login_err")))
        }
    }

    // MARK: - Быстрая регистрация (§1.2.2)

    enum ИтогРегистрации: Equatable {
        /// Аккаунт создан и сессия открыта; пароль показывается один раз.
        case создан(телефон: String, пароль: String)
        case номерЗанят
        case иинЗанят
        case ошибка(String)
    }

    /**
     POST cabinet.php?action=register_quick {csrf, phone, iin, website, ft, code, agree}. website — поле-ловушка, всегда
     пустое; ft — сколько миллисекунд человек провёл на экране (у сайта — performance.now() от загрузки страницы): по нему
     и ловушке сервер, по-видимому, отсекает ботов (INFERRED), поэтому время настоящее. code — пусто: SMS-код сайт убрал.
     Только после «Всё верно, создать» в окне «Подтвердите номер». Не повторяется: второй вызов мог бы создать второй
     аккаунт на другой номер, если человек успел его поправить.
     */
    static func зарегистрировать(телефон: String, иин: String, мсНаЭкране: Int) async throws -> ИтогРегистрации {
        let страница = try await состояние()
        guard !страница.csrf.isEmpty else { throw Сбой.приложение }
        let тело: [String: Any] = [
            "csrf": страница.csrf,
            "phone": телефон.trimmingCharacters(in: .whitespacesAndNewlines),
            "iin": иин,
            "website": "",
            "ft": max(0, мсНаЭкране),
            "code": "",
            "agree": true
        ]
        let ответ = try await запрос(путь("cabinet.php?action=register_quick"), метод: "POST", тело: тело)
        guard let j = ответ.json else { throw Сбой.приложение }
        if да(j["ok"]) {
            let uid = строка(j["uid"])
            if !uid.isEmpty { await запомнить("ulx_me_id", uid) }
            /* Страницу не перезагружаем: сайт сначала показывает «Аккаунт создан» и перезагружается по «Продолжить»
               (послеВхода зовёт экран входа). Номер — из ответа, если он есть: так его записал сервер. */
            let номер = строка(j["phone"])
            return .создан(телефон: номер.isEmpty ? телефон : номер, пароль: строка(j["password"]))
        }
        if да(j["exists"]) { return .номерЗанят }
        if да(j["iin_taken"]) { return .иинЗанят }
        return .ошибка(текстОшибки(строка(j["error"]), запасной: ВходText.т("err")))
    }

    /// После входа — как location.reload() сайта: страница под слоем перезагружается уже вошедшей (KlikoUser.id, новый
    /// токен), а номер вошедшего ложится в ulx_me_id — по нему dm.php и заявки узнают «я» (§0.6).
    static func послеВхода(uid: String) async {
        /* TestFlight 1.10: витрина, чат и кабинет узнают о входе сразу, а не при своём следующем показе. */
        СессияПриложения.shared.вошёлСвоимЭкраном(uid: uid)
        if !uid.isEmpty { await запомнить("ulx_me_id", uid) }
        WebBridge.shared.webView?.reload()
    }

    // MARK: - Выбор роли на воротах (§1.1)

    /// authGateRole сайта: выбор «Я покупатель» / «Я продавец» хранится в localStorage.ulx_reg_role — по нему кабинет
    /// потом решает, показывать ли промо «Стать продавцом» (§1.7.1).
    static func запомнитьРоль(_ роль: String) async {
        await запомнить("ulx_reg_role", роль)
    }

    // MARK: - Новая редакция соглашения (§1.6)

    enum ИтогСоглашения: Equatable {
        case принято
        /// Сессии нет (error auth): показать вход.
        case нуженВход
        case ошибка(String)
    }

    /// POST cabinet.php?action=terms_accept {csrf, accept: 1}. retry:true — один автоповтор, как у сайта; csrf — один
    /// повтор со свежим токеном (сайт в этом случае перезагружает страницу — натив перечитывает её сам). Только по
    /// нажатию «Принимаю».
    static func принятьСоглашение() async throws -> ИтогСоглашения {
        var повторы = 0
        while true {
            let страница = try await состояние()
            if страница.вошёл == false { return .нуженВход }
            guard !страница.csrf.isEmpty else { throw Сбой.приложение }
            let тело: [String: Any] = ["csrf": страница.csrf, "accept": 1]
            let ответ = try await запрос(путь("cabinet.php?action=terms_accept"), метод: "POST", тело: тело)
            guard let j = ответ.json else { throw Сбой.приложение }
            if да(j["ok"]) { return .принято }
            let ошибка = строка(j["error"])
            if ошибка == "auth" { return .нуженВход }
            if (да(j["retry"]) || ошибка == "csrf") && повторы == 0 {
                повторы += 1
                continue
            }
            /* err_generic + код, как у сайта («Ошибка» и машинный код в скобках — по нему поддержка найдёт причину). */
            let общий = ВходText.т("err")
            return .ошибка(ошибка.isEmpty ? общий : (Self.машинныйКод(ошибка) ? общий + " (" + ошибка + ")" : ошибка))
        }
    }

    // MARK: - Выход (§1.3.2)

    /**
     Выход теми же шагами, что window.klikoLogout (U @2136), только в порядке, при котором ничего не теряется:
       1. GET /cabinet.php?logout=1&t=<токен> (без /kz/<язык>, как у сайта) — сервер закрывает сессию и снимает привязки
          уведомлений этого телефона, пока кука сессии ещё на месте. Нет связи — бросаем «Нет соединения» и НИЧЕГО не
          стираем: иначе сессия на сервере осталась бы жить, а уведомления ушедшего шли бы на этот телефон;
       2. мост klikoLogout, как у страницы: обёртка забывает токены пушей и плашки сделки и закрывает плашку;
       3. ВыходНачисто — всё, что лежит на телефоне (данные WebView и все нативные хранилища);
       4. страница под слоем — гостевой кабинет с bye=1, куда, по-видимому, и ведёт ответ сервера (INFERRED): на ней же
          обёртка по bye=1 ещё раз стирает данные WebView (безвредно — стирать уже нечего).
     Только по нажатию «Выйти» и подтверждению.
     */
    static func выйти() async throws {
        let страница = try await состояние()
        /* Владелец 26.09.2026: стираем без запроса к серверу только когда страница ясно говорит «гость». Неизвестное
           состояние (403/429 WAF, страница без KlikoUser и __ULX_GUEST) или вошедший без токена — сбой, ничего не
           стираем: иначе сессия на сервере жила бы, а уведомления ушедшего шли бы на этот телефон. */
        if страница.вошёл != false {
            guard страница.вошёл == true, !страница.csrf.isEmpty else { throw Сбой.приложение }
            let токен = страница.csrf.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? страница.csrf
            let ответ = try await запрос("/cabinet.php?logout=1&t=" + токен)
            guard ответ.код > 0, ответ.код < 500 else { throw Сбой.сеть }
            guard ответ.код < 400 else { throw Сбой.приложение }
        }
        if let web = WebBridge.shared.webView {
            web.evaluateJavaScript("try{window.webkit.messageHandlers.klikoLogout.postMessage({});}catch(e){};0",
                                   completionHandler: nil)
        }
        ВыходНачисто.стереть()
        if let гость = Config.страницаСайта("cabinet.php?bye=1") {
            WebBridge.shared.webView?.load(URLRequest(url: гость))
        }
    }

    // MARK: - Проверка сеанса (§1.3.3)

    /// Что сказал /api/sess_alert.php: этот сеанс завершён (kicked) или в аккаунт вошли с другого устройства (alert).
    struct СигналСеанса: Equatable {
        /// Ключи текстов ВходText (те же фразы, что __klkSA.txt сайта).
        let заголовок: String
        let текст: String
        /// Сеанс завершён — предложить «Войти».
        let войти: Bool
    }

    /**
     GET /api/sess_alert.php (credentials same-origin, no-store) — только чтение. Ответ «Это были вы?» (POST do=answer)
     натив не шлёт: «Нет, это не я» завершает чужой вход и может включить вход только через eGov (§8.2 «Риски»), и даже
     молчаливое «да» на вход через eGov сайт шлёт сам — вопрос задаёт страница кабинета. Поэтому кабинет показывает
     сигнал и ведёт на страницу сайта, где на него отвечают.
     */
    static func сигналСеанса() async -> СигналСеанса? {
        guard let ответ = try? await запрос("/api/sess_alert.php", ждать: false), let j = ответ.json else { return nil }
        if let сеанс = j["kicked"] as? [String: Any] {
            if строка(сеанс["via"]) == "denied" {
                return СигналСеанса(заголовок: "den_t", текст: "den_s", войти: true)
            }
            if да(сеанс["self"]) {
                return СигналСеанса(заголовок: "self_t", текст: "self_s", войти: true)
            }
            let вопрос = сеанс["q"] as? [String: Any]
            if let вопрос, !да(вопрос["info"]) {
                return СигналСеанса(заголовок: "kick_q_t", текст: "q", войти: false)
            }
            return СигналСеанса(заголовок: "kick_t", текст: вопрос != nil ? "info_s" : "kick_s", войти: true)
        }
        if let вход = j["alert"] as? [String: Any] {
            if да(вход["info"]) {
                return СигналСеанса(заголовок: "live_info_t", текст: "info_s", войти: false)
            }
            return СигналСеанса(заголовок: "live_q_t", текст: "q", войти: false)
        }
        return nil
    }

    // MARK: - Разбор страницы

    /// Значения, которые сервер печатает в HTML кабинета (сверено по снимку: guest/ и user/kz_ru_cabinet.php.html).
    static func разобрать(_ html: String) -> Состояние {
        var с = Состояние()
        if let пользователь = найти(#"window\.KlikoUser=(\{[^;<]*\});"#, в: html),
           let данные = пользователь.data(using: .utf8),
           let объект = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] {
            с.uid = строка(объект["id"])
        }
        let гость = найти(#"window\.__ULX_GUEST\s*=\s*(true|false)"#, в: html)
        if !с.uid.isEmpty {
            с.вошёл = true
        } else if let гость {
            с.вошёл = гость == "false"
        } else if найти(#"window\.KlikoUser="#, в: html) != nil {
            с.вошёл = false
        }
        let токены: [String] = [
            найти(#"window\.KlikoCsrf="([^"]*)""#, в: html) ?? "",
            найти(#"const CSRF\s*=\s*"([^"]*)""#, в: html) ?? "",
            найти(#"window\.__UIP_CSRF="([^"]*)""#, в: html) ?? ""
        ]
        с.csrf = токены.first(where: { !$0.isEmpty }) ?? ""
        if let начало = html.range(of: "const CAB_USER = {") {
            let хвост = String(html[начало.upperBound...].prefix(4000))
            if let литерал = найти(#"\bname:\s*("(?:[^"\\]|\\.)*")"#, в: хвост) {
                с.имя = строкаJSON(литерал).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        if let bio = найти(#"const BIO_ON\s*=\s*(true|false)"#, в: html) { с.eGovВключён = bio == "true" }
        с.новоеСоглашение = найти(#"window\.__TERMS_RENEW\s*=\s*(true|false)"#, в: html) == "true"
        if let литерал = найти(#"window\.__TERMS_VER\s*=\s*("(?:[^"\\]|\\.)*")"#, в: html) {
            с.редакция = строкаJSON(литерал)
        }
        if let массив = найти(#"window\.__TERMS_WHAT\s*=\s*(\[(?:\s*"(?:[^"\\]|\\.)*"\s*,?)*\s*\])"#, в: html),
           let данные = массив.data(using: .utf8),
           let пункты = (try? JSONSerialization.jsonObject(with: данные)) as? [Any] {
            с.чтоИзменилось = пункты.compactMap { $0 as? String }.filter { !$0.isEmpty }
        }
        /* Этап 41: то, что «Моим объявлениям» нужно со страницы (сверено по снимку user/kz_ru_cabinet.php.html). */
        с.магазин = найти(#"const IS_SHOP\s*=\s*(true|false)"#, в: html) == "true"
        с.верифицирован = найти(#"const IS_VERIFIED\s*=\s*(true|false)"#, в: html) == "true"
        if let литерал = найти(#"const ADV_STATUS_LABEL\s*=\s*("(?:[^"\\]|\\.)*")"#, в: html) {
            с.подписьОдобрено = строкаJSON(литерал)
        }
        if let объектИИ = найти(#"window\.CAB_AI\s*=\s*(\{[^\n]*?\});"#, в: html),
           let данные = объектИИ.data(using: .utf8),
           let ии = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] {
            с.ии = квота(ии)
        }
        return с
    }

    /// Этап 41: CAB_AI → КвотаИИ (поля — как их читает renderSlotBanner сайта).
    private static func квота(_ ии: [String: Any]) -> КвотаИИ {
        var к = КвотаИИ()
        к.показать = да(ии["show"])
        к.оплачено = да(ии["paid"])
        к.бесплатно = да(ии["free"])
        к.лимит = (ии["limit"] as? NSNumber)?.intValue ?? Int(строка(ии["limit"])) ?? 0
        к.осталось = (ии["rem"] as? NSNumber)?.intValue ?? Int(строка(ии["rem"])) ?? 0
        к.верифицирован = да(ии["verified"])
        к.название = строка(ии["t"])
        к.безлимит = строка(ии["unlimited"])
        к.осталосьПодпись = строка(ии["left"])
        к.кнопкаВерификации = строка(ии["cta_verify"])
        к.кнопкаПакета = строка(ии["cta_pack"])
        к.бесплатноЗаголовок = строка(ии["free_t"])
        к.бесплатноПодпись = строка(ии["free_s"])
        return к
    }

    /// Первая группа первого совпадения.
    private static func найти(_ шаблон: String, в тексте: String) -> String? {
        guard let выражение = try? NSRegularExpression(pattern: шаблон, options: []) else { return nil }
        let весь = NSRange(тексте.startIndex..<тексте.endIndex, in: тексте)
        guard let совпадение = выражение.firstMatch(in: тексте, options: [], range: весь) else { return nil }
        let номер = совпадение.numberOfRanges > 1 ? 1 : 0
        guard let диапазон = Range(совпадение.range(at: номер), in: тексте) else { return nil }
        return String(тексте[диапазон])
    }

    /// Строковый литерал JS/JSON в кавычках ("Р…") → строка.
    private static func строкаJSON(_ литерал: String) -> String {
        guard let данные = ("[" + литерал + "]").data(using: .utf8),
              let массив = (try? JSONSerialization.jsonObject(with: данные)) as? [Any],
              let первая = массив.first as? String else { return "" }
        return первая
    }

    // MARK: - Транспорт: fetch внутри страницы

    /**
     Этап 41: тот же транспорт для остальных экранов кабинета («Мои объявления» и дальше). хвост — относительный вызов
     сайта («cabinet.php?action=my_items»): он уходит на /kz/<язык>/<хвост>, как у страницы кабинета (карта §0.3);
     отКорня — путь от корня без локали («/api/jobs.php?action=mine»), как _ULX_BASE+"/…" сайта. Токен кладёт вызывающий:
     какие запросы шлют csrf, решает сам сайт (§0.2).
     */
    static func вызвать(_ хвост: String, метод: String = "GET", тело: [String: Any]? = nil,
                        отКорня: Bool = false, ждать: Bool = true, толькоСтраницей: Bool = false) async throws -> Ответ {
        try await запрос(отКорня ? хвост : путь(хвост), метод: метод, тело: тело, ждать: ждать,
                         толькоСтраницей: толькоСтраницей)
    }

    struct Ответ {
        let код: Int
        let текст: String
        var json: [String: Any]? {
            guard let данные = текст.data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any]
        }
    }

    /// Тело скрипта: аргументы m (метод), u (путь от корня сайта), b (тело JSON строкой). Путь относительный — fetch
    /// разрешает его от источника страницы (kliko.kz или www.kliko.kz), и запрос всегда свой, same-origin.
    private static let скриптЗапроса = """
    try {
      const o = {method: m, credentials: 'same-origin', cache: 'no-store', redirect: 'follow'};
      if (m === 'POST') { o.headers = {'Content-Type': 'application/json'}; o.body = b; }
      const r = await fetch(u, o);
      const t = await r.text();
      return JSON.stringify({s: r.status, t: t});
    } catch (e) {
      return JSON.stringify({e: (e && e.name === 'TypeError') ? 'net' : 'js'});
    }
    """

    private static func запрос(_ путь: String, метод: String = "GET", тело: [String: Any]? = nil,
                               ждать: Bool = true, толькоСтраницей: Bool = false) async throws -> Ответ {
        /* Config.нативнаяСессия: сначала URLSession (NativeCabinetTransport.swift). Сессию не узнали или связь
           оборвалась до отправки — тот же запрос прежним путём, ниже. Оборвалась после отправки — запись не повторяем.
           толькоСтраницей (вход по QR, qr.php) — всегда fetch страницы: её кука kliko_cab, её User-Agent с KlikoApp и
           настоящие Origin/Referer, без подставленных заголовков. */
        if Config.нативнаяСессия && !толькоСтраницей {
            let телоЗапроса: НативныйТранспортКабинета.Тело = метод == "POST" ? .json(телоСтрокой(тело)) : .нет
            switch await НативныйТранспортКабинета.выполнить(путь, метод: метод, тело: телоЗапроса) {
            case .ответ(let код, let текст):
                return Ответ(код: код, текст: текст)
            case .сеть(let отправлен):
                if отправлен && метод != "GET" { throw Сбой.сеть }
            case .черезСтраницу:
                break
            }
        }
        let web = try await страницаСайта(ждать: ждать)
        var строкаТела = ""
        if let тело, let данные = try? JSONSerialization.data(withJSONObject: тело),
           let текст = String(data: данные, encoding: .utf8) {
            строкаТела = текст
        }
        let аргументы: [String: Any] = ["m": метод, "u": путь, "b": строкаТела]
        let сырой: String = try await withCheckedThrowingContinuation { (продолжение: CheckedContinuation<String, Error>) in
            web.callAsyncJavaScript(скриптЗапроса, arguments: аргументы, in: nil, in: .defaultClient) { итог in
                switch итог {
                case .success(let значение):
                    продолжение.resume(returning: (значение as? String) ?? "")
                case .failure(let ошибка):
                    продолжение.resume(throwing: ошибка)
                }
            }
        }
        guard let данные = сырой.data(using: .utf8),
              let объект = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else {
            throw Сбой.приложение
        }
        if let сбой = объект["e"] as? String {
            throw сбой == "net" ? Сбой.сеть : Сбой.приложение
        }
        let код = (объект["s"] as? NSNumber)?.intValue ?? 0
        return Ответ(код: код, текст: (объект["t"] as? String) ?? "")
    }

    /// Тело JSON строкой — ровно так же, как для скрипта запроса (b).
    private static func телоСтрокой(_ тело: [String: Any]?) -> String {
        guard let тело, let данные = try? JSONSerialization.data(withJSONObject: тело),
              let текст = String(data: данные, encoding: .utf8) else { return "" }
        return текст
    }

    // MARK: - Страница по адресу: куда она привела

    /// Итог открытия страницы сайта: HTTP-код последнего ответа, адрес после всех перенаправлений и текст страницы.
    /// Перенаправила — текст не качается (пусто): нужен только адрес, куда она вела.
    struct ОтветСтраницы {
        let код: Int
        /// r.url — адрес последнего ответа; nil — страница не сказала.
        let адрес: URL?
        let перенаправлена: Bool
        let текст: String
    }

    /// Аргумент u — путь от корня сайта. Перенаправила — тело обрывается (AbortController): карточка, на которую
    /// ведёт гарант-ссылка, весит много, а нужен только её адрес.
    private static let скриптСтраницы = """
    try {
      const c = (typeof AbortController === 'function') ? new AbortController() : null;
      const o = {method: 'GET', credentials: 'same-origin', cache: 'no-store', redirect: 'follow'};
      if (c) { o.signal = c.signal; }
      const r = await fetch(u, o);
      const a = String(r.url || '');
      if (r.redirected) {
        if (c) { try { c.abort(); } catch (x) {} }
        return JSON.stringify({s: r.status, a: a, r: 1, t: ''});
      }
      const t = await r.text();
      return JSON.stringify({s: r.status, a: a, r: 0, t: t});
    } catch (e) {
      return JSON.stringify({e: (e && e.name === 'TypeError') ? 'net' : 'js'});
    }
    """

    /**
     Гарант-ссылка партнёра (/dl.php?c=<код>, GuaranteeLink.swift): страница сама отмечает открытие и кладёт цену
     продавца тому, кто вошёл, а кончается перенаправлением на карточку или своей страницей «нет ссылки / срок вышел».
     Тот же fetch изнутри страницы под слоем, что у вызвать(толькоСтраницей: true): кука сессии kliko_cab, User-Agent
     с KlikoApp, настоящие Origin и Referer — без подставленных заголовков и мимо URLSession-транспорта. Обычный GET,
     как переход по ссылке; отличие от запроса — отдаёт и адрес, куда страница привела (r.url, r.redirected).
     путь — от корня сайта («/dl.php?c=…»).
     */
    static func открытьСтраницу(_ путь: String, ждать: Bool = true) async throws -> ОтветСтраницы {
        let web = try await страницаСайта(ждать: ждать)
        let сырой: String = try await withCheckedThrowingContinuation { (продолжение: CheckedContinuation<String, Error>) in
            web.callAsyncJavaScript(скриптСтраницы, arguments: ["u": путь], in: nil, in: .defaultClient) { итог in
                switch итог {
                case .success(let значение):
                    продолжение.resume(returning: (значение as? String) ?? "")
                case .failure(let ошибка):
                    продолжение.resume(throwing: ошибка)
                }
            }
        }
        guard let данные = сырой.data(using: .utf8),
              let объект = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else {
            throw Сбой.приложение
        }
        if let сбой = объект["e"] as? String {
            throw сбой == "net" ? Сбой.сеть : Сбой.приложение
        }
        let код = (объект["s"] as? NSNumber)?.intValue ?? 0
        let строкаАдреса = ((объект["a"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let адрес: URL? = строкаАдреса.isEmpty ? nil : URL(string: строкаАдреса)
        let перенаправлена = ((объект["r"] as? NSNumber)?.intValue ?? 0) != 0
        return ОтветСтраницы(код: код, адрес: адрес, перенаправлена: перенаправлена,
                             текст: (объект["t"] as? String) ?? "")
    }

    /// Страница сайта под слоем, готовая выполнить запрос. Не на сайте (шлюз, eGov, пусто) — грузим главную и ждём.
    private static func страницаСайта(ждать: Bool) async throws -> WKWebView {
        guard let web = WebBridge.shared.webView else { throw Сбой.сеть }
        if наСайте(web) && !web.isLoading { return web }
        guard ждать else { throw Сбой.сеть }
        if !наСайте(web) {
            if WebBridge.shared.loadFailed { throw Сбой.сеть }
            if !web.isLoading, let главная = Config.страницаСайта("") { web.load(URLRequest(url: главная)) }
        }
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if наСайте(web) && !web.isLoading { return web }
        }
        throw Сбой.сеть
    }

    private static func наСайте(_ web: WKWebView) -> Bool {
        guard let адрес = web.url, адрес.scheme?.lowercased() == "https",
              let хост = адрес.host?.lowercased() else { return false }
        return хост == "kliko.kz" || хост == "www.kliko.kz"
    }

    /**
     Этап 45: то же для экранов кабинета — ключи, по которым сайт сам продолжает начатое в приложении. Лид-чат с денежной
     кнопкой при выключенном Config.деньгиСделок кладёт ulx_open_lead {cid, me, ts}: кабинет сайта при загрузке сам
     откроет этот чат (восстановление открытого чата, карта §6.4.11).
     */
    static func положитьВХранилище(_ ключ: String, _ значение: String) async {
        await запомнить(ключ, значение)
    }

    /// localStorage страницы (общий для миров скриптов) — как пишет сам сайт.
    private static func запомнить(_ ключ: String, _ значение: String) async {
        guard let web = try? await страницаСайта(ждать: true) else { return }
        let скрипт = "try { localStorage.setItem(k, v); } catch (e) {} return 1;"
        let _: Bool = await withCheckedContinuation { (продолжение: CheckedContinuation<Bool, Never>) in
            web.callAsyncJavaScript(скрипт, arguments: ["k": ключ, "v": значение], in: nil, in: .defaultClient) { _ in
                продолжение.resume(returning: true)
            }
        }
    }

    /// «/kz/<язык>/<хвост>» — язык тот же, что у Config.страницаСайта (и у текстов приложения).
    private static func путь(_ хвост: String) -> String {
        guard let полный = Config.страницаСайта(хвост),
              let части = URLComponents(url: полный, resolvingAgainstBaseURL: true) else { return "/kz/ru/" + хвост }
        let запрос = части.percentEncodedQuery.map { "?" + $0 } ?? ""
        return части.percentEncodedPath + запрос
    }

    // MARK: - Разбор значений

    /// Машинный код вида «csrf», «auth», «not_found» — не текст для человека (ulxErr сайта, §0.5).
    static func машинныйКод(_ ошибка: String) -> Bool {
        ошибка.range(of: "^[a-z][a-z0-9_]{1,14}$", options: .regularExpression) != nil
    }

    /// Текст сервера как есть; пусто или машинный код — запасной текст сайта.
    private static func текстОшибки(_ ошибка: String, запасной: String) -> String {
        let чистая = ошибка.trimmingCharacters(in: .whitespacesAndNewlines)
        if чистая.isEmpty || машинныйКод(чистая) { return запасной }
        return чистая
    }

    private static func да(_ значение: Any?) -> Bool {
        if let число = значение as? NSNumber { return число.intValue != 0 }
        if let текст = значение as? String { return текст == "1" || текст == "true" }
        return false
    }

    private static func строка(_ значение: Any?) -> String {
        if let текст = значение as? String { return текст }
        if let число = значение as? NSNumber { return число.stringValue }
        return ""
    }
}

/**
 НОМЕР ТЕЛЕФОНА КАК У САЙТА (этап 40): klkFmt и klkState из общего скрипта страниц (G @71180, G @~76000). Маска
 «+7 (7XX) XXX-XX-XX», только Казахстан; код оператора — из KLK_CODES (зеркало inc/phone_kz.php сайта). В запрос уходит
 значение поля с маской — так шлёт сайт.
 */
enum НомерКЗ {
    static let коды: Set<String> = ["700", "701", "702", "705", "706", "707", "708", "747", "750", "751", "760", "761",
                                    "762", "763", "764", "771", "775", "776", "777", "778"]

    /// Цифры ASCII — \D в JS.
    static func цифры(_ текст: String) -> String {
        String(текст.unicodeScalars.filter { $0.value >= 48 && $0.value <= 57 }.map { Character($0) })
    }

    /// klkFmt: «8 700…» и «+7 700…» не сдвигают номер; десять цифр с семёркой без «+» — номер без кода страны.
    static func формат(_ сырой: String) -> String {
        var d = цифры(сырой)
        if d.isEmpty { return "" }
        if !сырой.contains("+") && d.count == 10 && d.hasPrefix("7") { d = "7" + d }
        if d.count > 11 { d = "7" + String(d.suffix(10)) }
        if d.hasPrefix("8") { d = "7" + String(d.dropFirst()) }
        if !d.hasPrefix("7") { d = "7" + d }
        d = String(d.prefix(11))
        let n: [Character] = Array(d.dropFirst())
        var s = "+7"
        if !n.isEmpty { s += " (" + String(n.prefix(3)) }
        if n.count >= 3 { s += ")" }
        if n.count > 3 { s += " " + String(n[3..<min(6, n.count)]) }
        if n.count > 6 { s += "-" + String(n[6..<min(8, n.count)]) }
        if n.count > 8 { s += "-" + String(n[8..<min(10, n.count)]) }
        return s
    }

    enum Проверка: Equatable {
        case годен
        case нетКода(String)
        case короткий
    }

    /// klkState + klkPhoneCheck: пустое поле — тоже «Введите номер полностью».
    static func проверить(_ значение: String) -> Проверка {
        var d = цифры(значение)
        if d.count > 11 { d = "7" + String(d.suffix(10)) }
        if d.hasPrefix("8") { d = "7" + String(d.dropFirst()) }
        let n = String((d.hasPrefix("7") ? String(d.dropFirst()) : d).prefix(10))
        let код = String(n.prefix(3))
        if n.count >= 3 && !коды.contains(код) { return .нетКода(код) }
        if n.count < 10 { return .короткий }
        return .годен
    }

    /// Текст у поля (KLK_TXT сайта) или nil — номер годится.
    static func ошибка(_ значение: String) -> String? {
        switch проверить(значение) {
        case .годен: return nil
        case .нетКода(let код): return String(format: ВходText.т("phone_code"), код)
        case .короткий: return ВходText.т("phone_short")
        }
    }

    /// _credPhoneFmt окна «Аккаунт создан»: «+7 700 123 45 67».
    static func дляДоступа(_ номер: String) -> String {
        var d = цифры(номер)
        if d.count == 11 { d = String(d.dropFirst()) }
        let n: [Character] = Array(d)
        func часть(_ от: Int, _ до: Int) -> String {
            guard от < n.count else { return "" }
            return String(n[от..<min(до, n.count)])
        }
        return "+7 " + часть(0, 3) + " " + часть(3, 6) + " " + часть(6, 8) + " " + часть(8, 10)
    }
}

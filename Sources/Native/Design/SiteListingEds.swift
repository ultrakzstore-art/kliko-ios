import Foundation
import SwiftUI
import UIKit

/**
 «СДЕЛКА С ПОДПИСЬЮ eGov» НА СТРАНИЦЕ ОБЪЯВЛЕНИЯ (владелец: «на сайт не прыгать, всё своими экранами»).

 В режиме MK_DEAL_MODE = "eds" (переменная страницы сайта рядом с MK_ESCROW_PAUSED) сайт вместо гаранта ставит кнопку
 «Сделка с подписью eGov» — переменная A в mkOpenModal (js/marketplace.min.js):
   · T = I && !(L || no_escrow || !seller_verified || E || раздел transport, realty, services, jobs, animals), где
     L — цена больше нуля, но ниже MK_ESCROW_MIN (20 000 ₸), E — посуточная аренда без цены продажи; своё объявление (P)
     кнопки не получает. В режиме eds кнопок гаранта («Купить / Арендовать / Заказать безопасно») нет совсем
     (ГарантОбъявления.кнопка);
   · нажатие — mkEdsStart: GET /eds.php?action=quote&pid=<номер> → {ok, live, eligible, auth, own, verified, price,
     price_src, fee: {buyer, seller}} или {ok: false, msg}. live — своя сделка по объявлению уже идёт: сразу она
     (/cabinet.php?eds=<live>). Иначе окно mkEdsShow: «Договор · Встреча · Оплата и акт», «Цена в договоре» («согласованная
     в чате», если price_src = agreed), eds_note и плата за подпись (eds_fee_mk); внизу по ответу — «Составить договор»,
     «Пройти верификацию», «Войти, чтобы оформить», «Это ваше объявление.» или eds_unavail;
   · «Составить договор» — mkEdsCreate: POST /eds.php?action=create {pid, csrf} → {ok, url} и переход по url
     (/cabinet.php?eds=<id>). Здесь тот же адрес идёт своим путём (WebBridge.перейти → СделкиEDS): «Мои сделки» и окно
     сделки поверх. Ошибка — msg или «Не удалось оформить договор», обрыв — «Нет соединения».
 Запросы — транспорт «Моих сделок» (СделкиAPI → КабинетСайта.вызвать, токен страницы кабинета), пути от корня, как
 _MKB = "/" сайта. Денег создание не касается: плата за подпись списывается при подписи, в окне сделки.

 Режим читается со страницы ленты сайта (/marketplace — та же, откуда MK_SHOPS) не чаще раза в 30 минут и хранится на
 телефоне; флага на странице нет — режим прежний (сначала escrow, как у сайта).
 */

// MARK: - Режим сделок сайта (MK_DEAL_MODE)

@MainActor
final class РежимСделокСайта: ObservableObject {
    static let shared = РежимСделокСайта()

    /// true — MK_DEAL_MODE = "eds": вместо гаранта «Сделка с подписью eGov».
    @Published private(set) var eds: Bool

    private var сверено: Date? = nil
    private var идёт = false
    nonisolated private static let ключ = "kliko.dealMode"
    nonisolated private static let шаблон = #"MK_DEAL_MODE\s*=\s*["']([A-Za-z_]{1,20})["']"#

    /// Последнее известное значение без главного потока — для правил кнопок (ГарантОбъявления, СделкаEDSОбъявления).
    nonisolated static var edsСейчас: Bool {
        UserDefaults.standard.string(forKey: ключ) == "eds"
    }

    private init() {
        eds = Self.edsСейчас
    }

    /// Разметка страницы сайта: MK_DEAL_MODE, если он там есть.
    func принять(_ html: String) {
        сверено = Date()
        guard let режим = Self.режим(html) else { return }
        UserDefaults.standard.set(режим, forKey: Self.ключ)
        let новое = режим == "eds"
        if новое != eds { eds = новое }
    }

    /// Сверить режим со страницей ленты — не чаще раза в 30 минут; не прочиталась — прежнее значение.
    func сверить() async {
        guard !идёт else { return }
        if let сверено, Date().timeIntervalSince(сверено) < 1800 { return }
        идёт = true
        defer { идёт = false }
        if сверено == nil {
            /* Первый раз — та же загрузка, что у MK_SHOPS (SiteSession.магазины): страница качается один раз, режим
               принимает она сама. */
            _ = await SiteSession.магазины()
            return
        }
        var запрос = URLRequest(url: Config.apiBase.appendingPathComponent("marketplace"))
        запрос.timeoutInterval = 15
        guard let ответ = try? await URLSession.shared.data(for: запрос),
              let страница = String(data: ответ.0, encoding: .utf8) else { return }
        принять(страница)
    }

    nonisolated private static func режим(_ html: String) -> String? {
        guard let выражение = try? NSRegularExpression(pattern: шаблон),
              let найдено = выражение.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let часть = Range(найдено.range(at: 1), in: html) else { return nil }
        return html[часть].lowercased()
    }
}

// MARK: - Правила и запросы

/// Ответ eds.php?action=quote — то, что показывает окно mkEdsShow.
struct РасчётСделкиEDS: Identifiable, Equatable {
    let id: UUID
    /// eligible — договор по этому объявлению оформляется.
    let годна: Bool
    /// auth — человек вошёл.
    let вошёл: Bool
    /// own — объявление его.
    let своё: Bool
    /// verified — проверен через eGov.
    let проверен: Bool
    /// parseInt(price) || 0.
    let цена: Int
    /// price_src === "agreed" — цена согласована в чате.
    let согласована: Bool
    /// +fee.buyer || 0, +fee.seller || 0.
    let платаПокупателя: Int
    let платаПродавца: Int

    init(_ j: [String: Any]) {
        id = UUID()
        годна = МоиОбъявленияAPI.да(j["eligible"])
        вошёл = МоиОбъявленияAPI.да(j["auth"])
        своё = МоиОбъявленияAPI.да(j["own"])
        проверен = МоиОбъявленияAPI.да(j["verified"])
        цена = max(0, МоиОбъявленияAPI.целое(j["price"]))
        согласована = МоиОбъявленияAPI.строка(j["price_src"]) == "agreed"
        let плата = j["fee"] as? [String: Any]
        платаПокупателя = max(0, МоиОбъявленияAPI.целое(плата?["buyer"]))
        платаПродавца = max(0, МоиОбъявленияAPI.целое(плата?["seller"]))
    }
}

/// Итог mkEdsStart.
enum ИтогРасчётаEDS {
    /// Окно mkEdsShow с этим ответом.
    case окно(РасчётСделкиEDS)
    /// live — своя сделка по объявлению уже идёт: её номер.
    case идёт(String)
    /// Тост сайта: msg, «Не удалось оформить договор» или «Нет соединения».
    case ошибка(String)
}

/// Итог mkEdsCreate.
enum ИтогСозданияEDS {
    /// Адрес сделки (url ответа) — перейти по нему.
    case готово(URL)
    case ошибка(String)
}

/// Что сделать, когда окно «Сделка с подписью eGov» уедет.
enum ПослеЛистаEDS: Equatable {
    /// «Войти, чтобы оформить» — свой экран входа.
    case вход
    /// «Пройти верификацию» — своё окно верификации.
    case верификация
    /// Сделка создана — её адрес (/cabinet.php?eds=<id>).
    case сделка(URL)
}

enum СделкаEDSОбъявления {
    /// T сайта без проверки режима: не ниже MK_ESCROW_MIN, продавец проверен и не отказался от гаранта, не посуточная
    /// аренда и не авто, недвижимость, услуги, работа или животные.
    static func подходит(_ т: Listing) -> Bool {
        let аренда = т.ценаАренды != nil
        let цена = т.price ?? 0
        let нижеМинимума = цена > 0 && цена < ГарантОбъявления.минимум
        if нижеМинимума || т.безГаранта || !т.продавецПроверен || аренда { return false }
        return !["transport", "realty", "services", "jobs", "animals"].contains(т.корень)
    }

    /// Кнопка «Сделка с подписью eGov» у объявления есть (режим eds и T сайта).
    static func есть(_ т: Listing) -> Bool {
        РежимСделокСайта.edsСейчас && подходит(т)
    }

    /// mkEdsStart: GET /eds.php?action=quote&pid=<номер>.
    @MainActor
    static func расчёт(_ номер: String) async -> ИтогРасчётаEDS {
        let ответ: [String: Any]?
        do {
            ответ = try await СделкиAPI.получить("/eds.php?action=quote&pid=" + EDSAPI.вАдрес(номер), отКорня: true)
        } catch {
            return .ошибка(ТекстыСделкиEDSОбъявления.т("no_conn"))
        }
        /* t.json() не разобрался — у сайта это catch: «Нет соединения». */
        guard let j = ответ else { return .ошибка(ТекстыСделкиEDSОбъявления.т("no_conn")) }
        guard МоиОбъявленияAPI.да(j["ok"]) else { return .ошибка(сообщение(j)) }
        let идущая = МоиОбъявленияAPI.строка(j["live"]).trimmingCharacters(in: .whitespaces)
        if !идущая.isEmpty, идущая != "0", EDSAPI.годныйНомер(идущая) { return .идёт(идущая) }
        return .окно(РасчётСделкиEDS(j))
    }

    /// mkEdsCreate: POST /eds.php?action=create {pid, csrf} → url. Номер — только буквы, цифры, «_» и «-», как у сайта.
    @MainActor
    static func создать(_ номер: String) async -> ИтогСозданияEDS {
        let чистый = String(номер.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") })
        let j: [String: Any]
        do {
            j = try await СделкиAPI.отправить("/eds.php?action=create", тело: ["pid": чистый], отКорня: true)
        } catch {
            return .ошибка(ТекстыСделкиEDSОбъявления.т("no_conn"))
        }
        if МоиОбъявленияAPI.да(j["ok"]) {
            let адрес = МоиОбъявленияAPI.строка(j["url"]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !адрес.isEmpty, let полный = Config.url(адрес) { return .готово(полный) }
            /* Адреса нет, а номер есть — та же страница сделки, что у сайта после create. */
            let созданная = МоиОбъявленияAPI.строка(j["id"]).trimmingCharacters(in: .whitespaces)
            if EDSAPI.годныйНомер(созданная), let полный = адресСделки(созданная) { return .готово(полный) }
        }
        return .ошибка(сообщение(j))
    }

    /// APP_L + "/cabinet.php?eds=" + encodeURIComponent(номер).
    static func адресСделки(_ номер: String) -> URL? {
        Config.страницаСайта("cabinet.php?eds=" + EDSAPI.вАдрес(номер))
    }

    /// e.msg || ttf("eds_err", …).
    private static func сообщение(_ j: [String: Any]) -> String {
        let текст = МоиОбъявленияAPI.строка(j["msg"]).trimmingCharacters(in: .whitespacesAndNewlines)
        return текст.isEmpty ? ТекстыСделкиEDSОбъявления.т("eds_err") : текст
    }
}

// MARK: - Окно «Сделка с подписью eGov» (mkEdsShow, .mkei-* сайта)

/**
 Как #mk-eds-info сайта: шапка на поверхности — квадрат 58 с зелёным градиентом (#1bb268 → #0f7a44) и значком пера,
 заголовок 22 жирным, подзаголовок 14 серым, «×» 32 справа сверху, черта снизу; три шага на зелёной линии (номер 26 на
 мятном круге, значок 38 на мятном квадрате, заголовок 16 и текст 14); плашка на поверхности 2 с рамкой — цена в
 договоре, eds_note и плата за подпись; внизу — кнопка 50 зелёным или серая строка по ответу сервера. Лист по высоте
 содержимого (SheetFit).
 */
struct ЛистСделкиEDSОбъявления: View {
    let товар: Listing
    let расчёт: РасчётСделкиEDS
    /// Что сделать, когда лист уедет: вход, верификация или адрес созданной сделки.
    let после: (ПослеЛистаEDS) -> Void
    @Environment(\.dismiss) private var закрыть
    @State private var создаём = false
    @State private var тост: String? = nil

    init(товар: Listing, расчёт: РасчётСделкиEDS, после: @escaping (ПослеЛистаEDS) -> Void) {
        self.товар = товар
        self.расчёт = расчёт
        self.после = после
    }

    private func т(_ ключ: String) -> String { ТекстыСделкиEDSОбъявления.т(ключ) }

    private static let шаги: [(значок: String, заголовок: String, текст: String)] = [
        ("doc.text", "eds_s1_t", "eds_s1_d"),
        ("qrcode", "eds_s2_t", "eds_s2_d"),
        ("pencil.line", "eds_s3_t", "eds_s3_d")
    ]

    /// .mkei-hero-ic: linear-gradient(135deg, #1bb268, #0f7a44) — одинаковый в обеих темах.
    private static let градиентНачало = Color(uiColor: Theme.hex(0x1BB268))
    private static let градиентКонец = Color(uiColor: Theme.hex(0x0F7A44))

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                шапка
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.шаги.indices, id: \.self) { номер in
                        шаг(номер)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 4)
                заметка
                    .padding(.horizontal, 24)
                низ
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
            }
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.поверхность)
        .overlay(alignment: .bottom) {
            if let тост {
                ТостEDS(текст: тост)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: тост)
        .interactiveDismissDisabled(создаём)
        .листПоВысоте()
    }

    // MARK: Шапка (.mkei-hero)

    private var шапка: some View {
        VStack(spacing: 0) {
            Image(systemName: "pencil.line")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 58, height: 58)
                .background(LinearGradient(colors: [Self.градиентНачало, Self.градиентКонец],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                .shadow(color: Self.градиентКонец.opacity(0.45), radius: 10, x: 0, y: 8)
                .padding(.bottom, 12)
                .accessibilityHidden(true)
            Text(т("eds_title"))
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            Text(т("eds_sub"))
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 350)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 16)
        .overlay(alignment: .topTrailing) {
            Button { закрыть() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 32, height: 32)
                    .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(создаём)
            .padding(14)
            .accessibilityLabel(т("close"))
        }
        .overlay(alignment: .bottom) {
            Theme.линия
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    // MARK: Шаги (.mkei-steps)

    private func шаг(_ номер: Int) -> some View {
        let ш = Self.шаги[номер]
        let последний = номер == Self.шаги.count - 1
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(String(номер + 1))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.зелёный)
                    .frame(width: 26, height: 26)
                    .background(Theme.мята, in: Circle())
                if !последний {
                    LinearGradient(colors: [Theme.зелёный2, Theme.мята], startPoint: .top, endPoint: .bottom)
                        .frame(width: 2)
                        .frame(minHeight: 16, maxHeight: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: ш.значок)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.зелёный)
                    .frame(width: 38, height: 38)
                    .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(т(ш.заголовок))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(т(ш.текст))
                        .font(.system(size: 14))
                        .lineSpacing(2)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 16)
        }
        /* Линия шага тянется на всю его высоту: сначала своя высота по тексту, потом линия её заполняет. */
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Плашка (.mkei-note)

    private var заметка: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.зелёный)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                строкаЦены
                Text(т("eds_note"))
                if let плата = строкаПлаты {
                    Text(плата)
                }
            }
            .font(.system(size: 13))
            .lineSpacing(2)
            .foregroundStyle(Theme.текстВторой)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// «Цена в договоре: 25 000 ₸» жирным и « · согласованная в чате», если цену согласовали в чате.
    private var строкаЦены: Text {
        let сумма = DesignText.число(расчёт.цена) + "\u{00A0}₸"
        let цена = Text(т("eds_price") + ": " + сумма)
            .fontWeight(.bold)
            .foregroundStyle(Theme.текст)
        guard расчёт.согласована else { return цена }
        return цена + Text(" · " + т("eds_price_agreed"))
    }

    /// eds_fee_mk — только если за подпись вообще берут плату.
    private var строкаПлаты: String? {
        guard расчёт.платаПокупателя + расчёт.платаПродавца > 0 else { return nil }
        return т("eds_fee_mk")
            .replacingOccurrences(of: "{b}", with: DesignText.число(расчёт.платаПокупателя))
            .replacingOccurrences(of: "{s}", with: DesignText.число(расчёт.платаПродавца))
    }

    // MARK: Низ (.mkei-foot)

    @ViewBuilder
    private var низ: some View {
        if !расчёт.годна {
            подпись(т("eds_unavail"))
        } else if !расчёт.вошёл {
            кнопка(т("eds_need_login")) { уйти(.вход) }
        } else if расчёт.своё {
            подпись(т("eds_own"))
        } else if расчёт.проверен {
            кнопка(т("eds_go"), занята: создаём) { создать() }
        } else {
            VStack(spacing: 10) {
                кнопка(т("eds_need_verify")) { уйти(.верификация) }
                подпись(т("eds_need_verify_t"))
            }
        }
    }

    /// .mkei-ok: зелёная кнопка 50 со стрелкой; пока идёт запрос — белое колесо вместо надписи («…» сайта).
    private func кнопка(_ надпись: String, занята: Bool = false, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                if занята {
                    SiteSpinner.белый
                } else {
                    Text(надпись)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеСайта())
        .disabled(занята)
        .accessibilityLabel(надпись)
    }

    /// Серая строка по центру (eds_own, eds_unavail, eds_need_verify_t).
    private func подпись(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 13))
            .lineSpacing(2)
            .foregroundStyle(Theme.текстВторой)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }

    // MARK: Действия

    private func уйти(_ куда: ПослеЛистаEDS) {
        после(куда)
        закрыть()
    }

    /// mkEdsCreate: удалось — лист уезжает, панель ведёт по адресу сделки; нет — тост и кнопка снова доступна.
    private func создать() {
        guard !создаём else { return }
        создаём = true
        let номер = товар.id
        Task { @MainActor in
            let итог = await СделкаEDSОбъявления.создать(номер)
            switch итог {
            case .готово(let адрес):
                уйти(.сделка(адрес))
            case .ошибка(let текст):
                создаём = false
                показатьТост(текст)
            }
        }
    }

    private func показатьТост(_ текст: String) {
        тост = текст
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if тост == текст { тост = nil }
        }
    }
}

// MARK: - Тексты

/**
 Русские — слово в слово со словаря сайта js/i18n-marketplace-ru.js (eds_btn, eds_title, eds_sub, eds_s1…s3, eds_price,
 eds_price_agreed, eds_note, eds_fee_mk, eds_own, eds_go, eds_need_verify, eds_need_verify_t, eds_need_login,
 eds_unavail, eds_err, no_conn). Остальные языки — перевод тех же фраз теми же словами, что окно сделки (EDSText).
 */
enum ТекстыСделкиEDSОбъявления {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[ListingPageText.язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "eds_btn": "Сделка с подписью eGov",
            "eds_title": "Сделка с подписью eGov",
            "eds_sub": "Площадка денег не касается: договор и акт подписываете через eGov, платите продавцу при получении.",
            "eds_s1_t": "Договор",
            "eds_s1_d": "Вы и продавец подписываете договор купли-продажи через eGov. После этого откроются телефоны.",
            "eds_s2_t": "Встреча",
            "eds_s2_d": "Осмотрите товар. Продавец покажет код или QR — введите его у себя: встреча попадёт в протокол.",
            "eds_s3_t": "Оплата и акт",
            "eds_s3_d": "Платите продавцу напрямую и вместе подписываете акт: «получил и оплатил» — «передал и получил оплату».",
            "eds_price": "Цена в договоре",
            "eds_price_agreed": "согласованная в чате",
            "eds_note": "Площадка не принимает и не удерживает деньги — вы платите продавцу сами. Договор, акт и протокол хранятся у нас.",
            "eds_fee_mk": "Подписание договора: {b} ₸ с вас и {s} ₸ с продавца — с баланса кошелька. Если договор не подпишут обе стороны, плата вернётся.",
            "eds_own": "Это ваше объявление.",
            "eds_go": "Составить договор",
            "eds_need_verify": "Пройти верификацию",
            "eds_need_verify_t": "Договор подписывают только проверенные через eGov.",
            "eds_need_login": "Войти, чтобы оформить",
            "eds_unavail": "Для этого объявления договор с подписью eGov сейчас не оформляется.",
            "eds_err": "Не удалось оформить договор",
            "no_conn": "Нет соединения",
            "close": "Закрыть"
        ],
        "kk": [
            "eds_btn": "eGov қолтаңбасымен мәміле",
            "eds_title": "eGov қолтаңбасымен мәміле",
            "eds_sub": "Алаң ақшаға тиіспейді: шарт пен актіге eGov арқылы қол қоясыз, сатушыға тауарды алғанда төлейсіз.",
            "eds_s1_t": "Шарт",
            "eds_s1_d": "Сіз бен сатушы eGov арқылы сатып алу-сату шартына қол қоясыздар. Осыдан кейін телефондар ашылады.",
            "eds_s2_t": "Кездесу",
            "eds_s2_d": "Тауарды қараңыз. Сатушы код немесе QR көрсетеді — оны өзіңізде енгізіңіз: кездесу хаттамаға түседі.",
            "eds_s3_t": "Төлем және акт",
            "eds_s3_d": "Сатушыға тікелей төлейсіз және актіге бірге қол қоясыздар: «алдым және төледім» — «бердім және төлемді алдым».",
            "eds_price": "Шарттағы баға",
            "eds_price_agreed": "чатта келісілген",
            "eds_note": "Алаң ақша қабылдамайды және ұстамайды — сатушыға өзіңіз төлейсіз. Шарт, акт және хаттама бізде сақталады.",
            "eds_fee_mk": "Шартқа қол қою: сізден {b} ₸ және сатушыдан {s} ₸ — әмиян балансынан. Шартқа екі тарап та қол қоймаса, төлем қайтарылады.",
            "eds_own": "Бұл сіздің хабарландыруыңыз.",
            "eds_go": "Шарт жасау",
            "eds_need_verify": "Верификациядан өту",
            "eds_need_verify_t": "Шартқа тек eGov арқылы тексерілгендер қол қояды.",
            "eds_need_login": "Рәсімдеу үшін кіріңіз",
            "eds_unavail": "Бұл хабарландыру бойынша eGov қолтаңбасымен шарт қазір рәсімделмейді.",
            "eds_err": "Шартты рәсімдеу мүмкін болмады",
            "no_conn": "Байланыс жоқ",
            "close": "Жабу"
        ],
        "en": [
            "eds_btn": "Deal signed via eGov",
            "eds_title": "Deal signed via eGov",
            "eds_sub": "The platform doesn't touch the money: you sign the contract and the act via eGov and pay the seller on receipt.",
            "eds_s1_t": "Contract",
            "eds_s1_d": "You and the seller sign a sales contract via eGov. After that, phone numbers become visible.",
            "eds_s2_t": "Meeting",
            "eds_s2_d": "Inspect the item. The seller shows a code or QR — enter it on your side: the meeting goes into the log.",
            "eds_s3_t": "Payment and act",
            "eds_s3_d": "Pay the seller directly and sign the act together: «received and paid» — «handed over and got paid».",
            "eds_price": "Price in the contract",
            "eds_price_agreed": "agreed in chat",
            "eds_note": "The platform doesn't accept or hold money — you pay the seller yourself. The contract, act and log are stored with us.",
            "eds_fee_mk": "Signing the contract: {b} ₸ from you and {s} ₸ from the seller — from the wallet balance. If both parties don't sign, the fee is refunded.",
            "eds_own": "This is your listing.",
            "eds_go": "Draw up the contract",
            "eds_need_verify": "Get verified",
            "eds_need_verify_t": "Only users verified via eGov can sign the contract.",
            "eds_need_login": "Sign in to proceed",
            "eds_unavail": "An eGov-signed contract isn't available for this listing right now.",
            "eds_err": "Couldn't draw up the contract",
            "no_conn": "No connection",
            "close": "Close"
        ],
        "ar": [
            "eds_btn": "صفقة بتوقيع eGov",
            "eds_title": "صفقة بتوقيع eGov",
            "eds_sub": "المنصة لا تتعامل مع المال: توقّعون العقد والمحضر عبر eGov، وتدفع للبائع عند الاستلام.",
            "eds_s1_t": "العقد",
            "eds_s1_d": "توقّع أنت والبائع عقد البيع والشراء عبر eGov. بعد ذلك تظهر أرقام الهواتف.",
            "eds_s2_t": "لقاء",
            "eds_s2_d": "افحص السلعة. سيعرض البائع رمزًا أو QR — أدخله لديك: يُسجَّل اللقاء في المحضر.",
            "eds_s3_t": "الدفع والمحضر",
            "eds_s3_d": "ادفع للبائع مباشرةً ووقّعا المحضر معًا: «استلمت ودفعت» — «سلّمت واستلمت المبلغ».",
            "eds_price": "السعر في العقد",
            "eds_price_agreed": "متفق عليه في الدردشة",
            "eds_note": "المنصة لا تستلم المال ولا تحتجزه — تدفع للبائع بنفسك. العقد والمحضر والسجل محفوظة لدينا.",
            "eds_fee_mk": "توقيع العقد: {b} ₸ منك و{s} ₸ من البائع — من رصيد المحفظة. إذا لم يوقّع الطرفان العقد، تُعاد الرسوم.",
            "eds_own": "هذا إعلانك.",
            "eds_go": "إعداد العقد",
            "eds_need_verify": "اجتياز التحقق",
            "eds_need_verify_t": "لا يوقّع العقد إلا من تم التحقق منهم عبر eGov.",
            "eds_need_login": "سجّل الدخول للمتابعة",
            "eds_unavail": "لا يمكن حاليًا إعداد عقد بتوقيع eGov لهذا الإعلان.",
            "eds_err": "تعذّر إعداد العقد",
            "no_conn": "لا يوجد اتصال",
            "close": "إغلاق"
        ]
    ]
}

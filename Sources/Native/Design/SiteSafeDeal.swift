import SwiftUI

/**
 «КУПИТЬ БЕЗОПАСНО» НА СТРАНИЦЕ ОБЪЯВЛЕНИЯ (владелец 26.09.2026: «когда цена не меняется — купить безопасно же?»).

 Кнопка гаранта — переменная A в mkOpenModal (js/marketplace.min.js сайта), режим MK_DEAL_MODE = "escrow",
 MK_ESCROW_PAUSED = false (так на странице объявления в снимке сайта):
   · E — аренда посуточно без цены продажи (for_rent, rent_price_day > 0, цена «Договорная» или нет) — «Арендовать
     безопасно» (rent_request), mkRentJump;
   · L — цена больше нуля, но ниже MK_ESCROW_MIN (20 000 ₸), и это не E — кнопки нет; нет её и при no_escrow и у
     непроверенного продавца (seller_verified);
   · иначе вошедший и проверенный (_MK_ME_VERIFIED): услуга раздела services — «Заказать безопасно» (order_guarantor,
     cabinet.php?start_service=), остальное — «Купить безопасно» (buy_safe, mkEscrowCheckout — окно «Безопасная
     сделка»); гость и непроверенный — «Купить безопасно», mkEscrowInfo («Как работает Гарант-сделка» с кнопкой
     «Зарегистрироваться» или «Пройти верификацию»).

 Окно «Безопасная сделка» — _mkEscrowGo сайта: щит, «Безопасная сделка» / «Деньги под защитой гаранта», товар, строки
 «Цена товара», «Комиссия гаранта 1,9%» и «Сервисный сбор» (mkFeeParts), «Итого» (mkDealFee), раскрывашки «За что эти
 деньги» и «Как проходит сделка» (MK_ECO_STEPS_TXT), кнопка «Оплатить и заморозить». План суммы — _ecoPlan: товар —
 полная цена; авто и недвижимость — задаток-бронь (deposit_amount), аренда — залог (rent_deposit); этих двух полей в
 ответе, который разбирает приложение, нет, поэтому там только пояснение сайта, без чисел.

 Упрощение для новичка: одно название — «Безопасная сделка», одна фраза — «Деньги у Kliko, пока вы не получите товар»;
 кнопка окна — «Оплатить безопасно», «Комиссия гаранта» — «Сервисный сбор», банковский остаток — «Сбор банка». Суммы и
 действия прежние. На паузе гаранта (ПаузаГаранта) кнопки «Купить/Заказать безопасно» нет.

 🔴 ДЕНЬГИ — ТОЛЬКО ЗА Config.деньгиСделок (false). Выключен — окно лишь объясняет, а его кнопка открывает страницу
 оформления сделки сайта (cabinet.php?start_deal=<номер>) в веб-обёртке, как другие денежные кнопки приложения.
 Включён — сразу своё создание сделки (DealCreate.swift): задание в ЗаданияДенегСделок и «Мои сделки», тот же путь,
 что у ссылки ?start_deal=.
 */
enum ГарантОбъявления {
    /// MK_ESCROW_MIN страницы сайта: ниже этой цены гаранта нет.
    static let минимум: Double = 20_000
    /// MK_SHOWN_RATE — доля «Комиссии гаранта» в сборе (MK_COMM_PCT = "1,9").
    static let показаннаяСтавка: Double = 0.019

    enum Кнопка: Equatable {
        /// E сайта — «Арендовать безопасно».
        case аренда
        /// «Купить безопасно» (у проверенного в разделе услуг — «Заказать безопасно»).
        case купить
    }

    /// A сайта: nil — кнопки гаранта нет.
    static func кнопка(_ т: Listing) -> Кнопка? {
        let аренда = т.ценаАренды != nil
        if аренда { return .аренда }
        let цена = т.price ?? 0
        let нижеГаранта = цена > 0 && цена < минимум
        if нижеГаранта || т.безГаранта || !т.продавецПроверен { return nil }
        /* Гарант на паузе (MK_ESCROW_PAUSED) — «Купить безопасно» и его обещание не показываем; деньги не затронуты. */
        if ПаузаГаранта.наПаузеСейчас { return nil }
        return .купить
    }

    /// Цена не обсуждается (нет «Торг») и гарант есть — главная кнопка нижней панели «Купить безопасно».
    static func купитьСразу(_ т: Listing) -> Bool {
        guard !т.услуга, кнопка(т) == .купить else { return false }
        return !т.negotiable && (т.price ?? 0) > 0
    }

    /// Что замораживается — _ecoPlan сайта.
    enum План {
        case товар(база: Int)
        case задаток
        case аренда
    }

    static func план(_ т: Listing) -> План {
        if т.forRent { return .аренда }
        if т.корень == "transport" || т.корень == "realty" { return .задаток }
        return .товар(база: Int((т.price ?? 0).rounded()))
    }

    /// mkFeeParts: «Комиссия гаранта» — база × MK_SHOWN_RATE, «Сервисный сбор» — остаток сбора mkDealFee.
    struct Суммы: Equatable {
        let база: Int
        let комиссия: Int
        let сбор: Int
        let итого: Int
    }

    static func суммы(_ база: Int, ставки: СтавкиСделки = СтавкиСделки()) -> Суммы {
        let б = max(0, база)
        let весь = ставки.сбор(б)
        let комиссия = тенгеБезПереполнения((Double(б) * показаннаяСтавка).rounded())
        return Суммы(база: б, комиссия: комиссия, сбор: max(0, весь - комиссия), итого: б + весь)
    }

    /// Хвост страницы сайта с номером объявления в адресе: только буквы, цифры, «-» и «_».
    static func страница(_ начало: String, _ номер: String) -> URL? {
        let разрешено = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard let чистый = номер.addingPercentEncoding(withAllowedCharacters: разрешено), !чистый.isEmpty else {
            return nil
        }
        return Config.страницаСайта(начало + чистый)
    }
}

/// Какое окно гаранта открыто поверх объявления.
enum ЛистГарантаОбъявления: Identifiable {
    /// mkEscrowInfo — гость или без верификации.
    case пояснение(ЛистГарантСделки.Кнопка)
    /// _mkEscrowGo — проверенный, деньги в приложении выключены.
    case оформление

    var id: String {
        switch self {
        case .пояснение(let кнопка):
            switch кнопка {
            case .понятно: return "info-ok"
            case .регистрация: return "info-reg"
            case .верификация: return "info-verify"
            }
        case .оформление:
            return "checkout"
        }
    }
}

// MARK: - Окно «Безопасная сделка» (_mkEscrowGo сайта)

struct ОкноБезопаснойСделки: View {
    let товар: Listing
    /// Страница сайта — панель откроет её, когда окно закроется.
    let открыть: (URL) -> Void
    @Environment(\.dismiss) private var закрыть
    @State private var заЧто = false
    @State private var шагиОткрыты = false

    init(товар: Listing, открыть: @escaping (URL) -> Void) {
        self.товар = товар
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { БезопаснаяСделкаТекст.т(ключ) }

    private static let шаги: [(String, String)] = [("s1_t", "s1_d"), ("s2_t", "s2_d"), ("s3_t", "s3_d"), ("s4_t", "s4_d")]

    var body: some View {
        /* Лист по высоте содержимого — без пустого низа (владелец: «везде пустота снизу»). */
        ScrollView {
            VStack(spacing: 0) {
                шапка
                VStack(alignment: .leading, spacing: 14) {
                    строкаТовара
                    суммы
                    раскрывашкаЗаЧто
                    раскрывашкаШагов
                }
                .padding(16)
                низ
            }
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.поверхность)
        .листПоВысоте()
    }

    // MARK: Шапка (.mk-eco-head)

    private var шапка: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(LinearGradient(colors: [Theme.зелёный2, Theme.зелёный], startPoint: .topLeading,
                                           endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(т("co_title"))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                Text(т("co_sub"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
            }
            Spacer(minLength: 0)
            Button { закрыть() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 34, height: 34)
                    .background(Theme.поверхность2, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ListingPageText.т("close"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Theme.линия.frame(height: 1)
        }
    }

    // MARK: Товар (.mk-eco-item)

    private var строкаТовара: some View {
        HStack(spacing: 12) {
            AsyncImage(url: товар.обложка ?? товар.фотоАдреса.first) { фаза in
                if let картинка = фаза.image {
                    картинка.resizable().scaledToFill()
                } else {
                    Theme.поверхность2
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .accessibilityHidden(true)
            Text(товар.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    // MARK: Суммы (.mk-eco-rows)

    @ViewBuilder
    private var суммы: some View {
        switch ГарантОбъявления.план(товар) {
        case .товар(let база):
            let с = ГарантОбъявления.суммы(база)
            VStack(spacing: 10) {
                строка(т("co_price"), ListingCard.тенге(Double(с.база)))
                HStack(spacing: 8) {
                    мелкая(подписьКомиссии, ListingCard.тенге(Double(с.комиссия)))
                    Theme.линия.frame(width: 1, height: 14)
                    мелкая(т("co_service"), ListingCard.тенге(Double(с.сбор)))
                    Spacer(minLength: 0)
                }
                Theme.линия.frame(height: 1)
                HStack {
                    Text(т("co_total"))
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    Text(ListingCard.тенге(Double(с.итого)))
                        .font(.system(size: 18, weight: .heavy))
                }
                .foregroundStyle(Theme.текст)
            }
            .padding(14)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        case .задаток:
            заметка(т("co_price_dep"), т("co_note_dep"))
        case .аренда:
            заметка(т("co_price_rent"), т("co_note_rent"))
        }
    }

    /// «Комиссия гаранта {pct}%» — MK_COMM_PCT с запятой, как у сайта (в английском и арабском — точка).
    private var подписьКомиссии: String {
        var процент = String(format: "%.1f", ГарантОбъявления.показаннаяСтавка * 100)
        let язык = ListingPageText.язык
        if язык == "ru" || язык == "kk" { процент = процент.replacingOccurrences(of: ".", with: ",") }
        return т("co_fee_s").replacingOccurrences(of: "{pct}", with: процент)
    }

    private func строка(_ подпись: String, _ значение: String) -> some View {
        HStack {
            Text(подпись)
                .font(.system(size: 15))
                .foregroundStyle(Theme.текстВторой)
            Spacer()
            Text(значение)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.текст)
        }
    }

    private func мелкая(_ подпись: String, _ значение: String) -> some View {
        HStack(spacing: 4) {
            Text(подпись)
                .foregroundStyle(Theme.текстВторой)
            Text(значение)
                .fontWeight(.bold)
                .foregroundStyle(Theme.текст)
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func заметка(_ заголовок: String, _ текст: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(заголовок)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(текст)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    // MARK: Раскрывашки (.mk-eco-disc)

    private var раскрывашкаЗаЧто: some View {
        DisclosureGroup(isExpanded: $заЧто) {
            VStack(alignment: .leading, spacing: 8) {
                абзац(т("co_why_1_t"), т("co_why_1"))
                абзац(т("co_why_2_t"), т("co_why_2"))
            }
            .padding(.top, 8)
        } label: {
            Text(т("co_why"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.текст)
        }
        .tint(Theme.акцент)
    }

    private func абзац(_ жирно: String, _ текст: String) -> some View {
        let начало = Text(жирно).fontWeight(.bold).foregroundStyle(Theme.текст)
        let конец = Text(" — " + текст).foregroundStyle(Theme.текстВторой)
        return (начало + конец)
            .font(.system(size: 14))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var раскрывашкаШагов: some View {
        DisclosureGroup(isExpanded: $шагиОткрыты) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Self.шаги.indices, id: \.self) { номер in
                    шаг(номер)
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.акцент)
                        .accessibilityHidden(true)
                    Text(т("steps_g"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .padding(.top, 8)
        } label: {
            Text(т("steps_h"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.текст)
        }
        .tint(Theme.акцент)
    }

    private func шаг(_ номер: Int) -> some View {
        let ключи = Self.шаги[номер]
        return HStack(alignment: .top, spacing: 10) {
            Text(String(номер + 1))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(width: 24, height: 24)
                .background(Theme.акцент, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(т(ключи.0))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(т(ключи.1))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Низ (.mk-eco-foot)

    private var низ: some View {
        VStack(spacing: 8) {
            Button {
                if let адрес = ГарантОбъявления.страница("cabinet.php?start_deal=", товар.id) ?? товар.адрес {
                    открыть(адрес)
                }
                закрыть()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                    Text(т("co_pay"))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(LinearGradient(colors: [Theme.зелёный2, Theme.зелёный], startPoint: .topLeading,
                                           endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            }
            .buttonStyle(НажатиеСайта())
            .accessibilityHint(ListingPageText.т("on_site"))
            Text(ListingPageText.т("on_site"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .background(Theme.поверхность)
        .overlay(alignment: .top) {
            Theme.линия.frame(height: 1)
        }
    }
}

// MARK: - Тексты

/**
 Русские — словарь сайта js/i18n-marketplace-ru.js (escrow_bar, order_guarantor, edit_listing, promote_listing, co_title,
 co_sub, co_price, co_service, co_total, co_why*, co_price_dep, co_note_dep, co_price_rent, co_note_rent, co_pay) и
 значения по умолчанию ttf(…) в js/marketplace.min.js («Комиссия гаранта {pct}%»); «Как проходит сделка» — MK_ECO_STEPS_TXT
 сайта на всех четырёх языках. Остальные kk/en/ar — тем же тоном, что прежние тексты приложения.
 */
enum БезопаснаяСделкаТекст {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[ListingPageText.язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "buy_safe_sub": "Деньги у Kliko, пока вы не получите товар",
            "order_safe": "Заказать безопасно",
            "edit": "Редактировать", "promote": "Продвинуть",
            "co_title": "Безопасная сделка", "co_sub": "Деньги у Kliko, пока вы не получите товар",
            "co_price": "Цена товара", "co_fee_s": "Сервисный сбор {pct}%", "co_service": "Сбор банка",
            "co_total": "Итого", "co_pay": "Оплатить безопасно",
            "co_why": "За что эти деньги",
            "co_why_1_t": "Сервисный сбор",
            "co_why_1": "деньги у нас, а не у продавца. Он получит их после вашего подтверждения. Что-то не так — спор и возврат.",
            "co_why_2_t": "Сбор банка",
            "co_why_2": "то, что берёт банк за перевод. Мы на нём не зарабатываем.",
            "co_price_dep": "Задаток (бронь)",
            "co_note_dep": "У Kliko остаётся только задаток-бронь, не полная цена. Остальное — при встрече и оформлении.",
            "co_price_rent": "Залог за аренду",
            "co_note_rent": "У Kliko остаётся только залог. Он вернётся вам после аренды, если с вещью всё в порядке.",
            "steps_h": "Как проходит сделка",
            "steps_g": "Что-то не так при получении — открываете спор, деньги вернём.",
            "s1_t": "Вы оплачиваете — деньги у Kliko", "s1_d": "Деньги у Kliko, а не у продавца.",
            "s2_t": "Продавец передаёт товар", "s2_d": "Лично или доставкой/курьером.",
            "s3_t": "Вы получаете и проверяете", "s3_d": "Осмотрите и протестируйте до подтверждения.",
            "s4_t": "Подтверждаете — деньги продавцу", "s4_d": "Всё ок → отправляем оплату продавцу."
        ],
        "kk": [
            "buy_safe_sub": "Тауарды алғанша ақша Kliko-да тұрады",
            "order_safe": "Қауіпсіз тапсырыс беру",
            "edit": "Өңдеу", "promote": "Жарнамалау",
            "co_title": "Қауіпсіз мәміле", "co_sub": "Тауарды алғанша ақша Kliko-да тұрады",
            "co_price": "Тауар бағасы", "co_fee_s": "Сервистік алым {pct}%", "co_service": "Банк алымы",
            "co_total": "Барлығы", "co_pay": "Қауіпсіз төлеу",
            "co_why": "Бұл ақша не үшін",
            "co_why_1_t": "Сервистік алым",
            "co_why_1": "ақша сатушыда емес, бізде. Ол сіз растағаннан кейін алады. Бірдеңе дұрыс болмаса — дау және қайтару.",
            "co_why_2_t": "Банк алымы",
            "co_why_2": "банк аударым үшін алатын сома. Біз одан табыс таппаймыз.",
            "co_price_dep": "Кепілақы (брондау)",
            "co_note_dep": "Kliko-да толық баға емес, тек брондау кепілақысы тұрады. Қалғаны — кездесу мен рәсімдеу кезінде.",
            "co_price_rent": "Жалға алу кепілі",
            "co_note_rent": "Kliko-да тек кепіл тұрады. Затқа бәрі дұрыс болса, жалдан кейін ол өзіңізге қайтады.",
            "steps_h": "Мәміле қалай өтеді",
            "steps_g": "Алу кезінде бірдеңе дұрыс болмаса — дау ашасыз, ақшаны қайтарамыз.",
            "s1_t": "Төлейсіз — ақша Kliko-да", "s1_d": "Ақша сатушыда емес, Kliko-да.",
            "s2_t": "Сатушы тауарды береді", "s2_d": "Жеке немесе жеткізу/курьермен.",
            "s3_t": "Сіз алып, тексересіз", "s3_d": "Растамас бұрын қарап, сынап көріңіз.",
            "s4_t": "Растайсыз — ақша сатушыға", "s4_d": "Бәрі жақсы → төлемді сатушыға жібереміз."
        ],
        "en": [
            "buy_safe_sub": "Kliko holds the money until you receive the item",
            "order_safe": "Order safely",
            "edit": "Edit", "promote": "Promote",
            "co_title": "Safe deal", "co_sub": "Kliko holds the money until you receive the item",
            "co_price": "Item price", "co_fee_s": "Service fee {pct}%", "co_service": "Bank fee",
            "co_total": "Total", "co_pay": "Pay safely",
            "co_why": "What this money is for",
            "co_why_1_t": "Service fee",
            "co_why_1": "the money stays with us, not the seller. They get it after you confirm. Something wrong — dispute and refund.",
            "co_why_2_t": "Bank fee",
            "co_why_2": "what the bank charges for the transfer. We don't earn on it.",
            "co_price_dep": "Deposit (reservation)",
            "co_note_dep": "Kliko holds only the reservation deposit, not the full price. The rest is paid when you meet and sign.",
            "co_price_rent": "Rental deposit",
            "co_note_rent": "Kliko holds only the deposit. It comes back to you after the rental if the item is fine.",
            "steps_h": "How the deal works",
            "steps_g": "Something wrong on delivery — open a dispute and get your money back.",
            "s1_t": "You pay — Kliko holds the money", "s1_d": "Kliko holds the money, not the seller.",
            "s2_t": "Seller hands over the item", "s2_d": "In person or by delivery/courier.",
            "s3_t": "You receive and inspect", "s3_d": "Check and test it before confirming.",
            "s4_t": "You confirm — seller gets paid", "s4_d": "All good → we release payment to the seller."
        ],
        "ar": [
            "buy_safe_sub": "يحتفظ Kliko بالمال حتى تستلم السلعة",
            "order_safe": "اطلب بأمان",
            "edit": "تعديل", "promote": "ترويج",
            "co_title": "صفقة آمنة", "co_sub": "يحتفظ Kliko بالمال حتى تستلم السلعة",
            "co_price": "سعر السلعة", "co_fee_s": "رسوم الخدمة {pct}%", "co_service": "رسوم البنك",
            "co_total": "الإجمالي", "co_pay": "ادفع بأمان",
            "co_why": "مقابل ماذا هذا المبلغ",
            "co_why_1_t": "رسوم الخدمة",
            "co_why_1": "المال لدينا وليس لدى البائع. يحصل عليه بعد تأكيدك. إن حدث خطأ — نزاع واسترداد.",
            "co_why_2_t": "رسوم البنك",
            "co_why_2": "ما يأخذه البنك مقابل التحويل. لا نربح منه.",
            "co_price_dep": "عربون (حجز)",
            "co_note_dep": "يحتفظ Kliko بعربون الحجز فقط وليس بالسعر كاملًا. الباقي عند اللقاء والتوثيق.",
            "co_price_rent": "تأمين الإيجار",
            "co_note_rent": "يحتفظ Kliko بالتأمين فقط. يعود إليك بعد الإيجار إن كانت السلعة سليمة.",
            "steps_h": "كيف تتم الصفقة",
            "steps_g": "حدث خطأ عند الاستلام — افتح نزاعًا واسترد أموالك.",
            "s1_t": "تدفع — المال لدى Kliko", "s1_d": "المال لدى Kliko وليس لدى البائع.",
            "s2_t": "يسلّم البائع السلعة", "s2_d": "شخصيًا أو عبر التوصيل/المندوب.",
            "s3_t": "تستلم وتفحص", "s3_d": "افحصها وجرّبها قبل التأكيد.",
            "s4_t": "تؤكد — يُدفع للبائع", "s4_d": "كل شيء جيد → نحوّل الدفع للبائع."
        ]
    ]
}

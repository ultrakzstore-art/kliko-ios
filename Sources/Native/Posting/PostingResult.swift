import SwiftUI
import UIKit

/**
 ПОСЛЕ ПОДАЧИ — ЭКРАН «ОПУБЛИКОВАНО» / «НА ПРОВЕРКЕ» (владелец 26.09.2026: «как на сайте»).

 Сайт после submit (js/cabinet.min.js): auto = approved — плашка «Объявление опубликовано!» и окно showSocialModal
 (карточка, блок promoUpsellHTML «Продвиньте — продайте быстрее» с полосами «Без продвижения ×1» и «В ТОПе до ×7», кнопка
 «Продвинуть объявление» → openPromote; «или расскажите о нём» и быстрые кнопки WhatsApp, Telegram, «Ссылка» —
 socialQuickShare: текст «Название — цена ₸» и адрес /marketplace.php?item=<id>). Иначе — окно _modOver «Объявление
 на проверке» с текстами mod_wait_*. Здесь оба случая — один экран: статус словами сайта, карточка ленты (ListingCard),
 «Продвинуть» — и при проверке (владелец), быстрые кнопки и «Поделиться» — окно кабинета ОкноПоделитьсяКабинета
 (ролик для Reels, автопостинг), «Посмотреть объявление», «Мои объявления», «Подать ещё».

 🔴 ДЕНЬГИ. «Продвинуть» — платная услуга: при Config.цифровыеПокупки окно покупки App Store (ЛистУслугиApple), иначе
 страница сайта cabinet.php?promote=<id>. Решает ЭкранПодачи (послеПодачиНажат), здесь — только кнопка.
 */
struct ЭкранПослеПодачи: View {
    enum Действие { case продвинуть, посмотреть, мои, ещё, закрыть }

    let итог: ИтогПодачи
    let товар: Listing
    /// ТОП подключили при подаче (top_applied) — вместо предложения «ТОП уже подключён».
    let топПодключён: Bool
    let действие: (Действие) -> Void

    @Environment(\.openURL) private var открытьСсылку
    @State private var скопировано = false
    @State private var полосы = false

    init(итог: ИтогПодачи, товар: Listing, топПодключён: Bool, действие: @escaping (Действие) -> Void) {
        self.итог = итог
        self.товар = товар
        self.топПодключён = топПодключён
        self.действие = действие
    }

    /// Этот экран — для опубликованного и отправленного на проверку; остальные итоги — окно ОкноИтогаПодачи.
    static func берёт(_ итог: ИтогПодачи) -> Bool {
        switch итог {
        case .опубликовано, .наПроверке: return true
        default: return false
        }
    }

    static func номер(_ итог: ИтогПодачи) -> String {
        switch итог {
        case .опубликовано(let id): return id
        case .наПроверке(let id): return id
        default: return ""
        }
    }

    static func опубликовано(_ итог: ИтогПодачи) -> Bool {
        if case .опубликовано = итог { return true }
        return false
    }

    private func т(_ ключ: String) -> String { ПослеПодачиText.т(ключ) }
    private func п(_ ключ: String) -> String { ПодачаText.т(ключ) }

    private var id: String { Self.номер(итог) }
    private var опубликовано: Bool { Self.опубликовано(итог) }

    /// Адрес объявления, как у socialQuickShare сайта.
    private var ссылка: URL? {
        guard !id.isEmpty else { return nil }
        let код = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        return Config.url("/marketplace.php?item=" + код)
    }

    /// «Название — 150 000 ₸» (без цены — только название).
    private var текстОтправки: String {
        let цена = Int(товар.price ?? 0)
        guard цена > 0 else { return товар.title }
        return товар.title + " — " + ПодачаМодель.деньги(цена) + " ₸"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.фонСтраницы.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    шапка
                    VStack(spacing: 8) {
                        Text(т("preview"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.текстВторой)
                        КарточкаЛентыПодачи(товар: товар)
                    }
                    if !id.isEmpty { продвижение }
                    if let ссылка { поделиться(ссылка) }
                    кнопки
                }
                .padding(.horizontal, 16)
                .padding(.top, 52)
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            Button { действие(.закрыть) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .frame(width: 36, height: 36)
                    .background(Theme.поверхность, in: Circle())
                    .overlay { Circle().strokeBorder(Theme.линия, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 16)
            .accessibilityLabel(п("close"))
        }
    }

    // MARK: - Статус

    private var шапка: some View {
        VStack(spacing: 10) {
            Image(systemName: опубликовано ? "checkmark.circle.fill" : "clock.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(опубликовано ? Theme.зелёныйЯркий : КраскаОбъявлений.предупреждениеТекст)
                .accessibilityHidden(true)
            Text(опубликовано ? п("published") : п("mod_wait_t"))
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if опубликовано {
                Text(п("published_s"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 6) {
                    Text(п("mod_wait_b"))
                    Text("\(Text(п("mod_wait_b2")).bold()) — \(п("mod_wait_b3"))")
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Продвижение (promoUpsellHTML)

    @ViewBuilder
    private var продвижение: some View {
        if топПодключён {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.зелёныйЯркий)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(т("top_done"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(т("top_done_s"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label(т("promo_h"), systemImage: "arrow.up.forward.circle.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                VStack(spacing: 8) {
                    полоса(т("promo_lo"), "×1", доля: 0.16, горячая: false)
                    полоса(т("promo_hi"), т("promo_x7"), доля: 1, горячая: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(т("promo_lo") + " ×1, " + т("promo_hi") + " " + т("promo_x7"))
                Text(т("promo_note"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                КнопкаПодачи(т("promo_cta")) { действие(.продвинуть) }
            }
            .padding(14)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.топРамка, lineWidth: 1.5)
            }
            .onAppear {
                withAnimation(ДвижениеСайта.мягко(.easeOut(duration: 0.9).delay(0.1))) { полосы = true }
            }
        }
    }

    private func полоса(_ подпись: String, _ значение: String, доля: CGFloat, горячая: Bool) -> some View {
        HStack(spacing: 8) {
            Text(подпись)
                .font(.system(size: 12, weight: горячая ? .bold : .regular))
                .foregroundStyle(горячая ? Theme.текст : Theme.текстВторой)
                .frame(width: 112, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { г in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.поверхность2)
                    Capsule()
                        .fill(горячая ? AnyShapeStyle(LinearGradient(colors: [Theme.зелёный2, Theme.зелёныйЯркий],
                                                                    startPoint: .leading, endPoint: .trailing))
                                      : AnyShapeStyle(Theme.текстВторой.opacity(0.45)))
                        .frame(width: г.size.width * (полосы ? доля : 0))
                }
            }
            .frame(height: 8)
            Text(значение)
                .font(.system(size: 12, weight: .heavy).monospacedDigit())
                .foregroundStyle(горячая ? Theme.акцент : Theme.текстВторой)
                .frame(minWidth: 44, alignment: .trailing)
        }
    }

    // MARK: - Поделиться (socialQuickShare)

    private func поделиться(_ ссылка: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(т("share_h"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.текст)
            HStack(spacing: 8) {
                быстрая(т("wa"), значок: "message.fill", краска: Color(red: 37 / 255, green: 211 / 255, blue: 102 / 255)) {
                    ПоделитьсяСайта.whatsApp(ДанныеОтправкиСайта(товар, номер: id))
                }
                быстрая(т("tg"), значок: "paperplane.fill", краска: Color(red: 34 / 255, green: 158 / 255, blue: 217 / 255)) {
                    ПоделитьсяСайта.telegram(ДанныеОтправкиСайта(товар, номер: id))
                }
                быстрая(скопировано ? т("copied") : т("copy"), значок: скопировано ? "checkmark" : "link",
                        краска: скопировано ? Theme.зелёныйЯркий : Theme.текстВторой) {
                    скопировать(ссылка)
                }
                быстрая(п("share"), значок: "square.and.arrow.up", краска: Theme.акцент) {
                    /* Окно кабинета (showSocialModal сайта): ролик, быстрые кнопки, автопостинг — CabinetShare.swift. */
                    ОкноПоделитьсяКабинета.показать(ДанныеОтправкиСайта(товар, номер: id))
                }
            }
            if !опубликовано {
                Text(т("share_mod"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private func быстрая(_ подпись: String, значок: String, краска: Color, _ нажато: @escaping () -> Void) -> some View {
        Button(action: нажато) {
            ярлык(подпись, значок: значок, краска: краска)
        }
        .buttonStyle(.plain)
    }

    private func ярлык(_ подпись: String, значок: String, краска: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: значок)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(краска)
                .frame(width: 44, height: 44)
                .background(Theme.поверхность2, in: Circle())
                .accessibilityHidden(true)
            Text(подпись)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func открытьЧерез(_ основа: String, _ параметры: [URLQueryItem]) {
        guard var части = URLComponents(string: основа) else { return }
        части.queryItems = параметры
        if let адрес = части.url { открытьСсылку(адрес) }
    }

    private func скопировать(_ ссылка: URL) {
        UIPasteboard.general.string = текстОтправки + "\n" + ссылка.absoluteString
        ОткликСайта.успех()
        скопировано = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            скопировано = false
        }
    }

    // MARK: - Куда дальше

    private var кнопки: some View {
        VStack(spacing: 10) {
            if опубликовано && !id.isEmpty {
                КнопкаПодачи(т("view")) { действие(.посмотреть) }
            }
            КнопкаПодачиВторая(т("mine")) { действие(.мои) }
            Button { действие(.ещё) } label: {
                Label(т("more"), systemImage: "plus.circle")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.акцент)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Модель: куда после подачи

extension ПодачаМодель {
    /// «Посмотреть объявление»: мастер прочь, объявление — нативной карточкой (или страницей сайта), список — в фоне.
    func открытьОбъявлениеПослеПодачи(_ id: String, запасной: @escaping (URL) -> Void) {
        итог = nil
        остановить()
        плашкаПосле = ""
        ПодачаОкно.shared.цель = nil
        let код = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        let адрес = Config.url("/marketplace.php?item=" + код)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            if NativeRouter.доступна(.объявление(id: id)) {
                NativeRouter.shared.цель = .объявление(id: id)
            } else if let адрес {
                запасной(адрес)
            }
            await МоиОбъявленияМодель.shared.загрузить(страницу: false)
        }
    }

    /// «Подать ещё»: чистая форма и стартовый экран «Что размещаете?»; «Мои объявления» обновятся в фоне.
    func податьЕщё() {
        итог = nil
        плашкаПосле = ""
        топПослеПодачи = false
        чистаяФорма()
        Task { @MainActor in await МоиОбъявленияМодель.shared.загрузить(страницу: false) }
    }
}

// MARK: - Тексты (ru — слова сайта: promoUpsellHTML, showSocialModal, socialQuickShare)

enum ПослеПодачиText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь: [String: String]
        switch язык {
        case "kk": словарь = kk
        case "en": словарь = en
        case "ar": словарь = ar
        default: словарь = ru
        }
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let ru: [String: String] = [
        "preview": "Так увидят объявление покупатели",
        "promo_h": "Продвиньте — продайте быстрее",
        "promo_lo": "Без продвижения",
        "promo_hi": "В ТОПе",
        "promo_x7": "до ×7",
        "promo_note": "Объявление поднимается в ТОП выдачи и авто-поднимается в ленте — в разы больше просмотров и откликов.",
        "promo_cta": "Продвинуть объявление",
        "top_done": "ТОП уже подключён",
        "top_done_s": "Объявление сразу в верху выдачи. Ничего доплачивать не нужно.",
        "share_h": "Поделитесь объявлением",
        "share_mod": "Ссылка откроется у всех, как только объявление пройдёт проверку.",
        "wa": "WhatsApp",
        "tg": "Telegram",
        "copy": "Ссылка",
        "copied": "Скопировано",
        "view": "Посмотреть объявление",
        "mine": "Мои объявления",
        "more": "Подать ещё"
    ]

    private static let kk: [String: String] = [
        "preview": "Сатып алушылар хабарландыруды осылай көреді",
        "promo_h": "Жарнамалаңыз — тезірек сатыңыз",
        "promo_lo": "Жарнамасыз",
        "promo_hi": "ТОП-та",
        "promo_x7": "×7 дейін",
        "promo_note": "Хабарландыру іздеудің ТОП-на көтеріліп, лентада өзі көтеріледі — қаралым мен хабарласу бірнеше есе көп.",
        "promo_cta": "Хабарландыруды жарнамалау",
        "top_done": "ТОП қосылған",
        "top_done_s": "Хабарландыру бірден іздеудің жоғарғы жағында. Қосымша төлеудің қажеті жоқ.",
        "share_h": "Хабарландырумен бөлісіңіз",
        "share_mod": "Хабарландыру тексеруден өткен соң сілтеме барлығына ашылады.",
        "wa": "WhatsApp",
        "tg": "Telegram",
        "copy": "Сілтеме",
        "copied": "Көшірілді",
        "view": "Хабарландыруды көру",
        "mine": "Менің хабарландыруларым",
        "more": "Тағы беру"
    ]

    private static let en: [String: String] = [
        "preview": "This is how buyers will see your listing",
        "promo_h": "Promote it — sell faster",
        "promo_lo": "Without promotion",
        "promo_hi": "In TOP",
        "promo_x7": "up to ×7",
        "promo_note": "The listing goes to the TOP of results and is bumped in the feed automatically — many times more views and replies.",
        "promo_cta": "Promote listing",
        "top_done": "TOP is already on",
        "top_done_s": "The listing is at the top of results right away. Nothing more to pay.",
        "share_h": "Share your listing",
        "share_mod": "The link will open for everyone as soon as the listing passes review.",
        "wa": "WhatsApp",
        "tg": "Telegram",
        "copy": "Link",
        "copied": "Copied",
        "view": "View listing",
        "mine": "My listings",
        "more": "Post another"
    ]

    private static let ar: [String: String] = [
        "preview": "هكذا سيرى المشترون إعلانك",
        "promo_h": "روّج له — بِع أسرع",
        "promo_lo": "بدون ترويج",
        "promo_hi": "في TOP",
        "promo_x7": "حتى ×7",
        "promo_note": "يرتفع الإعلان إلى TOP في النتائج ويُرفع تلقائيًا في الموجز — مشاهدات وردود أكثر بعدة مرات.",
        "promo_cta": "ترويج الإعلان",
        "top_done": "TOP مفعّل بالفعل",
        "top_done_s": "الإعلان في أعلى النتائج فورًا. لا حاجة لدفع المزيد.",
        "share_h": "شارك إعلانك",
        "share_mod": "سيفتح الرابط للجميع بمجرد اجتياز الإعلان للمراجعة.",
        "wa": "WhatsApp",
        "tg": "Telegram",
        "copy": "الرابط",
        "copied": "تم النسخ",
        "view": "عرض الإعلان",
        "mine": "إعلاناتي",
        "more": "نشر إعلان آخر"
    ]
}

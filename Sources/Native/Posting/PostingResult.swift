import SwiftUI
import UIKit

/**
 ПОСЛЕ ПОДАЧИ — ЛИСТ «ОПУБЛИКОВАНО! ПОДЕЛИТЕСЬ РОЛИКОМ» (владелец 26.09.2026: «как на сайте»).

 Сайт после submit (js/cabinet.min.js): auto = approved — плашка «Объявление опубликовано!» и лист showSocialModal
 (.soc-card): ручка и «✕», галочка, «Опубликовано! Поделитесь роликом», строка объявления .soc-prev (фото, название,
 цена), «или расскажите о нём», .soc-hero «Сделать видео и поделиться» — окно кабинета ОкноПоделитьсяКабинета (ролик
 для Reels, автопостинг), быстрые плитки WhatsApp, Telegram, «Ссылка» (socialQuickShare: «Название — цена ₸» и адрес
 /marketplace.php?item=<id>) и «Позже». «На проверке» — окно _modOver (ОкноИтогаПодачи), не этот лист.

 Владелец (обход новичком): спокойный лист — «Опубликовано. Сообщим, когда напишет покупатель», строка объявления,
 одна ссылка «Поделиться» и «Готово». Ролик для Reels / TikTok и быстрые плитки — за «Поделиться», не первым делом.
 Большого предложения ТОПа здесь нет; под «Поделиться» — маленькая ссылка «Продвинуть объявление» (окно покупки
 App Store, как на карточке «Моих объявлений»), только при Config.цифровыеПокупки и без ТОПа; выключено — ничего, ссылок
 на оплату на сайте нет (App Store 3.1.1). ТОП подключён при подаче — короткие сведения «ТОП уже подключён».
 */
struct ЭкранПослеПодачи: View {
    enum Действие { case продвинуть, посмотреть, мои, ещё, закрыть }

    let итог: ИтогПодачи
    let товар: Listing
    /// ТОП подключили при подаче (top_applied) — сведения «ТОП уже подключён».
    let топПодключён: Bool
    let действие: (Действие) -> Void

    @State private var скопировано = false
    /// «Поделиться» нажато — ролик и быстрые плитки раскрыты.
    @State private var делимся = false

    init(итог: ИтогПодачи, товар: Listing, топПодключён: Bool, действие: @escaping (Действие) -> Void) {
        self.итог = итог
        self.товар = товар
        self.топПодключён = топПодключён
        self.действие = действие
    }

    /// Этот лист — для опубликованного; остальные итоги (и «на проверке») — окно ОкноИтогаПодачи.
    static func берёт(_ итог: ИтогПодачи) -> Bool {
        if case .опубликовано = итог { return true }
        return false
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
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { действие(.закрыть) }
                .accessibilityHidden(true)
            ViewThatFits(in: .vertical) {
                лист
                ScrollView { лист }
                    .scrollBounceBehavior(.basedOnSize)
            }
            .background {
                КраскаПодачи.карточка
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 20, topTrailingRadius: 20, style: .continuous))
                    .ignoresSafeArea(edges: .bottom)
            }
        }
    }

    private var лист: some View {
        VStack(spacing: 0) {
            верх
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56, weight: .regular))
                .foregroundStyle(Theme.зелёныйЯркий)
                .frame(width: 62, height: 62)
                .accessibilityHidden(true)
            Text(п("pub_calm_t"))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(КраскаПодачи.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            Text(п("pub_calm_s"))
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            строкаОбъявления
                .padding(.top, 16)
            if топПодключён {
                продвижение.padding(.top, 12)
            }
            if let ссылка {
                if делимся {
                    поделиться(ссылка)
                        .transition(.opacity)
                } else {
                    ссылкаПоделиться
                }
            }
            if можноПродвинуть {
                ссылкаПродвинуть
            }
            КнопкаПодачи(п("done")) { действие(.закрыть) }
                .padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: 560)
    }

    /// Одна ссылка «Поделиться» — раскрывает ролик и быстрые плитки.
    private var ссылкаПоделиться: some View {
        Button {
            withAnimation(ДвижениеСайта.мягко(.easeOut(duration: 0.2))) { делимся = true }
        } label: {
            Label(п("share"), systemImage: "square.and.arrow.up")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(КраскаПодачи.акцентТекст)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
    }

    /// Продвижение — только покупкой App Store (Config.цифровыеПокупки), когда ТОПа ещё нет.
    private var можноПродвинуть: Bool {
        Config.цифровыеПокупки && !топПодключён && !id.isEmpty
    }

    /// Вторичная ссылка под «Поделиться»: «Продвинуть объявление» — окно покупки App Store (PostingView, .продвинуть).
    private var ссылкаПродвинуть: some View {
        Button {
            действие(.продвинуть)
        } label: {
            Label(т("promo_cta"), systemImage: "arrow.up.forward.circle")
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    /// .soc-top: ручка 42×4 и «✕» 32×32 на --surf2.
    private var верх: some View {
        ZStack {
            Capsule()
                .fill(КраскаПодачи.линия)
                .frame(width: 42, height: 4)
            HStack {
                Spacer(minLength: 0)
                Button { действие(.закрыть) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(КраскаПодачи.текст)
                        .frame(width: 32, height: 32)
                        .background(КраскаПодачи.поле, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(п("close"))
            }
        }
        .frame(height: 44)
    }

    /// .soc-prev: фото 52×52, название и цена; нажатие — открыть объявление.
    private var строкаОбъявления: some View {
        Button { действие(.посмотреть) } label: {
            HStack(spacing: 10) {
                обложка
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(товар.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(КраскаПодачи.текст)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(ценаСтрокой)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(КраскаПодачи.акцентТекст)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(id.isEmpty)
    }

    /// Обложка: файл снимка на телефоне или адрес сервера.
    @ViewBuilder
    private var обложка: some View {
        if let адрес = адресОбложки {
            AsyncImage(url: адрес) { фаза in
                if let изображение = фаза.image {
                    изображение.resizable().scaledToFill()
                } else {
                    КраскаПодачи.линия
                }
            }
        } else {
            КраскаПодачи.линия
        }
    }

    private var адресОбложки: URL? {
        guard let обложка = товар.thumb, !обложка.isEmpty else { return nil }
        if обложка.hasPrefix("file:") { return URL(string: обложка) }
        return Config.url(обложка)
    }

    /// Цена как у сайта: «150 000 ₸», без цены — «Договорная».
    private var ценаСтрокой: String {
        let цена = Int(товар.price ?? 0)
        return цена > 0 ? ПодачаМодель.деньги(цена) + " ₸" : п("price_negotiable")
    }

    // MARK: - ТОП уже подключён (из promoUpsellHTML — только сведения)

    private var продвижение: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(т("top_done"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(КраскаПодачи.текст)
                Text(т("top_done_s"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Поделиться (.soc-hero и .soc-quick)

    private func поделиться(_ ссылка: URL) -> some View {
        VStack(spacing: 0) {
            Text(п("soc_sub"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
                .padding(.bottom, 10)
            Button {
                /* Окно кабинета (showSocialModal сайта): ролик, быстрые кнопки, автопостинг — CabinetShare.swift. */
                ОкноПоделитьсяКабинета.показать(ДанныеОтправкиСайта(товар, номер: id))
            } label: {
                ролик
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            HStack(spacing: 8) {
                быстрая(т("wa"), значок: "message.fill", краска: Color(red: 37 / 255, green: 211 / 255, blue: 102 / 255)) {
                    ПоделитьсяСайта.whatsApp(ДанныеОтправкиСайта(товар, номер: id))
                }
                быстрая(т("tg"), значок: "paperplane.fill", краска: Color(red: 34 / 255, green: 158 / 255, blue: 217 / 255)) {
                    ПоделитьсяСайта.telegram(ДанныеОтправкиСайта(товар, номер: id))
                }
                быстрая(скопировано ? т("copied") : т("copy"), значок: скопировано ? "checkmark" : "link",
                        краска: скопировано ? КраскаПодачи.хорошоТекст : КраскаПодачи.текст) {
                    скопировать(ссылка)
                }
            }
            .padding(.top, 8)
        }
    }

    /// .soc-hero: градиент Instagram 120°, скругление 18, значок в белом квадрате 20 %.
    private var ролик: some View {
        let градиент = Gradient(stops: [
            .init(color: Color(red: 249 / 255, green: 206 / 255, blue: 52 / 255), location: 0),
            .init(color: Color(red: 238 / 255, green: 42 / 255, blue: 123 / 255), location: 0.44),
            .init(color: Color(red: 98 / 255, green: 40 / 255, blue: 215 / 255), location: 1)
        ])
        return HStack(spacing: 12) {
            Image(systemName: "video.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(п("soc_hero"))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Text(п("soc_hero_s"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.right")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.white)
                .flipsForRightToLeftLayoutDirection(true)
                .accessibilityHidden(true)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(gradient: градиент, startPoint: UnitPoint(x: 0, y: 0.2), endPoint: UnitPoint(x: 1, y: 0.8)),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .contentShape(Rectangle())
    }

    /// Плитка .soc-quick: --card, кромка --line, скругление 14, высота 70, значок 20 и 12/700.
    private func быстрая(_ подпись: String, значок: String, краска: Color, _ нажато: @escaping () -> Void) -> some View {
        Button(action: нажато) {
            VStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(краска)
                    .accessibilityHidden(true)
                Text(подпись)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(КраскаПодачи.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 70)
            .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
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

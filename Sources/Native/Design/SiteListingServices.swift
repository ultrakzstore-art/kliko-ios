import SwiftUI
import UIKit

/**
 ВСПОМОГАТЕЛЬНЫЕ УСЛУГИ И БЫСТРЫЕ ВОПРОСЫ НА СТРАНИЦЕ ОБЪЯВЛЕНИЯ (владелец 28.09.2026: «как на сайте — эвакуатор, СТО,
 шиномонтаж, грузчики…»).

 · «Нужна помощь?» (mkServiceBlock сайта, .mk-svc) — у всего, кроме услуг и вакансий, последним в колонке .mk-mcol-e,
   сразу под «Расположением». Пилюли — MK_SVC_MAP.M по разделу объявления; нет — по его родителям вверх по дереву
   (до 25 шагов), потом по корню, иначе одна «Найти специалиста». Нажатие — mkBroadcast: лист запроса исполнителям
   рядом (ЛистЗапросаИсполнителям, тот же, что у грузоперевозок) с текстом услуги (svcq_<ключ>), городом и точкой
   объявления, section «services» и specialty из SVC_CAT («evacuation», «moving-service»…).
 · «Быстрые вопросы» (mkSvcQuestions, .mk-sq) — только у услуг и вакансий, в колонке .mk-mcol-d после кнопок связи:
   четыре вопроса по направлению услуги (MK_SVC_Q[_mkSvcDir]), иначе общие. Нажатие — mkChatOpen(id, q): чат по
   объявлению с вопросом в строке ввода (не отправляется сам — человек жмёт «Отправить»).
 */

// MARK: - «Нужна помощь?» (mkServiceBlock) — услуги рядом по разделу

struct БлокУслугСайта: View {
    let товар: Listing
    @State private var запрос: ЗапросИсполнителям?
    @State private var пульс = false
    /// --fs-xs и --fs-sm сайта — с крупным шрифтом телефона растут.
    @ScaledMetric(relativeTo: .caption2) private var кегльЗаголовка: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var кегль: CGFloat = 12

    init(товар: Listing) {
        self.товар = товар
    }

    /// Ключи пилюль, как mkServiceBlock: раздел, его родители, корень; ничего — «spec».
    static func ключи(_ товар: Listing) -> [String] {
        var раздел = товар.категория
        var шагов = 0
        while let р = раздел, шагов < 25 {
            if let набор = ТекстыУслугРядом.разделы[р] { return набор }
            раздел = РазделыСайта.родитель(р)
            шагов += 1
        }
        return ТекстыУслугРядом.разделы[товар.корень] ?? ["spec"]
    }

    var body: some View {
        let ключи = Self.ключи(товар).filter { ТекстыУслугРядом.значки[$0] != nil }
        VStack(alignment: .leading, spacing: 10) {
            заголовок
            ПереносСтрок(промежуток: 6, междуСтрок: 6) {
                if ключи.isEmpty {
                    /* Пустой набор — одна зелёная «Найти специалиста рядом» (.mk-svc-chip.broadcast) в корень. */
                    Button { запрос = общийЗапрос() } label: {
                        ПилюляУслугиСайта(значок: "dot.radiowaves.left.and.right",
                                          текст: ТекстыУслугРядом.т("find_specialist"), кегль: кегль, общая: true)
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
                } else {
                    ForEach(ключи, id: \.self) { ключ in
                        Button { запрос = запросПо(ключ) } label: {
                            ПилюляУслугиСайта(значок: ТекстыУслугРядом.значки[ключ] ?? "wrench.and.screwdriver",
                                              текст: ТекстыУслугРядом.т("svc_" + ключ), кегль: кегль, общая: false)
                        }
                        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Theme.цвет(светлый: Theme.hex(0xF4F8F6), тёмный: Theme.hex(0x163024, 0.45))
                RadialGradient(colors: [Theme.оттенокАкцента, Color.clear], center: .topLeading, startRadius: 0,
                               endRadius: 260)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .shadow(color: Color(red: 16 / 255, green: 32 / 255, blue: 24 / 255).opacity(0.08), radius: 8, x: 0, y: 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.оттенокАкцента, lineWidth: 1)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .onAppear {
            guard !ДвижениеСайта.тихо else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { пульс = true }
        }
        .sheet(item: $запрос) { какой in
            ЛистЗапросаИсполнителям(запрос: какой)
        }
    }

    /// .mk-svc-title: пульсирующая точка и «НУЖНА ПОМОЩЬ?» (11, 800, в верхнем регистре).
    private var заголовок: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(RadialGradient(colors: [Color(uiColor: Theme.hex(0x4FD9A4)), Theme.зелёный2],
                                     center: UnitPoint(x: 0.32, y: 0.3), startRadius: 0, endRadius: 6))
                .frame(width: 9, height: 9)
                .background {
                    Circle()
                        .fill(Theme.зелёный2.opacity(пульс ? 0.05 : 0.22))
                        .frame(width: пульс ? 21 : 15, height: пульс ? 21 : 15)
                }
                .accessibilityHidden(true)
            Text(ТекстыУслугРядом.т("need_help").uppercased())
                .font(.system(size: кегльЗаголовка, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func запросПо(_ ключ: String) -> ЗапросИсполнителям {
        ЗапросИсполнителям(текст: ТекстыУслугРядом.вопрос(ключ), город: товар.city, широта: широта,
                           долгота: долгота, раздел: "services",
                           специальность: ТекстыУслугРядом.специальности[ключ] ?? "")
    }

    /// mkBroadcast(o, "", …) запасной пилюли: раздел — корень объявления, текст пустой.
    private func общийЗапрос() -> ЗапросИсполнителям {
        ЗапросИсполнителям(текст: "", город: товар.city, широта: широта, долгота: долгота,
                           раздел: товар.корень, специальность: "")
    }

    private var широта: String { товар.поляВида.широта.map { String($0) } ?? "" }
    private var долгота: String { товар.поляВида.долгота.map { String($0) } ?? "" }
}

/// .mk-svc-chip в .mk-mwrap: пилюля 32 pt, значок 14 зелёным (0,82), текст 12 полужирным. общая — .broadcast:
/// зелёная заливка, белые текст и значок.
private struct ПилюляУслугиСайта: View {
    let значок: String
    let текст: String
    let кегль: CGFloat
    let общая: Bool

    private static let фон = Theme.цвет(светлый: Theme.hex(0xFFFFFF), тёмный: Theme.hex(0xFFFFFF, 0.05))
    private static let рамка = Theme.цвет(светлый: Theme.hex(0x1D7D4A, 0.10), тёмный: Theme.hex(0xFFFFFF, 0.12))
    private static let краска = Theme.цвет(0x1D7D4A, 0xD8EFE2)

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: значок)
                .font(.system(size: кегль, weight: .semibold))
                .foregroundStyle(общая ? Color.white : Theme.зелёный2)
                .opacity(общая ? 1 : 0.82)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: кегль, weight: .semibold))
                .foregroundStyle(общая ? Color.white : Self.краска)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(minHeight: 32)
        .background {
            if общая {
                Capsule().fill(LinearGradient(colors: [Theme.зелёный2, Theme.акцент], startPoint: .topLeading,
                                              endPoint: .bottomTrailing))
            } else {
                Capsule().fill(Self.фон)
            }
        }
        .overlay { Capsule().strokeBorder(общая ? Color.clear : Self.рамка, lineWidth: 1) }
        .contentShape(Capsule())
    }
}

// MARK: - «Быстрые вопросы» (mkSvcQuestions) — у услуг

/// Вопрос, с которым открывается чат по объявлению.
struct ВопросУслугиВЧат: Identifiable, Hashable {
    let id = UUID()
    let текст: String
}

struct БыстрыеВопросыУслуги: View {
    let товар: Listing
    /// Страница сайта для чата (как у «Согласовать с продавцом»); nil — пустое действие.
    let открыть: ((URL) -> Void)?
    @State private var вопрос: ВопросУслугиВЧат?
    @ScaledMetric(relativeTo: .subheadline) private var кегльЗаголовка: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var кегльПодписи: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var кегль: CGFloat = 12

    init(товар: Listing, открыть: ((URL) -> Void)?) {
        self.товар = товар
        self.открыть = открыть
    }

    /// Показывать ли: услуга или вакансия (mkIsService) и нативный чат по объявлению, куда лягут вопросы.
    static func есть(_ товар: Listing) -> Bool {
        товар.услуга && Config.нативныйЧат && Config.чатОбъявления
    }

    /// _mkSvcDir: прямой потомок «services», в ветке которого раздел; нет — пусто.
    static func направление(_ раздел: String?) -> String {
        guard var текущий = раздел, !текущий.isEmpty else { return "" }
        var шагов = 0
        while let родитель = РазделыСайта.родитель(текущий), родитель != "services", шагов < 12 {
            текущий = родитель
            шагов += 1
        }
        return РазделыСайта.родитель(текущий) == "services" ? текущий : ""
    }

    var body: some View {
        let вопросы = ТекстыУслугРядом.вопросыУслуги(Self.направление(товар.категория))
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "ellipsis.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 26, height: 26)
                    .background(Theme.акцент, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                    .shadow(color: Theme.акцент.opacity(0.45), radius: 6, x: 0, y: 4)
                    .accessibilityHidden(true)
                Text(ТекстыУслугРядом.т("svc_q_title"))
                    .font(.system(size: кегльЗаголовка, weight: .heavy))
                    .tracking(-0.14)
                    .foregroundStyle(Theme.акцент)
                    .accessibilityAddTraits(.isHeader)
            }
            .padding(.bottom, 4)
            Text(ТекстыУслугРядом.т("svc_q_sub"))
                .font(.system(size: кегльПодписи, weight: .medium))
                .foregroundStyle(Theme.текстВторой)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            ПереносСтрок(промежуток: 6, междуСтрок: 6) {
                ForEach(вопросы, id: \.self) { текст in
                    Button { вопрос = ВопросУслугиВЧат(текст: текст) } label: {
                        Text(текст)
                            .font(.system(size: кегль, weight: .bold))
                            .foregroundStyle(Theme.акцент)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Theme.поверхность, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                    .accessibilityHint(ТекстыУслугРядом.т("svc_q_hint"))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .fill(Theme.акцент.opacity(0.10))
                .shadow(color: Color(red: 16 / 255, green: 32 / 255, blue: 24 / 255).opacity(0.06), radius: 8, x: 0,
                        y: 6)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .navigationDestination(item: $вопрос) { какой in
            ЭкранЧатаОбъявления(товар: товар, предложить: false, открыть: откуда, текст: какой.текст)
        }
    }

    /// Куда чат уводит на сайт (снятое объявление, сделка): нет страницы — никуда.
    private var откуда: (URL) -> Void {
        открыть ?? { _ in }
    }
}

/// Словарь MK_SVC_MAP сайта (T — значок, подпись, вопрос; M — пилюли раздела) и тексты блока на языке телефона.
enum ТекстыУслугРядом {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[ListingPageText.язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    /// Текст запроса исполнителям (T[ключ][3] / svcq_<ключ>); у «spec» — пусто, человек пишет сам.
    static func вопрос(_ ключ: String) -> String {
        let текст = т("q_" + ключ)
        return текст.hasPrefix("q_") ? "" : текст
    }

    /// SVC_CAT сайта: пилюля → раздел услуг (specialty запроса). Нет — пусто, как у сайта.
    static let специальности: [String: String] = [
        "evak": "evacuation",
        "sto": "car-service",
        "tire": "tire-service",
        "carwash": "car-wash",
        "autopaint": "auto-painting",
        "autoglass": "auto-glass",
        "autoelec": "auto-electrician",
        "diag": "auto-diagnostics",
        "autoexp": "auto-diagnostics",
        "renovate": "repair-construction",
        "plumb": "plumbing-service",
        "electro": "electrical-service",
        "wininstall": "window-install",
        "winrepair": "window-repair-svc",
        "mosquito": "window-mosquito",
        "assembly": "furniture-assembly",
        "mover": "moving-service",
        "phonefix": "phone-repair",
        "screen": "screen-replacement",
        "battery": "battery-replacement",
        "lapfix": "laptop-repair",
        "pcfix": "pc-repair",
        "upgrade": "pc-upgrade",
        "virus": "virus-removal",
        "os": "os-install",
        "tvfix": "tv-repair",
        "fridgefix": "fridge-repair",
        "washfix": "washer-repair",
        "acfix": "ac-repair",
        "acinstall": "ac-repair",
        "delivery": "delivery-courier",
        "bigdeliv": "cargo-transport",
        "babycour": "delivery-courier",
        "sportcour": "delivery-courier",
        "trainer": "fitness-trainer",
        "vet": "pet-walking",
        "grooming": "pet-walking",
        "pet-walk": "pet-walking",
        "tailor": "tailoring",
        "shoefix": "shoe-repair",
        "photosvc": "photographer",
        "dronsvc": "drone-photo",
        "jurcheck": "lawyer",
    ]

    /// Четыре быстрых вопроса по направлению услуги (MK_SVC_Q), нет направления — общие (_def).
    static func вопросыУслуги(_ направление: String) -> [String] {
        let язык = вопросы[ListingPageText.язык] ?? вопросы["ru"] ?? [:]
        return язык[направление] ?? язык["_def"] ?? []
    }

    /// MK_SVC_Q сайта на языках приложения: язык → направление → вопросы.
    private static let вопросы: [String: [String: [String]]] = [
        "ru": [
            "tech-repair": ["Выезжаете на дом?", "Сколько стоит диагностика?", "Какая гарантия на ремонт?", "Как быстро приедете?"],
            "repair-construction": ["Выезжаете на замер?", "Смета бесплатная?", "Материалы ваши или мои?", "Какие сроки работ?"],
            "auto-services": ["Есть запись на сегодня?", "Сколько по времени?", "Гарантия на работу есть?", "Работаете с моей маркой?"],
            "beauty-health": ["Есть свободное время сегодня?", "Работаете на выезд?", "Сколько длится процедура?", "Материалы свои?"],
            "tutors-education": ["Онлайн или очно?", "Первое занятие пробное?", "Сколько стоит занятие?", "Какой график?"],
            "it-development": ["Какие сроки по проекту?", "Цена под ключ?", "Есть портфолио?", "Правки входят в стоимость?"],
            "delivery-courier": ["Успеете сегодня?", "Сколько стоит доставка?", "Межгород возите?", "Есть отслеживание?"],
            "photo-video-svc": ["Свободны на эту дату?", "Сколько фото в итоге?", "Сроки обработки?", "Нужен аванс?"],
            "events": ["Свободны на дату?", "Что входит в программу?", "Сколько по времени?", "Нужен аванс?"],
            "legal-financial": ["Консультация бесплатна?", "Работаете онлайн?", "Сколько стоит услуга?", "Какие сроки?"],
            "translation": ["Есть нотариальное заверение?", "Сроки перевода?", "Цена за страницу?", "Какие языки?"],
            "other-services": ["Выезжаете на дом?", "Сколько стоит?", "Когда свободны?", "Какая гарантия?"],
            "_def": ["Услуга ещё актуальна?", "Сколько стоит?", "Когда свободны?", "Выезжаете на дом?"],
        ],
        "kk": [
            "tech-repair": ["Үйге барасыз ба?", "Диагностика қанша тұрады?", "Жөндеуге кепілдік қандай?", "Қаншалықты тез келесіз?"],
            "repair-construction": ["Өлшеуге барасыз ба?", "Смета тегін бе?", "Материал сіздікі ме, менікі ме?", "Жұмыс мерзімі қандай?"],
            "auto-services": ["Бүгінге жазылу бар ма?", "Қанша уақыт алады?", "Жұмысқа кепілдік бар ма?", "Менің маркаммен жұмыс істейсіз бе?"],
            "beauty-health": ["Бүгін бос уақыт бар ма?", "Үйге барып істейсіз бе?", "Процедура қанша уақытқа созылады?", "Материал өзіңіздікі ме?"],
            "tutors-education": ["Онлайн ба, бетпе-бет пе?", "Алғашқы сабақ сынақ па?", "Бір сабақ қанша тұрады?", "Кесте қандай?"],
            "it-development": ["Жоба мерзімі қандай?", "Толық баға қанша?", "Портфолио бар ма?", "Түзетулер бағаға кіре ме?"],
            "delivery-courier": ["Бүгін үлгересіз бе?", "Жеткізу қанша тұрады?", "Қалааралық тасисыз ба?", "Бақылау бар ма?"],
            "photo-video-svc": ["Осы күнге боссыз ба?", "Нәтижесінде қанша фото?", "Өңдеу мерзімі қандай?", "Аванс керек пе?"],
            "events": ["Сол күнге боссыз ба?", "Бағдарламаға не кіреді?", "Қанша уақыт алады?", "Аванс керек пе?"],
            "legal-financial": ["Кеңес тегін бе?", "Онлайн жұмыс істейсіз бе?", "Қызмет қанша тұрады?", "Мерзімі қандай?"],
            "translation": ["Нотариалды куәландыру бар ма?", "Аударма мерзімі қандай?", "Бір беттің бағасы қанша?", "Қандай тілдер?"],
            "other-services": ["Үйге барасыз ба?", "Қанша тұрады?", "Қашан боссыз?", "Кепілдік қандай?"],
            "_def": ["Қызмет әлі өзекті ме?", "Қанша тұрады?", "Қашан боссыз?", "Үйге барасыз ба?"],
        ],
        "en": [
            "tech-repair": ["Do you make house calls?", "How much is diagnostics?", "What's the repair warranty?", "How soon can you come?"],
            "repair-construction": ["Do you come out to measure?", "Is the estimate free?", "Your materials or mine?", "How long will the work take?"],
            "auto-services": ["Any slots today?", "How long does it take?", "Is the work under warranty?", "Do you service my car make?"],
            "beauty-health": ["Any free time today?", "Do you do home visits?", "How long is the procedure?", "Do you bring your own materials?"],
            "tutors-education": ["Online or in person?", "Is the first lesson a trial?", "How much is a lesson?", "What's the schedule?"],
            "it-development": ["What's the project timeline?", "Turnkey price?", "Do you have a portfolio?", "Are revisions included?"],
            "delivery-courier": ["Can you make it today?", "How much is delivery?", "Do you go intercity?", "Is there tracking?"],
            "photo-video-svc": ["Are you free on this date?", "How many photos in the end?", "Editing turnaround?", "Is a deposit required?"],
            "events": ["Are you free on the date?", "What's in the program?", "How long is it?", "Is a deposit required?"],
            "legal-financial": ["Is the consultation free?", "Do you work online?", "How much is the service?", "What's the timeline?"],
            "translation": ["Do you offer notarization?", "Translation turnaround?", "Price per page?", "Which languages?"],
            "other-services": ["Do you make house calls?", "How much is it?", "When are you free?", "What's the warranty?"],
            "_def": ["Is the service still available?", "How much is it?", "When are you free?", "Do you make house calls?"],
        ],
        "ar": [
            "tech-repair": ["هل تأتون إلى المنزل؟", "كم تكلفة التشخيص؟", "ما الضمان على الإصلاح؟", "متى يمكنكم الوصول؟"],
            "repair-construction": ["هل تأتون لأخذ القياسات؟", "هل التقدير مجاني؟", "المواد منكم أم مني؟", "ما مدة العمل؟"],
            "auto-services": ["هل يوجد موعد اليوم؟", "كم يستغرق من الوقت؟", "هل يوجد ضمان على العمل؟", "هل تعملون على نوع سيارتي؟"],
            "beauty-health": ["هل لديكم وقت متاح اليوم؟", "هل تقدمون زيارات منزلية؟", "كم تستغرق الجلسة؟", "هل المواد من عندكم؟"],
            "tutors-education": ["عبر الإنترنت أم حضوريًا؟", "هل الدرس الأول تجريبي؟", "كم سعر الدرس؟", "ما الجدول؟"],
            "it-development": ["ما المدة الزمنية للمشروع؟", "ما السعر الشامل؟", "هل لديكم أعمال سابقة؟", "هل التعديلات ضمن السعر؟"],
            "delivery-courier": ["هل يمكنكم التوصيل اليوم؟", "كم تكلفة التوصيل؟", "هل توصلون بين المدن؟", "هل يوجد تتبع؟"],
            "photo-video-svc": ["هل أنتم متاحون في هذا التاريخ؟", "كم صورة في النهاية؟", "ما مدة المعالجة؟", "هل يلزم عربون؟"],
            "events": ["هل أنتم متاحون في التاريخ؟", "ماذا يشمل البرنامج؟", "كم المدة؟", "هل يلزم عربون؟"],
            "legal-financial": ["هل الاستشارة مجانية؟", "هل تعملون عبر الإنترنت؟", "كم سعر الخدمة؟", "ما المدة؟"],
            "translation": ["هل يوجد تصديق من كاتب العدل؟", "ما مدة الترجمة؟", "كم السعر للصفحة؟", "ما اللغات المتاحة؟"],
            "other-services": ["هل تأتون إلى المنزل؟", "كم السعر؟", "متى تكونون متاحين؟", "ما الضمان؟"],
            "_def": ["هل الخدمة ما زالت متاحة؟", "كم السعر؟", "متى تكونون متاحين؟", "هل تأتون إلى المنزل؟"],
        ],
    ]

    static let значки: [String: String] = [
        "evak": "car",
        "sto": "wrench.and.screwdriver",
        "tire": "circle.circle",
        "carwash": "drop",
        "autoexp": "magnifyingglass",
        "autopaint": "paintbrush",
        "autoglass": "eye",
        "autoelec": "bolt",
        "diag": "cpu",
        "microfix": "wrench.and.screwdriver",
        "boatfix": "wrench.and.screwdriver",
        "realtor": "house",
        "jurcheck": "checkmark.shield",
        "renovate": "wrench.and.screwdriver",
        "mover": "truck.box",
        "plumb": "drop",
        "electro": "bolt",
        "wininstall": "door.left.hand.closed",
        "winrepair": "wrench.and.screwdriver",
        "mosquito": "square.grid.3x3",
        "phonefix": "iphone",
        "screen": "iphone",
        "battery": "bolt",
        "lapfix": "laptopcomputer",
        "pcfix": "cpu",
        "upgrade": "cpu",
        "virus": "checkmark.shield",
        "os": "wrench.and.screwdriver",
        "tvfix": "tv",
        "fridgefix": "wrench.and.screwdriver",
        "washfix": "wrench.and.screwdriver",
        "acfix": "wind",
        "acinstall": "wind",
        "delivery": "truck.box",
        "assembly": "wrench.and.screwdriver",
        "bigdeliv": "truck.box",
        "vet": "pawprint",
        "grooming": "scissors",
        "pet-walk": "pawprint",
        "tailor": "tshirt",
        "shoefix": "shoeprints.fill",
        "babycour": "truck.box",
        "sportcour": "truck.box",
        "trainer": "dumbbell",
        "photosvc": "camera",
        "dronsvc": "airplane",
        "spec": "dot.radiowaves.left.and.right",
    ]

    static let разделы: [String: [String]] = [
        "transport": ["evak", "sto", "tire", "carwash", "autoexp"],
        "cars": ["evak", "sto", "tire", "carwash", "autoexp", "autopaint", "autoglass", "autoelec", "diag"],
        "cars-sedan": ["evak", "sto", "tire", "carwash", "autoexp", "autopaint", "autoglass", "autoelec", "diag"],
        "cars-suv": ["evak", "sto", "tire", "carwash", "autoexp", "autopaint", "autoglass", "autoelec", "diag"],
        "cars-electric": ["evak", "sto", "autoelec", "diag", "carwash"],
        "motorcycles": ["sto", "tire", "carwash", "spec"],
        "scooters": ["sto", "tire", "carwash", "spec"],
        "e-scooters": ["microfix", "delivery", "spec"],
        "trucks-special": ["evak", "sto", "tire", "spec"],
        "auto-parts": ["sto", "autoelec", "diag", "spec"],
        "tires-wheels": ["tire", "sto", "spec"],
        "water-transport": ["boatfix", "bigdeliv", "spec"],
        "boats": ["boatfix", "bigdeliv", "spec"],
        "jet-skis": ["boatfix", "bigdeliv", "spec"],
        "realty": ["realtor", "jurcheck", "renovate", "mover", "plumb", "electro"],
        "apartments": ["realtor", "jurcheck", "renovate", "mover", "plumb", "electro"],
        "rooms": ["realtor", "renovate", "mover", "plumb", "electro"],
        "houses": ["realtor", "jurcheck", "renovate", "mover", "plumb", "electro"],
        "cottages": ["realtor", "jurcheck", "renovate", "mover", "plumb", "electro"],
        "commercial-realty": ["realtor", "jurcheck", "renovate", "electro"],
        "land": ["realtor", "jurcheck", "spec"],
        "windows-doors": ["wininstall", "winrepair", "mosquito", "electro"],
        "repair": ["plumb", "electro", "mover", "renovate", "wininstall"],
        "home-garden": ["renovate", "mover", "assembly", "plumb", "electro", "wininstall"],
        "phones-tablets": ["phonefix", "screen", "battery"],
        "smartphones": ["phonefix", "screen", "battery"],
        "tablets": ["phonefix", "screen", "battery"],
        "phone-parts": ["phonefix", "screen", "battery", "spec"],
        "computers": ["lapfix", "pcfix", "upgrade", "virus", "os"],
        "laptops": ["lapfix", "upgrade", "virus", "os"],
        "desktops": ["pcfix", "upgrade", "virus", "os"],
        "pc-components": ["pcfix", "upgrade", "spec"],
        "monitors": ["spec"],
        "tv-audio": ["tvfix"],
        "tv": ["tvfix"],
        "appliances": ["fridgefix", "washfix", "acfix"],
        "fridges": ["fridgefix"],
        "washing-machines": ["washfix"],
        "air-conditioners": ["acfix", "acinstall"],
        "furniture": ["assembly", "mover"],
        "sofas": ["assembly", "mover"],
        "beds": ["assembly", "mover"],
        "wardrobes": ["assembly", "mover"],
        "animals": ["vet", "grooming", "pet-walk"],
        "dogs": ["vet", "grooming", "pet-walk"],
        "cats": ["vet", "grooming"],
        "clothing": ["tailor", "shoefix"],
        "shoes": ["shoefix", "tailor"],
        "kids": ["babycour", "spec"],
        "strollers-carseats": ["babycour", "assembly"],
        "sport": ["trainer", "spec"],
        "bicycles": ["microfix", "delivery", "spec"],
        "fitness": ["trainer", "assembly"],
        "photo-video": ["photosvc", "dronsvc"],
        "drones": ["dronsvc", "photosvc"],
        "cameras": ["photosvc", "spec"],
        "electronics": ["spec"],
    ]

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "need_help": "Нужна помощь?",
            "find_specialist": "Найти специалиста рядом", "svc_q_title": "Быстрые вопросы",
            "svc_q_sub": "Быстро спросите специалиста — ответ придёт вам в чат",
            "svc_q_hint": "Откроет чат с этим вопросом",
            "svc_evak": "Эвакуатор", "q_evak": "Нужен эвакуатор",
            "svc_sto": "СТО рядом", "q_sto": "Ищу СТО / автосервис",
            "svc_tire": "Шиномонтаж", "q_tire": "Нужен шиномонтаж",
            "svc_carwash": "Автомойка", "q_carwash": "Ищу автомойку рядом",
            "svc_autoexp": "Подборщик авто", "q_autoexp": "Ищу подборщика / автоэксперта",
            "svc_autopaint": "Кузовной ремонт", "q_autopaint": "Нужен кузовной ремонт или покраска",
            "svc_autoglass": "Замена стёкол авто", "q_autoglass": "Нужна замена или ремонт стекла авто",
            "svc_autoelec": "Авто-электрик", "q_autoelec": "Ищу авто-электрика",
            "svc_diag": "Диагностика авто", "q_diag": "Нужна компьютерная диагностика авто",
            "svc_microfix": "Ремонт самоката/велосипеда", "q_microfix": "Нужен ремонт электросамоката или велосипеда",
            "svc_boatfix": "Ремонт лодки/мотора", "q_boatfix": "Нужен ремонт лодки или лодочного мотора",
            "svc_realtor": "Риелтор", "q_realtor": "Ищу риелтора",
            "svc_jurcheck": "Юр. проверка", "q_jurcheck": "Нужна юридическая проверка объекта недвижимости",
            "svc_renovate": "Ремонт под ключ", "q_renovate": "Ищу бригаду для ремонта квартиры",
            "svc_mover": "Переезд / грузчики", "q_mover": "Нужны грузчики или перевозка мебели",
            "svc_plumb": "Сантехник", "q_plumb": "Нужен сантехник",
            "svc_electro": "Электрик", "q_electro": "Нужен электрик",
            "svc_wininstall": "Установка окон", "q_wininstall": "Нужна установка пластиковых окон",
            "svc_winrepair": "Ремонт окон", "q_winrepair": "Нужен ремонт окна / замена ручки / уплотнителя",
            "svc_mosquito": "Москитные сетки", "q_mosquito": "Нужны москитные сетки на окна",
            "svc_phonefix": "Ремонт телефона", "q_phonefix": "Нужен ремонт телефона",
            "svc_screen": "Замена экрана", "q_screen": "Нужна замена экрана телефона",
            "svc_battery": "Замена аккумулятора", "q_battery": "Нужна замена аккумулятора телефона",
            "svc_lapfix": "Ремонт ноутбука", "q_lapfix": "Нужен ремонт ноутбука",
            "svc_pcfix": "Ремонт компьютера", "q_pcfix": "Нужен ремонт компьютера",
            "svc_upgrade": "Апгрейд ПК", "q_upgrade": "Хочу апгрейд компьютера / заменить комплектующие",
            "svc_virus": "Удалить вирусы", "q_virus": "Нужно удаление вирусов и настройка Windows",
            "svc_os": "Установка Windows", "q_os": "Нужна установка / переустановка Windows",
            "svc_tvfix": "Ремонт телевизора", "q_tvfix": "Нужен ремонт телевизора",
            "svc_fridgefix": "Ремонт холодильника", "q_fridgefix": "Нужен ремонт холодильника",
            "svc_washfix": "Ремонт стиралки", "q_washfix": "Нужен ремонт стиральной машины",
            "svc_acfix": "Ремонт кондиционера", "q_acfix": "Нужен ремонт или чистка кондиционера",
            "svc_acinstall": "Установка кондиц.", "q_acinstall": "Нужна установка кондиционера",
            "svc_delivery": "Доставка / перевозка", "q_delivery": "Нужна доставка или перевозка",
            "svc_assembly": "Сборка мебели", "q_assembly": "Нужна сборка мебели",
            "svc_bigdeliv": "Газель / грузовик", "q_bigdeliv": "Нужна газель или грузовик для перевозки",
            "svc_vet": "Ветеринар рядом", "q_vet": "Нужен ветеринар / выезд на дом",
            "svc_grooming": "Грумер / стрижка", "q_grooming": "Нужен грумер для животного",
            "svc_pet-walk": "Выгул собак", "q_pet-walk": "Нужен выгул собаки",
            "svc_tailor": "Пошив / ремонт", "q_tailor": "Нужен ателье / ремонт одежды",
            "svc_shoefix": "Ремонт обуви", "q_shoefix": "Нужен ремонт обуви",
            "svc_babycour": "Доставка", "q_babycour": "Нужна доставка детских товаров",
            "svc_sportcour": "Доставка", "q_sportcour": "Нужна доставка спортинвентаря",
            "svc_trainer": "Тренер", "q_trainer": "Ищу персонального тренера",
            "svc_photosvc": "Фотограф", "q_photosvc": "Ищу фотографа",
            "svc_dronsvc": "Съёмка с дрона", "q_dronsvc": "Нужна аэро-фотосъёмка / видео с дрона",
            "svc_spec": "Найти специалиста",
        ],
        "kk": [
            "need_help": "Көмек керек пе?",
            "find_specialist": "Жақын маман табу", "svc_q_title": "Жылдам сұрақтар",
            "svc_q_sub": "Маманнан тез сұраңыз — жауап чатқа келеді",
            "svc_q_hint": "Осы сұрақпен чат ашылады",
            "svc_evak": "Эвакуатор", "q_evak": "Эвакуатор керек",
            "svc_sto": "Жақын СТО", "q_sto": "СТО / автосервис іздеймін",
            "svc_tire": "Шиномонтаж", "q_tire": "Шиномонтаж керек",
            "svc_carwash": "Автожуу", "q_carwash": "Жақын жерден автожуу іздеймін",
            "svc_autoexp": "Көлік таңдаушы", "q_autoexp": "Көлік таңдаушы / автосарапшы іздеймін",
            "svc_autopaint": "Шанақ жөндеу", "q_autopaint": "Шанақ жөндеу немесе бояу керек",
            "svc_autoglass": "Көлік әйнегін ауыстыру", "q_autoglass": "Көлік әйнегін ауыстыру не жөндеу керек",
            "svc_autoelec": "Автоэлектрик", "q_autoelec": "Автоэлектрик іздеймін",
            "svc_diag": "Көлік диагностикасы", "q_diag": "Көлікке компьютерлік диагностика керек",
            "svc_microfix": "Самокат/велосипед жөндеу", "q_microfix": "Электросамокат не велосипед жөндеу керек",
            "svc_boatfix": "Қайық/мотор жөндеу", "q_boatfix": "Қайық не қайық моторын жөндеу керек",
            "svc_realtor": "Риелтор", "q_realtor": "Риелтор іздеймін",
            "svc_jurcheck": "Заң тексеруі", "q_jurcheck": "Жылжымайтын мүлікті заңдық тексеру керек",
            "svc_renovate": "Кілтке дейін жөндеу", "q_renovate": "Пәтер жөндеуге бригада іздеймін",
            "svc_mover": "Көшу / жүкшілер", "q_mover": "Жүкшілер не жиһаз тасымалы керек",
            "svc_plumb": "Сантехник", "q_plumb": "Сантехник керек",
            "svc_electro": "Электрик", "q_electro": "Электрик керек",
            "svc_wininstall": "Терезе орнату", "q_wininstall": "Пластик терезе орнату керек",
            "svc_winrepair": "Терезе жөндеу", "q_winrepair": "Терезе жөндеу / тұтқа не тығыздағыш ауыстыру керек",
            "svc_mosquito": "Москит торлары", "q_mosquito": "Терезеге москит торы керек",
            "svc_phonefix": "Телефон жөндеу", "q_phonefix": "Телефон жөндеу керек",
            "svc_screen": "Экран ауыстыру", "q_screen": "Телефон экранын ауыстыру керек",
            "svc_battery": "Аккумулятор ауыстыру", "q_battery": "Телефон аккумуляторын ауыстыру керек",
            "svc_lapfix": "Ноутбук жөндеу", "q_lapfix": "Ноутбук жөндеу керек",
            "svc_pcfix": "Компьютер жөндеу", "q_pcfix": "Компьютер жөндеу керек",
            "svc_upgrade": "ДК жаңарту", "q_upgrade": "Компьютерді жаңартқым / бөлшектерін ауыстырғым келеді",
            "svc_virus": "Вирустарды жою", "q_virus": "Вирустарды жою және Windows баптау керек",
            "svc_os": "Windows орнату", "q_os": "Windows орнату / қайта орнату керек",
            "svc_tvfix": "Теледидар жөндеу", "q_tvfix": "Теледидар жөндеу керек",
            "svc_fridgefix": "Тоңазытқыш жөндеу", "q_fridgefix": "Тоңазытқыш жөндеу керек",
            "svc_washfix": "Кір жуғыш жөндеу", "q_washfix": "Кір жуғыш машина жөндеу керек",
            "svc_acfix": "Кондиционер жөндеу", "q_acfix": "Кондиционер жөндеу не тазалау керек",
            "svc_acinstall": "Кондиционер орнату", "q_acinstall": "Кондиционер орнату керек",
            "svc_delivery": "Жеткізу / тасымал", "q_delivery": "Жеткізу не тасымал керек",
            "svc_assembly": "Жиһаз құрастыру", "q_assembly": "Жиһаз құрастыру керек",
            "svc_bigdeliv": "Газель / жүк көлігі", "q_bigdeliv": "Тасымалға газель не жүк көлігі керек",
            "svc_vet": "Жақын ветеринар", "q_vet": "Ветеринар / үйге шақыру керек",
            "svc_grooming": "Грумер / қырқу", "q_grooming": "Жануарға грумер керек",
            "svc_pet-walk": "Итті серуендету", "q_pet-walk": "Итті серуендету керек",
            "svc_tailor": "Тігу / жөндеу", "q_tailor": "Ателье / киім жөндеу керек",
            "svc_shoefix": "Аяқ киім жөндеу", "q_shoefix": "Аяқ киім жөндеу керек",
            "svc_babycour": "Жеткізу", "q_babycour": "Балалар тауарларын жеткізу керек",
            "svc_sportcour": "Жеткізу", "q_sportcour": "Спорт құралдарын жеткізу керек",
            "svc_trainer": "Жаттықтырушы", "q_trainer": "Жеке жаттықтырушы іздеймін",
            "svc_photosvc": "Фотограф", "q_photosvc": "Фотограф іздеймін",
            "svc_dronsvc": "Дроннан түсіру", "q_dronsvc": "Дроннан фото / бейне түсіру керек",
            "svc_spec": "Маман табу",
        ],
        "en": [
            "need_help": "Need help?",
            "find_specialist": "Find a specialist nearby", "svc_q_title": "Quick questions",
            "svc_q_sub": "Ask the specialist quickly — the reply will come to your chat",
            "svc_q_hint": "Opens the chat with this question",
            "svc_evak": "Tow truck", "q_evak": "Need a tow truck",
            "svc_sto": "Car service nearby", "q_sto": "Looking for a car service",
            "svc_tire": "Tyre service", "q_tire": "Need a tyre service",
            "svc_carwash": "Car wash", "q_carwash": "Looking for a car wash nearby",
            "svc_autoexp": "Car inspector", "q_autoexp": "Looking for a car inspector",
            "svc_autopaint": "Body repair", "q_autopaint": "Need body repair or painting",
            "svc_autoglass": "Auto glass", "q_autoglass": "Need car glass replaced or repaired",
            "svc_autoelec": "Auto electrician", "q_autoelec": "Looking for an auto electrician",
            "svc_diag": "Car diagnostics", "q_diag": "Need computer diagnostics for my car",
            "svc_microfix": "Scooter/bike repair", "q_microfix": "Need an e-scooter or bike repaired",
            "svc_boatfix": "Boat/motor repair", "q_boatfix": "Need a boat or outboard motor repaired",
            "svc_realtor": "Realtor", "q_realtor": "Looking for a realtor",
            "svc_jurcheck": "Legal check", "q_jurcheck": "Need a legal check of the property",
            "svc_renovate": "Full renovation", "q_renovate": "Looking for a crew to renovate an apartment",
            "svc_mover": "Movers", "q_mover": "Need movers or furniture transport",
            "svc_plumb": "Plumber", "q_plumb": "Need a plumber",
            "svc_electro": "Electrician", "q_electro": "Need an electrician",
            "svc_wininstall": "Window installation", "q_wininstall": "Need PVC windows installed",
            "svc_winrepair": "Window repair", "q_winrepair": "Need a window repaired / handle or seal replaced",
            "svc_mosquito": "Insect screens", "q_mosquito": "Need insect screens for windows",
            "svc_phonefix": "Phone repair", "q_phonefix": "Need a phone repaired",
            "svc_screen": "Screen replacement", "q_screen": "Need a phone screen replaced",
            "svc_battery": "Battery replacement", "q_battery": "Need a phone battery replaced",
            "svc_lapfix": "Laptop repair", "q_lapfix": "Need a laptop repaired",
            "svc_pcfix": "PC repair", "q_pcfix": "Need a computer repaired",
            "svc_upgrade": "PC upgrade", "q_upgrade": "Want to upgrade my PC / replace components",
            "svc_virus": "Virus removal", "q_virus": "Need viruses removed and Windows set up",
            "svc_os": "Windows install", "q_os": "Need Windows installed / reinstalled",
            "svc_tvfix": "TV repair", "q_tvfix": "Need a TV repaired",
            "svc_fridgefix": "Fridge repair", "q_fridgefix": "Need a fridge repaired",
            "svc_washfix": "Washer repair", "q_washfix": "Need a washing machine repaired",
            "svc_acfix": "AC repair", "q_acfix": "Need an AC repaired or cleaned",
            "svc_acinstall": "AC installation", "q_acinstall": "Need an AC installed",
            "svc_delivery": "Delivery", "q_delivery": "Need delivery or transport",
            "svc_assembly": "Furniture assembly", "q_assembly": "Need furniture assembled",
            "svc_bigdeliv": "Van / truck", "q_bigdeliv": "Need a van or truck for transport",
            "svc_vet": "Vet nearby", "q_vet": "Need a vet / home visit",
            "svc_grooming": "Groomer", "q_grooming": "Need a groomer for my pet",
            "svc_pet-walk": "Dog walking", "q_pet-walk": "Need a dog walker",
            "svc_tailor": "Tailoring", "q_tailor": "Need a tailor / clothing repair",
            "svc_shoefix": "Shoe repair", "q_shoefix": "Need shoes repaired",
            "svc_babycour": "Delivery", "q_babycour": "Need kids' goods delivered",
            "svc_sportcour": "Delivery", "q_sportcour": "Need sports gear delivered",
            "svc_trainer": "Trainer", "q_trainer": "Looking for a personal trainer",
            "svc_photosvc": "Photographer", "q_photosvc": "Looking for a photographer",
            "svc_dronsvc": "Drone shooting", "q_dronsvc": "Need aerial photo / drone video",
            "svc_spec": "Find a specialist",
        ],
        "ar": [
            "need_help": "تحتاج مساعدة؟",
            "find_specialist": "ابحث عن مختص قريب", "svc_q_title": "أسئلة سريعة",
            "svc_q_sub": "اسأل المختص بسرعة — سيصلك الرد في الدردشة",
            "svc_q_hint": "يفتح الدردشة بهذا السؤال",
            "svc_evak": "سحب السيارات", "q_evak": "أحتاج سيارة سحب",
            "svc_sto": "ورشة قريبة", "q_sto": "أبحث عن ورشة سيارات",
            "svc_tire": "إطارات", "q_tire": "أحتاج خدمة إطارات",
            "svc_carwash": "غسيل سيارات", "q_carwash": "أبحث عن مغسلة سيارات قريبة",
            "svc_autoexp": "خبير سيارات", "q_autoexp": "أبحث عن خبير لفحص السيارة",
            "svc_autopaint": "إصلاح الهيكل", "q_autopaint": "أحتاج إصلاح الهيكل أو الطلاء",
            "svc_autoglass": "زجاج السيارات", "q_autoglass": "أحتاج استبدال أو إصلاح زجاج السيارة",
            "svc_autoelec": "كهربائي سيارات", "q_autoelec": "أبحث عن كهربائي سيارات",
            "svc_diag": "تشخيص السيارة", "q_diag": "أحتاج تشخيصًا حاسوبيًا للسيارة",
            "svc_microfix": "إصلاح سكوتر/دراجة", "q_microfix": "أحتاج إصلاح سكوتر كهربائي أو دراجة",
            "svc_boatfix": "إصلاح قارب/محرك", "q_boatfix": "أحتاج إصلاح قارب أو محرك قارب",
            "svc_realtor": "وسيط عقاري", "q_realtor": "أبحث عن وسيط عقاري",
            "svc_jurcheck": "فحص قانوني", "q_jurcheck": "أحتاج فحصًا قانونيًا للعقار",
            "svc_renovate": "تجديد شامل", "q_renovate": "أبحث عن فريق لتجديد شقة",
            "svc_mover": "نقل / عمال", "q_mover": "أحتاج عمال نقل أو نقل أثاث",
            "svc_plumb": "سباك", "q_plumb": "أحتاج سباكًا",
            "svc_electro": "كهربائي", "q_electro": "أحتاج كهربائيًا",
            "svc_wininstall": "تركيب نوافذ", "q_wininstall": "أحتاج تركيب نوافذ بلاستيكية",
            "svc_winrepair": "إصلاح نوافذ", "q_winrepair": "أحتاج إصلاح نافذة / استبدال مقبض أو عازل",
            "svc_mosquito": "شبكات البعوض", "q_mosquito": "أحتاج شبكات بعوض للنوافذ",
            "svc_phonefix": "إصلاح الهاتف", "q_phonefix": "أحتاج إصلاح هاتف",
            "svc_screen": "استبدال الشاشة", "q_screen": "أحتاج استبدال شاشة الهاتف",
            "svc_battery": "استبدال البطارية", "q_battery": "أحتاج استبدال بطارية الهاتف",
            "svc_lapfix": "إصلاح اللابتوب", "q_lapfix": "أحتاج إصلاح لابتوب",
            "svc_pcfix": "إصلاح الكمبيوتر", "q_pcfix": "أحتاج إصلاح كمبيوتر",
            "svc_upgrade": "ترقية الكمبيوتر", "q_upgrade": "أريد ترقية الكمبيوتر / استبدال القطع",
            "svc_virus": "إزالة الفيروسات", "q_virus": "أحتاج إزالة الفيروسات وضبط ويندوز",
            "svc_os": "تثبيت ويندوز", "q_os": "أحتاج تثبيت / إعادة تثبيت ويندوز",
            "svc_tvfix": "إصلاح التلفاز", "q_tvfix": "أحتاج إصلاح تلفاز",
            "svc_fridgefix": "إصلاح الثلاجة", "q_fridgefix": "أحتاج إصلاح ثلاجة",
            "svc_washfix": "إصلاح الغسالة", "q_washfix": "أحتاج إصلاح غسالة",
            "svc_acfix": "إصلاح المكيف", "q_acfix": "أحتاج إصلاح أو تنظيف مكيف",
            "svc_acinstall": "تركيب مكيف", "q_acinstall": "أحتاج تركيب مكيف",
            "svc_delivery": "توصيل / نقل", "q_delivery": "أحتاج توصيلًا أو نقلًا",
            "svc_assembly": "تركيب الأثاث", "q_assembly": "أحتاج تركيب أثاث",
            "svc_bigdeliv": "شاحنة صغيرة / كبيرة", "q_bigdeliv": "أحتاج شاحنة للنقل",
            "svc_vet": "بيطري قريب", "q_vet": "أحتاج طبيبًا بيطريًا / زيارة منزلية",
            "svc_grooming": "تجميل الحيوانات", "q_grooming": "أحتاج مزيّنًا لحيواني الأليف",
            "svc_pet-walk": "تمشية الكلاب", "q_pet-walk": "أحتاج من يمشّي كلبي",
            "svc_tailor": "خياطة / إصلاح", "q_tailor": "أحتاج خياطًا / إصلاح ملابس",
            "svc_shoefix": "إصلاح الأحذية", "q_shoefix": "أحتاج إصلاح حذاء",
            "svc_babycour": "توصيل", "q_babycour": "أحتاج توصيل مستلزمات أطفال",
            "svc_sportcour": "توصيل", "q_sportcour": "أحتاج توصيل معدات رياضية",
            "svc_trainer": "مدرب", "q_trainer": "أبحث عن مدرب شخصي",
            "svc_photosvc": "مصور", "q_photosvc": "أبحث عن مصور",
            "svc_dronsvc": "تصوير بالدرون", "q_dronsvc": "أحتاج تصويرًا جويًا / فيديو بالدرون",
            "svc_spec": "ابحث عن مختص",
        ],
    ]
}

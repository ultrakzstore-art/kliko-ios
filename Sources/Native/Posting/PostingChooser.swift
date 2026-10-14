import SwiftUI

/**
 ЭКРАН «БЫСТРО / ПОДРОБНО» — ЧИСТО И НАПОЛНЕННО (владелец 14.10.2026: «окно „быстро или подробно“ суховато — подправь,
 чтобы чисто выглядело, а то снизу пустота»; принципы: мощная анимированная подача, удобно для глаз, ровная схема,
 летает на всех девайсах).

 Сверху вниз: шапка ГеройПодачи, «Как подать объявление?», карточка «Создать объявление с ИИ» (КарточкаИИВыбораПодачи —
 только при рубильнике и ответе info), две крупные карточки одного размера — «Быстро · ~30 секунд» со схемой «Снимите →
 Kliko AI заполнит → Опубликуйте» и «Подробно · все поля» со схемой «Раздел → Фото → Данные → Цена», блок «Как продать
 быстрее» (плитки 2 × 2 одной высоты) и короткая подсказка внизу.

 Главная карточка (прошлый выбор, по умолчанию — «Быстро») заметнее: зелёная кромка, мятная заливка сверху, кружок
 значка — градиент кнопки камеры, шаги её схемы один раз подсвечиваются по очереди. Вторая — спокойная: белая карточка
 с тонкой линией, схема без подсветки.

 Компоновка (РаскладкаВыбораПодачи): на высоком экране лишняя высота уходит в карточки, промежутки и над подсказкой —
 без пустоты снизу; что сверх (iPad во весь экран) — поровну сверху и снизу, блок по центру; на маленьком — обычная
 прокрутка. Появление блоков — каскадом, один раз.

 «Уменьшение движения» и лёгкий режим (РежимУстройства): без каскада и без бега подсветки — всё сразу на месте; в лёгком
 режиме ещё и без цветной тени. Dynamic Type: на крупных размерах схема шагов — столбиком, советы — в одну колонку.
 RTL: стрелки chevron.forward, порядок HStack зеркалится сам.

 Выбор — прежний: ВыборРежимаПодачи (PostingQuick.swift) отдаёт сюда выбратьБыструюПодачу и выбратьПодробнуюПодачу.
 */
@MainActor
struct ЭкранВыбораПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    /// ПамятьРежимаПодачи.последний: "quick", "full" или nil.
    let прошлый: String?
    let закрыть: () -> Void
    let быстро: () -> Void
    let подробно: () -> Void
    @Environment(\.dynamicTypeSize) private var размерШрифта

    init(модель: ПодачаМодель, прошлый: String?, закрыть: @escaping () -> Void, быстро: @escaping () -> Void,
         подробно: @escaping () -> Void) {
        self.модель = модель
        self.прошлый = прошлый
        self.закрыть = закрыть
        self.быстро = быстро
        self.подробно = подробно
    }

    private func т(_ ключ: String) -> String { ВыборПодачиText.т(ключ) }

    var body: some View {
        let советы = списокСоветов
        return GeometryReader { окно in
            ScrollView {
                РаскладкаВыбораПодачи(минВысота: max(0, окно.size.height - 28), промежуток: 14) {
                    ГеройПодачи(правка: false, закрыть: закрыть)
                        .появлениеВыбораПодачи(0)
                    заголовок
                        .появлениеВыбораПодачи(1)
                    /* «Создать объявление с ИИ» (AIImagePosting.swift): только при Config.ииРедакторФото и ответе info. */
                    КарточкаИИВыбораПодачи(модель: модель)
                        .появлениеВыбораПодачи(2)
                    режимы
                        .layoutValue(key: РастяжкаБлокаВыбораПодачи.self,
                                     value: ЗначениеРастяжкиВыбораПодачи(вес: 3, предел: 0.4))
                    заголовокСоветов
                        .появлениеВыбораПодачи(5)
                        .layoutValue(key: ОтступПередБлокомВыбораПодачи.self,
                                     value: ОтступВыбораПодачи(величина: 22, растёт: true))
                    сетка(советы)
                        .layoutValue(key: ОтступПередБлокомВыбораПодачи.self,
                                     value: ОтступВыбораПодачи(величина: 10, растёт: false))
                        .layoutValue(key: РастяжкаБлокаВыбораПодачи.self,
                                     value: ЗначениеРастяжкиВыбораПодачи(вес: 1, предел: 0.25))
                    подсказка
                        .появлениеВыбораПодачи(6 + советы.count)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: Заголовок

    private var заголовок: some View {
        Text(т("ch_title"))
            .font(.title3.weight(.heavy))
            .foregroundStyle(КраскаПодачи.текст)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Две карточки одного размера

    private var режимы: some View {
        СеткаРавныхВыбораПодачи(колонок: 1, промежуток: 12) {
            КарточкаРежимаПодачи(значок: "bolt.fill", заголовок: т("ch_quick"), значокМеты: "clock",
                                 мета: т("ch_quick_meta"), метаГолосом: т("ch_quick_meta_ax"), подпись: т("ch_quick_s"),
                                 шаги: шагиБыстро, прошлый: прошлый == "quick", главная: прошлый != "full",
                                 действие: быстро)
                .появлениеВыбораПодачи(3)
            КарточкаРежимаПодачи(значок: "list.number", заголовок: т("ch_full"), значокМеты: "list.bullet",
                                 мета: т("ch_full_meta"), метаГолосом: т("ch_full_meta"), подпись: т("ch_full_s"),
                                 шаги: шагиПодробно, прошлый: прошлый == "full", главная: прошлый == "full",
                                 действие: подробно)
                .появлениеВыбораПодачи(4)
        }
    }

    /// Короткий путь: камера → Kliko AI (recognize) → «Проверьте» и «Опубликовать».
    private var шагиБыстро: [ШагСхемыПодачи] {
        [
            ШагСхемыПодачи(id: 0, значок: "camera.fill", подпись: т("ch_q1")),
            ШагСхемыПодачи(id: 1, значок: "sparkles", подпись: т("ch_q2")),
            ШагСхемыПодачи(id: 2, значок: "paperplane.fill", подпись: т("ch_q3"))
        ]
    }

    /// Мастер: «Что размещаете?» → Фото → Данные → Цена (дальше — адрес и проверка).
    private var шагиПодробно: [ШагСхемыПодачи] {
        [
            ШагСхемыПодачи(id: 0, значок: "square.grid.2x2", подпись: т("ch_f1")),
            ШагСхемыПодачи(id: 1, значок: "photo.on.rectangle", подпись: т("ch_f2")),
            ШагСхемыПодачи(id: 2, значок: "text.alignleft", подпись: т("ch_f3")),
            ШагСхемыПодачи(id: 3, значок: "tag.fill", подпись: т("ch_f4"))
        ]
    }

    // MARK: Как продать быстрее

    private var заголовокСоветов: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.золото)
                .accessibilityHidden(true)
            Text(т("ch_tips"))
                .font(.headline.weight(.heavy))
                .foregroundStyle(КраскаПодачи.текст)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
    }

    /// Четыре честных общих совета. Гарант на паузе или ещё ни разу не сверен — «Безопасную сделку» не обещаем:
    /// на её месте совет про описание.
    private var списокСоветов: [СоветПродажиПодачи] {
        var список: [СоветПродажиПодачи] = [
            СоветПродажиПодачи(id: "photo", значок: "sun.max.fill", заголовок: т("ch_tip_photo"),
                               подпись: т("ch_tip_photo_s"), фон: КраскаПодачи.вниманиеФон,
                               цвет: КраскаПодачи.вниманиеТекст),
            СоветПродажиПодачи(id: "price", значок: "chart.line.uptrend.xyaxis", заголовок: т("ch_tip_price"),
                               подпись: т("ch_tip_price_s"), фон: КраскаПодачи.хорошоФон,
                               цвет: КраскаПодачи.хорошоТекст),
            СоветПродажиПодачи(id: "chat", значок: "bubble.left.and.bubble.right.fill", заголовок: т("ch_tip_chat"),
                               подпись: т("ch_tip_chat_s"), фон: КраскаПодачи.инфоФон, цвет: КраскаПодачи.инфоТекст)
        ]
        if ПаузаГаранта.работаетПоСверке {
            список.append(СоветПродажиПодачи(id: "safe", значок: "lock.shield.fill", заголовок: т("ch_tip_safe"),
                                             подпись: т("ch_tip_safe_s"), фон: Theme.оттенокАкцента,
                                             цвет: Theme.акцент))
        } else {
            список.append(СоветПродажиПодачи(id: "desc", значок: "doc.text.fill", заголовок: т("ch_tip_desc"),
                                             подпись: т("ch_tip_desc_s"), фон: Theme.оттенокАкцента,
                                             цвет: Theme.акцент))
        }
        return список
    }

    /// Плитки одной высоты: две колонки, на крупном шрифте (Dynamic Type, accessibility) — одна.
    private func сетка(_ советы: [СоветПродажиПодачи]) -> some View {
        СеткаРавныхВыбораПодачи(колонок: размерШрифта.isAccessibilitySize ? 1 : 2, промежуток: 10) {
            ForEach(советы.indices, id: \.self) { номер in
                ПлиткаСоветаПодачи(совет: советы[номер])
                    .появлениеВыбораПодачи(6 + номер)
            }
        }
    }

    // MARK: Подсказка внизу

    private var подсказка: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(КраскаПодачи.акцентТекст)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(т("ch_hint"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(КраскаПодачи.поле, in: форма)
        .overlay { форма.strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Карточка режима

/// Шаг схемы на карточке режима: номер по порядку, значок и подпись.
struct ШагСхемыПодачи: Identifiable {
    let id: Int
    let значок: String
    let подпись: String
}

/**
 Крупная карточка «Быстро» или «Подробно»: кружок значка, заголовок, метка («~30 секунд» / «все поля»), «В прошлый раз»,
 подпись и схема шагов внизу. Вся карточка — кнопка. Растягивается по высоте, которую даёт сетка: лишнее — между
 подписью и схемой.
 */
@MainActor
struct КарточкаРежимаПодачи: View {
    let значок: String
    let заголовок: String
    let значокМеты: String
    let мета: String
    let метаГолосом: String
    let подпись: String
    let шаги: [ШагСхемыПодачи]
    let прошлый: Bool
    let главная: Bool
    let действие: () -> Void
    @ObservedObject private var режим = РежимУстройства.shared

    init(значок: String, заголовок: String, значокМеты: String, мета: String, метаГолосом: String, подпись: String,
         шаги: [ШагСхемыПодачи], прошлый: Bool, главная: Bool, действие: @escaping () -> Void) {
        self.значок = значок
        self.заголовок = заголовок
        self.значокМеты = значокМеты
        self.мета = мета
        self.метаГолосом = метаГолосом
        self.подпись = подпись
        self.шаги = шаги
        self.прошлый = прошлый
        self.главная = главная
        self.действие = действие
    }

    /// Цветная тень — только у главной и не в лёгком режиме; иначе — тень карточки кабинета (в тёмной теме её нет).
    private var яркаяТень: Bool { главная && !режим.лёгкий }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        return Button {
            ОткликСайта.выбор()
            действие()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                шапка
                Spacer(minLength: 16)
                СхемаШаговПодачи(шаги: шаги, главная: главная)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { фон(форма) }
            .overlay {
                форма.strokeBorder(главная ? КраскаПодачи.хорошоТекст : КраскаПодачи.линия, lineWidth: главная ? 1.5 : 1)
            }
            .shadow(color: яркаяТень ? Color(uiColor: Theme.hex(0x0F5132, 0.16)) : КраскаПодачи.тень,
                    radius: яркаяТень ? 12 : 6, y: яркаяТень ? 6 : 2)
            .contentShape(форма)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: ДвижениеСайта.сжатие))
    }

    /// Главная — карточка с мятной заливкой сверху; вторая — просто карточка.
    @ViewBuilder
    private func фон(_ форма: RoundedRectangle) -> some View {
        if главная {
            форма.fill(КраскаПодачи.карточка)
                .overlay {
                    форма.fill(LinearGradient(colors: [КраскаПодачи.хорошоФон, КраскаПодачи.хорошоФон.opacity(0)],
                                              startPoint: .top, endPoint: .bottom))
                }
        } else {
            форма.fill(КраскаПодачи.карточка)
        }
    }

    private var шапка: some View {
        HStack(alignment: .top, spacing: 12) {
            кружок
            VStack(alignment: .leading, spacing: 4) {
                /* Заголовок и метки в строку; не влезают (длинный язык, крупный шрифт) — метки под заголовком. */
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        названиеТекст
                        меткаМеты
                        if прошлый { меткаПрошлый }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        названиеТекст
                        HStack(spacing: 6) {
                            меткаМеты
                            if прошлый { меткаПрошлый }
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        названиеТекст
                        меткаМеты
                        if прошлый { меткаПрошлый }
                    }
                }
                Text(подпись)
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.bold))
                .foregroundStyle(главная ? КраскаПодачи.хорошоТекст : Theme.текстВторой)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
    }

    private var кружок: some View {
        Image(systemName: значок)
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(главная ? Color.white : КраскаПодачи.хорошоТекст)
            .frame(width: 46, height: 46)
            .background {
                if главная {
                    Circle().fill(LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    Circle().fill(КраскаПодачи.хорошоФон)
                }
            }
            .accessibilityHidden(true)
    }

    private var названиеТекст: some View {
        Text(заголовок)
            .font(.title3.weight(.heavy))
            .foregroundStyle(КраскаПодачи.текст)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// «~30 секунд» / «все поля»: часы или список, на главной — зелёным по белому с зелёной кромкой.
    private var меткаМеты: some View {
        HStack(spacing: 4) {
            Image(systemName: значокМеты)
                .font(.caption2.weight(.bold))
            Text(мета)
                .font(.caption.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(главная ? КраскаПодачи.хорошоТекст : Theme.текстВторой)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(главная ? КраскаПодачи.карточка : КраскаПодачи.поле, in: Capsule())
        .overlay {
            Capsule().strokeBorder(главная ? КраскаПодачи.хорошоТекст.opacity(0.35) : КраскаПодачи.линия, lineWidth: 1)
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(метаГолосом)
    }

    /// «В прошлый раз» — бывает только у главной: залитая зелёным, чтобы читалась на мятной заливке.
    private var меткаПрошлый: some View {
        Text(ВыборПодачиText.т("ch_last"))
            .font(.caption2.weight(.bold))
            .foregroundStyle(КраскаПодачи.карточка)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(КраскаПодачи.хорошоТекст, in: Capsule())
            .fixedSize()
    }
}

// MARK: - Схема шагов

/**
 Мини-схема пути: кружки со значками, между ними линия, подписи под кружками; колонки одной ширины. У главной карточки
 при появлении шаги один раз подсвечиваются по очереди (кружок вспыхивает и остаётся зелёным, линия к нему зеленеет),
 последний — залитый градиентом кнопки камеры. «Уменьшение движения» или лёгкий режим — сразу всё подсвечено, без
 движения. У второй карточки схема спокойная, без подсветки. На крупном шрифте (accessibility) — столбиком, без линий.
 */
@MainActor
struct СхемаШаговПодачи: View {
    let шаги: [ШагСхемыПодачи]
    let главная: Bool
    /// Последний подсвеченный шаг: −1 — ещё ни один (до прохода), шаги.count − 1 — все.
    @State private var горит: Int
    /// Шаг, который сейчас вспыхивает (чуть крупнее); −1 — ни один.
    @State private var вспышка = -1
    @State private var сыграно = false
    @Environment(\.accessibilityReduceMotion) private var безДвижения
    @Environment(\.dynamicTypeSize) private var размерШрифта
    @ObservedObject private var режим = РежимУстройства.shared

    init(шаги: [ШагСхемыПодачи], главная: Bool) {
        self.шаги = шаги
        self.главная = главная
        let проход = главная && !ДвижениеСайта.тихо && !РежимУстройства.shared.лёгкий
        _горит = State(initialValue: проход ? -1 : шаги.count - 1)
    }

    private var тихо: Bool { безДвижения || ДвижениеСайта.тихо || режим.лёгкий }

    var body: some View {
        Group {
            if размерШрифта.isAccessibilitySize {
                столбик
            } else {
                строка
            }
        }
        .task { await пройти() }
    }

    /// Один проход подсветки: пауза под каскад карточек, затем шаг за шагом; ушли с экрана посреди — всё подсвечено.
    private func пройти() async {
        guard главная, !сыграно else { return }
        сыграно = true
        guard !тихо else {
            горит = шаги.count - 1
            вспышка = -1
            return
        }
        try? await Task.sleep(nanoseconds: 450_000_000)
        for номер in шаги.indices {
            if Task.isCancelled { break }
            withAnimation(ДвижениеСайта.мягко(.spring(response: 0.32, dampingFraction: 0.62))) {
                горит = номер
                вспышка = номер
            }
            try? await Task.sleep(nanoseconds: 280_000_000)
        }
        withAnimation(ДвижениеСайта.мягко(.easeOut(duration: 0.25))) {
            горит = шаги.count - 1
            вспышка = -1
        }
    }

    private func светится(_ номер: Int) -> Bool { главная && номер <= горит }

    private var строка: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(шаги) { шаг in
                колонка(шаг)
            }
        }
    }

    private var столбик: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(шаги) { шаг in
                HStack(spacing: 10) {
                    кружок(шаг)
                    Text(шаг.подпись)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(цветПодписи(шаг.id))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Колонка шага: линия к соседям (левая половина — к предыдущему, правая — к следующему) под кружком и подпись.
    private func колонка(_ шаг: ШагСхемыПодачи) -> some View {
        VStack(spacing: 7) {
            ZStack {
                HStack(spacing: 0) {
                    отрезок(виден: шаг.id > 0, горит: светится(шаг.id))
                    отрезок(виден: шаг.id < шаги.count - 1, горит: светится(шаг.id + 1))
                }
                кружок(шаг)
            }
            Text(шаг.подпись)
                .font(.caption.weight(.semibold))
                .foregroundStyle(цветПодписи(шаг.id))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity)
    }

    private func отрезок(виден: Bool, горит: Bool) -> some View {
        Capsule()
            .fill(горит ? КраскаПодачи.хорошоТекст : Theme.текстВторой.opacity(0.22))
            .frame(height: 3)
            .frame(maxWidth: .infinity)
            .opacity(виден ? 1 : 0)
    }

    private func кружок(_ шаг: ШагСхемыПодачи) -> some View {
        let свет = светится(шаг.id)
        let финиш = свет && шаг.id == шаги.count - 1
        return Image(systemName: шаг.значок)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(цветЗначка(свет: свет, финиш: финиш))
            .frame(width: 36, height: 36)
            .background {
                ZStack {
                    /* Непрозрачная подложка: линия под кружком не просвечивает и в тёмной теме. */
                    Circle().fill(КраскаПодачи.карточка)
                    if финиш {
                        Circle().fill(LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                    } else {
                        Circle().fill(свет ? КраскаПодачи.хорошоФон : КраскаПодачи.поле)
                    }
                }
            }
            .overlay {
                Circle().strokeBorder(цветКромки(свет: свет, финиш: финиш), lineWidth: 1.5)
            }
            .scaleEffect(вспышка == шаг.id ? 1.14 : 1)
            .accessibilityHidden(true)
    }

    private func цветЗначка(свет: Bool, финиш: Bool) -> Color {
        if финиш { return Color.white }
        if свет { return КраскаПодачи.хорошоТекст }
        return главная ? Theme.текстВторой : КраскаПодачи.акцентТекст
    }

    private func цветКромки(свет: Bool, финиш: Bool) -> Color {
        if финиш { return Color.clear }
        if свет { return КраскаПодачи.хорошоТекст.opacity(0.55) }
        return КраскаПодачи.линия
    }

    private func цветПодписи(_ номер: Int) -> Color {
        светится(номер) ? КраскаПодачи.текст : Theme.текстВторой
    }
}

// MARK: - Плитка совета

/// Совет «Как продать быстрее»: значок в цветном квадрате, заголовок и подпись.
struct СоветПродажиПодачи: Identifiable {
    let id: String
    let значок: String
    let заголовок: String
    let подпись: String
    let фон: Color
    let цвет: Color
}

/// Плитка совета: растягивается по высоте ячейки сетки — все плитки ровные.
struct ПлиткаСоветаПодачи: View {
    let совет: СоветПродажиПодачи

    init(совет: СоветПродажиПодачи) {
        self.совет = совет
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            Image(systemName: совет.значок)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(совет.цвет)
                .frame(width: 34, height: 34)
                .background(совет.фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(совет.заголовок)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(КраскаПодачи.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Text(совет.подпись)
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(КраскаПодачи.карточка, in: форма)
        .overlay { форма.strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Каскад появления

/**
 Шаг каскада экрана выбора: блок поднимается на 14 pt и проявляется; каждый следующий — на 0,06 с позже. Один раз —
 при появлении экрана. «Уменьшение движения» или лёгкий режим — сразу на месте.
 */
@MainActor
struct ПоявлениеВыбораПодачи: ViewModifier {
    let номер: Int
    @State private var видно: Bool
    @Environment(\.accessibilityReduceMotion) private var безДвижения

    init(номер: Int) {
        self.номер = номер
        _видно = State(initialValue: ДвижениеСайта.тихо || РежимУстройства.shared.лёгкий)
    }

    func body(content: Content) -> some View {
        content
            .opacity(видно ? 1 : 0)
            .offset(y: видно ? 0 : 14)
            .onAppear {
                guard !видно else { return }
                guard !безДвижения else {
                    видно = true
                    return
                }
                let пружина = Animation.spring(response: 0.5, dampingFraction: 0.86).delay(0.06 * Double(номер))
                withAnimation(ДвижениеСайта.мягко(пружина)) {
                    видно = true
                }
            }
    }
}

extension View {
    /// Шаг каскада экрана «Быстро / Подробно» (ПоявлениеВыбораПодачи).
    @MainActor
    func появлениеВыбораПодачи(_ номер: Int) -> some View {
        modifier(ПоявлениеВыбораПодачи(номер: номер))
    }
}

// MARK: - Компоновка

/// Растяжка блока на высоком экране: вес — доля лишней высоты, предел — не больше этой доли собственной высоты.
struct ЗначениеРастяжкиВыбораПодачи {
    let вес: CGFloat
    let предел: CGFloat
}

struct РастяжкаБлокаВыбораПодачи: LayoutValueKey {
    static let defaultValue = ЗначениеРастяжкиВыбораПодачи(вес: 0, предел: 0)
}

/// Промежуток перед блоком: величина и растёт ли он на высоком экране (заголовок советов и их сетка держатся вместе).
struct ОтступВыбораПодачи {
    let величина: CGFloat
    let растёт: Bool
}

struct ОтступПередБлокомВыбораПодачи: LayoutValueKey {
    static let defaultValue: ОтступВыбораПодачи? = nil
}

/**
 Блоки экрана выбора сверху вниз во всю ширину. Высота — не меньше окна (минВысота): на высоком экране лишнее идёт
 сначала в блоки с растяжкой (карточки режимов, советы — не больше своего предела), потом поровну в растущие промежутки
 (не больше промежутка каждому), потом над последним блоком (не больше двух промежутков): на телефоне подсказка прижата
 к низу, пустоты под ней нет. Что осталось сверх (iPad) — поровну сверху и снизу: блок по центру, без дыры посередине.
 Пустой блок (карточка ИИ без рубильника) места и промежутка не занимает. Не влезает — высота по содержимому, прокрутка.
 */
struct РаскладкаВыбораПодачи: Layout {
    let минВысота: CGFloat
    let промежуток: CGFloat

    private struct Замер {
        var высоты: [CGFloat]
        var отступы: [CGFloat]
        var растущие: [Bool]
        var итог: CGFloat
    }

    private func замерить(_ ширина: CGFloat, _ subviews: Subviews) -> Замер {
        var замер = Замер(высоты: [], отступы: [], растущие: [], итог: 0)
        var первый = true
        for вид in subviews {
            let высота = вид.sizeThatFits(ProposedViewSize(width: ширина, height: nil)).height
            замер.высоты.append(высота)
            guard высота >= 0.5 else {
                замер.отступы.append(0)
                замер.растущие.append(false)
                continue
            }
            let свой = вид[ОтступПередБлокомВыбораПодачи.self]
            let отступ: CGFloat = первый ? 0 : (свой?.величина ?? промежуток)
            замер.отступы.append(отступ)
            замер.растущие.append(!первый && (свой?.растёт ?? true))
            замер.итог += отступ + высота
            первый = false
        }
        return замер
    }

    private func идеальнаяШирина(_ subviews: Subviews) -> CGFloat {
        subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ширина = proposal.width ?? идеальнаяШирина(subviews)
        let замер = замерить(ширина, subviews)
        return CGSize(width: ширина, height: max(замер.итог, минВысота))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let замер = замерить(bounds.width, subviews)
        let видимые = subviews.indices.filter { замер.высоты[$0] >= 0.5 }
        var лишнее = max(0, bounds.height - замер.итог)
        var добавки = [CGFloat](repeating: 0, count: subviews.count)

        /* 1. Растяжка блоков по весам, не больше предела. */
        let суммаВесов = видимые.reduce(CGFloat(0)) { $0 + subviews[$1][РастяжкаБлокаВыбораПодачи.self].вес }
        if лишнее > 0.5 && суммаВесов > 0 {
            let всего = лишнее
            for номер in видимые {
                let растяжка = subviews[номер][РастяжкаБлокаВыбораПодачи.self]
                guard растяжка.вес > 0 else { continue }
                let доля = всего * растяжка.вес / суммаВесов
                добавки[номер] = min(доля, замер.высоты[номер] * растяжка.предел).rounded(.down)
                лишнее -= добавки[номер]
            }
        }

        /* 2. Растущие промежутки — поровну, не больше обычного промежутка каждому. */
        let растущих = видимые.filter { замер.растущие[$0] }.count
        var кПромежутку: CGFloat = 0
        if растущих > 0 && лишнее > 0.5 {
            кПромежутку = min(лишнее / CGFloat(растущих), промежуток).rounded(.down)
            лишнее -= кПромежутку * CGFloat(растущих)
        }

        /* 3. Остаток: над последним блоком (подсказкой) — не больше двух промежутков, она держится у советов. Что сверх
           (iPad во весь экран: колонка 640 pt, окно до ~1300 pt) — поровну сверху и снизу: блок по центру окна, а не
           пустая полоса посреди экрана между советами и подсказкой. */
        let последний = видимые.last
        let надПоследним = видимые.count > 1 ? min(max(0, лишнее), промежуток * 2).rounded(.down) : 0
        let сверху = (max(0, лишнее - надПоследним) / 2).rounded(.down)
        var y = bounds.minY + сверху
        for номер in subviews.indices {
            let видим = замер.высоты[номер] >= 0.5
            if видим {
                y += замер.отступы[номер]
                if замер.растущие[номер] { y += кПромежутку }
                if номер == последний && номер != видимые.first { y += надПоследним }
            }
            let высота = замер.высоты[номер] + добавки[номер]
            subviews[номер].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: bounds.width, height: высота))
            if видим { y += высота }
        }
    }
}

/**
 Сетка ячеек одной высоты (самой высокой по содержимому): колонок — сколько сказано, неполный последний ряд делит
 ширину поровну (одна плитка — во всю ширину). Дают больше высоты — ячейки растут поровну; бесконечность или меньше
 содержимого — высота по содержимому.
 */
struct СеткаРавныхВыбораПодачи: Layout {
    let колонок: Int
    let промежуток: CGFloat

    private func ряды(_ число: Int) -> [Range<Int>] {
        let к = max(1, колонок)
        return stride(from: 0, to: число, by: к).map { $0 ..< min($0 + к, число) }
    }

    private func ширинаЯчейки(_ ряд: Range<Int>, _ ширина: CGFloat) -> CGFloat {
        let n = CGFloat(max(1, ряд.count))
        return max(0, (ширина - (n - 1) * промежуток) / n)
    }

    private func высотаЯчейки(_ ширина: CGFloat, _ subviews: Subviews) -> CGFloat {
        var наибольшая: CGFloat = 0
        for ряд in ряды(subviews.count) {
            let w = ширинаЯчейки(ряд, ширина)
            for номер in ряд {
                наибольшая = max(наибольшая, subviews[номер].sizeThatFits(ProposedViewSize(width: w, height: nil)).height)
            }
        }
        return наибольшая
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let всего = ряды(subviews.count).count
        guard всего > 0 else { return .zero }
        let к = CGFloat(max(1, колонок))
        let ширина = proposal.width
            ?? (к * (subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0) + (к - 1) * промежуток)
        let n = CGFloat(всего)
        let естественная = высотаЯчейки(ширина, subviews) * n + (n - 1) * промежуток
        if let h = proposal.height, h.isFinite, h > естественная {
            return CGSize(width: ширина, height: h)
        }
        return CGSize(width: ширина, height: естественная)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let все = ряды(subviews.count)
        guard !все.isEmpty else { return }
        let n = CGFloat(все.count)
        let ячейка = max(высотаЯчейки(bounds.width, subviews), (bounds.height - (n - 1) * промежуток) / n)
        var y = bounds.minY
        for ряд in все {
            let w = ширинаЯчейки(ряд, bounds.width)
            var x = bounds.minX
            for номер in ряд {
                subviews[номер].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: w, height: ячейка))
                x += w + промежуток
            }
            y += ячейка + промежуток
        }
    }
}

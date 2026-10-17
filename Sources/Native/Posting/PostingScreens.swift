import SwiftUI
import UIKit

/**
 ПОДАЧА — ШАПКИ, СТАРТ «ЧТО РАЗМЕЩАЕТЕ?», ГОСТЬ, ОКНА «KLIKO AI РАСПОЗНАЁТ» И ИТОГА ПОДАЧИ (этап 42, по CSS кабинета).

 Шапка шагов — градиентная .ehero #add-screen (прокручивается вместе со страницей), у старта — .rw2-hd с «+» или «‹»,
 у загрузки, ошибки и гостя — простая строка с «✕». Окно распознавания — #airec-modal с «Заполнить вручную»
 (airecManual), окно итога — _modOver сайта; длинный текст сервера прокручивается, кнопки всегда видны.
 */

// MARK: - Простая шапка

/// Строка «Новое объявление» и «✕» — у загрузки, ошибки и гостя (своей шапки у них на сайте нет).
struct ШапкаПодачи: View {
    let правка: Bool
    let закрыть: () -> Void

    init(правка: Bool, закрыть: @escaping () -> Void) {
        self.правка = правка
        self.закрыть = закрыть
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(ПодачаText.т(правка ? "edit_title" : "form_title_new"))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(КраскаПодачи.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            КнопкаЗакрытьПодачи(действие: закрыть)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(КраскаПодачи.карточка)
        .overlay(alignment: .bottom) {
            Rectangle().fill(КраскаПодачи.линия).frame(height: 1)
        }
    }
}

/// «✕» .rw2-x: 34×34, скругление 10, на --surf2.
struct КнопкаЗакрытьПодачи: View {
    let действие: () -> Void

    init(действие: @escaping () -> Void) {
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(КраскаПодачи.текст)
                .frame(width: 34, height: 34)
                .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ПодачаText.т("close"))
    }
}

// MARK: - Градиентная шапка шагов (.ehero)

/// #add-screen .ehero: градиент 135° --g2 → --g, скругление 14, блик в углу, «Новое объявление», подзаголовок,
/// справа круглая кнопка (на сайте «?», здесь «✕») и плашка «Черновик» (в правке — «Опубликовано»).
struct ГеройПодачи: View {
    let правка: Bool
    let закрыть: () -> Void

    init(правка: Bool, закрыть: @escaping () -> Void) {
        self.правка = правка
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    /// Тёмная тема и правка — затемнение linear-gradient(rgba(6,10,14,.44), rgba(6,10,14,.52)).
    private var затемнение: Color {
        if правка { return Color(uiColor: Theme.hex(0x060A0E, 0.48)) }
        return Theme.цвет(светлый: Theme.hex(0x060A0E, 0), тёмный: Theme.hex(0x060A0E, 0.48))
    }

    /**
     Заголовок и подзаголовок слева, «✕» — в правом верхнем углу на линии заголовка, «Черновик» — под подзаголовком.
     Блик — наложением на градиент: размер шапки задаёт её текст (раньше круг 180×180 в фоне растягивал зелёную
     подложку выше и ниже шапки, и полоса типа «Легковая / Изменить» наезжала на неё).
     */
    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(т(правка ? "edit_title" : "form_title_new"))
                        .font(.system(size: 19, weight: .heavy))
                        .kerning(-0.3)
                        .foregroundStyle(Color.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(т(правка ? "edit_sub" : "form_hero_sub"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: закрыть) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.2), in: Circle())
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 1) }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(т("close"))
            }
            плашка
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [Theme.зелёный2, Theme.зелёный], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay { затемнение }
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0)], center: .center,
                                             startRadius: 0, endRadius: 63))
                        .frame(width: 180, height: 180)
                        .offset(x: 50, y: -50)
                        .allowsHitTesting(false)
                }
                .clipShape(форма)
        }
        .shadow(color: Color(uiColor: Theme.hex(0x0F5132, 0.22)), radius: 6, y: 4)
    }

    /// .estatus: точка --acc-rgb2 с кольцом 30 %, 11/700 белым на белом 20 %.
    private var плашка: some View {
        let точка = Color(uiColor: Theme.hex(0x34C997))
        return HStack(spacing: 6) {
            Circle()
                .fill(точка)
                .frame(width: 6, height: 6)
                .background(Circle().fill(точка.opacity(0.3)).frame(width: 12, height: 12))
                .accessibilityHidden(true)
            Text(т(правка ? "edit_pill" : "draft"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.2), in: Capsule())
    }
}

// MARK: - Стартовый экран «Что размещаете?»

/**
 Старт подачи в схеме главной (владелец 14.10.2026, по скринам: «белые одинаковые высокие плитки с тонкой иконкой,
 много пустоты, сухо»; «удобно для глаз, ровная схема везде, мощная анимированная подача, летает на всех девайсах»).

 Плитки — как плитки разделов главной (ПлиткаРаздела, SiteHome.swift): у каждой краска своего раздела, градиент, круг в
 углу, название и подпись слева сверху, картинка раздела с сайта справа снизу (ПлиткаСтартаПодачи ниже). Все плитки
 одной высоты на всех экранах старта, нечётная последняя — во всю ширину, как седьмая плитка главной. Подэкраны («Что за
 товар?», сделка, вид недвижимости…) — в краске родителя, со значком в круге.

 Движение: экран старта сменяется въездом на 28 pt со стороны хода и проявлением, прежний гаснет; плитки встают
 лесенкой (ПоявлениеЛесенкой) — всё вместе до 0,35 с. Нажатие — 0,97 и щелчок (ОткликСайта). «Уменьшение движения» —
 без въезда и лесенки. Смахивание от края — то же, что «‹» в шапке (EdgeSwipeBack.swift).
 Без GeometryReader: прежняя растяжка плиток до 1,4 × по высоте окна и давала «много пустоты».
 */
struct СтартПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    let работа: () -> Void
    let перенос: () -> Void
    let закрыть: () -> Void
    /// Куда идём: плитка — вперёд, новый экран въезжает с края «далее»; «‹» и смахивание — назад, с края «назад».
    /// Ставится в том же нажатии, что и смена экрана, — переход нового экрана сразу берёт верную сторону.
    @State private var вперёд = true
    @Environment(\.layoutDirection) private var направление

    init(модель: ПодачаМодель, работа: @escaping () -> Void, перенос: @escaping () -> Void,
         закрыть: @escaping () -> Void) {
        self.модель = модель
        self.работа = работа
        self.перенос = перенос
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    /// Плитка: ключ, заголовок, подпись, значок.
    private struct Плитка: Identifiable {
        let id: String
        let заголовок: String
        let подпись: String
        let значок: String
    }

    var body: some View {
        VStack(spacing: 0) {
            шапка
            ZStack(alignment: .top) {
                экран
                    .id(ключЭкрана)
                    .transition(переход)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(ДвижениеСайта.шаг, value: ключЭкрана)
        }
        /* Смахнуть от края — то же, что «‹» в шапке; нет её (корень правки, там «+») — нет и жеста. */
        .смахиваниеНазад(включено: естьНазад) { назад() }
        /* Раньше это делал экран «Быстро / Подробно»: есть ли генератор иллюстраций — лениво (info). */
        .task {
            if !модель.правка { await ГотовностьИИФото.shared.проверить() }
        }
    }

    /// «‹» в шапке есть везде, кроме корня правки.
    private var естьНазад: Bool {
        !(модель.старт == .корень && модель.правка)
    }

    /// Ключ экрана старта: новый ключ — новый экран (и своя прокрутка с начала).
    private var ключЭкрана: String {
        switch модель.старт {
        case .корень: return "root"
        case .товар: return "goods"
        case .одежда: return "clothing"
        case .животные: return "animals"
        case .аренда: return "rentgood"
        case .сделка: return "realty"
        case .видНедвижимости(let сделка): return "realty-" + сделка
        case .транспорт: return "auto"
        }
    }

    /// Новый экран въезжает на 28 pt со стороны хода и проявляется; прежний гаснет вдвое быстрее — два экрана не стоят
    /// друг на друге. В арабском стороны зеркальны: offset сам не зеркалится.
    private var переход: AnyTransition {
        let сторона: CGFloat = (вперёд ? 1 : -1) * (направление == .rightToLeft ? -1 : 1)
        return .asymmetric(insertion: AnyTransition.offset(x: 28 * сторона).combined(with: .opacity),
                           removal: AnyTransition.opacity.animation(ДвижениеСайта.мягко(.easeOut(duration: 0.12))))
    }

    /// Экран старта: вопрос, подсказка, плитки; у «Сдать вещь» — срок, у корня — перенос по ссылке.
    private var экран: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(вопрос)
                    .font(.system(size: 20, weight: .heavy))
                    .kerning(-0.3)
                    .foregroundStyle(КраскаПодачи.текст)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(подсказка)
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                сетка
                    .padding(.top, 16)
                if модель.старт == .аренда {
                    срокАренды
                        .modifier(ПоявлениеЛесенкой(номер: плитки.count))
                }
                if модель.старт == .корень {
                    переносСсылкой
                        .modifier(ПоявлениеЛесенкой(номер: плитки.count))
                }
                /* Пачка 83: экрана «Быстро / Подробно» нет — сюда приходят по «Подробно» или по памяти выбора;
                   короткий путь — ссылкой (PostingQuick.swift). */
                if модель.старт == .корень && !модель.правка {
                    СсылкаПутиПодачи(ВыборПодачиText.т("ch_quick_cam"), значок: "camera") {
                        ОткликСайта.выбор()
                        модель.выбратьБыструюПодачу()
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .modifier(ПоявлениеЛесенкой(номер: плитки.count + 1))
                }
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 24, trailing: 20))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Шапка .rw2-hd

    private var шапка: some View {
        HStack(spacing: 12) {
            if модель.старт == .корень && модель.правка {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                               endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .shadow(color: Color(uiColor: Theme.hex(0x34C997, 0.4)), radius: 6, y: 6)
                    .accessibilityHidden(true)
            } else {
                Button { назад() } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(КраскаПодачи.текст)
                        .frame(width: 34, height: 34)
                        .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.94))
                .accessibilityLabel(т("back"))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(т("form_title_new"))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(КраскаПодачи.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                подзаголовокШапки
            }
            Spacer(minLength: 0)
            КнопкаЗакрытьПодачи(действие: закрыть)
        }
        .padding(.top, 16)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .background(КраскаПодачи.карточка)
        .overlay(alignment: .bottom) {
            Rectangle().fill(КраскаПодачи.линия).frame(height: 1)
        }
    }

    /// Подпись шапки: на подэкране — точка краски раздела перед его именем (та же краска, что у плиток ниже).
    private var подзаголовокШапки: some View {
        HStack(spacing: 6) {
            if модель.старт != .корень {
                Circle()
                    .fill(Color(uiColor: Theme.hex(краскаЭкрана)))
                    .frame(width: 7, height: 7)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityHidden(true)
            }
            Text(подзаголовок)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentTransition(.opacity)
        }
        .animation(ДвижениеСайта.смена, value: ключЭкрана)
    }

    /// #as-sub: на корне «Выберите, что размещаете», ниже — имя раздела.
    private var подзаголовок: String {
        switch модель.старт {
        case .корень: return т("as_sub")
        case .товар: return т("as_goods")
        case .одежда: return т("as_clothing")
        case .животные: return т("as_animals")
        case .аренда: return т("as_rentgood")
        case .сделка, .видНедвижимости: return т("as_realty")
        case .транспорт: return т("as_auto")
        }
    }

    // MARK: Плитки .rw2-tiles

    /// Сетка 2 × 1fr, как .mh-hub главной: плитки одной высоты, нечётная последняя — во всю ширину (седьмая плитка
    /// главной), без дыры справа.
    private var сетка: some View {
        let все = плитки
        let рядов = (все.count + 1) / 2
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(0..<рядов, id: \.self) { р in
                GridRow {
                    if р * 2 + 1 < все.count {
                        плитка(все[р * 2], номер: р * 2)
                        плитка(все[р * 2 + 1], номер: р * 2 + 1)
                    } else {
                        плитка(все[р * 2], номер: р * 2)
                            .gridCellColumns(2)
                    }
                }
            }
        }
    }

    private func плитка(_ п: Плитка, номер: Int) -> some View {
        ПлиткаСтартаПодачи(заголовок: п.заголовок, подпись: п.подпись, значок: п.значок, краска: краскаПлитки(п.id),
                           картинка: картинкаПлитки(п.id), ключЗначка: ключЗначка(п.id)) {
            нажата(п.id)
        }
        .frame(maxWidth: .infinity)
        .modifier(ПоявлениеЛесенкой(номер: номер))
    }

    // MARK: Краски и картинки плиток

    /// Плитка корня → раздел главной (РазделГлавной, SiteHome.swift): его краска и картинка /img/cat-<ключ>.webp.
    /// У одежды и «Сдать вещь» раздела на главной нет.
    private static let разделыГлавной: [String: String] = [
        "animals": "animals", "goods": "goods", "realty": "realty", "auto": "transport", "services": "services",
        "jobs": "jobs"
    ]

    /// Краска плитки корня — --vc того же раздела на главной; у одежды и «Сдать вещь» — из той же палитры: розовая
    /// одежда рядом с сиреневыми «Животными», небесная «Сдать вещь» рядом с фиолетовой «Работой» и бирюзовыми «Услугами».
    private static func краскаКорня(_ id: String) -> UInt32 {
        if let ключ = разделыГлавной[id], let раздел = РазделГлавной.с(ключом: ключ) { return раздел.краска }
        switch id {
        case "clothing": return 0xDB2777
        case "rentgood": return 0x0284C7
        default: return КарточкаПереносаПодачи.краска
        }
    }

    /// Краска подэкрана — краска плитки корня, с которой пришли.
    private var краскаЭкрана: UInt32 {
        switch модель.старт {
        case .корень: return КарточкаПереносаПодачи.краска
        case .товар: return Self.краскаКорня("goods")
        case .одежда: return Self.краскаКорня("clothing")
        case .животные: return Self.краскаКорня("animals")
        case .аренда: return Self.краскаКорня("rentgood")
        case .сделка, .видНедвижимости: return Self.краскаКорня("realty")
        case .транспорт: return Self.краскаКорня("auto")
        }
    }

    /// На корне у каждой плитки своя краска, на подэкранах — краска родителя.
    private func краскаПлитки(_ id: String) -> UInt32 {
        модель.старт == .корень ? Self.краскаКорня(id) : краскаЭкрана
    }

    /// Картинка раздела с сайта — у плиток корня, у которых есть раздел на главной; у прочих — значок в круге.
    private func картинкаПлитки(_ id: String) -> URL? {
        guard модель.старт == .корень, let ключ = Self.разделыГлавной[id] else { return nil }
        return РазделГлавной.с(ключом: ключ)?.картинка
    }

    /// 16.10.2026: значок корня в стиле iOS (ИконкаРаздела, CategoryIcons.swift) — у всех плиток корня, и у одежды и
    /// «Сдать вещь» тоже, чтобы сетка была ровной: ключ раздела главной или сам id («clothing», «rentgood»). На
    /// подэкранах и при выключенном Config.нативныеЗначкиРазделов — nil: картинка сайта или значок в круге, как было.
    private func ключЗначка(_ id: String) -> String? {
        guard Config.нативныеЗначкиРазделов, модель.старт == .корень else { return nil }
        return Self.разделыГлавной[id] ?? id
    }

    // MARK: «Или сразу укажите срок» (_ASTART_RENT)

    private var срокАренды: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(т("as_rent_lbl").uppercased())
                .font(.system(size: 11, weight: .heavy))
                .kerning(0.66)
                .foregroundStyle(КраскаПодачи.текст.opacity(0.58))
            HStack(spacing: 8) {
                чипСрока(т("as_rent_day"), период: "day")
                чипСрока(т("as_rent_month"), период: "month")
            }
        }
        .padding(.top, 18)
    }

    /// .rw2-chip: сразу форма без раздела с этим сроком (_asRentGo('', период)).
    private func чипСрока(_ подпись: String, период: String) -> some View {
        Button {
            ОткликСайта.выбор()
            модель.применитьСтарт(тип: "rentgood", раздел: "", плитка: т("as_rentgood"), подсказка: "", период: период,
                                  подпись: т("as_rentgood_s"))
        } label: {
            Text(подпись)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(КраскаПодачи.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 46)
                .background(КраскаПодачи.карточка, in: Capsule())
                .overlay { Capsule().strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
                .contentShape(Capsule())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
    }

    // MARK: Перенос по ссылке (.li-entry)

    private var переносСсылкой: some View {
        КарточкаПереносаПодачи(заголовок: т("li_entry_t"), подпись: т("li_entry_s")) {
            ОткликСайта.выбор()
            перенос()
        }
        .padding(.top, 14)
    }

    // MARK: Тексты и плитки

    private var вопрос: String {
        switch модель.старт {
        case .корень: return т("as_root_q")
        case .товар: return т("as_goods_q")
        case .одежда: return т("as_cloth_q")
        case .животные: return т("as_anim_q")
        case .аренда: return т("as_rent_q")
        case .сделка: return т("as_rl_deal_q")
        case .видНедвижимости: return т("as_rl_kind_q")
        case .транспорт: return т("as_auto_q")
        }
    }

    private var подсказка: String {
        switch модель.старт {
        case .корень: return т("as_root_s")
        case .товар: return т("as_goods_s")
        case .одежда: return т("as_cloth_s")
        case .животные: return т("as_anim_s")
        case .аренда: return т("as_rent_s")
        case .сделка: return т("as_rl_deal_s")
        case .видНедвижимости: return т("as_rl_kind_s")
        case .транспорт: return т("as_auto_s")
        }
    }

    /// _ASTART, _ASTART_GOODS, _ASTART_CLOTH, _ASTART_ANIMALS, _ASTART_RENT, _ASTART_REALTY, _ASTART_AUTO сайта.
    private var плитки: [Плитка] {
        switch модель.старт {
        case .корень:
            return [
                Плитка(id: "clothing", заголовок: т("as_clothing"), подпись: т("as_clothing_s"), значок: "tshirt"),
                Плитка(id: "animals", заголовок: т("as_animals"), подпись: т("as_animals_s"), значок: "pawprint"),
                Плитка(id: "goods", заголовок: т("as_goods"), подпись: т("as_goods_sub"), значок: "shippingbox"),
                Плитка(id: "realty", заголовок: т("as_realty"), подпись: т("as_realty_s"), значок: "house"),
                Плитка(id: "auto", заголовок: т("as_auto"), подпись: т("as_auto_sub"), значок: "car"),
                Плитка(id: "services", заголовок: т("as_services"), подпись: т("as_services_s"), значок: "wrench.and.screwdriver"),
                Плитка(id: "jobs", заголовок: т("as_jobs"), подпись: т("as_jobs_s"), значок: "briefcase"),
                Плитка(id: "rentgood", заголовок: т("as_rentgood"), подпись: т("as_rentgood_s"), значок: "arrow.triangle.2.circlepath")
            ]
        case .товар:
            return [
                Плитка(id: "smartphones|phone", заголовок: т("g_phone"), подпись: т("g_phone_s"), значок: "iphone"),
                Плитка(id: "laptops|laptop", заголовок: т("g_laptop"), подпись: т("g_laptop_s"), значок: "laptopcomputer"),
                Плитка(id: "appliances|appliance", заголовок: т("g_appl"), подпись: т("g_appl_s"), значок: "washer"),
                Плитка(id: "tv-audio|appliance", заголовок: т("g_tv"), подпись: т("g_tv_s"), значок: "tv"),
                Плитка(id: "furniture|furniture", заголовок: т("g_furn"), подпись: т("g_furn_s"), значок: "sofa"),
                Плитка(id: "|other", заголовок: т("g_other"), подпись: т("g_other_s"), значок: "shippingbox")
            ]
        case .одежда:
            return [
                Плитка(id: "womens-clothing|clothes", заголовок: т("c_women"), подпись: т("c_women_s"), значок: "tshirt"),
                Плитка(id: "mens-clothing|clothes", заголовок: т("c_men"), подпись: т("c_men_s"), значок: "tshirt"),
                Плитка(id: "kids-clothing|clothes", заголовок: т("c_kids"), подпись: т("c_kids_s"), значок: "figure.and.child.holdinghands"),
                Плитка(id: "shoes|shoes", заголовок: т("c_shoes"), подпись: т("c_shoes_s"), значок: "shoeprints.fill"),
                Плитка(id: "bags-accessories|clothes", заголовок: т("c_bags"), подпись: т("c_bags_s"), значок: "bag"),
                Плитка(id: "jewelry|other", заголовок: т("c_jewel"), подпись: т("c_jewel_s"), значок: "sparkles")
            ]
        case .животные:
            return [
                Плитка(id: "dogs|", заголовок: т("a_dogs"), подпись: т("a_dogs_s"), значок: "pawprint"),
                Плитка(id: "cats|", заголовок: т("a_cats"), подпись: т("a_cats_s"), значок: "cat"),
                Плитка(id: "birds|", заголовок: т("a_birds"), подпись: т("a_birds_s"), значок: "bird"),
                Плитка(id: "livestock|", заголовок: т("a_stock"), подпись: т("a_stock_s"), значок: "hare"),
                Плитка(id: "rodents|", заголовок: т("a_rod"), подпись: т("a_rod_s"), значок: "hare"),
                Плитка(id: "fish-aquariums|", заголовок: т("a_fish"), подпись: т("a_fish_s"), значок: "fish"),
                Плитка(id: "pet-food-care|", заголовок: т("a_food"), подпись: т("a_food_s"), значок: "takeoutbag.and.cup.and.straw"),
                Плитка(id: "animals|", заголовок: т("g_other"), подпись: т("g_other_s"), значок: "pawprint")
            ]
        case .аренда:
            return [
                Плитка(id: "power-tools|", заголовок: т("r_tools"), подпись: т("r_tools_s"), значок: "hammer"),
                Плитка(id: "electronics|", заголовок: т("r_tech"), подпись: т("r_tech_s"), значок: "camera"),
                Плитка(id: "sport|", заголовок: т("r_sport"), подпись: т("r_sport_s"), значок: "figure.hiking"),
                Плитка(id: "home-garden|", заголовок: т("r_home"), подпись: т("r_home_s"), значок: "leaf"),
                Плитка(id: "|", заголовок: т("g_other"), подпись: т("g_other_s"), значок: "shippingbox")
            ]
        case .сделка:
            return [
                Плитка(id: "sale", заголовок: т("as_rl_sale"), подпись: "", значок: "house"),
                Плитка(id: "rent", заголовок: т("as_rl_rent"), подпись: "", значок: "key")
            ]
        case .видНедвижимости:
            var виды = [
                Плитка(id: "apartment|apartments", заголовок: т("rl_flat"), подпись: т("rl_flat_s"), значок: "building.2"),
                Плитка(id: "house|houses", заголовок: т("rl_house"), подпись: т("rl_house_s"), значок: "house"),
                Плитка(id: "commercial|commercial-realty", заголовок: т("rl_office"), подпись: т("rl_office_s"), значок: "building"),
                Плитка(id: "land|land", заголовок: т("rl_land"), подпись: т("rl_land_s"), значок: "map")
            ]
            /* «Гараж, паркинг» (realty.kind = garage, сайт 14.10.2026) — когда раздел есть в дереве сайта. */
            if модель.справочники.разделы["garages-parking"] != nil {
                виды.append(Плитка(id: "garage|garages-parking", заголовок: ПодачаСайтаText.т("rl_garage"),
                                   подпись: ПодачаСайтаText.т("rl_garage_s"), значок: "parkingsign.circle"))
            }
            return виды
        case .транспорт:
            return [
                Плитка(id: "cars", заголовок: т("t_cars"), подпись: т("t_cars_s"), значок: "car"),
                Плитка(id: "motorcycles", заголовок: т("t_moto"), подпись: т("t_moto_s"), значок: "bicycle"),
                Плитка(id: "trucks-special", заголовок: т("t_truck"), подпись: т("t_truck_s"), значок: "truck.box"),
                Плитка(id: "auto-parts", заголовок: т("t_parts"), подпись: т("t_parts_s"), значок: "gearshape.2"),
                Плитка(id: "water-transport", заголовок: т("t_water"), подпись: т("t_water_s"), значок: "sailboat")
            ]
        }
    }

    /// ADD_HINTS сайта: подсказка Kliko AI по чипу — идёт на сервер как есть (по-русски, её читает модель).
    private static let подсказки: [String: String] = [
        "phone": "Это смартфон/мобильный телефон", "laptop": "Это ноутбук", "clothes": "Это одежда",
        "shoes": "Это обувь", "furniture": "Это мебель", "appliance": "Это бытовая техника"
    ]

    private func нажата(_ id: String) {
        ОткликСайта.выбор()
        вперёд = true
        let подпись = подписьПлитки(id)
        let под = подзаголовокПлитки(id)
        switch модель.старт {
        case .корень:
            if id == "jobs" {
                /* Мастер «Работы» шлёт в /api/jobs.php свой набор полей (jobWizOpen) — свой мастер МастерРезюме
                   (cabinet?add=jobs перехватывают НативныеОкна). */
                работа()
                return
            }
            модель.выбратьПлитку(id)
        case .товар, .одежда:
            let части = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let раздел = части.first ?? ""
            let чип = части.count > 1 ? части[1] : ""
            модель.применитьСтарт(тип: "goods", раздел: раздел, плитка: подпись, подсказка: Self.подсказки[чип] ?? "",
                                  подпись: под)
        case .животные:
            let раздел = id.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            модель.применитьСтарт(тип: "goods", раздел: раздел, плитка: подпись, подсказка: "", подпись: под)
        case .аренда:
            let раздел = id.split(separator: "|", omittingEmptySubsequences: false).first.map(String.init) ?? ""
            модель.применитьСтарт(тип: "rentgood", раздел: раздел, плитка: подпись, подсказка: "", период: nil,
                                  подпись: под)
        case .сделка:
            модель.старт = .видНедвижимости(id)
        case .видНедвижимости(let сделка):
            let части = id.split(separator: "|").map(String.init)
            guard части.count == 2 else { return }
            модель.применитьНедвижимость(сделка: сделка, вид: части[0], раздел: части[1])
        case .транспорт:
            /* _asAutoGo: ADD_TYPE="" — тип «транспорт» без отдельного значения; уточнение кузова — первым шагом мастера авто (_asRenderAutoKids), потом марка и модель. */
            модель.применитьСтарт(тип: "", раздел: id, плитка: подпись, подсказка: "", подпись: под)
        }
    }

    private func подписьПлитки(_ id: String) -> String {
        плитки.first(where: { $0.id == id })?.заголовок ?? ""
    }

    private func подзаголовокПлитки(_ id: String) -> String {
        плитки.first(where: { $0.id == id })?.подпись ?? ""
    }

    private func назад() {
        вперёд = false
        switch модель.старт {
        case .видНедвижимости:
            модель.старт = .сделка
        case .корень:
            /* Новое объявление начинается с камеры: «Назад» с «Что размещаете?» — обратно к фото. */
            модель.кКамере()
        default:
            модель.старт = .корень
        }
    }
}

// MARK: - Плитка старта (в схеме .mh-tile главной)

/**
 Плитка старта подачи — как светлая плитка раздела главной (ПлиткаРаздела, SiteHome.swift): градиент по краске раздела,
 круг краски за правым нижним краем, название и подпись слева сверху, картинка раздела справа снизу. Картинки нет (у
 одежды, «Сдать вещь», на подэкранах), она ещё не пришла или нет сети — на её месте значок в круге краски (КружокСтарта):
 рамка постоянная, догрузка ничего не сдвигает. Высота одна на всех экранах старта — ровная схема.
 С 16.10.2026 у плиток корня вместо картинки сайта — значок раздела в стиле iOS (ключЗначка, ИконкаРаздела), у всех
 восьми, включая одежду и «Сдать вещь»; подэкраны — со значком в круге, как были.

 Лёгкая: без тени у картинки и без размытия — градиент, круг, картинка, текст и кромка в 1 pt.
 */
private struct ПлиткаСтартаПодачи: View {
    let заголовок: String
    let подпись: String
    let значок: String
    let краска: UInt32
    let картинка: URL?
    /// Ключ нативного значка корня (ИконкаРаздела) вместо картинки и круга; nil — картинка или значок в круге.
    let ключЗначка: String?
    let действие: () -> Void
    @Environment(\.colorScheme) private var схема
    /// Нажатий — растёт, и знак нативного значка отскакивает.
    @State private var прыжок = 0

    init(заголовок: String, подпись: String, значок: String, краска: UInt32, картинка: URL?, ключЗначка: String?,
         действие: @escaping () -> Void) {
        self.заголовок = заголовок
        self.подпись = подпись
        self.значок = значок
        self.краска = краска
        self.картинка = картинка
        self.ключЗначка = ключЗначка
        self.действие = действие
    }

    /// Высота плитки: у нижних плиток главной 88, здесь на 4 больше — под подпись в три строки.
    private static let высота: CGFloat = 92
    /// Рамка картинки (и значка в круге) справа снизу; подпись отступает от неё.
    private static let рамка: CGFloat = 50
    /// Размер картинки для загрузчика — как у светлой плитки главной (высота 88 × 0,88): КартинкиЛенты хранит её по
    /// адресу и размеру, и показанная на главной картинка здесь берётся из памяти с первого кадра, без сети.
    private static let пунктовКартинки: CGFloat = 88 * 0.88

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        let к = Theme.hex(краска)
        return Button(action: { прыжок += 1; действие() }) {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(stops: КраскаПлиткиСтарта.остановки(к, тёмная: тёмная),
                               startPoint: UnitPoint(x: 0.25, y: 0), endPoint: UnitPoint(x: 0.75, y: 1))
                /* ::after главной — круг 104 за правым нижним краем: 10 % краски, в тёмной 16 %. */
                Circle()
                    .fill(Color(uiColor: к).opacity(тёмная ? 0.16 : 0.1))
                    .frame(width: 104, height: 104)
                    .offset(x: 22, y: 30)
                Group {
                    if let ключЗначка {
                        /* 16.10.2026: значок корня в стиле iOS 44 в той же рамке (ИконкаРаздела, CategoryIcons.swift). */
                        ИконкаРаздела(ключ: ключЗначка, сторона: 44, прыжок: прыжок)
                    } else {
                        КартинкаЛенты(картинка, пунктов: Self.пунктовКартинки, заполнить: false) {
                            КружокСтарта(значок: значок, краска: к)
                        }
                    }
                }
                .frame(width: Self.рамка, height: Self.рамка)
                .padding(.trailing, 8)
                .padding(.bottom, 7)
                .accessibilityHidden(true)
                подписи(к)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: Self.высота)
            .clipShape(форма)
            .overlay { форма.strokeBorder(КраскаПлиткиСтарта.кромка(к, тёмная: тёмная), lineWidth: 1) }
            .contentShape(форма)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(подпись.isEmpty ? заголовок : заголовок + ", " + подпись)
        .accessibilityAddTraits(.isButton)
    }

    /// Название — во всю ширину (картинка ниже его строки), подпись — до трёх строк левее картинки: «студия, комнаты,
    /// новостройка», казахские и арабские подписи в две строки по 86 pt (iPhone SE) не влезают, а по высоте третья строка
    /// входит (12 + 18 + 3 + 3 × 14 = 75 из 92).
    private func подписи(_ к: UIColor) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(заголовок)
                .font(.system(size: 15, weight: .heavy))
                .kerning(-0.2)
                .foregroundStyle(КраскаПодачи.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.trailing, 10)
            if !подпись.isEmpty {
                Text(подпись)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(КраскаПлиткиСтарта.подпись(к, тёмная: тёмная))
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .padding(.trailing, Self.рамка + 12)
            }
        }
        .padding(.leading, 14)
        .padding(.top, 12)
    }

    private var тёмная: Bool { схема == .dark }
}

/// Значок в круге краски — у плитки без картинки (и пока картинка не пришла) и у карточки переноса: градиент от краски,
/// подмешанной к белому, к краске, притушенной почти чёрным (как сплошная плитка главной), значок белый.
private struct КружокСтарта: View {
    let значок: String
    let краска: UIColor

    init(значок: String, краска: UIColor) {
        self.значок = значок
        self.краска = краска
    }

    var body: some View {
        Image(systemName: значок)
            .symbolVariant(.fill)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 42, height: 42)
            .background(LinearGradient(colors: [Color(uiColor: Theme.смесь(краска, UIColor.white, 0.86)),
                                                Color(uiColor: Theme.смесь(краска, Theme.hex(0x0B1F17), 0.8))],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle())
            .accessibilityHidden(true)
    }
}

/// Краски плиток старта от краски раздела — по образцу светлой плитки главной (ПлиткаРаздела.остановки и цветСчёта).
/// Поверхность — карточка кабинета (КраскаПодачи.карточка): #fff и #1c1c26 — в тёмной плитка светлее фона страницы.
private enum КраскаПлиткиСтарта {
    static func поверхность(тёмная: Bool) -> UIColor {
        тёмная ? Theme.hex(0x1C1C26) : UIColor.white
    }

    /// linear-gradient(150deg, …): сверху 22 % краски (в тёмной 26 %), с 70 % (в тёмной 62 %) и до низа — 7 % (14 %).
    static func остановки(_ к: UIColor, тёмная: Bool) -> [Gradient.Stop] {
        let п = поверхность(тёмная: тёмная)
        let конец = Color(uiColor: Theme.смесь(к, п, тёмная ? 0.14 : 0.07))
        return [
            Gradient.Stop(color: Color(uiColor: Theme.смесь(к, п, тёмная ? 0.26 : 0.22)), location: 0),
            Gradient.Stop(color: конец, location: тёмная ? 0.62 : 0.7),
            Gradient.Stop(color: конец, location: 1)
        ]
    }

    /// Подпись и «›»: 55 % краски с чернилами, в тёмной — с белым; на подложке своей краски контраст не ниже 4,5.
    static func подпись(_ к: UIColor, тёмная: Bool) -> Color {
        Color(uiColor: Theme.смесь(к, тёмная ? UIColor.white : Theme.hex(0x13211B), 0.55))
    }

    /// Кромка 1 pt: краска 16 %, в тёмной 30 % — светлый низ плитки не сливается с фоном страницы.
    static func кромка(_ к: UIColor, тёмная: Bool) -> Color {
        Color(uiColor: к).opacity(тёмная ? 0.3 : 0.16)
    }
}

/// «Уже размещено на другой площадке?» (.li-entry) в схеме плиток: зелёный круг со ссылкой, заголовок, подпись и «›» на
/// подложке зелёного, пунктирная кромка — как у сайта.
private struct КарточкаПереносаПодачи: View {
    let заголовок: String
    let подпись: String
    let действие: () -> Void
    @Environment(\.colorScheme) private var схема

    init(заголовок: String, подпись: String, действие: @escaping () -> Void) {
        self.заголовок = заголовок
        self.подпись = подпись
        self.действие = действие
    }

    /// Зелёный слайда «Продавайте на Kliko» главной (БаннерГлавной.слайды, «sell»).
    static let краска: UInt32 = 0x0F7A44

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        let к = Theme.hex(Self.краска)
        let тёмная = схема == .dark
        return Button(action: действие) {
            HStack(spacing: 12) {
                КружокСтарта(значок: "link", краска: к)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(КраскаПодачи.текст)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(подпись)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(КраскаПлиткиСтарта.подпись(к, тёмная: тёмная))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(КраскаПлиткиСтарта.подпись(к, тёмная: тёмная))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(stops: КраскаПлиткиСтарта.остановки(к, тёмная: тёмная),
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: форма)
            .overlay {
                форма.strokeBorder(Color(uiColor: к).opacity(тёмная ? 0.5 : 0.36),
                                   style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            }
            .contentShape(форма)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
    }
}

/**
 Лесенка появления на старте: плитка проявляется и подъезжает на 10 pt снизу с масштаба 0,96, с задержкой 0,02 с на номер
 — восемь плиток и карточка под ними (номер 8) встают целиком за 0,34 с. Только прозрачность, сдвиг и масштаб: без
 размытия и замеров. «Уменьшение движения» — сразу на месте, без лесенки.
 */
private struct ПоявлениеЛесенкой: ViewModifier {
    let номер: Int
    @Environment(\.accessibilityReduceMotion) private var безДвижения
    @State private var видна = false

    /// Явный init: закрытое состояние не должно попадать в поэлементный.
    init(номер: Int) {
        self.номер = номер
    }

    func body(content: Content) -> some View {
        let наМесте = видна || безДвижения
        return content
            .opacity(наМесте ? 1 : 0)
            .offset(y: наМесте ? 0 : 10)
            .scaleEffect(наМесте ? 1 : 0.96)
            .onAppear {
                guard !видна else { return }
                guard !безДвижения, !ДвижениеСайта.тихо else {
                    видна = true
                    return
                }
                withAnimation(.easeOut(duration: 0.18).delay(Double(min(номер, 8)) * 0.02)) { видна = true }
            }
    }
}

// MARK: - Гость (#guest-add-card)

/// Тизер «Новое объявление» для гостя: зона фото и «Заполнить вручную» — любое нажатие ведёт ко входу.
struct ГостьПодачи: View {
    let войти: () -> Void

    init(войти: @escaping () -> Void) {
        self.войти = войти
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    /// Карточка по центру экрана: на высоком телефоне без пустоты снизу, на маленьком — прокрутка.
    var body: some View {
        GeometryReader { окно in
            ScrollView {
                карточка
                    .padding(14)
                    .frame(minHeight: окно.size.height)
            }
        }
    }

    private var карточка: some View {
            КарточкаПодачи {
                VStack(alignment: .leading, spacing: 0) {
                    Text(т("guest_t"))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(КраскаПодачи.текст)
                        .accessibilityAddTraits(.isHeader)
                    Text(т("guest_s"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                    Button(action: войти) {
                        VStack(spacing: 8) {
                            Image(systemName: "camera")
                                .font(.system(size: 32, weight: .regular))
                                .foregroundStyle(Theme.текстВторой)
                                .accessibilityHidden(true)
                            Text(т("guest_tap"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(КраскаПодачи.текст)
                                .multilineTextAlignment(.center)
                            Text(String(format: т("form_photo_hint"), 5))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.текстВторой)
                        }
                        .padding(.vertical, 28)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                                .strokeBorder(КраскаПодачи.линия, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 16)
                    Button(action: войти) {
                        Label(т("form_manual"), systemImage: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(КраскаПодачи.текст)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                    .strokeBorder(КраскаПодачи.линия, lineWidth: 1.5)
                            }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                }
            }
    }
}

// MARK: - Окно «Kliko AI распознаёт товар» (#airec-modal)

struct ОкноРаспознавания: View {
    let шаг: Int
    let отмена: () -> Void

    init(шаг: Int, отмена: @escaping () -> Void) {
        self.шаг = шаг
        self.отмена = отмена
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    private static let тёмныйЗелёный = Color(uiColor: Theme.hex(0x1D7D4A))
    private static let глубокийЗелёный = Color(uiColor: Theme.hex(0x0F5132))

    var body: some View {
        ZStack {
            Color(red: 8 / 255, green: 20 / 255, blue: 14 / 255).opacity(0.72).ignoresSafeArea()
            VStack(spacing: 0) {
                верх
                низ
            }
            .frame(maxWidth: 350)
            .background(КраскаПодачи.карточка)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .shadow(color: Color.black.opacity(0.4), radius: 40, y: 30)
            .padding(20)
        }
    }

    /// .airec-top: градиент, «шар» с искрами, заголовок и подзаголовок.
    private var верх: some View {
        VStack(spacing: 0) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 70, height: 70)
                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .padding(.bottom, 14)
                .accessibilityHidden(true)
            Text(т(шаг >= 4 ? "airec_done_t" : "airec_t_light"))
                .font(.system(size: 19, weight: .heavy))
                .kerning(-0.3)
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
            Text(т(шаг >= 4 ? "airec_done_l" : "airec_s_light"))
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Theme.цвет(0x1D7D4A, 0x34C997), Theme.цвет(0x0F5132, 0x22A05B)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .accessibilityElement(children: .combine)
    }

    /// .airec-body: полоса хода, четыре шага, «Заполнить вручную».
    private var низ: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { г in
                ZStack(alignment: .leading) {
                    Capsule().fill(КраскаПодачи.хорошоФон)
                    Capsule()
                        .fill(LinearGradient(colors: [Self.тёмныйЗелёный, Self.глубокийЗелёный], startPoint: .leading,
                                             endPoint: .trailing))
                        .frame(width: г.size.width * CGFloat(min(max(шаг, 0), 4)) / 4)
                }
            }
            .frame(height: 8)
            .animation(ДвижениеСайта.шаг, value: шаг)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                ForEach(1...4, id: \.self) { номер in
                    строка(номер)
                }
            }
            .padding(.top, 20)
            Button(action: отмена) {
                Text(т("form_manual"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                            .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
        }
        .padding(24)
    }

    private func строка(_ номер: Int) -> some View {
        let готов = номер < шаг || шаг >= 4
        let идёт = номер == шаг && шаг < 4
        return HStack(spacing: 12) {
            ZStack {
                if готов {
                    Circle().fill(Color(uiColor: Theme.hex(0x0F9D58)))
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                } else if идёт {
                    Circle()
                        .fill(Color(uiColor: Theme.hex(0x34C997, 0.12)))
                        .frame(width: 34, height: 34)
                    Circle().fill(КраскаПодачи.хорошоФон)
                    Text(String(номер))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.цвет(0x0F5132, 0x5CD39A))
                } else {
                    Circle().fill(КраскаПодачи.поле)
                    Text(String(номер))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            .frame(width: 26, height: 26)
            .accessibilityHidden(true)
            Text(т("airec_l" + String(номер)))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(готов || идёт ? КраскаПодачи.текст : Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if идёт {
                SiteSpinner(размер: 16, толщина: 2)
            }
        }
    }
}

// MARK: - Окно итога подачи (_modOver, §2.5.2)

struct ОкноИтогаПодачи: View {
    /// освободить — «Мои объявления» (опубликованные): снять или удалить старое; исправить — правка отклонённого
    /// с причиной над формой (сайт 13–14.10.2026); расширить — окно покупки App Store этой услуги (лимит слотов).
    enum Действие { case готово, верификация, освободить, исправить, расширить(ВидУслугиApple) }

    let итог: ИтогПодачи
    let заголовок: String
    /// У отклонённого известен номер — «Исправить».
    let исправить: Bool
    let действие: (Действие) -> Void
    /// Товары App Store: «Расширить лимит» — только когда товар слотов загружен.
    @ObservedObject private var покупки = ПокупкиApple.shared

    init(итог: ИтогПодачи, заголовок: String, исправить: Bool = false, действие: @escaping (Действие) -> Void) {
        self.итог = итог
        self.заголовок = заголовок
        self.исправить = исправить
        self.действие = действие
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            /* Длинная причина от сервера на iPhone SE — карточка прокручивается, кнопки не уходят за край. */
            ViewThatFits(in: .vertical) {
                карточка
                ScrollView {
                    карточка
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(20)
        }
    }

    private var отказ: Bool {
        switch итог {
        case .отклонено, .запрещено: return true
        default: return false
        }
    }

    private var карточка: some View {
        VStack(spacing: 0) {
            Image(systemName: значок)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(цвет)
                .padding(.bottom, 12)
                .accessibilityHidden(true)
            Text(заглавие)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(КраскаПодачи.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(текст)
                .font(.system(size: 14))
                .lineSpacing(отказ ? 4 : 7)
                .foregroundStyle(отказ ? КраскаПодачи.плохоТекст : КраскаПодачи.текст)
                .multilineTextAlignment(отказ ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: отказ ? .leading : .center)
                .background(отказ ? Color(red: 229 / 255, green: 72 / 255, blue: 77 / 255).opacity(0.08) : КраскаПодачи.поле,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .padding(.top, 12)
            VStack(spacing: 10) {
                кнопки
            }
            .padding(.top, 20)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: 400)
        .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .shadow(color: Color.black.opacity(0.3), radius: 30, y: 20)
    }

    @ViewBuilder
    private var кнопки: some View {
        switch итог {
        case .опубликовано(let id):
            if let ссылка = Config.url("/marketplace.php?item=" + (id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id)),
               !id.isEmpty {
                ShareLink(item: ссылка, subject: Text(заголовок), message: Text(заголовок)) {
                    Label(т("share"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
                .tint(Theme.акцент)
            }
            КнопкаПодачи(т("mod_ok")) { действие(.готово) }
        case .ждётВерификации:
            /* Владелец (обход новичком): одно понятное действие, «Позже» — тихо. */
            КнопкаПодачи(т("verify_egov_1m")) { действие(.верификация) }
            КнопкаПодачиВторая(т("later")) { действие(.готово) }
        case .неактивные(_, let верификация):
            /* Места нет (владелец 16.10.2026: «в окне предлагать расширить сразу»): «Расширить лимит» — главной (App
               Store: слоты, комбо или PRO; после покупки объявление активируется само), верификация (+5) или «Освободить
               место» — второй, затем «Позже». Купить нечего — верификация или «Освободить место» главной, как было. */
            if РасширениеЛимита.есть(РасширениеЛимита.слоты) {
                кнопкаРасширения
                КнопкаПодачиВторая(т(верификация ? "verify_plus5" : "free_place")) {
                    действие(верификация ? .верификация : .освободить)
                }
            } else if верификация {
                КнопкаПодачи(т("verify_egov_1m")) { действие(.верификация) }
            } else {
                КнопкаПодачи(т("free_place")) { действие(.освободить) }
            }
            КнопкаПодачиВторая(т("later")) { действие(.готово) }
        case .лимит:
            if РасширениеЛимита.есть(РасширениеЛимита.слоты) {
                кнопкаРасширения
                КнопкаПодачиВторая(т("free_place")) { действие(.освободить) }
            } else {
                КнопкаПодачи(т("free_place")) { действие(.освободить) }
            }
            КнопкаПодачиВторая(т("later")) { действие(.готово) }
        case .отклонено:
            /* Отказ: «Исправить» — правка этого объявления с причиной над формой (без «Активировать»). */
            if исправить {
                КнопкаПодачи(ПодачаСайтаText.т("fix")) { действие(.исправить) }
                КнопкаПодачиВторая(т("later")) { действие(.готово) }
            } else {
                КнопкаПодачи(т("mod_ok")) { действие(.готово) }
            }
        case .наПроверке, .сохраненоИИ, .запрещено:
            КнопкаПодачи(т("mod_ok")) { действие(.готово) }
        }
    }

    /// «Расширить лимит» — главная зелёная кнопка окна; товар App Store ещё грузится — с колесом.
    private var кнопкаРасширения: some View {
        КнопкаРасширения(цепочка: РасширениеЛимита.слоты, действие: { вид in действие(.расширить(вид)) }) { занято, нажать in
            КнопкаПодачи(т("limit_more"), занято: занято, действие: нажать)
        }
    }

    private var значок: String {
        switch итог {
        case .опубликовано: return "checkmark.circle"
        case .наПроверке, .ждётВерификации: return "clock"
        case .отклонено, .запрещено: return "xmark.circle"
        case .сохраненоИИ: return "doc.text"
        case .неактивные, .лимит: return "square.stack.3d.up"
        }
    }

    private var цвет: Color {
        switch итог {
        case .опубликовано, .наПроверке, .ждётВерификации: return КраскаПодачи.акцентТекст
        case .отклонено, .запрещено: return КраскаПодачи.плохоТекст
        case .сохраненоИИ, .неактивные, .лимит: return Theme.текстВторой
        }
    }

    private var заглавие: String {
        switch итог {
        case .опубликовано: return т("published")
        case .наПроверке: return т("mod_wait_t")
        case .отклонено: return т("mod_rej_t")
        case .сохраненоИИ: return т("mod_saved_t")
        case .ждётВерификации: return т("held_pub_t")
        case .неактивные: return т("held_t")
        case .лимит: return т("limit_t")
        case .запрещено(let з, _): return з
        }
    }

    private var текст: String {
        switch итог {
        case .опубликовано: return т("published_s")
        /* Владелец (обход новичком): одно простое предложение, без «Неактивных» и «слотов». */
        case .наПроверке: return т("mod_wait_1")
        case .отклонено(let причина): return причина
        case .сохраненоИИ(let часы):
            return т("mod_manual_1").replacingOccurrences(of: "{n}", with: часы.isEmpty ? "24" : часы)
        case .ждётВерификации(let ошибка): return ошибка.isEmpty ? т("held_pub_1") : т("held_pub_1") + "\n\n" + ошибка
        case .неактивные(_, let верификация):
            /* С «Расширить лимит» — фраза, что после расширения объявление сразу уйдёт на витрину. */
            if РасширениеЛимита.есть(РасширениеЛимита.слоты) {
                return ЛимитText.т(верификация ? "lu_held_d_verify" : "lu_held_d")
            }
            return т(верификация ? "held_verify_1" : "held_d")
        case .лимит: return т("limit_d")
        case .запрещено(_, let т1): return т1
        }
    }
}

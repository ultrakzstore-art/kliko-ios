import MapKit
import SwiftUI

/// Куда ведёт навигация ленты — карта объявлений (этап 39). Кладётся в стек ленты, как ЧатЦель и ИзбранноеЦель.
enum КартаЦель: Hashable {
    case объявления
}

/// Раздел в полосе над картой — ключ и название с главной сайта (FeedSnapshot), как у полосы разделов ленты.
struct РазделКарты: Identifiable, Hashable {
    let ключ: String
    let название: String

    var id: String { ключ }
}

extension КартаAPI.Город {
    var координата: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: широта, longitude: долгота) }
}

/**
 ЭКРАН КАРТЫ ОБЪЯВЛЕНИЙ — ЭТАП 39 (владелец 25.09.2026: «приложение должно быть почти 100% похоже на сайт, только нативное
 SwiftUI»).

 Образец — карта kliko.kz на телефоне (mkMapOpen в js/marketplace.min.js, .mk-map-* в css/marketplace.min.css и
 css/marketplace-parts.min.css): сверху зелёная полоса .mk-map-top с «×», названием и числом (#mk-map-cnt), под ней полоса
 разделов .mk-map-cats, ниже на мягком фоне .mk-map-body — холст .mk-map-canvas (скругление 18, рамка и тень) и под ним
 список .mk-map-list на 38 % высоты экрана (на широком экране — справа, 392 pt, как у сайта с 900 px). На холсте —
 «Схема | Спутник» справа сверху (.mk-mtype) и круглая «Рядом» справа снизу (.mk-geoloc); пузыри городов
 (.mk-citybubble), ценники (.mk-pin) и кружки ценников (markercluster). Холст — MapKit (SwiftUI Map, iOS 17) вместо
 Leaflet и тайлов OpenStreetMap: своя карта системы, тёмная в тёмной теме.

 Что отличается от сайта и почему:
   · нажатие на ценник сразу открывает нативное объявление (этап 28), а не только подсвечивает строку: на телефоне
     второй шаг «Открыть» — лишний; строка списка тоже открывает объявление;
   · переключателя «Объявления | Продавцы» нет: «Продавцы» сайт собирает на странице из уже загруженной ленты (MK_SHOPS),
     своего запроса у него нет;
   · «Маршрут» (лист такси и 2ГИС сайта) — не здесь, адрес точки (Nominatim) — тоже: у приложения нет такого листа.
 Фильтры — те же, что у ленты под картой (раздел, поиск, город, цена, состояние…); раздел в полосе карты меняет и ленту,
 как mkMapCat сайта. Экран лежит в стеке ленты: «×» и «смахнуть от края» — назад, объявление ложится поверх карты.
 */
struct ЭкранКарты: View {
    @ObservedObject private var лента: FeedModel
    private let разделы: [РазделКарты]
    /// Открыть объявление поверх карты — стек ленты у NativeFeedView.
    private let открыть: (Listing) -> Void

    @StateObject private var модель = МодельКарты()
    @ObservedObject private var выборГорода = ВыборГорода.shared
    /// Зелёная полоса под часами — часы светлые (ВидСайта.карточки, как у фото страницы объявления).
    @ObservedObject private var вид = ВидСайта.shared
    @Environment(\.dismiss) private var закрыть
    @Environment(\.стекСайта) private var стек
    /// Камера холста; стартовый вид — вся страна, как setView([48.02, 66.92], 5) сайта.
    @State private var позиция: MapCameraPosition = .region(ГеометрияКарты.всяСтрана)
    /// «Спутник» вместо «Схемы» — _mkMapType сайта, только на время экрана.
    @State private var спутник = false
    /// Точка «Вы здесь» после «Рядом».
    @State private var моё: МоёМестоНаКарте? = nil
    @State private var ищемМеня = false
    /// Короткое сообщение над холстом («Не удалось определить местоположение»).
    @State private var плашка: String? = nil
    /// Своя метка в ВидСайта.карточки.
    @State private var меткаЭкрана = UUID()

    /// Явный init: экран создаёт NativeFeedView из другого файла.
    init(лента: FeedModel, разделы: [РазделКарты], открыть: @escaping (Listing) -> Void) {
        _лента = ObservedObject(wrappedValue: лента)
        self.разделы = разделы
        self.открыть = открыть
    }

    var body: some View {
        GeometryReader { рамка in
            VStack(spacing: 0) {
                ВерхКарты(счёт: рамка.size.width > 520 ? модель.подписьСчёта : nil, занята: модель.занята,
                          закрыть: { закрыть() })
                if !разделы.isEmpty {
                    ПолосаРазделовКарты(разделы: разделы, выбран: лента.раздел,
                                        выбрать: { ключ in лента.выбратьРаздел(ключ) })
                }
                телоКарты(рамка.size, высотаОкна: рамка.size.height + рамка.safeAreaInsets.top
                          + рамка.safeAreaInsets.bottom)
            }
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .background(СмахнутьНазад().frame(width: 0, height: 0))
        .onAppear {
            модель.начать(условия)
            отметиться()
        }
        .onDisappear { вид.карточки[меткаЭкрана] = nil }
        /* Раздел сменили в полосе карты (он меняет и ленту) — пузыри, ценники и список города заново. */
        .onChange(of: условия) { _, новые in модель.сменитьУсловия(новые) }
    }

    /// Фильтры карты — те же, что у ленты сейчас: раздел, отправленный поиск, место и фильтры на сервере (если включены).
    private var условия: УсловияКарты {
        let выбранный = лента.раздел
        let отбор = Config.фильтрыНаСервере ? лента.фильтры.годные(для: выбранный) : ФильтрыЛенты()
        return УсловияКарты(раздел: выбранный, поиск: лента.действующее.текст, где: выборГорода.гдеЛенты,
                            фильтры: отбор, аренда: лента.аренда)
    }

    // MARK: - Раскладка

    /// .mk-map-body: холст и список столбиком; на широком экране — рядом, список справа.
    @ViewBuilder
    private func телоКарты(_ размер: CGSize, высотаОкна: CGFloat) -> some View {
        if размер.width >= 700 {
            HStack(spacing: 12) {
                холст
                панель
                    .frame(width: 392)
            }
            .padding(12)
        } else {
            VStack(spacing: 12) {
                холст
                панель
                    // 38vh сайта — от всей высоты окна, не от места под шапкой
                    .frame(height: max(180, высотаОкна * 0.38))
            }
            .padding(12)
        }
    }

    // MARK: - Холст

    private var холст: some View {
        GeometryReader { г in
            карта
                .onAppear { модель.размер = г.size }
                .onChange(of: г.size) { _, новый in модель.размер = новый }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topTrailing) {
            ПереключательВидаКарты(спутник: $спутник)
                .padding(10)
        }
        .overlay(alignment: .bottomTrailing) {
            КнопкаРядом(включена: моё != nil, ищем: ищемМеня) { рядом() }
                .padding(10)
        }
        .overlay(alignment: .bottomLeading) {
            состояниеХолста
                .padding(.leading, 10)
                .padding(.bottom, 10)
                .padding(.trailing, 64)
        }
        .overlay(alignment: .top) {
            if let текст = плашка {
                ПлашкаКарты(текст: текст)
                    .padding(.top, 52)
                    .padding(.horizontal, 12)
                    .transition(.opacity)
            }
        }
        .теньКарточкиСайта(радиус: Theme.Радиус.lg)
    }

    /// Сам холст MapKit: пузыри городов издалека, ценники и кружки ближе порога, «Вы здесь». Поворота и наклона нет —
    /// у карты сайта их тоже нет, а компас без них не нужен.
    private var карта: some View {
        Map(position: $позиция, interactionModes: [.pan, .zoom]) {
            ForEach(модель.пузыри) { пузырь in
                Annotation(пузырь.город, coordinate: пузырь.координата, anchor: .center) {
                    ПузырьГорода(город: пузырь) { нажатГород(пузырь) }
                }
                .annotationTitles(.hidden)
            }
            ForEach(модель.знакиНаХолсте) { знак in
                Annotation(подпись(знак), coordinate: знак.координата, anchor: .center) {
                    ЗнакНаХолсте(знак: знак, открыть: { товар in открытьОбъявление(товар) },
                                 приблизить: { приблизить(к: знак) })
                }
                .annotationTitles(.hidden)
            }
            ForEach(моёСписком) { точка in
                Annotation(MapText.т("me"), coordinate: точка.координата, anchor: .center) {
                    ТочкаМеня()
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(спутник ? MapStyle.imagery : MapStyle.standard)
        .mapControls {
            MapScaleView()
        }
        /* Карта остановилась — _mkMapOnMove сайта: режим, кружки и (через паузу) ценники видимой области. */
        .onMapCameraChange(frequency: .onEnd) { контекст in
            модель.камераСменилась(контекст.region)
        }
    }

    private var моёСписком: [МоёМестоНаКарте] {
        guard let точка = моё else { return [] }
        return [точка]
    }

    /// Неудача запроса — плашка с «Повторить»; пока пузыри ещё не пришли — «Загружаем карту…».
    @ViewBuilder
    private var состояниеХолста: some View {
        if модель.неудача {
            ПлашкаНеудачиКарты { модель.повторить() }
        } else if !модель.городаПришли && модель.грузимГорода {
            ПлашкаЗагрузкиКарты()
        }
    }

    // MARK: - Список под картой

    private static let верхСписка = "верх-списка-карты"

    private var панель: some View {
        ScrollViewReader { прокрутка in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Color.clear
                        .frame(height: 0)
                        .id(Self.верхСписка)
                    содержимоеСписка
                }
                .padding(8)
            }
            /* Список сменился (города → город → ценники) — к началу. */
            .onChange(of: модель.видСписка) { _, _ in
                прокрутка.scrollTo(Self.верхСписка, anchor: .top)
            }
        }
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .теньКарточкиСайта(радиус: Theme.Радиус.lg)
    }

    /// Ветки _mkMapListUpdate сайта: города в кадре, объявления выбранного города или ценники в кадре.
    @ViewBuilder
    private var содержимоеСписка: some View {
        switch модель.видСписка {
        case .города:
            списокГородовВКадре
        case .город:
            списокОбъявленийГорода
        case .пины:
            списокЦенников
        }
    }

    @ViewBuilder
    private var списокГородовВКадре: some View {
        let строки = модель.городаВКадре
        if строки.isEmpty {
            if модель.грузимГорода && !модель.городаПришли {
                ПустоКарты(текст: MapText.т("loading"), крутилка: true)
            } else if модель.неудача && !модель.городаПришли {
                ПустоКарты(текст: MapText.т("fail"), крутилка: false)
            } else {
                ПустоКарты(текст: MapText.т("zoom_hint"), крутилка: false)
            }
        } else {
            ForEach(Array(строки.prefix(200))) { строкаГорода in
                КарточкаГородаКарты(город: строкаГорода) { нажатГород(строкаГорода) }
            }
        }
    }

    @ViewBuilder
    private var списокОбъявленийГорода: some View {
        let строки = модель.строкиГорода
        if модель.грузимСписок {
            ПустоКарты(текст: MapText.т("loading"), крутилка: true)
        } else if строки.isEmpty {
            ПустоКарты(текст: MapText.т("none"), крутилка: false)
        } else {
            ForEach(Array(строки.prefix(120))) { строка in
                СтрокаОбъявленияКарты(строка: строка) { открытьОбъявление(строка.товар) }
            }
        }
    }

    @ViewBuilder
    private var списокЦенников: some View {
        let строки = модель.строкиПинов
        if строки.isEmpty {
            if модель.грузимПины {
                ПустоКарты(текст: MapText.т("loading"), крутилка: true)
            } else {
                ПустоКарты(текст: MapText.т("none"), крутилка: false)
            }
        } else {
            ForEach(Array(строки.prefix(120))) { строка in
                СтрокаОбъявленияКарты(строка: строка) { открытьОбъявление(строка.товар) }
            }
        }
    }

    // MARK: - Действия

    /// Пузырь или карточка города — mkCityZoom: карта к городу на зум MK_APPROX_MAXZOOM + 2, его объявления — в список.
    private func нажатГород(_ выбранный: КартаAPI.Город) {
        let цель = ГеометрияКарты.область(центр: выбранный.координата, зум: ГеометрияКарты.порогЗума + 2,
                                          размер: модель.размер)
        модель.выбратьГород(выбранный.город, цель: цель)
        withAnimation(ДвижениеСайта.камера) { позиция = .region(цель) }
    }

    /// Кружок ценников — как у markercluster: на два шага ближе, к его середине.
    private func приблизить(к знак: ЗнакКарты) {
        let сейчас = ГеометрияКарты.зум(модель.область, ширина: модель.размер.width)
        let новыйЗум = min(ГеометрияКарты.наибольшийЗум, max(сейчас, ГеометрияКарты.порогЗума) + 2)
        let цель = ГеометрияКарты.область(центр: знак.координата, зум: новыйЗум, размер: модель.размер)
        withAnimation(ДвижениеСайта.камера) { позиция = .region(цель) }
    }

    /// Объявление поверх карты. Ценник без названия — это только номер: открываем заготовкой, как ссылку (этап 8), и
    /// страница дотянет объявление сама, а не покажет пустое название.
    private func открытьОбъявление(_ товар: Listing) {
        открыть(товар.title.isEmpty ? Listing(номер: товар.id) : товар)
    }

    /// «Рядом» — mkMapHere: второй раз снимает точку; иначе — одна точка и карта на 2 км вокруг неё (toBounds(2e3)).
    private func рядом() {
        if моё != nil {
            моё = nil
            return
        }
        guard !ищемМеня else { return }
        ищемМеня = true
        модель.найтиМеня { найдено in
            ищемМеня = false
            guard let точка = найдено else {
                показатьПлашку(MapText.т("geo_denied"))
                return
            }
            моё = МоёМестоНаКарте(широта: точка.latitude, долгота: точка.longitude)
            let цель = MKCoordinateRegion(center: точка, latitudinalMeters: 2000, longitudinalMeters: 2000)
            withAnimation(ДвижениеСайта.камера) { позиция = .region(цель) }
        }
    }

    private func показатьПлашку(_ текст: String) {
        withAnimation(ДвижениеСайта.появление) { плашка = текст }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if плашка == текст {
                withAnimation(ДвижениеСайта.уход) { плашка = nil }
            }
        }
    }

    /// Подпись знака для карты (сама подпись скрыта — annotationTitles(.hidden)).
    private func подпись(_ знак: ЗнакКарты) -> String {
        if знак.пины.count == 1, let пин = знак.пины.first { return ПодписиКарты.ценникКоротко(пин.товар) }
        return ПодписиКарты.коротко(знак.пины.count)
    }

    /**
     Зелёная полоса под часами — часы светлые. Используем ту же отметку, что страница объявления с фото под часами
     (КарточкаНаЭкране, этап 28): NativeTabsView по ней светлит часы и прячет панель сайта — у карты сайта панели тоже нет
     (#mk-map-ov закрывает страницу целиком).
     */
    private func отметиться() {
        let запись = КарточкаНаЭкране(стек: стек, фотоПодЧасами: true)
        if вид.карточки[меткаЭкрана] != запись { вид.карточки[меткаЭкрана] = запись }
    }
}

// MARK: - Подписи

/// Числа и цены так, как их пишет скрипт карты сайта.
enum ПодписиКарты {
    /// Одна цифра после точки, как Math.round(n / делитель) / 10 у сайта: 12 → «1.2», 150 → «15».
    static func десятые(_ n: Int, делитель: Double) -> String {
        let десятых = Int((Double(n) / делитель).rounded())
        let целых = десятых / 10
        let остаток = десятых % 10
        return остаток == 0 ? String(целых) : String(целых) + "." + String(остаток)
    }

    /// _mkCountShort: «1.2м», «1.2к», «56».
    static func коротко(_ n: Int) -> String {
        let число = max(0, n)
        if число >= 1_000_000 { return десятые(число, делитель: 100_000) + MapText.т("short_m") }
        if число >= 1_000 { return десятые(число, делитель: 100) + MapText.т("short_k") }
        return String(число)
    }

    /// Цена целыми тенге, как parseInt(t.price) сайта; нет, ноль или несуразное — nil.
    static func тенге(_ товар: Listing) -> Int? {
        guard let цена = товар.price, цена.isFinite, цена >= 1, цена < 1e15 else { return nil }
        return Int(цена)
    }

    /// _mkPriceShort — надпись ценника: «1.2м», «15к», «900»; без цены — «•».
    static func ценникКоротко(_ товар: Listing) -> String {
        guard let p = тенге(товар) else { return "•" }
        if p >= 1_000_000 { return десятые(p, делитель: 100_000) + MapText.т("short_m") }
        if p >= 1_000 { return String(Int((Double(p) / 1_000).rounded())) + MapText.т("short_k") }
        return String(p)
    }

    /// _mkPrice — цена в строке списка: «1.2 млн ₸», «15 тыс ₸», «9 500 ₸»; без цены — «Договорная».
    static func цена(_ товар: Listing) -> String {
        guard let p = тенге(товар) else { return MapText.т("negotiable") }
        if p >= 1_000_000 {
            return (десятые(p, делитель: 100_000) + "\u{00A0}" + MapText.т("mln") + "\u{00A0}₸").слеваНаправо
        }
        if p >= 10_000 {
            return (String(Int((Double(p) / 1_000).rounded())) + "\u{00A0}" + MapText.т("thous") + "\u{00A0}₸").слеваНаправо
        }
        return (DesignText.число(p) + "\u{00A0}₸").слеваНаправо
    }

    /// Расстояние от центра карты: «350 м», «1.2 км»; у сайта — только до 9999 км.
    static func расстояние(_ км: Double?) -> String? {
        guard let значение = км, значение.isFinite, значение >= 0, значение < 9999 else { return nil }
        if значение < 1 { return String(Int((значение * 1000).rounded())) + "\u{00A0}" + MapText.т("meters") }
        return String(format: "%.1f", значение) + "\u{00A0}" + MapText.т("km")
    }
}

// MARK: - Полосы

/// .mk-map-top: зелёная полоса под часами — «×», «Карта», крутилка запроса и число (#mk-map-cnt).
private struct ВерхКарты: View {
    let счёт: String?
    let занята: Bool
    let закрыть: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: закрыть) {
                // .mk-map-x сайта — знак «×» 21px обычного начертания
                Text("×")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(Color.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MapText.т("close"))
            Text(MapText.т("map"))
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if занята {
                SiteSpinner.мелкийБелый
            }
            if let подпись = счёт {
                Text(подпись)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Theme.зелёный.ignoresSafeArea(edges: .top))
    }
}

/// .mk-map-cats: «Все» и разделы пилюлями; выбранный — зелёный с белым текстом, «Все» — жирнее (.is-all).
private struct ПолосаРазделовКарты: View {
    let разделы: [РазделКарты]
    let выбран: String
    let выбрать: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                чип(ключ: "", название: MapText.т("all"), всё: true)
                ForEach(разделы) { раздел in
                    чип(ключ: раздел.ключ, название: раздел.название, всё: false)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        /* mask-image сайта: у конца полосы мягкое затухание 26px (в RTL — у левого края). */
        .mask {
            HStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 26)
                    .flipsForRightToLeftLayoutDirection(true)
            }
        }
        .background(Theme.поверхность)
        .overlay(alignment: .bottom) {
            Theme.линия
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MapText.т("sections"))
    }

    private func чип(ключ: String, название: String, всё: Bool) -> some View {
        let вкл = выбран == ключ
        return Button { выбрать(ключ) } label: {
            Text(название)
                .font(.system(size: 14, weight: всё ? .heavy : .semibold))
                .foregroundStyle(вкл ? Color.white : Theme.текст)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(вкл ? Theme.зелёный2 : Theme.поверхность2, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(вкл ? Color.clear : Theme.линия, lineWidth: 1)
                }
                // .mk-map-cat.on: 0 6px 14px -8px rgba(15,81,50,.8)
                .shadow(color: вкл ? Color(uiColor: Theme.hex(0x0F5132, 0.5)) : .clear, radius: 5, x: 0, y: 4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(вкл ? .isSelected : [])
    }
}

// MARK: - Знаки на холсте

/// .mk-citybubble: зелёный кружок-пилюля с числом объявлений города, белая кромка и тень.
private struct ПузырьГорода: View {
    let город: КартаAPI.Город
    let нажать: () -> Void

    var body: some View {
        Button(action: нажать) {
            Text(ПодписиКарты.коротко(город.число))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 38)
                .frame(minWidth: 38)
                .background(Theme.зелёный, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Color.white, lineWidth: 2)
                }
                .shadow(color: Color.black.opacity(0.32), radius: 5, x: 0, y: 3)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(город.город + ", " + DesignText.предложений(город.число))
        .accessibilityHint(MapText.т("city_hint"))
    }
}

/// Ценник одного объявления (.mk-pin) или кружок нескольких с числом.
private struct ЗнакНаХолсте: View {
    let знак: ЗнакКарты
    let открыть: (Listing) -> Void
    let приблизить: () -> Void

    var body: some View {
        if знак.пины.count == 1, let пин = знак.пины.first {
            Button { открыть(пин.товар) } label: {
                Text(ПодписиКарты.ценникКоротко(пин.товар))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .strokeBorder(Color.white, lineWidth: 1.5)
                    }
                    .shadow(color: Color.black.opacity(0.35), radius: 3.5, x: 0, y: 2)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(пин.товар.голос)
            .accessibilityHint(MapText.т("open_hint"))
        } else {
            Button(action: приблизить) {
                Text(ПодписиКарты.коротко(знак.пины.count))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .frame(height: 34)
                    .frame(minWidth: 34)
                    .background(Theme.зелёный, in: Capsule())
                    .overlay {
                        Capsule().strokeBorder(Color.white, lineWidth: 2)
                    }
                    .shadow(color: Color.black.opacity(0.32), radius: 5, x: 0, y: 3)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: MapText.т("cluster"), String(знак.пины.count)))
            .accessibilityHint(MapText.т("cluster_hint"))
        }
    }
}

/// «Вы здесь» — circleMarker сайта: синяя точка #378add в белой кромке.
private struct ТочкаМеня: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)
            Circle()
                .fill(Color(uiColor: Theme.hex(0x378ADD)))
                .frame(width: 14, height: 14)
        }
        .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MapText.т("me"))
    }
}

// MARK: - Кнопки и плашки на холсте

/// .mk-mtype: «Схема | Спутник», выбранное — зелёным.
private struct ПереключательВидаКарты: View {
    @Binding var спутник: Bool

    var body: some View {
        HStack(spacing: 0) {
            кнопка(MapText.т("scheme"), вкл: !спутник) { спутник = false }
            Theme.линия
                .frame(width: 1, height: 32)
                .accessibilityHidden(true)
            кнопка(MapText.т("sat"), вкл: спутник) { спутник = true }
        }
        .background(Theme.поверхность)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .shadow(color: Color.black.opacity(0.22), radius: 5, x: 0, y: 2)
        .fixedSize()
    }

    private func кнопка(_ текст: String, вкл: Bool, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Text(текст)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(вкл ? Color.white : Theme.текст)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(вкл ? Theme.зелёный : Theme.поверхность)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(вкл ? .isSelected : [])
    }
}

/// .mk-geoloc: круглая «Рядом» 44 pt; включена — зелёная.
private struct КнопкаРядом: View {
    let включена: Bool
    let ищем: Bool
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            Image(systemName: "location.fill")
                .font(.system(size: 17, weight: .semibold))
                // .mk-geoloc.locating — иконка зелёная, пока ищем
                .foregroundStyle(включена && !ищем ? Color.white : (ищем ? Theme.зелёный : Theme.текстВторой))
                .frame(width: 44, height: 44)
                .background(включена && !ищем ? Theme.зелёный : Theme.поверхность, in: Circle())
                .shadow(color: Color.black.opacity(0.28), radius: 6, x: 0, y: 3)
                .overlay {
                    if включена || ищем {
                        КольцоРядом(длительность: ищем ? 1 : 1.7)
                            .id(ищем)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MapText.т("here"))
        .accessibilityAddTraits(включена ? .isSelected : [])
    }
}

/// .mk-geoloc::after: кольцо на 4 шире кнопки, 2px зелёным, расходится (mkGeoPulse: .92→1.6, .7→0).
private struct КольцоРядом: View {
    let длительность: Double
    @State private var пульс = false
    @Environment(\.accessibilityReduceMotion) private var безДвижения

    var body: some View {
        Circle()
            .strokeBorder(Theme.зелёный, lineWidth: 2)
            .padding(-4)
            .scaleEffect(безДвижения ? 1 : (пульс ? 1.6 : 0.92))
            .opacity(безДвижения ? 0.4 : (пульс ? 0 : 0.7))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear {
                guard !безДвижения else { return }
                withAnimation(.easeOut(duration: длительность).repeatForever(autoreverses: false)) {
                    пульс = true
                }
            }
    }
}

/// Плашка на холсте — в виде .mk-map-addr сайта: поверхность, рамка, тень.
private struct ОбёрткаПлашкиКарты<Содержимое: View>: View {
    let содержимое: Содержимое

    init(@ViewBuilder содержимое: () -> Содержимое) {
        self.содержимое = содержимое()
    }

    var body: some View {
        HStack(spacing: 10) {
            содержимое
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.25), radius: 10, x: 0, y: 6)
    }
}

/// «Карта недоступна — проверьте интернет» и «Повторить».
private struct ПлашкаНеудачиКарты: View {
    let повторить: () -> Void

    var body: some View {
        ОбёрткаПлашкиКарты {
            Text(MapText.т("fail"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: повторить) {
                Text(MapText.т("retry"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
        }
    }
}

/// «Загружаем карту…» с крутилкой — .mk-map-loading, только маленькой плашкой: сама карта MapKit уже на экране.
private struct ПлашкаЗагрузкиКарты: View {
    var body: some View {
        ОбёрткаПлашкиКарты {
            SiteSpinner.мелкий
            Text(MapText.т("loading"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Короткое сообщение — как .mk-toast сайта: тёмная плашка со светлым текстом (в тёмной теме наоборот).
private struct ПлашкаКарты: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(Theme.поверхность)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .background(Theme.текст, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .shadow(color: Color.black.opacity(0.22), radius: 12, x: 0, y: 8)
    }
}

// MARK: - Строки списка

/// .mk-map-empty: подсказка по центру списка, серым.
private struct ПустоКарты: View {
    let текст: String
    let крутилка: Bool

    var body: some View {
        VStack(spacing: 10) {
            if крутилка {
                SiteSpinner()
            }
            Text(текст)
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }
}

/// .mk-mcard.mk-citycard: зелёный квадрат со зданием, город, «N предложений» и стрелка.
private struct КарточкаГородаКарты: View {
    let город: КартаAPI.Город
    let нажать: () -> Void

    var body: some View {
        Button(action: нажать) {
            HStack(spacing: 10) {
                Image(systemName: "building.2")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.white)
                    .frame(width: 54, height: 54)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(город.город)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    Text(DesignText.предложений(город.число))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.зелёный)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .flipsForRightToLeftLayoutDirection(true)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.текстВторой)
            }
            .padding(8)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(город.город + ", " + DesignText.предложений(город.число))
        .accessibilityHint(MapText.т("city_hint"))
        .accessibilityAddTraits(.isButton)
    }
}

/// .mk-mcard: фото 54 pt, «ТОП» и название, цена зелёным, расстояние и город, «↗ Открыть» (.mk-mc-act). У трёх первых
/// ТОПов — золотистая подложка слева (.mk-mcard.top).
private struct СтрокаОбъявленияКарты: View {
    let строка: СтрокаКарты
    let открыть: () -> Void

    var body: some View {
        Button(action: открыть) {
            HStack(alignment: .center, spacing: 10) {
                миниатюра
                VStack(alignment: .leading, spacing: 1) {
                    заголовок
                    Text(ПодписиКарты.цена(строка.товар))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.зелёный)
                        .lineLimit(1)
                    if !подробности.isEmpty {
                        Text(подробности)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(1)
                    }
                    // .mk-mc-acts: margin-top 6 (5 + зазор столбика 1)
                    ПилюляОткрыть()
                        .padding(.top, 5)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .background(фон)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(голос)
        .accessibilityHint(MapText.т("open_hint"))
        .accessibilityAddTraits(.isButton)
    }

    private var миниатюра: some View {
        Theme.поверхность2
            .frame(width: 54, height: 54)
            .overlay {
                КартинкаЛенты(строка.товар.обложка, пунктов: 54) {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.текстВторой.opacity(0.6))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
    }

    private var заголовок: some View {
        HStack(spacing: 5) {
            if строка.топ {
                Text(MapText.т("top"))
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(0.2)
                    .foregroundStyle(Color(uiColor: Theme.hex(0x7A4F05)))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(uiColor: Theme.hex(0xF6C453)),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.xxs, style: .continuous))
            }
            Text(строка.товар.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var фон: some View {
        if строка.топ {
            LinearGradient(colors: [Color(uiColor: Theme.hex(0xF5B642, 0.12)), Color.clear],
                           startPoint: .leading, endPoint: .trailing)
        } else {
            Color.clear
        }
    }

    /// «1.2 км · Алматы» — расстояние от центра карты и город.
    private var подробности: String {
        let части: [String?] = [ПодписиКарты.расстояние(строка.км), строка.товар.city.isEmpty ? nil : строка.товар.city]
        return части.compactMap { $0 }.joined(separator: " · ")
    }

    /// VoiceOver: название, цена, город, «в топе» — и расстояние.
    private var голос: String {
        let части: [String?] = [строка.товар.голос, ПодписиКарты.расстояние(строка.км)]
        return части.compactMap { $0 }.joined(separator: ", ")
    }
}

/// .mk-mc-act «Открыть»: рамка, зелёная стрелка. Нажимается вся строка — пилюля только показывает, куда она ведёт.
private struct ПилюляОткрыть: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.акцент)
            Text(MapText.т("open"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

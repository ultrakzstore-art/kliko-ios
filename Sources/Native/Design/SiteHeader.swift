import SwiftUI
import WebKit

/**
 ШАПКА ГЛАВНОЙ КАК НА САЙТЕ — ЭТАП 25 (владелец 25.09.2026: «приложение должно быть почти 100% похоже на сайт»).

 Образец — .mk-topbar главной kliko.kz на телефоне (<style id="mk-gtop-css">): зелёный градиент под часами со
 скруглённым низом, в первом ряду знак Kliko.kz и город («По всей стране»), справа — кнопка темы; во втором — белое
 поле «Что искали?» с камерой. Вместо системной панели навигации и .searchable ленты — эта шапка, а всё, что жило в
 системной панели, осталось: колокольчик сохранённого поиска (этап 12), поиск с историей (этап 6), фокус по
 быстрому действию «Поиск» (этап 10). Разметка, отступы и краски — из CSS сайта (Theme, этап 24).

 🔴 ЧТО ВЕДЁТ НА САЙТ. Город на сайте выбирается выпадающим списком внутри страницы (mkToggleCityDD), поиск по фото
 — тоже скриптом страницы (mkPhotoSearch): своих адресов у них нет. Поэтому и город, и камера открывают ленту сайта
 без главной (/kz/<язык>/?all=1 — MH.all в js/marketplace-home.js), где в той же шапке есть и город, и камера.
 Кнопки «Карта» нет: карта сайта — тоже слой страницы (mkMapOpen) без адреса, а угаданный адрес хуже никакого.
 Этап 39: при Config.картаОбъявлений «Карта» есть — круглой кнопкой справа от поля, как #mk-map-btn сайта на телефоне, и
 открывает свою карту (ЭкранКарты, Native/Map) теми же запросами, что mkMapOpen, а не адрес сайта.

 Этап 32: при Config.выборГорода город больше не ведёт на сайт — он открывает свой лист «Где ищете?» (ЛистГорода,
 Native/Geo), а подпись — выбор приложения (ВыборГорода.подпись), а не #mk-city-lbl страницы.
 */
struct ШапкаСайта<Справа: View, УПоиска: View, Снизу: View>: View {
    @Binding var текст: String
    let фокус: FocusState<Bool>.Binding
    /// Подпись города — как на странице сайта (#mk-city-lbl), по умолчанию «По всей стране».
    let город: String
    let открытьГород: () -> Void
    /// Подсказка VoiceOver у города: «Откроется на сайте» (этап 25) или выбор в приложении (этап 32).
    let подсказкаГорода: String
    /// Камера в поле; nil — без неё.
    let поискПоФото: (() -> Void)?
    let найти: () -> Void
    /// Этап 49: под шапкой полоса разделов (не главная) — у шапки тогда меньше отступ снизу и скругление 22, как у
    /// .mk-vrail сайта; на главной — скругление 20 (html.mk-gtop.mk-home .mk-topbar).
    let сПолосой: Bool
    let справа: Справа
    let уПоиска: УПоиска
    let снизу: Снизу
    /// Этап 49: подсказка в поле — одна из тех, что сервер сайта ставит в #mk-q при каждой отрисовке страницы; здесь —
    /// при каждом появлении шапки.
    @State private var подсказка: String = DesignText.подсказкиПоиска.randomElement() ?? DesignText.т("search")

    init(текст: Binding<String>, фокус: FocusState<Bool>.Binding, город: String,
         открытьГород: @escaping () -> Void, подсказкаГорода: String = DesignText.т("on_site"),
         поискПоФото: (() -> Void)?, найти: @escaping () -> Void, сПолосой: Bool = false,
         @ViewBuilder справа: () -> Справа, @ViewBuilder уПоиска: () -> УПоиска, @ViewBuilder снизу: () -> Снизу) {
        _текст = текст
        self.фокус = фокус
        self.город = город
        self.открытьГород = открытьГород
        self.подсказкаГорода = подсказкаГорода
        self.поискПоФото = поискПоФото
        self.найти = найти
        self.сПолосой = сПолосой
        self.справа = справа()
        self.уПоиска = уПоиска()
        self.снизу = снизу()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    логотип
                        .fixedSize()
                    кнопкаГорода
                    Spacer(minLength: 0)
                    справа
                        .fixedSize()
                }
                HStack(spacing: 8) {
                    полеПоиска
                    уПоиска
                        .fixedSize()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, сПолосой ? 8 : 14)
            снизу
        }
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ФонШапкиСайта(радиус: сПолосой ? Theme.Радиус.шапка : Theme.Радиус.xl)
                .ignoresSafeArea(edges: .top)
        }
    }

    /// Знак и надпись: значок 25 pt с белой кромкой 18 %, «Kliko» белым, «.kz» мятным (#a3dcc0), как .mk-logo.
    private var логотип: some View {
        HStack(spacing: 5) {
            KlikoLogoIcon(size: 25)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                }
            KlikoWordmark(height: 17, надпись: .white, домен: Theme.шапкаМята)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kliko.kz")
        .accessibilityAddTraits(.isHeader)
    }

    /// Город: мятная плашка 26 pt со значком, подпись 14 pt жирным, стрелка вниз — .mk-city-btn.
    private var кнопкаГорода: some View {
        Button(action: открытьГород) {
            HStack(spacing: 8) {
                Image(systemName: "mappin")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.шапкаМятаТекст)
                    .frame(width: 26, height: 26)
                    .background(Theme.шапкаМята, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(город)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Theme.шапкаМята)
            }
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesignText.т("city") + ": " + город)
        .accessibilityHint(подсказкаГорода)
        .accessibilityAddTraits(.isButton)
    }

    /// Белое поле 38 pt (.mk-tbsearch): лупа, текст 16 pt (меньше — и iOS увеличит страницу, на сайте то же правило),
    /// крестик, пока что-то набрано, и камера (.mk-cam-badge: 33 × 33 без подложки, серая #6b7f76).
    private var полеПоиска: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            TextField(подсказка, text: $текст,
                      prompt: Text(подсказка).foregroundColor(Theme.текстВторой))
                .font(.system(size: 16))
                .foregroundStyle(Theme.текст)
                .tint(Theme.акцент)
                .focused(фокус)
                .submitLabel(.search)
                .onSubmit(найти)
            if !текст.isEmpty {
                Button { текст = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DesignText.т("clear"))
            }
            if let поискПоФото {
                Button(action: поискПоФото) {
                    Image(systemName: "camera")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(uiColor: Theme.hex(0x6B7F76)))
                        .frame(width: 33, height: 33)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DesignText.т("photo"))
                .accessibilityHint(DesignText.т("on_site"))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 38)
        .frame(maxWidth: .infinity)
        .background(Theme.полеПоиска, in: Capsule())
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 6)
        .contentShape(Capsule())
    }
}

/**
 Пилюля шапки «тема │ язык» — #theme-sw и #mk-lang-wrap сайта (этап 49): левая половина 38 × 38 — луна или солнце,
 разделитель белый 16 %, правая — код языка 13 pt жирным; подложка белый 12 % (в тёмной 8 %) с кромкой белый 18 %.
 Нажатие на язык — список #mk-lang-dd: RU «Рус», KZ «Қаз», EN «Eng», AR «عربي», у текущего галочка (ЯзыкПриложения).
 Выбор темы выключен — одна половина с языком.
 */
struct ПилюляТемыИЯзыка: View {
    /// Смена темы; nil — половины темы нет.
    let тема: (() -> Void)?
    /// Луна в светлой теме, солнце в тёмной — как uipThemeIcon сайта.
    let значокТемы: String
    @ObservedObject private var язык = ЯзыкПриложения.shared

    init(тема: (() -> Void)?, значокТемы: String) {
        self.тема = тема
        self.значокТемы = значокТемы
    }

    var body: some View {
        HStack(spacing: 0) {
            if let тема {
                Button(action: тема) {
                    Image(systemName: значокТемы)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DesignText.т("theme"))
                Rectangle()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 1, height: 22)
                    .accessibilityHidden(true)
            }
            Menu {
                ForEach(ЯзыкПриложения.варианты) { вариант in
                    Button {
                        язык.выбрать(вариант)
                    } label: {
                        if вариант.код == язык.код {
                            Label(вариант.метка + "  " + вариант.имя, systemImage: "checkmark")
                        } else {
                            Text(вариант.метка + "  " + вариант.имя)
                        }
                    }
                }
            } label: {
                Text(язык.текущий.метка)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color.white)
                    .padding(.leading, тема == nil ? 11 : 8)
                    .padding(.trailing, 11)
                    .frame(height: 38)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel(DesignText.т("lang"))
            .accessibilityValue(язык.текущий.имя)
        }
        .background(Theme.шапкаКнопка, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Theme.шапкаКнопкаРамка, lineWidth: 1)
        }
    }
}

/**
 Полоса разделов под шапкой — .mk-vrail сайта на телефоне вне главной (этап 49): зелёное продолжение шапки, пилюли 38 pt
 со значками — «Все», Авто, Недвижимость, Услуги, Электроника, Товары, Животные, Работа; выбранная — белая, текст и значок
 цветом раздела («Все» — #0f4d31). «Работа» — страница вакансий сайта (своего экрана у приложения нет).
 */
struct ПолосаРазделовШапки: View {
    /// Раздел ленты: «» — «Все».
    let выбран: String
    let название: (РазделГлавной) -> String
    let выбрать: (String) -> Void
    let вакансии: () -> Void
    @Environment(\.colorScheme) private var схема

    init(выбран: String, название: @escaping (РазделГлавной) -> String, выбрать: @escaping (String) -> Void,
         вакансии: @escaping () -> Void) {
        self.выбран = выбран
        self.название = название
        self.выбрать = выбрать
        self.вакансии = вакансии
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                чип(ключ: "", подпись: DesignText.т("v_all"), значок: "square.grid.2x2", краска: 0x0F4D31)
                ForEach(РазделГлавной.полоса) { раздел in
                    чип(ключ: раздел.ключ, подпись: название(раздел), значок: раздел.значок, краска: раздел.краска)
                }
            }
            .padding(.horizontal, 16)
        }
        .mask {
            LinearGradient(stops: [Gradient.Stop(color: Color.clear, location: 0),
                                   Gradient.Stop(color: Color.black, location: 0.04),
                                   Gradient.Stop(color: Color.black, location: 0.9),
                                   Gradient.Stop(color: Color.clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private func чип(ключ: String, подпись: String, значок: String, краска: UInt32) -> some View {
        let выбранный = ключ == выбран
        return Button {
            if ключ == "jobs" {
                вакансии()
            } else {
                выбрать(ключ)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.system(size: 14, weight: .semibold))
                Text(подпись)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(выбранный ? Color(uiColor: Theme.hex(краска)) : Color.white)
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(выбранный ? Color.white : (схема == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.12)),
                        in: Capsule())
            .overlay {
                Capsule().strokeBorder(выбранный ? Color.white : Theme.шапкаКнопкаРамка, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        .accessibilityAddTraits(выбранный ? .isSelected : [])
        .accessibilityHint(ключ == "jobs" ? DesignText.т("on_site") : "")
    }
}

/// Круглая кнопка на шапке (тема, колокольчик, «Карта» сайта): 38 pt, белый 12 %, кромка белый 18 % — .mk-map-badge.
struct КругШапкиСайта: View {
    let значок: String

    var body: some View {
        Image(systemName: значок)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 38, height: 38)
            .background(Theme.шапкаКнопка, in: Circle())
            .overlay {
                Circle().strokeBorder(Theme.шапкаКнопкаРамка, lineWidth: 1)
            }
            .contentShape(Circle())
    }
}

/// Фон шапки: градиент сверху вниз, блик слева сверху и скруглённый низ 22 pt с тенью — html.mk-gtop .mk-topbar.
struct ФонШапкиСайта: View {
    /// Этап 49: на главной — 20 (--r-xl), с полосой разделов под шапкой — 22, как у сайта.
    let радиус: CGFloat

    init(радиус: CGFloat = Theme.Радиус.шапка) {
        self.радиус = радиус
    }

    private var форма: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: радиус,
                               bottomTrailingRadius: радиус, topTrailingRadius: 0, style: .continuous)
    }

    var body: some View {
        форма
            .fill(LinearGradient(stops: [Gradient.Stop(color: Theme.шапкаВерх, location: 0),
                                         Gradient.Stop(color: Theme.шапкаСередина, location: 0.55),
                                         Gradient.Stop(color: Theme.шапкаНиз, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                форма.fill(RadialGradient(colors: [Theme.шапкаБлик, Color.clear], center: .topLeading,
                                          startRadius: 0, endRadius: 300))
            }
            .shadow(color: Color(red: 4 / 255, green: 34 / 255, blue: 20 / 255).opacity(0.3), radius: 12, x: 0, y: 6)
            .accessibilityHidden(true)
    }
}

/**
 Что сейчас на экране у нативного слоя — для строки состояния и нижней панели сайта (этапы 25, 27).

 Строку состояния решает SceneDelegate (KlikoHostingController), а зелёная шапка видна не всегда: только на корне ленты
 (не поверх неё карточка), на выбранной вкладке ленты и не в две колонки iPad (там шапка — в левой колонке, а часы и
 батарея — над обеими). Тогда часы светлые на зелёном, иначе — как раньше, системные.
 */
@MainActor
final class ВидСайта: ObservableObject {
    static let shared = ВидСайта()

    /// Корень ленты на экране в стеке (ничего не открыто поверх, не две колонки iPad).
    @Published var кореньЛенты = false
    /// Выбрана вкладка ленты; без нижних вкладок лента одна — всегда.
    @Published var вкладкаЛенты = true
    /// Лента на главной — ни поиска, ни раздела: первая кнопка панели — «Категории», иначе «Главная» (этап 27).
    @Published var главная = true
    /// Подпись города с загруженной страницы сайта; nil — ещё не знаем, тогда «По всей стране».
    @Published var город: String? = nil
    /// Страницы объявления как на сайте на экране (этапы 28–29), по своей метке: в каком стеке и под часами ли фото.
    /// По ним NativeTabsView прячет панель сайта и решает, светлые ли часы.
    @Published var карточки: [UUID: КарточкаНаЭкране] = [:]
    /// Экраны поверх корня вкладки, которых нет в её NavigationPath (сравнение избранного), — по своей метке и стеку.
    /// Владелец 25.09.2026, проверка на телефоне, сборка 33: над ними панель сайта тоже прячется.
    @Published var поверх: [UUID: СтекСайта] = [:]
    /// Сверху выбранной вкладки — страница объявления с фото под часами: часы светлые (ставит NativeTabsView).
    @Published var фотоПодЧасами = false

    private init() {}
}

extension SiteSession {
    /// Подпись города в шапке загруженной страницы (#mk-city-lbl): город, радиус или «По всей стране». Город живёт в
    /// веб-сессии, и спросить его у страницы — единственный способ показать ровно то, что покажет сайт. Страница без
    /// шапки (или ещё не загружена) — nil, и шапка оставляет прежнюю подпись.
    @MainActor
    static func город() async -> String? {
        guard let web = WebBridge.shared.webView, WebBridge.shared.isLoaded else { return nil }
        let js = "(function(){var e=document.getElementById('mk-city-lbl');return e?String(e.textContent||''):''})()"
        guard let строка = try? await web.evaluateJavaScript(js) as? String else { return nil }
        let подпись = строка.trimmingCharacters(in: .whitespacesAndNewlines)
        return подпись.isEmpty ? nil : подпись
    }
}

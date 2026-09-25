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

 Этап 32: при Config.выборГорода город больше не ведёт на сайт — он открывает свой лист «Где ищете?» (ЛистГорода,
 Native/Geo), а подпись — выбор приложения (ВыборГорода.подпись), а не #mk-city-lbl страницы.
 */
struct ШапкаСайта<Справа: View, УПоиска: View>: View {
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
    let справа: Справа
    let уПоиска: УПоиска

    init(текст: Binding<String>, фокус: FocusState<Bool>.Binding, город: String,
         открытьГород: @escaping () -> Void, подсказкаГорода: String = DesignText.т("on_site"),
         поискПоФото: (() -> Void)?, найти: @escaping () -> Void,
         @ViewBuilder справа: () -> Справа, @ViewBuilder уПоиска: () -> УПоиска) {
        _текст = текст
        self.фокус = фокус
        self.город = город
        self.открытьГород = открытьГород
        self.подсказкаГорода = подсказкаГорода
        self.поискПоФото = поискПоФото
        self.найти = найти
        self.справа = справа()
        self.уПоиска = уПоиска()
    }

    var body: some View {
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
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            ФонШапкиСайта()
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

    /// Белое поле высотой 38–40 pt: лупа, текст 16 pt (меньше — и iOS увеличит страницу, на сайте то же правило),
    /// крестик, пока что-то набрано, и камера в светлом кружке.
    private var полеПоиска: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            TextField(DesignText.т("search"), text: $текст,
                      prompt: Text(DesignText.т("search")).foregroundColor(Theme.текстВторой))
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 30, height: 30)
                        .background(Theme.полеПоискаКнопка, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DesignText.т("photo"))
                .accessibilityHint(DesignText.т("on_site"))
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(Theme.полеПоиска, in: Capsule())
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 6)
        .contentShape(Capsule())
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
    private var форма: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: Theme.Радиус.шапка,
                               bottomTrailingRadius: Theme.Радиус.шапка, topTrailingRadius: 0, style: .continuous)
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

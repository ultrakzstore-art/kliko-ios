import SwiftUI
import UIKit

/**
 СТРАНИЦА ОБЪЯВЛЕНИЯ КАК НА САЙТЕ — ЭТАП 28 (владелец 25.09.2026: «почти 100% похоже на сайт, только нативное SwiftUI —
 такой же красивый, как сайт»).

 Образец — объявление kliko.kz на телефоне (mkOpenModal в js/marketplace.min.js, стили .mk-modal в css/marketplace.min.css):
 фото от края до края под часами с полосками листания, над ним тёмные квадратные кнопки — сердце и «Поделиться» слева,
 «×» справа; оранжевая метка «Б/У» («С пробегом» у авто); ниже название 22 pt с тонкой зелёной чертой, крупная цена
 («от» у услуг), плашка режима работы, «Продавец утверждает» с галочками, крошки раздела со значком, совет «… — на что
 смотреть», описание с характеристиками, карточка продавца и похожие.

 Системной панели нет — как у сайта, кнопки лежат над фото; «смахнуть от края — назад» возвращает СмахнутьНазад.
 Состояние (догрузка, копия без сети, похожие) держит ListingDetailView: эта страница только рисует то, что ей дали,
 и зовёт его действия. Прежний вид (Config.дизайнКакНаСайте = false) и заготовка по ссылке (этап 8) — прежние.
 */
struct СтраницаОбъявленияСайта: View {
    let товар: Listing
    let догружаем: Bool
    let неДогрузилась: Bool
    /// Этап 13: на экране копия с телефона — когда она легла.
    let сохранённаяКопия: Date?
    let похожие: Похожие.Состояние
    @Binding var страница: Int
    let открытьФото: (Int) -> Void
    let повторить: () -> Void
    /// «Поделиться» картинкой (этап 19); nil — ссылкой через ShareLink, как при выключенном рубильнике.
    let поделитьсяКартинкой: (() -> Void)?
    /// Открыть страницу сайта — запасной путь «Согласовать с продавцом» из «Расположения»; nil — кнопки нет.
    let открыть: ((URL) -> Void)?

    @Environment(\.dismiss) private var закрыть
    /// Страница положена в стек (есть куда вернуться). Корень правой колонки iPad (этап 14) — «×» не нужен.
    @Environment(\.isPresented) private var вСтеке
    /// В стеке какой вкладки панели сайта лежит страница — по нему панель прячется (этап 29), а часы светлеют.
    @Environment(\.стекСайта) private var стек
    @ObservedObject private var вид = ВидСайта.shared
    /// Своя метка у каждой страницы: две страницы одного стека (похожее поверх) не путаются.
    @State private var метка = UUID()
    @State private var названия: [String: String] = [:]
    /// Продавец — магазин (MK_SHOPS страницы сайта): вне часов работы плашка у услуг красная, «закрыто».
    @State private var магазин = false
    @State private var листДоверия = false
    @State private var скрытыеСоветы: Set<String> = СоветыОбъявления.скрытые()
    /// Фото ушло из-под часов — под ними поверхность, и часы снова по теме.
    @State private var прокручено = false

    /// Явный init: страницу создаёт ListingDetailView из другого файла.
    init(товар: Listing, догружаем: Bool, неДогрузилась: Bool, сохранённаяКопия: Date?, похожие: Похожие.Состояние,
         страница: Binding<Int>, открытьФото: @escaping (Int) -> Void, повторить: @escaping () -> Void,
         поделитьсяКартинкой: (() -> Void)?, открыть: ((URL) -> Void)? = nil) {
        self.товар = товар
        self.догружаем = догружаем
        self.неДогрузилась = неДогрузилась
        self.сохранённаяКопия = сохранённаяКопия
        self.похожие = похожие
        _страница = страница
        self.открытьФото = открытьФото
        self.повторить = повторить
        self.поделитьсяКартинкой = поделитьсяКартинкой
        self.открыть = открыть
    }

    var body: some View {
        GeometryReader { рамка in
            let верх = рамка.safeAreaInsets.top
            ZStack(alignment: .top) {
                ScrollView {
                    содержимое(ширина: рамка.size.width, верх: верх)
                }
                .coordinateSpace(NamedCoordinateSpace.named(ПрокруткаСтраницыОбъявления.имя))
                if прокручено {
                    Theme.поверхность
                        .frame(height: верх)
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
                кнопки
                    .padding(.top, верх + 20)
                    .padding(.horizontal, 12)
            }
            .ignoresSafeArea(edges: .top)
            .animation(ДвижениеСайта.выбор, value: прокручено)
        }
        .background(Theme.поверхность.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .background(СмахнутьНазад().frame(width: 0, height: 0))
        .sheet(isPresented: $листДоверия) {
            ЛистДоверия(пункты: товар.пунктыДоверия, ключСовета: товар.ключСовета)
        }
        .task(id: товар.категория) { await загрузитьНазвания() }
        .task(id: товар.продавецID) { await узнатьМагазин() }
        .onAppear { отметиться() }
        .onDisappear { вид.карточки[метка] = nil }
        .onChange(of: прокручено) { _, _ in отметиться() }
    }

    // MARK: - Содержимое

    private func содержимое(ширина: CGFloat, верх: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ГалереяСайта(адреса: товар.фотоАдреса, страница: $страница, верх: верх, ширина: ширина,
                         метка: товар.меткаСостояния, аренда: товар.forRent, открыть: открытьФото)
                .background {
                    /* Нижний край галереи на экране: ушёл выше часов — фото больше не под ними. */
                    GeometryReader { г in
                        Color.clear
                            .onChange(of: г.frame(in: CoordinateSpace.global).maxY < верх + 8, initial: true) { _, стало in
                                if стало != прокручено { прокручено = стало }
                            }
                            /* Где фото в прокрутке — по нему страницу смахивают вниз только от самого верха
                               (ЗакрытьСмахиваниемВниз в SiteListingPull.swift). */
                            .preference(key: ВерхСтраницыОбъявления.self,
                                        value: г.frame(in: NamedCoordinateSpace.named(ПрокруткаСтраницыОбъявления.имя)).minY)
                    }
                }
            ВерхСтраницы(товар: товар, магазин: магазин, названия: названия, листДоверия: $листДоверия)
                .padding(.horizontal, 20)
                .padding(.top, 18)
            НизСтраницы(товар: товар, догружаем: догружаем, неДогрузилась: неДогрузилась,
                        сохранённаяКопия: сохранённаяКопия, скрытыеСоветы: $скрытыеСоветы, повторить: повторить,
                        открыть: открыть)
                .padding(.horizontal, 20)
                .padding(.top, 18)
            if Config.похожие {
                ПолосаПохожих(состояние: похожие,
                              заголовок: ListingPageText.т(товар.услуга ? "similar_svc" : "similar"))
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Кнопки над фото

    /// Сердце и «Поделиться» слева, «×» справа — .mk-mhead сайта.
    private var кнопки: some View {
        HStack(spacing: 4) {
            if Config.избранное {
                КнопкаИзбранного(товар: товар, место: .фото)
            }
            кнопкаПоделиться
            Spacer(minLength: 8)
            if вСтеке {
                КнопкаНадФото(значок: "xmark", подпись: ListingPageText.т("close")) { закрыть() }
            }
        }
    }

    @ViewBuilder
    private var кнопкаПоделиться: some View {
        if let картинкой = поделитьсяКартинкой {
            КнопкаНадФото(значок: "square.and.arrow.up", подпись: FeedText.т("share"), действие: картинкой)
                .accessibilityHint(ShareCardText.т("hint"))
        } else if товар.адрес != nil {
            Button { ЛистПоделитьсяСайта.показать(товар) } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .фонКнопкиНадФото()
            }
            .accessibilityLabel(FeedText.т("share"))
        }
    }

    // MARK: - Сведения со страницы сайта

    private func загрузитьНазвания() async {
        guard let раздел = товар.категория else { return }
        var нужные = [раздел]
        if let родитель = РазделыСайта.родитель(раздел) { нужные.append(родитель) }
        let ответ = await SiteSession.названияРазделов(нужные)
        /* Страница не назвала раздел — имя из справочника сайта на языке приложения, а не «Категория». */
        let итог = await ИменаРазделовСайта.запасные(нужные).merging(ответ) { _, соСтраницы in соСтраницы }
        if !итог.isEmpty { названия = итог }
    }

    private func узнатьМагазин() async {
        guard товар.услуга, let продавец = товар.продавецID else { return }
        магазин = await SiteSession.магазины().contains(продавец)
    }

    /// Сказать панели и часам, что страница на экране и лежит ли фото под часами.
    private func отметиться() {
        let запись = КарточкаНаЭкране(стек: стек, фотоПодЧасами: !прокручено)
        if вид.карточки[метка] != запись { вид.карточки[метка] = запись }
    }
}

// MARK: - Верх: название, цена, режим, «Продавец утверждает», крошки

private struct ВерхСтраницы: View {
    let товар: Listing
    let магазин: Bool
    let названия: [String: String]
    @Binding var листДоверия: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ЗаголовокСайта(текст: товар.title)
            if товар.ценаВидна {
                ЦенаСайта(товар: товар)
            }
            if let часы = товар.текстЧасов {
                БлокЧасов(часы: часы, подпись: товар.услуга ? ListingPageText.т("hours_work") : nil,
                          состояние: состояниеЧасов)
            }
            let пункты = товар.пунктыДоверия
            if !пункты.isEmpty {
                БлокДоверия(пункты: пункты) { листДоверия = true }
            }
            if let раздел = товар.категория {
                КрошкиСайта(раздел: раздел, названия: названия) { выбранный in
                    /* Раздел — лентой на слое вкладок; слоя нет — ничего, страница сайта не открывается. */
                    WebBridge.shared.открытьЭкран(.найти(ИскомоеЛенты(текст: "", раздел: выбранный)), запасной: nil)
                }
            }
        }
    }

    /// mkHoursState: круглосуточно или открыто — зелёная; закрыто у магазина услуг — красная; иначе — оранжевая.
    private var состояниеЧасов: БлокЧасов.Состояние {
        if товар.часыРежим == "247" || товар.открытоСейчас() { return .открыто }
        return товар.услуга && магазин ? .закрыто : .нетНаМесте
    }
}

// MARK: - Низ: пометки, совет, описание, продавец

private struct НизСтраницы: View {
    let товар: Listing
    let догружаем: Bool
    let неДогрузилась: Bool
    let сохранённаяКопия: Date?
    @Binding var скрытыеСоветы: Set<String>
    let повторить: () -> Void
    let открыть: ((URL) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            /* Этап 13: без связи — сохранённая копия с телефона; сказать, от когда она. */
            if let когда = сохранённаяКопия {
                ЗаметкаКопииСайта(когда: когда, догружаем: догружаем, повторить: повторить)
            }
            if неДогрузилась {
                Label(FeedText.т("detail_partial"), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
            if let ключ = товар.ключСовета, !скрытыеСоветы.contains(ключ) {
                БлокСовета(ключ: ключ) {
                    СоветыОбъявления.скрыть(ключ)
                    withAnimation(ДвижениеСайта.вставкаСписка) { _ = скрытыеСоветы.insert(ключ) }
                }
            }
            /* Авто и жильё (SiteListingKinds.swift): проверка, схема, свои характеристики, оплата и место — как у сайта. */
            if let видСтраницы = товар.видСтраницы {
                БлокиВидаДоОписания(товар: товар, вид: видСтраницы)
                let пункты = товар.характеристикиВида
                if !пункты.isEmpty || товар.описание != nil {
                    БлокОписанияВида(характеристики: пункты, описание: товар.описаниеДляЭкрана,
                                     добавлено: товар.когдаДобавлено, просмотры: товар.просмотры)
                }
                if let оплата = товар.поляВида.оплата, (товар.price ?? 0) > 0, оплата.рассрочка || оплата.кредит {
                    СпособыОплатыСайта(товар: товар, оплата: оплата)
                }
            } else if !товар.характеристики.isEmpty || товар.описание != nil {
                БлокОписанияСайта(характеристики: товар.характеристики, описание: товар.описаниеДляЭкрана,
                                  добавлено: товар.когдаДобавлено, просмотры: товар.просмотры)
            }
            if товар.продавец != nil {
                /* Этап 37: карточка открывает отзывы о продавце, рядом с подпиской — «⋮» с «Заблокировать» и
                   «Пожаловаться», как .mk-msc и .mk-sfollow сайта (нет seller_id — ни того, ни другого). */
                if Config.продавецОтзывы || Config.жалобы, let продавецID = товар.продавецID {
                    БлокПродавца(товар: товар, продавецID: продавецID)
                } else if Config.подпискиССайтом, let продавецID = товар.продавецID {
                    /* Этап 36: под карточкой — «Подписаться на продавца», как .mk-sfollow сайта. */
                    ПродавецСПодпиской(товар: товар, продавецID: продавецID)
                } else {
                    КарточкаПродавцаСайта(товар: товар)
                }
            }
            /* «Расположение» — у всех разделов, как rt = mkLocationBlock(r) в колонке .mk-mcol-e сайта; нет ни места,
               ни точки — нет и блока (SiteListingLocation.swift). */
            if РасположениеСайта.есть(товар) {
                РасположениеСайта(товар: товар, открыть: открыть)
            }
            if догружаем {
                SiteSpinner()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
    }
}

/// «Сохранённая копия · когда» (этап 13) — плашкой поверхности 2, как .mk-escrow-note сайта.
private struct ЗаметкаКопииСайта: View {
    let когда: Date
    let догружаем: Bool
    let повторить: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: OfflineText.т("copy"), OfflineText.когда(когда)))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(OfflineText.т("copy_sub"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            if !догружаем {
                Button(FeedText.т("retry"), action: повторить)
                    .font(.system(size: 13, weight: .bold))
                    .tint(Theme.акцент)
            }
        }
        .padding(12)
        .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }
}

// MARK: - Какие советы человек закрыл

/// Закрытый совет «… — на что смотреть» больше не показывается — на этом телефоне, как localStorage ulx_btips_<вид>
/// у сайта. Настройка устройства, а не аккаунта: при выходе не стирается.
enum СоветыОбъявления {
    private static let ключ = "kliko.listing.tipsHidden"

    static func скрытые() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: ключ) ?? [])
    }

    static func скрыть(_ вид: String) {
        var все = скрытые()
        все.insert(вид)
        UserDefaults.standard.set(Array(все).sorted(), forKey: ключ)
    }
}

// MARK: - Какая страница на экране (этапы 28–29)

/// В стеке какой вкладки панели сайта живёт экран. Ставит NativeTabsView; без вкладок — «другое».
enum СтекСайта: Hashable {
    case лента, избранное, другое
}

private struct КлючСтекаСайта: EnvironmentKey {
    static let defaultValue: СтекСайта = .другое
}

extension EnvironmentValues {
    var стекСайта: СтекСайта {
        get { self[КлючСтекаСайта.self] }
        set { self[КлючСтекаСайта.self] = newValue }
    }
}

/// Страница объявления на экране: в каком стеке и лежит ли её фото под часами.
struct КарточкаНаЭкране: Equatable {
    let стек: СтекСайта
    let фотоПодЧасами: Bool
}

extension SiteSession {
    /// Магазины (MK_SHOPS страницы сайта) — продавцы с витриной: у их услуг вне часов работы плашка «закрыто».
    /// Страница не загружена или списка нет — пусто.
    @MainActor
    static func магазины() async -> Set<String> {
        guard let web = WebBridge.shared.webView, WebBridge.shared.isLoaded else { return [] }
        let js = "(function(){try{return JSON.stringify((typeof MK_SHOPS!=='undefined'&&MK_SHOPS&&MK_SHOPS.forEach)"
            + "?Array.from(MK_SHOPS):[]);}catch(e){return '[]';}})()"
        guard let строка = try? await web.evaluateJavaScript(js) as? String,
              let данные = строка.data(using: .utf8),
              let список = try? JSONSerialization.jsonObject(with: данные) as? [String] else { return [] }
        return Set(список)
    }
}

import SwiftUI
import UIKit

/*
 ЧАСТИ СТРАНИЦЫ ОБЪЯВЛЕНИЯ КАК НА САЙТЕ (этап 28, владелец 25.09.2026: «почти 100% похоже на сайт, только нативное
 SwiftUI»). Каждая часть — свой вид: так тело страницы остаётся коротким, и компилятор не выбирает типы часами.
 Размеры и краски — из css/marketplace.min.css (.mk-mgal, .mk-gprog, .mk-gcond, .mk-mtitle, .mk-mprice, .mk-hours,
 .mk-trustbox, .mk-mcats, .mk-btips, .mk-msub, .mk-mspec, .mk-mdesc, .mk-mmeta, .mk-msc) в разметке телефона.
 */

// MARK: - Перенос строк (flex-wrap сайта)

/// Ряд, который переносится на следующую строку, когда не помещается, — как display:flex; flex-wrap:wrap у крошек и
/// характеристик сайта.
struct ПереносСтрок: Layout {
    var промежуток: CGFloat = 8
    var междуСтрок: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ширина = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var строка: CGFloat = 0
        var самая: CGFloat = 0
        for вид in subviews {
            let р = вид.sizeThatFits(ProposedViewSize(width: ширина, height: nil))
            if x > 0 && x + р.width > ширина {
                y += строка + междуСтрок
                x = 0
                строка = 0
            }
            x += р.width + промежуток
            строка = max(строка, р.height)
            самая = max(самая, x - промежуток)
        }
        return CGSize(width: proposal.width ?? самая, height: y + строка)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var строка: CGFloat = 0
        for вид in subviews {
            let р = вид.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + р.width > bounds.maxX {
                y += строка + междуСтрок
                x = bounds.minX
                строка = 0
            }
            вид.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                      proposal: ProposedViewSize(width: min(р.width, bounds.width), height: р.height))
            x += р.width + промежуток
            строка = max(строка, р.height)
        }
    }
}

// MARK: - «Смахни — назад» без системной панели

/**
 Страница объявления прячет системную панель (кнопки — над фото, как у сайта), а UIKit вместе с панелью выключает жест
 «смахнуть от края — назад». Посредник на время показа страницы становится делегатом этого жеста у своего стека и
 разрешает его, когда есть куда возвращаться; уходя, возвращает прежнего делегата — остальные экраны живут как жили.
 Глобальной подмены UINavigationController нет: она задела бы чат, кабинет и iPad.
 */
struct СмахнутьНазад: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Посредник { Посредник() }
    func updateUIViewController(_ uiViewController: Посредник, context: Context) {}

    final class Посредник: UIViewController, UIGestureRecognizerDelegate {
        private weak var стек: UINavigationController?
        private weak var прежний: UIGestureRecognizerDelegate?
        private var поставлен = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !поставлен, let найден = navigationController, let жест = найден.interactivePopGestureRecognizer else {
                return
            }
            стек = найден
            прежний = жест.delegate
            жест.delegate = self
            жест.isEnabled = true
            поставлен = true
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            вернуть()
        }

        private func вернуть() {
            guard поставлен else { return }
            поставлен = false
            if let жест = стек?.interactivePopGestureRecognizer, жест.delegate === self {
                жест.delegate = прежний
            }
        }

        /// Корень стека смахивать некуда: жест на нём у UIKit замораживает экран.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (стек?.viewControllers.count ?? 0) > 1
        }
    }
}

// MARK: - Кнопки над фото (.mk-mhead)

extension View {
    /// .mk-mhead .mk-mbtn: квадрат 36 pt со скруглением 10, rgba(14,20,17,.45) и размытие под ним, значок белый.
    func фонКнопкиНадФото() -> some View {
        self
            .frame(width: 36, height: 36)
            .background(Theme.кнопкаНадФото, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .environment(\.colorScheme, .dark)
            .padding(4)
            .contentShape(Rectangle())
    }
}

struct КнопкаНадФото: View {
    let значок: String
    let подпись: String
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            Image(systemName: значок)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .фонКнопкиНадФото()
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.92))
        .accessibilityLabel(подпись)
    }
}

// MARK: - Галерея (.mk-mgal на телефоне)

/**
 Фото от края до края и под строкой состояния. Сайт показывает снимок целиком (object-fit: contain) на тёмной подложке
 #0d1512 — здесь та же подложка, а поля по бокам и под часами заполняет тот же снимок, размытый (как фон, который
 _mkGalBg сайта берёт из фото). Высота — по пропорции первого снимка, но не выше 4:5 и не ниже 16:10, как рамка
 галереи сайта (--gal-h). Сверху — затемнение 104 pt (.mk-mgal::before), полоски листания (.mk-gprog) и метка
 состояния (.mk-gbadges) в 66 pt от верха фото.
 */
struct ГалереяСайта: View {
    let адреса: [URL]
    @Binding var страница: Int
    /// Высота строки состояния: фото уходит под неё, а полоски и метка — ниже.
    let верх: CGFloat
    let ширина: CGFloat
    let метка: Listing.МеткаСостояния?
    let аренда: Bool
    let открыть: (Int) -> Void
    @State private var пропорция: CGFloat = 1

    /// Явный init: страницу создаёт другой файл, и поэлементный init не должен зависеть от закрытых свойств.
    init(адреса: [URL], страница: Binding<Int>, верх: CGFloat, ширина: CGFloat, метка: Listing.МеткаСостояния?,
         аренда: Bool, открыть: @escaping (Int) -> Void) {
        self.адреса = адреса
        _страница = страница
        self.верх = верх
        self.ширина = ширина
        self.метка = метка
        self.аренда = аренда
        self.открыть = открыть
    }

    var body: some View {
        let высотаФото = ширина / max(0.8, min(1.6, пропорция))
        let высота = верх + высотаФото
        return ZStack(alignment: .topLeading) {
            слайды(высота: высота)
            затемнение
                .frame(width: ширина, height: верх + 104)
                .allowsHitTesting(false)
            if адреса.count > 1 {
                полоски
                    .padding(.top, верх + 8)
                    .allowsHitTesting(false)
            }
            метки
                .padding(.top, верх + 66)
                .padding(.leading, 16)
                .allowsHitTesting(false)
        }
        .frame(width: ширина, height: высота, alignment: .top)
        .clipped()
    }

    @ViewBuilder
    private func слайды(высота: CGFloat) -> some View {
        if адреса.isEmpty {
            Theme.подложкаФото
                .overlay {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(Color.white.opacity(0.35))
                        .padding(.top, верх)
                }
                .frame(width: ширина, height: высота)
                .accessibilityHidden(true)
        } else {
            TabView(selection: $страница) {
                ForEach(Array(адреса.enumerated()), id: \.offset) { номер, адрес in
                    СлайдФото(адрес: адрес, верх: верх, ширина: ширина, высота: высота) { размер in
                        guard номер == 0, размер.height > 0 else { return }
                        пропорция = размер.width / размер.height
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { открыть(номер) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(format: ListingPageText.т("photo"), номер + 1, адреса.count))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { открыть(номер) }
                    .tag(номер)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(width: ширина, height: высота)
        }
    }

    private var затемнение: some View {
        LinearGradient(stops: [
            .init(color: Color(red: 6 / 255, green: 10 / 255, blue: 8 / 255).opacity(0.46), location: 0),
            .init(color: Color(red: 6 / 255, green: 10 / 255, blue: 8 / 255).opacity(0.14), location: 0.58),
            .init(color: Color.clear, location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }

    /// .mk-gprog: полоски 2,5 pt через 4 pt, белые 40 %; пройденные и текущая — белые.
    private var полоски: some View {
        HStack(spacing: 4) {
            ForEach(0..<адреса.count, id: \.self) { номер in
                Capsule()
                    .fill(номер <= страница ? Color.white : Color.white.opacity(0.4))
                    .frame(height: 2.5)
                    .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: ширина)
        .animation(.easeOut(duration: 0.2), value: страница)
    }

    /// .mk-gcond: «Б/У» оранжевым (#b8620c), «Новое» — зелёным; «Аренда» — синим градиентом.
    private var метки: some View {
        HStack(spacing: 6) {
            if let метка {
                Text(метка.текст)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.44)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(метка.новое ? Theme.зелёный2 : Theme.меткаБУ,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
            if аренда {
                Text(ListingPageText.т("rent"))
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.44)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(LinearGradient(colors: [Color(uiColor: Theme.hex(0x2563EB)), Color(uiColor: Theme.hex(0x1D4ED8))],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                    .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
            }
        }
    }
}

/// Один снимок: целиком по ширине под строкой состояния, вокруг — он же, размытый. Картинка своя, а не AsyncImage:
/// нужен её размер (пропорция галереи), а URLSession.shared кладёт её в общий кэш — оттуда её берёт «Поделиться» (этап 19).
private struct СлайдФото: View {
    let адрес: URL
    let верх: CGFloat
    let ширина: CGFloat
    let высота: CGFloat
    let размер: (CGSize) -> Void
    @State private var картинка: UIImage? = nil
    @State private var неудача = false

    init(адрес: URL, верх: CGFloat, ширина: CGFloat, высота: CGFloat, размер: @escaping (CGSize) -> Void) {
        self.адрес = адрес
        self.верх = верх
        self.ширина = ширина
        self.высота = высота
        self.размер = размер
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.подложкаФото
            if let картинка {
                Image(uiImage: картинка)
                    .resizable()
                    .scaledToFill()
                    .frame(width: ширина, height: высота)
                    .blur(radius: 26, opaque: true)
                    .overlay(Color.black.opacity(0.3))
                    .clipped()
                Image(uiImage: картинка)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ширина, height: max(1, высота - верх))
                    .padding(.top, верх)
            } else if неудача {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(Color.white.opacity(0.35))
                    .frame(maxHeight: .infinity)
            } else {
                ProgressView()
                    .tint(Color.white)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: ширина, height: высота)
        .clipped()
        .task(id: адрес) { await загрузить() }
    }

    private func загрузить() async {
        guard картинка == nil else { return }
        var запрос = URLRequest(url: адрес)
        запрос.cachePolicy = .returnCacheDataElseLoad
        do {
            let (данные, _) = try await URLSession.shared.data(for: запрос)
            guard let снимок = UIImage(data: данные) else {
                неудача = true
                return
            }
            let готовый = await снимок.byPreparingForDisplay() ?? снимок
            guard !Task.isCancelled else { return }
            картинка = готовый
            неудача = false
            размер(готовый.size)
        } catch {
            if !Task.isCancelled { неудача = true }
        }
    }
}

// MARK: - Заголовок и цена (.mk-mtitle, .mk-mprice)

/// Название 22 pt и под ним тонкая черта: зелёный 45 % → 16 % → цвет линии (.mk-mtitle::after).
struct ЗаголовокСайта: View {
    let текст: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(текст)
                .font(.system(size: 22, weight: .heavy))
                .tracking(-0.22)
                .lineSpacing(3)
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            LinearGradient(stops: [
                .init(color: Theme.зелёный2.opacity(0.45), location: 0),
                .init(color: Theme.зелёный2.opacity(0.16), location: 0.26),
                .init(color: Theme.линия, location: 0.52),
                .init(color: Theme.линия.opacity(0.35), location: 1)
            ], startPoint: .leading, endPoint: .trailing)
            .frame(height: 2)
            .clipShape(Capsule())
            .accessibilityHidden(true)
        }
    }
}

/// Цена 30 pt: «от» у услуг, «/сут» у аренды, красная со скидкой и зачёркнутой старой, «ТОРГ» при торге.
struct ЦенаСайта: View {
    let товар: Listing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if товар.ценаОт {
                Text(ListingPageText.т("price_from"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
            if let день = товар.ценаАренды {
                Text(ListingCard.тенге(день))
                    .font(.system(size: 30, weight: .heavy))
                    .tracking(-0.75)
                    .foregroundStyle(Theme.текст)
                Text(товар.единицаАренды)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
            } else if товар.negotiable && (товар.price ?? 0) <= 0 {
                Text(ListingPageText.т("negotiable"))
                    .font(.system(size: 27, weight: .heavy))
                    .italic()
                    .foregroundStyle(Theme.зелёный2)
            } else {
                обычная
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var обычная: some View {
        let скидка = товар.скидкаПроцентов
        Text(ListingCard.цена(товар))
            .font(.system(size: 30, weight: .heavy))
            .tracking(-0.75)
            .foregroundStyle(скидка == nil ? Theme.текст : Theme.ценаСкидка)
        if let скидка, let старая = товар.oldPrice {
            Text(ListingCard.тенге(старая))
                .font(.system(size: 18, weight: .bold))
                .strikethrough(true, color: Theme.ценаСкидка)
                .foregroundStyle(Theme.текстВторой)
            Text(verbatim: "↓ \(скидка)%")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Theme.скидкаТекст)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Theme.скидкаФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.xxs, style: .continuous))
        }
        if товар.negotiable && (товар.price ?? 0) > 0 {
            Text(ListingPageText.т("torg").uppercased())
                .font(.system(size: 12, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(Theme.зелёный2)
        }
    }
}

// MARK: - Режим работы (.mk-hours)

struct БлокЧасов: View {
    enum Состояние { case открыто, нетНаМесте, закрыто }

    let часы: String
    /// «РЕЖИМ РАБОТЫ» — у услуг; у товаров сайт пишет одно время.
    let подпись: String?
    let состояние: Состояние

    private var краска: Color {
        switch состояние {
        case .открыто: return Theme.зелёный
        case .нетНаМесте: return Theme.оранжевый
        case .закрыто: return Theme.малиновый
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(состояние == .закрыто ? Theme.текстВторой : краска,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .shadow(color: состояние == .закрыто ? Color.clear : краска.opacity(0.45), radius: 6, x: 0, y: 4)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let подпись {
                    Text(подпись.uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(Theme.текстВторой)
                }
                Text(часы)
                    .font(.system(size: 15, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.текст)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(краска.opacity(состояние == .закрыто ? 0.09 : 0.10),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .теньКарточкиСайта(радиус: Theme.Радиус.lg)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Подзаголовок (.mk-msub)

/// «ОПИСАНИЕ», «ПРОДАВЕЦ УТВЕРЖДАЕТ»: значок в мятном квадрате 24 pt и прописные 11 pt.
struct ПодзаголовокСайта: View {
    let значок: String
    let текст: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: значок)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 24, height: 24)
                .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                .accessibilityHidden(true)
            Text(текст.uppercased())
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.5)
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

// MARK: - «Продавец утверждает» (.mk-trustbox)

struct БлокДоверия: View {
    let пункты: [Listing.ПунктДоверия]
    let подробнее: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ПодзаголовокСайта(значок: "checkmark.shield", текст: ListingPageText.т("claims"))
                Spacer(minLength: 8)
                Button(action: подробнее) {
                    HStack(spacing: 2) {
                        Text(ListingPageText.т("what_gives"))
                            .font(.system(size: 12, weight: .bold))
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(Theme.акцент)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(пункты, id: \.self) { пункт in
                        ПунктДоверияСайта(пункт: пункт)
                    }
                }
                .padding(.vertical, 1)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: подробнее)
        }
    }
}

/// .mk-trustbox-i: галочка и подпись; ключевой (гарантия, доставка) — зелёный на зелёной подложке.
struct ПунктДоверияСайта: View {
    let пункт: Listing.ПунктДоверия

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: пункт.значок)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .accessibilityHidden(true)
            Text(пункт.текст)
                .font(.system(size: 14, weight: пункт.ключевой ? .bold : .semibold))
                .foregroundStyle(пункт.ключевой ? Theme.акцент : Theme.текстПункта)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(пункт.ключевой ? Theme.оттенокАкцента : Theme.фонПункта,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.xxs, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.xxs, style: .continuous)
                .strokeBorder(пункт.ключевой ? Theme.оттенокАкцента : Theme.рамкаПункта, lineWidth: 1)
        }
    }
}

/// «Что это даёт»: знаки доверия с пометкой «заявлено» и совет по разделу, «Понятно».
struct ЛистДоверия: View {
    let пункты: [Listing.ПунктДоверия]
    let ключСовета: String?
    @Environment(\.dismiss) private var закрыть

    init(пункты: [Listing.ПунктДоверия], ключСовета: String?) {
        self.пункты = пункты
        self.ключСовета = ключСовета
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(ListingPageText.т("trust_title"))
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                ForEach(пункты, id: \.self) { пункт in
                    HStack(spacing: 10) {
                        ПунктДоверияСайта(пункт: пункт)
                        Spacer(minLength: 8)
                        if !пункт.ключевой {
                            Text(ListingPageText.т("claimed"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.текстВторой)
                        }
                    }
                }
                if let ключ = ключСовета {
                    Text(ListingPageText.т("trust_look"))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .padding(.top, 6)
                    СписокСовета(ключ: ключ)
                }
                Button { закрыть() } label: {
                    Text(ListingPageText.т("ok"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .padding(20)
        }
        .background(Theme.поверхность.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Хлебные крошки (.mk-mcats)

/// Значок корня, родитель зелёным, «›», сам раздел чёрным; под ними — линия. Нажатие — лента этого раздела.
struct КрошкиСайта: View {
    let раздел: String
    let названия: [String: String]
    let выбрать: (String) -> Void

    var body: some View {
        let родитель = РазделыСайта.родитель(раздел)
        let имяРаздела = названия[раздел]
        return VStack(alignment: .leading, spacing: 12) {
            ПереносСтрок(промежуток: 8, междуСтрок: 6) {
                Image(systemName: РазделыСайта.значок(раздел))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(height: 26)
                    .accessibilityHidden(true)
                if let родитель, let имя = названия[родитель] {
                    крошка(имя, куда: родитель, лист: false)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.текстВторой.opacity(0.55))
                        .frame(height: 26)
                        .accessibilityHidden(true)
                }
                if let имяРаздела {
                    крошка(имяРаздела, куда: раздел, лист: true)
                } else if let корень = имяКорня {
                    /* Страница сайта не назвала раздел — хотя бы корень, словами приложения. */
                    крошка(корень.имя, куда: корень.ключ, лист: true)
                }
            }
            Theme.линия
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    /// Корень раздела названием из текстов приложения; неизвестный корень — nil, крошки нет.
    private var имяКорня: (ключ: String, имя: String)? {
        let корень = РазделыСайта.корень(раздел)
        let имя = ListingPageText.т("root_" + корень)
        return имя.hasPrefix("root_") ? nil : (корень, имя)
    }

    private func крошка(_ текст: String, куда: String, лист: Bool) -> some View {
        Button { выбрать(куда) } label: {
            Text(текст)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(лист ? Theme.текст : Theme.акцент)
                .lineLimit(1)
                .frame(height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Совет «… — на что смотреть» (.mk-btips)

struct СписокСовета: View {
    let ключ: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(1...4, id: \.self) { номер in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                        .accessibilityHidden(true)
                    Text(ListingPageText.т("tip_\(ключ)_\(номер)"))
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Плашка совета: зелёная черта слева, лампочка, «×» и «Понятно» — оба прячут совет этого вида насовсем (как
/// localStorage ulx_btips_<вид> у сайта).
struct БлокСовета: View {
    let ключ: String
    let скрыть: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .accessibilityHidden(true)
                Text(ListingPageText.т("tip_" + ключ))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Button(action: скрыть) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой.opacity(0.8))
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ListingPageText.т("close"))
            }
            СписокСовета(ключ: ключ)
            Button(action: скрыть) {
                Text(ListingPageText.т("ok"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.vertical, 14)
        .padding(.leading, 19)
        .padding(.trailing, 16)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .overlay(alignment: .leading) {
            UnevenRoundedRectangle(topLeadingRadius: Theme.Радиус.md, bottomLeadingRadius: Theme.Радиус.md,
                                   bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
                .fill(Theme.зелёный2)
                .frame(width: 3)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Описание и характеристики (.mk-about-h, .mk-mspec, .mk-mdesc, .mk-mmeta)

struct БлокОписанияСайта: View {
    let характеристики: [Listing.Характеристика]
    let описание: String?
    let добавлено: String?
    let просмотры: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ПодзаголовокСайта(значок: "info.circle", текст: ListingPageText.т("desc"))
            if !характеристики.isEmpty {
                ПереносСтрок(промежуток: 8, междуСтрок: 8) {
                    ForEach(характеристики, id: \.self) { х in
                        Text(х.ключ + ": " + х.значение)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.текст)
                            .lineLimit(2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.поверхность2, in: Capsule())
                    }
                }
            }
            if let описание {
                Text(описание)
                    .font(.system(size: 15))
                    .lineSpacing(6)
                    .foregroundStyle(Theme.текст)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if добавлено != nil || (просмотры ?? 0) > 0 {
                HStack(spacing: 16) {
                    if let добавлено {
                        Label(String(format: ListingPageText.т("added"), добавлено), systemImage: "clock")
                    }
                    if let п = просмотры, п > 0 {
                        Label(String(п), systemImage: "eye")
                            .accessibilityLabel(String(format: ListingPageText.т("views"), п))
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .labelStyle(МеткаСайта())
            }
        }
    }
}

/// Значок и текст через 6 pt, значок чуть бледнее — как span svg в .mk-mmeta.
struct МеткаСайта: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .opacity(0.85)
            configuration.title
        }
    }
}

// MARK: - Продавец (.mk-msc)

struct КарточкаПродавцаСайта: View {
    let товар: Listing

    private var буква: String {
        String((товар.продавец ?? "?").trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        HStack(spacing: 14) {
            аватар
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(товар.продавец ?? FeedText.т("seller"))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    if товар.продавецПроверен {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.проверен)
                            Text(ListingPageText.т("verified"))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.текст)
                                .lineLimit(1)
                        }
                        .layoutPriority(-1)
                    }
                }
                рейтинг
                if let строка = статистика {
                    Text(строка)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .теньКарточкиСайта(радиус: Theme.Радиус.lg)
        .accessibilityElement(children: .combine)
    }

    /// .mk-msc-av: квадрат 52 pt со скруглением 14, зелёный градиент и первая буква имени; есть фото — фото.
    private var аватар: some View {
        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
            .fill(LinearGradient(colors: [Theme.зелёный2, Theme.зелёныйЯркий], startPoint: .topLeading,
                                 endPoint: .bottomTrailing))
            .frame(width: 52, height: 52)
            .overlay {
                Text(буква)
                    .font(.system(size: 21, weight: .heavy))
                    .foregroundStyle(Color.white)
            }
            .overlay {
                if let адрес = товар.аватарПродавца.flatMap({ Config.url($0) }) {
                    AsyncImage(url: адрес) { картинка in
                        картинка.resizable().scaledToFill()
                    } placeholder: {
                        Color.clear
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                }
            }
            .accessibilityHidden(true)
    }

    /// Пять звёзд (.mk-stars5), «5.0» и «· 5 отзывов»; оценки нет — «Новый продавец».
    @ViewBuilder
    private var рейтинг: some View {
        if let оценка = товар.рейтингПродавца {
            HStack(spacing: 6) {
                HStack(spacing: 1) {
                    ForEach(1...5, id: \.self) { номер in
                        Image(systemName: "star.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Double(номер) <= оценка + 0.25 ? Theme.звезда : Theme.линия)
                    }
                }
                .accessibilityHidden(true)
                Text(String(format: "%.1f", оценка))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                if let отзывы = товар.отзывыПродавца {
                    Text("· " + ListingPageText.число(отзывы, "reviews"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                }
            }
        } else {
            Text(ListingPageText.т("new_seller"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.текстВторой)
        }
    }

    /// «7 сделок · с 2026 г.».
    private var статистика: String? {
        var части: [String] = []
        if let с = товар.сделкиПродавца { части.append(ListingPageText.число(с, "deals")) }
        if let год = товар.продавецС { части.append(String(format: ListingPageText.т("since"), год)) }
        return части.isEmpty ? nil : части.joined(separator: " · ")
    }
}

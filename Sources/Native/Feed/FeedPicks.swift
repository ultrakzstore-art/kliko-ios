import SwiftUI
import UIKit
import WebKit

/**
 КАРУСЕЛЬ ПОДСКАЗОК НАД ЛЕНТОЙ — #mk-vpicks сайта (home.html, js/marketplace.min.js mkVitPicks/mkVcInit, css
 skin-vitrina.min.css; 26.09.2026).

 Где: во всей ленте и в поиске, не на главной (html.mk-home прячет) и не в разделе (html[data-vx] прячет), между «Вы
 смотрели» и заголовком выдачи. На телефоне — лента слайдов по 82 % ширины с доводкой, под ней точки (.mk-vdots: 6 × 6,
 текущая — 18 в ширину зеленью); сама листается раз в 5 с, если её не трогали 8 с и не включено «Уменьшение движения».

 Слайды:
   · «Рядом с вами» (.mk-vpick--near): мини-карта справа; подпись — «N в радиусе 2 км» среди загруженных, без точки —
     «Включите геолокацию — покажем ближайшие». Нажатие — mkNearToggle (ГеоЛенты): «Рядом со мной» включается или
     выключается; «×» — скрыть навсегда (mk_picks_off);
   · «Гарант-сделка» (.mk-vpick--trust): зелёный градиент, щит, «Как это работает» — окно mkEscrowInfo (ЛистГарантСделки);
     «×» — скрыть;
   · «Ваш поиск» (.mk-vpick--sub): есть сохранённые поиски — первый («ключевое слово» или раздел), «следим за N» и
     «Смотреть подписки»; нет, но в ленте запрос — он и «Сохранить поиск»; иначе «Сохраните поиск — пришлём, когда
     появится». ⚠️ На телефоне сайт этот слайд прячет (@media max-width 900px: .mk-vpick--sub{display:none}); владелец
     попросил его — показываем, выключить — `вашПоискНаТелефоне`.
 Скрыты оба первых — карусели нет ([data-near-off][data-trust-off]{display:none}).
 */
struct КарусельПодсказок: View {
    /// Загруженное — для «N в радиусе 2 км».
    let товары: [Listing]
    /// «Рядом со мной» включено.
    let рядом: Bool
    /// Набранный и отправленный запрос ленты (mkSt.q).
    let запрос: String
    let нажатьРядом: () -> Void
    let нажатьГарант: () -> Void
    let нажатьПоиск: () -> Void

    /// Слайд «Ваш поиск» на телефоне (см. шапку: у сайта он на телефоне скрыт).
    static let вашПоискНаТелефоне = true

    @ObservedObject private var гео = ГеоЛенты.shared
    @ObservedObject private var сохранённые = SavedSearchStore.shared
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @Environment(\.colorScheme) private var схема
    @State private var скрытые: Set<String> = КарусельПодсказок.прочитатьСкрытые()
    @State private var текущий: String?
    @State private var тронули = Date.distantPast
    @State private var листаемСами = false

    init(товары: [Listing], рядом: Bool, запрос: String, нажатьРядом: @escaping () -> Void,
         нажатьГарант: @escaping () -> Void, нажатьПоиск: @escaping () -> Void) {
        self.товары = товары
        self.рядом = рядом
        self.запрос = запрос
        self.нажатьРядом = нажатьРядом
        self.нажатьГарант = нажатьГарант
        self.нажатьПоиск = нажатьПоиск
    }

    private var слайды: [String] {
        var итог: [String] = []
        if !скрытые.contains("near") { итог.append("near") }
        if !скрытые.contains("trust") { итог.append("trust") }
        if Self.вашПоискНаТелефоне { итог.append("sub") }
        return итог
    }

    var body: some View {
        if !(скрытые.contains("near") && скрытые.contains("trust")) {
            VStack(spacing: 2) {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(слайды, id: \.self) { ключ in
                            слайд(ключ)
                                .containerRelativeFrame(.horizontal) { длина, _ in длина * 0.82 }
                                .id(ключ)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 14, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $текущий)
                .fixedSize(horizontal: false, vertical: true)
                if слайды.count >= 2 { точки }
            }
            .onChange(of: текущий) { _, _ in
                if листаемСами { листаемСами = false } else { тронули = Date() }
            }
            .task(id: меньшеДвижения) { await листатьСами() }
        }
    }

    /// Точки .mk-vdots: нажатие — к слайду.
    private var точки: some View {
        HStack(spacing: 6) {
            ForEach(слайды, id: \.self) { ключ in
                let вкл = (текущий ?? слайды.first) == ключ
                Button {
                    тронули = Date()
                    withAnimation(.easeInOut(duration: 0.3)) { текущий = ключ }
                } label: {
                    Capsule()
                        .fill(вкл ? Theme.акцент : Theme.линия)
                        .frame(width: вкл ? 18 : 6, height: 6)
                        .frame(height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: текущий)
        .frame(maxWidth: .infinity)
    }

    /// mkVcInit: раз в 5 с — следующий слайд, если 8 с не трогали; при «Уменьшении движения» не листается.
    private func листатьСами() async {
        guard !меньшеДвижения else { return }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            let список = слайды
            guard список.count >= 2, Date().timeIntervalSince(тронули) >= 8 else { continue }
            let место = список.firstIndex(of: текущий ?? список[0]) ?? 0
            листаемСами = true
            withAnimation(.easeInOut(duration: 0.45)) { текущий = список[(место + 1) % список.count] }
        }
    }

    @ViewBuilder
    private func слайд(_ ключ: String) -> some View {
        switch ключ {
        case "near": слайдРядом
        case "trust": слайдГаранта
        default: слайдПоиска
        }
    }

    // MARK: - «Рядом с вами»

    private var подписьРядом: String {
        if let n = гео.вРадиусеДвух(товары) { return ВитринаТекст.т("near_n", число: n) }
        return ВитринаТекст.т("near_s")
    }

    private var слайдРядом: some View {
        Button { нажатьРядом() } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if гео.ищем {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "location.fill")
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text(ВитринаТекст.т("near_h"))
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.акцент)
                    Spacer(minLength: 0)
                    Text(подписьРядом)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                МиниКартаРядом()
                    .frame(width: 116)
                    .frame(minHeight: 94)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .strokeBorder(рядом ? Theme.акцент : Theme.линия, lineWidth: рядом ? 1.5 : 1)
            }
            .background { тень }
        }
        .buttonStyle(НажатиеСайта())
        .accessibilityAddTraits(рядом ? .isSelected : [])
        .overlay(alignment: .topTrailing) {
            крестик("near", подпись: ВитринаТекст.т("close_near"), тёмный: false)
                .padding(10)
        }
    }

    // MARK: - «Гарант-сделка»

    private var слайдГаранта: some View {
        Button { нажатьГарант() } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(ВитринаТекст.т("trust_h"))
                        .font(.system(size: 15, weight: .bold))
                    Text(ВитринаТекст.т("trust_s"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.78))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text(ВитринаТекст.т("trust_go"))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.18), in: Capsule())
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Color.white)
            .padding(.vertical, 14)
            .padding(.leading, 16)
            .padding(.trailing, 44)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 150, height: 150)
                    .offset(x: 34, y: -46)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .background { тень }
        }
        .buttonStyle(НажатиеСайта())
        .overlay(alignment: .topTrailing) {
            крестик("trust", подпись: ВитринаТекст.т("close_trust"), тёмный: true)
                .padding(6)
        }
    }

    // MARK: - «Ваш поиск»

    private var слайдПоиска: some View {
        let поиски = сохранённые.поиски
        let заголовок: String
        let подпись: String
        let действие: String
        if let первый = поиски.first {
            let слово = первый.искомое.текст
            заголовок = слово.isEmpty ? (первый.названиеРаздела ?? ВитринаТекст.т("sub_h")) : слово
            подпись = ВитринаТекст.т("sub_n", число: поиски.count)
            действие = ВитринаТекст.т("sub_open")
        } else if !запрос.isEmpty {
            заголовок = запрос
            подпись = ""
            действие = ВитринаТекст.т("sub_go")
        } else {
            заголовок = ВитринаТекст.т("sub_s")
            подпись = ""
            действие = ВитринаТекст.т("sub_go")
        }
        return Button { нажатьПоиск() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "bell")
                        .font(.system(size: 13, weight: .bold))
                    Text(ВитринаТекст.т("sub_h"))
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Theme.золото)
                Text(заголовок)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !подпись.isEmpty {
                    Text(подпись)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text(действие)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.золото)
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .background(Theme.цвет(0xFBF3DC, 0x2A2417),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .background { тень }
        }
        .buttonStyle(НажатиеСайта())
    }

    // MARK: - Общее

    /// Тень .mk-vpick на телефоне: 0 12px 26px −20px rgba(15,40,28,.5), в тёмной — 0 14px 28px −18px rgba(0,0,0,.9).
    private var тень: some View {
        RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
            .fill(Theme.поверхность.shadow(.drop(color: схема == .dark ? Color.black.opacity(0.6)
                                                    : Color(red: 15 / 255, green: 40 / 255, blue: 28 / 255).opacity(0.22),
                                                  radius: 6, x: 0, y: 8)))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// «×» слайда (.mk-vpick-x): у «Рядом» — на подложке поверхности, у «Гаранта» — белый на зелёном.
    private func крестик(_ ключ: String, подпись: String, тёмный: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                скрытые.insert(ключ)
                Self.записатьСкрытые(скрытые)
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(тёмный ? Color.white.opacity(0.7) : Theme.текстВторой)
                .frame(width: 28, height: 28)
                .background {
                    if !тёмный {
                        Circle().fill(Theme.поверхность)
                            .shadow(color: Color.black.opacity(0.18), radius: 3, x: 0, y: 2)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(подпись)
    }

    /// mk_picks_off сайта — «near», «trust» через запятую; у приложения — в своих настройках (kliko.feed.picksOff).
    nonisolated static func прочитатьСкрытые() -> Set<String> {
        let строка = UserDefaults.standard.string(forKey: "kliko.feed.picksOff") ?? ""
        return Set(строка.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    nonisolated static func записатьСкрытые(_ набор: Set<String>) {
        UserDefaults.standard.set(набор.sorted().joined(separator: ","), forKey: "kliko.feed.picksOff")
    }
}

/// Мини-карта слайда «Рядом с вами» (.mk-vmap): клетка улиц, две дороги, круг вокруг «я» и пять точек объявлений.
struct МиниКартаРядом: View {
    var body: some View {
        GeometryReader { г in
            let w = г.size.width
            let h = г.size.height
            ZStack(alignment: .topLeading) {
                Theme.поверхность2
                Path { путь in
                    var y: CGFloat = 13
                    while y < h {
                        путь.move(to: CGPoint(x: 0, y: y))
                        путь.addLine(to: CGPoint(x: w, y: y))
                        y += 14
                    }
                    var x: CGFloat = 17
                    while x < w {
                        путь.move(to: CGPoint(x: x, y: 0))
                        путь.addLine(to: CGPoint(x: x, y: h))
                        x += 18
                    }
                }
                .stroke(Theme.линия.opacity(0.55), lineWidth: 1)
                Rectangle().fill(Theme.линия).frame(width: w, height: 3).offset(y: h * 0.58)
                Rectangle().fill(Theme.линия).frame(width: 3, height: h).offset(x: w * 0.47)
                Circle()
                    .fill(Theme.зелёныйЯркий.opacity(0.14))
                    .overlay { Circle().strokeBorder(Theme.зелёныйЯркий.opacity(0.4), lineWidth: 1) }
                    .frame(width: 58, height: 58)
                    .position(x: w * 0.47, y: h * 0.44)
                ForEach(Self.точки.indices, id: \.self) { номер in
                    let т = Self.точки[номер]
                    Circle()
                        .fill(Theme.зелёный)
                        .overlay { Circle().strokeBorder(Theme.поверхность, lineWidth: 2) }
                        .frame(width: 9, height: 9)
                        .position(x: w * т.x, y: h * т.y)
                }
                Circle()
                    .fill(Theme.зелёныйЯркий)
                    .overlay { Circle().strokeBorder(Theme.поверхность, lineWidth: 2) }
                    .frame(width: 11, height: 11)
                    .position(x: w * 0.47, y: h * 0.44)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous).strokeBorder(Theme.линия, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }

    /// Места точек из разметки сайта (left, top).
    private static let точки: [CGPoint] = [CGPoint(x: 0.26, y: 0.22), CGPoint(x: 0.62, y: 0.52),
                                           CGPoint(x: 0.18, y: 0.70), CGPoint(x: 0.78, y: 0.26),
                                           CGPoint(x: 0.90, y: 0.66)]
}

// MARK: - Окно «Как работает Гарант-сделка» (mkEscrowInfo без объявления)

/**
 mkEscrowInfo() сайта, открытое со слайда «Гарант-сделка»: зелёная шапка со щитом, заголовок и подзаголовок, четыре шага с
 номерами на линии и кнопка mkEscrowCTA без объявления: гость — «Зарегистрироваться» (кабинет), вошедший без проверки —
 «Пройти верификацию» (cabinet.php?go=verify), проверенный (_MK_ME_VERIFIED) — «Я понял». Денег окно не трогает.
 */
struct ЛистГарантСделки: View {
    /// Кнопка внизу: nil — «Я понял» (закрыть), иначе страница сайта.
    enum Кнопка: Equatable {
        case понятно
        case регистрация
        case верификация
    }

    let кнопка: Кнопка
    let открыть: (URL) -> Void
    @Environment(\.dismiss) private var закрыть

    init(кнопка: Кнопка, открыть: @escaping (URL) -> Void) {
        self.кнопка = кнопка
        self.открыть = открыть
    }

    private static let шаги: [(значок: String, заголовок: String, текст: String)] = [
        ("lock", "escrow_s1_t", "escrow_s1_d"),
        ("shippingbox", "escrow_s2_t", "escrow_s2_d"),
        ("cube", "escrow_s3_t", "escrow_s3_d"),
        ("checkmark.circle", "escrow_s4_t", "escrow_s4_d")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                шапка
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.шаги.indices, id: \.self) { номер in
                        шаг(номер)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                кнопкаВнизу
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
        }
        .background(Theme.поверхность)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var шапка: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .background(Color.white.opacity(0.16),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                Spacer()
                Button { закрыть() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.16), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ВитринаТекст.т("close"))
            }
            Text(ВитринаТекст.т("escrow_title"))
                .font(.system(.title2, weight: .heavy))
                .accessibilityAddTraits(.isHeader)
            Text(ВитринаТекст.т("escrow_hero"))
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                   endPoint: .bottomTrailing))
    }

    private func шаг(_ номер: Int) -> some View {
        let ш = Self.шаги[номер]
        let последний = номер == Self.шаги.count - 1
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text(String(номер + 1))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .frame(width: 28, height: 28)
                    .background(Theme.акцент, in: Circle())
                if !последний {
                    Rectangle()
                        .fill(Theme.линия)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: ш.значок)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 32, height: 32)
                    .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(ВитринаТекст.т(ш.заголовок))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(ВитринаТекст.т(ш.текст))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, последний ? 4 : 18)
        }
    }

    @ViewBuilder
    private var кнопкаВнизу: some View {
        Button {
            switch кнопка {
            case .понятно:
                закрыть()
            case .регистрация:
                закрыть()
                if let адрес = Config.страницаСайта("cabinet.php") { открыть(адрес) }
            case .верификация:
                закрыть()
                if let адрес = Config.страницаСайта("cabinet.php?go=verify") { открыть(адрес) }
            }
        } label: {
            HStack(spacing: 8) {
                if кнопка == .понятно { Image(systemName: "checkmark") }
                Text(ВитринаТекст.т(кнопка == .понятно ? "escrow_ok"
                                     : (кнопка == .регистрация ? "escrow_register" : "escrow_verify")))
                if кнопка != .понятно { Image(systemName: "arrow.right") }
            }
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(НажатиеСайта())
    }

    /// Какая кнопка у этого человека — mkEscrowCTA: вход и _MK_ME_VERIFIED спрашиваем у загруженной страницы.
    @MainActor
    static func кнопкаСейчас() async -> Кнопка {
        let состояние = await SiteSession.состояние()
        guard состояние.вошёл == true else { return .регистрация }
        guard let web = WebBridge.shared.webView, WebBridge.shared.isLoaded else { return .верификация }
        let js = "(function(){try{return window._MK_ME_VERIFIED===true?'1':'0';}catch(e){return '0';}})()"
        let ответ = (try? await web.evaluateJavaScript(js)) as? String
        return ответ == "1" ? .понятно : .верификация
    }
}

// MARK: - Окно «Доступ к геопозиции запрещён» (ulxPermHint, js/geo.min.js)

/// ulxPermHint("гео"): запрещено Kliko — «Открыть настройки» (klikoSettings → Настройки приложения); выключено на всём
/// устройстве — путь в Настройках; внизу «Понятно».
struct ЛистДоступаГео: View {
    let выключеноНаУстройстве: Bool
    @Environment(\.dismiss) private var закрыть

    init(выключеноНаУстройстве: Bool) {
        self.выключеноНаУстройстве = выключеноНаУстройстве
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(ВитринаТекст.т(выключеноНаУстройстве ? "perm_off_t" : "perm_t"))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.текст)
                .padding(.bottom, 6)
            Text(ВитринаТекст.т(выключеноНаУстройстве ? "perm_off_s" : "perm_s"))
                .font(.system(size: 15))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
            if выключеноНаУстройстве {
                Text(ВитринаТекст.т("perm_path"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .padding(.bottom, 12)
            } else {
                Button {
                    закрыть()
                    if let адрес = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(адрес) }
                } label: {
                    Text(ВитринаТекст.т("perm_settings"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.зелёный2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            Button { закрыть() } label: {
                Text(ВитринаТекст.т("perm_ok"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Мелкое

/// Всплывающая строка внизу (toast сайта): «Показываю ближайшие к вам», «Не удалось определить местоположение».
struct ТостЛенты: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(Color(red: 19 / 255, green: 33 / 255, blue: 27 / 255).opacity(0.94), in: Capsule())
            .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 6)
            .accessibilityAddTraits(.isStaticText)
    }
}

/// Чип «Рядом со мной» с «×» над выдачей (mkRenderActive: ["near", near_me]).
struct ЧипРядомСоМной: View {
    let убрать: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "location.fill")
                .font(.system(size: 11, weight: .bold))
            Text(ВитринаТекст.т("near_me"))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Button(action: убрать) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ВитринаТекст.т("close"))
        }
        .foregroundStyle(Theme.акцент)
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 32)
        .background(Theme.мята, in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.рамкаПункта, lineWidth: 1) }
    }
}

import SwiftUI
import UIKit
import WebKit

/**
 ИСТОРИИ РАЗДЕЛОВ — «Новости и акции» сайта (владелец 26.09.2026: «Истории из плиток главной, как на сайте»).

 Что есть в снимке сайта (26.09.2026):
   · js/marketplace-home.min.js: mkHomeGo(t) — плитка главной переводит в раздел и, если mkStoriesWant(t), сразу открывает
     mkStoriesOpen(t, 0, {from:"tile"}); в ленте раздела над заголовком — ряд кружков _mxStRow(t) из
     window.MK_STORIES[t] = {n: имя, l: [{id, img, t}, …]}: кольцо-градиент, просмотренные (localStorage ulx_st_seen) —
     серым кольцом, нажатие — mkStoriesOpen(t, номер, {from:"row"});
   · css/marketplace-parts.min.css, «part stories»: полноэкранный просмотр .stv — карточка со скруглением 20 на чёрном
     #050807, фото на весь экран с медленным наездом (6,5 с), затемнение сверху и снизу, сверху полоски хода (3 pt, белые
     30 %, пройденные 92 %), кружок раздела его цветом с белым кольцом, имя и подпись, «×»; снизу заголовок, текст в три
     строки, белая кнопка (.stv-cta) и прозрачная «Перейти к …» (.stv-go, главная — если белой нет), флажок «Не показывать
     7 дней» (.stv-hide); пауза — полоска приглушена;
   · словарь: st_news «Новости и акции», st_more «Подробнее», st_go_<раздел> «Перейти к Авто»…, st_hide7, st_prev, st_next.
 Самого скрипта историй (mkStoriesOpen, mkStoriesWant) и MK_STORIES в снимке нет — сервер кладёт их только туда, где
 истории есть. Поэтому истории берём у загруженной страницы сайта (window.MK_STORIES), тем же видом; нет их — нет ни ряда,
 ни открытия с плитки, как у сайта. Поля истории, кроме id, img и t, разбираем терпимо: текст — p, d или text; кнопка — b,
 cta или btn; ссылка — u, url, href или link.

 Поведение просмотра: одна история — 6,5 с (столько идёт наезд фото у сайта); касание левой трети — назад, остального —
 вперёд; держать — пауза; смахнуть вниз — закрыть; вбок — следующая или предыдущая. Кончились — закрыть.
 Открытие с плитки (mkStoriesWant): у раздела есть истории и он не скрыт флажком «Не показывать 7 дней».
 */
struct ИсторияРаздела: Identifiable, Hashable {
    let id: String
    let картинка: URL?
    let заголовок: String
    let текст: String
    /// Подпись белой кнопки; nil — «Подробнее», если есть ссылка.
    let кнопка: String?
    let ссылка: URL?
}

struct ИсторииРаздела: Hashable {
    let раздел: String
    let название: String
    let истории: [ИсторияРаздела]
}

@MainActor
final class ХранилищеИсторий: ObservableObject {
    static let shared = ХранилищеИсторий()

    @Published private(set) var разделы: [String: ИсторииРаздела] = [:]
    /// ulx_st_seen сайта — просмотренные истории.
    @Published private(set) var просмотрены: Set<String> = []

    private init() {
        просмотрены = Set(UserDefaults.standard.stringArray(forKey: "kliko.feed.storiesSeen") ?? [])
    }

    /// Истории со страницы сайта (window.MK_STORIES). Нет страницы или историй — прежние остаются.
    func загрузить() async {
        guard let web = WebBridge.shared.webView, WebBridge.shared.isLoaded else { return }
        let js = "(function(){try{return JSON.stringify(window.MK_STORIES||null);}catch(e){return 'null';}})()"
        guard let строка = (try? await web.evaluateJavaScript(js)) as? String,
              let данные = строка.data(using: .utf8),
              let корень = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any] else { return }
        var итог: [String: ИсторииРаздела] = [:]
        for (ключ, значение) in корень {
            let набор = значение as? [String: Any]
            let список = (набор?["l"] as? [Any]) ?? (значение as? [Any]) ?? []
            let истории = список.compactMap { Self.история($0) }
            guard !истории.isEmpty else { continue }
            let имя = (набор?["n"] as? String) ?? ""
            итог[ключ] = ИсторииРаздела(раздел: ключ, название: имя, истории: истории)
        }
        if итог != разделы { разделы = итог }
    }

    private static func строка(_ поля: [String: Any], _ ключи: [String]) -> String? {
        for ключ in ключи {
            if let s = поля[ключ] as? String {
                let чистая = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !чистая.isEmpty { return чистая }
            } else if let n = поля[ключ] as? NSNumber {
                return n.stringValue
            }
        }
        return nil
    }

    private static func история(_ сырое: Any) -> ИсторияРаздела? {
        guard let поля = сырое as? [String: Any] else { return nil }
        let картинка = строка(поля, ["img", "image", "src"]).flatMap { Config.url($0) }
        let заголовок = строка(поля, ["t", "title"]) ?? ""
        guard картинка != nil || !заголовок.isEmpty else { return nil }
        let id = строка(поля, ["id"]) ?? (заголовок + "|" + (картинка?.absoluteString ?? ""))
        return ИсторияРаздела(id: id, картинка: картинка, заголовок: заголовок,
                              текст: строка(поля, ["p", "d", "text", "desc"]) ?? "",
                              кнопка: строка(поля, ["b", "cta", "btn"]),
                              ссылка: строка(поля, ["u", "url", "href", "link"]).flatMap { Config.url($0) })
    }

    /// mkStoriesWant: у раздела есть истории, и их не скрыли на 7 дней.
    func хочет(_ раздел: String) -> Bool {
        guard let набор = разделы[раздел], !набор.истории.isEmpty else { return false }
        let до = UserDefaults.standard.double(forKey: "kliko.feed.storiesHide." + раздел)
        return до <= Date().timeIntervalSince1970
    }

    func отметить(_ id: String) {
        guard !просмотрены.contains(id) else { return }
        просмотрены.insert(id)
        UserDefaults.standard.set(Array(просмотрены.suffix(500)), forKey: "kliko.feed.storiesSeen")
    }

    /// «Не показывать 7 дней» — с плитки раздел неделю не открывает истории сам.
    func скрытьНаНеделю(_ раздел: String) {
        UserDefaults.standard.set(Date().timeIntervalSince1970 + 7 * 86_400, forKey: "kliko.feed.storiesHide." + раздел)
    }
}

/// Что открыть в просмотре: раздел, с какой истории и откуда (с плитки — флажок «Не показывать 7 дней»).
struct ЦельИсторий: Identifiable, Hashable {
    let раздел: String
    let номер: Int
    let сПлитки: Bool

    var id: String { раздел + "#" + String(номер) + (сПлитки ? "t" : "r") }
}

// MARK: - Ряд кружков (_mxStRow, .vst)

struct РядИсторий: View {
    let набор: ИсторииРаздела
    let открыть: (Int) -> Void
    @ObservedObject private var хранилище = ХранилищеИсторий.shared

    init(набор: ИсторииРаздела, открыть: @escaping (Int) -> Void) {
        self.набор = набор
        self.открыть = открыть
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(набор.истории.enumerated()), id: \.element.id) { пара in
                    кружок(пара.element, номер: пара.offset)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 4)                // .vst: padding 2 2 4
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ВитринаТекст.т("st_news"))
    }

    private func кружок(_ история: ИсторияРаздела, номер: Int) -> some View {
        let просмотрена = хранилище.просмотрены.contains(история.id)
        return Button { открыть(номер) } label: {
            VStack(spacing: 6) {
                ZStack {
                    if просмотрена {
                        Circle().fill(Theme.линия)
                    } else {
                        Circle().fill(AngularGradient(colors: Self.кольцо, center: .center,
                                                      startAngle: .degrees(120), endAngle: .degrees(480)))
                    }
                    AsyncImage(url: история.картинка) { фаза in
                        if let картинка = фаза.image {
                            картинка.resizable().scaledToFill()
                        } else {
                            Theme.поверхность2
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .overlay { Circle().strokeBorder(Theme.поверхность, lineWidth: 2) }
                }
                .frame(width: 62, height: 62)
                Text(история.заголовок.isEmpty ? набор.название : история.заголовок)
                    .font(.system(size: 10, weight: .semibold))     // .vst-t: --fs-2xs 10 px, 600
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 72)
            }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.95))
    }

    /// conic-gradient(from 210deg, #fbbf24, #f43f5e, #d946ef, #8b5cf6, #fbbf24).
    private static let кольцо: [Color] = [Color(uiColor: Theme.hex(0xFBBF24)), Color(uiColor: Theme.hex(0xF43F5E)),
                                          Color(uiColor: Theme.hex(0xD946EF)), Color(uiColor: Theme.hex(0x8B5CF6)),
                                          Color(uiColor: Theme.hex(0xFBBF24))]
}

// MARK: - Просмотр (.stv)

struct ПросмотрИсторий: View {
    let набор: ИсторииРаздела
    let сПлитки: Bool
    /// «Перейти к …» — лента раздела.
    let перейти: (String) -> Void
    /// Ссылка белой кнопки — страница сайта или экран приложения.
    let открыть: (URL) -> Void

    @Environment(\.dismiss) private var закрыть
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @State private var номер: Int
    @State private var доля: Double = 0
    @State private var пауза = false
    @State private var скрыть7 = false
    @State private var наезд = false
    @State private var сдвиг: CGSize = .zero

    /// Одна история — 6,5 с, как наезд фото у сайта (.stv-img transition transform 6.5s).
    private static let длительность: Double = 6.5

    init(набор: ИсторииРаздела, начать: Int, сПлитки: Bool, перейти: @escaping (String) -> Void,
         открыть: @escaping (URL) -> Void) {
        self.набор = набор
        self.сПлитки = сПлитки
        self.перейти = перейти
        self.открыть = открыть
        _номер = State(initialValue: max(0, min(начать, набор.истории.count - 1)))
    }

    private var история: ИсторияРаздела? {
        guard набор.истории.indices.contains(номер) else { return nil }
        return набор.истории[номер]
    }

    private var раздел: РазделГлавной? { РазделГлавной.с(ключом: набор.раздел) }

    private var краска: Color {
        Color(uiColor: Theme.hex(раздел?.краска ?? 0x0F5132))
    }

    private var имяРаздела: String {
        if !набор.название.isEmpty { return набор.название }
        return DesignText.т("v_" + набор.раздел)
    }

    var body: some View {
        ZStack {
            Color(red: 5 / 255, green: 8 / 255, blue: 7 / 255).ignoresSafeArea()
            карточка
                .padding(.vertical, 4)
                .offset(y: max(0, сдвиг.height))
                .opacity(1 - min(0.5, max(0, сдвиг.height) / 600))
        }
        .statusBarHidden(true)
        .task(id: номер) { await идти() }
        .onChange(of: скрыть7) { _, вкл in
            if вкл { ХранилищеИсторий.shared.скрытьНаНеделю(набор.раздел) }
        }
    }

    private var карточка: some View {
        ZStack(alignment: .top) {
            фото
            LinearGradient(stops: [Gradient.Stop(color: Color.black.opacity(0.52), location: 0),
                                   Gradient.Stop(color: Color.clear, location: 0.2),
                                   Gradient.Stop(color: Color.clear, location: 0.46),
                                   Gradient.Stop(color: Color.black.opacity(0.84), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            GeometryReader { г in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(жест(ширина: г.size.width))
            }
            VStack(spacing: 12) {
                полоски
                шапка
                Spacer(minLength: 0)
                низ
            }
            .padding(.top, 12)
        }
        .background(Color(red: 11 / 255, green: 15 / 255, blue: 13 / 255))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
        .foregroundStyle(Color.white)
    }

    @ViewBuilder
    private var фото: some View {
        if let адрес = история?.картинка {
            GeometryReader { г in
                AsyncImage(url: адрес) { фаза in
                    if let картинка = фаза.image {
                        картинка
                            .resizable()
                            .scaledToFill()
                            .frame(width: г.size.width, height: г.size.height)
                            .scaleEffect(наезд || меньшеДвижения ? 1 : 1.05)
                            .clipped()
                    } else {
                        LinearGradient(colors: [краска, Color(red: 11 / 255, green: 15 / 255, blue: 13 / 255)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .id(адрес)
            }
            .allowsHitTesting(false)
        } else {
            LinearGradient(colors: [краска, Color(red: 11 / 255, green: 15 / 255, blue: 13 / 255)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .allowsHitTesting(false)
        }
    }

    /// .stv-bars: полоска на историю; пройденные — белые 92 %, текущая заполняется.
    private var полоски: some View {
        HStack(spacing: 4) {
            ForEach(набор.истории.indices, id: \.self) { н in
                GeometryReader { г in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(н < номер ? 0.92 : 0.3))
                        if н == номер {
                            Capsule()
                                .fill(Color.white)
                                .frame(width: г.size.width * CGFloat(доля))
                                .opacity(пауза ? 0.6 : 1)
                        }
                    }
                }
                .frame(height: 3)
                .shadow(color: Color.black.opacity(0.35), radius: 1.5, x: 0, y: 1)
            }
        }
        .padding(.horizontal, 14)
        .accessibilityHidden(true)
    }

    /// .stv-head: кружок раздела его цветом с белым кольцом, имя и «Новости и акции», «×».
    private var шапка: some View {
        HStack(spacing: 10) {
            Image(systemName: раздел?.значок ?? "sparkles")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 38, height: 38)
                .background(краска, in: Circle())
                .overlay { Circle().strokeBorder(Color.white.opacity(0.92), lineWidth: 2) }
            VStack(alignment: .leading, spacing: 1) {
                Text(имяРаздела)
                    .font(.system(size: 16, weight: .heavy))
                    .lineLimit(1)
                Text(ВитринаТекст.т("st_news"))
                    .font(.system(size: 11, weight: .semibold))
                    .opacity(0.74)
            }
            .shadow(color: Color.black.opacity(0.35), radius: 4)
            Spacer(minLength: 0)
            Button { закрыть() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.28), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ВитринаТекст.т("close"))
        }
        .padding(.horizontal, 14)
    }

    /// .stv-foot: заголовок, текст в три строки, белая кнопка, «Перейти к …», «Не показывать 7 дней».
    private var низ: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let история, !история.заголовок.isEmpty || !история.текст.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !история.заголовок.isEmpty {
                        Text(история.заголовок)
                            .font(.system(size: 24, weight: .heavy))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !история.текст.isEmpty {
                        Text(история.текст)
                            .font(.system(size: 15))
                            .lineLimit(3)
                            .opacity(0.92)
                    }
                }
                .shadow(color: Color.black.opacity(0.45), radius: 6)
                .accessibilityElement(children: .combine)
            }
            VStack(spacing: 8) {
                if let ссылка = история?.ссылка {
                    Button {
                        закрыть()
                        /* Объявление, раздел, «Работа», витрина, справка — своим экраном; прочее — прежним «открыть». */
                        if !ПереходыКабинета.своимЭкраном(ссылка, объявление: true) { открыть(ссылка) }
                    } label: {
                        Text(история?.кнопка ?? ВитринаТекст.т("st_more"))
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(Color(red: 11 / 255, green: 31 / 255, blue: 23 / 255))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(НажатиеСайта())
                }
                кнопкаРаздела(главная: история?.ссылка == nil)
            }
            if сПлитки {
                Toggle(isOn: $скрыть7) {
                    Text(ВитринаТекст.т("st_hide7"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                .toggleStyle(ФлажокИсторий())
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func кнопкаРаздела(главная: Bool) -> some View {
        Button {
            закрыть()
            перейти(набор.раздел)
        } label: {
            HStack(spacing: 8) {
                Text(ВитринаТекст.т("st_go_" + набор.раздел))
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .bold))
            }
            .font(.system(size: главная ? 16 : 15, weight: .heavy))
            .foregroundStyle(главная ? Color(red: 11 / 255, green: 31 / 255, blue: 23 / 255) : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: главная ? 50 : 46)
            .background(главная ? Color.white : Color.white.opacity(0.1), in: Capsule())
            .overlay { Capsule().strokeBorder(главная ? Color.white : Color.white.opacity(0.34), lineWidth: 1) }
        }
        .buttonStyle(НажатиеСайта())
    }

    /// Касание: левая треть — назад, остальное — вперёд; держать — пауза; вниз — закрыть; вбок — соседняя история.
    private func жест(ширина: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { значение in
                if !пауза { пауза = true }
                if значение.translation.height > 0 && abs(значение.translation.height) > abs(значение.translation.width) {
                    сдвиг = значение.translation
                }
            }
            .onEnded { значение in
                пауза = false
                let dx = значение.translation.width
                let dy = значение.translation.height
                withAnimation(.easeOut(duration: 0.2)) { сдвиг = .zero }
                if dy > 90 && abs(dy) > abs(dx) {
                    закрыть()
                    return
                }
                if abs(dx) > 60 && abs(dx) > abs(dy) {
                    if dx < 0 { вперёд() } else { назад() }
                    return
                }
                guard abs(dx) < 12 && abs(dy) < 12 else { return }
                /* Короткое касание — листаем; долгое — это была пауза. */
                if значение.startLocation.x < ширина / 3 { назад() } else { вперёд() }
            }
    }

    private func вперёд() {
        if номер + 1 < набор.истории.count {
            номер += 1
        } else {
            закрыть()
        }
    }

    private func назад() {
        if номер > 0 {
            номер -= 1
        } else {
            доля = 0
        }
    }

    /// Ход полоски: 6,5 с на историю, пауза держит; дошла — следующая.
    private func идти() async {
        доля = 0
        наезд = false
        if let история { ХранилищеИсторий.shared.отметить(история.id) }
        withAnimation(.linear(duration: Self.длительность)) { наезд = true }
        let шаг = 0.05
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            if пауза { continue }
            доля = min(1, доля + шаг / Self.длительность)
            if доля >= 1 {
                вперёд()
                return
            }
        }
    }
}

/// .stv-hide: квадратный флажок 20 × 20 с белой рамкой и подпись.
struct ФлажокИсторий: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(configuration.isOn ? Color(red: 11 / 255, green: 31 / 255, blue: 23 / 255) : Color.clear)
                    .frame(width: 20, height: 20)
                    .background(configuration.isOn ? Color.white : Color.clear,
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.white.opacity(configuration.isOn ? 1 : 0.72), lineWidth: 1.5)
                    }
                configuration.label
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

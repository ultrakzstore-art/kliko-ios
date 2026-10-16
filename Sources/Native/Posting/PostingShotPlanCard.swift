import SwiftUI
import UIKit

/**
 КАРТОЧКА «СНИМИТЕ ПО ПЛАНУ» НА ШАГЕ «ФОТО» — ЖИВАЯ (владелец 16.10.2026, скрин шага «Фото»: «снять по шагам сухой —
 добей»; удобно для глаз, ровная схема, мощная подача, летает на XR).

 Прежде — панель внутри карточки фото: значок, заголовок, совет, кадры чипами и бледная кнопка. Теперь — своя карточка
 шага сразу под карточкой фото (КарточкаПодачи: скругление 14, поля 16, кромка и тень — как у соседних):
   · шапка — кольцо прогресса «N/M» (заполняется при показе и с каждым новым кадром; план закрыт — зелёный диск
     с галочкой, «Все кадры сняты» и отклик «успех»), заголовок плана («Снимите по плану · Ноутбук») и «Снято N из M»;
     под ними совет плана — как был, слово в слово;
   · лента кадров — карточки одного размера 92×112: значок кадра (ПланСъёмки.значок) в цветном квадрате с мягким
     градиентом, номер в кружке, подпись в две строки; снятый — миниатюра снимка и зелёная галочка (новый — с
     пружинкой); пропущенный (не снят, а дальше по плану уже снято) — бледный; следующий — с зелёной кромкой. Касание
     неснятого — камера сразу на этом кадре (снятьКадр шага). Не помещаются — лента листается и встаёт по карточкам,
     край гаснет в фон карточки (есть ещё), при показе лента сама встаёт к следующему кадру;
   · «Снять по шагам» — главная кнопка подачи (градиент --g → --g2, как «Опубликовать»), когда она впервые за запуск
     на экране (не под краем и не под нижней панелью), по ней один раз проходит блик; после начала — «Продолжить
     съёмку · кадр 2 из 5» и какой кадр следующий.
 Галочки новых кадров ставятся, когда камера закрыта: снятое в камере отмечается лесенкой уже на глазах, после
 возврата. «Уменьшение движения» — всё сразу: без лесенки, пружин, прыжков и блика. Лёгкость для XR: ни GeometryReader
 в ленте (ряд или лента — выбирает ViewThatFits; один — у кнопки, и только пока блик не прошёл), ни размытия у карточек
 (размыт только блик кнопки и только на время прохода).
 */
struct ПланСъёмкиВид: View {
    let план: ПланСъёмки.План
    /// Места плана, у которых уже есть кадр.
    let снятые: Set<String>
    /// Плитки фото шага — миниатюры снятых кадров по их месту плана.
    let плитки: [ПлиткаФото]
    /// Камера открыта поверх шага — галочки новых кадров ждут возврата.
    let камераОткрыта: Bool
    /// Касание неснятого кадра; nil — кадры не нажимаются.
    let снять: ((String) -> Void)?
    /// «Снять по шагам»; nil — кнопки нет (план закрыт, места под фото нет, камеры нет).
    let поШагам: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    /// Карточка показана: лента встаёт лесенкой, кольцо заполняется.
    @State private var показ = false
    /// Места, чьи галочки уже поставлены (новые ставятся по одной, с пружинкой).
    @State private var отмеченные: Set<String> = []
    /// Растёт, когда план закрылся на глазах: отклик «успех», прыгают галочки и кольцо.
    @State private var праздник = 0
    /// Ход отметки новых кадров: новый ход отменяет прежний — «успех» и прыжки не срабатывают дважды.
    @State private var ходОтметки: Task<Void, Never>? = nil

    init(план: ПланСъёмки.План, снятые: Set<String>, плитки: [ПлиткаФото] = [], камераОткрыта: Bool = false,
         снять: ((String) -> Void)? = nil, поШагам: (() -> Void)? = nil) {
        self.план = план
        self.снятые = снятые
        self.плитки = плитки
        self.камераОткрыта = камераОткрыта
        self.снять = снять
        self.поШагам = поШагам
    }

    private func т(_ ключ: String) -> String { МастерПодачиText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    private var всего: Int { план.ключи.count }

    /// Места этого плана, у которых есть кадр.
    private var снятыеПлана: Set<String> { Set(план.ключи.filter { снятые.contains($0) }) }

    /// Галочка видна: место снято и его галочка уже поставлена.
    private func видно(_ ключ: String) -> Bool {
        !ключ.isEmpty && снятые.contains(ключ) && отмеченные.contains(ключ)
    }

    private var видноСнято: Int { план.ключи.filter { видно($0) }.count }

    private var всеСняты: Bool { всего > 0 && видноСнято >= всего }

    /// _rcNext без пропусков: первый неснятый кадр — с него камера «Снять по шагам».
    private var следующий: Int? { план.ключи.firstIndex { !снятые.contains($0) } }

    /// Последний снятый по порядку плана — всё неснятое до него (кроме следующего) считается пропущенным.
    private var последнийСнятый: Int { план.ключи.lastIndex { снятые.contains($0) } ?? -1 }

    var body: some View {
        КарточкаПодачи {
            VStack(alignment: .leading, spacing: 12) {
                шапка
                if !план.совет.isEmpty {
                    Text(план.совет)
                        .font(.system(size: 12))
                        .lineSpacing(2)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                лента
                if let поШагам {
                    КнопкаПоШагамПлана(заголовок: заголовокКнопки, подпись: подписьКнопки, тихо: тихо,
                                       действие: поШагам)
                        .padding(.top, 2)
                }
            }
        }
        .sensoryFeedback(.success, trigger: праздник)
        .onAppear { появиться() }
        .onChange(of: снятые) { _, _ in свести(послеКамеры: false) }
        .onChange(of: план.ключи) { _, _ in свести(послеКамеры: false) }
        .onChange(of: камераОткрыта) { _, открыта in
            if !открыта { свести(послеКамеры: true) }
        }
    }

    // MARK: Шапка

    /// Кольцо «N/M», заголовок плана и «Снято N из M» (всё снято — «Все кадры сняты» зелёным).
    private var шапка: some View {
        HStack(alignment: .center, spacing: 12) {
            КольцоПланаСъёмки(снято: видноСнято, всего: всего, показ: показ || тихо, тихо: тихо, праздник: праздник)
            VStack(alignment: .leading, spacing: 3) {
                Text(план.заголовок)
                    .font(.system(size: 14, weight: .heavy))
                    .kerning(-0.2)
                    .foregroundStyle(КраскаПодачи.текст)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(всеСняты ? т("rshc_all") : String(format: т("rsh_count"), min(видноСнято, всего), всего))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(всеСняты ? КраскаПодачи.хорошоТекст : Theme.текстВторой)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Лента кадров

    /// Все кадры помещаются — просто ряд; нет — лента с прокруткой по карточкам и гаснущим краем.
    private var лента: some View {
        ViewThatFits(in: .horizontal) {
            рядКадров
                .frame(maxWidth: .infinity, alignment: .leading)
            ScrollViewReader { прокрутка in
                ScrollView(.horizontal, showsIndicators: false) {
                    рядКадров
                        .scrollTargetLayout()
                }
                .contentMargins(.leading, 16, for: .scrollContent)
                .contentMargins(.trailing, 30, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .frame(height: КадрЛентыПлана.высота + 8)
                .overlay(alignment: .trailing) { крайЛенты }
                .padding(.horizontal, -16)
                .onAppear { встатьКСледующему(прокрутка, плавно: false) }
                .onChange(of: камераОткрыта) { _, открыта in
                    if !открыта { встатьКСледующему(прокрутка, плавно: true) }
                }
            }
        }
    }

    private var рядКадров: some View {
        HStack(spacing: 8) {
            ForEach(Array(план.кадры.enumerated()), id: \.offset) { номер, кадр in
                кадрЛенты(номер, кадр)
                    .id(номер)
            }
        }
        .padding(.vertical, 4)
    }

    /// Край ленты гаснет в фон карточки — видно, что дальше есть ещё кадры.
    private var крайЛенты: some View {
        LinearGradient(colors: [КраскаПодачи.карточка.opacity(0), КраскаПодачи.карточка], startPoint: .leading,
                       endPoint: .trailing)
            .frame(width: 28)
            .flipsForRightToLeftLayoutDirection(true)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Неснятый кадр при заданном действии — кнопка (камера на этом кадре), остальное — просто карточка.
    @ViewBuilder
    private func кадрЛенты(_ номер: Int, _ кадр: String) -> some View {
        let ключ = номер < план.ключи.count ? план.ключи[номер] : ""
        let отмечен = видно(ключ)
        let есть = !ключ.isEmpty && снятые.contains(ключ)
        let следом = номер == следующий
        let карточка = КадрЛентыПлана(номер: номер, подпись: кадр, значок: ПланСъёмки.значок(ключ),
                                     окраска: ОкраскаКадраПлана.для(ключ, номер),
                                     снимок: отмечен ? плитки.first(where: { $0.слот == ключ }) : nil,
                                     снят: отмечен, пропущен: !есть && !следом && номер < последнийСнятый,
                                     следующий: следом && снять != nil, праздник: праздник, тихо: тихо)
            .opacity(показ || тихо ? 1 : 0)
            .offset(y: показ || тихо ? 0 : 14)
            .animation(тихо ? nil : Animation.spring(response: 0.46, dampingFraction: 0.8)
                           .delay(0.05 + Double(номер) * 0.06), value: показ)
        if !есть, !ключ.isEmpty, let снять {
            Button { снять(ключ) } label: {
                карточка
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.95))
            .accessibilityHint(СъёмкаПоПлануText.т("chip_hint"))
        } else {
            карточка
        }
    }

    /// Лента сама встаёт к следующему кадру, если он за краем (первые три видны и так): при показе — сразу, после
    /// камеры — плавно, пока ставятся галочки.
    private func встатьКСледующему(_ прокрутка: ScrollViewProxy, плавно: Bool) {
        guard let цель = следующий, цель > 2 else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: плавно ? 300_000_000 : 60_000_000)
            if плавно {
                withAnimation(ДвижениеСайта.прокрутка) { прокрутка.scrollTo(цель, anchor: .center) }
            } else {
                прокрутка.scrollTo(цель, anchor: .center)
            }
        }
    }

    // MARK: Кнопка

    /// До первого кадра — «Снять по шагам»; после — «Продолжить съёмку · кадр 2 из 5».
    private var заголовокКнопки: String {
        guard !снятыеПлана.isEmpty, let следующий else { return СъёмкаПоПлануText.т("step_btn") }
        return т("rshc_go") + " · " + String(format: т("rshc_shot"), следующий + 1, всего)
    }

    /// До первого кадра — «Камера подскажет каждый кадр…»; после — «Следующий кадр: …».
    private var подписьКнопки: String {
        guard !снятыеПлана.isEmpty, let следующий, следующий < план.кадры.count else {
            return СъёмкаПоПлануText.т("step_btn_s")
        }
        return String(format: СъёмкаПоПлануText.т("cam_next"), план.кадры[следующий])
    }

    // MARK: Движение

    /// Первый показ: галочки снятого — сразу, без пружин; лента встаёт лесенкой, кольцо заполняется. Повторный
    /// onAppear (у вида под fullScreenCover камеры он приходит после её закрытия) галочки не трогает: новые ставит
    /// свести по одной.
    private func появиться() {
        guard !показ else { return }
        отмеченные = снятыеПлана
        показ = true
    }

    /// Новые кадры получают галочку по одной, с пружинкой (после камеры — когда она уже закрылась); ушедшие (удалили,
    /// «Начать сначала») снимаются сразу. Новый ход отменяет прежний (подряд пришли два обновления, кадр после
    /// закрытия камеры): неотмеченное он доделает сам. План закрылся на глазах — праздник, один раз: до хода план не
    /// закрыт (новые есть), а закончить ход может только последний.
    private func свести(послеКамеры: Bool) {
        guard !камераОткрыта else { return }
        let нужно = снятыеПлана
        let ушли = отмеченные.subtracting(нужно)
        if !ушли.isEmpty {
            withAnimation(ДвижениеСайта.смена) { отмеченные.subtract(ушли) }
        }
        let новые = план.ключи.filter { нужно.contains($0) && !отмеченные.contains($0) }
        guard !новые.isEmpty else { return }
        ходОтметки?.cancel()
        ходОтметки = nil
        let ключи = план.ключи
        if тихо {
            отмеченные.formUnion(новые)
            if ключи.allSatisfy({ отмеченные.contains($0) }) { праздник += 1 }
            return
        }
        ходОтметки = Task { @MainActor in
            try? await Task.sleep(nanoseconds: послеКамеры ? 420_000_000 : 80_000_000)
            for ключ in новые {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(response: 0.38, dampingFraction: 0.58)) { отмеченные.formUnion([ключ]) }
                try? await Task.sleep(nanoseconds: 140_000_000)
            }
            guard !Task.isCancelled else { return }
            if !ключи.isEmpty && ключи.allSatisfy({ отмеченные.contains($0) }) { праздник += 1 }
        }
    }
}

// MARK: - Карточка кадра в ленте

/// Кадр плана в ленте: значок в цветном квадрате (снят — миниатюра и галочка), номер в кружке, подпись в две строки.
struct КадрЛентыПлана: View {
    let номер: Int
    let подпись: String
    let значок: String
    let окраска: ОкраскаКадраПлана
    /// Плитка снятого кадра — её миниатюра вместо значка; nil — значок.
    let снимок: ПлиткаФото?
    let снят: Bool
    let пропущен: Bool
    let следующий: Bool
    let праздник: Int
    let тихо: Bool

    static let ширина: CGFloat = 92
    static let высота: CGFloat = 112
    private static let высотаКартинки: CGFloat = 60

    private func т(_ ключ: String) -> String { МастерПодачиText.т(ключ) }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return VStack(alignment: .leading, spacing: 7) {
            картинка
            Text(подпись)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(КраскаПодачи.текст)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(width: Self.ширина, height: Self.высота, alignment: .top)
        .background(снят ? КраскаПодачи.хорошоФон : КраскаПодачи.поле, in: форма)
        .overlay { форма.strokeBorder(кромка, lineWidth: следующий ? 1.5 : 1) }
        .opacity(пропущен ? 0.55 : 1)
        .contentShape(форма)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(голос)
        .accessibilityAddTraits(снят ? .isSelected : [])
    }

    private var кромка: Color {
        if следующий { return Theme.зелёный2 }
        return снят ? КраскаПодачи.хорошоТекст.opacity(0.35) : КраскаПодачи.линия
    }

    /// «1. Общий вид, снят» / «…, пропущен» / «…, следующий».
    private var голос: String {
        var части = [String(номер + 1) + ". " + подпись]
        if снят {
            части.append(т("rshc_done"))
        } else if пропущен {
            части.append(т("rshc_skip"))
        } else if следующий {
            части.append(т("rshc_next"))
        }
        return части.joined(separator: ", ")
    }

    /// Квадрат кадра: значок на мягком градиенте или миниатюра снимка; номер — слева сверху, галочка — справа.
    private var картинка: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous)
        return ZStack {
            if снят, let снимок {
                миниатюра(снимок)
                    .transition(.opacity)
            } else {
                значокКадра
                    .transition(.opacity)
            }
        }
        .frame(width: Self.ширина - 12, height: Self.высотаКартинки)
        .clipShape(форма)
        .overlay(alignment: .topLeading) {
            кружокНомера
                .padding(4)
        }
        .overlay(alignment: .topTrailing) {
            if снят {
                галочка
                    .padding(4)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
    }

    private var значокКадра: some View {
        let краска = снят ? ОкраскаКадраПлана.мята : окраска
        return LinearGradient(colors: [краска.верх, краска.низ], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: значок)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(краска.знак)
                    .accessibilityHidden(true)
            }
    }

    /// Миниатюра снятого: превью плитки, нет его — адрес сервера (черновик, правка), нет и его — значок.
    @ViewBuilder
    private func миниатюра(_ плитка: ПлиткаФото) -> some View {
        if let превью = плитка.превью {
            Color.clear
                .overlay {
                    Image(uiImage: превью)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else if let адрес = Config.url(плитка.url) {
            Color.clear
                .overlay {
                    /* КартинкаЛенты, а не AsyncImage: из памяти — в первом кадре, уменьшенной под карточку. */
                    КартинкаЛенты(адрес, пунктов: Self.ширина - 12) {
                        значокКадра
                    }
                }
                .clipped()
        } else {
            значокКадра
        }
    }

    private var кружокНомера: some View {
        Text(String(номер + 1))
            .font(.system(size: 10, weight: .heavy).monospacedDigit())
            .foregroundStyle(снят ? Color.white : окраска.знак)
            .frame(width: 18, height: 18)
            .background(снят ? Color.black.opacity(0.45) : КраскаПодачи.карточка.opacity(0.92), in: Circle())
            .accessibilityHidden(true)
    }

    private var галочка: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .black))
            .symbolEffect(.bounce, value: тихо ? 0 : праздник)
            .foregroundStyle(Color.white)
            .frame(width: 18, height: 18)
            .background(Theme.зелёный2, in: Circle())
            .overlay { Circle().strokeBorder(Color.white, lineWidth: 1.5) }
            .accessibilityHidden(true)
    }
}

// MARK: - Цвет кадра

/// Мягкий градиент квадрата и цвет значка: по порядку кадра — мята, небо, сирень, роза, янтарь; дефекты и износ — всегда
/// янтарь (внимание). Светлая тема — пастель, тёмная — прозрачный тон того же цвета.
struct ОкраскаКадраПлана {
    let верх: Color
    let низ: Color
    let знак: Color

    static func для(_ ключ: String, _ номер: Int) -> ОкраскаКадраПлана {
        if ключ.contains("defect") || ключ.contains("wear") { return янтарь }
        return набор[((номер % набор.count) + набор.count) % набор.count]
    }

    private static func тон(_ светлыйВерх: UInt32, _ светлыйНиз: UInt32, _ тёмный: UInt32, знак: Color) -> ОкраскаКадраПлана {
        ОкраскаКадраПлана(верх: Theme.цвет(светлый: Theme.hex(светлыйВерх), тёмный: Theme.hex(тёмный, 0.26)),
                          низ: Theme.цвет(светлый: Theme.hex(светлыйНиз), тёмный: Theme.hex(тёмный, 0.08)),
                          знак: знак)
    }

    static let мята = тон(0xD3F1E0, 0xF1FAF5, 0x34C997, знак: Theme.цвет(0x0F7A44, 0x5CD39A))
    static let небо = тон(0xD9E6FF, 0xF3F7FF, 0x60A5FA, знак: Theme.цвет(0x1E4FC2, 0x8CC0F7))
    static let сирень = тон(0xE8DEFF, 0xF7F3FF, 0xA78BFA, знак: Theme.цвет(0x6236C9, 0xBBA5FB))
    static let роза = тон(0xFBDDEA, 0xFFF4F8, 0xF472B6, знак: Theme.цвет(0xB0225F, 0xF59AC4))
    static let янтарь = тон(0xFCE9C8, 0xFFF8EC, 0xE0BD5E, знак: Theme.цвет(0xA14D07, 0xE8C877))

    private static let набор: [ОкраскаКадраПлана] = [мята, небо, сирень, роза, янтарь]
}

// MARK: - Кольцо прогресса

/// «0/5» в кольце: дорожка --line, заполнение — зелёный градиент; всё снято — зелёный диск с белой галочкой.
struct КольцоПланаСъёмки: View {
    let снято: Int
    let всего: Int
    /// false — кольцо пустое (до показа карточки), чтобы заполнение было видно.
    let показ: Bool
    let тихо: Bool
    let праздник: Int

    private static let размер: CGFloat = 46
    private static let толщина: CGFloat = 4

    private var доля: CGFloat {
        guard всего > 0, показ else { return 0 }
        return CGFloat(min(снято, всего)) / CGFloat(всего)
    }

    private var всё: Bool { всего > 0 && снято >= всего }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(КраскаПодачи.линия, lineWidth: Self.толщина)
            Circle()
                .inset(by: Self.толщина / 2)
                .trim(from: 0, to: доля)
                .stroke(LinearGradient(colors: [Theme.зелёный2, Theme.акцент], startPoint: .topLeading,
                                       endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: Self.толщина, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(тихо ? nil : Animation.spring(response: 0.7, dampingFraction: 0.86), value: доля)
            if всё {
                Circle()
                    .fill(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .padding(Self.толщина + 2)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .heavy))
                    .symbolEffect(.bounce, value: тихо ? 0 : праздник)
                    .foregroundStyle(Color.white)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(String(min(снято, всего)))
                        .font(.system(size: 15, weight: .heavy).monospacedDigit())
                        .foregroundStyle(КраскаПодачи.текст)
                        .contentTransition(.numericText())
                    Text("/" + String(всего))
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.текстВторой)
                }
                .transition(.opacity)
            }
        }
        .frame(width: Self.размер, height: Self.размер)
        .animation(тихо ? nil : Animation.spring(response: 0.42, dampingFraction: 0.6), value: всё)
        .accessibilityHidden(true)
    }
}

// MARK: - Кнопка «Снять по шагам»

/// Блик проходит по кнопке один раз за запуск приложения (когда кнопка на экране) — дальше кнопка спокойная.
enum БликКнопкиПлана {
    static var был = false
}

/// Главная кнопка плана: камера в светлом круге, заголовок и подпись белым, стрелка; градиент и тень — как у
/// КнопкаПодачи («Опубликовать»). При первом показе — косой блик слева направо (в арабском — справа налево).
struct КнопкаПоШагамПлана: View {
    let заголовок: String
    let подпись: String
    let тихо: Bool
    let действие: () -> Void

    /// Где блик: 0 — за левым краем, 1 — за правым.
    @State private var блик: CGFloat = 0
    /// Блик в пути — только тогда он есть в дереве (размытие не висит на кнопке постоянно).
    @State private var бликИдёт = false
    /// Блик ещё не прошёл: пока так — кнопку сторожит датчикБлика (после — его нет в дереве).
    @State private var ждётБлика = true

    init(заголовок: String, подпись: String, тихо: Bool, действие: @escaping () -> Void) {
        self.заголовок = заголовок
        self.подпись = подпись
        self.тихо = тихо
        self.действие = действие
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return Button(action: действие) {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.18), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(подпись)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                       endPoint: .bottomTrailing), in: форма)
            .overlay {
                if бликИдёт {
                    ПолосаБликаПлана(доля: блик)
                        .fill(Color.white.opacity(0.3))
                        .blur(radius: 7)
                        .flipsForRightToLeftLayoutDirection(true)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .clipShape(форма)
            .shadow(color: Color(uiColor: Theme.hex(0x0F5132, 0.45)), radius: 6, y: 6)
            .contentShape(форма)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .accessibilityElement(children: .combine)
        .background { датчикБлика }
    }

    /**
     Блик — когда кнопка на экране, а не при сборке шага: шаг «Фото» строится целиком, и кнопка под карточкой фото и
     плашками часто ниже края экрана или под нижней панелью (на XR — почти всегда). Пока блик не прошёл, лёгкий
     GeometryReader сверяет место кнопки с экраном; прошёл (или «Уменьшение движения», или уже был за этот запуск) —
     датчика нет в дереве.
     */
    @ViewBuilder
    private var датчикБлика: some View {
        if ждётБлика && !тихо && !БликКнопкиПлана.был {
            GeometryReader { г in
                let видна = Self.наЭкране(г.frame(in: .global))
                Color.clear
                    .onAppear { if видна { пройтиБликом() } }
                    .onChange(of: видна) { _, сейчас in
                        if сейчас { пройтиБликом() }
                    }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// Кнопка целиком на экране и выше нижней панели мастера (запас 110 pt снизу, 40 pt сверху — под шапкой).
    private static func наЭкране(_ место: CGRect) -> Bool {
        let экран = UIScreen.main.bounds
        return место.height > 0 && место.minY >= 40 && место.maxY <= экран.height - 110
    }

    /// Блик — один раз за запуск и не при «Уменьшении движения»: полоса появляется за краем, через миг едет.
    private func пройтиБликом() {
        guard !тихо, !БликКнопкиПлана.был else { return }
        БликКнопкиПлана.был = true
        ждётБлика = false
        блик = 0
        бликИдёт = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000)
            withAnimation(.easeInOut(duration: 1.1)) { блик = 1 }
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            бликИдёт = false
        }
    }
}

/// Косая полоса блика: доля 0 — целиком за левым краем, 1 — за правым; между ними едет плавно (animatableData).
struct ПолосаБликаПлана: Shape {
    var доля: CGFloat

    var animatableData: CGFloat {
        get { доля }
        set { доля = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let ширина = max(28, rect.width * 0.16)
        let наклон = rect.height * 0.45
        let путь = rect.width + ширина + наклон + 32
        let x = rect.minX - ширина - наклон - 16 + путь * доля
        var п = Path()
        п.move(to: CGPoint(x: x + наклон, y: rect.minY))
        п.addLine(to: CGPoint(x: x + наклон + ширина, y: rect.minY))
        п.addLine(to: CGPoint(x: x + ширина, y: rect.maxY))
        п.addLine(to: CGPoint(x: x, y: rect.maxY))
        п.closeSubpath()
        return п
    }
}

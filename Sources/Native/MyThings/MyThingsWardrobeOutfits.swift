import SwiftUI
import UIKit

/**
 «МОЙ ГАРДЕРОБ» — ОБРАЗЫ ИЗ СВОИХ ВЕЩЕЙ (пачка 16.10.2026; владелец: «мощная анимированная подача»).

 Доска-коллаж: 3–6 своих вещей на ровной раскладке (поле 4 : 5, места — по числу вещей: крупные слева, мелкие справа);
 порядок — по слоям (верх или целиком, низ, верхняя, обувь, аксессуары), дальше — как переставили. Перестановка —
 удержать и перетащить на другое место: вещь приподнимается и идёт за пальцем, место под ней вздрагивает, отпустили —
 обе встают пружиной. VoiceOver — действия «раньше», «позже», «убрать». «Уменьшение движения» и лёгкий режим — без
 полёта, сразу на место.

 Хранится только порядок вещей (ОбразМоего.вещи) — раскладка по нему одна и та же везде: на доске, на обложке образа
 в «Моём гардеробе». «Подобрать сам» — вещи недостающих слоёв, цвета которых сочетаются со всеми уже выбранными
 (ЦветСтандарта.сочетается), каждый раз в другом порядке. Только на телефоне (МоёХранилище.обновитьГардероб).
 */
enum РаскладкаОбраза {
    /// Ширина поля к высоте.
    static let пропорция: CGFloat = 0.8
    static let меньше = 3
    static let больше = 6

    /// Места вещей в долях поля (x, y, ширина, высота) по их числу.
    static func места(_ число: Int) -> [CGRect] {
        func м(_ x: CGFloat, _ y: CGFloat, _ ш: CGFloat, _ в: CGFloat) -> CGRect {
            CGRect(x: x, y: y, width: ш, height: в)
        }
        switch число {
        case ...0:
            return []
        case 1:
            return [м(0.12, 0.08, 0.76, 0.84)]
        case 2:
            return [м(0.03, 0.12, 0.46, 0.76), м(0.51, 0.12, 0.46, 0.76)]
        case 3:
            return [м(0.03, 0.03, 0.56, 0.46), м(0.03, 0.51, 0.56, 0.46), м(0.61, 0.27, 0.36, 0.46)]
        case 4:
            return [м(0.03, 0.03, 0.56, 0.46), м(0.03, 0.51, 0.56, 0.46), м(0.61, 0.03, 0.36, 0.46),
                    м(0.61, 0.51, 0.36, 0.46)]
        case 5:
            return [м(0.03, 0.03, 0.56, 0.46), м(0.03, 0.51, 0.56, 0.46), м(0.61, 0.03, 0.36, 0.30),
                    м(0.61, 0.35, 0.36, 0.30), м(0.61, 0.67, 0.36, 0.30)]
        default:
            return [м(0.03, 0.03, 0.46, 0.30), м(0.51, 0.03, 0.46, 0.30), м(0.03, 0.35, 0.46, 0.30),
                    м(0.51, 0.35, 0.46, 0.30), м(0.03, 0.67, 0.46, 0.30), м(0.51, 0.67, 0.46, 0.30)]
        }
    }

    /// Место в точках поля.
    static func рамка(_ доля: CGRect, _ поле: CGSize) -> CGRect {
        CGRect(x: доля.minX * поле.width, y: доля.minY * поле.height, width: доля.width * поле.width,
               height: доля.height * поле.height)
    }

    /// Порядок слоёв на доске: главное — на крупных местах.
    static func номерСлоя(_ слой: СлойГардеробаМоего) -> Int {
        switch слой {
        case .верх, .целиком: return 0
        case .низ: return 1
        case .верхняя: return 2
        case .обувь: return 3
        case .аксессуар: return 4
        }
    }

    /// Новая вещь — на место своего слоя (после вещей того же и более главных слоёв).
    static func вставить(_ id: UUID, _ вид: ВидВещиГардеробаМоего, в порядок: inout [UUID], гардероб: ГардеробМоего) {
        let мой = номерСлоя(вид.слой)
        let место = порядок.firstIndex { другой in
            guard let в = гардероб.вещь(другой) else { return false }
            return номерСлоя(в.вид.слой) > мой
        } ?? порядок.count
        порядок.insert(id, at: место)
    }

    /**
     «Подобрать сам»: к выбранным — вещи недостающих слоёв (с платьем или костюмом — обувь, верхняя, аксессуар; иначе —
     верх, низ, обувь, верхняя, аксессуар), каждая сочетается по цвету со всеми уже взятыми; кандидаты перемешаны.
     Ничего не выбрано — начинает с верха или платья. Не больше шести.
     */
    static func подобрать(_ выбранные: [UUID], гардероб: ГардеробМоего) -> [UUID] {
        var итог = выбранные.filter { гардероб.вещь($0) != nil }
        var взятые = итог.compactMap { гардероб.вещь($0) }
        if взятые.isEmpty, let главная = гардероб.вещи.filter({ $0.вид.слой == .верх || $0.вид.слой == .целиком })
            .shuffled().first {
            итог.append(главная.id)
            взятые.append(главная)
        }
        let целиком = взятые.contains { $0.вид.слой == .целиком }
        let нужные: [СлойГардеробаМоего] = целиком ? [.обувь, .верхняя, .аксессуар]
            : [.верх, .низ, .обувь, .верхняя, .аксессуар]
        for слой in нужные where итог.count < больше && !взятые.contains(where: { $0.вид.слой == слой }) {
            let кандидат = гардероб.вещи.shuffled().first { в in
                в.вид.слой == слой && !итог.contains(в.id) && взятые.allSatisfy { $0.сочетается(с: в) }
            }
            if let кандидат {
                вставить(кандидат.id, кандидат.вид, в: &итог, гардероб: гардероб)
                взятые.append(кандидат)
            }
        }
        return итог
    }

    /// Цвета образа: все пары сочетаются и ярких не больше двух — хорошо; иначе — что не так.
    static func проверка(_ вещи: [ВещьГардеробаМоего]) -> (хорошо: Bool, текст: String) {
        let цвета = вещи.compactMap(\.цвета.first)
        for (номер, а) in цвета.enumerated() {
            for б in цвета.dropFirst(номер + 1) where !а.сочетается(с: б) {
                return (false, String(format: МойГардеробText.т("mw_outfit_clash"), а.название, б.название.lowercased()))
            }
        }
        let яркие = Set(цвета.filter { !$0.нейтральный })
        if яркие.count > 2 { return (false, МойГардеробText.т("mw_outfit_loud")) }
        return (true, МойГардеробText.т(цвета.isEmpty ? "mw_outfit_nocolor" : "mw_outfit_ok"))
    }

    /// Чего не хватает до полного образа: «Добавьте обувь»; хватает — nil.
    static func нехватка(_ вещи: [ВещьГардеробаМоего]) -> String? {
        let слои = Set(вещи.map(\.вид.слой))
        if !слои.contains(.целиком) {
            if !слои.contains(.верх) { return МойГардеробText.т("mw_outfit_need_top") }
            if !слои.contains(.низ) { return МойГардеробText.т("mw_outfit_need_bottom") }
        }
        if !слои.contains(.обувь) { return МойГардеробText.т("mw_outfit_need_shoes") }
        return nil
    }
}

// MARK: - Доска

/// Доска-коллаж образа с перестановкой. переставить(откуда, куда) — номера мест.
struct ДоскаОбраза: View {
    let вещи: [ВещьГардеробаМоего]
    let переставить: (Int, Int) -> Void
    let убрать: (UUID) -> Void
    @State private var тащим: UUID? = nil
    @State private var сдвиг: CGSize = .zero
    @State private var над: Int? = nil

    init(вещи: [ВещьГардеробаМоего], переставить: @escaping (Int, Int) -> Void, убрать: @escaping (UUID) -> Void) {
        self.вещи = вещи
        self.переставить = переставить
        self.убрать = убрать
    }

    /// Своё поле координат доски: место пальца и места вещей — в нём.
    private static let имяПоля = "доскаОбраза"

    private func т(_ ключ: String) -> String { МойГардеробText.т(ключ) }

    /// Вещь идёт за пальцем; «Уменьшение движения» и лёгкий режим — нет (меняются местами по отпусканию).
    private var полёт: Bool { !(ДвижениеСайта.тихо || РежимУстройства.shared.лёгкий) }

    var body: some View {
        GeometryReader { место in
            let поле = место.size
            let места = РаскладкаОбраза.места(вещи.count)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .fill(Theme.поверхность2)
                if вещи.isEmpty {
                    пусто
                }
                ForEach(Array(вещи.enumerated()), id: \.element.id) { номер, вещь in
                    if номер < места.count {
                        плитка(вещь, номер: номер, рамка: РаскладкаОбраза.рамка(места[номер], поле), места: места,
                               поле: поле)
                    }
                }
            }
            .coordinateSpace(NamedCoordinateSpace.named(Self.имяПоля))
        }
        .aspectRatio(РаскладкаОбраза.пропорция, contentMode: .fit)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .animation(ДвижениеСайта.мягко(.spring(response: 0.38, dampingFraction: 0.82)), value: вещи.map(\.id))
    }

    private var пусто: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            Text(т("mw_outfit_board_empty"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private func плитка(_ вещь: ВещьГардеробаМоего, номер: Int, рамка: CGRect, места: [CGRect],
                        поле: CGSize) -> some View {
        /* Значения — заранее, с явными типами: тернарники и арифметика в одной цепочке модификаторов — риск проверки
           типов в CI. Цепочка разбита на два оператора, порядок модификаторов прежний. */
        let этаТащится: Bool = тащим == вещь.id
        let подЭтой: Bool = над == номер && !этаТащится
        let цветРамки: Color = подЭтой ? Theme.акцент : Theme.линия
        let толщинаРамки: CGFloat = подЭтой ? 2 : 1
        let видимостьКнопки: Double = этаТащится ? 0 : 1
        let масштаб: CGFloat = этаТащится ? 1.06 : (подЭтой ? 0.95 : 1)
        let прозрачностьТени: Double = этаТащится ? 0.22 : 0
        let цветТени: Color = Color.black.opacity(прозрачностьТени)
        let радиусТени: CGFloat = этаТащится ? 14 : 0
        let сдвигТени: CGFloat = этаТащится ? 8 : 0
        let центрX: CGFloat = этаТащится ? рамка.midX + сдвиг.width : рамка.midX
        let центрY: CGFloat = этаТащится ? рамка.midY + сдвиг.height : рамка.midY
        let порядокСлоя: Double = этаТащится ? 10 : 0
        let основа = КартинкаВещиГардероба(вещь: вещь, поля: 8)
            .frame(width: рамка.width, height: рамка.height)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(цветРамки, lineWidth: толщинаРамки)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    ОткликСайта.выбор()
                    убрать(вещь.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.black.opacity(0.45))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеКнопкиФото(сжатие: 0.85))
                .opacity(видимостьКнопки)
                .accessibilityHidden(true)
            }
            .scaleEffect(масштаб)
            .shadow(color: цветТени, radius: радиусТени, y: сдвигТени)
            .gesture(перетаскивание(вещь, номер: номер, места: места, поле: поле))
        return основа
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(вещь.заголовок)
            .accessibilityHint(т("mw_outfit_drag_hint"))
            .accessibilityAction(named: Text(т("mw_outfit_earlier"))) {
                if номер > 0 { переставить(номер, номер - 1) }
            }
            .accessibilityAction(named: Text(т("mw_outfit_later"))) {
                if номер + 1 < вещи.count { переставить(номер, номер + 1) }
            }
            .accessibilityAction(named: Text(т("mw_outfit_remove"))) { убрать(вещь.id) }
            .position(x: центрX, y: центрY)
            .zIndex(порядокСлоя)
    }

    /// Удержать и тащить: вещь за пальцем, место под пальцем подсвечено; отпустили над другим — меняются местами.
    private func перетаскивание(_ вещь: ВещьГардеробаМоего, номер: Int, места: [CGRect],
                                поле: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.22)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: NamedCoordinateSpace.named(Self.имяПоля)))
            .onChanged { значение in
                switch значение {
                case .first(true):
                    guard тащим == nil else { return }
                    ОткликСайта.выбор()
                    withAnimation(ДвижениеСайта.мягко(.spring(response: 0.3, dampingFraction: 0.75))) { тащим = вещь.id }
                case .second(true, let ход?):
                    if тащим == nil { тащим = вещь.id }
                    сдвиг = полёт ? ход.translation : .zero
                    let новое = места.indices.first { РаскладкаОбраза.рамка(места[$0], поле).contains(ход.location) }
                    let цель = новое == номер ? nil : новое
                    if цель != над {
                        if цель != nil { ОткликСайта.выбор() }
                        withAnimation(ДвижениеСайта.выбор) { над = цель }
                    }
                default:
                    break
                }
            }
            .onEnded { _ in
                let цель = над
                withAnimation(ДвижениеСайта.мягко(.spring(response: 0.38, dampingFraction: 0.8))) {
                    if let цель { переставить(номер, цель) }
                    тащим = nil
                    сдвиг = .zero
                    над = nil
                }
                if цель != nil { ОткликСайта.успех() }
            }
    }
}

/// Обложка образа: та же раскладка из миниатюр, без жестов.
struct ОбложкаОбраза: View {
    let вещи: [ВещьГардеробаМоего]

    init(вещи: [ВещьГардеробаМоего]) {
        self.вещи = вещи
    }

    var body: some View {
        GeometryReader { место in
            let поле = место.size
            let видимые = Array(вещи.prefix(РаскладкаОбраза.больше))
            let места = РаскладкаОбраза.места(видимые.count)
            ZStack {
                Theme.поверхность2
                ForEach(Array(видимые.enumerated()), id: \.element.id) { номер, вещь in
                    let рамка = РаскладкаОбраза.рамка(места[номер], поле)
                    КартинкаВещиГардероба(вещь: вещь, поля: 4)
                        .frame(width: рамка.width, height: рамка.height)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                        .position(x: рамка.midX, y: рамка.midY)
                }
            }
        }
        .aspectRatio(РаскладкаОбраза.пропорция, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Карточка на экране

/// «Образы»: обложки своих образов рядом и «Собрать образ»; вещей меньше трёх — подсказка.
struct КарточкаОбразовГардероба: View {
    let гардероб: ГардеробМоего
    let открыть: (UUID?) -> Void

    init(гардероб: ГардеробМоего, открыть: @escaping (UUID?) -> Void) {
        self.гардероб = гардероб
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { МойГардеробText.т(ключ) }

    private var можно: Bool {
        гардероб.вещи.count >= РаскладкаОбраза.меньше && гардероб.образы.count < ГардеробМоего.пределОбразов
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mw_outfits"), значок: "rectangle.3.group")
            if гардероб.образы.isEmpty {
                Text(т(можно ? "mw_outfits_empty" : "mw_outfits_need"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(гардероб.образы) { образ in
                            обложка(образ)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            МалаяКнопкаАвтоподбора(заголовок: т("mw_outfit_new"), значок: "plus.rectangle.on.rectangle") {
                ОткликСайта.выбор()
                открыть(nil)
            }
            .disabled(!можно)
            .opacity(можно ? 1 : 0.45)
        }
        .карточкаМоего()
    }

    private func обложка(_ образ: ОбразМоего) -> some View {
        let вещи = гардероб.вещиОбраза(образ)
        let имя: String = образ.имя.isEmpty ? String(format: т("mw_outfit_n_items"), String(вещи.count)) : образ.имя
        /* Подпись для VoiceOver — заранее, с явными типами (склейка с map и joined в accessibilityLabel — риск
           проверки типов). */
        let состав: String = вещи.map(\.заголовок).joined(separator: ", ")
        let голос: String = имя + ". " + состав
        return Button {
            ОткликСайта.выбор()
            открыть(образ.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ОбложкаОбраза(вещи: вещи)
                    .frame(width: 124)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1)
                    }
                Text(имя)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .frame(width: 124, alignment: .leading)
            }
        }
        .buttonStyle(НажатиеСайта())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(голос)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Лист образа

/// Сборка образа: доска, проверка цветов, «Подобрать сам», название шаблоном, выбор своих вещей по слоям.
struct ЛистОбразаГардероба: View {
    let был: ОбразМоего?
    @ObservedObject private var хранилище = МоёХранилище.shared
    @Environment(\.dismiss) private var закрыть
    @Environment(\.horizontalSizeClass) private var класс
    @State private var вещи: [UUID]
    @State private var имя: String
    @State private var слой: СлойГардеробаМоего? = nil
    @State private var спросить = false

    /// Шаблоны названий — ключи подписей.
    private static let шаблоны = ["mw_outfit_tpl_work", "mw_outfit_tpl_weekend", "mw_outfit_tpl_evening",
                                  "mw_outfit_tpl_sport", "mw_outfit_tpl_travel"]

    init(образ: ОбразМоего?) {
        был = образ
        _вещи = State(initialValue: Array((образ?.вещи ?? []).prefix(РаскладкаОбраза.больше)))
        _имя = State(initialValue: образ?.имя ?? "")
    }

    private func т(_ ключ: String) -> String { МойГардеробText.т(ключ) }

    private var можно: Bool { (РаскладкаОбраза.меньше...РаскладкаОбраза.больше).contains(вещи.count) }

    var body: some View {
        let г = хранилище.запись.гардероб
        let выбранные = вещи.compactMap { г.вещь($0) }
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    доска(выбранные)
                    названиеБлок
                    выборВещей(г)
                    if был != nil {
                        МалаяКнопкаАвтоподбора(заголовок: т("mw_outfit_delete"), значок: "trash", опасная: true) {
                            спросить = true
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т(был == nil ? "mw_outfit_new" : "mw_outfit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(МоёText.т("my_cancel")) { закрыть() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(МоёText.т("my_save")) { сохранить() }
                        .fontWeight(.bold)
                        .disabled(!можно)
                }
            }
            .клавиатураМоего()
        }
        .tint(Theme.акцент)
        .confirmationDialog(т("mw_outfit_delete_q"), isPresented: $спросить, titleVisibility: .visible) {
            Button(МоёText.т("my_delete"), role: .destructive) { удалить() }
            Button(МоёText.т("my_cancel"), role: .cancel) {}
        }
    }

    // MARK: Доска и проверка

    private func доска(_ выбранные: [ВещьГардеробаМоего]) -> some View {
        let проверка = РаскладкаОбраза.проверка(выбранные)
        let нехватка = РаскладкаОбраза.нехватка(выбранные)
        return VStack(alignment: .leading, spacing: 10) {
            ДоскаОбраза(вещи: выбранные, переставить: переставить, убрать: убрать)
            HStack(spacing: 8) {
                Text(String(format: т("mw_outfit_count"), String(вещи.count), String(РаскладкаОбраза.больше)))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(можно ? Theme.акцент : Theme.текстВторой)
                    .contentTransition(.numericText())
                Spacer(minLength: 4)
                МалаяКнопкаАвтоподбора(заголовок: т("mw_outfit_auto"), значок: "wand.and.stars") { подобрать() }
            }
            if выбранные.count >= 2 {
                Label(проверка.текст, systemImage: проверка.хорошо ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(проверка.хорошо ? Theme.акцент : Theme.оранжевый)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            if let нехватка, !выбранные.isEmpty {
                Label(нехватка, systemImage: "plus.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .transition(.opacity)
            }
            if выбранные.count >= 2 {
                Text(т("mw_outfit_drag_hint"))
                    .font(.caption2)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .карточкаМоего(поля: 12)
        .animation(ДвижениеСайта.смена, value: вещи)
    }

    private var названиеБлок: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("mw_outfit_name"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
            ПолеТекстаГардероба(подсказка: т("mw_outfit_name_ph"), текст: $имя, предел: 40)
            ПотокЧипов(зазор: 6) {
                ForEach(Self.шаблоны, id: \.self) { ключ in
                    let подпись = т(ключ)
                    ЧипМоего(подпись, выбран: имя == подпись) {
                        ОткликСайта.выбор()
                        имя = имя == подпись ? "" : подпись
                    }
                }
            }
        }
        .карточкаМоего()
    }

    // MARK: Свои вещи

    private func выборВещей(_ г: ГардеробМоего) -> some View {
        let показ = г.вещи.filter { слой == nil || $0.вид.слой == слой }
        let колонки = Array(repeating: GridItem(.flexible(), spacing: 8), count: класс == .regular ? 5 : 3)
        return VStack(alignment: .leading, spacing: 10) {
            ЗаголовокМоего(т("mw_outfit_pick"), значок: "hanger")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ЧипМоего(т("mw_all"), выбран: слой == nil) { слой = nil }
                    ForEach(СлойГардеробаМоего.allCases, id: \.self) { с in
                        if г.вещи.contains(where: { $0.вид.слой == с }) {
                            ЧипМоего(МойГардеробText.слой(с), выбран: слой == с) {
                                ОткликСайта.выбор()
                                withAnimation(ДвижениеСайта.смена) { слой = с }
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            LazyVGrid(columns: колонки, spacing: 8) {
                ForEach(показ) { вещь in
                    плиткаВыбора(вещь, г)
                }
            }
        }
        .карточкаМоего()
    }

    private func плиткаВыбора(_ вещь: ВещьГардеробаМоего, _ г: ГардеробМоего) -> some View {
        let выбрана = вещи.contains(вещь.id)
        let полно = вещи.count >= РаскладкаОбраза.больше && !выбрана
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return Button {
            переключить(вещь, г)
        } label: {
            Color.clear
                .aspectRatio(0.8, contentMode: .fit)
                .overlay { КартинкаВещиГардероба(вещь: вещь, поля: 6) }
                .clipShape(форма)
                .overlay { форма.strokeBorder(выбрана ? Theme.акцент : Theme.линия, lineWidth: выбрана ? 2.5 : 1) }
                .overlay(alignment: .topTrailing) {
                    if выбрана {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Theme.акцент)
                            .padding(5)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .opacity(полно ? 0.4 : 1)
                .contentShape(форма)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.94))
        .disabled(полно)
        .animation(ДвижениеСайта.выбор, value: выбрана)
        .accessibilityLabel(вещь.заголовок)
        .accessibilityAddTraits(выбрана ? .isSelected : [])
    }

    // MARK: Действия

    private func переключить(_ вещь: ВещьГардеробаМоего, _ г: ГардеробМоего) {
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.мягко(.spring(response: 0.38, dampingFraction: 0.82))) {
            if let i = вещи.firstIndex(of: вещь.id) {
                вещи.remove(at: i)
            } else if вещи.count < РаскладкаОбраза.больше {
                РаскладкаОбраза.вставить(вещь.id, вещь.вид, в: &вещи, гардероб: г)
            }
        }
    }

    private func переставить(_ откуда: Int, _ куда: Int) {
        guard вещи.indices.contains(откуда), вещи.indices.contains(куда), откуда != куда else { return }
        вещи.swapAt(откуда, куда)
    }

    private func убрать(_ id: UUID) {
        withAnimation(ДвижениеСайта.мягко(.spring(response: 0.38, dampingFraction: 0.82))) {
            вещи.removeAll { $0 == id }
        }
    }

    private func подобрать() {
        let г = хранилище.запись.гардероб
        let новые = РаскладкаОбраза.подобрать(вещи, гардероб: г)
        guard новые != вещи else {
            ОткликСайта.предупреждение()
            return
        }
        ОткликСайта.успех()
        withAnimation(ДвижениеСайта.мягко(.spring(response: 0.42, dampingFraction: 0.8))) { вещи = новые }
    }

    private func сохранить() {
        guard можно else { return }
        let имяОбраза = String(имя.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let состав = вещи
        if let был {
            хранилище.обновитьГардероб { г in
                guard let i = г.образы.firstIndex(where: { $0.id == был.id }) else { return }
                г.образы[i].имя = имяОбраза
                г.образы[i].вещи = состав
            }
        } else {
            guard хранилище.запись.гардероб.образы.count < ГардеробМоего.пределОбразов else {
                ОткликСайта.предупреждение()
                return
            }
            let новый = ОбразМоего(имя: имяОбраза, вещи: состав)
            хранилище.обновитьГардероб { г in г.образы.insert(новый, at: 0) }
        }
        ОткликСайта.успех()
        закрыть()
    }

    private func удалить() {
        guard let был else { return }
        хранилище.обновитьГардероб { г in г.образы.removeAll { $0.id == был.id } }
        ОткликСайта.успех()
        закрыть()
    }
}

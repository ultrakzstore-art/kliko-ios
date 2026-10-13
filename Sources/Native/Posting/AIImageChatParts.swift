import SwiftUI
import UIKit

/**
 ОКНО «ОБЪЯВЛЕНИЕ С ИИ» — РЕПЛИКИ.

 Человек — зелёный пузырь справа (и миниатюра его фото). ИИ — слева, со значком палочки:
   · ждём — карточка-заглушка: бегущее сияние, проценты, «Пишу описание…» / «Рисую обложку…» / «Правлю фото…»;
   · черновик (последний в диалоге) — богатая карточка: обложка-иллюстрация с плашкой «Иллюстрация ИИ», заголовок,
     раздел и состояние, описание, характеристики (сомнительные — с «?»), подсказка цены; изменённое в этом ходе —
     с зелёной меткой. Под ней — «Создать объявление», «Изменить», «Другая обложка» и постер-оформление;
   · картинка (правка или прежняя иллюстрация) — проявляется из размытия; плашка «Изменено ИИ» / «Иллюстрация ИИ»;
     «Взять в объявление» (в правке плитки — «Заменить фото» и «Добавить новым»), «Ещё вариант», «Править эту»,
     «Сравнить» — шторка «До / После»;
   · отказ — готовый текст и кнопки по случаю: «Повторить», «Проверить ещё раз», «Другое фото», «Начать заново»,
     «Свой ИИ».
 «Уменьшение движения» — без сияния и проявления; VoiceOver — подписи у картинок и кнопок, шторка — регулируемая.
 */
struct РепликаИИФотоВид: View {
    @ObservedObject var модель: МодельЧатаИИФото
    let реплика: РепликаИИФото
    let полная: Bool

    init(модель: МодельЧатаИИФото, реплика: РепликаИИФото, полная: Bool) {
        self.модель = модель
        self.реплика = реплика
        self.полная = полная
    }

    var body: some View {
        switch реплика.кто {
        case .человек:
            ПузырьЧеловекаИИФото(реплика: реплика)
        case .ии:
            ОтветИИФотоВид(модель: модель, реплика: реплика, полная: полная)
        }
    }
}

// MARK: - Человек

struct ПузырьЧеловекаИИФото: View {
    let реплика: РепликаИИФото

    init(реплика: РепликаИИФото) {
        self.реплика = реплика
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 56)
            VStack(alignment: .trailing, spacing: 6) {
                if let фото = реплика.фото {
                    Image(uiImage: фото)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 140, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                        .accessibilityLabel(ИИФотоText.т("aim_your_photo"))
                }
                Text(реплика.текст)
                    .font(.body)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Theme.пузырьМой,
                                in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18,
                                                           bottomTrailingRadius: 6, topTrailingRadius: 18,
                                                           style: .continuous))
                    .accessibilityLabel(ИИФотоText.т("aim_you") + ": " + реплика.текст)
            }
        }
    }
}

// MARK: - ИИ

struct ОтветИИФотоВид: View {
    @ObservedObject var модель: МодельЧатаИИФото
    let реплика: РепликаИИФото
    let полная: Bool

    init(модель: МодельЧатаИИФото, реплика: РепликаИИФото, полная: Bool) {
        self.модель = модель
        self.реплика = реплика
        self.полная = полная
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                содержимое
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        if let черновик = реплика.черновик, полная {
            КарточкаЧерновикаИИФото(модель: модель, реплика: реплика, черновик: черновик)
        } else {
            if реплика.состояние == .ждём {
                ЗаглушкаИИФото(прогресс: реплика.прогресс, подпись: ЗаглушкаИИФото.подписьЭтапа(реплика),
                               квадрат: реплика.нуженРисунок)
            } else if let картинка = реплика.картинка {
                КартинкаОтветаИИФото(модель: модель, реплика: реплика, картинка: картинка)
            } else if реплика.удалена {
                ЗаметкаПодачи(т("aim_image_gone"), тон: .серый, значок: "photo")
            }
            if !реплика.текст.isEmpty && реплика.состояние != .ждём {
                ПодписьИИФото(текст: реплика.текст, своимИИ: реплика.своимИИ)
            }
            if реплика.черновик != nil {
                Label(т("aim_draft_updated"), systemImage: "doc.text")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        if !реплика.заметка.isEmpty {
            ЗаметкаПодачи(реплика.заметка, тон: .инфо, значок: "info.circle")
        }
        if реплика.состояние == .отказ, let отказ = реплика.отказ {
            ОтказЧатаИИФото(модель: модель, реплика: реплика, отказ: отказ)
        }
    }
}

/// Ответ ИИ текстом — пузырь слева; «через ваш ИИ», если ход сделал «Свой ИИ» (own_ai_run).
struct ПодписьИИФото: View {
    let текст: String
    let своимИИ: Bool

    init(текст: String, своимИИ: Bool) {
        self.текст = текст
        self.своимИИ = своимИИ
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(текст)
                .font(.body)
                .foregroundStyle(КраскаПодачи.текст)
                .fixedSize(horizontal: false, vertical: true)
            if своимИИ {
                Text(СвойИИText.т("oai_via"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.пузырьЧужой,
                    in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 18, bottomTrailingRadius: 18,
                                               topTrailingRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Ожидание

/// Карточка-заглушка хода: мягкий зелёный фон, бегущее сияние, палочка, проценты, этап и полоса.
struct ЗаглушкаИИФото: View {
    let прогресс: Int
    let подпись: String
    let квадрат: Bool
    var проценты = true
    @State private var бег = false
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения

    init(прогресс: Int, подпись: String, квадрат: Bool, проценты: Bool = true) {
        self.прогресс = прогресс
        self.подпись = подпись
        self.квадрат = квадрат
        self.проценты = проценты
    }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    /// «Жду очереди…», «Пишу описание…», «Рисую обложку…» / «Правлю фото…», «Проверяю…».
    static func подписьЭтапа(_ р: РепликаИИФото) -> String {
        let т = ИИФотоText.т
        if р.вОчереди { return т("aim_stage_queue") }
        switch р.этап {
        case "text": return т("aim_stage_text")
        case "image": return т(р.режим == "edit" ? "aim_stage_edit" : "aim_stage_image")
        case "check": return т("aim_stage_check")
        default: return т(р.режим == "edit" ? "aim_stage_edit" : "aim_stage_think")
        }
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        return ZStack {
            LinearGradient(colors: [КраскаПодачи.хорошоФон, КраскаПодачи.поле, КраскаПодачи.хорошоФон],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            сияние
            VStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                    .symbolEffect(.pulse, isActive: !тихо)
                    .accessibilityHidden(true)
                if проценты {
                    Text(String(прогресс) + "%")
                        .font(.title2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(КраскаПодачи.текст)
                        .contentTransition(.numericText())
                }
                Text(подпись)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                if проценты {
                    ProgressView(value: Double(прогресс), total: 100)
                        .tint(Theme.зелёный2)
                        .frame(maxWidth: 180)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: квадрат ? nil : 150)
        .aspectRatio(квадрат ? 1 : nil, contentMode: .fit)
        .clipShape(форма)
        .overlay { форма.strokeBorder(КраскаПодачи.хорошоТекст.opacity(0.22), lineWidth: 1) }
        .onAppear {
            guard !тихо else { return }
            бег = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(подпись)
        .accessibilityValue(проценты ? String(format: ИИФотоText.т("aim_progress_a11y"), прогресс) : "")
        .accessibilityAddTraits(.updatesFrequently)
    }

    private static let бегСияния = Animation.linear(duration: 1.5).repeatForever(autoreverses: false)

    private var сияние: some View {
        GeometryReader { г in
            LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.5), Color.white.opacity(0)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: г.size.width * 0.45)
                .rotationEffect(.degrees(16))
                .offset(x: бег ? г.size.width * 1.2 : -г.size.width * 0.7)
                .animation(бег ? Self.бегСияния : nil, value: бег)
        }
        .opacity(тихо ? 0 : 0.55)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Картинка проявляется из размытия (при «Уменьшении движения» — сразу).
struct ПроявлениеИИФото: ViewModifier {
    @State private var видно = false
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения

    func body(content: Content) -> some View {
        let готово = видно || меньшеДвижения || ДвижениеСайта.тихо
        return content
            .opacity(готово ? 1 : 0)
            .blur(radius: готово ? 0 : 18)
            .scaleEffect(готово ? 1 : 1.03)
            .onAppear {
                guard !видно else { return }
                withAnimation(ДвижениеСайта.мягко(.easeOut(duration: 0.7))) { видно = true }
            }
    }
}

// MARK: - Картинка ответа

/// Квадрат (иллюстрация) или кадр фото (правка) с плашкой; «Сравнить» — шторка «До / После».
struct КартинкаОтветаИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото
    let реплика: РепликаИИФото
    let картинка: UIImage
    @State private var сравнить = false

    init(модель: МодельЧатаИИФото, реплика: РепликаИИФото, картинка: UIImage) {
        self.модель = модель
        self.реплика = реплика
        self.картинка = картинка
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if сравнить, let до = реплика.до {
                ШторкаИИФото(до: до, после: картинка)
            } else {
                КадрИИФото(картинка: картинка, вид: реплика.вид)
            }
            if реплика.состояние == .готово { действия }
        }
    }

    private var действия: some View {
        ПотокЧипов(зазор: 8) {
            if реплика.взята {
                ОтметкаВзятоИИФото(текст: т("aim_in_listing"))
            } else if let плитка = модель.плиткаПравки, реплика.вид == "edited" {
                КнопкаЧатаИИФото(т("aim_replace"), значок: "arrow.triangle.2.circlepath", главная: true,
                                 занято: модель.берём) {
                    модель.взять(реплика.id, как: .заменить(плитка))
                }
                КнопкаЧатаИИФото(т("aim_add_new"), значок: "plus", занято: модель.берём) {
                    модель.взять(реплика.id, как: .новое)
                }
            } else {
                КнопкаЧатаИИФото(т("aim_take"), значок: "square.and.arrow.down", главная: true, занято: модель.берём) {
                    модель.взять(реплика.id, как: реплика.вид == "illustration" ? .обложка : .новое)
                }
            }
            КнопкаЧатаИИФото(т(реплика.вид == "edited" ? "aim_again" : "aim_other_cover"),
                             значок: "arrow.triangle.2.circlepath") {
                модель.ещёВариант(реплика.id)
            }
            .disabled(модель.идёт)
            КнопкаЧатаИИФото(т("aim_edit_this"), значок: "pencil") { модель.правитьЭту(реплика.id) }
                .disabled(модель.идёт)
            if реплика.до != nil {
                КнопкаЧатаИИФото(т(сравнить ? "aim_compare_off" : "aim_compare"), значок: "rectangle.split.2x1") {
                    withAnimation(ДвижениеСайта.смена) { сравнить.toggle() }
                }
            }
        }
    }
}

/// Кадр с плашкой «Иллюстрация ИИ» / «Изменено ИИ»; пропорции — картинки (иллюстрация — квадрат).
struct КадрИИФото: View {
    let картинка: UIImage
    let вид: String

    init(картинка: UIImage, вид: String) {
        self.картинка = картинка
        self.вид = вид
    }

    private var пропорция: CGFloat {
        let р = картинка.size
        guard р.width > 0, р.height > 0 else { return 1 }
        return max(0.5, min(1.8, р.width / р.height))
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        return Color.clear
            .aspectRatio(пропорция, contentMode: .fit)
            .overlay {
                Image(uiImage: картинка)
                    .resizable()
                    .scaledToFill()
            }
            .clipShape(форма)
            .overlay { форма.strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
            .overlay(alignment: .topLeading) {
                if !вид.isEmpty {
                    ПометкаИИФото(вид: вид, мелкая: false)
                        .padding(10)
                }
            }
            .modifier(ПроявлениеИИФото())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ПометкаИИФото.текст(вид))
            .accessibilityAddTraits(.isImage)
    }
}

/// Шторка «До / После»: слева от ручки — исходное фото, справа — правка. Тянуть пальцем; VoiceOver — вверх/вниз по 10 %.
struct ШторкаИИФото: View {
    let до: UIImage
    let после: UIImage
    @State private var доля: CGFloat = 0.5

    init(до: UIImage, после: UIImage) {
        self.до = до
        self.после = после
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    private var пропорция: CGFloat {
        let р = после.size
        guard р.width > 0, р.height > 0 else { return 1 }
        return max(0.5, min(1.8, р.width / р.height))
    }

    var body: some View {
        GeometryReader { место in
            let ш = место.size.width
            let в = место.size.height
            ZStack(alignment: .topLeading) {
                Image(uiImage: после)
                    .resizable()
                    .scaledToFill()
                    .frame(width: ш, height: в)
                    .clipped()
                Image(uiImage: до)
                    .resizable()
                    .scaledToFill()
                    .frame(width: ш, height: в)
                    .clipped()
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(0, ш * доля))
                    }
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 3, height: в)
                    .shadow(color: Color.black.opacity(0.35), radius: 3)
                    .position(x: ш * доля, y: в / 2)
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.зелёный2)
                    .frame(width: 38, height: 38)
                    .background(Color.white, in: Circle())
                    .shadow(color: Color.black.opacity(0.3), radius: 4, y: 2)
                    .position(x: ш * доля, y: в / 2)
                метка(т("aim_before"))
                    .position(x: 40, y: 22)
                метка(т("aim_after"))
                    .position(x: max(40, ш - 44), y: 22)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { жест in
                доля = min(1, max(0, жест.location.x / max(1, ш)))
            })
        }
        /* Шторка — про место на снимке, а не про текст: «До» всегда слева, и при арабском тоже. */
        .environment(\.layoutDirection, .leftToRight)
        .aspectRatio(пропорция, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(т("aim_compare_a11y"))
        .accessibilityValue(String(format: т("aim_compare_value"), Int((доля * 100).rounded())))
        .accessibilityHint(т("aim_compare_hint"))
        .accessibilityAdjustableAction { направление in
            switch направление {
            case .increment: доля = min(1, доля + 0.1)
            case .decrement: доля = max(0, доля - 0.1)
            @unknown default: break
            }
        }
    }

    private func метка(_ текст: String) -> some View {
        Text(текст)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.55), in: Capsule())
    }
}

// MARK: - Черновик

/// Богатая карточка черновика объявления (последняя в диалоге) и действия под ней.
struct КарточкаЧерновикаИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото
    let реплика: РепликаИИФото
    let черновик: ЧерновикИИФото
    @State private var описаниеЦеликом = false

    init(модель: МодельЧатаИИФото, реплика: РепликаИИФото, черновик: ЧерновикИИФото) {
        self.модель = модель
        self.реплика = реплика
        self.черновик = черновик
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    private func изменено(_ поле: String) -> Bool { реплика.изменено.contains(поле) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !реплика.текст.isEmpty {
                ПодписьИИФото(текст: реплика.текст, своимИИ: реплика.своимИИ)
            }
            карточка
            if реплика.состояние == .готово {
                действия
            }
            if let постер = реплика.постер {
                ПостерЧатаИИФото(модель: модель, реплика: реплика, постер: постер)
            }
        }
    }

    private var карточка: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            обложка
            VStack(alignment: .leading, spacing: 12) {
                шапка
                описание
                if !черновик.характеристики.isEmpty {
                    ХарактеристикиЧерновикаИИФото(черновик: черновик, изменены: изменено("specs"))
                }
                if let цена = черновик.цена {
                    строкаЦены(цена)
                }
            }
            .padding(14)
        }
        .background(КраскаПодачи.карточка, in: форма)
        .clipShape(форма)
        .overlay { форма.strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
        .shadow(color: КраскаПодачи.тень, radius: 8, y: 3)
    }

    @ViewBuilder
    private var обложка: some View {
        if let картинка = реплика.картинка {
            КадрИИФото(картинка: картинка, вид: реплика.вид.isEmpty ? "illustration" : реплика.вид)
                .padding(8)
        } else if реплика.состояние == .ждём && реплика.нуженРисунок {
            ЗаглушкаИИФото(прогресс: реплика.прогресс, подпись: ЗаглушкаИИФото.подписьЭтапа(реплика), квадрат: true)
                .padding(8)
        }
    }

    private var шапка: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(черновик.название.isEmpty ? "—" : черновик.название)
                .font(.title3.weight(.heavy))
                .foregroundStyle(КраскаПодачи.текст)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(МеткаИзмененияИИФото(есть: изменено("title")))
                .accessibilityAddTraits(.isHeader)
            ПотокЧипов(зазор: 6) {
                let раздел = модель.подача.справочники.имя(черновик.раздел)
                if !раздел.isEmpty {
                    чип(раздел, значок: "square.grid.2x2", изменён: изменено("category"))
                }
                if !черновик.состояние.isEmpty {
                    чип(т(черновик.состояние == "new" ? "aim_cond_new" : "aim_cond_used"), значок: "sparkle",
                        изменён: изменено("cond"))
                }
                if !черновик.марка.isEmpty {
                    чип(черновик.марка, значок: "tag", изменён: изменено("brand"))
                }
            }
        }
    }

    private func чип(_ текст: String, значок: String, изменён: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: значок)
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
            Text(текст)
                .font(.caption.weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(изменён ? КраскаПодачи.хорошоТекст : КраскаПодачи.текст)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(изменён ? КраскаПодачи.хорошоФон : КраскаПодачи.поле, in: Capsule())
    }

    @ViewBuilder
    private var описание: some View {
        if !черновик.описание.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(черновик.описание)
                    .font(.subheadline)
                    .foregroundStyle(КраскаПодачи.текст)
                    .lineLimit(описаниеЦеликом ? nil : 6)
                    .fixedSize(horizontal: false, vertical: true)
                    .modifier(МеткаИзмененияИИФото(есть: изменено("description")))
                if черновик.описание.count > 280 {
                    Button(т(описаниеЦеликом ? "aim_less" : "aim_more_text")) {
                        withAnimation(ДвижениеСайта.смена) { описаниеЦеликом.toggle() }
                    }
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                }
            }
        }
    }

    /// «Цена: 280 000 – 380 000 ₸» и откуда она: похожие объявления Kliko, оценка Kliko AI или ваш ИИ.
    private func строкаЦены(_ цена: ЦенаИИФото) -> some View {
        let низ = цена.низ > 0 ? цена.низ : цена.середина
        let верх = цена.верх > 0 ? цена.верх : цена.середина
        let диапазон = низ == верх ? ПодачаМодель.деньги(низ) : ПодачаМодель.деньги(низ) + " – " + ПодачаМодель.деньги(верх)
        let откуда = цена.рынок ? т("aim_price_market") : (реплика.своимИИ ? т("aim_price_own") : т("aim_price_ai"))
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: т("aim_price"), диапазон + " ₸"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(КраскаПодачи.текст)
                Text(откуда + " · " + т("aim_price_hint"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .modifier(МеткаИзмененияИИФото(есть: изменено("price_hint")))
        .accessibilityElement(children: .combine)
    }

    private var действия: some View {
        VStack(alignment: .leading, spacing: 8) {
            ЗелёнаяКнопкаФото(заголовок: т("aim_create"), значок: "checkmark.seal.fill") {
                модель.создатьОбъявление(реплика.id)
            }
            .disabled(модель.берём || модель.идёт)
            .opacity(модель.берём || модель.идёт ? 0.6 : 1)
            ПотокЧипов(зазор: 8) {
                КнопкаЧатаИИФото(т("aim_change"), значок: "pencil") { модель.вПоле += 1 }
                if реплика.картинка != nil {
                    КнопкаЧатаИИФото(т("aim_other_cover"), значок: "arrow.triangle.2.circlepath") {
                        модель.ещёВариант(реплика.id)
                    }
                    .disabled(модель.идёт)
                    if !реплика.взята {
                        КнопкаЧатаИИФото(т("aim_take_cover"), значок: "square.and.arrow.down", занято: модель.берём) {
                            модель.взять(реплика.id, как: .обложка)
                        }
                    }
                }
            }
            if реплика.взята {
                ОтметкаВзятоИИФото(текст: т("aim_cover_in_listing"))
            }
        }
    }
}

/// Характеристики черновика: подпись — значение; сомнительные (unsure) — с «?» и «проверьте».
struct ХарактеристикиЧерновикаИИФото: View {
    let черновик: ЧерновикИИФото
    let изменены: Bool

    init(черновик: ЧерновикИИФото, изменены: Bool) {
        self.черновик = черновик
        self.изменены = изменены
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(т("aim_specs"))
                .font(.footnote.weight(.heavy))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(черновик.характеристики.enumerated()), id: \.offset) { номер, х in
                    строка(х)
                    if номер < черновик.характеристики.count - 1 {
                        Divider().overlay(КраскаПодачи.линия)
                    }
                }
            }
            .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .modifier(МеткаИзмененияИИФото(есть: изменены))
            if черновик.характеристики.contains(where: { черновик.неуверенные.contains($0.ключ) }) {
                Label(т("aim_unsure_note"), systemImage: "questionmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(КраскаПодачи.вниманиеТекст)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func строка(_ х: ХарактеристикаИИФото) -> some View {
        let сомнение = черновик.неуверенные.contains(х.ключ)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(х.подпись)
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 8)
            Text(х.значение)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(КраскаПодачи.текст)
                .multilineTextAlignment(.trailing)
            if сомнение {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(Theme.оранжевый)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(сомнение ? КраскаПодачи.вниманиеФон : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityValue(сомнение ? т("aim_unsure_a11y") : "")
    }
}

/// Изменённое в этом ходе — тонкая зелёная полоса слева (changed из status).
struct МеткаИзмененияИИФото: ViewModifier {
    let есть: Bool

    func body(content: Content) -> some View {
        content
            .padding(.leading, есть ? 8 : 0)
            .overlay(alignment: .leading) {
                if есть {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.зелёный2)
                        .frame(width: 3)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityHint(есть ? ИИФотоText.т("aim_changed_a11y") : "")
    }
}

/// Постер-оформление, собранный на телефоне: превью и «Взять постер в объявление».
struct ПостерЧатаИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото
    let реплика: РепликаИИФото
    let постер: UIImage

    init(модель: МодельЧатаИИФото, реплика: РепликаИИФото, постер: UIImage) {
        self.модель = модель
        self.реплика = реплика
        self.постер = постер
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(т("aim_poster_t"), systemImage: "rectangle.on.rectangle.angled")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(КраскаПодачи.текст)
                .accessibilityAddTraits(.isHeader)
            Text(т("aim_poster_s"))
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            КадрИИФото(картинка: постер, вид: "illustration")
                .frame(maxWidth: 300)
            if реплика.постерВзят {
                ОтметкаВзятоИИФото(текст: т("aim_poster_in_listing"))
            } else {
                КнопкаЧатаИИФото(т("aim_poster_take"), значок: "square.and.arrow.down", занято: модель.берём) {
                    модель.взять(реплика.id, постер: true, как: .новое)
                }
            }
        }
        .padding(12)
        .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
        }
    }
}

// MARK: - Отказ

struct ОтказЧатаИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото
    let реплика: РепликаИИФото
    let отказ: ОтказИИФото

    init(модель: МодельЧатаИИФото, реплика: РепликаИИФото, отказ: ОтказИИФото) {
        self.модель = модель
        self.реплика = реплика
        self.отказ = отказ
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    private var значок: String {
        switch отказ.код {
        case "limit": return "clock.badge.exclamationmark"
        case "net": return "wifi.exclamationmark"
        case "bad_prompt", "not_allowed": return "hand.raised.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: значок)
                    .foregroundStyle(Theme.оранжевый)
                    .accessibilityHidden(true)
                Text(отказ.текст)
                    .font(.subheadline)
                    .foregroundStyle(КраскаПодачи.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(КраскаПодачи.вниманиеФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(КраскаПодачи.вниманиеКромка, lineWidth: 1)
            }
            .accessibilityElement(children: .combine)
            ПотокЧипов(зазор: 8) {
                if реплика.продолжаемая {
                    КнопкаЧатаИИФото(т(отказ.код == "slow" ? "aim_check_again" : "aim_retry"), значок: "arrow.clockwise",
                                     главная: true) {
                        модель.продолжить(реплика.id)
                    }
                } else if отказ.повторить && реплика.повтор != nil {
                    КнопкаЧатаИИФото(т("aim_retry"), значок: "arrow.clockwise", главная: true) {
                        модель.повторить(реплика.id)
                    }
                }
                if отказ.другоеФото {
                    КнопкаЧатаИИФото(т("aim_other_photo"), значок: "photo") { модель.выбратьФото = true }
                }
                if отказ.заново {
                    КнопкаЧатаИИФото(т("aim_restart"), значок: "arrow.counterclockwise") { модель.начатьЗаново() }
                }
                if let свой = отказ.свойИИ {
                    КнопкаЧатаИИФото(т("aim_own_ai"), значок: "cpu") { ОкноСвоегоИИ.показатьОтказ(свой) }
                }
            }
        }
    }
}

// MARK: - Кнопки

/// Кнопка-капсула под ответом: главная — зелёная заливка, остальные — мятные; занята — колёсико.
struct КнопкаЧатаИИФото: View {
    let заголовок: String
    let значок: String
    var главная = false
    var занято = false
    let действие: () -> Void
    @Environment(\.isEnabled) private var доступна

    init(_ заголовок: String, значок: String, главная: Bool = false, занято: Bool = false,
         действие: @escaping () -> Void) {
        self.заголовок = заголовок
        self.значок = значок
        self.главная = главная
        self.занято = занято
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                if занято {
                    ProgressView()
                        .controlSize(.small)
                        .tint(главная ? Color.white : Theme.зелёный2)
                } else {
                    Image(systemName: значок)
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(заголовок)
                    .font(.footnote.weight(.bold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .foregroundStyle(главная ? Color.white : КраскаПодачи.хорошоТекст)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 36)
            .background(главная ? AnyShapeStyle(Theme.зелёный2) : AnyShapeStyle(КраскаПодачи.хорошоФон), in: Capsule())
            .opacity(доступна ? 1 : 0.5)
            .contentShape(Capsule())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
        .disabled(занято)
    }
}

/// «В объявлении ✓» вместо кнопки, когда картинку уже взяли.
struct ОтметкаВзятоИИФото: View {
    let текст: String

    init(текст: String) {
        self.текст = текст
    }

    var body: some View {
        Label(текст, systemImage: "checkmark.circle.fill")
            .font(.footnote.weight(.bold))
            .foregroundStyle(КраскаПодачи.хорошоТекст)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 36)
            .background(КраскаПодачи.хорошоФон, in: Capsule())
    }
}

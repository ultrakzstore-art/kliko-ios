import SwiftUI
import UIKit
import ImageIO

/**
 3D-ОБЗОР — ЭКРАН «360°» (Listing3DModel.swift): модели ещё нет (или не вышла), а ракурсы-вырезки есть.

 Пять кадров продавца без фона (спереди → 45° спереди-слева → сбоку → 45° сзади-слева → сзади) — на чистом фоне
 экрана с мягкой тенью-пятном под вещью. Палец по горизонтали плавно листает ракурсы с перекрёстным растворением и лёгким
 сдвигом кадров навстречу друг другу — похоже на поворот вещи. Отпустили — вещь докатывается по инерции до ближайшего
 ракурса (дальше — чем резче бросок). Палец вправо — следующий ракурс: передняя сторона уходит вправо, как у модели в
 «3D»; поворот физический и в RTL не зеркалится (точки ракурсов внизу — тоже слева направо, чтобы шли за пальцем).
 Крайние ракурсы — упор: съёмка — половина круга, без выдуманных зеркальных сторон.

 «Уменьшение движения»: без инерции и сдвига — только растворение к ближайшему ракурсу. Лёгкий режим — кадры меньше
 (900 px по длинной стороне вместо 1500). Ракурсов больше пяти (разбор берёт до 12) — сторона кадра меньше, чтобы все
 кадры вместе остались в том же бюджете памяти. Докат по инерции идёт по кадрам экрана (TimelineView): позиция — от
 времени кадра, а не шагами сна. VoiceOver: обзор — один элемент «Обзор 360°» со значением «Сбоку, ракурс 3 из 5»;
 смахивание вверх/вниз — соседний ракурс. Подсказка «Ведите пальцем» — до первого касания.

 Кадры качаются через тот же кэш на диске (КэшОбъёма), не больше трёх сразу, полоса показывает «2 из 5». Не загрузился
 один — обзор из остальных (если их хотя бы два), не загрузилось меньше двух — «Не удалось загрузить обзор» и
 «Повторить».
 */
struct ПросмотрОбзора360: View {
    let модель: МодельОбъёмаОбъявления
    let лёгкий: Bool
    @State private var кадры: [UIImage] = []
    /// Номер каждого кадра в model3d.angles — по нему подпись ракурса, если какой-то не загрузился.
    @State private var номера: [Int] = []
    @State private var загружено = 0
    @State private var ошибка = false
    @State private var попытка = 0
    /// Где мы между ракурсами: 0 — первый, 1,5 — между вторым и третьим.
    @State private var позиция: Double = 0
    @State private var начало: Double? = nil
    @State private var трогали = false
    /// Докатывание после броска (инерция) — новое касание его останавливает. позиция уже равна цели, экран рисует
    /// докат по времени кадра.
    @State private var докат: Докат? = nil
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @Environment(\.colorScheme) private var схема

    init(модель: МодельОбъёмаОбъявления, лёгкий: Bool) {
        self.модель = модель
        self.лёгкий = лёгкий
    }

    private func т(_ ключ: String) -> String { ОбъёмText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    private var последний: Double { Double(max(0, кадры.count - 1)) }

    /// Ближайший к экрану кадр.
    private var текущий: Int { min(max(Int(позиция.rounded()), 0), max(0, кадры.count - 1)) }

    var body: some View {
        Group {
            if кадры.count >= 2 {
                обзор
                    .transition(.opacity)
            } else if ошибка {
                ОшибкаОбъёма(заголовок: т("o3_error_360")) {
                    ошибка = false
                    загружено = 0
                    попытка += 1
                }
            } else {
                ЗагрузкаОбъёма(постер: модель.постер, доля: доляЗагрузки, текст: т("o3_loading_360"),
                               подпись: String(format: т("o3_of"), String(загружено), String(модель.ракурсы.count)))
            }
        }
        .animation(ДвижениеСайта.смена, value: кадры.count >= 2)
        .task(id: попытка) { await загрузить() }
        .task(id: докат) { await закончитьДокат() }
        .onDisappear { докат = nil }
    }

    /// Докат: откуда, куда, когда начался и сколько длится; позиция на экране — функция времени (ease-out).
    private struct Докат: Equatable {
        let откуда: Double
        let цель: Double
        let старт: Date
        let длительность: Double

        func позиция(_ момент: Date) -> Double {
            let прошло = min(1, max(0, момент.timeIntervalSince(старт) / длительность))
            let плавно = 1 - pow(1 - прошло, 3)
            return откуда + (цель - откуда) * плавно
        }
    }

    /// Где вещь на экране сейчас: в докате — по времени, иначе — позиция.
    private func видимая(_ момент: Date) -> Double {
        докат?.позиция(момент) ?? позиция
    }

    /// Докат дошёл — экран больше не перерисовывается каждый кадр (TimelineView на паузе).
    private func закончитьДокат() async {
        guard let д = докат else { return }
        try? await Task.sleep(nanoseconds: UInt64(max(0, д.длительность) * 1_000_000_000) + 20_000_000)
        guard !Task.isCancelled, докат == д else { return }
        докат = nil
    }

    private var доляЗагрузки: Double? {
        let всего = модель.ракурсы.count
        return всего > 0 ? Double(загружено) / Double(всего) : nil
    }

    // MARK: Обзор

    private var обзор: some View {
        GeometryReader { место in
            let шаг = max(36, Double(место.size.width) / 5)
            TimelineView(.animation(minimumInterval: nil, paused: докат == nil)) { кадрЭкрана in
                сцена(ширина: место.size.width, позиция: видимая(кадрЭкрана.date))
            }
            .contentShape(Rectangle())
            .gesture(тяга(шаг: шаг))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(т("o3_spin_a11y"))
            .accessibilityValue(подписьРакурса(текущий, полная: true))
            .accessibilityHint(т("o3_spin_hint"))
            .accessibilityAdjustableAction { направление in
                switch направление {
                case .increment: перейти(к: текущий + 1)
                case .decrement: перейти(к: текущий - 1)
                @unknown default: break
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { низ }
        .откликВыбора(текущий)
    }

    /// Два соседних кадра: нижний гаснет, верхний проявляется; оба чуть едут навстречу (при «Уменьшении движения» — нет).
    private func сцена(ширина: CGFloat, позиция: Double) -> some View {
        let п = min(max(позиция, 0), последний)
        let нижний = min(Int(п.rounded(.down)), max(0, кадры.count - 1))
        let доля = п - Double(нижний)
        let верхний = min(нижний + 1, max(0, кадры.count - 1))
        let сдвиг: CGFloat = тихо ? 0 : min(14, ширина * 0.035)
        return ZStack(alignment: .bottom) {
            тень(ширина: ширина)
            ZStack {
                кадр(нижний)
                    .opacity(1 - доля)
                    .offset(x: CGFloat(доля) * сдвиг)
                if верхний != нижний && доля > 0.001 {
                    кадр(верхний)
                        .opacity(доля)
                        .offset(x: -CGFloat(1 - доля) * сдвиг)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func кадр(_ номер: Int) -> some View {
        Image(uiImage: кадры[номер])
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Мягкое пятно тени под вещью — круг с размытым краем, сплющенный по высоте (без blur: дёшево и в лёгком режиме).
    private func тень(ширина: CGFloat) -> some View {
        let радиус = ширина * 0.34
        return Circle()
            .fill(RadialGradient(colors: [Color.black.opacity(схема == .dark ? 0.42 : 0.16), Color.black.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: радиус))
            .frame(width: радиус * 2, height: радиус * 2)
            .scaleEffect(x: 1, y: 0.14, anchor: .center)
            .frame(height: радиус * 0.3)
            .padding(.bottom, 14)
            .accessibilityHidden(true)
    }

    // MARK: Палец

    private func тяга(шаг: Double) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { з in
                if начало == nil {
                    /* Касание посреди доката — вещь останавливается там, где она на экране сейчас. */
                    let сейчас = видимая(Date())
                    докат = nil
                    позиция = сейчас
                    начало = сейчас
                    if !трогали {
                        withAnimation(ДвижениеСайта.появление) { трогали = true }
                    }
                }
                позиция = min(max((начало ?? 0) + Double(з.translation.width) / шаг, 0), последний)
            }
            .onEnded { з in
                let откуда = начало ?? позиция
                начало = nil
                let бросок = откуда + Double(з.predictedEndTranslation.width) / шаг
                let цель = min(max((тихо ? позиция : бросок).rounded(), 0), последний)
                let путь = abs(цель - позиция)
                доехать(до: цель, за: тихо ? 0.15 : min(0.9, 0.25 + 0.12 * путь))
            }
    }

    /// Соседний ракурс (VoiceOver, точки внизу).
    private func перейти(к номер: Int) {
        let цель = Double(min(max(номер, 0), max(0, кадры.count - 1)))
        if !трогали { трогали = true }
        доехать(до: цель, за: тихо ? 0.15 : 0.35)
    }

    /// Плавно до цели: замедляясь к концу (ease-out), кадр за кадром экрана — растворение идёт через все промежуточные
    /// ракурсы. позиция (точки, подпись, VoiceOver) — сразу цель; сцена рисует докат по времени кадра.
    private func доехать(до цель: Double, за длительность: Double) {
        let откуда = видимая(Date())
        guard длительность > 0, abs(цель - откуда) > 0.001 else {
            докат = nil
            позиция = цель
            return
        }
        докат = Докат(откуда: откуда, цель: цель, старт: Date(), длительность: длительность)
        позиция = цель
    }

    // MARK: Низ

    private var низ: some View {
        VStack(spacing: 8) {
            if !трогали {
                ПодсказкаОбъёма(значок: "hand.draw", текст: т("o3_hint_360"))
                    .transition(.opacity)
            }
            Text(подписьРакурса(текущий, полная: false))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .accessibilityHidden(true)
            точки
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Точки ракурсов: текущая — длинная зелёная; нажатие — к этому ракурсу. Слева направо и в RTL — как идёт палец.
    private var точки: some View {
        HStack(spacing: 2) {
            ForEach(0..<кадры.count, id: \.self) { номер in
                Button { перейти(к: номер) } label: {
                    Capsule()
                        .fill(номер == текущий ? Theme.акцент : Theme.линия)
                        .frame(width: номер == текущий ? 18 : 8, height: 8)
                        .frame(minWidth: 26, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .animation(ДвижениеСайта.выбор, value: текущий)
        .accessibilityHidden(true)
    }

    /// «Сбоку» (пять ракурсов по договору) или «Ракурс 3 из 5»; полная — для VoiceOver: имя и номер.
    private func подписьРакурса(_ место: Int, полная: Bool) -> String {
        guard место >= 0, место < номера.count else { return "" }
        let номер = String(место + 1)
        let всего = String(кадры.count)
        let поНомеру = String(format: т("o3_angle"), номер, всего)
        let имена = ["o3_a_front", "o3_a_fl", "o3_a_side", "o3_a_rl", "o3_a_rear"]
        guard модель.ракурсы.count == имена.count, номера[место] < имена.count else { return поНомеру }
        let имя = т(имена[номера[место]])
        return полная ? имя + ", " + поНомеру : имя
    }

    // MARK: Загрузка

    private func загрузить() async {
        /* Экран снова на виду — кадры уже есть. */
        guard кадры.count < 2 else { return }
        let адреса = Array(модель.ракурсы.prefix(МодельОбъёмаОбъявления.пределРакурсов))
        /* Бюджет памяти — как у пяти кадров: ракурсов больше — каждый меньше (но не мельче 600 px). */
        let база = лёгкий ? 900 : 1500
        let сторона = адреса.count > 5 ? max(600, база * 5 / адреса.count) : база
        загружено = 0
        var итог: [Int: UIImage] = [:]
        let открытьКадр: @Sendable (Int, URL) async -> (Int, ЯщикКартинкиОбъёма?) = { номер, адрес in
            guard let файл = try? await КэшОбъёма.shared.файл(адрес, прогресс: nil) else { return (номер, nil) }
            return (номер, КартинкиОбъёма.открыть(файл, сторона: сторона))
        }
        await withTaskGroup(of: (Int, ЯщикКартинкиОбъёма?).self) { группа in
            /* Не больше трёх сразу: пик памяти — три разжатых кадра, а не все. */
            var следующий = 0
            while следующий < min(3, адреса.count) {
                let номер = следующий
                let адрес = адреса[номер]
                группа.addTask { await открытьКадр(номер, адрес) }
                следующий += 1
            }
            while let готово = await группа.next() {
                if let ящик = готово.1 { итог[готово.0] = ящик.картинка }
                загружено += 1
                if следующий < адреса.count {
                    let номер = следующий
                    let адрес = адреса[номер]
                    группа.addTask { await открытьКадр(номер, адрес) }
                    следующий += 1
                }
            }
        }
        guard !Task.isCancelled else { return }
        let порядок = итог.keys.sorted()
        guard порядок.count >= 2 else {
            ошибка = true
            return
        }
        номера = порядок
        позиция = 0
        кадры = порядок.compactMap { итог[$0] }
    }
}

/// Картинка ракурса в «ящике»: из фоновой задачи на главную.
final class ЯщикКартинкиОбъёма: @unchecked Sendable {
    let картинка: UIImage

    init(_ картинка: UIImage) {
        self.картинка = картинка
    }
}

/// Открыть PNG ракурса уменьшенным (ImageIO, не на главной нити): длинная сторона — не больше `сторона` px.
enum КартинкиОбъёма {
    nonisolated static func открыть(_ файл: URL, сторона: Int) -> ЯщикКартинкиОбъёма? {
        let чтение = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let источник = CGImageSourceCreateWithURL(файл as CFURL, чтение) else { return nil }
        let параметры: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: сторона
        ]
        guard let картинка = CGImageSourceCreateThumbnailAtIndex(источник, 0, параметры as CFDictionary) else {
            return nil
        }
        return ЯщикКартинкиОбъёма(UIImage(cgImage: картинка))
    }
}

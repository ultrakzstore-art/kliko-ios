import SwiftUI

/**
 «ПРИМЕРИТЬ / ПРОВЕРИТЬ» — КНОПКИ НА СТРАНИЦЕ ОБЪЯВЛЕНИЯ И ОКНО ИИ-ПРИМЕРОЧНОЙ (владелец 13.10.2026: «примерочная для
 одежды» → «нужнее охват всего»).

 Одна точка входа для всех способов (хаб, TryOnHub.swift): страница объявления (СтраницаОбъявленияСайта,
 SiteListing.swift) спрашивает КнопкаПримерочной.есть(товар) и ставит КнопкаПримерочной(товар:номерФото:) под ценой и
 крошками. Кнопка сама решает по разделу, что показать (ПодборПримерки): один способ — большая зелёная кнопка во всю
 ширину, с подписью и бегущим бликом (при «Уменьшении движения» — без него); несколько — первый большой, остальные
 аккуратным рядом под ним (не влезают в строку — столбиком). Способы ИИ появляются, когда сервер ответил info как надо
 (ГотовностьПримерочной), — до этого их нет. Нажатие — окно способа поверх всего (ПоверхВсего).
 */
struct КнопкаПримерочной: View {
    let товар: Listing
    /// Фото галереи на экране — его и примеряем (photo_index); другое можно выбрать в окне.
    let номерФото: Int
    @ObservedObject private var готовность = ГотовностьПримерочной.shared
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @ScaledMetric(relativeTo: .body) private var круг: CGFloat = 42
    @State private var блик = false

    init(товар: Listing, номерФото: Int) {
        self.товар = товар
        self.номерФото = номерФото
    }

    /// Ставить ли кнопки на страницу вообще — без сети: есть ли у объявления хоть один способ (на телефоне — по
    /// рубильнику и разделу; ИИ — по рубильнику, разделу и фото, если сервер ещё не отказал). Сервер спрашивает уже сама
    /// кнопка.
    @MainActor
    static func есть(_ т: Listing) -> Bool {
        !ПодборПримерки.способы(т, подтверждённые: false).isEmpty
    }

    private func т(_ ключ: String) -> String { ХабПримеркиText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    /// Что можно нажать сейчас. Способы ИИ зависят от ответа сервера — потому готовность здесь наблюдается.
    private var способы: [СпособПримерки] {
        ПодборПримерки.способы(товар, подтверждённые: true)
    }

    /// Нужен ли ответ сервера: у объявления может быть способ ИИ.
    private var нуженСервер: Bool {
        ПодборПримерки.способы(товар, подтверждённые: false).contains { $0.наСервере }
    }

    var body: some View {
        let список = способы
        VStack(spacing: 0) {
            /* Полоса нулевой высоты: на ней живёт .task, пока кнопок ещё нет (пустой вид задач не запускает). */
            Color.clear
                .frame(height: 0)
                .accessibilityHidden(true)
            if let главный = список.first {
                VStack(spacing: 10) {
                    большая(главный)
                    if список.count > 1 {
                        ряд(Array(список.dropFirst()))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .transition(.opacity)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(т("th_group_a11y"))
            }
        }
        .animation(ДвижениеСайта.появление, value: список)
        .task(id: товар.id) {
            guard нуженСервер else { return }
            await готовность.проверить()
        }
    }

    private func открыть(_ способ: СпособПримерки) {
        ОткликСайта.выбор()
        ПодборПримерки.открыть(способ, товар: товар, номерФото: номерФото)
    }

    // MARK: Главная кнопка

    private func большая(_ способ: СпособПримерки) -> some View {
        Button { открыть(способ) } label: {
            HStack(spacing: 12) {
                Image(systemName: способ.значок(товар))
                    .font(.body.weight(.semibold))
                    .frame(width: круг, height: круг)
                    .background(Color.white.opacity(0.16), in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(способ.заголовокДля(товар))
                        .font(.callout.weight(.heavy))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(способ.подпись(товар))
                        .font(.footnote)
                        .opacity(0.86)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: способ.наСервере ? "sparkles" : "chevron.forward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.шапкаМята)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                LinearGradient(colors: [Theme.панельСвязиНачало, Theme.панельСвязиКонец],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .overlay { блеск }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .shadow(color: Theme.панельСвязиКонец.opacity(0.28), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: ДвижениеСайта.сжатие))
        .accessibilityLabel(способ.заголовокДля(товар))
        .accessibilityValue(способ.подпись(товар))
        .accessibilityHint(способ.подсказкаДля(товар))
        .task { await пробежатьБлик() }
    }

    /// Блик пробегает два раза и замирает за краем кнопки: бесконечная анимация держала бы перерисовку страницы
    /// объявления с частотой экрана, пока она открыта. Ушли со страницы — задача отменяется.
    private func пробежатьБлик() async {
        guard !тихо else { return }
        блик = false
        for проход in 0..<2 {
            try? await Task.sleep(nanoseconds: проход == 0 ? 800_000_000 : 1_400_000_000)
            if Task.isCancelled || тихо { return }
            withAnimation(.easeInOut(duration: 1.8)) { блик = true }
            try? await Task.sleep(nanoseconds: 1_900_000_000)
            if Task.isCancelled { return }
            /* Назад к началу — без анимации: полоса и там, и там за краем кнопки, скачка не видно. */
            блик = false
        }
    }

    /// Косая светлая полоса пробегает по кнопке от начала к концу строки — намёк, что здесь «волшебство».
    @ViewBuilder
    private var блеск: some View {
        if !тихо {
            GeometryReader { место in
                LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.26), Color.white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: место.size.width * 0.34, height: место.size.height * 2)
                    .rotationEffect(.degrees(16))
                    .offset(x: блик ? место.size.width * 1.15 : -место.size.width * 0.5, y: -место.size.height * 0.5)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: Остальные способы

    /// Остальные способы — в строку; не влезают (крупный шрифт, длинные подписи) — столбиком.
    private func ряд(_ список: [СпособПримерки]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(список) { способ in малая(способ) }
            }
            VStack(spacing: 10) {
                ForEach(список) { способ in малая(способ) }
            }
        }
    }

    private func малая(_ способ: СпособПримерки) -> some View {
        Button { открыть(способ) } label: {
            HStack(spacing: 8) {
                Image(systemName: способ.значок(товар))
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                Text(способ.заголовокДля(товар))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if способ.наСервере {
                    Image(systemName: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Theme.акцент)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.панельКромка, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: ДвижениеСайта.сжатие))
        .accessibilityLabel(способ.заголовокДля(товар))
        .accessibilityValue(способ.подпись(товар))
        .accessibilityHint(способ.подсказкаДля(товар))
    }
}

// MARK: - Окно ИИ-примерочной

@MainActor
enum ОкноПримерочной {
    /// Окно ИИ-примерочной во всю высоту поверх того, что на экране (страница объявления, лист продавца, iPad справа).
    /// вид — что рисует ИИ: человек в вещи, машина с дисками, комната с вещью.
    static func открыть(товар: Listing, номерФото: Int, вид: ВидИИПримерки = .человек) {
        guard Config.примерочная else { return }
        ПоверхВсего.показать(большой: true) { закрыть in
            ЭкранПримерочной(товар: товар, номерФото: номерФото, вид: вид, закрыть: закрыть)
        }
    }
}

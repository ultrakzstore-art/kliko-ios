import SwiftUI

/**
 «МОЁ» — «МОЙ КОМПЬЮТЕР»: БЛОК «МОЖНО УЛУЧШИТЬ» (docs/STANDARDS.md §6.5; логика — MyThingsPCUpgrade.swift).

 Карточка экрана: цель чипами (Учёба и работа · Игры · Монтаж и фото · Больше места · Быстрее включается), диагноз
 фактами со знаками ✓ / ⚠ / ✕, до трёх вариантов — «Так», «Или так», «Или по-крупному»: заголовок стандартом, польза,
 проверки построчно, «от N ₸ · M предложений» (нажимается — объявление), «Найти на Kliko» (обычный поиск по нажатию),
 «Продать старую» (мастер подачи), «Поставить: самим или у мастера» (раздел «Апгрейд ПК»); свёрнутая строка «Так нельзя»
 с причинами и всегда — «Можно ничего не менять». Цены грузятся не сразу (0,6 с — чтобы быстрый проход экрана не ходил в
 сеть) и с памятью на 10 минут; пока грузятся — тихая строка «Ищем на Kliko…». Без счётчиков, таймеров и «успейте».
 */
struct БлокАпгрейдаМоего: View {
    let компьютер: КомпьютерМоего
    let открытьТовар: (Listing) -> Void
    let найти: (String, String) -> Void
    let продать: (String) -> Void
    @State private var цель: ЦельАпгрейдаМоего
    @State private var подсказки = ПодсказкиКомпьютераМоего.пусто
    @State private var цены: [String: ЦенаВариантаМоего] = [:]
    @State private var грузим = false
    @State private var нельзяОткрыто = false

    init(компьютер: КомпьютерМоего, открытьТовар: @escaping (Listing) -> Void,
         найти: @escaping (String, String) -> Void, продать: @escaping (String) -> Void) {
        self.компьютер = компьютер
        self.открытьТовар = открытьТовар
        self.найти = найти
        self.продать = продать
        _цель = State(initialValue: компьютер.вид == .ноутбук ? .работа : .игры)
    }

    private func т(_ ключ: String) -> String { МойКомпьютерText.т(ключ) }

    /// Пересчёт — при смене компьютера или цели.
    private struct Ключ: Equatable {
        let компьютер: КомпьютерМоего
        let цель: ЦельАпгрейдаМоего
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ЗаголовокМоего(т("mpc_up_title"), значок: "wand.and.stars")
            цели
            диагноз
            варианты
            нельзя
            ничего
            Text(т("mpc_up_note"))
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
        .карточкаМоего()
        .animation(ДвижениеСайта.смена, value: подсказки)
        .animation(ДвижениеСайта.смена, value: цены)
        .task(id: Ключ(компьютер: компьютер, цель: цель)) {
            await пересчитать()
        }
    }

    // MARK: Цель и диагноз

    private var цели: some View {
        ПотокЧипов(зазор: 8) {
            ForEach(ЦельАпгрейдаМоего.allCases) { ц in
                ЧипМоего(ц.название, выбран: цель == ц, значок: ц.значок) {
                    ОткликСайта.выбор()
                    цель = ц
                }
            }
        }
    }

    @ViewBuilder
    private var диагноз: some View {
        if !подсказки.диагноз.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(подсказки.диагноз) { п in
                    СтрокаПроверкиАпгрейдаМоего(пункт: п, крупно: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .transition(.opacity)
        }
    }

    // MARK: Варианты

    @ViewBuilder
    private var варианты: some View {
        if подсказки.варианты.isEmpty {
            ЗаметкаКомпьютераМоего(т("mpc_up_empty"), значок: "info.circle")
        } else {
            ForEach(Array(подсказки.варианты.enumerated()), id: \.element.id) { номер, вариант in
                КарточкаВариантаАпгрейдаМоего(вариант: вариант, номер: номер, цена: цены[вариант.id], грузим: грузим,
                                              открытьТовар: открытьТовар, найти: найти, продать: продать)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var нельзя: some View {
        if !подсказки.нельзя.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    ОткликСайта.выбор()
                    withAnimation(ДвижениеСайта.смена) { нельзяОткрыто.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: УровеньСтандарта.неПодходит.значок)
                            .foregroundStyle(УровеньСтандарта.неПодходит.краска)
                        Text(String(format: т("mpc_up_cant_n"), String(подсказки.нельзя.count)))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.текст)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.текстВторой)
                            .rotationEffect(.degrees(нельзяОткрыто ? 180 : 0))
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеКнопкиФото(сжатие: 0.98))
                .accessibilityValue(нельзяОткрыто ? т("mpc_open") : т("mpc_closed"))
                if нельзяОткрыто {
                    ForEach(подсказки.нельзя) { вариант in
                        Text(вариант.заголовок + " — " + (вариант.причина ?? ""))
                            .font(.footnote)
                            .foregroundStyle(Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    private var ничего: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.title3)
                .foregroundStyle(Theme.акцент)
            VStack(alignment: .leading, spacing: 2) {
                Text(т("mpc_up_nothing"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                Text(т("mpc_up_nothing_sub"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Пересчёт и цены

    /// Варианты — сразу (чистые функции на телефоне); цены — после паузы, по разделам, с памятью на 10 минут.
    @MainActor
    private func пересчитать() async {
        let новые = ПодсказкиАпгрейдаМоего.подсказки(компьютер, цель: цель)
        if новые != подсказки { подсказки = новые }
        let компоненты = новые.варианты.flatMap(\.компоненты).filter { !$0.безЦены }
        let разделы = Array(Set(компоненты.map(\.раздел))).sorted()
        guard !разделы.isEmpty else {
            if !цены.isEmpty { цены = [:] }
            return
        }
        try? await Task.sleep(nanoseconds: 600_000_000)
        guard !Task.isCancelled else { return }
        грузим = true
        var загружено: [String: [ЦеныАпгрейдаМоего.Предложение]] = [:]
        for раздел in разделы {
            if let список = await ЦеныАпгрейдаМоего.shared.предложения(раздела: раздел) { загружено[раздел] = список }
            if Task.isCancelled {
                грузим = false
                return
            }
        }
        var итог: [String: ЦенаВариантаМоего] = [:]
        for вариант in новые.варианты {
            let свои = вариант.компоненты.filter { !$0.безЦены }
            guard !свои.isEmpty else { continue }
            var части: [ЦеныАпгрейдаМоего.ЦенаКомпонента] = []
            var сбой = false
            for компонент in свои {
                guard let список = загружено[компонент.раздел] else {
                    сбой = true
                    continue
                }
                части.append(ЦеныАпгрейдаМоего.цена(компонент, список))
            }
            итог[вариант.id] = ЦенаВариантаМоего(части: части, неЗагрузилось: сбой && части.isEmpty)
        }
        цены = итог
        грузим = false
    }
}

// MARK: - Строка проверки

/// «✓ DDR4 ✓», «⚠ БП 500 Вт — советуют от 550»: значок уровня его краской и текст; для VoiceOver — слово уровня.
struct СтрокаПроверкиАпгрейдаМоего: View {
    let пункт: ПунктСверкиСтандарта
    let крупно: Bool

    init(пункт: ПунктСверкиСтандарта, крупно: Bool = false) {
        self.пункт = пункт
        self.крупно = крупно
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: пункт.уровень.значок)
                .font(крупно ? .subheadline : .footnote)
                .foregroundStyle(пункт.уровень.краска)
            Text(пункт.текст)
                .font(крупно ? .subheadline : .footnote)
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(пункт.уровень.слово + ". " + пункт.текст)
    }
}

// MARK: - Карточка варианта

struct КарточкаВариантаАпгрейдаМоего: View {
    let вариант: ВариантАпгрейдаМоего
    let номер: Int
    let цена: ЦенаВариантаМоего?
    let грузим: Bool
    let открытьТовар: (Listing) -> Void
    let найти: (String, String) -> Void
    let продать: (String) -> Void

    init(вариант: ВариантАпгрейдаМоего, номер: Int, цена: ЦенаВариантаМоего?, грузим: Bool,
         открытьТовар: @escaping (Listing) -> Void, найти: @escaping (String, String) -> Void,
         продать: @escaping (String) -> Void) {
        self.вариант = вариант
        self.номер = номер
        self.цена = цена
        self.грузим = грузим
        self.открытьТовар = открытьТовар
        self.найти = найти
        self.продать = продать
    }

    private func т(_ ключ: String) -> String { МойКомпьютерText.т(ключ) }

    private var метка: String {
        switch номер {
        case 0: return т("mpc_up_a")
        case 1: return т("mpc_up_b")
        default: return т("mpc_up_c")
        }
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            шапка
            VStack(alignment: .leading, spacing: 3) {
                Text(вариант.заголовок)
                    .font(.headline)
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Text(вариант.польза)
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(вариант.пункты.enumerated()), id: \.offset) { _, пункт in
                    СтрокаПроверкиАпгрейдаМоего(пункт: пункт)
                }
            }
            ценаСтрока
            кнопки
            поставить
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: форма)
        .overlay { форма.strokeBorder(вариант.уровень.краска.opacity(0.35), lineWidth: 1) }
    }

    private var шапка: some View {
        HStack(spacing: 8) {
            Text(метка)
                .font(.caption.weight(.heavy))
                .textCase(.uppercase)
                .foregroundStyle(Theme.акцент)
            Spacer(minLength: 8)
            Image(systemName: вариант.уровень.значокИтога)
                .foregroundStyle(вариант.уровень.краска)
                .accessibilityLabel(вариант.уровень.слово)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Цена

    @ViewBuilder
    private var ценаСтрока: some View {
        if вариант.компоненты.contains(where: { !$0.безЦены }) {
            if let цена {
                if цена.неЗагрузилось {
                    Text(т("mpc_up_price_fail"))
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                } else if цена.части.count == 1, let часть = цена.части.first {
                    строкаЦены(часть, свояПодпись: false)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(цена.части.enumerated()), id: \.offset) { _, часть in
                            строкаЦены(часть, свояПодпись: true)
                        }
                        if let вместе = цена.вместе {
                            Text(String(format: т("mpc_up_together"), СделкиФормат.тенге(вместе)))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.текст)
                        }
                    }
                }
            } else if грузим {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(т("mpc_up_loading"))
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// «от 9 000 ₸ · 7 предложений ›» — нажимается; нет — «Пока нет на Kliko».
    @ViewBuilder
    private func строкаЦены(_ часть: ЦеныАпгрейдаМоего.ЦенаКомпонента, свояПодпись: Bool) -> some View {
        let приставка = свояПодпись ? часть.подпись + " — " : ""
        if let от = часть.от, let товар = часть.товар {
            Button {
                ОткликСайта.выбор()
                открытьТовар(товар)
            } label: {
                HStack(spacing: 6) {
                    Text(приставка + String(format: т("mpc_up_from"), СделкиФормат.тенге(от)))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.акцент)
                        .multilineTextAlignment(.leading)
                    Text("· " + String(format: т("mpc_up_offers"), String(часть.предложений)))
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                    Spacer(minLength: 4)
                    СтрелкаСтрокиКабинета()
                }
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.98))
            .accessibilityHint(т("mpc_up_open_hint"))
        } else {
            Text(приставка + т("mpc_up_none"))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Кнопки

    private var кнопки: some View {
        ПотокЧипов(зазор: 8) {
            if let первый = вариант.компоненты.first {
                МалаяКнопкаАвтоподбора(заголовок: т("mpc_up_find"), значок: "magnifyingglass") {
                    найти(первый.запрос, первый.раздел)
                }
            }
            if let старая = вариант.старая {
                МалаяКнопкаАвтоподбора(заголовок: т(вариант.продатьСвой ? "mpc_up_sell_own" : "mpc_up_sell_old"),
                                       значок: "tag") {
                    продать(старая)
                }
            }
        }
    }

    @ViewBuilder
    private var поставить: some View {
        if let ключ = вариант.поставить {
            Button {
                найти("", "pc-upgrade")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(Theme.акцент)
                    Text(т(ключ == "easy" ? "mpc_up_install_easy" : "mpc_up_install_pro"))
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    СтрелкаСтрокиКабинета()
                }
                .frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.98))
            .accessibilityHint(т("mpc_up_masters_hint"))
        }
    }
}

import SwiftUI

/**
 БЛОК «РАЗМЕР» В ПОДАЧЕ ОДЕЖДЫ И ОБУВИ — «КАК НА БИРКЕ МАГАЗИНА» (таблицы и правила — ClothingSizes.swift).

 Сверху вкладки таблиц (у обуви «Женская / Мужская / Детская», у одежды «Одежда / Джинсы / Бельё»), под ними
 переключатель системы (только те, что есть у таблицы: EU · RU · US · UK · MEX · INT · см), ровная сетка чипов одной
 высоты в выбранной системе, у джинсов — ещё длина L, у белья — чашка. Ниже — «бирка»: крупно выбранная система, строкой
 все системы, как на ярлыке, мерки тела по таблице и мелкая оговорка «у брендов бывает ±½ размера»; под ней — что ушло
 в поле объявления (меню, чтобы поправить) и есть ли строка в описании.

 Движение лёгкое, «летает на XR»: сетка — стопка HStack без GeometryReader и ленивых сеток, выбранный чип — одна
 заливка, которая перелетает (matchedGeometryEffect), бирка мягко перестраивается (contentTransition(.numericText()))
 и чуть подпрыгивает (phaseAnimator), под пальцем — лёгкий отклик (.impact(weight: .light)). «Уменьшение движения» — без
 полёта и прыжка (ДвижениеСайта.мягко, accessibilityReduceMotion).
 */
struct БлокРазмераПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    let набор: НаборРазмеровОдежды

    init(модель: ПодачаМодель, набор: НаборРазмеровОдежды) {
        self.модель = модель
        self.набор = набор
    }

    var body: some View {
        let поле = модель.полеРазмераОдежды
        /* Метка прокрутки к ошибке — как у ячейки поля схемы («sp_storage»); без поля — своя, чтобы не было двух. */
        VStack(spacing: 0) {
            ПанельРазмераОдежды(модель: модель, набор: набор, поле: поле)
                .id(набор.ключ)
        }
        .id(поле == nil ? "cz_size" : "sp_" + ПравилаРазмераОдежды.слот)
    }
}

/// Состояние блока: вкладка, система каждой вкладки, выбор. Новый раздел — новое состояние (.id(набор.ключ)).
private struct ПанельРазмераОдежды: View {
    @ObservedObject var модель: ПодачаМодель
    let набор: НаборРазмеровОдежды
    let поле: ПолеХарактеристики?

    @State private var вкладка: String
    @State private var системы: [String: String] = [:]
    @State private var выбор: ВыборРазмераОдежды? = nil
    @State private var толчок = 0
    @State private var восстановлено = false
    @Namespace private var пространство

    init(модель: ПодачаМодель, набор: НаборРазмеровОдежды, поле: ПолеХарактеристики?) {
        self.модель = модель
        self.набор = набор
        self.поле = поле
        _вкладка = State(initialValue: набор.начальная)
    }

    private func т(_ ключ: String) -> String { РазмерыОдеждыText.т(ключ) }

    /// Пружина выбора: короткая, с лёгким перелётом; при «Уменьшении движения» — nil.
    private var пружина: Animation? { ДвижениеСайта.мягко(.spring(response: 0.34, dampingFraction: 0.74)) }

    private var текущая: ВкладкаРазмеровОдежды { набор.вкладка(вкладка) ?? набор.вкладки[0] }

    private func система(_ в: ВкладкаРазмеровОдежды) -> СистемаРазмераОдежды {
        let код = системы[в.ключ] ?? в.системаПоля(поле)
        return в.система(код) ?? в.системы[0]
    }

    var body: some View {
        let в = текущая
        let с = система(в)
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            шапка
            if набор.вкладки.count > 1 { полосаВкладок }
            if в.системы.count > 1 { полосаСистем(в, с) }
            сетка(в, с)
            бирка(в, с)
            if поле != nil { СтрокаОшибки(модель.ошибка("sp_" + ПравилаРазмераОдежды.слот)) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(КраскаПодачи.карточка, in: форма)
        .overlay { форма.strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
        .sensoryFeedback(.impact(weight: .light), trigger: толчок)
        .откликВыбора(системы)
        .откликВыбора(вкладка)
        .onAppear(perform: восстановить)
    }

    // MARK: Шапка

    /// Значок бирки в мятном квадрате, «Размер» (подпись поля сайта) · обязательно / необязательно, пояснение.
    private var шапка: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "tag")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.акцент)
                .frame(width: 33, height: 33)
                .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(поле?.подпись ?? т("title"))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(КраскаПодачи.текст)
                    if поле?.обязательно == true {
                        Text("*")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(КраскаПодачи.плохоТекст)
                    } else {
                        Text("· " + ПодачаText.т("form_optional"))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
                Text(т("sub"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: Вкладки и системы

    private var полосаВкладок: some View {
        ПолосаВыбораРазмера(варианты: набор.вкладки.map { ВариантПоля(ключ: $0.ключ, подпись: т("t_" + $0.ключ)) },
                            выбрано: вкладка, высота: 36, пространство: пространство, метка: "tab") { ключ in
            сменитьВкладку(ключ)
        }
    }

    private func полосаСистем(_ в: ВкладкаРазмеровОдежды, _ с: СистемаРазмераОдежды) -> some View {
        ПолосаВыбораРазмера(варианты: в.системы.map { ВариантПоля(ключ: $0.код, подпись: РазмерыОдеждыText.система($0.код)) },
                            выбрано: с.код, высота: 30, пространство: пространство, метка: "sys") { код in
            withAnimation(пружина) { системы[в.ключ] = код }
            /* Размер выбран в этой вкладке — его система уходит в size_sys (владелец 17.10.2026). */
            if выбор?.вкладка == в.ключ && модель.форма.системаРазмера != код { модель.форма.системаРазмера = код }
        }
    }

    // MARK: Сетка

    /// Чипы основной таблицы в выбранной системе; у джинсов и белья — подпись и вторая сетка (длина L, чашка).
    private func сетка(_ в: ВкладкаРазмеровОдежды, _ с: СистемаРазмераОдежды) -> some View {
        let мой = выбор?.вкладка == в.ключ ? выбор : nil
        return VStack(alignment: .leading, spacing: 10) {
            if в.склейка != .нет {
                ПодписьПоля(т(в.склейка == .джинсы ? "waist" : "band"), мелкая: true)
            }
            СеткаЧиповРазмера(чипы: в.основная.чипы(с.первый), выбранныйРяд: мой?.ряд,
                              код: РазмерыОдеждыText.система(с.код), системаКод: с.код,
                              пространство: пространство, метка: "a") { чип in
                выбрать(чип, в)
            }
            if let вторая = в.вторая {
                ПодписьПоля(т(в.склейка == .джинсы ? "length" : "cup"), необязательно: true, мелкая: true)
                    .padding(.top, 2)
                СеткаЧиповРазмера(чипы: вторая.чипы(с.второй ?? 0), выбранныйРяд: мой?.ряд2,
                                  код: "", системаКод: "", пространство: пространство, метка: "b") { чип in
                    выбратьВторой(чип, в)
                }
                .opacity(мой == nil ? 0.45 : 1)
                .disabled(мой == nil)
                if мой == nil { ПодсказкаПоля(т("first_main")) }
            }
        }
    }

    // MARK: Бирка

    @ViewBuilder
    private func бирка(_ в: ВкладкаРазмеровОдежды, _ с: СистемаРазмераОдежды) -> some View {
        if let выбор, let своя = набор.вкладка(выбор.вкладка) {
            let код = выбор.вкладка == в.ключ ? с.код : система(своя).код
            БиркаРазмера(своя.бирка(выбор, система: код), толчок: толчок, сброс: сбросить) {
                низБирки(своя, выбор)
            }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        } else {
            ПустаяБиркаРазмера()
                .transition(.opacity)
        }
    }

    /// Под биркой: что ушло в поле объявления (меню — поправить) и есть ли строка в описании (нет — кнопка).
    private func низБирки(_ в: ВкладкаРазмеровОдежды, _ выбор: ВыборРазмераОдежды) -> some View {
        let строка = в.строкаОписания(выбор)
        let вОписании = модель.форма.описание.contains(строка)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                значениеПоля
                Spacer(minLength: 4)
                состояниеОписания(вОписании, в, выбор)
            }
            VStack(alignment: .leading, spacing: 8) {
                значениеПоля
                состояниеОписания(вОписании, в, выбор)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var значениеПоля: some View {
        if let поле {
            let сейчас = модель.значениеХарактеристики(поле.поле)
            let показ = поле.вариантыСПодписью.first(where: { $0.ключ == сейчас })?.подпись ?? сейчас
            if поле.вводом {
                ПлашкаПоляРазмера(подпись: т("in_listing"), значение: показ.isEmpty ? т("unset") : показ,
                                  пусто: показ.isEmpty, стрелка: false)
            } else {
                Menu {
                    Button(ПодачаText.т("spec_unset")) { задатьПоле("") }
                    ForEach(поле.вариантыСПодписью, id: \.self) { вариант in
                        Button {
                            задатьПоле(вариант.ключ)
                        } label: {
                            if вариант.ключ == сейчас {
                                Label(вариант.подпись, systemImage: "checkmark")
                            } else {
                                Text(вариант.подпись)
                            }
                        }
                    }
                } label: {
                    ПлашкаПоляРазмера(подпись: т("in_listing"), значение: показ.isEmpty ? т("unset") : показ,
                                      пусто: показ.isEmpty, стрелка: true)
                }
                .accessibilityLabel(т("in_listing"))
                .accessibilityValue(показ.isEmpty ? т("unset") : показ)
            }
        }
    }

    @ViewBuilder
    private func состояниеОписания(_ есть: Bool, _ в: ВкладкаРазмеровОдежды, _ выбор: ВыборРазмераОдежды) -> some View {
        if есть {
            Label(т("in_desc"), systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .lineLimit(1)
        } else {
            Button {
                толчок += 1
                записать(выбор, в)
            } label: {
                Label(т("to_desc"), systemImage: "plus.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(КраскаПодачи.акцентТекст)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Theme.оттенокАкцента, in: Capsule())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        }
    }

    // MARK: Действия

    private func выбрать(_ чип: ЧипРазмераОдежды, _ в: ВкладкаРазмеровОдежды) {
        var новый = ВыборРазмераОдежды(вкладка: в.ключ, ряд: чип.id, ряд2: nil)
        if let был = выбор, был.вкладка == в.ключ {
            /* Тот же размер (US W 6.5 стоит в двух рядах) — ряд прежний; длина и чашка остаются. */
            if чип.ряды.contains(был.ряд) { новый.ряд = был.ряд }
            новый.ряд2 = был.ряд2
        }
        применить(новый, в)
    }

    private func выбратьВторой(_ чип: ЧипРазмераОдежды, _ в: ВкладкаРазмеровОдежды) {
        guard var был = выбор, был.вкладка == в.ключ else { return }
        /* Длина и чашка — по желанию: второе нажатие снимает. */
        if let ряд2 = был.ряд2, чип.ряды.contains(ряд2) {
            был.ряд2 = nil
        } else {
            был.ряд2 = чип.id
        }
        применить(был, в)
    }

    private func применить(_ новый: ВыборРазмераОдежды, _ в: ВкладкаРазмеровОдежды) {
        withAnimation(пружина) { выбор = новый }
        толчок += 1
        записать(новый, в)
    }

    /// Поле сайта и строка описания — одной записью формы (один didSet, один черновик).
    private func записать(_ новый: ВыборРазмераОдежды?, _ в: ВкладкаРазмеровОдежды?) {
        var ф = модель.форма
        if let новый, let в {
            ф.описание = ПравилаРазмераОдежды.сСтрокой(ф.описание, в.строкаОписания(новый))
            if let поле {
                ф.storage = ПравилаРазмераОдежды.значениеПоля(в, новый, поле) ?? ""
            }
            /* size_sys — система, в которой продавец выбирал (docs/SERVER_SIZES.md §2.2). */
            ф.системаРазмера = система(в).код
        } else {
            ф.описание = ПравилаРазмераОдежды.безСтроки(ф.описание)
            if поле != nil { ф.storage = "" }
            ф.системаРазмера = nil
        }
        if ф != модель.форма { модель.форма = ф }
    }

    private func задатьПоле(_ значение: String) {
        guard модель.форма.storage != значение else { return }
        модель.форма.storage = значение
    }

    private func сбросить() {
        withAnimation(пружина) { выбор = nil }
        записать(nil, nil)
    }

    /// Другая вкладка; выбранный размер переезжает по общей системе (EU 38 женской обуви → EU 38 мужской).
    private func сменитьВкладку(_ ключ: String) {
        guard ключ != вкладка, let новая = набор.вкладка(ключ) else { return }
        withAnimation(ДвижениеСайта.вкладка) { вкладка = ключ }
        guard let был = выбор, был.вкладка != ключ, let старая = набор.вкладка(был.вкладка),
              let ряд = ПравилаРазмераОдежды.тотЖеРазмер(был, из: старая, в: новая) else { return }
        применить(ВыборРазмераОдежды(вкладка: ключ, ряд: ряд, ряд2: nil), новая)
    }

    /// Один раз: наша строка в описании (черновик, правка) или значение поля (Kliko AI, правка) → выбор. Ничего не пишет.
    private func восстановить() {
        guard !восстановлено else { return }
        восстановлено = true
        let ф = модель.форма
        if let найдено = ПравилаРазмераОдежды.найти(ф.описание, в: набор) {
            вкладка = найдено.вкладка
            выбор = найдено
            /* Система выбора продавца (черновик, правка — size_sys) или своего размера вещи «Моего» — на переключателе. */
            let код: String = ф.системаРазмера ?? (модель.заготовка?.системаРазмера ?? "")
            if !код.isEmpty, набор.вкладка(найдено.вкладка)?.система(код) != nil {
                системы[найдено.вкладка] = код
            }
            return
        }
        guard let поле else { return }
        let значение = модель.значениеХарактеристики(поле.поле)
        if let найдено = ПравилаРазмераОдежды.изЗначенияПоля(значение, в: набор, начальная: вкладка, поле: поле) {
            вкладка = найдено.вкладка
            выбор = найдено
        }
    }
}

// MARK: - Полоса выбора (вкладки и системы)

/// Сегмент на --surf2: выбранный пункт — карточка с зелёной кромкой, она перелетает (matchedGeometryEffect).
private struct ПолосаВыбораРазмера: View {
    let варианты: [ВариантПоля]
    let выбрано: String
    let высота: CGFloat
    let пространство: Namespace.ID
    let метка: String
    let выбрать: (String) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(варианты, id: \.self) { в in
                кнопка(в)
            }
        }
        .padding(3)
        .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
        }
    }

    private func кнопка(_ в: ВариантПоля) -> some View {
        let да = в.ключ == выбрано
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous)
        return Button {
            выбрать(в.ключ)
        } label: {
            Text(в.подпись)
                .font(.system(size: высота > 32 ? 14 : 13, weight: да ? Font.Weight.bold : Font.Weight.semibold))
                .foregroundStyle(да ? КраскаПодачи.акцентТекст : Theme.текстВторой)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 2)
                .frame(maxWidth: .infinity)
                .frame(height: высота)
                .background {
                    if да {
                        форма
                            .fill(КраскаПодачи.карточка)
                            .overlay { форма.strokeBorder(Theme.акцент, lineWidth: 1.5) }
                            .matchedGeometryEffect(id: метка, in: пространство)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(да ? .isSelected : [])
    }
}

// MARK: - Сетка чипов

/**
 Ровная сетка: колонок 5, 4, 3 или 2 — по самой длинной подписи, все чипы одной высоты (40), неполный ряд добит пустыми
 местами. Выбранный — зелёная заливка, одна на сетку: она перелетает к новому чипу.
 */
private struct СеткаЧиповРазмера: View {
    let чипы: [ЧипРазмераОдежды]
    let выбранныйРяд: Int?
    /// Подпись системы для VoiceOver («EU»), пусто — без неё.
    let код: String
    /// Код системы — возраст показывается на языке телефона.
    let системаКод: String
    let пространство: Namespace.ID
    let метка: String
    let нажато: (ЧипРазмераОдежды) -> Void

    static func колонки(_ подписи: [String]) -> Int {
        let длина = подписи.map { $0.count }.max() ?? 0
        if длина <= 4 { return 5 }
        if длина <= 6 { return 4 }
        if длина <= 11 { return 3 }
        return 2
    }

    var body: some View {
        let колонки = Self.колонки(чипы.map { РазмерыОдеждыText.чип($0.значение, код: системаКод) })
        let ряды = stride(from: 0, to: чипы.count, by: колонки).map { Array(чипы[$0..<min($0 + колонки, чипы.count)]) }
        VStack(spacing: 8) {
            ForEach(ряды.indices, id: \.self) { н in
                HStack(spacing: 8) {
                    ForEach(ряды[н]) { чип in
                        кнопка(чип)
                    }
                    ForEach(0..<(колонки - ряды[н].count), id: \.self) { _ in
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func кнопка(_ чип: ЧипРазмераОдежды) -> some View {
        let выбран = выбранныйРяд.map { чип.ряды.contains($0) } ?? false
        let подпись = РазмерыОдеждыText.чип(чип.значение, код: системаКод)
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return Button {
            нажато(чип)
        } label: {
            Text(подпись)
                .font(.system(size: 15, weight: выбран ? Font.Weight.heavy : Font.Weight.semibold).monospacedDigit())
                .foregroundStyle(выбран ? Color.white : КраскаПодачи.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    if выбран {
                        форма
                            .fill(Theme.зелёный)
                            .matchedGeometryEffect(id: метка, in: пространство)
                    } else {
                        форма.fill(КраскаПодачи.поле)
                    }
                }
                .overlay { форма.strokeBorder(выбран ? Color.clear : КраскаПодачи.линия, lineWidth: 1) }
                .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.94))
        .accessibilityLabel(код.isEmpty ? подпись : код + " " + подпись)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

// MARK: - Плашка поля и пустая бирка

/// «В объявлении: 46 ▾» — значение поля сайта; пусто — серым.
private struct ПлашкаПоляРазмера: View {
    let подпись: String
    let значение: String
    let пусто: Bool
    let стрелка: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(подпись)
                .foregroundStyle(Theme.текстВторой)
            Text(значение)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(пусто ? Theme.текстВторой : КраскаПодачи.текст)
            if стрелка {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(КраскаПодачи.карточка, in: Capsule())
        .overlay { Capsule().strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
        .contentShape(Capsule())
    }
}

/// Бирка до выбора: пунктирная рамка и «Выберите размер — бирка соберётся сама».
private struct ПустаяБиркаРазмера: View {
    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        HStack(spacing: 10) {
            Image(systemName: "tag")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.акцент.opacity(0.7))
                .accessibilityHidden(true)
            Text(РазмерыОдеждыText.т("empty"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(КраскаПодачи.поле.opacity(0.6), in: форма)
        .overlay { форма.strokeBorder(КраскаПодачи.линия, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])) }
    }
}

// MARK: - Бирка (подача и окно объявления)

/**
 Бирка размера: дырочка слева, как у ярлыка; крупно — выбранная система («EU 42»), рядом таблица («Женская обувь»);
 пунктир; строкой все системы («EU 42 | RU 41 | US W 10 | UK 7.5 | MEX 27 | 27 см», выбранная — жирно и зелёным);
 мерки тела по таблице; оговорка «±½». Низ — свой у подачи (поле объявления, строка описания), у покупателя — пусто.
 */
struct БиркаРазмера<Низ: View>: View {
    let данные: ДанныеБиркиРазмера
    let толчок: Int
    let сброс: (() -> Void)?
    let низ: Низ
    @Environment(\.accessibilityReduceMotion) private var безДвижения

    init(_ данные: ДанныеБиркиРазмера, толчок: Int = 0, сброс: (() -> Void)? = nil, @ViewBuilder низ: () -> Низ) {
        self.данные = данные
        self.толчок = толчок
        self.сброс = сброс
        self.низ = низ()
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            верх
            ПунктирБирки()
                .stroke(КраскаПодачи.линия, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(height: 1)
                .accessibilityHidden(true)
            Text(БиркаРазмера.строка(данные.части, выделено: данные.выделено))
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(КраскаПодачи.текст)
                .contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
            if !данные.мерки.isEmpty {
                Label(данные.мерки, systemImage: "ruler")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .contentTransition(.numericText())
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(РазмерыОдеждыText.т("note"))
                .font(.system(size: 11))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            низ
        }
        .padding(.vertical, 12)
        .padding(.leading, 26)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(КраскаПодачи.поле, in: форма)
        .overlay { форма.strokeBorder(Theme.акцент.opacity(0.35), lineWidth: 1) }
        .overlay(alignment: .leading) { дырочка }
        .phaseAnimator(безДвижения ? [1.0] : [1.0, 1.025, 1.0], trigger: толчок) { содержимое, масштаб in
            содержимое.scaleEffect(масштаб)
        } animation: { _ in
            .spring(response: 0.22, dampingFraction: 0.6)
        }
        .accessibilityElement(children: .contain)
    }

    /// Крупно система, рядом таблица, справа «×» (только в подаче).
    private var верх: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(данные.главная)
                .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(КраскаПодачи.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(данные.подпись)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if let сброс {
                Button(action: сброс) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 28, height: 28)
                        .background(КраскаПодачи.карточка, in: Circle())
                        .overlay { Circle().strokeBorder(КраскаПодачи.линия, lineWidth: 1) }
                        .contentShape(Circle())
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.9))
                .accessibilityLabel(РазмерыОдеждыText.т("clear"))
            }
        }
    }

    /// Дырочка ярлыка у левого края.
    private var дырочка: some View {
        Circle()
            .fill(КраскаПодачи.карточка)
            .overlay { Circle().strokeBorder(Theme.акцент.opacity(0.35), lineWidth: 1) }
            .frame(width: 10, height: 10)
            .padding(.leading, 9)
            .accessibilityHidden(true)
    }

    /// Строка систем: куски неразрывны и изолированы (арабский порядок не ломает «US W 9»), между ними «|»;
    /// выбранная система — жирно и зелёным.
    static func строка(_ части: [ЧастьБиркиРазмера], выделено: String) -> AttributedString {
        var итог = AttributedString()
        for (номер, часть) in части.enumerated() {
            if номер > 0 {
                var черта = AttributedString("  |  ")
                черта.foregroundColor = Theme.текстВторой.opacity(0.55)
                итог += черта
            }
            let текст = РазмерыОдеждыText.показ(часть).replacingOccurrences(of: " ", with: "\u{00A0}")
            var кусок = AttributedString(текст.слеваНаправо)
            let коды = часть.код.components(separatedBy: "/")
            if часть.код == выделено || коды.contains(выделено) {
                кусок.font = Font.system(size: 14, weight: .heavy).monospacedDigit()
                кусок.foregroundColor = Theme.акцент
            }
            итог += кусок
        }
        return итог
    }
}

extension БиркаРазмера where Низ == EmptyView {
    /// Бирка без низа и без «×» — для окна объявления.
    init(_ данные: ДанныеБиркиРазмера) {
        self.init(данные, толчок: 0, сброс: nil) { EmptyView() }
    }
}

/// Пунктир поперёк бирки.
private struct ПунктирБирки: Shape {
    func path(in r: CGRect) -> Path {
        var путь = Path()
        путь.move(to: CGPoint(x: r.minX, y: r.midY))
        путь.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return путь
    }
}

/**
 Бирка в окне объявления у покупателя — ГОТОВА, НО НЕ ВСТРОЕНА (окно объявления правит другая пачка). Встраивать в
 Design/SiteListing.swift перед БлокОписанияВида (низ страницы, «Характеристики у всех разделов»):
     if let бирка = СтрокаРазмераВсехСистем.бирка(описание: товар.описание ?? "", раздел: товар.категория) {
         БиркаРазмераОбъявления(данные: бирка)
     }
 а описание для экрана — без нашей строки: ПравилаРазмераОдежды.безСтроки(…).
 */
struct БиркаРазмераОбъявления: View {
    let данные: ДанныеБиркиРазмера

    init(данные: ДанныеБиркиРазмера) {
        self.данные = данные
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(РазмерыОдеждыText.т("buyer_title"), systemImage: "tag")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            БиркаРазмера(данные)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

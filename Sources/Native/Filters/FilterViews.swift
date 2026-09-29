import SwiftUI

/**
 ФИЛЬТРЫ КАК НА САЙТЕ — ЭТАП 33 (владелец 25.09.2026: «почти 100% похоже на сайт»). Модель и параметры —
 FeedFilters.swift.

 Образцы — лента сайта на телефоне (css/marketplace.min.css, css/marketplace-parts.min.css, разметка главной):
   · ПолосаФильтров — правая часть .mk-rbar: кнопка «Фильтры» (.mk-ctrl, 40 pt, скругление 14, рамка 1,5 цвета линии;
     выбрано что-то — мятная с зелёной рамкой и числом на зелёной плашке .mk-fc) и «Сначала показывать» — выпадающий
     список .mk-sort-sel во всю оставшуюся ширину;
   · ЧипыФильтров — .mk-active: мятные пилюли .mk-achip с «×» и красное «Сбросить всё» (.mk-clearall), с переносом строк;
   · ЛистФильтров — .mk-drawer: снизу, скругление 20, шапка «Фильтры» 19 pt с квадратной «×» на --mk-surf2, группы
     .mk-dfg — заголовок заглавными серым с золотой чертой 14×2, варианты .mk-dopt (40 pt, скругление 12, --mk-surf2 с
     рамкой; выбранный — мятный, рамка 2 pt акцентом и галочка), цена — два поля .mk-pinp через «—»; внизу .mk-dfoot:
     «Сбросить» на --mk-surf2 и зелёная «Показать N» градиентом.

 🔴 ПРИМЕНЯЕТСЯ СРАЗУ, КАК У САЙТА. У сайта каждое нажатие в панели сразу перерисовывает ленту (mkRender), а «Показать»
 только закрывает панель, и на ней — сколько нашлось (_mkTotal, total ответа). Так и здесь: вариант — сразу в ленту под
 листом (FeedModel.применитьФильтры, прежний запрос отменяется), набранные цена и год — после 0,7 с тишины и при закрытии
 листа; «Показать» пишет total первой страницы. Лишних запросов нет: то же самое второй раз не запрашивается.
 */

// MARK: - Краски

private enum КраскиФильтров {
    /// Выбранный вариант, чип и рамка кнопки «Фильтры»: --mk-green, в тёмной — --mk-bright (#5cd39a): [data-theme=dark]
    /// .mk-dopt.on и .mk-achip.
    static let выбрано = Theme.цвет(0x0F5132, 0x5CD39A)
    /// «Сбросить всё» (.mk-clearall): --mk-danger — #e5484d и #ff6168.
    static let сброс = Theme.цвет(0xE5484D, 0xFF6168)
    /// Число на «Фильтры» (.mk-fc): --mk-green. В тёмной у сайта это #5cd39a, и белые цифры на нём не читаются
    /// (этап 31) — берём #1d7d4a.
    static let плашкаЧисла = Theme.цвет(0x0F5132, 0x1D7D4A)
}

// MARK: - Над выдачей (.mk-rbar)

/// «Фильтры» с числом и «Сначала показывать» — одной строкой над выдачей, как у сайта на телефоне.
struct ПолосаФильтров: View {
    let число: Int
    let сортировка: СортировкаЛенты
    let открыть: () -> Void
    let выбрать: (СортировкаЛенты) -> Void
    /// Этап 39: значок карты последним в строке — вход в карту объявлений с фильтрами этой ленты. nil — значка нет.
    var карта: (() -> Void)? = nil
    /// Дизайн сайта: на «Фильтры» — сводка mkFbtnSync (`подпись`), без неё — один значок (#mk-fbtn:not(.has)).
    var сайт = false
    var подпись: String? = nil
    /// #mk-subbtn: колокольчик «Подписаться на этот поиск» первым в строке; nil — его нет (нет ни поиска, ни раздела).
    var подписка: (() -> Void)? = nil
    var подписан = false

    var body: some View {
        HStack(spacing: 8) {
            if let подписаться = подписка {
                КнопкаПодпискиВыдачи(подписан: подписан, действие: подписаться)
            }
            КнопкаФильтров(число: число, сайт: сайт, подпись: подпись, действие: открыть)
            МенюСортировки(сортировка: сортировка, выбрать: выбрать)
            if let открытьКарту = карта {
                КнопкаКартыЛенты(действие: открытьКарту)
            }
        }
        .padding(.horizontal, 16)
    }
}

/// .mk-ctrl.mk-subbtn: на телефоне подпись спрятана (#mk-subbtn-lbl) — квадрат 42×40 с колокольчиком; подписан (.on) —
/// заливка и рамка --mk-green, значок белый.
private struct КнопкаПодпискиВыдачи: View {
    let подписан: Bool
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            Image(systemName: подписан ? "bell.fill" : "bell")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(подписан ? Color.white : Theme.текстВторой)
                .frame(width: 42, height: 40)
                .background(подписан ? Theme.зелёный : Theme.поверхность,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(подписан ? Theme.зелёный : Theme.линия, lineWidth: 1.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SavedSearchText.т(подписан ? "unsave" : "save"))
    }
}

/// Этап 39: квадрат .mk-ctrl 40 pt со значком карты зелёным — как «Карта» сайта (.mk-map-badge: --mk-green2 значок).
private struct КнопкаКартыЛенты: View {
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            Image(systemName: "map")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 40, height: 40)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MapText.т("map"))
    }
}

/// .mk-ctrl#mk-fbtn: значок трёх убывающих линий, «Фильтры» и число выбранного. В дизайне сайта на телефоне без
/// выбранного — один значок 42×40, с выбранным — сводка (не шире 9,5 em, с многоточием).
private struct КнопкаФильтров: View {
    let число: Int
    var сайт = false
    var подпись: String? = nil
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: сайт ? 16 : 15, weight: .semibold))
                    .foregroundStyle(выбрано ? Theme.акцент : Theme.текстВторой)
                    .accessibilityHidden(true)
                if let надпись {
                    if сайт {
                        НеШире(максимум: 9.5 * 14) { строка(надпись) }
                    } else {
                        строка(надпись)
                    }
                }
                if выбрано {
                    Text(String(число))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(КраскиФильтров.плашкаЧисла,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, одинЗначок ? 0 : 12)
            .padding(.vertical, 4)
            .frame(minWidth: одинЗначок ? 42 : nil, minHeight: 40)
            .background(выбрано ? Theme.мята : Theme.поверхность,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(выбрано ? КраскиФильтров.выбрано : Theme.линия, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel(FilterText.т("filters"))
        .accessibilityValue(подпись ?? (выбрано ? String(число) : ""))
    }

    private var выбрано: Bool { число > 0 }

    private func строка(_ надпись: String) -> some View {
        Text(надпись)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(выбрано ? Theme.акцент : Theme.текст)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// Надпись на кнопке: прежний вид — всегда «Фильтры», дизайн сайта — сводка или ничего.
    private var надпись: String? { сайт ? подпись : FilterText.т("filters") }

    /// Только значок — квадрат 42×40, как #mk-fbtn:not(.has) сайта.
    private var одинЗначок: Bool { надпись == nil && !выбрано }
}

/// max-width сайта: своя ширина, пока влезает в `максимум`, длиннее — ужимается до него (текст — с многоточием).
/// .frame(maxWidth:) тут не годится: он растянул бы и короткую надпись до предела.
private struct НеШире: Layout {
    let максимум: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let вид = subviews.first else { return .zero }
        let ширина = min(proposal.width ?? максимум, максимум)
        return вид.sizeThatFits(ProposedViewSize(width: ширина, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// «Сначала показывать» — .mk-sort-sel: выбранный порядок и стрелка вниз; нажатие — список вариантов с галочкой.
private struct МенюСортировки: View {
    let сортировка: СортировкаЛенты
    let выбрать: (СортировкаЛенты) -> Void

    var body: some View {
        Menu {
            Picker(FilterText.т("sort_title"), selection: выбор) {
                ForEach(СортировкаЛенты.вМеню, id: \.self) { вариант in
                    Text(вариант.подпись).tag(вариант)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(сортировка.подпись)
                    .font(.system(size: 16, weight: .semibold))      // select на телефоне — не меньше 16 px
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.trailing, -2)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel(FilterText.т("sort_title"))
        .accessibilityValue(сортировка.подпись)
    }

    /// Галочка — на пункте списка: «новые подряд» из ссылки (date_desc) отмечены как «Новые», как select сайта.
    private var выбор: Binding<СортировкаЛенты> {
        Binding(get: { сортировка.пунктМеню }, set: { новая in выбрать(новая) })
    }
}

/// .mk-active: выбранное пилюлями с «×» и «Сбросить всё». Строка переносится, как flex-wrap у сайта.
struct ЧипыФильтров: View {
    let чипы: [АктивныйФильтр]
    let убрать: (ВидФильтра) -> Void
    let сбросить: () -> Void

    var body: some View {
        ПереносЧипов {
            ForEach(чипы) { чип in
                ЧипАктивногоФильтра(текст: чип.текст) { убрать(чип.вид) }
            }
            Button(action: сбросить) {
                Text(FilterText.т("reset_all"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(КраскиФильтров.сброс)
                    .padding(.horizontal, 4)
                    .frame(minHeight: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }
}

/// .mk-achip: мятная пилюля, текст 12 pt зелёным и «×» в кружке. Нажатие на всю пилюлю убирает фильтр — у сайта это
/// только «×» 20 pt, но на телефоне в неё трудно попасть пальцем; VoiceOver читает «Сбросить: …», как aria-label сайта.
private struct ЧипАктивногоФильтра: View {
    let текст: String
    let убрать: () -> Void

    var body: some View {
        Button(action: убрать) {
            HStack(spacing: 6) {
                Text(текст)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(Theme.зелёный2.opacity(0.18), in: Circle())
                    .accessibilityHidden(true)
            }
            .foregroundStyle(КраскиФильтров.выбрано)
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 7)          // 6 + рамка 1: пилюля 34, как .mk-achip
            .background(Theme.мята, in: Capsule())
            .overlay {
                Capsule().strokeBorder(Theme.зелёный2.opacity(0.25), lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(format: FilterText.т("remove_a11y"), текст))
    }
}

// MARK: - Перенос строк (flex-wrap)

/// Пилюли подряд с переносом на новую строку, когда в ширину больше не помещаются, — flex-wrap сайта.
struct ПотокЧипов: Layout {
    var зазор: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ширина = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var высотаРяда: CGFloat = 0
        var ширинаРядов: CGFloat = 0
        for вид in subviews {
            let р = Self.размер(вид, ширина)
            if x > 0 && x + р.width > ширина {
                y += высотаРяда + зазор
                x = 0
                высотаРяда = 0
            }
            x += р.width
            ширинаРядов = max(ширинаРядов, x)
            x += зазор
            высотаРяда = max(высотаРяда, р.height)
        }
        return CGSize(width: ширина.isFinite ? ширина : ширинаРядов, height: y + высотаРяда)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var высотаРяда: CGFloat = 0
        for вид in subviews {
            let р = Self.размер(вид, bounds.width)
            if x > bounds.minX && x + р.width > bounds.maxX {
                x = bounds.minX
                y += высотаРяда + зазор
                высотаРяда = 0
            }
            вид.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(р))
            x += р.width + зазор
            высотаРяда = max(высотаРяда, р.height)
        }
    }

    /// Свой размер пилюли; шире строки — ужатая до строки (текст тогда сократится многоточием).
    private static func размер(_ вид: LayoutSubview, _ ширина: CGFloat) -> CGSize {
        let свой = вид.sizeThatFits(.unspecified)
        guard ширина.isFinite, свой.width > ширина else { return свой }
        return вид.sizeThatFits(ProposedViewSize(width: ширина, height: nil))
    }
}

/// Содержимое в ПотокЧипов с зазором 8 — .mk-active и .mk-dopts сайта (gap 8px).
struct ПереносЧипов<Содержимое: View>: View {
    let содержимое: Содержимое

    init(@ViewBuilder содержимое: () -> Содержимое) {
        self.содержимое = содержимое()
    }

    var body: some View {
        let поток = ПотокЧипов(зазор: 8)
        поток {
            содержимое
        }
    }
}

// MARK: - Лист «Фильтры» (.mk-drawer)

/// Какое поле с числом в фокусе.
private enum ПолеФильтра: Hashable {
    case ценаОт
    case ценаДо
    case годОт
    case годДо
}

/// Лист «Фильтры». Варианты применяются сразу, набранные цена и год — после паузы и при закрытии (см. шапку файла).
struct ЛистФильтров: View {
    @ObservedObject private var модель: FeedModel
    @Environment(\.dismiss) private var закрыть
    /// Набранное в полях — строкой, как в поле; в фильтры уходит числом (ФильтрыЛенты.числоИз, год).
    @State private var ценаОт: String
    @State private var ценаДо: String
    @State private var годОт: String
    @State private var годДо: String
    @FocusState private var поле: ПолеФильтра?

    /// `начальные` — фильтры ленты на момент открытия: поля цены и года начинаются с них.
    init(модель: FeedModel, начальные: ФильтрыЛенты) {
        _модель = ObservedObject(wrappedValue: модель)
        _ценаОт = State(initialValue: начальные.ценаОт.map { String($0) } ?? "")
        _ценаДо = State(initialValue: начальные.ценаДо.map { String($0) } ?? "")
        _годОт = State(initialValue: начальные.годОт.map { String($0) } ?? "")
        _годДо = State(initialValue: начальные.годДо.map { String($0) } ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            шапка
            ScrollView {
                группы
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            низ
        }
        .background(Theme.поверхность)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.поверхность)
        .presentationCornerRadius(Theme.Радиус.xl)
        /* Набранные цена и год — в ленту после 0,7 с тишины: не запрос на каждую цифру. */
        .task(id: набранное) {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            применитьНабранное()
        }
        /* Закрыли смахиванием, пока пауза не вышла, — набранное всё равно в ленту. */
        .onDisappear { применитьНабранное() }
    }

    /// .mk-dhead: «Фильтры» и квадратная «×».
    private var шапка: some View {
        HStack(spacing: 12) {
            Text(FilterText.т("filters"))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button { готово() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .frame(width: 36, height: 36)
                    .background(Theme.поверхность2,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(FilterText.т("close"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.линия).frame(height: 1)
        }
    }

    /// Группы .mk-dfg: порядок, цена, год (транспорт), комнаты (жильё), коробка и топливо (транспорт), состояние,
    /// продавец, фото.
    @ViewBuilder
    private var группы: some View {
        VStack(alignment: .leading, spacing: 0) {
            группаСортировки
            группаЦены
            if ФильтрыЛенты.годДоступен(модель.раздел) { группаГода }
            if ФильтрыЛенты.комнатыДоступны(модель.раздел) { группаКомнат }
            if ФильтрыЛенты.автоДоступно(модель.раздел) { группыАвто }
            группаСостояния
            группаПродавца
            группаФото
        }
    }

    private var группаСортировки: some View {
        ГруппаФильтра(FilterText.т("sort_title")) {
            ПереносЧипов {
                ForEach(СортировкаЛенты.вМеню, id: \.self) { вариант in
                    ВариантФильтра(текст: вариант.подпись,
                                   выбран: модель.фильтры.сортировка.пунктМеню == вариант) {
                        применить { ф in ф.сортировка = вариант }
                    }
                }
            }
        }
    }

    /// «Коробка» и «Топливо» — шаги мастера авто сайта (MK_AF_GEAR, MK_AF_FUEL): несколько вариантов сразу, повторное
    /// нажатие снимает.
    private var группыАвто: some View {
        VStack(alignment: .leading, spacing: 0) {
            ГруппаФильтра(FilterText.т("gear")) {
                ПереносЧипов {
                    ForEach(ФильтрыЛенты.всеКоробки, id: \.self) { значение in
                        ВариантФильтра(текст: ФильтрыЛенты.подписьАвто(значение),
                                       выбран: модель.фильтры.коробка.contains(значение)) {
                            применить { ф in ФильтрыЛенты.переключить(значение, в: &ф.коробка) }
                        }
                    }
                }
            }
            ГруппаФильтра(FilterText.т("fuel")) {
                ПереносЧипов {
                    ForEach(ФильтрыЛенты.всеВидыТоплива, id: \.self) { значение in
                        ВариантФильтра(текст: ФильтрыЛенты.подписьАвто(значение),
                                       выбран: модель.фильтры.топливо.contains(значение)) {
                            применить { ф in ФильтрыЛенты.переключить(значение, в: &ф.топливо) }
                        }
                    }
                }
            }
        }
    }

    private var группаЦены: some View {
        ГруппаФильтра(FilterText.т("price")) {
            ПараПолей(от: $ценаОт, до: $ценаДо, заголовок: FilterText.т("price"), цифр: 12, фокус: $поле,
                      полеОт: .ценаОт, полеДо: .ценаДо)
        }
    }

    private var группаГода: some View {
        ГруппаФильтра(FilterText.т("year")) {
            ПараПолей(от: $годОт, до: $годДо, заголовок: FilterText.т("year"), цифр: 4, фокус: $поле,
                      полеОт: .годОт, полеДо: .годДо)
        }
    }

    private var группаКомнат: some View {
        ГруппаФильтра(FilterText.т("rooms")) {
            ПереносЧипов {
                ForEach(ФильтрыЛенты.всеКомнаты, id: \.self) { значение in
                    ВариантФильтра(текст: ФильтрыЛенты.подписьКомнат(значение),
                                   выбран: модель.фильтры.комнаты.contains(значение)) {
                        применить { ф in
                            if ф.комнаты.contains(значение) {
                                ф.комнаты.remove(значение)
                            } else {
                                ф.комнаты.insert(значение)
                            }
                        }
                    }
                }
            }
        }
    }

    /// «Новое» / «Б/У»: повторное нажатие снимает выбор, как #mk-d-cond сайта (mkSt.cond === v ? "" : v).
    private var группаСостояния: some View {
        ГруппаФильтра(FilterText.т("cond")) {
            ПереносЧипов {
                ForEach(СостояниеТовара.allCases, id: \.self) { вариант in
                    ВариантФильтра(текст: вариант.подпись(раздел: модель.раздел),
                                   выбран: модель.фильтры.состояние == вариант) {
                        применить { ф in ф.состояние = ф.состояние == вариант ? nil : вариант }
                    }
                }
            }
        }
    }

    private var группаПродавца: some View {
        ГруппаФильтра(FilterText.т("seller")) {
            ВариантФильтра(текст: FilterText.т("verified"), выбран: модель.фильтры.толькоПроверенные) {
                применить { ф in ф.толькоПроверенные.toggle() }
            }
        }
    }

    private var группаФото: some View {
        ГруппаФильтра(FilterText.т("photo"), последняя: true) {
            ВариантФильтра(текст: FilterText.т("photo_only"), выбран: модель.фильтры.сФото) {
                применить { ф in ф.сФото.toggle() }
            }
        }
    }

    /// .mk-dfoot: «Сбросить» и «Показать N».
    private var низ: some View {
        HStack(spacing: 10) {
            Button { сбросить() } label: {
                Text(FilterText.т("reset"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .padding(.horizontal, 20)
                    .frame(minHeight: 45)
                    .background(Theme.поверхность2,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
            .buttonStyle(.plain)
            Button { готово() } label: {
                подписьПоказать
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, minHeight: 45)
                    /* .mk-dapply: 135deg --mk-green2 → --mk-green, в тёмной — #34c997 → #22a05b */
                    .background(LinearGradient(colors: [Theme.зелёный2, Theme.зелёный],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        /* .mk-dfoot: линия сверху и тень вверх 0 −8 20 −14 rgba(0,0,0,.45) — мягче, без разлёта в стороны */
        .background(Theme.поверхность.shadow(.drop(color: Color.black.opacity(0.18), radius: 8, x: 0, y: -4)))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.линия).frame(height: 1)
        }
    }

    /// «Показать 41» — total выдачи под листом; пока она грузится — колесо (белый текст на тёмно-зелёном в обеих темах).
    private var подписьПоказать: some View {
        HStack(spacing: 6) {
            Text(FilterText.т("show"))
                .font(.system(size: 15, weight: .bold))
            if модель.грузим {
                SiteSpinner.мелкийБелый
            } else if let найдено = модель.всего {
                Text(DesignText.число(найдено))
                    .font(.system(size: 15, weight: .bold))
            }
        }
    }

    // MARK: - Действия

    /// Цена и год строкой — ключ паузы перед применением.
    private var набранное: String { [ценаОт, ценаДо, годОт, годДо].joined(separator: "|") }

    /// Изменение варианта — сразу в ленту, вместе с набранным в полях; клавиатура прячется.
    private func применить(_ изменить: (inout ФильтрыЛенты) -> Void) {
        поле = nil
        var новые = модель.фильтры
        вписатьНабранное(&новые)
        изменить(&новые)
        модель.применитьФильтры(новые)
    }

    private func применитьНабранное() {
        var новые = модель.фильтры
        вписатьНабранное(&новые)
        модель.применитьФильтры(новые)
    }

    private func вписатьНабранное(_ ф: inout ФильтрыЛенты) {
        ф.ценаОт = ФильтрыЛенты.числоИз(ценаОт, цифр: 12)
        ф.ценаДо = ФильтрыЛенты.числоИз(ценаДо, цифр: 12)
        ф.годОт = ФильтрыЛенты.год(годОт)
        ф.годДо = ФильтрыЛенты.год(годДо)
    }

    /// «Сбросить» — mkReset сайта для фильтров: всё выбранное и набранное — прочь; порядок остаётся, как у сайта.
    private func сбросить() {
        поле = nil
        ценаОт = ""
        ценаДо = ""
        годОт = ""
        годДо = ""
        модель.сброситьФильтры()
    }

    /// «Показать» и «×»: набранное — в ленту, лист — закрыть.
    private func готово() {
        поле = nil
        применитьНабранное()
        закрыть()
    }
}

// MARK: - Части листа

/// Группа .mk-dfg: заголовок заглавными серым с золотой чертой, содержимое, линия снизу (у последней — нет).
private struct ГруппаФильтра<Содержимое: View>: View {
    let заголовок: String
    let последняя: Bool
    let содержимое: Содержимое

    init(_ заголовок: String, последняя: Bool = false, @ViewBuilder содержимое: () -> Содержимое) {
        self.заголовок = заголовок
        self.последняя = последняя
        self.содержимое = содержимое()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Theme.золото)
                    .frame(width: 14, height: 2)
                Text(заголовок)
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.текстВторой)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            содержимое
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, последняя ? 0 : 20)
        .overlay(alignment: .bottom) {
            if !последняя {
                Rectangle().fill(Theme.линия).frame(height: 1)
            }
        }
        .padding(.bottom, последняя ? 0 : 20)
    }
}

/// Вариант .mk-dopt: пилюля 40 pt на --mk-surf2 с рамкой; выбранный — мятный, рамка 2 pt акцентом, галочка слева.
private struct ВариантФильтра: View {
    let текст: String
    let выбран: Bool
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                if выбран {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .accessibilityHidden(true)
                }
                Text(текст)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(выбран ? КраскиФильтров.выбрано : Theme.текст)
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .frame(minHeight: 40)
            .background(выбран ? Theme.мята : Theme.поверхность2,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(выбран ? Theme.зелёный2 : Theme.линия, lineWidth: выбран ? 2 : 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }
}

/// «от — до»: два поля .mk-pinp через тире.
private struct ПараПолей: View {
    @Binding var от: String
    @Binding var до: String
    let заголовок: String
    let цифр: Int
    let фокус: FocusState<ПолеФильтра?>.Binding
    let полеОт: ПолеФильтра
    let полеДо: ПолеФильтра

    var body: some View {
        HStack(spacing: 10) {
            ПолеЧисла(текст: $от, подсказка: FilterText.т("from"), подпись: заголовок + ", " + FilterText.т("from"),
                      цифр: цифр, фокус: фокус, своё: полеОт)
            Text("—")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            ПолеЧисла(текст: $до, подсказка: FilterText.т("to"), подпись: заголовок + ", " + FilterText.т("to"),
                      цифр: цифр, фокус: фокус, своё: полеДо)
        }
    }
}

/// Поле .mk-pinp: 42 pt на --mk-surf2, рамка 1,5 цвета линии, в фокусе — акцентом. Только цифры, не длиннее `цифр`.
private struct ПолеЧисла: View {
    @Binding var текст: String
    let подсказка: String
    let подпись: String
    let цифр: Int
    let фокус: FocusState<ПолеФильтра?>.Binding
    let своё: ПолеФильтра

    var body: some View {
        TextField(подсказка, text: $текст, prompt: Text(подсказка).foregroundColor(Theme.текстВторой))
            .font(.system(size: 16))               // .mk-pinp: 16 px, высота 44
            .foregroundStyle(Theme.текст)
            .tint(Theme.акцент)
            .keyboardType(.numberPad)
            .focused(фокус, equals: своё)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(вФокусе ? Theme.акцент : Theme.линия, lineWidth: 1.5)
            }
            .accessibilityLabel(подпись)
            .onChange(of: текст) { _, новое in
                let чистое = String(новое.filter { $0.isASCII && $0.isNumber }.prefix(цифр))
                if чистое != новое { текст = чистое }
            }
    }

    private var вФокусе: Bool { фокус.wrappedValue == своё }
}

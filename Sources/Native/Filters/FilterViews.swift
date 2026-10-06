import SwiftUI

/**
 ФИЛЬТРЫ КАК НА САЙТЕ — ЭТАП 33 (владелец 25.09.2026: «почти 100% похоже на сайт»). Модель и параметры —
 FeedFilters.swift.

 Образцы — лента сайта на телефоне (css/marketplace.min.css, css/marketplace-parts.min.css, разметка главной):
   · ПолосаФильтров — правая часть .mk-rbar: кнопка «Фильтры» (.mk-ctrl, 40 pt, скругление 14, рамка 1,5 цвета линии;
     выбрано что-то — мятная с зелёной рамкой и числом на зелёной плашке .mk-fc) и «Сначала показывать» — выпадающий
     список .mk-sort-sel во всю оставшуюся ширину;
   · ЧипыФильтров — .mk-active: мятные пилюли .mk-achip с «×» и красное «Сбросить всё» (.mk-clearall), с переносом строк;
   · ЛистФильтров — форма подбора сайта (.afx, js/marketplace-wizard.js, css/marketplace-parts.css; владелец 30.09.2026:
     «фильтрация по вертикали сейчас непонятная, на сайте лучше»): шапка «× · Параметры · Сбросить», карточки на сером
     фоне; короткий выбор — дорожкой («Все / Новые / С пробегом», «Все / Купить / Снять», комнаты, ОЗУ), длинный — строкой
     «Марка … Любая ›», открывающей список с поиском; числа — поля «от — до»; внизу одна зелёная «Показать N предложений».

 🔴 ПРИМЕНЯЕТСЯ СРАЗУ, КАК У САЙТА. У сайта каждое нажатие в панели сразу перерисовывает ленту (mkRender), а «Показать»
 только закрывает панель, и на ней — сколько нашлось (_mkTotal, total ответа). Так и здесь: вариант — сразу в ленту под
 листом (FeedModel.применитьФильтры, прежний запрос отменяется), набранные числа — после 0,7 с тишины и при закрытии
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


// MARK: - Лист «Фильтры» (.afx — форма подбора сайта)

/// Краски формы подбора сайта (.afx в css/marketplace-parts.css).
private enum КраскиЛистаФильтров {
    /// --afx-bg под карточками: --mk-surf2, в тёмной — #0e0e14.
    static let фон = Theme.цвет(0xF4F8F6, 0x0E0E14)
    /// --afx-fill — поля и дорожки: 5 % цвета текста поверх карточки, в тёмной — белый 7 %.
    static let заливка = Theme.цвет(светлый: Theme.hex(0x13211B, 0.05), тёмный: Theme.hex(0xFFFFFF, 0.07))
    /// --afx-segon — выбранный сегмент: --mk-surf, в тёмной — #2c2c38.
    static let сегмент = Theme.цвет(0xFFFFFF, 0x2C2C38)
    /// --afx-on — текст на зелёной кнопке: белый, в тёмной — #06170e.
    static let наКнопке = Theme.цвет(0xFFFFFF, 0x06170E)
}

/// Что выбирают в списке поверх формы (строка «… ›» формы сайта открывает список выбора).
private enum ВыборАвтоФильтра: Identifiable, Hashable {
    case марка
    case модель
    case типДетали
    case коробка
    case топливо
    case размещение
    case признаки
    case фасет(ФасетРаздела)

    var id: String {
        switch self {
        case .марка:          return "brand"
        case .модель:         return "model"
        case .типДетали:      return "ptype"
        case .коробка:        return "gear"
        case .топливо:        return "fuel"
        case .размещение:     return "place"
        case .признаки:       return "rt"
        case .фасет(let ф):   return "f:" + ф.колонка
        }
    }
}

/// Справочник марок и моделей — тот же загрузчик, что у мастера авто подачи (ПодачаМодель.загрузитьМарки и
/// моделиМарки, /api/auto_models.php): один на приложение, чтобы марки и модели не спрашивать при каждом открытии листа.
@MainActor
private enum СправочникМарокФильтров {
    static let общий = ПодачаМодель(цель: .новое)
}

/// Какое поле с числом в фокусе.
private enum ПолеФильтра: Hashable {
    case ценаОт
    case ценаДо
    case годОт
    case годДо
    case ступеньОт(ДиапазонФильтра)
    case ступеньДо(ДиапазонФильтра)
}

/// Вариант дорожки: ключ (уходит в фильтр) и подпись.
private struct ВариантДорожкиФильтров: Hashable {
    let ключ: String
    let текст: String
}

/// Строка «Подпись … Значение ›» (.afx-row) — описанием, чтобы между строками карточки ставить черту.
private struct ОписаниеСтрокиФильтров: Identifiable {
    let id: String
    let подпись: String
    let значение: String
    let пусто: String
    var закрыта = false
    let действие: () -> Void
}

/**
 Лист «Фильтры» — форма подбора сайта (_afxForm): порядок карточек как у сайта по разделу —
   · первой — «Раздел ›» (af_section): подразделы текущего, у них свои характеристики (см. карточкаРаздела);
   · авто: «Все / Новые / С пробегом»; тип запчасти, марка, модель; цена, год, пробег, объём; коробка, топливо;
   · жильё: «Все / Купить / Снять»; где помещение; комнаты, цена, площадь, участок, этаж; «Все / Новостройка /
     Вторичка», год постройки, «Уточнения»;
   · техника: «Все / Новые / Б/у»; цена; ОЗУ, накопитель, процессор, видеокарта; характеристики справочника;
   · прочее: состояние; цена; характеристики раздела строками;
   · у всех последней — «Продавец» и «Фото» дорожками (_afxVerSeg, _afxPhotoSeg).
 Варианты применяются сразу, набранные числа — после паузы и при закрытии (см. шапку файла). Порядок выдачи — в полосе над
 лентой, как у сайта: в форме его нет.
 */
struct ЛистФильтров: View {
    @ObservedObject private var модель: FeedModel
    @Environment(\.dismiss) private var закрыть
    /// Набранное в полях — строкой, как в поле; в фильтры уходит числом.
    @State private var ценаОт: String
    @State private var ценаДо: String
    @State private var годОт: String
    @State private var годДо: String
    @State private var ступениОт: [ДиапазонФильтра: String]
    @State private var ступениДо: [ДиапазонФильтра: String]
    @FocusState private var поле: ПолеФильтра?
    /// Открыт список выбора (лист поверх листа).
    @State private var выборАвто: ВыборАвтоФильтра?
    /// Открыт список «Раздел» (_afxListTCat / _afxListTree сайта).
    @State private var выборРаздела = false

    /// `начальные` — фильтры ленты на момент открытия: поля чисел начинаются с них.
    init(модель: FeedModel, начальные: ФильтрыЛенты) {
        _модель = ObservedObject(wrappedValue: модель)
        _ценаОт = State(initialValue: начальные.ценаОт.map { String($0) } ?? "")
        _ценаДо = State(initialValue: начальные.ценаДо.map { String($0) } ?? "")
        _годОт = State(initialValue: начальные.годОт.map { String($0) } ?? "")
        _годДо = State(initialValue: начальные.годДо.map { String($0) } ?? "")
        _ступениОт = State(initialValue: начальные.ступениОт.mapValues { ДиапазонФильтра.вЗапрос($0) })
        _ступениДо = State(initialValue: начальные.ступениДо.mapValues { ДиапазонФильтра.вЗапрос($0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            шапка
            ScrollView {
                группы
                    .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(КраскиЛистаФильтров.фон)
            .sheet(isPresented: $выборРаздела) {
                if let дерево = ДеревоРазделаФильтров.для(модель.раздел) {
                    ЛистРазделаФильтров(дерево: дерево, текущий: модель.раздел) { ключ in
                        выбратьРазделФильтров(ключ)
                    }
                }
            }
            низ
        }
        .background(Theme.поверхность)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.поверхность)
        .presentationCornerRadius(Theme.Радиус.xl)
        /* Набранные числа — в ленту после 0,7 с тишины: не запрос на каждую цифру. */
        .task(id: набранное) {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            применитьНабранное()
        }
        /* Закрыли смахиванием, пока пауза не вышла, — набранное всё равно в ленту. */
        .onDisappear { применитьНабранное() }
        .sheet(item: $выборАвто) { что in
            ЛистМаркиМодели(лента: модель, что: что)
        }
    }

    /// .afx-h: «×» слева, «Параметры» посередине, «Сбросить» зелёным справа.
    private var шапка: some View {
        ZStack {
            Text(FilterText.т("x_params"))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .padding(.horizontal, 110)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                Button { готово() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(FilterText.т("close"))
                Spacer(minLength: 8)
                Button { сбросить() } label: {
                    Text(FilterText.т("reset"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(Theme.поверхность)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.линия).frame(height: 1)
        }
    }

    /// Карточки формы по порядку сайта (см. описание листа).
    private var группы: some View {
        let раздел = модель.раздел
        let жильё = ФильтрыЛенты.сделкаДоступна(раздел)
        let строки = строкиВыбора
        let характеристики = строкиХарактеристик
        let диапазоны = ФильтрыЛенты.диапазоныХарактеристик(раздел)
        let дерево = ДеревоРазделаФильтров.для(раздел)
        return VStack(spacing: 8) {
            if let дерево { карточкаРаздела(дерево) }
            if жильё {
                if !модель.аренда { карточкаСделки }
            } else if ФильтрыЛенты.состояниеДоступно(раздел) {
                КарточкаФильтров { дорожкаСостояния }
            }
            if !строки.isEmpty { СтрокиФильтров(строки: строки) }
            карточкаЧисел
            if ФильтрыЛенты.автоДоступно(раздел) { СтрокиФильтров(строки: строкиАвто) }
            if !ФильтрыЛенты.видТехники(раздел).isEmpty { карточкаТехники }
            if !характеристики.isEmpty { СтрокиФильтров(строки: характеристики) }
            if !диапазоны.isEmpty { карточкаДиапазонов(диапазоны) }
            if жильё { карточкаЖильяЕщё }
            карточкаПродавца
        }
    }

    /// «Раздел ›» вверху формы (af_section сайта: «Вся электроника», «Все товары»…). На корне раздела характеристик нет —
    /// они у подразделов (ОЗУ у ноутбуков, память у смартфонов); владелец 06.10.2026: «человек не понимает, что выбрать
    /// тип», — поэтому строка стоит первой, а под ней, пока выбран весь раздел, — подсказка.
    private func карточкаРаздела(_ дерево: ДеревоРазделаФильтров) -> some View {
        let весь = модель.раздел == дерево.верх
        return КарточкаФильтров {
            СтрокаФильтров(подпись: дерево.подпись, значение: дерево.имя(модель.раздел), пусто: "") {
                поле = nil
                применитьНабранное()
                выборРаздела = true
            }
            if весь {
                Text(FilterText.т("x_section_hint"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Дорожки

    /// «Все / Новые / С пробегом» (у техники и товаров «Б/у», у жилья «Новостройка / Вторичка»); «Все» снимает.
    private var дорожкаСостояния: some View {
        let раздел = модель.раздел
        let жильё = ФильтрыЛенты.сделкаДоступна(раздел)
        let варианты = [ВариантДорожкиФильтров(ключ: "", текст: FilterText.т("all"))]
            + СостояниеТовара.allCases.map { с in
                ВариантДорожкиФильтров(ключ: с.rawValue,
                                       текст: (с == .новое && !жильё) ? FilterText.т("x_new_pl") : с.подпись(раздел: раздел))
            }
        let текущее = модель.фильтры.состояние?.rawValue ?? ""
        return ДорожкаФильтров(подпись: FilterText.т("cond"), видна: false, варианты: варианты,
                               выбран: { $0 == текущее }) { ключ in
            применить { ф in ф.состояние = СостояниеТовара(rawValue: ключ) }
        }
    }

    /// «Все / Купить / Снять» мастера жилья (intent). В режиме «Аренда» её нет: там уже intent=rent.
    private var карточкаСделки: some View {
        let варианты = ["", "sale", "rent"].map { к in
            ВариантДорожкиФильтров(ключ: к, текст: FilterText.т(к.isEmpty ? "all" : "deal_" + к))
        }
        let текущая = модель.фильтры.сделка
        return КарточкаФильтров {
            ДорожкаФильтров(подпись: FilterText.т("deal"), видна: false, варианты: варианты,
                            выбран: { $0 == текущая }) { ключ in
                применить { ф in ф.сделка = ключ }
            }
        }
    }

    /// Комнаты — рядом кнопок, несколько сразу (MK_AF_ROOMS: «Студия», 1…4, «5+»).
    private var дорожкаКомнат: some View {
        let варианты = ФильтрыЛенты.всеКомнаты.map { к in
            ВариантДорожкиФильтров(ключ: к, текст: к == "0" ? FilterText.т("studio") : (к == "5" ? "5+" : к))
        }
        let выбранные = модель.фильтры.комнаты
        return ДорожкаФильтров(подпись: FilterText.т("rooms"), видна: true, варианты: варианты,
                               выбран: { выбранные.contains($0) }) { ключ in
            применить { ф in
                if ф.комнаты.contains(ключ) {
                    ф.комнаты.remove(ключ)
                } else {
                    ф.комнаты.insert(ключ)
                }
            }
        }
    }

    // MARK: Строки выбора

    /// Тип запчасти, марка и модель (у запчастей — «Для какой марки»), где помещение (коммерция).
    private var строкиВыбора: [ОписаниеСтрокиФильтров] {
        let раздел = модель.раздел
        let ф = модель.фильтры
        var итог: [ОписаниеСтрокиФильтров] = []
        if ФильтрыЛенты.типДеталиДоступен(раздел) {
            итог.append(ОписаниеСтрокиФильтров(id: "ptype", подпись: FilterText.т("x_part"),
                                               значение: ф.типыДеталей.map { $0.название }.joined(separator: ", "),
                                               пусто: FilterText.т("any_m"), действие: { открытьВыбор(.типДетали) }))
        }
        if ФильтрыЛенты.маркаДоступна(раздел) {
            let запчасти = ФильтрыЛенты.маркаДляЗапчастей(раздел)
            let одна = ф.марки.count == 1
            итог.append(ОписаниеСтрокиФильтров(id: "brand", подпись: FilterText.т(запчасти ? "brand_for" : "brand"),
                                               значение: ф.марки.joined(separator: ", "),
                                               пусто: FilterText.т("any_f"), действие: { открытьВыбор(.марка) }))
            /* Модель без одной марки не выбрать: строка бледная и ведёт к марке, а не в пустой список. */
            итог.append(ОписаниеСтрокиФильтров(id: "model", подпись: FilterText.т(запчасти ? "model_for" : "model"),
                                               значение: одна ? ф.модель : "",
                                               пусто: FilterText.т(одна ? "any_f" : "model_first"),
                                               закрыта: !одна,
                                               действие: { открытьВыбор(одна ? .модель : .марка) }))
        }
        if ФильтрыЛенты.размещениеДоступно(раздел) {
            итог.append(ОписаниеСтрокиФильтров(id: "place", подпись: FilterText.т("place"),
                                               значение: ф.размещение.map { FilterText.т("pl_" + $0) }.joined(separator: ", "),
                                               пусто: FilterText.т("x_any_n"), действие: { открытьВыбор(.размещение) }))
        }
        return итог
    }

    /// «Коробка» и «Топливо» — строками со списком, несколько сразу.
    private var строкиАвто: [ОписаниеСтрокиФильтров] {
        let ф = модель.фильтры
        return [
            ОписаниеСтрокиФильтров(id: "gear", подпись: FilterText.т("gear"),
                                   значение: ф.коробка.map { ФильтрыЛенты.подписьАвто($0) }.joined(separator: ", "),
                                   пусто: FilterText.т("any_f"), действие: { открытьВыбор(.коробка) }),
            ОписаниеСтрокиФильтров(id: "fuel", подпись: FilterText.т("fuel"),
                                   значение: ф.топливо.map { ФильтрыЛенты.подписьАвто($0) }.joined(separator: ", "),
                                   пусто: FilterText.т("x_any_n"), действие: { открытьВыбор(.топливо) })
        ]
    }

    /// Характеристики раздела (фасеты): строка со списком значений. Нет ни одного значения — строки нет, как у сайта.
    private var строкиХарактеристик: [ОписаниеСтрокиФильтров] {
        ФильтрыЛенты.фасеты(модель.раздел).compactMap { фасет -> ОписаниеСтрокиФильтров? in
            let выбранные = модель.фильтры.фасеты[фасет.колонка] ?? []
            if !фасет.электроника
                && ФильтрыЛенты.значенияФасета(фасет.колонка, из: модель.items, выбранные: выбранные).isEmpty {
                return nil
            }
            let значение = выбранные
                .map { фасет.электроника ? ХарактеристикиЭлектроники.показ($0) : $0 }
                .joined(separator: ", ")
            return ОписаниеСтрокиФильтров(id: "f:" + фасет.колонка, подпись: фасет.подпись, значение: значение,
                                          пусто: FilterText.т("any_m"), действие: { открытьВыбор(.фасет(фасет)) })
        }
    }

    // MARK: Числа

    /// Комнаты (жильё), цена, год (не у жилья — там он в «ещё»), пробег, объём, площадь, участок, этаж.
    private var карточкаЧисел: some View {
        let раздел = модель.раздел
        let жильё = ФильтрыЛенты.сделкаДоступна(раздел)
        let аренда = модель.аренда || модель.фильтры.сделка == "rent"
        let ступени = ФильтрыЛенты.ступени(раздел).filter { д in
            /* У новой машины пробега нет — поле прячем, если в нём ничего не набрано (как mkAfCondPick сайта). */
            д != .пробег || модель.фильтры.состояние != .новое
                || !(ступениОт[д] ?? "").isEmpty || !(ступениДо[д] ?? "").isEmpty
        }
        let подписьЦены = FilterText.т(аренда ? "x_rent_price" : "price")
        return КарточкаФильтров {
            if ФильтрыЛенты.комнатыДоступны(раздел) {
                дорожкаКомнат
                ЧертаФильтров()
            }
            ПолеДиапазонаФильтров(подпись: подписьЦены, от: $ценаОт, до: $ценаДо, толькоДо: false, цифр: 12,
                                  дробное: false, фокус: $поле, полеОт: .ценаОт, полеДо: .ценаДо)
            if ФильтрыЛенты.годДоступен(раздел) && !жильё {
                ЧертаФильтров()
                полеГода
            }
            ForEach(ступени, id: \.self) { д in
                ЧертаФильтров()
                полеСтупени(д)
            }
        }
    }

    private var полеГода: some View {
        ПолеДиапазонаФильтров(подпись: ФильтрыЛенты.подписьГода(модель.раздел), от: $годОт, до: $годДо, толькоДо: false,
                              цифр: 4, дробное: false, фокус: $поле, полеОт: .годОт, полеДо: .годДо)
    }

    /// Поле «от — до» ступени; у пробега — одно «до», как у сайта (kmax), пока «от» не задано.
    private func полеСтупени(_ д: ДиапазонФильтра) -> some View {
        let толькоДо = д == .пробег && модель.фильтры.ступениОт[д] == nil && (ступениОт[д] ?? "").isEmpty
        let формат = Self.формат(д)
        return ПолеДиапазонаФильтров(подпись: д.подпись, от: текстСтупени(д, от: true), до: текстСтупени(д, от: false),
                                     толькоДо: толькоДо, цифр: формат.цифр, дробное: формат.дробное, фокус: $поле,
                                     полеОт: .ступеньОт(д), полеДо: .ступеньДо(д))
    }

    /// Сколько знаков и можно ли дробь: объём «1.6», площадь и участок бывают дробными.
    private static func формат(_ д: ДиапазонФильтра) -> (цифр: Int, дробное: Bool) {
        switch д {
        case .пробег:    return (7, false)
        case .двигатель: return (4, true)
        case .площадь:   return (7, true)
        case .участок:   return (7, true)
        case .этаж:      return (3, false)
        }
    }

    private func текстСтупени(_ д: ДиапазонФильтра, от: Bool) -> Binding<String> {
        Binding(
            get: { (от ? ступениОт[д] : ступениДо[д]) ?? "" },
            set: { новое in
                if от {
                    ступениОт[д] = новое
                } else {
                    ступениДо[д] = новое
                }
            }
        )
    }

    // MARK: Техника и характеристики

    /// ОЗУ, накопитель (у телефона — встроенная память), процессор и видеокарта — дорожками «Любая / 8 ГБ+ / …».
    private var карточкаТехники: some View {
        let компьютер = ФильтрыЛенты.видТехники(модель.раздел) == "pc"
        let ф = модель.фильтры
        let озу = [ВариантДорожкиФильтров(ключ: "", текст: FilterText.т("any_f"))]
            + (компьютер ? ФильтрыЛенты.ступениОЗУ : [4, 6, 8, 12]).map { гб in
                ВариантДорожкиФильтров(ключ: String(гб), текст: String(format: FilterText.т("gb_plus"), String(гб)))
            }
        let накопитель = [ВариантДорожкиФильтров(ключ: "", текст: FilterText.т("any_m"))]
            + (компьютер ? ФильтрыЛенты.ступениНакопителя : [128, 256, 512]).map { гб in
                ВариантДорожкиФильтров(ключ: String(гб), текст: ФильтрыЛенты.подписьНакопителя(гб))
            }
        let процессоры = [ВариантДорожкиФильтров(ключ: "", текст: FilterText.т("any_m"))]
            + ФильтрыЛенты.производители.map { к in
                ВариантДорожкиФильтров(ключ: к, текст: ФильтрыЛенты.подписьПроизводителя(к))
            }
        let видеокарты = [ВариантДорожкиФильтров(ключ: "", текст: FilterText.т("any_f")),
                          ВариантДорожкиФильтров(ключ: "1", текст: FilterText.т("x_gpu_disc"))]
        let озуСейчас = ф.озуОт.map { String($0) } ?? ""
        let накопительСейчас = ф.накопительОт.map { String($0) } ?? ""
        let процессорСейчас = ф.процессор
        let видеокартаСейчас = ф.дискретная ? "1" : ""
        return КарточкаФильтров {
            ДорожкаФильтров(подпись: FilterText.т("x_ram"), видна: true, варианты: озу,
                            выбран: { $0 == озуСейчас }) { ключ in
                применить { н in н.озуОт = Int(ключ) }
            }
            ЧертаФильтров()
            ДорожкаФильтров(подпись: FilterText.т(компьютер ? "storage" : "storage_phone"), видна: true,
                            варианты: накопитель, выбран: { $0 == накопительСейчас }) { ключ in
                применить { н in н.накопительОт = Int(ключ) }
            }
            if компьютер {
                ЧертаФильтров()
                ДорожкаФильтров(подпись: FilterText.т("cpu"), видна: true, варианты: процессоры,
                                выбран: { $0 == процессорСейчас }) { ключ in
                    применить { н in н.процессор = ключ }
                }
                ЧертаФильтров()
                ДорожкаФильтров(подпись: FilterText.т("x_gpu"), видна: true, варианты: видеокарты,
                                выбран: { $0 == видеокартаСейчас }) { ключ in
                    применить { н in н.дискретная = ключ == "1" }
                }
            }
        }
    }

    /// Числа электроники (ОЗУ, накопитель из справочника): ступени «от» дорожкой, как _afxESpecs сайта.
    private func карточкаДиапазонов(_ список: [ХарактеристикаЭлектроники]) -> some View {
        КарточкаФильтров {
            ForEach(Array(список.enumerated()), id: \.element) { номер, х in
                if номер > 0 { ЧертаФильтров() }
                дорожкаХарактеристики(х)
            }
        }
    }

    /// «Любая / 8GB+ / 16GB+ …»; «до», заданное прежде, — отдельной кнопкой с «×» (снимает только его).
    private func дорожкаХарактеристики(_ х: ХарактеристикаЭлектроники) -> some View {
        let от = модель.фильтры.характеристикиОт[х.колонка] ?? ""
        let до = модель.фильтры.характеристикиДо[х.колонка]
        let колонка = х.колонка
        let варианты = [ВариантДорожкиФильтров(ключ: "", текст: FilterText.т("any_f"))]
            + х.значения.map { в in ВариантДорожкиФильтров(ключ: в, текст: ХарактеристикиЭлектроники.показ(в) + "+") }
        return VStack(alignment: .leading, spacing: 0) {
            ДорожкаФильтров(подпись: х.подпись, видна: true, варианты: варианты, выбран: { $0 == от }) { ключ in
                применить { ф in ф.характеристикиОт[колонка] = ключ.isEmpty ? nil : ключ }
            }
            if let до {
                Button {
                    применить { ф in ф.характеристикиДо[колонка] = nil }
                } label: {
                    HStack(spacing: 6) {
                        Text(String(format: FilterText.т("to_x"), ХарактеристикиЭлектроники.показ(до)))
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Theme.текст)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 32)
                    .background(КраскиЛистаФильтров.заливка, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .accessibilityLabel(String(format: FilterText.т("remove_a11y"),
                                           String(format: FilterText.т("to_x"), ХарактеристикиЭлектроники.показ(до))))
            }
        }
    }

    // MARK: Жильё и продавец

    /// «Все / Новостройка / Вторичка», год постройки и «Уточнения» (признаки жилья списком по группам).
    private var карточкаЖильяЕщё: some View {
        let раздел = модель.раздел
        let признаки = ФильтрыЛенты.группыПризнаков(раздел, сделка: модель.фильтры.сделка, аренда: модель.аренда)
        let выбранные = признаки.flatMap { $0.признаки }.filter { модель.фильтры.признакиЖилья.contains($0) }
        /* Участку «Новостройка / Вторичка» не показывается — как kd !== 'land' в _afxFormRealty сайта. */
        let состояние = ФильтрыЛенты.состояниеДоступно(раздел) && !РазделыСайта.внутри(раздел, ["land"])
        let год = ФильтрыЛенты.годДоступен(раздел)
        return КарточкаФильтров {
            if состояние { дорожкаСостояния }
            if год {
                if состояние { ЧертаФильтров() }
                полеГода
            }
            if !признаки.isEmpty {
                if состояние || год { ЧертаФильтров() }
                СтрокаФильтров(подпись: FilterText.т("x_tags"),
                               значение: выбранные.map { ФильтрыЛенты.подписьПризнака($0) }.joined(separator: ", "),
                               пусто: FilterText.т("x_any_n")) {
                    открытьВыбор(.признаки)
                }
            }
        }
    }

    /// «Продавец» (у услуг — «Исполнитель»): «Все / Проверенные»; «Фото»: «Все / Только с фото».
    private var карточкаПродавца: some View {
        let услуги = РазделыСайта.корень(модель.раздел) == "services"
        let проверенные = модель.фильтры.толькоПроверенные ? "1" : ""
        let фото = модель.фильтры.сФото ? "1" : ""
        let всё = ВариантДорожкиФильтров(ключ: "", текст: FilterText.т("all"))
        return КарточкаФильтров {
            ДорожкаФильтров(подпись: FilterText.т(услуги ? "x_master" : "seller"), видна: true,
                            варианты: [всё, ВариантДорожкиФильтров(ключ: "1", текст: FilterText.т("verified"))],
                            выбран: { $0 == проверенные }) { ключ in
                применить { ф in ф.толькоПроверенные = ключ == "1" }
            }
            ЧертаФильтров()
            ДорожкаФильтров(подпись: FilterText.т("photo"), видна: true,
                            варианты: [всё, ВариантДорожкиФильтров(ключ: "1", текст: FilterText.т("photo_only"))],
                            выбран: { $0 == фото }) { ключ in
                применить { ф in ф.сФото = ключ == "1" }
            }
        }
    }

    // MARK: Низ

    /// .afx-f: одна зелёная кнопка «Показать N предложений»; ничего не нашлось — серая «Ничего не найдено».
    private var низ: some View {
        let ничего = !модель.грузим && модель.всего == 0
        return Button { готово() } label: {
            подписьПоказать
                .foregroundStyle(ничего ? Theme.текстВторой : КраскиЛистаФильтров.наКнопке)
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(ничего ? КраскиЛистаФильтров.заливка : Theme.акцент,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(ничего)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.поверхность)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.линия).frame(height: 1)
        }
    }

    /// Число — total выдачи под листом (она перезапрашивается тем же запросом при каждом выборе); пока грузится — колесо.
    @ViewBuilder
    private var подписьПоказать: some View {
        if модель.грузим {
            HStack(spacing: 8) {
                Text(FilterText.т("show"))
                    .font(.system(size: 17, weight: .heavy))
                SiteSpinner.мелкийБелый
            }
        } else if let найдено = модель.всего {
            Text(найдено == 0 ? FilterText.т("x_none")
                 : FilterText.т("show") + " " + DesignText.предложений(найдено))
                .font(.system(size: 17, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        } else {
            Text(FilterText.т("show"))
                .font(.system(size: 17, weight: .heavy))
        }
    }

    // MARK: - Действия

    /// Набранные числа строкой — ключ паузы перед применением.
    private var набранное: String {
        let ступени = ДиапазонФильтра.allCases.map { д in (ступениОт[д] ?? "") + "~" + (ступениДо[д] ?? "") }
        return ([ценаОт, ценаДо, годОт, годДо] + ступени).joined(separator: "|")
    }

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
        for д in ДиапазонФильтра.allCases {
            ф.ступениОт[д] = Self.дробь(ступениОт[д])
            ф.ступениДо[д] = Self.дробь(ступениДо[д])
        }
    }

    /// «1,6» и «1.6» — одно число; пусто и ноль — без границы.
    private static func дробь(_ строка: String?) -> Double? {
        guard let строка, let v = Double(строка.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
        return v
    }

    /// «Сбросить» — mkAfReset сайта: всё выбранное и набранное — прочь; порядок остаётся.
    private func сбросить() {
        поле = nil
        ценаОт = ""
        ценаДо = ""
        годОт = ""
        годДо = ""
        ступениОт = [:]
        ступениДо = [:]
        модель.сброситьФильтры()
    }

    /// Выбрали раздел в списке «Раздел»: лента — этого раздела (FeedModel.выбратьРаздел, фильтры прежнего — в память), форма
    /// сразу с его характеристиками. Набранная цена остаётся, как у mkAfPickTCat сайта; год и ступени — нового раздела.
    private func выбратьРазделФильтров(_ ключ: String) {
        поле = nil
        применитьНабранное()
        guard ключ != модель.раздел else { return }
        модель.выбратьРаздел(ключ)
        let н = модель.фильтры
        годОт = н.годОт.map { String($0) } ?? ""
        годДо = н.годДо.map { String($0) } ?? ""
        ступениОт = н.ступениОт.mapValues { ДиапазонФильтра.вЗапрос($0) }
        ступениДо = н.ступениДо.mapValues { ДиапазонФильтра.вЗапрос($0) }
        применитьНабранное()
    }

    /// Список выбора: набранное — сначала в ленту, клавиатура прячется.
    private func открытьВыбор(_ что: ВыборАвтоФильтра) {
        поле = nil
        применитьНабранное()
        выборАвто = что
    }

    /// «Показать» и «×»: набранное — в ленту, лист — закрыть.
    private func готово() {
        поле = nil
        применитьНабранное()
        закрыть()
    }
}

// MARK: - Части формы

/// Карточка .afx-grp: белая полоса во всю ширину на сером фоне.
private struct КарточкаФильтров<Содержимое: View>: View {
    let содержимое: Содержимое

    init(@ViewBuilder _ содержимое: () -> Содержимое) {
        self.содержимое = содержимое()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            содержимое
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность)
    }
}

/// Черта между строками карточки — с отступом слева, как .afx-grp > * + *::before.
private struct ЧертаФильтров: View {
    var body: some View {
        Rectangle()
            .fill(Theme.линия)
            .frame(height: 1)
            .padding(.leading, 16)
            .accessibilityHidden(true)
    }
}

/// Подпись над полями и дорожкой (.afx-lbl).
private struct ПодписьПоляФильтров: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.текст)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Строки выбора одной карточкой, с чертой между ними.
private struct СтрокиФильтров: View {
    let строки: [ОписаниеСтрокиФильтров]

    var body: some View {
        КарточкаФильтров {
            ForEach(Array(строки.enumerated()), id: \.element.id) { номер, с in
                if номер > 0 { ЧертаФильтров() }
                СтрокаФильтров(подпись: с.подпись, значение: с.значение, пусто: с.пусто, закрыта: с.закрыта,
                               действие: с.действие)
            }
        }
    }
}

/// Строка .afx-row: подпись слева, выбранное справа (или «Любая» бледным), шеврон.
private struct СтрокаФильтров: View {
    let подпись: String
    let значение: String
    let пусто: String
    var закрыта = false
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 12) {
                Text(подпись)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(закрыта ? Theme.текстВторой : Theme.текст)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if !значение.isEmpty || !пусто.isEmpty {
                    Text(значение.isEmpty ? пусто : значение)
                        .font(.system(size: 16, weight: значение.isEmpty ? .regular : .medium))
                        .foregroundStyle(значение.isEmpty ? Theme.текстВторой : Theme.текст)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .opacity(0.7)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(подпись)
        .accessibilityValue(значение.isEmpty ? пусто : значение)
    }
}

/// Переключатель в серой дорожке (.afx-seg): выбранный — белым сегментом. Больше шести вариантов — дорожка листается
/// вбок (.afx-seg.is-wide), иначе доли равные.
private struct ДорожкаФильтров: View {
    let подпись: String
    /// Подпись над дорожкой (.afx-lbl); у состояния и сделки её нет — дорожка говорит сама за себя.
    let видна: Bool
    let варианты: [ВариантДорожкиФильтров]
    let выбран: (String) -> Bool
    let нажать: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if видна { ПодписьПоляФильтров(текст: подпись) }
            if варианты.count > 6 {
                ScrollView(.horizontal, showsIndicators: false) {
                    дорожка(широкая: true)
                }
            } else {
                дорожка(широкая: false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(подпись)
    }

    private func дорожка(широкая: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(варианты, id: \.self) { в in
                let вкл = выбран(в.ключ)
                Button { нажать(в.ключ) } label: {
                    Text(в.текст)
                        .font(.system(size: 14, weight: вкл ? .bold : .medium))
                        .foregroundStyle(вкл ? Theme.текст : Theme.текстВторой)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: широкая ? nil : CGFloat.infinity, minHeight: 36)
                        .background {
                            if вкл {
                                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                                    .fill(КраскиЛистаФильтров.сегмент)
                                    .shadow(color: Color.black.opacity(0.10), radius: 1.5, x: 0, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(вкл ? .isSelected : [])
            }
        }
        .padding(2)
        .background(КраскиЛистаФильтров.заливка,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }
}

/// Поля «от — до» (.afx-rng): подпись сверху, два поля рядом; `толькоДо` — одно «до» во всю ширину (пробег).
private struct ПолеДиапазонаФильтров: View {
    let подпись: String
    @Binding var от: String
    @Binding var до: String
    let толькоДо: Bool
    let цифр: Int
    let дробное: Bool
    let фокус: FocusState<ПолеФильтра?>.Binding
    let полеОт: ПолеФильтра
    let полеДо: ПолеФильтра

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ПодписьПоляФильтров(текст: подпись)
            HStack(spacing: 8) {
                if !толькоДо {
                    ПолеЧисла(текст: $от, подсказка: FilterText.т("from"), подпись: подпись + ", " + FilterText.т("from"),
                              цифр: цифр, дробное: дробное, фокус: фокус, своё: полеОт)
                }
                ПолеЧисла(текст: $до, подсказка: FilterText.т("to"), подпись: подпись + ", " + FilterText.т("to"),
                          цифр: цифр, дробное: дробное, фокус: фокус, своё: полеДо)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }
}

/// Поле .afx-in: 44 pt на серой заливке без рамки, в фокусе — рамка акцентом. Только цифры (и одна точка у дробных),
/// не длиннее `цифр`.
private struct ПолеЧисла: View {
    @Binding var текст: String
    let подсказка: String
    let подпись: String
    let цифр: Int
    let дробное: Bool
    let фокус: FocusState<ПолеФильтра?>.Binding
    let своё: ПолеФильтра

    var body: some View {
        TextField(подсказка, text: $текст, prompt: Text(подсказка).foregroundColor(Theme.текстВторой))
            .font(.system(size: 17))
            .foregroundStyle(Theme.текст)
            .tint(Theme.акцент)
            .keyboardType(дробное ? .decimalPad : .numberPad)
            .focused(фокус, equals: своё)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(вФокусе ? Theme.поверхность : КраскиЛистаФильтров.заливка,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(вФокусе ? Theme.акцент : Color.clear, lineWidth: 1)
            }
            .accessibilityLabel(подпись)
            .onChange(of: текст) { _, новое in
                let чистое = ПолеЧисла.очистить(новое, цифр: цифр, дробное: дробное)
                if чистое != новое { текст = чистое }
            }
    }

    private var вФокусе: Bool { фокус.wrappedValue == своё }

    /// Цифры и одна точка (запятая становится точкой), не длиннее `цифр` знаков.
    static func очистить(_ строка: String, цифр: Int, дробное: Bool) -> String {
        var итог = ""
        var точка = false
        for знак in строка {
            if знак.isASCII && знак.isNumber {
                итог.append(знак)
            } else if дробное && !точка && (знак == "." || знак == ",") {
                итог.append(".")
                точка = true
            }
        }
        return String(итог.prefix(цифр))
    }
}

/// Группа вариантов списка выбора: заголовок (.afx-gh; пустой — без него) и варианты.
private struct ГруппаВариантовФильтров: Identifiable {
    let id: String
    let заголовок: String
    let варианты: [ВариантДорожкиФильтров]
}

/// Значения фасета (раздел|колонка), виденные при открытии списка без выбора: выбор сужает выдачу, и при повторном
/// открытии прочие значения брать уже не из чего.
private enum ПамятьЗначенийФасетов {
    static var значения: [String: [String]] = [:]
}

/**
 Список выбора (_afxPick сайта) — лист поверх формы: шапка «‹ Название», поиск сверху, строки во всю ширину с чертой.
 Один вариант (модель) — касание выбирает и возвращает к форме, у выбранной — галочка; несколько (марки, тип запчасти,
 коробка, топливо, размещение, уточнения, характеристики) — квадратные флажки и внизу «Готово». Как у сайта, выбор сразу
 уходит в ленту (FeedModel.применитьФильтры). Марки — «Любая», «Популярные» и «Все марки» по алфавиту; справочник —
 /api/auto_models.php через загрузчик подачи (СправочникМарокФильтров).
 */
private struct ЛистМаркиМодели: View {
    @ObservedObject private var лента: FeedModel
    @ObservedObject private var справочник: ПодачаМодель
    private let что: ВыборАвтоФильтра
    @Environment(\.dismiss) private var закрыть
    @State private var поиск = ""
    /// Модели выбранной марки; nil — ещё грузятся.
    @State private var модели: [МодельАвто]? = nil
    /// Справочник типов деталей не пришёл — «Повторить».
    @State private var деталиНеПришли = false
    /// Значения фасета на момент открытия списка: выдача сужается после каждого флажка, и строить варианты из неё
    /// заново нельзя — после «M» остался бы один «M» и второй размер не отметить.
    @State private var значенияФасетаПриОткрытии: [String]

    init(лента: FeedModel, что: ВыборАвтоФильтра) {
        _лента = ObservedObject(wrappedValue: лента)
        _справочник = ObservedObject(wrappedValue: СправочникМарокФильтров.общий)
        self.что = что
        var снимок: [String] = []
        if case .фасет(let фасет) = что, !фасет.электроника {
            let выбранные = лента.фильтры.фасеты[фасет.колонка] ?? []
            снимок = ФильтрыЛенты.значенияФасета(фасет.колонка, из: лента.items, выбранные: выбранные)
            /* Открыли снова, когда выбор уже сузил выдачу: к ней — значения, виденные без выбора в этом разделе. */
            let ключ = лента.раздел + "|" + фасет.колонка
            if выбранные.isEmpty {
                ПамятьЗначенийФасетов.значения[ключ] = снимок
            } else {
                for в in (ПамятьЗначенийФасетов.значения[ключ] ?? [])
                where !снимок.contains(where: { $0.lowercased() == в.lowercased() }) {
                    снимок.append(в)
                }
            }
        }
        _значенияФасетаПриОткрытии = State(initialValue: снимок)
    }

    var body: some View {
        VStack(spacing: 0) {
            шапка
            if let подсказка = подсказкаПоиска {
                ПоискМастераПодачи(подсказка, текст: $поиск)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 12)
                    .background(Theme.поверхность)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.линия).frame(height: 1)
                    }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    список
                }
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.поверхность)
            if что != .модель { низ }
        }
        .background(Theme.поверхность)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.поверхность)
        .presentationCornerRadius(Theme.Радиус.xl)
        .task { await загрузить() }
    }

    private var заголовок: String {
        let запчасти = ФильтрыЛенты.маркаДляЗапчастей(лента.раздел)
        switch что {
        case .марка:        return FilterText.т(запчасти ? "brand_for" : "brand")
        case .модель:       return FilterText.т(запчасти ? "model_for" : "model")
        case .типДетали:    return FilterText.т("x_part")
        case .коробка:      return FilterText.т("gear")
        case .топливо:      return FilterText.т("fuel")
        case .размещение:   return FilterText.т("place")
        case .признаки:     return FilterText.т("x_tags")
        case .фасет(let ф): return ф.подпись
        }
    }

    /// Поиск — у длинных списков: марки, модели, типы деталей, характеристики больше десяти значений.
    private var подсказкаПоиска: String? {
        switch что {
        case .марка:     return FilterText.т("brand_find")
        case .модель:    return FilterText.т("model_find")
        case .типДетали: return FilterText.т("part_find")
        case .фасет:     return (группыВариантов.first?.варианты.count ?? 0) > 10 ? FilterText.т("x_find") : nil
        case .коробка, .топливо, .размещение, .признаки: return nil
        }
    }

    /// .afx-h списка: «‹» слева, название посередине.
    private var шапка: some View {
        ZStack {
            Text(заголовок)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .padding(.horizontal, 56)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                Button { закрыть() } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(FilterText.т("x_back"))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(Theme.поверхность)
    }

    @ViewBuilder
    private var список: some View {
        switch что {
        case .марка:     списокМарок
        case .модель:    списокМоделей
        case .типДетали: списокДеталей
        case .коробка, .топливо, .размещение, .признаки, .фасет: списокПростой
        }
    }

    // MARK: Марки

    @ViewBuilder
    private var списокМарок: some View {
        if справочник.маркиАвто.isEmpty && справочник.маркиНеДоступны {
            заметка(FilterText.т("brands_fail"))
            кнопкаПовтора {
                Task { await справочник.загрузитьМарки() }
            }
        } else if справочник.маркиАвто.isEmpty {
            загрузка(FilterText.т("brand_load"))
        } else if !чистыйПоиск.isEmpty {
            let найденные = справочник.маркиАвто.filter { $0.lowercased().contains(чистыйПоиск) }
            if найденные.isEmpty { заметка(FilterText.т("brand_none")) }
            ForEach(найденные, id: \.self) { марка in строкаМарки(марка) }
        } else {
            строка(FilterText.т("any_f"), выбрана: лента.фильтры.марки.isEmpty, несколько: false) {
                изменить { ф in
                    ф.марки = []
                    ф.модель = ""
                }
            }
            let популярные = популярныеМарки
            if популярные.count >= 4 {
                подписьГруппы(FilterText.т("popular"))
                ForEach(популярные, id: \.self) { марка in строкаМарки(марка) }
            }
            подписьГруппы(FilterText.т("all_brands"))
            ForEach(маркиПоАлфавиту, id: \.self) { марка in строкаМарки(марка) }
        }
    }

    /// «Популярные» — те же частые марки Казахстана, что наверху сетки мастера авто подачи, если они есть в справочнике.
    private var популярныеМарки: [String] {
        var поНижнему: [String: String] = [:]
        for м in справочник.маркиАвто where поНижнему[м.lowercased()] == nil { поНижнему[м.lowercased()] = м }
        return МастерАвтоВид.популярные.compactMap { поНижнему[$0.lowercased()] }
    }

    private var маркиПоАлфавиту: [String] {
        справочник.маркиАвто.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func строкаМарки(_ марка: String) -> some View {
        строка(марка, марка: марка, выбрана: лента.фильтры.марки.contains(марка), несколько: true) {
            изменить { ф in ФильтрыЛенты.переключитьМарку(марка, в: &ф) }
        }
    }

    // MARK: Модели

    @ViewBuilder
    private var списокМоделей: some View {
        if let модели {
            if модели.isEmpty {
                заметка(FilterText.т("model_none"))
            } else {
                let найденные = чистыйПоиск.isEmpty ? модели
                    : модели.filter { $0.имя.lowercased().contains(чистыйПоиск) }
                if чистыйПоиск.isEmpty {
                    строка(FilterText.т("any_f"), выбрана: лента.фильтры.модель.isEmpty, несколько: false) {
                        выбратьМодель("")
                    }
                }
                if найденные.isEmpty { заметка(FilterText.т("nothing_found")) }
                ForEach(найденные) { м in
                    строка(м.имя, пояснение: м.годыВыпуска(сейчас: МастерПодачиText.т("aw_now")),
                           выбрана: лента.фильтры.модель == м.имя, несколько: false) { выбратьМодель(м.имя) }
                }
            }
        } else {
            загрузка(FilterText.т("model_load"))
        }
    }

    // MARK: Типы деталей

    /// Справочник /api/parts_types.php (тот же, что «Что за деталь» подачи); несколько сразу, «Любой» снимает все.
    @ViewBuilder
    private var списокДеталей: some View {
        let все = справочник.типыЗапчастей
        if все.isEmpty && деталиНеПришли {
            заметка(FilterText.т("brands_fail"))
            кнопкаПовтора {
                деталиНеПришли = false
                Task { await загрузитьДетали() }
            }
        } else if все.isEmpty {
            загрузка(FilterText.т("part_load"))
        } else {
            let найденные = чистыйПоиск.isEmpty ? все : все.filter { $0.подпись.lowercased().contains(чистыйПоиск) }
            if чистыйПоиск.isEmpty {
                строка(FilterText.т("any_m"), выбрана: лента.фильтры.типыДеталей.isEmpty, несколько: false) {
                    изменить { ф in ф.типыДеталей = [] }
                }
            }
            if найденные.isEmpty { заметка(FilterText.т("part_none")) }
            ForEach(найденные, id: \.self) { тип in
                строка(тип.подпись, выбрана: лента.фильтры.типыДеталей.contains(where: { $0.ключ == тип.ключ }),
                       несколько: true) {
                    изменить { ф in
                        if ф.типыДеталей.contains(where: { $0.ключ == тип.ключ }) {
                            ф.типыДеталей.removeAll { $0.ключ == тип.ключ }
                        } else {
                            ф.типыДеталей.append(ТипДеталиФильтра(ключ: тип.ключ, название: тип.подпись))
                        }
                    }
                }
            }
        }
    }

    private func загрузитьДетали() async {
        await справочник.загрузитьТипыЗапчастей()
        if справочник.типыЗапчастей.isEmpty { деталиНеПришли = true }
    }

    private func выбратьМодель(_ имя: String) {
        изменить { ф in ф.модель = имя }
        закрыть()
    }

    // MARK: Коробка, топливо, размещение, уточнения, характеристики

    private var группыВариантов: [ГруппаВариантовФильтров] {
        switch что {
        case .коробка:
            return [ГруппаВариантовФильтров(id: "g", заголовок: "", варианты: ФильтрыЛенты.всеКоробки.map { в in
                ВариантДорожкиФильтров(ключ: в, текст: ФильтрыЛенты.подписьАвто(в))
            })]
        case .топливо:
            return [ГруппаВариантовФильтров(id: "g", заголовок: "", варианты: ФильтрыЛенты.всеВидыТоплива.map { в in
                ВариантДорожкиФильтров(ключ: в, текст: ФильтрыЛенты.подписьАвто(в))
            })]
        case .размещение:
            return [ГруппаВариантовФильтров(id: "g", заголовок: "", варианты: ФильтрыЛенты.всеРазмещения.map { в in
                ВариантДорожкиФильтров(ключ: в, текст: FilterText.т("pl_" + в))
            })]
        case .признаки:
            let группы = ФильтрыЛенты.группыПризнаков(лента.раздел, сделка: лента.фильтры.сделка, аренда: лента.аренда)
            return группы.map { г in
                ГруппаВариантовФильтров(id: г.ключ, заголовок: FilterText.т(г.ключ), варианты: г.признаки.map { в in
                    ВариантДорожкиФильтров(ключ: в, текст: ФильтрыЛенты.подписьПризнака(в))
                })
            }
        case .фасет(let фасет):
            let выбранные = лента.фильтры.фасеты[фасет.колонка] ?? []
            let значения = фасет.электроника
                ? выбранные.filter { !фасет.значения.contains($0) } + фасет.значения
                : значенияФасетаПриОткрытии + выбранные.filter { в in
                    !значенияФасетаПриОткрытии.contains { $0.lowercased() == в.lowercased() }
                }
            return [ГруппаВариантовФильтров(id: "g", заголовок: "", варианты: значения.map { в in
                ВариантДорожкиФильтров(ключ: в, текст: фасет.электроника ? ХарактеристикиЭлектроники.показ(в) : в)
            })]
        case .марка, .модель, .типДетали:
            return []
        }
    }

    /// Флажки по группам; сверху «Не важно» — снимает всё отмеченное в этом списке.
    @ViewBuilder
    private var списокПростой: some View {
        let группы = группыВариантов
        let q = чистыйПоиск
        if q.isEmpty {
            строка(FilterText.т("any_v"), выбрана: !группы.contains { г in г.варианты.contains { выбранПростой($0.ключ) } },
                   несколько: false) {
                снятьПростые()
            }
        }
        ForEach(группы) { г in
            let видимые = q.isEmpty ? г.варианты : г.варианты.filter { $0.текст.lowercased().contains(q) }
            if !видимые.isEmpty {
                if !г.заголовок.isEmpty { подписьГруппы(г.заголовок) }
                ForEach(видимые, id: \.self) { в in
                    строка(в.текст, выбрана: выбранПростой(в.ключ), несколько: true) {
                        переключитьПростой(в.ключ)
                    }
                }
            }
        }
        if !q.isEmpty && !группы.contains(where: { г in г.варианты.contains { $0.текст.lowercased().contains(q) } }) {
            заметка(FilterText.т("nothing_found"))
        }
    }

    private func выбранПростой(_ ключ: String) -> Bool {
        let ф = лента.фильтры
        switch что {
        case .коробка:          return ф.коробка.contains(ключ)
        case .топливо:          return ф.топливо.contains(ключ)
        case .размещение:       return ф.размещение.contains(ключ)
        case .признаки:         return ф.признакиЖилья.contains(ключ)
        case .фасет(let фасет): return (ф.фасеты[фасет.колонка] ?? []).contains(ключ)
        case .марка, .модель, .типДетали: return false
        }
    }

    private func переключитьПростой(_ ключ: String) {
        let выбор = что
        изменить { ф in
            switch выбор {
            case .коробка:    ФильтрыЛенты.переключить(ключ, в: &ф.коробка)
            case .топливо:    ФильтрыЛенты.переключить(ключ, в: &ф.топливо)
            case .размещение: ФильтрыЛенты.переключить(ключ, в: &ф.размещение)
            case .признаки:   ФильтрыЛенты.переключить(ключ, в: &ф.признакиЖилья)
            case .фасет(let фасет):
                var список = ф.фасеты[фасет.колонка] ?? []
                ФильтрыЛенты.переключить(ключ, в: &список)
                ф.фасеты[фасет.колонка] = список.isEmpty ? nil : список
            case .марка, .модель, .типДетали:
                break
            }
        }
    }

    /// «Не важно»: снять отмеченное в этом списке (у уточнений — только признаки его групп).
    private func снятьПростые() {
        let выбор = что
        let ключиГрупп = Set(группыВариантов.flatMap { г in г.варианты.map { $0.ключ } })
        изменить { ф in
            switch выбор {
            case .коробка:          ф.коробка = []
            case .топливо:          ф.топливо = []
            case .размещение:       ф.размещение = []
            case .признаки:         ф.признакиЖилья.removeAll { ключиГрупп.contains($0) }
            case .фасет(let фасет): ф.фасеты[фасет.колонка] = nil
            case .марка, .модель, .типДетали:
                break
            }
        }
    }

    // MARK: Части

    /// .afx-f с одной зелёной «Готово» — у списков, где выбирают несколько.
    private var низ: some View {
        Button { закрыть() } label: {
            Text(FilterText.т("done"))
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(КраскиЛистаФильтров.наКнопке)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.акцент, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Theme.поверхность)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.линия).frame(height: 1)
        }
    }

    /// Строка .afx-opt: у марки слева — её знак с сайта (30 pt; нет знака — две буквы), у модели под названием — годы
    /// выпуска; справа — квадратный флажок (`несколько`) или галочка у выбранной.
    private func строка(_ текст: String, марка: String? = nil, пояснение: String = "", выбрана: Bool,
                        несколько: Bool, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            HStack(spacing: 12) {
                if let марка {
                    ЗнакМаркиСайта(марка, размер: 30) {
                        Text(ЛоготипыМарокСайта.буквы(марка))
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color(red: 0x5f / 255, green: 0x6c / 255, blue: 0x63 / 255))
                            .frame(width: 30, height: 30)
                            .background(Color.white, in: Circle())
                            .overlay { Circle().strokeBorder(Theme.линия, lineWidth: 1) }
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(текст)
                        .font(.system(size: 16, weight: выбрана ? .semibold : .regular))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    if !пояснение.isEmpty {
                        Text(пояснение)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if несколько {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(выбрана ? Theme.акцент : Color.clear)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(выбрана ? Theme.акцент : Theme.линия, lineWidth: 1.5)
                        if выбрана {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(КраскиЛистаФильтров.наКнопке)
                        }
                    }
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                } else if выбрана {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay(alignment: .bottom) { ЧертаФильтров() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбрана ? .isSelected : [])
    }

    /// Заголовок группы списка (.afx-gh): заглавными серым на сером фоне.
    private func подписьГруппы(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 13, weight: .bold))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(Theme.текстВторой)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(КраскиЛистаФильтров.фон)
            .accessibilityAddTraits(.isHeader)
    }

    private func заметка(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 14))
            .foregroundStyle(Theme.текстВторой)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
    }

    private func кнопкаПовтора(_ действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Text(FilterText.т("retry"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .frame(minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private func загрузка(_ текст: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(текст)
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Действия

    private var чистыйПоиск: String { поиск.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

    /// Выбор — сразу в ленту, как у сайта: каждое нажатие мастера перерисовывает выдачу.
    private func изменить(_ правка: (inout ФильтрыЛенты) -> Void) {
        var новые = лента.фильтры
        правка(&новые)
        лента.применитьФильтры(новые)
    }

    /// Марки — из общего справочника (второй раз не спрашиваются); модели — только одной выбранной марки.
    private func загрузить() async {
        switch что {
        case .марка:
            await справочник.загрузитьМарки()
        case .модель:
            let марки = лента.фильтры.марки
            guard марки.count == 1, let марка = марки.first else {
                модели = []
                return
            }
            модели = await справочник.моделиМарки(марка)
        case .типДетали:
            await загрузитьДетали()
        case .коробка, .топливо, .размещение, .признаки, .фасет:
            break
        }
    }
}

// MARK: - Раздел в форме

/// Пункт списка «Раздел»: ключ дерева сайта и имя на языке приложения.
private struct ПунктРазделаФильтров: Hashable {
    let ключ: String
    let имя: String
}

/**
 Дерево списка «Раздел» — как _afxListTCat и _afxListTree сайта: «Все …» (корень), дальше группы жирной строкой и под
 каждой её подразделы. У «Товаров» (MK_VSETS.goods) группы — разделы набора. Имена — из справочника разделов на языке
 приложения (ЗагрузкаКаталогаПоиска); справочника нет, у корня нет детей или это «Работа» (у неё своё окно) — строки нет.
 */
private struct ДеревоРазделаФильтров {
    struct Группа: Identifiable {
        let id: String
        let имя: String
        let дети: [ПунктРазделаФильтров]
    }

    /// Корень формы: раздел дерева или «goods».
    let верх: String
    let группы: [Группа]
    private let имена: [String: String]

    @MainActor
    static func для(_ раздел: String) -> ДеревоРазделаФильтров? {
        guard !раздел.isEmpty, let каталог = ЗагрузкаКаталогаПоиска.сейчас else { return nil }
        let корень = РазделыСайта.корень(раздел)
        guard корень != "jobs" else { return nil }
        let товары = раздел == "goods" || ListingsAPI.наборТоваров.contains(корень)
        let верх = товары ? "goods" : корень
        var детиУзла: [String: [String]] = [:]
        var имена: [String: String] = [:]
        for ключ in каталог.порядок {
            guard let узел = каталог.узлы[ключ] else { continue }
            имена[ключ] = узел.имя
            if let родитель = узел.родитель { детиУзла[родитель, default: []].append(ключ) }
        }
        let головы = товары ? ListingsAPI.наборТоваров : (детиУзла[верх] ?? [])
        let группы = головы.compactMap { г -> Группа? in
            guard let имя = имена[г] else { return nil }
            let дети = (детиУзла[г] ?? []).compactMap { к in имена[к].map { ПунктРазделаФильтров(ключ: к, имя: $0) } }
            return Группа(id: г, имя: имя, дети: дети)
        }
        guard !группы.isEmpty else { return nil }
        return ДеревоРазделаФильтров(верх: верх, группы: группы, имена: имена)
    }

    /// Подпись строки: «Раздел», у услуг — «Вид услуги», у животных — «Вид» (AFX_TREE сайта).
    var подпись: String {
        switch верх {
        case "services": return FilterText.т("x_svc_kind")
        case "animals":  return FilterText.т("x_pet_kind")
        default:         return FilterText.т("x_section")
        }
    }

    /// «Вся электроника», «Весь транспорт»… — корень целиком; у прочих корней — его имя.
    var всё: String {
        switch верх {
        case "electronics": return FilterText.т("x_all_tech")
        case "transport":   return FilterText.т("x_all_transport")
        case "services":    return FilterText.т("x_all_svc")
        case "animals":     return FilterText.т("x_all_pets")
        case "goods":       return FilterText.т("x_all_goods")
        default:            return имена[верх] ?? FilterText.т("all")
        }
    }

    func имя(_ раздел: String) -> String {
        раздел == верх ? всё : (имена[раздел] ?? раздел)
    }
}

/// Список «Раздел» поверх формы (_afxPick сайта): «‹ Раздел», поиск, «Все …», группы и подразделы. Касание выбирает
/// раздел и возвращает к форме — она уже с характеристиками выбранного.
private struct ЛистРазделаФильтров: View {
    let дерево: ДеревоРазделаФильтров
    let текущий: String
    let выбрать: (String) -> Void
    @Environment(\.dismiss) private var закрыть
    @State private var поиск = ""

    var body: some View {
        VStack(spacing: 0) {
            шапка
            ПоискМастераПодачи(FilterText.т("x_section_find"), текст: $поиск)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .background(Theme.поверхность)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.линия).frame(height: 1)
                }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    список
                }
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.поверхность)
        }
        .background(Theme.поверхность)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.поверхность)
        .presentationCornerRadius(Theme.Радиус.xl)
    }

    private var шапка: some View {
        ZStack {
            Text(дерево.подпись)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .padding(.horizontal, 56)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                Button { закрыть() } label: {
                    Image(systemName: "chevron.backward")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(FilterText.т("x_back"))
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(Theme.поверхность)
    }

    private var чистыйПоиск: String {
        поиск.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// С поиском — плоский список совпавших (группы и подразделы), без — дерево.
    @ViewBuilder
    private var список: some View {
        let запрос = чистыйПоиск
        if !запрос.isEmpty {
            let найденные = дерево.группы.flatMap { г in [ПунктРазделаФильтров(ключ: г.id, имя: г.имя)] + г.дети }
                .filter { $0.имя.lowercased().contains(запрос) }
            if найденные.isEmpty {
                Text(FilterText.т("x_section_none"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            ForEach(найденные, id: \.self) { п in строка(п.имя, ключ: п.ключ, уровень: 2) }
        } else {
            строка(дерево.всё, ключ: дерево.верх, уровень: 0)
            ForEach(дерево.группы) { г in
                Rectangle()
                    .fill(КраскиЛистаФильтров.фон)
                    .frame(height: 10)
                    .accessibilityHidden(true)
                строка(г.имя, ключ: г.id, уровень: 1)
                ForEach(г.дети, id: \.self) { п in строка(п.имя, ключ: п.ключ, уровень: 2) }
            }
        }
    }

    /// Уровень 0 — «Все …» со значком, 1 — группа жирной строкой (.is-grp), 2 — подраздел с отступом (.is-sub).
    private func строка(_ имя: String, ключ: String, уровень: Int) -> some View {
        let выбрана = ключ == текущий
        return Button {
            выбрать(ключ)
            закрыть()
        } label: {
            HStack(spacing: 12) {
                if уровень == 0 {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.акцент)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                }
                Text(имя)
                    .font(.system(size: 16, weight: (уровень < 2 || выбрана) ? .semibold : .regular))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if выбрана {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, уровень == 2 ? 32 : 16)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .overlay(alignment: .bottom) { ЧертаФильтров() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбрана ? .isSelected : [])
    }
}

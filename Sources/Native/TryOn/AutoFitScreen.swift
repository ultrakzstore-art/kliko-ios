import SwiftUI
import UIKit

/**
 «ПОДОЙДУТ ЛИ?» — ОКНО (владелец 13.10.2026: «распиши примерочную; нужен ли 3D — очки, шины, диски?» → «нужнее охват
 всего»).

 Вход один — хаб «Примерить / проверить» на странице объявления (TryOnHub.swift): у раздела «Шины и диски» кнопка
 «Подойдут ли?» (рубильник Config.автоПодбор), по нажатию хаб зовёт ОкноАвтоПодбора.открыть(товар:). Окно — лист во всю
 высоту поверх страницы (ПоверхВсего), в своей навигации:
   · «В объявлении» — что поняли из объявления: размер шин, сезон, R, J, PCD, ET, DIA, «продавец пишет: подходит к …»;
     не поняли или поняли не так — «Указать параметры» / «Исправить» (ПараметрыТовараАвтоподбора);
   · «Моя машина» — марка, модель, год из справочника (марки → модели → год) и параметры посадки: из справочника
     сервера или свои («на наклейке в проёме двери водителя или в инструкции»); запоминается на телефоне;
   · итог крупно и цветом: «Подходят ✓», «Подойдут с проставками / кольцами», «Не хватает данных», «Подойдут, но
     проверьте», «Не подходят» — и причины по пунктам (AutoFitMath.swift); у шин — сравнение со штатным размером;
   · «Сравнить размеры» — калькулятор шин (AutoFitCalc.swift), доступен всегда.
 Всё считается на телефоне; сервер — только справочник машин (AutoFitCar.swift, docs/SERVER_AUTOFIT.md). Тёмная тема —
 краски Theme; тексты растут с «Размером текста»; VoiceOver читает итог и каждый пункт целиком (уровень, что, почему);
 при «Уменьшении движения» итог появляется без пружины; RTL — ведущие края и стрелки «вперёд».
 */
@MainActor
enum ОкноАвтоПодбора {
    /// Открыть «Подойдут ли?» для объявления шин или дисков. Зовёт хаб (ПодборПримерки.открыть).
    static func открыть(товар: Listing) {
        guard Config.автоПодбор else { return }
        ПоверхВсего.показать(большой: true) { закрыть in
            ЭкранАвтоподбора(товар: товар, закрыть: закрыть)
        }
    }
}

/// Куда ведёт навигация окна.
enum ШагАвтоподбора: Hashable {
    case марка
    case модель(String)
    case год(String, String)
    case параметрыМашины
    case параметрыТовара
    case калькулятор
}

// MARK: - Модель окна

@MainActor
final class МодельАвтоподбора: ObservableObject {
    let товар: Listing
    /// Что поняли из объявления — до правок человека.
    let исходный: РазборАвтоподбора
    @Published private(set) var разбор: РазборАвтоподбора
    /// Человек поправил параметры товара.
    @Published private(set) var правлен = false
    @Published var путь: [ШагАвтоподбора] = []
    /// Какой размер шин товара сверяем (у разноширокого комплекта их два).
    @Published var размерТовара: РазмерШиныАвтоподбора?
    /// С каким штатным размером сравниваем; nil — подбираем сами (тот же посадочный диаметр или ближайший).
    @Published var штатныйВыбран: РазмерШиныАвтоподбора? = nil

    init(товар: Listing) {
        self.товар = товар
        let р = РазборАвтоподбора.из(товар)
        исходный = р
        разбор = р
        размерТовара = р.шины.first
    }

    /// Правка параметров товара человеком.
    func применить(_ новый: РазборАвтоподбора) {
        разбор = новый
        правлен = новый != исходный
        if let был = размерТовара, новый.шины.contains(был) { return }
        размерТовара = новый.шины.first
    }

    func вернутьИсходный() {
        применить(исходный)
    }

    /// Штатный размер для сравнения: выбранный человеком или подобранный.
    func штатный(_ посадка: ПосадкаАвтоподбора) -> РазмерШиныАвтоподбора? {
        if let выбран = штатныйВыбран, посадка.шины.contains(выбран) { return выбран }
        return СверкаАвтоподбора.штатныйДля(размерТовара, из: посадка.шины)
    }

    func вердикт(_ посадка: ПосадкаАвтоподбора?) -> ВердиктАвтоподбора? {
        guard let посадка else { return nil }
        return СверкаАвтоподбора.вердикт(разбор: разбор, размер: размерТовара, штатный: штатный(посадка),
                                         посадка: посадка)
    }

    /// Начальные размеры калькулятора: «было» — штатный машины, «стало» — шина из объявления. Чего нет — 205/55 R16.
    func размерыКалькулятора(_ посадка: ПосадкаАвтоподбора?) -> (было: РазмерШиныАвтоподбора, стало: РазмерШиныАвтоподбора) {
        let запасной = РазмерШиныАвтоподбора(ширина: 205, профиль: 55, диаметр: 16)
        let стало = размерТовара ?? посадка.flatMap { штатный($0) } ?? запасной
        let было = посадка.flatMap { штатный($0) } ?? стало
        return (было, стало)
    }
}

// MARK: - Краски и значки уровней

extension УровеньАвтоподбора {
    /// Значок пункта.
    var значок: String {
        switch self {
        case .подходит: return "checkmark.circle.fill"
        case .доработка: return "wrench.and.screwdriver.fill"
        case .неизвестно: return "questionmark.circle.fill"
        case .проверить: return "exclamationmark.triangle.fill"
        case .неПодходит: return "xmark.octagon.fill"
        }
    }

    /// Значок итога — у «подходят» печать с галочкой.
    var значокИтога: String { self == .подходит ? "checkmark.seal.fill" : значок }

    /// Краска значка на поверхности (своя в тёмной теме).
    var краска: Color {
        switch self {
        case .подходит: return Theme.зелёный2
        case .доработка: return Theme.цвет(0x1677C9, 0x5AB0F5)
        case .неизвестно: return Theme.текстВторой
        case .проверить: return Theme.цвет(0xC2410C, 0xFB923C)
        case .неПодходит: return Theme.цвет(0xDC2626, 0xF87171)
        }
    }

    /// Заливка карточки итога: белый текст на ней читается в обеих темах (контраст не ниже 4,5).
    var заливка: [Color] {
        switch self {
        case .подходит: return [Color(uiColor: Theme.hex(0x16803C)), Color(uiColor: Theme.hex(0x0F5132))]
        case .доработка: return [Color(uiColor: Theme.hex(0x1677C9)), Color(uiColor: Theme.hex(0x0B4F8A))]
        case .неизвестно: return [Color(uiColor: Theme.hex(0x5F6C63)), Color(uiColor: Theme.hex(0x3B4540))]
        case .проверить: return [Color(uiColor: Theme.hex(0xC2410C)), Color(uiColor: Theme.hex(0x9A3412))]
        case .неПодходит: return [Color(uiColor: Theme.hex(0xDC2626)), Color(uiColor: Theme.hex(0x991B1B))]
        }
    }
}

extension View {
    /// Карточка окна «Подойдут ли?»: поверхность, тонкая линия, скругление как у карточек сайта.
    func карточкаАвтоподбора() -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
    }
}

// MARK: - Окно

struct ЭкранАвтоподбора: View {
    let закрыть: () -> Void
    @StateObject private var модель: МодельАвтоподбора
    @ObservedObject private var гараж = ГаражАвтоподбора.shared

    init(товар: Listing, закрыть: @escaping () -> Void) {
        self.закрыть = закрыть
        _модель = StateObject(wrappedValue: МодельАвтоподбора(товар: товар))
    }

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    var body: some View {
        NavigationStack(path: $модель.путь) {
            ГлавнаяАвтоподбора(модель: модель, гараж: гараж)
                .navigationTitle(т("af_title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(т("af_close"), action: закрыть)
                    }
                }
                .navigationDestination(for: ШагАвтоподбора.self) { шаг in
                    ЭкранШагаАвтоподбора(шаг: шаг, модель: модель, гараж: гараж)
                }
        }
        .tint(Theme.акцент)
        .onAppear { гараж.подготовить() }
    }
}

/// Главная страница окна: товар, машина, итог, калькулятор, пометка.
struct ГлавнаяАвтоподбора: View {
    @ObservedObject var модель: МодельАвтоподбора
    @ObservedObject var гараж: ГаражАвтоподбора

    init(модель: МодельАвтоподбора, гараж: ГаражАвтоподбора) {
        self.модель = модель
        self.гараж = гараж
    }

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    private var вердикт: ВердиктАвтоподбора? { модель.вердикт(гараж.посадка) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                КарточкаТовараАвтоподбора(модель: модель)
                КарточкаМашиныАвтоподбора(модель: модель, гараж: гараж)
                итог
                ЗелёнаяКнопкаФото(заголовок: т("af_compare"), значок: "arrow.left.arrow.right", контурная: true) {
                    ОткликСайта.выбор()
                    модель.путь.append(.калькулятор)
                }
                .accessibilityHint(т("af_compare_hint"))
                Text(т("af_note"))
                    .font(.footnote)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            .animation(ДвижениеСайта.смена, value: вердикт)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .onChange(of: вердикт?.уровень) { старый, новый in
            guard let новый, старый != новый else { return }
            switch новый {
            case .подходит: ОткликСайта.успех()
            case .неПодходит: ОткликСайта.предупреждение()
            case .доработка, .неизвестно, .проверить: break
            }
            if let в = вердикт {
                UIAccessibility.post(notification: .announcement, argument: в.заголовок)
            }
        }
    }

    @ViewBuilder
    private var итог: some View {
        if let в = вердикт, let посадка = гараж.посадка {
            VStack(spacing: 12) {
                КарточкаВердиктаАвтоподбора(вердикт: в)
                if в.сравнение != nil && посадка.шины.count > 1 {
                    ВыборШтатногоАвтоподбора(модель: модель, штатные: посадка.шины, текущий: модель.штатный(посадка))
                }
                ПунктыАвтоподбора(вердикт: в) {
                    модель.путь.append(.параметрыМашины)
                }
            }
            .transition(.opacity)
        } else if модель.разбор.вид == nil && гараж.посадка != nil {
            /* Машина есть, а что за товар — не поняли: сверять не с чем, просим указать. */
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text(т("af_kind_unknown"))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: УровеньАвтоподбора.неизвестно.значок)
                        .foregroundStyle(УровеньАвтоподбора.неизвестно.краска)
                }
                .font(.subheadline)
                .foregroundStyle(Theme.текст)
                МалаяКнопкаАвтоподбора(заголовок: т("af_item_set"), значок: "pencil") {
                    модель.путь.append(.параметрыТовара)
                }
            }
            .карточкаАвтоподбора()
            .transition(.opacity)
        }
    }
}

// MARK: - Карточка товара

/// «В объявлении»: фото, название, что поняли (фишками), «продавец пишет», «Исправить».
struct КарточкаТовараАвтоподбора: View {
    @ObservedObject var модель: МодельАвтоподбора
    @ScaledMetric(relativeTo: .body) private var фото: CGFloat = 56

    init(модель: МодельАвтоподбора) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    private var р: РазборАвтоподбора { модель.разбор }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            шапка
            if р.пустой {
                Text(т("af_item_empty"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !р.пустой || р.сезон != nil {
                фишки
            }
            if !р.продавец.пустая {
                Label {
                    Text(String(format: т("af_seller_fits"), р.продавец.подпись))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "quote.bubble")
                        .foregroundStyle(Theme.акцент)
                }
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
            }
            кнопки
        }
        .карточкаАвтоподбора()
    }

    private var шапка: some View {
        HStack(alignment: .top, spacing: 12) {
            КартинкаЛенты(модель.товар.обложка, пунктов: фото) {
                Theme.поверхность2
            }
            .frame(width: фото, height: фото)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(р.вид?.название ?? т("af_item_title"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.акцент)
                    .textCase(.uppercase)
                Text(модель.товар.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
        }
    }

    /// Что поняли: размеры шин (их два — выбор, какой сверять), сезон, диаметр, ширина, разболтовки, вылет, отверстие.
    private var фишки: some View {
        ПотокЧипов(зазор: 8) {
            ForEach(р.шины, id: \.self) { размер in
                фишкаШины(размер)
            }
            if р.шины.isEmpty, let д = р.диаметрШины {
                ФишкаАвтоподбора(текст: "R" + ЧислаАвтоподбора.ч(д), значок: "circle.circle")
            }
            if let сезон = р.сезон {
                ФишкаАвтоподбора(текст: сезон.название, значок: сезон.значок)
            }
            if р.вид != .шины {
                ForEach(фишкиДиска, id: \.self) { текст in
                    ФишкаАвтоподбора(текст: текст, значок: nil)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(т("af_item_params_a11y"))
    }

    private var фишкиДиска: [String] {
        var итог: [String] = []
        if let д = р.диск.диаметр { итог.append("R" + ЧислаАвтоподбора.ч(д)) }
        if let ш = р.диск.ширина { итог.append(ЧислаАвтоподбора.ч(ш) + "J") }
        итог += р.диск.разболтовки.map { "PCD " + $0.подпись }
        if let et = р.диск.et { итог.append("ET" + ЧислаАвтоподбора.ч(et)) }
        if let dia = р.диск.dia { итог.append("DIA " + ЧислаАвтоподбора.ч(dia, знаков: 2)) }
        return итог
    }

    /// Размер шины фишкой; если их несколько — нажатием выбирается, какой сверять.
    @ViewBuilder
    private func фишкаШины(_ размер: РазмерШиныАвтоподбора) -> some View {
        if р.шины.count > 1 {
            let выбран = модель.размерТовара == размер
            Button {
                ОткликСайта.выбор()
                модель.размерТовара = размер
            } label: {
                ФишкаАвтоподбора(текст: размер.подпись, значок: выбран ? "checkmark" : "circle.circle", выбрана: выбран)
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
            .accessibilityAddTraits(выбран ? .isSelected : [])
            .accessibilityHint(т("af_pick_size_hint"))
        } else {
            ФишкаАвтоподбора(текст: размер.подпись, значок: "circle.circle")
        }
    }

    private var кнопки: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                правка
                if модель.правлен { сброс }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 8) {
                правка
                if модель.правлен { сброс }
            }
        }
    }

    private var правка: some View {
        МалаяКнопкаАвтоподбора(заголовок: т(р.пустой ? "af_item_set" : "af_item_edit"), значок: "pencil") {
            модель.путь.append(.параметрыТовара)
        }
    }

    private var сброс: some View {
        МалаяКнопкаАвтоподбора(заголовок: т("af_item_reset"), значок: "arrow.uturn.backward") {
            ОткликСайта.выбор()
            модель.вернутьИсходный()
        }
    }
}

/// Фишка параметра: «225/45 R17», «PCD 5×114.3». Выбранная — залита акцентом.
struct ФишкаАвтоподбора: View {
    let текст: String
    let значок: String?
    var выбрана = false

    init(текст: String, значок: String?, выбрана: Bool = false) {
        self.текст = текст
        self.значок = значок
        self.выбрана = выбрана
    }

    var body: some View {
        HStack(spacing: 5) {
            if let значок {
                Image(systemName: значок)
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
            }
            Text(текст)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(выбрана ? Theme.поверхность : Theme.акцент)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(выбрана ? AnyShapeStyle(Theme.акцент) : AnyShapeStyle(Theme.оттенокАкцента), in: Capsule())
        .overlay { Capsule().strokeBorder(Theme.рамкаПункта, lineWidth: выбрана ? 0 : 1) }
    }
}

/// Небольшая кнопка-ссылка: значок и слово акцентом, не меньше 44 pt в высоту.
struct МалаяКнопкаАвтоподбора: View {
    let заголовок: String
    let значок: String
    var опасная = false
    let действие: () -> Void

    init(заголовок: String, значок: String, опасная: Bool = false, действие: @escaping () -> Void) {
        self.заголовок = заголовок
        self.значок = значок
        self.опасная = опасная
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.subheadline.weight(.bold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(опасная ? УровеньАвтоподбора.неПодходит.краска : Theme.акцент)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.96))
        .accessibilityLabel(заголовок)
    }
}

// MARK: - Карточка машины

/// «Моя машина»: выбрать; найденные параметры; «нет в справочнике — введите сами».
struct КарточкаМашиныАвтоподбора: View {
    @ObservedObject var модель: МодельАвтоподбора
    @ObservedObject var гараж: ГаражАвтоподбора

    init(модель: МодельАвтоподбора, гараж: ГаражАвтоподбора) {
        self.модель = модель
        self.гараж = гараж
    }

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "car.fill")
                    .foregroundStyle(Theme.акцент)
                    .accessibilityHidden(true)
                Text(т("af_car_title"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.акцент)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                if гараж.ищем {
                    SiteSpinner(размер: 16, толщина: 2, стоит: ДвижениеСайта.тихо)
                        .accessibilityLabel(т("af_car_searching"))
                }
            }
            содержимое
        }
        .карточкаАвтоподбора()
    }

    @ViewBuilder
    private var содержимое: some View {
        if let п = гараж.посадка {
            СводкаМашиныАвтоподбора(машина: гараж.машина, посадка: п)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    другая
                    изменить
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 8) {
                    другая
                    изменить
                }
            }
        } else if let машина = гараж.машина {
            Text(машина.подпись)
                .font(.headline)
                .foregroundStyle(Theme.текст)
            Text(т(гараж.ищем ? "af_car_searching" : (гараж.молчание == .сеть ? "af_car_no_net" : "af_car_not_found")))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ЗелёнаяКнопкаФото(заголовок: т("af_car_enter"), значок: "slider.horizontal.3") {
                модель.путь.append(.параметрыМашины)
            }
            .disabled(гараж.ищем)
            другая
        } else {
            Text(т("af_car_empty"))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ЗелёнаяКнопкаФото(заголовок: т("af_car_pick"), значок: "car.fill") {
                ОткликСайта.выбор()
                модель.путь.append(.марка)
            }
            МалаяКнопкаАвтоподбора(заголовок: т("af_car_manual"), значок: "slider.horizontal.3") {
                модель.путь.append(.параметрыМашины)
            }
        }
    }

    private var другая: some View {
        МалаяКнопкаАвтоподбора(заголовок: т("af_car_other"), значок: "arrow.triangle.2.circlepath") {
            модель.путь.append(.марка)
        }
    }

    private var изменить: some View {
        МалаяКнопкаАвтоподбора(заголовок: т("af_car_edit"), значок: "slider.horizontal.3") {
            модель.путь.append(.параметрыМашины)
        }
    }
}

/// Машина и её параметры строками «что — значение»; источник — справочник или «введено вами».
struct СводкаМашиныАвтоподбора: View {
    let машина: МашинаАвтоподбора?
    let посадка: ПосадкаАвтоподбора

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    private var строки: [(подпись: String, значение: String)] {
        var итог: [(подпись: String, значение: String)] = []
        let п = посадка
        if let р = п.разболтовка { итог.append((т("af_p_pcd"), р.подпись)) }
        if let dia = п.dia { итог.append((т("af_p_dia"), String(format: т("af_mm"), ЧислаАвтоподбора.ч(dia, знаков: 2)))) }
        if let et = СверкаАвтоподбора.штатныйВылет(п) { итог.append((т("af_p_et"), et)) }
        if !п.штатныеДиаметры.isEmpty {
            итог.append((т("af_p_diam"), СверкаАвтоподбора.списокДиаметров(п.штатныеДиаметры)))
        }
        if !п.шины.isEmpty { итог.append((т("af_p_tires"), п.шины.map(\.подпись).joined(separator: ", "))) }
        if let низ = п.ширинаMin ?? п.ширинаMax, let верх = п.ширинаMax ?? п.ширинаMin {
            let ширина = низ == верх ? ЧислаАвтоподбора.ч(низ) + "J"
                : ЧислаАвтоподбора.ч(низ) + "…" + ЧислаАвтоподбора.ч(верх) + "J"
            итог.append((т("af_p_width"), ширина))
        }
        if let крепёж = п.крепёж { итог.append((т("af_p_bolt"), крепёж)) }
        return итог
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(машина?.подпись ?? т("af_car_own"))
                .font(.headline)
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(строки.enumerated()), id: \.offset) { _, строка in
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        подпись(строка.подпись)
                        Spacer(minLength: 8)
                        значение(строка.значение)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        подпись(строка.подпись)
                        значение(строка.значение)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Label(т(посадка.свои ? "af_src_own" : "af_src_ref"),
                  systemImage: посадка.свои ? "person.fill" : "books.vertical.fill")
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
        }
    }

    private func подпись(_ текст: String) -> some View {
        Text(текст)
            .font(.subheadline)
            .foregroundStyle(Theme.текстВторой)
    }

    private func значение(_ текст: String) -> some View {
        Text(текст)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.текст)
            .multilineTextAlignment(.trailing)
    }
}

// MARK: - Итог

/// Итог крупно и цветом; появляется пружиной (при «Уменьшении движения» — сразу).
struct КарточкаВердиктаАвтоподбора: View {
    let вердикт: ВердиктАвтоподбора
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @ScaledMetric(relativeTo: .title2) private var круг: CGFloat = 52
    @State private var появилось = false

    init(вердикт: ВердиктАвтоподбора) {
        self.вердикт = вердикт
    }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: вердикт.уровень.значокИтога)
                .font(.title2.weight(.bold))
                .frame(width: круг, height: круг)
                .background(Color.white.opacity(0.18), in: Circle())
                .scaleEffect(появилось ? 1 : 0.55)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(вердикт.заголовок)
                    .font(.title2.weight(.heavy))
                    .fixedSize(horizontal: false, vertical: true)
                if !вердикт.подпись.isEmpty {
                    Text(вердикт.подпись)
                        .font(.subheadline.weight(.medium))
                        .opacity(0.94)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: вердикт.уровень.заливка, startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .shadow(color: (вердикт.уровень.заливка.last ?? Color.black).opacity(0.25), radius: 12, x: 0, y: 5)
        .scaleEffect(появилось ? 1 : 0.96)
        .opacity(появилось ? 1 : 0)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .onAppear { показать() }
        .onChange(of: вердикт.уровень) { _, _ in
            guard !тихо else { return }
            появилось = false
            показать()
        }
    }

    private func показать() {
        if тихо {
            появилось = true
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { появилось = true }
        }
    }
}

/// Пункты итога: значок уровня, что и почему. VoiceOver читает строку целиком: «Нужна деталь. Центральное отверстие…».
struct ПунктыАвтоподбора: View {
    let вердикт: ВердиктАвтоподбора
    let дополнитьМашину: () -> Void

    init(вердикт: ВердиктАвтоподбора, дополнитьМашину: @escaping () -> Void) {
        self.вердикт = вердикт
        self.дополнитьМашину = дополнитьМашину
    }

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(т("af_why"))
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.текстВторой)
                .textCase(.uppercase)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(вердикт.пункты.enumerated()), id: \.element.id) { номер, пункт in
                строка(пункт)
                if номер < вердикт.пункты.count - 1 {
                    Divider()
                        .overlay(Theme.линия)
                }
            }
            if вердикт.нужныПараметрыМашины {
                МалаяКнопкаАвтоподбора(заголовок: т("af_car_add_params"), значок: "plus.circle", действие: дополнитьМашину)
                    .padding(.top, 12)
            }
        }
        .карточкаАвтоподбора()
    }

    private func строка(_ пункт: ПунктАвтоподбора) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: пункт.уровень.значок)
                .font(.body.weight(.semibold))
                .foregroundStyle(пункт.уровень.краска)
                .frame(minWidth: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(пункт.заголовок)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                Text(пункт.текст)
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(пункт.уровень.слово + ". " + пункт.заголовок + ". " + пункт.текст)
    }
}

/// «Сравнить со штатным»: у машины несколько штатных размеров — с каким сравнивать шину.
struct ВыборШтатногоАвтоподбора: View {
    @ObservedObject var модель: МодельАвтоподбора
    let штатные: [РазмерШиныАвтоподбора]
    let текущий: РазмерШиныАвтоподбора?

    init(модель: МодельАвтоподбора, штатные: [РазмерШиныАвтоподбора], текущий: РазмерШиныАвтоподбора?) {
        self.модель = модель
        self.штатные = штатные
        self.текущий = текущий
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(АвтоподборText.т("af_stock_pick"))
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.текстВторой)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)
            ПотокЧипов(зазор: 8) {
                ForEach(штатные, id: \.self) { размер in
                    let выбран = размер == текущий
                    Button {
                        ОткликСайта.выбор()
                        модель.штатныйВыбран = размер
                    } label: {
                        ФишкаАвтоподбора(текст: размер.подпись, значок: выбран ? "checkmark" : nil, выбрана: выбран)
                    }
                    .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
                    .accessibilityAddTraits(выбран ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

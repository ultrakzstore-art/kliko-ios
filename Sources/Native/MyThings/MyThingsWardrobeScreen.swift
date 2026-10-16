import SwiftUI
import UIKit

/**
 «МОЁ» — «МОЙ ГАРДЕРОБ» (пачка 16.10.2026 «мой дом, компьютер, гардероб и для вас»; владелец: «так же и гардероб
 вещей»; «это нужно для рекомендаций — по этим параметрам новинки и прочее»; «удобно для глаз, ровная схема везде, мощная
 анимированная подача, летает на всех девайсах»).

 Экран сверху вниз (каскад ПоявлениеМоего, как у хаба):
   · шапка — кольцо прогресса гардероба (прогрессГардероба), сводка и следующий шаг;
   · «Добавить вещь» — снять (камера) или из Фото, по нажатию: фон уходит, цвет и вид — сами, на телефоне
     (MyThingsWardrobePhoto.swift); или шаблоном вида — без фото;
   · фильтры по слою и сезону и ровная сетка вещей (2 колонки на iPhone SE, до 4 — на iPad);
   · образы (MyThingsWardrobeOutfits.swift), как сидят бренды (MyThingsWardrobeFit.swift), «Добавить из моих покупок».
 Лист вещи — MyThingsWardrobeItem.swift («С чем носить» — MyThingsWardrobeMatch.swift, размер —
 MyThingsWardrobeSize.swift). Всё — только на телефоне (МоёХранилище.обновитьГардероб), на сервер ничего не уходит.

 Ширина — до 680 pt. «Уменьшение движения» и лёгкий режим — без полёта (ДвижениеСайта, РежимУстройства), VoiceOver —
 карточки одним элементом. Экран не регистрирует ЦельМоего сам: это делают хаб и окно «Моего» (MyThingsHub.swift).
 */
struct ЭкранМоегоГардероба: View {
    @ObservedObject private var хранилище = МоёХранилище.shared
    @State private var лист: ЛистГардеробаМоего? = nil
    @State private var камера = false
    @State private var галерея = false
    @State private var слой: СлойГардеробаМоего? = nil
    @State private var сезон: СезонВещиМоего? = nil
    @State private var весть: String? = nil
    @State private var номерВести = 0

    init() {}

    private func т(_ ключ: String) -> String { МойГардеробText.т(ключ) }

    var body: some View {
        let запись = хранилище.запись
        ScrollView {
            VStack(spacing: 14) {
                верх(запись)
                низ(запись)
            }
            .padding(16)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .animation(ДвижениеСайта.вставкаСписка, value: запись.гардероб.вещи.map(\.id))
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .шапкаЭкранаСайта(МоёText.т("my_wardrobe"))
        .выборСнимкаГардероба(камера: $камера, галерея: $галерея) { источник in
            лист = .новая(ЗаготовкаВещиГардероба(источник: источник))
        }
        .sheet(item: $лист) { цель in
            содержимое(цель)
        }
        .overlay(alignment: .bottom) {
            if let весть {
                ТостКабинета(текст: весть)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityHidden(true)
            }
        }
        .onAppear { хранилище.подготовить() }
    }

    @ViewBuilder
    private func верх(_ запись: ЗаписьМоего) -> some View {
        let г = запись.гардероб
        ШапкаГардеробаМоего(прогресс: запись.прогрессГардероба, сводка: запись.сводкаГардероба)
            .появлениеМоего(0)
        КарточкаДобавленияГардероба(пусто: г.вещи.isEmpty, полно: г.вещи.count >= ГардеробМоего.пределВещей,
                                    снять: { камера = true }, изФото: { галерея = true },
                                    шаблон: { вид in лист = .новая(ЗаготовкаВещиГардероба(вид: вид)) })
            .появлениеМоего(1)
        if !г.вещи.isEmpty {
            фильтры(г)
                .появлениеМоего(2)
            сетка(г)
                .появлениеМоего(3)
        }
    }

    @ViewBuilder
    private func низ(_ запись: ЗаписьМоего) -> some View {
        let г = запись.гардероб
        КарточкаОбразовГардероба(гардероб: г) { id in лист = .образ(id) }
            .появлениеМоего(4)
        КарточкаПосадкиГардероба(гардероб: г) { бренд in лист = .посадка(бренд) }
            .появлениеМоего(5)
        if Config.покупкиВМоё {
            ПереходРазделаМоего(цель: .изПокупок) {
                КарточкаПокупокМоего(добавлено: г.вещи.filter { $0.покупка != nil }.count)
            }
            .появлениеМоего(6)
        }
        приватность
            .появлениеМоего(7)
    }

    private var приватность: some View {
        Label {
            Text(т("mw_local"))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(Theme.акцент)
        }
        .font(.footnote)
        .foregroundStyle(Theme.текстВторой)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: Фильтры и сетка

    /// Вещи под фильтром: слой и сезон (всесезонные — в любом сезоне).
    private func подФильтром(_ г: ГардеробМоего) -> [ВещьГардеробаМоего] {
        г.вещи.filter { в in
            (слой == nil || в.вид.слой == слой) && (сезон == nil || в.сезон == сезон || в.сезон == .всесезон)
        }
    }

    private func фильтры(_ г: ГардеробМоего) -> some View {
        let слои = СлойГардеробаМоего.allCases.filter { с in г.вещи.contains { $0.вид.слой == с } }
        let сезоны = СезонВещиМоего.allCases.filter { с in с != .всесезон && г.вещи.contains { $0.сезон != nil } }
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ЧипМоего(String(format: т("mw_all_n"), String(г.вещи.count)), выбран: слой == nil && сезон == nil) {
                    ОткликСайта.выбор()
                    withAnimation(ДвижениеСайта.смена) {
                        слой = nil
                        сезон = nil
                    }
                }
                ForEach(слои, id: \.self) { с in
                    ЧипМоего(МойГардеробText.слой(с), выбран: слой == с) {
                        ОткликСайта.выбор()
                        withAnimation(ДвижениеСайта.смена) { слой = слой == с ? nil : с }
                    }
                }
                if !сезоны.isEmpty {
                    Rectangle()
                        .fill(Theme.линия)
                        .frame(width: 1, height: 24)
                        .accessibilityHidden(true)
                }
                ForEach(сезоны, id: \.self) { с in
                    ЧипМоего(с.название, выбран: сезон == с, значок: МойГардеробText.значок(с)) {
                        ОткликСайта.выбор()
                        withAnimation(ДвижениеСайта.смена) { сезон = сезон == с ? nil : с }
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func сетка(_ г: ГардеробМоего) -> some View {
        let вещи = подФильтром(г)
        if вещи.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(т("mw_filter_empty"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                МалаяКнопкаАвтоподбора(заголовок: т("mw_filter_reset"), значок: "line.3.horizontal.decrease.circle") {
                    withAnimation(ДвижениеСайта.смена) {
                        слой = nil
                        сезон = nil
                    }
                }
            }
            .карточкаМоего()
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 12)], spacing: 12) {
                ForEach(вещи) { вещь in
                    Button {
                        ОткликСайта.выбор()
                        лист = .вещь(вещь.id)
                    } label: {
                        КарточкаВещиГардероба(вещь: вещь)
                    }
                    .buttonStyle(НажатиеСайта())
                    .contextMenu {
                        Button(role: .destructive) {
                            удалить(вещь)
                        } label: {
                            Label(т("mw_delete"), systemImage: "trash")
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
        }
    }

    // MARK: Листы

    @ViewBuilder
    private func содержимое(_ цель: ЛистГардеробаМоего) -> some View {
        switch цель {
        case .вещь(let id):
            if let вещь = хранилище.запись.гардероб.вещь(id) {
                ЛистВещиГардероба(вещь: вещь, заготовка: nil, открытьДругую: открытьДругую, продать: продать)
            }
        case .новая(let заготовка):
            ЛистВещиГардероба(вещь: nil, заготовка: заготовка, открытьДругую: открытьДругую, продать: продать)
        case .образ(let id):
            ЛистОбразаГардероба(образ: id.flatMap { номер in хранилище.запись.гардероб.образы.first { $0.id == номер } })
        case .посадка(let бренд):
            ЛистПосадкиГардероба(бренд: бренд)
        }
    }

    /// Своя вещь из «С чем носить» — её лист вместо текущего.
    private func открытьДругую(_ id: UUID) {
        лист = .вещь(id)
    }

    /// «Продать своё»: лист закрывается, мастер подачи — с готовым названием в буфере обмена.
    private func продать(_ вещь: ВещьГардеробаМоего) {
        лист = nil
        ПереходыГардероба.продать(название: вещь.названиеДляПродажи)
    }

    /// Удаление из меню карточки: купленное — вместе с отметкой сделки.
    private func удалить(_ вещь: ВещьГардеробаМоего) {
        if let сделка = вещь.покупка?.сделка, хранилище.запись.изСделок[сделка] == вещь.id {
            хранилище.убратьПокупку(сделка: сделка)
        } else {
            хранилище.обновитьГардероб { г in г.вещи.removeAll { $0.id == вещь.id } }
        }
        ОткликСайта.успех()
        показатьВесть(т("mw_deleted"))
    }

    private func показатьВесть(_ текст: String) {
        номерВести += 1
        let номер = номерВести
        withAnimation(ДвижениеСайта.появление) { весть = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard номер == номерВести else { return }
            withAnimation(ДвижениеСайта.уход) { весть = nil }
        }
    }
}

/// Что открыто листом поверх гардероба.
enum ЛистГардеробаМоего: Identifiable {
    case вещь(UUID)
    case новая(ЗаготовкаВещиГардероба)
    case образ(UUID?)
    case посадка(String?)

    var id: String {
        switch self {
        case .вещь(let id): return "item:" + id.uuidString
        case .новая(let заготовка): return "new:" + заготовка.номер.uuidString
        case .образ(let id): return "outfit:" + (id?.uuidString ?? "new")
        case .посадка(let бренд): return "fit:" + (бренд ?? "")
        }
    }
}

extension ВещьГардеробаМоего {
    /// Название для подачи: «Куртка Zara, M, чёрная» — вид или своё название, бренд, размер, цвет; до 75 знаков.
    var названиеДляПродажи: String {
        let своё = имя.trimmingCharacters(in: .whitespacesAndNewlines)
        var итог = своё.isEmpty ? вид.название : своё
        let б = бренд.trimmingCharacters(in: .whitespacesAndNewlines)
        if !б.isEmpty && !итог.lowercased().contains(б.lowercased()) { итог += " " + б }
        if let р = размер { итог += ", " + р.коротко }
        if let цвет = цвета.first, цвет != .разноцветный { итог += ", " + цвет.название.lowercased() }
        return String(итог.prefix(75))
    }
}

// MARK: - Шапка

/// Шапка гардероба: градиент шапки «Моего», кольцо прогресса гардероба, «Мой гардероб», сводка и следующий шаг.
struct ШапкаГардеробаМоего: View {
    let прогресс: ПрогрессМоего
    let сводка: String

    init(прогресс: ПрогрессМоего, сводка: String) {
        self.прогресс = прогресс
        self.сводка = сводка
    }

    private var текстШага: String {
        прогресс.шаг.map { МоёText.т($0) } ?? МоёText.т("my_all_set")
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.шапка, style: .continuous)
        HStack(alignment: .center, spacing: 16) {
            КольцоМоего(доля: прогресс.доля, размер: 68, толщина: 6, цвет: Theme.шапкаМята,
                        дорожка: Color.white.opacity(0.15), цветТекста: Color.white, шрифт: 15)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "hanger")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.шапкаМята)
                        .accessibilityHidden(true)
                    Text(МоёText.т("my_wardrobe"))
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(сводка)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.86))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                шаг
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [Theme.шапкаВерх, Theme.шапкаСередина, Theme.шапкаНиз], startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .clipShape(форма)
        }
        .overlay {
            БликМоего()
                .clipShape(форма)
        }
        .animation(ДвижениеСайта.смена, value: сводка)
        .animation(ДвижениеСайта.смена, value: прогресс.шаг)
        .accessibilityElement(children: .combine)
        .accessibilityValue(String(format: МоёText.т("my_ready"), ПроцентМоего.текст(прогресс.доля)))
    }

    private var шаг: some View {
        HStack(spacing: 5) {
            Image(systemName: прогресс.шаг == nil ? "checkmark" : "plus")
                .font(.system(size: 10, weight: .heavy))
                .accessibilityHidden(true)
            Text(текстШага)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Theme.шапкаМятаТекст)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Theme.шапкаМята, in: Capsule())
        .id(прогресс.шаг ?? "done")
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}

// MARK: - Добавить вещь

/// «Добавить вещь»: две крупные кнопки (снять, из Фото) и шаблоны вида чипами — без пустых полей.
struct КарточкаДобавленияГардероба: View {
    let пусто: Bool
    let полно: Bool
    let снять: () -> Void
    let изФото: () -> Void
    let шаблон: (ВидВещиГардеробаМоего) -> Void

    init(пусто: Bool, полно: Bool, снять: @escaping () -> Void, изФото: @escaping () -> Void,
         шаблон: @escaping (ВидВещиГардеробаМоего) -> Void) {
        self.пусто = пусто
        self.полно = полно
        self.снять = снять
        self.изФото = изФото
        self.шаблон = шаблон
    }

    /// Частые виды — шаблоны «без фото».
    private static let шаблоны: [ВидВещиГардеробаМоего] = [.футболка, .рубашка, .свитер, .джинсы, .брюки, .платье, .юбка,
                                                           .куртка, .пальто, .кроссовки, .ботинки, .сумка]

    private func т(_ ключ: String) -> String { МойГардеробText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mw_add"), значок: "plus.viewfinder")
            Text(т(пусто ? "mw_add_first" : "mw_add_sub"))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if КамераПодачи.есть {
                    большаяКнопка(т("mw_photo_shoot"), значок: "camera.fill", главная: true, действие: снять)
                }
                большаяКнопка(т("mw_photo_gallery"), значок: "photo.on.rectangle", главная: !КамераПодачи.есть,
                              действие: изФото)
            }
            Text(т("mw_add_tpl"))
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.текстВторой)
            ПотокЧипов(зазор: 6) {
                ForEach(Self.шаблоны, id: \.self) { вид in
                    ЧипМоего(вид.название, выбран: false, значок: вид.значок) {
                        ОткликСайта.выбор()
                        шаблон(вид)
                    }
                }
            }
            if полно {
                Text(т("mw_full"))
                    .font(.caption)
                    .foregroundStyle(Theme.оранжевый)
            }
        }
        .disabled(полно)
        .карточкаМоего()
    }

    private func большаяКнопка(_ заголовок: String, значок: String, главная: Bool,
                               действие: @escaping () -> Void) -> some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return Button {
            ОткликСайта.выбор()
            действие()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.system(size: 22, weight: .semibold))
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(главная ? Color.white : Theme.акцент)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background {
                if главная {
                    LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец], startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                        .clipShape(форма)
                } else {
                    форма.fill(Theme.оттенокАкцента)
                }
            }
            .contentShape(форма)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.96))
        .accessibilityLabel(заголовок)
    }
}

// MARK: - Карточка вещи

/// Карточка сетки: картинка 0,85 : 1, название, цвета точками и размер; купленное на Kliko — значок пакета.
struct КарточкаВещиГардероба: View {
    let вещь: ВещьГардеробаМоего

    init(вещь: ВещьГардеробаМоего) {
        self.вещь = вещь
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(0.85, contentMode: .fit)
                .overlay { КартинкаВещиГардероба(вещь: вещь) }
                .clipped()
                .overlay(alignment: .topLeading) { значки }
            VStack(alignment: .leading, spacing: 4) {
                Text(вещь.заголовок)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(вещь.цвета) { цвет in
                        КружокЦветаГардероба(цвет, размер: 10)
                    }
                    Text(вещь.размер?.коротко ?? вещь.вид.название)
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .background(Theme.поверхность, in: форма)
        .clipShape(форма)
        .теньКарточкиСайта(радиус: Theme.Радиус.md)
        .contentShape(форма)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(подписьДоступности)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var значки: some View {
        HStack(spacing: 4) {
            if вещь.покупка != nil {
                Image(systemName: "bag.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 22, height: 22)
                    .background(Theme.золото, in: Circle())
            }
            if let сезон = вещь.сезон {
                Image(systemName: МойГардеробText.значок(сезон))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 22, height: 22)
                    .background(Theme.поверхность.opacity(0.9), in: Circle())
            }
        }
        .padding(7)
        .accessibilityHidden(true)
    }

    private var подписьДоступности: String {
        var части = [вещь.заголовок]
        if !вещь.цвета.isEmpty { части.append(вещь.цвета.map(\.название).joined(separator: ", ")) }
        if let р = вещь.размер { части.append(р.коротко) }
        if let с = вещь.сезон { части.append(с.название) }
        if let п = вещь.покупка { части.append(п.подпись) }
        return части.joined(separator: ". ")
    }
}

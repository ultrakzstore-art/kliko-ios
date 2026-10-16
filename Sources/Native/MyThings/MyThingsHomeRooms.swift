import SwiftUI
import UIKit

/**
 «МОЙ ДОМ» — КОМНАТЫ (владелец 16.10.2026: «мой дом — что можно по дому?»; обещано: «комнаты Ш×Д×В, фото, шаблоны
 «спальня 3×4», AR-линейка»).

 Карточка — плитки комнат ровной сеткой (фото или значок вида на мягком градиенте, название, «3×4 м · 12 м²», точки
 палитры) и шаблоны чипами: «Спальня 3×4 м», «Гостиная 4×5 м», «Кухня 3×3 м», «Студия 25 м²»… Касание шаблона сразу
 кладёт комнату («≈ примерно, замерьте») и открывает её лист; «Своя комната» — пустую.

 Лист комнаты — правка живая (комната уже в записи: фото пишется в неё сразу): вид, своё название, шаблоны вида,
 ширина и длина регулятором (шаг 5 см), потолок чипами ряда 250…300 и регулятором, «Измерить в AR» (отрезки: ширина,
 высота, длина), фото по нажатию (камера или галерея) и палитра — до пяти цветов из 16: «Цвета с фото» считает их на
 телефоне (ПалитраФотоДома). Закрыли — записалось; новая комната, где так ничего и не указали, не остаётся.
 */
struct КарточкаКомнатДома: View {
    let дом: ДомМоего
    let открыть: (ЛистДомаМоего) -> Void

    init(дом: ДомМоего, открыть: @escaping (ЛистДомаМоего) -> Void) {
        self.дом = дом
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { МойДомText.т(ключ) }

    /// «Студия 25 м²» — своего вида нет: гостиная с названием «Студия».
    static let студия = ШаблонКомнатыМоего(id: "studio_25", вид: .гостиная, ширина: 500, длина: 500, высота: 270)
    static let шаблоны: [ШаблонКомнатыМоего] = ШаблонКомнатыМоего.все + [студия]

    static func подпись(_ шаблон: ШаблонКомнатыМоего) -> String {
        шаблон.id == студия.id ? МойДомText.т("mh_tpl_studio") : шаблон.подпись
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ЗаголовокМоего(т("mh_rooms"), значок: "square.split.2x2")
            if дом.комнаты.isEmpty {
                Text(т("mh_rooms_empty"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                    ForEach(дом.комнаты) { к in
                        ПлиткаКомнатыДома(комната: к) { открыть(.комната(к.id, новая: false)) }
                    }
                }
            }
            if дом.комнаты.count < ДомМоего.пределКомнат {
                Text(т("mh_rooms_add"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.текстВторой)
                ПотокЧипов(зазор: 8) {
                    ForEach(Self.шаблоны) { ш in
                        ЧипМоего(Self.подпись(ш), выбран: false, значок: ш.вид.значок) { добавить(ш) }
                    }
                    ЧипМоего(т("mh_room_own"), выбран: false, значок: "plus") { добавить(nil) }
                }
            }
        }
        .карточкаМоего()
    }

    private func добавить(_ шаблон: ШаблонКомнатыМоего?) {
        ОткликСайта.выбор()
        var черновик = шаблон?.комната() ?? КомнатаМоего(вид: .другая)
        if шаблон?.id == Self.студия.id { черновик.имя = т("mh_studio_name") }
        let новая = черновик
        guard дом.комнаты.count < ДомМоего.пределКомнат else { return }
        МоёХранилище.shared.обновитьДом { д in д.комнаты.append(новая) }
        открыть(.комната(новая.id, новая: true))
    }
}

/// Плитка комнаты: обложка 96 pt (фото или значок), точки палитры, название и размеры.
struct ПлиткаКомнатыДома: View {
    let комната: КомнатаМоего
    let действие: () -> Void

    init(комната: КомнатаМоего, действие: @escaping () -> Void) {
        self.комната = комната
        self.действие = действие
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        Button {
            ОткликСайта.выбор()
            действие()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                обложка
                    .frame(height: 96)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay(alignment: .topTrailing) { палитра }
                VStack(alignment: .leading, spacing: 2) {
                    Text(комната.заголовок)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    Text(МойДомЧисла.комната(комната) ?? МойДомText.т("mh_room_no_size"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.поверхность2)
            .clipShape(форма)
            .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1) }
            .contentShape(форма)
        }
        .buttonStyle(НажатиеСайта())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(комната.заголовок + ", " + (МойДомЧисла.комната(комната) ?? МойДомText.т("mh_room_no_size")))
        .accessibilityAddTraits(.isButton)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    @ViewBuilder
    private var обложка: some View {
        if let фото = комната.фото {
            ФотоМоегоВид(имя: фото.мини)
        } else {
            ZStack {
                LinearGradient(colors: [РазделМоего.дом.цвет.opacity(0.22), РазделМоего.дом.цвет.opacity(0.06)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: комната.вид.значок)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(РазделМоего.дом.цвет)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var палитра: some View {
        if !комната.палитра.isEmpty {
            HStack(spacing: -4) {
                ForEach(комната.палитра) { цвет in
                    КраскаЦветаДома(цвет: цвет, размер: 14)
                        .overlay { Circle().strokeBorder(Theme.поверхность, lineWidth: 1.5) }
                }
            }
            .padding(6)
            .background(Theme.поверхность.opacity(0.85), in: Capsule())
            .padding(8)
        }
    }
}

/// Числа «Моего дома» для подписей.
enum МойДомЧисла {
    /// «≈ 3×4 м · 12 м²»; нет ширины и длины — nil.
    static func комната(_ к: КомнатаМоего) -> String? {
        guard let ш = к.ширина, let д = к.длина else { return nil }
        let м = ЧислоМоего.ч(Double(ш) / 100) + "×" + ЧислоМоего.ч(Double(д) / 100) + " " + МоёText.т("my_u_m")
        let площадь = к.площадь.map { " · " + ЧислоМоего.ч($0) + " " + МойДомText.т("mh_m2") } ?? ""
        return (к.примерно ? "≈ " : "") + м + площадь
    }
}

// MARK: - Лист комнаты

struct РедакторКомнатыДома: View {
    let id: UUID
    let новая: Bool
    @ObservedObject private var хранилище = МоёХранилище.shared
    @State private var комната: КомнатаМоего
    @State private var камера = false
    @State private var галерея = false
    @State private var готовим = false
    @State private var считаем = false
    @State private var удалена = false
    @State private var весть: String? = nil

    init(id: UUID, новая: Bool) {
        self.id = id
        self.новая = новая
        _комната = State(initialValue: МоёХранилище.shared.запись.дом.комната(id) ?? КомнатаМоего(id: id, вид: .другая))
    }

    private func т(_ ключ: String) -> String { МойДомText.т(ключ) }

    /// Фото — из записи: его пишет хранилище само (сохранитьФото), в черновик листа оно не входит.
    private var фото: ФотоМоего? { хранилище.запись.дом.комната(id)?.фото }

    var body: some View {
        ОболочкаРедактораДома(заголовок: комната.заголовок, сохранить: nil, удалить: { удалить() }) {
            блокВида
            ПолеТекстаДома(заголовок: т("mh_name"), подсказка: т("mh_room_name_ph"), текст: $комната.имя)
            блокШаблонов
            блокРазмеров
            блокФото
            блокПалитры
        }
        .выборСнимкаДома(камера: $камера, галерея: $галерея) { источник in обработать(источник) }
        .animation(ДвижениеСайта.смена, value: комната.примерно)
        .animation(ДвижениеСайта.смена, value: фото)
        .animation(ДвижениеСайта.выбор, value: комната.палитра)
        .onDisappear { сохранить() }
    }

    // MARK: Вид и шаблоны

    private var блокВида: some View {
        VStack(alignment: .leading, spacing: 8) {
            ПодписьБлокаДома(т("mh_room_kind"))
            ПотокЧипов(зазор: 8) {
                ForEach(ВидКомнатыМоего.allCases, id: \.self) { вид in
                    ЧипМоего(вид.название, выбран: комната.вид == вид, значок: вид.значок) {
                        ОткликСайта.выбор()
                        комната.вид = вид
                    }
                }
            }
        }
    }

    private var шаблоныВида: [ШаблонКомнатыМоего] {
        КарточкаКомнатДома.шаблоны.filter { комната.вид == .другая || $0.вид == комната.вид }
    }

    @ViewBuilder
    private var блокШаблонов: some View {
        if !шаблоныВида.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ПодписьБлокаДома(т("mh_room_tpl"), пояснение: т("mh_room_tpl_hint"))
                ПотокЧипов(зазор: 8) {
                    ForEach(шаблоныВида) { ш in
                        ЧипМоего(КарточкаКомнатДома.подпись(ш), выбран: комната.примерно && комната.ширина == ш.ширина
                                    && комната.длина == ш.длина) {
                            ОткликСайта.выбор()
                            комната.ширина = ш.ширина
                            комната.длина = ш.длина
                            комната.высота = ш.высота
                            комната.примерно = true
                            if ш.id == КарточкаКомнатДома.студия.id && комната.имя.isEmpty {
                                комната.имя = т("mh_studio_name")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Размеры

    private var блокРазмеров: some View {
        VStack(alignment: .leading, spacing: 14) {
            ПодписьБлокаДома(т("mh_room_size"), пояснение: МойДомЧисла.комната(комната) ?? т("mh_room_size_hint"))
            РегуляторДома(заголовок: т("mh_room_w"), значение: комната.ширина, пределы: 100...1500, шаг: 5, обычно: 300,
                          примерно: комната.примерно) { x in
                комната.ширина = x
                комната.примерно = false
            }
            РегуляторДома(заголовок: т("mh_room_l"), значение: комната.длина, пределы: 100...1500, шаг: 5, обычно: 400,
                          примерно: комната.примерно) { x in
                комната.длина = x
                комната.примерно = false
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(т("mh_ceiling"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.текстВторой)
                ПотокЧипов(зазор: 8) {
                    ForEach(КаталогСтандартов.потолки, id: \.self) { в in
                        ЧипМоего(String(в), выбран: комната.высота == в) {
                            ОткликСайта.выбор()
                            комната.высота = в
                        }
                    }
                }
            }
            РегуляторДома(заголовок: т("mh_ceiling_own"), значение: комната.высота, пределы: 220...400, шаг: 5,
                          обычно: 270) { x in
                комната.высота = x
            }
            КнопкаЗамераДома(название: комната.заголовок) { ш, в, г in
                if let см = ЗамерДома.см(ш, КомнатаМоего.пределыСм) { комната.ширина = см }
                if let см = ЗамерДома.см(г, КомнатаМоего.пределыСм) { комната.длина = см }
                if let см = ЗамерДома.см(в, КомнатаМоего.пределыПотолка) { комната.высота = см }
                комната.примерно = false
            }
        }
    }

    // MARK: Фото

    private var блокФото: some View {
        VStack(alignment: .leading, spacing: 10) {
            ПодписьБлокаДома(т("mh_room_photo"), пояснение: т("mh_room_photo_hint"))
            if let фото {
                ФотоМоегоВид(имя: фото.файл)
                    .aspectRatio(фото.пропорция, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .transition(.opacity)
            }
            ПотокЧипов(зазор: 8) {
                if КамераПодачи.есть {
                    МалаяКнопкаАвтоподбора(заголовок: фото == nil ? т("mh_photo_take") : т("mh_photo_retake"),
                                           значок: "camera") { камера = true }
                }
                МалаяКнопкаАвтоподбора(заголовок: т("mh_photo_gallery"), значок: "photo.on.rectangle") { галерея = true }
                if фото != nil {
                    МалаяКнопкаАвтоподбора(заголовок: т("mh_photo_delete"), значок: "trash", опасная: true) {
                        хранилище.удалитьФото(.комната(id))
                    }
                }
            }
            .disabled(готовим)
            if готовим {
                ProgressView()
                    .tint(Theme.акцент)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(т("mh_busy"))
            }
            if let весть {
                Text(весть)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.оранжевый)
                    .transition(.opacity)
            }
            Label(МоёText.т("my_photo_local"), systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
        }
    }

    // MARK: Палитра

    private var блокПалитры: some View {
        VStack(alignment: .leading, spacing: 8) {
            ПодписьБлокаДома(т("mh_room_colors"), пояснение: т("mh_room_colors_hint"))
            if фото != nil {
                МалаяКнопкаАвтоподбора(заголовок: считаем ? т("mh_busy") : т("mh_colors_from_photo"), значок: "eyedropper") {
                    цветаСФото()
                }
                .disabled(считаем)
            }
            ПотокЧипов(зазор: 0) {
                ForEach(ЦветСтандарта.allCases) { цвет in
                    КругЦветаДома(цвет: цвет, выбран: комната.палитра.contains(цвет)) { переключить(цвет) }
                }
            }
        }
    }

    private func переключить(_ цвет: ЦветСтандарта) {
        if let место = комната.палитра.firstIndex(of: цвет) {
            ОткликСайта.выбор()
            комната.палитра.remove(at: место)
        } else if комната.палитра.count < КомнатаМоего.пределПалитры {
            ОткликСайта.выбор()
            комната.палитра.append(цвет)
        } else {
            ОткликСайта.предупреждение()
        }
    }

    // MARK: Снимок

    private func обработать(_ источник: ИсточникСнимкаМоего) {
        готовим = true
        весть = nil
        let место = МестоФотоМоего.комната(id)
        Task { @MainActor in
            let готовое = await Task.detached(priority: .userInitiated) { () -> ГотовоеФотоМоего? in
                switch источник {
                case .кадр(let кадр): return ОбработкаФотоМоего.подготовить(кадр)
                case .файл(let данные): return ОбработкаФотоМоего.подготовить(данные)
                }
            }.value
            guard let готовое else {
                готовим = false
                ОткликСайта.предупреждение()
                withAnimation(ДвижениеСайта.появление) { весть = МоёText.т("my_photo_bad") }
                return
            }
            let вышло = await хранилище.сохранитьФото(готовое, место: место)
            готовим = false
            guard вышло else {
                ОткликСайта.предупреждение()
                withAnimation(ДвижениеСайта.появление) { весть = МоёText.т("my_photo_save_fail") }
                return
            }
            ОткликСайта.успех()
            // Своей палитры ещё нет — цвета с нового фото сразу.
            if комната.палитра.isEmpty { await взятьЦвета(готовое.мини) }
        }
    }

    private func цветаСФото() {
        guard let фото, let адрес = ФайлыМоего.адресФото(фото.мини) else { return }
        Task { @MainActor in
            guard let данные = await Task.detached(priority: .userInitiated, operation: { () -> Data? in
                try? Data(contentsOf: адрес)
            }).value else { return }
            await взятьЦвета(данные)
        }
    }

    private func взятьЦвета(_ данные: Data) async {
        считаем = true
        let найденные = await Task.detached(priority: .userInitiated) { ПалитраФотоДома.цвета(данные) }.value
        считаем = false
        guard !найденные.isEmpty else { return }
        withAnimation(ДвижениеСайта.смена) { комната.палитра = найденные }
        ОткликСайта.успех()
        UIAccessibility.post(notification: .announcement,
                             argument: т("mh_colors_found") + ": " + найденные.map(\.название).joined(separator: ", "))
    }

    // MARK: Запись

    /// Черновик — в запись (фото — то, что уже в записи); новая пустая комната не остаётся. Пока открыта камера или
    /// выбор фото, пустую не убираем: снимок пишется в неё.
    private func сохранить() {
        guard !удалена else { return }
        let готовая = комната
        let номер = id
        хранилище.обновитьДом { д in
            guard let i = д.комнаты.firstIndex(where: { $0.id == номер }) else { return }
            var к = готовая
            к.фото = д.комнаты[i].фото
            д.комнаты[i] = к
        }
        let пустая = готовая.вид == .другая && готовая.ширина == nil && готовая.длина == nil && готовая.высота == nil
            && готовая.имя.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && готовая.палитра.isEmpty
            && фото == nil
        if новая && пустая && !камера && !галерея && !готовим {
            хранилище.обновитьДом { д in д.комнаты.removeAll { $0.id == номер } }
        }
    }

    private func удалить() {
        удалена = true
        let номер = id
        хранилище.обновитьДом { д in д.комнаты.removeAll { $0.id == номер } }
    }
}

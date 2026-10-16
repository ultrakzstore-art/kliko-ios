import SwiftUI
import UIKit

/**
 «МОЙ ГАРДЕРОБ» — ЛИСТ ВЕЩИ (владелец: «стандарты = удобство: не пустые поля, а выбор по стандартам, шаблоны, камера»).

 Сверху вниз: фото (камера или Фото — по нажатию; фон уходит на телефоне, MyThingsWardrobePhoto.swift) → что это (слой
 и вид чипами; по фото — подсказка Vision) → цвет (16 цветов каталога; по вырезке — сам) → размер (чип с биркой всех
 систем; свой размер из «Моих мерок» — сразу) → бренд (подсказки) и «Как сидит?» (заметка посадки бренда одним
 касанием) → сезон, своё название, заметка. У сохранённой вещи ещё «С чем носить» (MyThingsWardrobeMatch.swift),
 «Продать своё» и «Удалить с телефона».

 Черновик — копия вещи в листе; «Сохранить» пишет одним замыканием хранилища (обновитьГардероб), потом фото
 (сохранитьФото, место .вещьГардероба: вещь уже в записи). Фото вещи меняет только хранилище — правка листа своё фото не
 затирает. Обработка снимка — вне главной нити; пока идёт, «Сохранить» ждёт.
 */

/// Заготовка новой вещи: вид шаблоном и снимок (камера или галерея) — что есть.
struct ЗаготовкаВещиГардероба {
    /// Свой номер листа: две заготовки подряд — два разных листа.
    let номер: UUID
    var вид: ВидВещиГардеробаМоего?
    var источник: ИсточникСнимкаМоего?

    init(вид: ВидВещиГардеробаМоего? = nil, источник: ИсточникСнимкаМоего? = nil) {
        номер = UUID()
        self.вид = вид
        self.источник = источник
    }
}

struct ЛистВещиГардероба: View {
    /// Сохранённая вещь (правка) или nil — новая.
    let была: ВещьГардеробаМоего?
    let заготовка: ЗаготовкаВещиГардероба?
    let открытьДругую: (UUID) -> Void
    let продать: (ВещьГардеробаМоего) -> Void
    @ObservedObject private var хранилище = МоёХранилище.shared
    @Environment(\.dismiss) private var закрыть
    @Environment(\.horizontalSizeClass) private var класс
    @State private var черновик: ВещьГардеробаМоего
    @State private var слойВыбора: СлойГардеробаМоего
    @State private var снимок: СнимокВещиГардероба? = nil
    @State private var убратьФото = false
    @State private var обработка = false
    @State private var задача: Task<Void, Never>? = nil
    @State private var видТронут: Bool
    @State private var цветТронут = false
    @State private var видПоФото = false
    @State private var посадка: ПосадкаВещиМоего? = nil
    @State private var где = ""
    @State private var размерЛист = false
    @State private var камера = false
    @State private var галерея = false
    @State private var спросить = false
    @State private var весть: String? = nil
    @State private var номерВести = 0
    @State private var начато = false

    init(вещь: ВещьГардеробаМоего?, заготовка: ЗаготовкаВещиГардероба?, открытьДругую: @escaping (UUID) -> Void,
         продать: @escaping (ВещьГардеробаМоего) -> Void) {
        была = вещь
        self.заготовка = заготовка
        self.открытьДругую = открытьДругую
        self.продать = продать
        let начальная = вещь ?? ВещьГардеробаМоего(вид: заготовка?.вид ?? .другое)
        _черновик = State(initialValue: начальная)
        _слойВыбора = State(initialValue: начальная.вид.слой)
        _видТронут = State(initialValue: вещь != nil || заготовка?.вид != nil)
        _цветТронут = State(initialValue: вещь.map { !$0.цвета.isEmpty && !$0.цветСам } ?? false)
    }

    private func т(_ ключ: String) -> String { МойГардеробText.т(ключ) }

    /// Вещь уже в записи (правка): «С чем носить» и действия — по сохранённому.
    private var сохранённая: ВещьГардеробаМоего? {
        guard let была else { return nil }
        return хранилище.запись.гардероб.вещь(была.id)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    фотоБлок
                    видБлок
                    цветБлок
                    размерБлок
                    брендБлок
                    сезонБлок
                    if let сохранённая {
                        СЧемНоситьГардероба(вещь: сохранённая, запись: хранилище.запись, открытьСвою: открытьДругую)
                        действия(сохранённая)
                    }
                }
                .padding(16)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .animation(ДвижениеСайта.смена, value: черновик.вид)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(была == nil ? т("mw_item_new") : черновик.заголовок)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { панель }
            .клавиатураМоего()
        }
        .tint(Theme.акцент)
        .выборСнимкаГардероба(камера: $камера, галерея: $галерея) { источник in обработать(источник) }
        .sheet(isPresented: $размерЛист) {
            ВыборРазмераГардероба(виды: черновик.вид.видыРазмера, был: черновик.размер, тело: хранилище.запись.тело,
                                  готово: { новый in черновик.размер = новый })
        }
        .confirmationDialog(т("mw_delete_q"), isPresented: $спросить, titleVisibility: .visible) {
            Button(МоёText.т("my_delete"), role: .destructive) { удалить() }
            Button(МоёText.т("my_cancel"), role: .cancel) {}
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
        .onAppear { начать() }
        .onDisappear { задача?.cancel() }
    }

    @ToolbarContentBuilder
    private var панель: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(МоёText.т("my_cancel")) { закрыть() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if обработка {
                SiteSpinner(размер: 18, толщина: 2, стоит: ДвижениеСайта.тихо)
                    .accessibilityLabel(т("mw_photo_busy"))
            } else {
                Button(МоёText.т("my_save")) { сохранить() }
                    .fontWeight(.bold)
            }
        }
    }

    // MARK: Фото

    private var фотоБлок: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                картинка
                if обработка {
                    VStack(spacing: 10) {
                        SiteSpinner(размер: 28, толщина: 3, стоит: ДвижениеСайта.тихо)
                        Text(т("mw_photo_busy"))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.текст)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .animation(ДвижениеСайта.смена, value: обработка)
            меткиФото
            кнопкиФото
        }
        .карточкаМоего(поля: 12)
    }

    /// Что на снимке сейчас: новый (ещё не записан), своё фото, обложка купленного или значок.
    @ViewBuilder
    private var картинка: some View {
        if let снимок {
            ZStack {
                подложкаФото
                Image(uiImage: снимок.картинка)
                    .resizable()
                    .aspectRatio(contentMode: снимок.вырезано ? .fit : .fill)
                    .padding(снимок.вырезано ? 16 : 0)
            }
            .id(ObjectIdentifier(снимок.картинка))
            .transition(.opacity.combined(with: .scale(scale: 0.94)))
            .accessibilityHidden(true)
        } else {
            КартинкаВещиГардероба(вещь: убратьФото ? безФото : черновик, мини: false, поля: 16)
        }
    }

    /// Черновик без своего фото — после «Убрать» до сохранения.
    private var безФото: ВещьГардеробаМоего {
        var в = черновик
        в.фото = nil
        return в
    }

    private var подложкаФото: some View {
        ZStack {
            Theme.поверхность2
            if let цвет = черновик.цвета.first, цвет != .разноцветный {
                цвет.краска.opacity(цвет.светлый ? 0.22 : 0.12)
            }
        }
    }

    @ViewBuilder
    private var меткиФото: some View {
        let есть = снимок != nil || (!убратьФото && черновик.фото != nil)
        if let снимок {
            Label(т(снимок.вырезано ? "mw_photo_cut" : "mw_photo_kept"),
                  systemImage: снимок.вырезано ? "scissors" : "photo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(снимок.вырезано ? Theme.акцент : Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        } else if !есть {
            Text(т("mw_photo_hint"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let покупка = черновик.покупка {
            Label(покупка.подписьСЦеной, systemImage: "bag.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.золото)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var кнопкиФото: some View {
        let есть = снимок != nil || (!убратьФото && черновик.фото != nil)
        return ПотокЧипов(зазор: 8) {
            if КамераПодачи.есть {
                МалаяКнопкаАвтоподбора(заголовок: т(есть ? "mw_photo_retake" : "mw_photo_shoot"), значок: "camera") {
                    ОткликСайта.выбор()
                    камера = true
                }
            }
            МалаяКнопкаАвтоподбора(заголовок: т("mw_photo_gallery"), значок: "photo.on.rectangle") {
                ОткликСайта.выбор()
                галерея = true
            }
            if есть {
                МалаяКнопкаАвтоподбора(заголовок: т("mw_photo_remove"), значок: "trash", опасная: true) {
                    ОткликСайта.выбор()
                    withAnimation(ДвижениеСайта.смена) {
                        снимок = nil
                        убратьФото = черновик.фото != nil
                    }
                }
            }
        }
    }

    // MARK: Вид

    private var видБлок: some View {
        VStack(alignment: .leading, spacing: 10) {
            ЗаголовокМоего(т("mw_kind"), значок: "hanger")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(СлойГардеробаМоего.allCases, id: \.self) { слой in
                        ЧипМоего(МойГардеробText.слой(слой), выбран: слой == слойВыбора) {
                            ОткликСайта.выбор()
                            withAnimation(ДвижениеСайта.смена) { слойВыбора = слой }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            ПотокЧипов(зазор: 8) {
                ForEach(ВидВещиГардеробаМоего.allCases.filter { $0.слой == слойВыбора }, id: \.self) { вид in
                    ЧипМоего(вид.название, выбран: вид == черновик.вид, значок: вид.значок) { выбратьВид(вид) }
                }
            }
            .id(слойВыбора)
            .transition(.opacity)
            if видПоФото {
                Label(т("mw_kind_photo"), systemImage: "wand.and.stars")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.акцент)
                    .transition(.opacity)
            }
        }
        .карточкаМоего()
    }

    private func выбратьВид(_ вид: ВидВещиГардеробаМоего) {
        guard вид != черновик.вид else { return }
        ОткликСайта.выбор()
        видТронут = true
        withAnimation(ДвижениеСайта.смена) {
            черновик.вид = вид
            видПоФото = false
            поправитьРазмер()
        }
    }

    /// Размер не того вида (сменили вид вещи) — прочь; нет размера — свой из «Моих мерок».
    private func поправитьРазмер() {
        let виды = черновик.вид.видыРазмера
        if let р = черновик.размер, !виды.contains(р.вид) { черновик.размер = nil }
        guard черновик.размер == nil else { return }
        let тело = хранилище.запись.тело
        черновик.размер = виды.lazy.compactMap { тело.размер($0) }.first
    }

    // MARK: Цвет

    private var цветБлок: some View {
        VStack(alignment: .leading, spacing: 10) {
            ЗаголовокМоего(т("mw_color"), значок: "paintpalette")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: класс == .regular ? 8 : 4),
                      spacing: 10) {
                ForEach(ЦветСтандарта.allCases) { цвет in
                    кнопкаЦвета(цвет)
                }
            }
            HStack(spacing: 6) {
                if черновик.цветСам && !черновик.цвета.isEmpty {
                    Image(systemName: "wand.and.stars")
                        .accessibilityHidden(true)
                }
                Text(подписьЦвета)
                    .contentTransition(.opacity)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(черновик.цветСам ? Theme.акцент : Theme.текстВторой)
            .fixedSize(horizontal: false, vertical: true)
        }
        .карточкаМоего()
    }

    private var подписьЦвета: String {
        guard !черновик.цвета.isEmpty else { return т("mw_color_hint") }
        let имена = черновик.цвета.map(\.название).joined(separator: ", ")
        return черновик.цветСам ? String(format: т("mw_color_auto"), имена) : имена
    }

    private func кнопкаЦвета(_ цвет: ЦветСтандарта) -> some View {
        let выбран = черновик.цвета.contains(цвет)
        return Button {
            ОткликСайта.выбор()
            цветТронут = true
            withAnimation(ДвижениеСайта.выбор) {
                черновик.цветСам = false
                if выбран {
                    черновик.цвета.removeAll { $0 == цвет }
                } else if черновик.цвета.count >= 2 {
                    черновик.цвета[1] = цвет
                } else {
                    черновик.цвета.append(цвет)
                }
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    КружокЦветаГардероба(цвет, размер: 32)
                    if выбран {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(цвет.светлый ? Color.black.opacity(0.75) : Color.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 40, height: 40)
                .overlay {
                    Circle()
                        .strokeBorder(Theme.акцент, lineWidth: выбран ? 2 : 0)
                        .frame(width: 40, height: 40)
                }
                Text(цвет.название)
                    .font(.system(size: 10, weight: выбран ? .bold : .medium))
                    .foregroundStyle(выбран ? Theme.акцент : Theme.текстВторой)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .accessibilityLabel(цвет.название)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }

    // MARK: Размер, бренд, посадка

    @ViewBuilder
    private var размерБлок: some View {
        if !черновик.вид.видыРазмера.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ЗаголовокМоего(т("mw_size"), значок: "tag")
                ЧипРазмераВещиГардероба(размер: черновик.размер) {
                    ОткликСайта.выбор()
                    размерЛист = true
                }
                if let р = черновик.размер, хранилище.запись.тело.размер(р.вид) == р {
                    Label(т("mw_size_from_mine"), systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.акцент)
                }
            }
            .карточкаМоего()
            .transition(.opacity)
        }
    }

    private var брендБлок: some View {
        let г = хранилище.запись.гардероб
        let подсказки = ПосадкаГардероба.подсказки(черновик.бренд, г: г, предел: 6)
        let сводка = ПосадкаГардероба.сводка(бренда: черновик.бренд, г)
        let можноПосадку = !черновик.бренд.trimmingCharacters(in: .whitespaces).isEmpty && черновик.размер != nil
        return VStack(alignment: .leading, spacing: 10) {
            ЗаголовокМоего(т("mw_brand"), значок: "textformat")
            ПолеТекстаГардероба(подсказка: т("mw_brand_ph"), текст: $черновик.бренд, предел: ВещьГардеробаМоего.пределБренда)
            if !подсказки.isEmpty {
                ПотокЧипов(зазор: 6) {
                    ForEach(подсказки, id: \.self) { имя in
                        ЧипМоего(имя, выбран: false) {
                            ОткликСайта.выбор()
                            черновик.бренд = имя
                        }
                    }
                }
            }
            if let сводка {
                Label(сводка.совет + (сводка.беру.map { " · " + String(format: т("mw_fit_take"), $0) } ?? ""),
                      systemImage: "ruler")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(сводка.краска)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if можноПосадку {
                Text(т("mw_fit_how"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                ВыборПосадкиГардероба(посадка: $посадка, где: $где)
            } else if черновик.размер == nil && !черновик.вид.видыРазмера.isEmpty {
                Text(т("mw_fit_need_size"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .карточкаМоего()
    }

    // MARK: Сезон, название, заметка

    private var сезонБлок: some View {
        VStack(alignment: .leading, spacing: 10) {
            ЗаголовокМоего(т("mw_season"), значок: "sun.snow")
            ПотокЧипов(зазор: 8) {
                ForEach(СезонВещиМоего.allCases, id: \.self) { с in
                    ЧипМоего(с.название, выбран: черновик.сезон == с) {
                        ОткликСайта.выбор()
                        черновик.сезон = черновик.сезон == с ? nil : с
                    }
                }
            }
            Text(т("mw_name"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
            ПолеТекстаГардероба(подсказка: т("mw_name_ph"), текст: $черновик.имя, предел: ВещьГардеробаМоего.пределИмени)
            Text(т("mw_note"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
            ПолеТекстаГардероба(подсказка: т("mw_note_ph"), текст: $черновик.заметка,
                                предел: ВещьГардеробаМоего.пределЗаметки, строк: 3)
        }
        .карточкаМоего()
    }

    // MARK: Действия

    private func действия(_ вещь: ВещьГардеробаМоего) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            МалаяКнопкаАвтоподбора(заголовок: т("mw_sell"), значок: "tag.circle") {
                ОткликСайта.выбор()
                продать(вещь)
            }
            Text(т("mw_sell_hint"))
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            МалаяКнопкаАвтоподбора(заголовок: т("mw_delete"), значок: "trash", опасная: true) {
                спросить = true
            }
        }
        .карточкаМоего()
    }

    // MARK: Ход

    private func начать() {
        guard !начато else { return }
        начато = true
        хранилище.подготовить()
        if была == nil {
            if заготовка?.вид != nil { поправитьРазмер() }
            if let источник = заготовка?.источник { обработать(источник) }
        } else if let р = черновик.размер {
            let заметка = хранилище.запись.гардероб.заметки(бренда: черновик.бренд)
                .last { ПравилаРазмераОдежды.ключ($0.размер) == ПравилаРазмераОдежды.ключ(р.коротко) }
            посадка = заметка?.посадка
            где = заметка?.текст ?? ""
        }
    }

    private func обработать(_ источник: ИсточникСнимкаМоего) {
        задача?.cancel()
        обработка = true
        задача = Task { @MainActor in
            let итог = await Task.detached(priority: .userInitiated) {
                ОбработкаВещиГардероба.обработать(источник)
            }.value
            guard !Task.isCancelled else { return }
            обработка = false
            guard let итог else {
                ОткликСайта.предупреждение()
                показатьВесть(т("mw_photo_bad"))
                return
            }
            withAnimation(ДвижениеСайта.мягко(.spring(response: 0.45, dampingFraction: 0.82))) {
                снимок = итог
                убратьФото = false
                if !цветТронут && !итог.цвета.isEmpty {
                    черновик.цвета = итог.цвета
                    черновик.цветСам = true
                }
                if !видТронут, let найден = итог.вид {
                    черновик.вид = найден
                    слойВыбора = найден.слой
                    видПоФото = true
                    поправитьРазмер()
                }
            }
            ОткликСайта.успех()
            UIAccessibility.post(notification: .announcement, argument: т(итог.вырезано ? "mw_photo_cut" : "mw_photo_kept"))
        }
    }

    private func сохранить() {
        guard !обработка else { return }
        var вещь = черновик
        вещь.нормализовать()
        let id = вещь.id
        let новая = было(id) == false
        if новая && хранилище.запись.гардероб.вещи.count >= ГардеробМоего.пределВещей {
            ОткликСайта.предупреждение()
            показатьВесть(т("mw_full"))
            return
        }
        let заметка = заметкаПосадки(вещь)
        хранилище.обновитьГардероб { г in
            if let i = г.вещи.firstIndex(where: { $0.id == id }) {
                вещь.фото = г.вещи[i].фото
                г.вещи[i] = вещь
            } else {
                вещь.фото = nil
                г.вещи.insert(вещь, at: 0)
            }
            if let заметка { ПосадкаГардероба.записать(заметка, в: &г) }
        }
        if убратьФото && снимок == nil { хранилище.удалитьФото(.вещьГардероба(id)) }
        if let снимок {
            let склад = хранилище
            Task { @MainActor in
                _ = await склад.сохранитьФото(снимок.готовое, место: .вещьГардероба(id), расширение: снимок.расширение)
            }
        }
        ОткликСайта.успех()
        закрыть()
    }

    /// Вещь с этим номером уже в записи.
    private func было(_ id: UUID) -> Bool { хранилище.запись.гардероб.вещь(id) != nil }

    /// Заметка посадки из листа: бренд, размер как на бирке и «как сидит» — все три есть.
    private func заметкаПосадки(_ вещь: ВещьГардеробаМоего) -> ЗаметкаПосадкиМоего? {
        let бренд = вещь.бренд.trimmingCharacters(in: .whitespaces)
        guard let посадка, let р = вещь.размер, !бренд.isEmpty else { return nil }
        return ЗаметкаПосадкиМоего(бренд: бренд, вид: р.вид, размер: String(р.коротко.prefix(16)), посадка: посадка,
                                   текст: String(где.prefix(60)))
    }

    /// Купленное на Kliko уходит вместе с отметкой сделки (его снова можно добавить из покупок).
    private func удалить() {
        let id = черновик.id
        if let сделка = черновик.покупка?.сделка, хранилище.запись.изСделок[сделка] == id {
            хранилище.убратьПокупку(сделка: сделка)
        } else {
            хранилище.обновитьГардероб { г in г.вещи.removeAll { $0.id == id } }
        }
        ОткликСайта.успех()
        закрыть()
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

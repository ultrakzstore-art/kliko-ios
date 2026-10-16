import SwiftUI
import UIKit

/**
 «МОЁ» — «МОЙ КОМПЬЮТЕР / НОУТБУК» (владелец 16.10.2026: «мой компьютер — видюха или ОЗУ; подсказывать — можно так или
 так; показывать, что был куплен там — цифровизация реальности»; docs/STANDARDS.md §8.1, §6.5, §8.8).

 Экран: до четырёх компьютеров лентой сверху (главный — со звездой: с ним сверяются объявления и в него ложатся
 купленные детали); карточка вида — настольный или ноутбук, своё название, модель («B550M DS3H» сама даёт сокет и
 чипсет), «Куплено на Kliko · окт 2026 · 250 000 ₸»; живая схема (MyThingsPCScheme.swift) с лентой частей и панелью
 выбора по стандартам (MyThingsPCParts.swift), шаблон — меню над схемой; «Заполнить по снимку экрана»
 (MyThingsPCScan.swift); «Можно улучшить» (MyThingsPCUpgradeView.swift); купленное на Kliko для этого компьютера с
 вопросом «Поставили?» (MyThingsPCHistory.swift); история «добавлен · поставили · заменили» с датами; «Удалить с
 телефона». Пусто — карточка «Компьютер или ноутбук»: два вида, шаблоны и снимок экрана — первая минута без пустых полей.

 Только на телефоне (МоёХранилище.обновитьКомпьютер); правка — сразу, история правок — при уходе с экрана и в фоне
 (сравнение со снимком при входе). Скорость: экран наблюдает только хранилище «Моего»; тяжёлого в body нет — подсказки
 и цены считает блок апгрейда в своей задаче, разбор снимка экрана — вне главной нити. Подача — как у «Моего» v1:
 карточки, ровная сетка до 680 pt, Theme, ДвижениеСайта (тихо и лёгкий режим), VoiceOver, тёмная тема.
 */
struct ЭкранМоегоКомпьютера: View {
    @ObservedObject private var хранилище = МоёХранилище.shared
    @Environment(\.scenePhase) private var фаза
    @Environment(\.открытьОбъявлениеВСтеке) private var открытьВСтеке
    @State private var выбранный: UUID? = nil
    @State private var часть: ЧастьКомпьютераМоего = .память
    @State private var вспышка: Set<ЧастьКомпьютераМоего> = []
    @State private var скан = false
    @State private var спроситьУдалить = false
    /// Компьютеры при входе на экран — с ними сравниваются правки для истории.
    @State private var снимок: [UUID: КомпьютерМоего] = [:]
    /// «Поставили? — Позже» до следующего входа.
    @State private var позже: Set<UUID> = []
    @State private var всяИстория = false
    @State private var весть: String? = nil
    @State private var номерВести = 0

    init() {}

    private func т(_ ключ: String) -> String { МойКомпьютерText.т(ключ) }

    var body: some View {
        let запись = хранилище.запись
        let текущий = запись.компьютер(выбранный) ?? запись.главныйКомпьютер
        ScrollView {
            VStack(spacing: 14) {
                if let текущий {
                    содержимое(текущий, запись)
                } else {
                    пусто
                }
            }
            .padding(16)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
            .animation(ДвижениеСайта.смена, value: текущий?.id)
            .animation(ДвижениеСайта.вставкаСписка, value: запись.компьютеры.count)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .шапкаЭкранаСайта(МоёText.т("my_pc"))
        .клавиатураМоего()
        .toolbar { меню(текущий, запись) }
        .sheet(isPresented: $скан) {
            ЛистСканаКомпьютераМоего(вид: текущий?.вид) { находки in
                применитьСкан(находки, текущий?.id)
            }
        }
        .confirmationDialog(String(format: т("mpc_delete_q"), текущий?.заголовок ?? ""), isPresented: $спроситьУдалить,
                            titleVisibility: .visible) {
            Button(МоёText.т("my_delete"), role: .destructive) {
                if let текущий { удалить(текущий.id) }
            }
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
        .onAppear {
            хранилище.подготовить()
            запомнить()
        }
        .onDisappear { записатьИсторию() }
        .onChange(of: фаза) { _, новая in
            if новая != .active { записатьИсторию() }
        }
    }

    @ViewBuilder
    private func содержимое(_ к: КомпьютерМоего, _ запись: ЗаписьМоего) -> some View {
        if запись.компьютеры.count > 1 {
            полоса(к, запись)
        }
        карточкаВида(к, главный: запись.главныйКомпьютер?.id == к.id, несколько: запись.компьютеры.count > 1)
        карточкаСхемы(к)
        карточкаСкана
        БлокАпгрейдаМоего(компьютер: к,
                          открытьТовар: { товар in ПереходыКомпьютераМоего.открыть(товар, вСтеке: открытьВСтеке) },
                          найти: { запрос, раздел in ПереходыКомпьютераМоего.найти(запрос, раздел: раздел) },
                          продать: { название in продатьСтарую(название) })
            .id(к.id)
        купленное(к, запись)
        история(к)
        низ
    }

    // MARK: - Меню и лента компьютеров

    @ToolbarContentBuilder
    private func меню(_ к: КомпьютерМоего?, _ запись: ЗаписьМоего) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if запись.компьютеры.count < ЗаписьМоего.пределКомпьютеров {
                    Button { добавить(.настольный) } label: {
                        Label(т("mpc_add_desktop"), systemImage: ВидКомпьютераМоего.настольный.значок)
                    }
                    Button { добавить(.ноутбук) } label: {
                        Label(т("mpc_add_laptop"), systemImage: ВидКомпьютераМоего.ноутбук.значок)
                    }
                }
                if let к {
                    Button { скан = true } label: {
                        Label(т("mpc_scan_btn"), systemImage: "text.viewfinder")
                    }
                    if запись.главныйКомпьютер?.id != к.id {
                        Button { сделатьГлавным(к.id) } label: {
                            Label(т("mpc_make_main"), systemImage: "star")
                        }
                    }
                    Button(role: .destructive) { спроситьУдалить = true } label: {
                        Label(т("mpc_delete"), systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel(МоёText.т("my_more_actions"))
            }
        }
    }

    /// Несколько компьютеров — лента чипов; главный — со звездой; «＋» — ещё один (до четырёх).
    private func полоса(_ к: КомпьютерМоего, _ запись: ЗаписьМоего) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(запись.компьютеры) { другой in
                    ЧипМоего(другой.заголовок, выбран: другой.id == к.id,
                             значок: другой.id == запись.главныйКомпьютер?.id ? "star.fill" : другой.вид.значок) {
                        ОткликСайта.выбор()
                        withAnimation(ДвижениеСайта.смена) { выбранный = другой.id }
                    }
                }
                if запись.компьютеры.count < ЗаписьМоего.пределКомпьютеров {
                    Menu {
                        Button(ВидКомпьютераМоего.настольный.название) { добавить(.настольный) }
                        Button(ВидКомпьютераМоего.ноутбук.название) { добавить(.ноутбук) }
                    } label: {
                        Label(МоёText.т("my_add"), systemImage: "plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.акцент)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(Theme.оттенокАкцента, in: Capsule())
                            .overlay { Capsule().strokeBorder(Theme.рамкаПункта, lineWidth: 1) }
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
    }

    // MARK: - Вид, название, модель

    private func карточкаВида(_ к: КомпьютерМоего, главный: Bool, несколько: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ЗначокПрофиляМоего(значок: к.вид.значок, цвет: РазделМоего.компьютер.цвет)
                VStack(alignment: .leading, spacing: 2) {
                    Text(к.заголовок)
                        .font(.headline)
                        .foregroundStyle(Theme.текст)
                        .lineLimit(2)
                    Text(к.сводка.isEmpty ? т("mpc_summary_empty") : к.сводка)
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
                if главный && несколько {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Theme.золото)
                        .accessibilityLabel(т("mpc_main"))
                }
            }
            .accessibilityElement(children: .combine)
            Picker(т("mpc_kind"), selection: Binding(get: { к.вид }, set: { новый in сменитьВид(к.id, новый) })) {
                ForEach(ВидКомпьютераМоего.allCases, id: \.self) { вид in
                    Text(вид.название).tag(вид)
                }
            }
            .pickerStyle(.segmented)
            ПолеТекстаКомпьютераМоего(заголовок: т("mpc_name"), подсказка: т("mpc_name_ph"), значение: к.имя,
                                      предел: КомпьютерМоего.пределИмени) { новое in
                изменить(к.id) { $0.имя = новое }
            }
            ПолеТекстаКомпьютераМоего(заголовок: т(к.вид == .ноутбук ? "mpc_model_laptop" : "mpc_model_board"),
                                      подсказка: т(к.вид == .ноутбук ? "mpc_model_laptop_ph" : "mpc_model_board_ph"),
                                      значение: к.модель, предел: 80) { новая in
                принятьМодель(к.id, новая)
            }
            if let покупка = к.покупка {
                Label(покупка.подписьСЦеной, systemImage: "bag.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.золото)
            }
        }
        .карточкаМоего()
        .animation(ДвижениеСайта.смена, value: к.сводка)
    }

    /// Модель платы («B550M DS3H») — сокет и чипсет сами; у ноутбука — только модель.
    private func принятьМодель(_ id: UUID, _ модель: String) {
        изменить(id) { к in
            к.модель = модель
            guard к.вид == .настольный, !модель.isEmpty else { return }
            let набор = РазборСтандартов.разобрать(текст: модель, семьи: [.сокет], источник: .продавец).набор
            if let ч = набор[.сокет, КлючСтандарта.чипсет] { к.чипсет = ч }
            if к.сокет == nil, let с = набор[.сокет, КлючСтандарта.сокет] { к.сокет = с }
        }
    }

    private func сменитьВид(_ id: UUID, _ новый: ВидКомпьютераМоего) {
        ОткликСайта.выбор()
        изменить(id) { $0.вид = новый }
        if !ЧастьКомпьютераМоего.части(новый).contains(часть) {
            withAnimation(ДвижениеСайта.выбор) { часть = .память }
        }
    }

    // MARK: - Схема и панель

    private func карточкаСхемы(_ к: КомпьютерМоего) -> some View {
        let части = ЧастьКомпьютераМоего.части(к.вид)
        let выбранная = части.contains(часть) ? часть : .память
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ЗаголовокМоего(т("mpc_scheme"), значок: "cpu")
                Spacer(minLength: 8)
                шаблоны(к)
            }
            ЖиваяСхемаКомпьютераМоего(компьютер: к, выбрана: выбранная, вспышка: вспышка) { новая in
                выбрать(новая)
            }
            лентаЧастей(к, выбранная)
            Divider()
            ПанельЧастиКомпьютераМоего(часть: выбранная, компьютер: привязка(к.id))
                .id(выбранная)
                .transition(.opacity)
        }
        .карточкаМоего()
        .animation(ДвижениеСайта.смена, value: выбранная)
    }

    private func выбрать(_ новая: ЧастьКомпьютераМоего) {
        guard новая != часть else { return }
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.выбор) { часть = новая }
    }

    private func лентаЧастей(_ к: КомпьютерМоего, _ выбранная: ЧастьКомпьютераМоего) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ЧастьКомпьютераМоего.части(к.вид)) { ч in
                    ВкладкаЧастиКомпьютераМоего(часть: ч, выбрана: ч == выбранная, заполнена: ч.заполнена(к)) {
                        выбрать(ч)
                    }
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
    }

    /// Правка компьютера через панель: сразу в хранилище; удалённый — не воскрешаем.
    private func привязка(_ id: UUID) -> Binding<КомпьютерМоего> {
        Binding(get: { хранилище.запись.компьютер(id) ?? КомпьютерМоего(id: id, вид: .настольный) },
                set: { новый in
                    guard хранилище.запись.компьютер(id) != nil else { return }
                    хранилище.обновитьКомпьютер(новый)
                })
    }

    private func изменить(_ id: UUID, _ правка: (inout КомпьютерМоего) -> Void) {
        guard var к = хранилище.запись.компьютер(id) else { return }
        правка(&к)
        хранилище.обновитьКомпьютер(к)
    }

    // MARK: - Шаблоны

    /// «Шаблон ▾» над схемой: частые сборки своего вида — касание ставит части (название и история — свои).
    private func шаблоны(_ к: КомпьютерМоего) -> some View {
        let приставка = к.вид == .ноутбук ? "laptop" : "pc"
        return Menu {
            ForEach(ШаблонКомпьютераМоего.все.filter { $0.id.hasPrefix(приставка) }) { ш in
                Button(ш.подпись) { применитьШаблон(ш, к.id) }
            }
        } label: {
            Label(т("mpc_template"), systemImage: "square.grid.2x2")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.акцент)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(Theme.оттенокАкцента, in: Capsule())
        }
        .accessibilityHint(т("mpc_template_hint"))
    }

    private func применитьШаблон(_ ш: ШаблонКомпьютераМоего, _ id: UUID) {
        let образец = ш.компьютер()
        изменить(id) { к in
            к.вид = образец.вид
            if образец.сокет != nil { к.сокет = образец.сокет }
            if образец.tdp != nil { к.tdp = образец.tdp }
            к.память = образец.память
            if !образец.бп.пусто { к.бп = образец.бп }
            if !образец.корпус.пусто { к.корпус = образец.корпус }
            if !образец.слотыM2.isEmpty { к.слотыM2 = образец.слотыM2 }
            if образец.отсеков25 != nil { к.отсеков25 = образец.отсеков25 }
            if !образец.накопители.isEmpty { к.накопители = образец.накопители }
            к.записать("template", ш.подпись)
        }
        запомнить(id)
        ОткликСайта.успех()
        вспыхнуть(Set(ЧастьКомпьютераМоего.части(образец.вид)))
        показатьВесть(т("mpc_template_done"))
    }

    // MARK: - Снимок экрана

    private var карточкаСкана: some View {
        VStack(alignment: .leading, spacing: 10) {
            ЗаголовокМоего(т("mpc_scan_card"), значок: "text.viewfinder")
            Text(т("mpc_scan_card_sub"))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ЗелёнаяКнопкаФото(заголовок: т("mpc_scan_btn"), значок: "photo.on.rectangle", контурная: true) {
                ОткликСайта.выбор()
                скан = true
            }
        }
        .карточкаМоего()
    }

    /// Найденное на снимке — в компьютер (нет компьютера — новый, вид — со снимка), с событием и вспышкой частей.
    private func применитьСкан(_ находки: [НаходкаСнимкаКомпьютераМоего], _ id: UUID?) {
        guard !находки.isEmpty else { return }
        var части = Set<ЧастьКомпьютераМоего>()
        if let id, хранилище.запись.компьютер(id) != nil {
            изменить(id) { к in
                части = РазборСнимкаКомпьютераМоего.применить(находки, к: &к)
                к.записать("scan", "")
            }
            запомнить(id)
        } else {
            var вид = ВидКомпьютераМоего.настольный
            for н in находки {
                if case .вид(let найденный, _) = н { вид = найденный }
            }
            var новый = КомпьютерМоего(вид: вид)
            новый.записать("added", "")
            части = РазборСнимкаКомпьютераМоего.применить(находки, к: &новый)
            новый.записать("scan", "")
            guard хранилище.добавитьКомпьютер(новый) else { return }
            снимок[новый.id] = новый
            выбранный = новый.id
        }
        let порядок: [ЧастьКомпьютераМоего] = [.память, .процессор, .накопители, .видеокарта]
        if let первая = порядок.first(where: { части.contains($0) }) { часть = первая }
        вспыхнуть(части)
        показатьВесть(т("mpc_scan_done"))
    }

    // MARK: - Купленное на Kliko

    @ViewBuilder
    private func купленное(_ к: КомпьютерМоего, _ запись: ЗаписьМоего) -> some View {
        let вещи = запись.вещиВ(.компьютер, к.id)
        if !вещи.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ЗаголовокМоего(т("mpc_bought_title"), значок: "bag")
                ForEach(вещи) { вещь in
                    строкаКупленного(вещь, к)
                }
            }
            .карточкаМоего()
        }
        // «Добавить из моих покупок» — цель стека регистрирует хаб (или окно «Моего»).
        if Config.покупкиВМоё {
            ПереходРазделаМоего(цель: .изПокупок) {
                КарточкаПокупокМоего(добавлено: запись.изСделок.count)
            }
        }
    }

    private func строкаКупленного(_ вещь: ВещьМоего, _ к: КомпьютерМоего) -> some View {
        let поставлена = ИсторияКомпьютераМоего.поставлена(вещь, в: к)
        let подпись = (вещь.покупка?.подписьСЦеной ?? МоёText.т("my_bought_kliko"))
            + (поставлена ? " · " + т("mpc_installed") : "")
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: поставлена ? "checkmark.circle.fill" : "shippingbox")
                    .foregroundStyle(поставлена ? Theme.зелёный2 : Theme.золото)
                VStack(alignment: .leading, spacing: 2) {
                    Text(вещь.название)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(2)
                    Text(подпись)
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if !поставлена && !позже.contains(вещь.id) {
                Text(т("mpc_installed_q"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                ПотокЧипов(зазор: 8) {
                    МалаяКнопкаАвтоподбора(заголовок: т("mpc_installed_yes"), значок: "checkmark") {
                        поставить(вещь, к.id)
                    }
                    МалаяКнопкаАвтоподбора(заголовок: т("mpc_later"), значок: "clock") {
                        ОткликСайта.выбор()
                        withAnimation(ДвижениеСайта.смена) { _ = позже.insert(вещь.id) }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }

    /// «Да, поставили»: конфигурация — по стандартам детали, в историю — «Поставили».
    private func поставить(_ вещь: ВещьМоего, _ id: UUID) {
        var найденная: ЧастьКомпьютераМоего? = nil
        изменить(id) { к in
            найденная = ИсторияКомпьютераМоего.поставить(вещь, в: &к)
            ИсторияКомпьютераМоего.отметить(вещь, часть: найденная, в: &к)
        }
        запомнить(id)
        ОткликСайта.успех()
        if let найденная {
            withAnimation(ДвижениеСайта.выбор) { часть = найденная }
            вспыхнуть([найденная])
        }
        показатьВесть(т("mpc_installed_done"))
    }

    // MARK: - История

    @ViewBuilder
    private func история(_ к: КомпьютерМоего) -> some View {
        if !к.история.isEmpty {
            let события = Array(к.история.reversed())
            let видно = всяИстория ? события : Array(события.prefix(5))
            VStack(alignment: .leading, spacing: 10) {
                ЗаголовокМоего(т("mpc_history"), значок: "clock.arrow.circlepath")
                ForEach(видно) { событие in
                    строкаИстории(событие)
                }
                if события.count > 5 {
                    Button {
                        ОткликСайта.выбор()
                        withAnimation(ДвижениеСайта.вставкаСписка) { всяИстория.toggle() }
                    } label: {
                        Text(всяИстория ? т("mpc_history_less")
                                 : String(format: т("mpc_history_all"), String(события.count)))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.акцент)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(НажатиеКнопкиФото(сжатие: 0.96))
                }
            }
            .карточкаМоего()
        }
    }

    private func строкаИстории(_ событие: СобытиеКомпьютераМоего) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ИсторияКомпьютераМоего.значок(событие))
                .foregroundStyle(Theme.акцент)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(ИсторияКомпьютераМоего.заголовок(событие))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                if !событие.текст.isEmpty {
                    Text(событие.текст)
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(ФорматКомпьютераМоего.дата(событие.когда))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.текстВторой)
        }
        .accessibilityElement(children: .combine)
        .transition(.opacity)
    }

    // MARK: - Низ и пусто

    private var низ: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(т("mpc_local"))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Theme.акцент)
            }
            .font(.footnote)
            .foregroundStyle(Theme.текстВторой)
            Button {
                спроситьУдалить = true
            } label: {
                Label(т("mpc_delete"), systemImage: "trash")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.скидкаТекст)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.96))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    /// Ни одного компьютера: два вида, снимок экрана и шаблоны — без пустых полей.
    private var пусто: some View {
        VStack(alignment: .leading, spacing: 14) {
            ЗначокПрофиляМоего(значок: "desktopcomputer", цвет: РазделМоего.компьютер.цвет, размер: 56)
            Text(т("mpc_empty_title"))
                .font(.title3.weight(.heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            Text(т("mpc_empty_sub"))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                кнопкаВида(.настольный)
                кнопкаВида(.ноутбук)
            }
            ЗелёнаяКнопкаФото(заголовок: т("mpc_scan_btn"), значок: "text.viewfinder", контурная: true) {
                ОткликСайта.выбор()
                скан = true
            }
            ГруппаЧиповКомпьютераМоего(т("mpc_templates_start")) {
                ForEach(ШаблонКомпьютераМоего.все) { ш in
                    ЧипМоего(ш.подпись, выбран: false, значок: "square.grid.2x2") {
                        добавитьИзШаблона(ш)
                    }
                }
            }
            Label {
                Text(т("mpc_local"))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Theme.акцент)
            }
            .font(.footnote)
            .foregroundStyle(Theme.текстВторой)
        }
        .карточкаМоего()
        .появлениеМоего(0)
    }

    private func кнопкаВида(_ вид: ВидКомпьютераМоего) -> some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return Button {
            добавить(вид)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: вид.значок)
                    .font(.system(size: 30, weight: .semibold))
                    .accessibilityHidden(true)
                Text(вид.название)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.акцент)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(Theme.оттенокАкцента, in: форма)
            .overlay { форма.strokeBorder(Theme.рамкаПункта, lineWidth: 1) }
            .contentShape(форма)
        }
        .buttonStyle(НажатиеСайта())
        .accessibilityLabel(String(format: т("mpc_add_kind"), вид.название))
    }

    // MARK: - Действия

    private func добавить(_ вид: ВидКомпьютераМоего) {
        var новый = КомпьютерМоего(вид: вид)
        новый.записать("added", "")
        guard хранилище.добавитьКомпьютер(новый) else { return }
        ОткликСайта.успех()
        снимок[новый.id] = новый
        withAnimation(ДвижениеСайта.смена) {
            выбранный = новый.id
            часть = .память
        }
    }

    private func добавитьИзШаблона(_ ш: ШаблонКомпьютераМоего) {
        var новый = ш.компьютер()
        новый.записать("added", "")
        новый.записать("template", ш.подпись)
        guard хранилище.добавитьКомпьютер(новый) else { return }
        ОткликСайта.успех()
        снимок[новый.id] = новый
        withAnimation(ДвижениеСайта.смена) {
            выбранный = новый.id
            часть = .память
        }
        показатьВесть(т("mpc_template_done"))
    }

    private func сделатьГлавным(_ id: UUID) {
        хранилище.сделатьГлавным(компьютер: id)
        ОткликСайта.успех()
        показатьВесть(т("mpc_main_done"))
    }

    private func удалить(_ id: UUID) {
        хранилище.удалитьКомпьютер(id)
        снимок[id] = nil
        выбранный = nil
        ОткликСайта.успех()
        показатьВесть(т("mpc_deleted"))
    }

    /// «Продать старую деталь»: название — в буфер обмена (весть говорит об этом), потом мастер подачи.
    private func продатьСтарую(_ название: String) {
        ОткликСайта.выбор()
        показатьВесть(String(format: т("mpc_sell_copied"), название))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            ПереходыКомпьютераМоего.продать(название: название)
        }
    }

    // MARK: - История правок

    private func запомнить() {
        снимок = Dictionary(хранилище.запись.компьютеры.map { ($0.id, $0) }, uniquingKeysWith: { первый, _ in первый })
    }

    private func запомнить(_ id: UUID) {
        снимок[id] = хранилище.запись.компьютер(id)
    }

    /// Правки с входа — событиями истории (по одному на часть), затем новый снимок.
    private func записатьИсторию() {
        let сейчас = Date()
        var правки: [UUID: [(что: String, текст: String)]] = [:]
        for к in хранилище.запись.компьютеры {
            guard let прежний = снимок[к.id], !ИсторияКомпьютераМоего.заполняется(к, сейчас: сейчас) else { continue }
            let события = ИсторияКомпьютераМоего.события(было: прежний, стало: к)
            if !события.isEmpty { правки[к.id] = события }
        }
        if !правки.isEmpty {
            хранилище.обновитьКомпьютеры { список in
                for i in список.indices {
                    guard let события = правки[список[i].id] else { continue }
                    for с in события { список[i].записать(с.что, с.текст, когда: сейчас) }
                }
            }
        }
        запомнить()
    }

    // MARK: - Вспышка и весть

    private func вспыхнуть(_ части: Set<ЧастьКомпьютераМоего>) {
        guard !части.isEmpty else { return }
        withAnimation(ДвижениеСайта.мягко(.easeOut(duration: 0.25))) { вспышка = части }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            withAnimation(ДвижениеСайта.мягко(.easeInOut(duration: 0.6))) { вспышка = [] }
        }
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

// MARK: - Вкладка части

/// Вкладка ленты частей под схемой: значок, имя и точка «заполнено»; выбранная — зелёная.
private struct ВкладкаЧастиКомпьютераМоего: View {
    let часть: ЧастьКомпьютераМоего
    let выбрана: Bool
    let заполнена: Bool
    let действие: () -> Void

    init(часть: ЧастьКомпьютераМоего, выбрана: Bool, заполнена: Bool, действие: @escaping () -> Void) {
        self.часть = часть
        self.выбрана = выбрана
        self.заполнена = заполнена
        self.действие = действие
    }

    private var точка: Color {
        if выбрана { return заполнена ? Color.white : Color.white.opacity(0.4) }
        return заполнена ? Theme.зелёный2 : Theme.линия
    }

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                Image(systemName: часть.значок)
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
                Text(часть.название)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Circle()
                    .fill(точка)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(выбрана ? Color.white : Theme.акцент)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(выбрана ? AnyShapeStyle(Theme.зелёный2) : AnyShapeStyle(Theme.оттенокАкцента), in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.рамкаПункта, lineWidth: выбрана ? 0 : 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.95))
        .accessibilityLabel(часть.название)
        .accessibilityValue(МойКомпьютерText.т(заполнена ? "mpc_filled" : "mpc_unset"))
        .accessibilityAddTraits(выбрана ? .isSelected : [])
        .animation(ДвижениеСайта.выбор, value: выбрана)
    }
}

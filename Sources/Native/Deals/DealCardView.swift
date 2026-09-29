import SwiftUI
import UIKit

/**
 КАРТОЧКА СДЕЛКИ — ЭКРАН, ЭТАП 43 (владелец 26.09.2026: «всё одно и то же, просто код разный»; Config.нативныеСделки).

 Модалка #deal-modal сайта (renderDeal, карта §4.3–§4.5) сверху вниз: товар, роль и собеседник, выбор способа оплаты
 покупателем, плашка статуса; полоса «Спор · решение за 24–48 ч»; баннер задатка или аренды; мастер шагов («Шаг N из 5»)
 с действиями этого шага и блоком передачи внутри; после завершения — «Связь с покупателем / продавцом» и контакты;
 межгород; «Перед передачей: снимите блокировку» для телефонов; свёрнутые «Деньги и документы» и «История сделки».
 Пока сделка идёт — плавающая «Связь с …» (переписка приложения, dm.php).
 Живое обновление, Live Activity, запросы — КарточкаСделкиМодель. Денежная кнопка шлёт НажатиеСделки.деньги(…) — окна
 СлойДенегСделки (ДеньгиСделкиМодель); посылка, встреча, возврат и курьер по городу — свои блоки и окна СлойПередачиСделки
 (ПередачаСделкиМодель). На сайт карточка не уводит ни одним нажатием.
 */
struct ЭкранСделки: View {
    @StateObject private var модель: КарточкаСделкиМодель
    let открыть: (URL) -> Void

    @State private var спорОткрыт = false
    @State private var чекОткрыт = false
    @State private var спроситьОтклонить = false
    @State private var спроситьСмену = false
    @State private var способЗаперт = false
    @State private var спроситьСпорВозврата = false
    @State private var навигатор: ВыборНавигатора? = nil
    @State private var входОткрыт = false
    /// Окно «Откуда забрать» / «Куда доставить» (DealPickupMap.swift).
    @State private var точкаНаКарте: ТочкаНаКартеСделки? = nil
    /// Лист «Отслеживание» (Sources/Native/Tracking) вместо ссылок Яндекса и перевозчика.
    @State private var отслеживаниеОткрыто = false

    init(id: String, открыть: @escaping (URL) -> Void) {
        _модель = StateObject(wrappedValue: КарточкаСделкиМодель(id: id))
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    var body: some View {
        содержимое
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.поверхность.ignoresSafeArea())
            .modifier(ШапкаСделок(заголовок: модель.id))
            .task { await модель.появилась() }
            .onDisappear { модель.исчезла() }
            .overlay(alignment: .bottom) { плашкаВнизу }
            .onChange(of: модель.просьбаТочкиКуда) { _, _ in
                /* Курьеру нужна точка «куда везти» — окно карты, как hovAddrOpen сайта после подсказки. */
                guard let с = модель.сделка, точкаНаКарте == nil else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { точкаНаКарте = ТочкаНаКартеСделки.куда(с) }
            }
            /* Этап 44: окна денег (баллы, отмена, приёмка, eGov, банк, ход) — живут только за Config.деньгиСделок. */
            .modifier(СлойДенегСделки(деньги: модель.деньги, спор: $спорОткрыт, открыть: открыть))
            /* Передача своими блоками: окна посылки, встречи, возврата и курьера, вопросы, сканер QR. */
            .modifier(СлойПередачиСделки(передача: модель.передача, карточка: модель))
            .sheet(isPresented: $спорОткрыт) {
                if let с = модель.сделка {
                    ОкноСпора(сделка: с, модель: модель, закрыть: { спорОткрыт = false })
                }
            }
            .sheet(isPresented: $чекОткрыт) {
                if let с = модель.сделка {
                    ЧекСделки(сделка: с, закрыть: { чекОткрыт = false })
                }
            }
            .sheet(item: $точкаНаКарте) { цель in
                ЛистТочкиСделки(цель: цель, модель: модель)
            }
            .sheet(isPresented: $отслеживаниеОткрыто) {
                NavigationStack {
                    ЭкранОтслеживания(сделка: модель.id, можноМенять: модель.сделка?.можноМенятьТрек ?? false)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(т("close")) { отслеживаниеОткрыто = false }
                            }
                        }
                }
                .presentationDetents([.medium, .large])
            }
            .onReceive(NotificationCenter.default.publisher(for: .klikoТрекИзменился)) { весть in
                /* Новый статус доставки — и на плашку экрана блокировки. */
                guard (весть.userInfo?["deal"] as? String) == модель.id, let с = модель.сделка else { return }
                ЖиваяСделка.показать(с)
            }
            .sheet(isPresented: eGovТалонаНаЭкране) {
                if let запрос = модель.eGovТалона {
                    ОкноEGov(запрос: запрос, готово: { модель.послеEGovТалона() }, закрыть: { модель.eGovТалона = nil })
                }
            }
            .sheet(isPresented: $входОткрыт) {
                ЭкранВхода(eGovВключён: true, открыть: открыть, вошли: {
                    Task { await модель.загрузить() }
                })
            }
            .alert(т("at_reject_q"), isPresented: $спроситьОтклонить) {
                Button(т("at_reject_ok"), role: .destructive) { модель.условия(принять: false) }
                Button(т("at_reject_back"), role: .cancel) {}
            } message: {
                Text(т("at_reject_msg"))
            }
            .alert(т((модель.сделка?.продавец ?? false) ? "hnd_switch" : "hnd_switch_b"), isPresented: $спроситьСмену) {
                Button(т("hnd_switch_yes"), role: .destructive) { модель.способ("") }
                Button(т("btn_cancel"), role: .cancel) {}
            } message: {
                Text(т("hnd_switch_q2"))
            }
            .alert(т("ret_disp_t"), isPresented: $спроситьСпорВозврата) {
                Button(т("ret_disp_ok")) { спорВозврата() }
                Button(т("btn_cancel"), role: .cancel) {}
            } message: {
                Text(т("ret_disp_m"))
            }
            .alert(т("hnd_lock_t"), isPresented: $способЗаперт) {
                Button(т("hnd_lock_ok"), role: .cancel) {}
            } message: {
                Text(т("hnd_lock_m"))
            }
            .alert(модель.окно?.заголовок ?? "", isPresented: окноНаЭкране) {
                Button(т("hnd_lock_ok"), role: .cancel) {}
            } message: {
                Text(модель.окно?.текст ?? "")
            }
            .confirmationDialog(навигатор?.заголовок ?? "", isPresented: навигаторНаЭкране, titleVisibility: .visible,
                                presenting: навигатор) { выбор in
                ForEach(выбор.варианты) { вариант in
                    Button(вариант.название) {
                        if выбор.курьер { модель.курьерВызван() }
                        UIApplication.shared.open(вариант.адрес)
                    }
                }
                Button(т("btn_cancel"), role: .cancel) {}
            } message: { выбор in
                Text(выбор.текст)
            }
    }

    private var окноНаЭкране: Binding<Bool> {
        Binding(get: { модель.окно != nil }, set: { показано in
            if !показано { модель.окно = nil }
        })
    }

    private var eGovТалонаНаЭкране: Binding<Bool> {
        Binding(get: { модель.eGovТалона != nil }, set: { показано in
            if !показано { модель.eGovТалона = nil }
        })
    }

    /// clocalReturnDispute: спор return_fault без текста; ок — «Передали модератору…» вместо общего dsp_ok.
    private func спорВозврата() {
        модель.открытьСпор(код: "return_fault", текст: "", фото: nil) { ошибка in
            if ошибка == nil {
                модель.показать(т("ret_disp_done"))
            } else if let e = ошибка, !e.isEmpty {
                модель.показать(e)
            }
        }
    }

    private var навигаторНаЭкране: Binding<Bool> {
        Binding(get: { навигатор != nil }, set: { показан in
            if !показан { навигатор = nil }
        })
    }

    // MARK: - Состояния

    @ViewBuilder
    private var содержимое: some View {
        if модель.нуженВход {
            ПустоСайта(значок: "person.crop.circle", заголовок: CabinetText.т("signed_out"),
                       подпись: CabinetText.т("signed_out_sub"), кнопка: CabinetText.т("login"),
                       действие: { войти() })
        } else if let с = модель.сделка {
            ScrollViewReader { прокрутка in
                ScrollView {
                    КарточкаСделки(сделка: с, модель: модель, открыть: открыть, действие: { нажато($0) })
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                }
                .refreshable { await модель.загрузить() }
                .onChange(of: с.шаги.текущий) { старый, новый in
                    /* Шаг сменился (заморозили, отправили…): не прыгаем куда попало — ведём к новому шагу, как сайт. */
                    guard старый != новый else { return }
                    withAnimation(.easeInOut(duration: 0.35)) {
                        прокрутка.scrollTo(МастерСделки.якорьШага, anchor: .top)
                    }
                }
                /* Кнопка связи — своей нижней полосой: содержимое кончается над ней и никогда под неё не уходит. */
                .safeAreaInset(edge: .bottom, spacing: 0) { полосаСвязи }
            }
        } else if let ошибка = модель.ошибка {
            ПустоСайта(значок: "exclamationmark.triangle", заголовок: ошибка, кнопка: т("retry"),
                       действие: { Task { await модель.загрузить() } })
        } else {
            VStack(spacing: 12) {
                SiteSpinner()
                Text(т("loading"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Плашка сайта (toast) — по центру внизу.
    @ViewBuilder
    private var плашкаВнизу: some View {
        VStack(spacing: 10) {
            if let текст = модель.плашка {
                Text(текст)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.зелёный, in: Capsule())
                    .padding(.horizontal, 20)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
            /* Место под полосу «Связь с …»: плашка встаёт над ней, а не на кнопку. */
            if let с = модель.сделка, чатОткрыт(с) {
                Color.clear.frame(height: Self.высотаПолосы)
            }
        }
        .padding(.bottom, 12)
        .allowsHitTesting(false)
    }

    /// Высота полосы связи: кнопка 46 и поля 10 + 8.
    private static let высотаПолосы: CGFloat = 64

    /// «Связь с покупателем / продавцом» (#dm-chat-fab) — закреплённой полосой внизу (safeAreaInset), как нижняя панель
    /// сайта: карточка прокручивается над ней, шаги и «Деньги и документы» не прячутся под кнопкой.
    @ViewBuilder
    private var полосаСвязи: some View {
        if let с = модель.сделка, чатОткрыт(с) {
            NavigationLink(value: ЧатЦель.продавец(id: с.собеседник.id, имя: имяСобеседника(с), объявление: с.товар)) {
                ярлыкСвязи(с)
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background {
                Theme.поверхность
                    .opacity(0.97)
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.линия).frame(height: 1)
                    }
            }
        }
    }

    private func ярлыкСвязи(_ с: Сделка) -> some View {
        Label(т(с.продавец ? "dl_link_buyer" : "dl_link_seller"), systemImage: "bubble.left.and.bubble.right")
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                       endPoint: .bottomTrailing), in: Capsule())
            .shadow(color: КраскаСделокКабинета.теньКнопки.opacity(0.5), radius: 8, x: 0, y: 4)
            .contentShape(Capsule())
    }

    /// Чат по сделке: есть собеседник, чат не закрыт, сделка не закончена.
    private func чатОткрыт(_ с: Сделка) -> Bool {
        !с.собеседник.id.isEmpty && !с.собеседник.чатЗакрыт && !["confirmed", "resolved", "cancelled"].contains(с.статус)
    }

    private func имяСобеседника(_ с: Сделка) -> String {
        с.собеседник.имя.isEmpty ? т("peer_fallback") : с.собеседник.имя
    }

    // MARK: - Нажатия

    private func нажато(_ н: НажатиеСделки) {
        switch н {
        case .деньги(let действие):
            /* Деньги — своими окнами (ДеньгиСделкиМодель); на сайт карточка не уводит. Стоп-кран админки (deals_money)
               погасил деньги — не молчаливое нажатие, а своё окно «шаг пока недоступен», как у сделки с подписью eGov. */
            guard Config.деньгиСделок else {
                БезСайта.сообщить(заголовок: БезСайтаText.т("deal_t"), текст: БезСайтаText.т("deal_s"))
                return
            }
            модель.деньги.начать(действие)
        case .спор:
            спорОткрыт = true
        case .чек:
            чекОткрыт = true
        case .подтвердитьУсловия:
            модель.условия(принять: true)
        case .отклонитьЗаявку:
            спроситьОтклонить = true
        case .попроситьТалон:
            модель.попроситьТалон()
        case .подписатьТалон:
            модель.подписатьТалон()
        case .спорВозврата:
            спроситьСпорВозврата = true
        case .способ(let режим):
            модель.способ(режим)
        case .сменитьСпособ:
            спроситьСмену = true
        case .способЗаперт:
            способЗаперт = true
        case .точка(let откуда):
            if let с = модель.сделка {
                точкаНаКарте = откуда ? ТочкаНаКартеСделки.откуда(с) : ТочкаНаКартеСделки.куда(с)
            }
        case .маршрут(let адрес, let точка):
            навигатор = ВыборНавигатора.маршрут(адрес: адрес, точка: точка)
        case .курьер(let откуда, let куда):
            if let а = откуда, let б = куда {
                навигатор = ВыборНавигатора.курьер(а, б)
            } else {
                /* Сайт ищет точки по адресам через nominatim; приложение этого не делает — нужна точка на карте. */
                модель.показать(т("hnd_cr_mine"))
            }
        case .ссылка(let адрес):
            UIApplication.shared.open(адрес)
        case .отслеживание:
            /* «Где курьер» / «Отследить»: своя карточка «Отслеживание», без Safari и сайта перевозчика. */
            отслеживаниеОткрыто = true
        case .скопировать(let текст):
            UIPasteboard.general.string = текст
            модель.показать(т("copied"))
        case .страница(let хвост):
            if let адрес = Config.url(хвост) { открыть(адрес) }
        }
    }

    private func войти() {
        if Config.нативныйВход {
            входОткрыт = true
        } else if let адрес = Config.страницаСайта("cabinet.php") {
            открыть(адрес)
        }
    }
}

// MARK: - Выбор навигатора (hovRoutePick / hovCourierPick)

struct ВыборНавигатора {
    struct Вариант: Identifiable {
        let id: Int
        let название: String
        let адрес: URL
    }

    let заголовок: String
    let текст: String
    let варианты: [Вариант]
    /// Нажатие отмечает courier_called (hovCourierMark).
    let курьер: Bool

    static func маршрут(адрес: String, точка: ТочкаСделки?) -> ВыборНавигатора {
        let т = СделкиText.т
        var список: [Вариант] = []
        if let точка, let такси = НавигаторыСделки.такси(точка) {
            список.append(Вариант(id: 0, название: т("hnd_rt_taxi"), адрес: такси))
        }
        if let гис = НавигаторыСделки.дваГис(точка, адрес: адрес) {
            список.append(Вариант(id: 1, название: т("hnd_rt_2g"), адрес: гис))
        }
        let пояснение = точка == nil ? т("hnd_rt_noptr") : т("hnd_rt_taxi_s")
        return ВыборНавигатора(заголовок: т("hnd_route"), текст: адрес.isEmpty ? пояснение : адрес + "\n\n" + пояснение,
                               варианты: список, курьер: false)
    }

    static func курьер(_ а: ТочкаСделки, _ б: ТочкаСделки) -> ВыборНавигатора {
        let т = СделкиText.т
        var список: [Вариант] = []
        if let я = НавигаторыСделки.курьерЯндекса(а, б) {
            список.append(Вариант(id: 0, название: т("hnd_cr_ya"), адрес: я))
        }
        if let гис = НавигаторыСделки.таксиДваГис(а, б) {
            список.append(Вариант(id: 1, название: т("hnd_cr_2g"), адрес: гис))
        }
        return ВыборНавигатора(заголовок: т("hnd_call_courier"), текст: т("hnd_cr_ready") + "\n\n" + т("hnd_cr_note"),
                               варианты: список, курьер: true)
    }
}

// MARK: - Содержимое карточки

struct КарточкаСделки: View {
    let сделка: Сделка
    @ObservedObject var модель: КарточкаСделкиМодель
    let открыть: (URL) -> Void
    let действие: (НажатиеСделки) -> Void

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            шапка
            if сделка.статус == "disputed" { полосаСпора }
            if сделка.задаток {
                ЗаметкаСделки(ТекстСделки.сЖирным(т("dl_dep_banner")), вид: .предупреждение)
            } else if сделка.аренда {
                ЗаметкаСделки(ТекстСделки.сЖирным(т("dl_rent_banner")), вид: .инфо)
            }
            МастерСделки(сделка: сделка, модель: модель, действие: действие)
            if сделка.естьОтслеживание {
                /* Статус доставки своей карточкой; подпись сделки сменилась — карточка переспросит. */
                БлокОтслеживания(сделка: сделка.id, повод: сделка.подпись, можноМенять: сделка.можноМенятьТрек,
                                 исходнаяСсылка: сделка.ссылкаСлежения,
                                 изменено: { Task { await модель.загрузить() } })
            }
            if ["confirmed", "resolved", "cancelled"].contains(сделка.статус) {
                КонтактыСделки(сделка: сделка, открыть: открыть, действие: действие)
            }
            if let м = сделка.межгородДанные { межгород(м) }
            блокировкаАктивации
            /* .dmf подряд: margin-bottom 8. */
            VStack(alignment: .leading, spacing: 8) {
                ДеньгиИДокументы(сделка: сделка, модель: модель, открыть: открыть, действие: действие)
                ИсторияСделки(сделка: сделка)
            }
        }
    }

    // MARK: Шапка

    private var шапка: some View {
        HStack(alignment: .center, spacing: 10) {
            КартинкаЛенты(Config.url(сделка.фото), пунктов: 56) {
                ZStack {
                    Theme.поверхность2
                    Image(systemName: "shippingbox")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(сделка.название.isEmpty ? т("deals_item_fallback") : сделка.название)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Text(сделка.строкаРоли)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                if let выбор = выборОплаты {
                    (Text(т("pw_chose") + ": ") + Text(выбор).bold().foregroundColor(Theme.текст))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
                плашкаСтатуса
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }

    /// payWishLine: «Покупатель выбрал: оплата картой / с кошелька / рассрочка / кредит, N мес.».
    private var выборОплаты: String? {
        let код = сделка.способОплаты
        guard !код.isEmpty else { return nil }
        let названия: [String: String] = ["card": т("pw_card"), "wallet": т("pw_wallet"), "installment": т("pw_inst"),
                                           "credit": т("pw_credit")]
        let название = названия[код] ?? код
        return название + (сделка.срокОплаты > 0 ? ", " + String(сделка.срокОплаты) + " " + т("pw_mo") : "")
    }

    /// Статус в шапке renderDeal: серая подложка #f3f4f6 (при возврате #fff4e5) в обеих темах и свой цвет текста.
    private var плашкаСтатуса: some View {
        let символ = сделка.идётВозврат ? "arrow.uturn.backward" : ВидСтатусаСделки.для(сделка.статус).символ
        let фон: UInt32 = сделка.идётВозврат ? 0xFFF4E5 : 0xF3F4F6
        return HStack(spacing: 4) {
            Image(systemName: символ)
                .font(.system(size: 11, weight: .semibold))
                .accessibilityHidden(true)
            Text(сделка.заголовокСтатуса)
                .font(.system(size: 12, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color(uiColor: Theme.hex(краскаСтатуса)))
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(Color(uiColor: Theme.hex(фон)),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.xxs, style: .continuous))
    }

    /// Цвета текста статуса из renderDeal — одни и те же в обеих темах (подложка светлая).
    private var краскаСтатуса: UInt32 {
        if сделка.идётВозврат { return 0x9A6A10 }
        switch сделка.статус {
        case "proposed", "pending", "shipped": return 0x92400E
        case "accepted", "held":               return 0x1E40AF
        case "delivered":                      return 0x166534
        case "disputed":                       return 0x991B1B
        case "cancelled":                      return 0x6B7280
        default:                               return 0x374151
        }
    }

    /// #dm-strip: «Спор · решение за 24–48 ч».
    private var полосаСпора: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .accessibilityHidden(true)
            Text(т("dl_dsp_strip").uppercased())
                .font(.system(size: 12, weight: .heavy))
                .tracking(0.6)
            Spacer(minLength: 4)
            Text(т("dl_dsp_strip_r"))
                .font(.system(size: 12, weight: .bold))
                .opacity(0.9)
        }
        .foregroundStyle(Theme.цвет(0xFFFFFF, 0xFFE3E3))
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Theme.цвет(0xB32222, 0x7F1D1D), in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Межгород (dealCarrierCard)

    private func межгород(_ м: МежгородСделки) -> some View {
        БлокСделки {
            ЗаголовокБлокаСделки(текст: т("far_t"), символ: "truck.box")
            if !м.откуда.isEmpty || !м.куда.isEmpty {
                (Text((м.откуда.isEmpty ? "—" : м.откуда) + " → ") + Text(м.куда.isEmpty ? "—" : м.куда).bold())
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текст)
            }
            if !м.перевозчик.isEmpty {
                (Text(т("far_by")) + Text(м.перевозчик).bold())
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
            if !м.трек.isEmpty {
                КнопкаСделки(т("far_track") + м.трек, вид: .вторая, символ: "doc.on.doc") { действие(.скопировать(м.трек)) }
            }
            ЗаметкаСделки(Text(т("far_who")), вид: .предупреждение)
            ПодписьСделки(т("far_ours"))
        }
    }

    // MARK: Блокировка активации (dealIcloudCard)

    @ViewBuilder
    private var блокировкаАктивации: some View {
        if сделка.телефонИлиПланшет {
            if сделка.продавец && ["pending", "held", "shipped"].contains(сделка.статус) {
                ЗаметкаСделки(Text(т("dic_seller_title")).bold() + Text("\n" + т("dic_seller_text")), вид: .предупреждение,
                              символ: "iphone")
            } else if !сделка.продавец && ["shipped", "delivered"].contains(сделка.статус) {
                ЗаметкаСделки(Text(т("dic_buyer_title")).bold() + Text("\n" + т("dic_buyer_text"))
                              + Text("\n" + т("dic_how")).font(.system(size: 12)),
                              вид: .предупреждение, символ: "iphone")
            }
        }
    }
}

// MARK: - Мастер шагов (dealWizard)

struct МастерСделки: View {
    let сделка: Сделка
    @ObservedObject var модель: КарточкаСделкиМодель
    let действие: (НажатиеСделки) -> Void

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    var body: some View {
        let шаги = сделка.шаги
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(шаги.подписи.enumerated()), id: \.offset) { пара in
                let i = пара.offset
                if i == шаги.текущий && !шаги.всеПройдены {
                    текущий(i, подпись: пара.element, всего: шаги.подписи.count, пауза: шаги.пауза)
                } else {
                    строка(i, подпись: пара.element, пройден: i < шаги.текущий || шаги.всеПройдены)
                }
            }
            if шаги.всеПройдены {
                работаШага
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .strokeBorder(КраскаСделокКабинета.хорошоКромка, lineWidth: 1.5)
                    }
                    .padding(.top, 8)
            }
        }
    }

    /// Действия шага и блок передачи — внутри шага, как у сайта.
    private var работаШага: some View {
        VStack(alignment: .leading, spacing: 10) {
            ДействияСделки(сделка: сделка, модель: модель, действие: действие)
            if БлокПередачи.нужен(сделка) {
                БлокПередачи(сделка: сделка, модель: модель, действие: действие)
            }
        }
    }

    private func текущий(_ i: Int, подпись: String, всего: Int, пауза: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                /* Цепочка из семи «+» не укладывалась во время проверки типов (Codemagic, 26.09.2026) — склейка массивом. */
                Text([т("dw_step"), String(i + 1), т("dw_of"), String(всего)].joined(separator: " ").uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.66)
                    .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                Text(подпись)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
            }
            if !пауза.isEmpty {
                /* .dwz-frozen: и пауза, и спор — жёлтая плашка. */
                Text(пауза)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(КраскаСделокКабинета.предупреждениеТекст)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(КраскаСделокКабинета.предупреждениеФон,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                            .strokeBorder(КраскаСделокКабинета.предупреждениеКромка, lineWidth: 1.5)
                    }
            }
            работаШага
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(КраскаСделокКабинета.хорошоКромка, lineWidth: 1.5)
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
        .id(Self.якорьШага)
    }

    /// Якорь текущего шага — к нему карточка прокручивает, когда шаг сменился.
    static let якорьШага = "deal-step-current"

    private func строка(_ i: Int, подпись: String, пройден: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(пройден ? "✓" : String(i + 1))
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(пройден ? КраскаСделокКабинета.хорошоТекст : Theme.текстВторой)
                .frame(width: 22, height: 22)
                .background(пройден ? КраскаСделокКабинета.хорошоФон : Theme.поверхность2, in: Circle())
                .overlay {
                    Circle().strokeBorder(пройден ? КраскаСделокКабинета.хорошоКромка : Theme.линия, lineWidth: 1.5)
                }
            Text(подпись)
                .font(.system(size: 13))
                .foregroundStyle(пройден ? Theme.текст.opacity(0.62) : Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 22)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityValue(пройден ? т("a11y_step_done") : "")
    }
}

// MARK: - Контакты второй стороны (hovPeerCard)

struct КонтактыСделки: View {
    let сделка: Сделка
    let открыть: (URL) -> Void
    let действие: (НажатиеСделки) -> Void

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    private var п: СобеседникСделки { сделка.собеседник }

    var body: some View {
        if !п.id.isEmpty && (!п.телефон.isEmpty || !п.whatsApp.isEmpty || !п.telegram.isEmpty) {
            /* .dm-peer: рамка 1.5, поля 12/14, радиус 14. */
            VStack(alignment: .leading, spacing: 10) {
                Text(т(сделка.продавец ? "dl_link_buyer" : "dl_link_seller"))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 10) {
                    Text(String(имя.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .frame(width: 42, height: 42)
                        .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                                   endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(имя)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.текст)
                        if !п.телефон.isEmpty {
                            Text(п.телефон)
                                .font(.system(size: 13))
                                .monospacedDigit()
                                .foregroundStyle(Theme.текстВторой)
                        }
                    }
                    Spacer(minLength: 4)
                    if !п.телефон.isEmpty {
                        Button {
                            действие(.скопировать(п.телефон))
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 15))
                                .foregroundStyle(Theme.текстВторой)
                                .frame(width: 36, height: 36)
                                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms,
                                                                                    style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(т("hov_copy"))
                    }
                }
                каналы
                if let адрес = Config.страницаСайта("seller.php?id=" + СделкиAPI.вАдрес(п.id)) {
                    Button {
                        /* Витрина собеседника — своим экраном поверх сделки; номер не годится — страница сайта. */
                        if !ОкноПродавца.открыть(id: п.id, имя: п.имя) { открыть(адрес) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 16))
                                .accessibilityHidden(true)
                            Text(т(п.роль == "seller" ? "hov_prof_seller" : "hov_prof_buyer"))
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.текстВторой)
                                .flipsForRightToLeftLayoutDirection(true)
                                .accessibilityHidden(true)
                        }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                .strokeBorder(Theme.линия, lineWidth: 1.5)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, -2)
                }
                if п.чатЗакрыт { ПодписьСделки(т("hov_closed")) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
        }
    }

    private var имя: String { п.имя.isEmpty ? т("peer_fallback") : п.имя }

    private var каналы: some View {
        HStack(spacing: 8) {
            if !п.чатЗакрыт {
                NavigationLink(value: ЧатЦель.продавец(id: п.id, имя: имя, объявление: сделка.товар)) {
                    ярлык(т("hov_chat"), "bubble.left", вид: .главный)
                }
                .buttonStyle(.plain)
            }
            if !п.телефон.isEmpty, let звонок = URL(string: "tel:" + п.телефон.filter { $0.isNumber || $0 == "+" }) {
                Button { действие(.ссылка(звонок)) } label: { ярлык(т("hov_call"), "phone", вид: .обычный) }
                    .buttonStyle(.plain)
            }
            if let wa = URL(string: п.whatsApp), !п.whatsApp.isEmpty {
                Button { действие(.ссылка(wa)) } label: { ярлык("WhatsApp", "message", вид: .whatsApp) }
                    .buttonStyle(.plain)
            }
            if let tg = URL(string: п.telegram), !п.telegram.isEmpty {
                Button { действие(.ссылка(tg)) } label: { ярлык("Telegram", "paperplane", вид: .telegram) }
                    .buttonStyle(.plain)
            }
        }
    }

    /// Плитки .hov-t: .pri — градиент, .wa и .tg — свой цвет текста и рамки.
    private enum ВидЯрлыка { case главный, обычный, whatsApp, telegram }

    private func ярлык(_ текст: String, _ символ: String, вид: ВидЯрлыка) -> some View {
        let главный = вид == .главный
        let краска: Color
        let рамка: Color
        switch вид {
        case .главный:  краска = Color.white; рамка = Color.clear
        case .обычный:  краска = Theme.текст; рамка = Theme.линия
        case .whatsApp: краска = Color(uiColor: Theme.hex(0x1F9D55)); рамка = Color(uiColor: Theme.hex(0xBDE5CD))
        case .telegram: краска = Color(uiColor: Theme.hex(0x2481CC)); рамка = Color(uiColor: Theme.hex(0xBCDCF4))
        }
        let фон: AnyShapeStyle = главный
            ? AnyShapeStyle(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                           endPoint: .bottomTrailing))
            : AnyShapeStyle(Theme.поверхность)
        return VStack(spacing: 6) {
            Image(systemName: символ)
                .font(.system(size: 18))
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(краска)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(рамка, lineWidth: 1.5)
        }
    }
}

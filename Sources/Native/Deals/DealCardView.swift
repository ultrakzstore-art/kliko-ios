import SwiftUI
import UIKit

/**
 КАРТОЧКА СДЕЛКИ — ЭКРАН, ЭТАП 43 (владелец 26.09.2026: «всё одно и то же, просто код разный»; Config.нативныеСделки).

 Модалка #deal-modal сайта (renderDeal, карта §4.3–§4.5) сверху вниз: товар, роль и собеседник, выбор способа оплаты
 покупателем, плашка статуса; полоса «Спор · решение за 24–48 ч»; баннер задатка или аренды; мастер шагов («Шаг N из 5»)
 с действиями этого шага и блоком передачи внутри; после завершения — «Связь с покупателем / продавцом» и контакты;
 межгород; «Перед передачей: снимите блокировку» для телефонов; свёрнутые «Деньги и документы» и «История сделки».
 Пока сделка идёт — плавающая «Связь с …» (переписка приложения, dm.php).
 Живое обновление, Live Activity, запросы — КарточкаСделкиМодель. 🔴 Деньги — страница сделки сайта (Config.деньгиСделок).
 Этап 44: денежная кнопка шлёт НажатиеСделки.деньги(…) — при выключенном рубильнике это та же страница сайта, при
 включённом — окна СлойДенегСделки (ДеньгиСделкиМодель).
 */
struct ЭкранСделки: View {
    @StateObject private var модель: КарточкаСделкиМодель
    let открыть: (URL) -> Void

    @State private var спорОткрыт = false
    @State private var чекОткрыт = false
    @State private var спроситьОтклонить = false
    @State private var спроситьСмену = false
    @State private var способЗаперт = false
    @State private var навигатор: ВыборНавигатора? = nil
    @State private var входОткрыт = false

    init(id: String, открыть: @escaping (URL) -> Void) {
        _модель = StateObject(wrappedValue: КарточкаСделкиМодель(id: id))
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { СделкиText.т(ключ) }

    var body: some View {
        содержимое
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .modifier(ШапкаСделок(заголовок: модель.id))
            .task { await модель.появилась() }
            .onDisappear { модель.исчезла() }
            .overlay(alignment: .bottom) { низ }
            /* Этап 44: окна денег (баллы, отмена, приёмка, eGov, банк, ход) — живут только за Config.деньгиСделок. */
            .modifier(СлойДенегСделки(деньги: модель.деньги, спор: $спорОткрыт, открыть: открыть))
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
            ScrollView {
                КарточкаСделки(сделка: с, модель: модель, открыть: открыть, действие: { нажато($0) })
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 90)
            }
            .refreshable { await модель.загрузить() }
        } else if let ошибка = модель.ошибка {
            ПустоСайта(значок: "exclamationmark.triangle", заголовок: ошибка, кнопка: т("retry"),
                       действие: { Task { await модель.загрузить() } })
        } else {
            VStack(spacing: 12) {
                ProgressView()
                Text(т("loading"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Плашка сайта (toast) и плавающая «Связь с покупателем / продавцом» (dmChatSync).
    @ViewBuilder
    private var низ: some View {
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
            if let с = модель.сделка, чатОткрыт(с) {
                if Config.нативныйЧат {
                    NavigationLink(value: ЧатЦель.продавец(id: с.собеседник.id, имя: имяСобеседника(с), объявление: с.товар)) {
                        ярлыкСвязи(с)
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
                } else {
                    /* Своей переписки нет (рубильник чата выключен) — чат сделки на её странице сайта. */
                    Button { нажато(.наСайт) } label: { ярлыкСвязи(с) }
                        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
                }
            }
        }
        .padding(.bottom, 16)
    }

    private func ярлыкСвязи(_ с: Сделка) -> some View {
        Label(т(с.продавец ? "dl_link_buyer" : "dl_link_seller"), systemImage: "bubble.left.and.bubble.right")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 46)
            .background(Theme.зелёный, in: Capsule())
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
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
        case .наСайт:
            /* То, чего у приложения нет (карта, eGov-подпись, коды посылки): та же сделка на странице сайта. */
            if let адрес = Config.страницаСайта("cabinet.php?deal=" + СделкиAPI.вАдрес(модель.id)) { открыть(адрес) }
        case .деньги(let действие):
            /* 🔴 Этап 44: деньги — своими окнами только за Config.деньгиСделок (false); иначе страница сделки сайта. */
            if Config.деньгиСделок {
                модель.деньги.начать(действие)
            } else {
                нажато(.наСайт)
            }
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
        case .способ(let режим):
            модель.способ(режим)
        case .сменитьСпособ:
            спроситьСмену = true
        case .способЗаперт:
            способЗаперт = true
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
            if ["confirmed", "resolved", "cancelled"].contains(сделка.статус) {
                КонтактыСделки(сделка: сделка, открыть: открыть, действие: действие)
            }
            if let м = сделка.межгородДанные { межгород(м) }
            блокировкаАктивации
            ДеньгиИДокументы(сделка: сделка, модель: модель, открыть: открыть, действие: действие)
            ИсторияСделки(сделка: сделка)
        }
    }

    // MARK: Шапка

    private var шапка: some View {
        HStack(alignment: .top, spacing: 10) {
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
            VStack(alignment: .leading, spacing: 4) {
                Text(сделка.название.isEmpty ? т("deals_item_fallback") : сделка.название)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Text(сделка.строкаРоли)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                if let выбор = выборОплаты {
                    (Text(т("pw_chose") + ": ") + Text(выбор).bold().foregroundColor(Theme.текст))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
                плашкаСтатуса
            }
        }
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

    private var плашкаСтатуса: some View {
        let вид: ВидСтатусаСделки = сделка.идётВозврат ? .предупреждение : ВидСтатусаСделки.для(сделка.статус).вид
        return Text(сделка.заголовокСтатуса)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(вид.текст)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(вид.фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.xxs, style: .continuous))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// #dm-strip: «Спор · решение за 24–48 ч».
    private var полосаСпора: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text(т("dl_dsp_strip"))
                .font(.system(size: 14, weight: .heavy))
            Spacer(minLength: 4)
            Text(т("dl_dsp_strip_r"))
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(КраскаОбъявлений.плохоТекст, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
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
        VStack(alignment: .leading, spacing: 8) {
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
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1)
                    }
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
        VStack(alignment: .leading, spacing: 8) {
            /* Цепочка из семи «+» не укладывалась во время проверки типов (Codemagic, 26.09.2026) — склейка массивом. */
            Text([т("dw_step"), String(i + 1), т("dw_of"), String(всего)].joined(separator: " "))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Theme.акцент)
            Text(подпись)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            if !пауза.isEmpty {
                ЗаметкаСделки(Text(пауза), вид: сделка.статус == "disputed" ? .плохо : .предупреждение)
            }
            работаШага
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(сделка.статус == "disputed" ? КраскаОбъявлений.плохоКромка : Theme.акцент, lineWidth: 1.5)
        }
    }

    private func строка(_ i: Int, подпись: String, пройден: Bool) -> some View {
        HStack(spacing: 10) {
            Text(пройден ? "✓" : String(i + 1))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(пройден ? Color.white : Theme.текстВторой)
                .frame(width: 26, height: 26)
                .background(пройден ? Theme.зелёный : Theme.поверхность2, in: Circle())
            Text(подпись)
                .font(.system(size: 15, weight: пройден ? .semibold : .regular))
                .foregroundStyle(пройден ? Theme.текст : Theme.текстВторой)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
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
            БлокСделки {
                Text(т(сделка.продавец ? "dl_link_buyer" : "dl_link_seller"))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 10) {
                    Text(String(имя.prefix(1)).uppercased())
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.зелёный, in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(имя)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.текст)
                        if !п.телефон.isEmpty {
                            Text(п.телефон)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.текстВторой)
                        }
                    }
                    Spacer(minLength: 4)
                    if !п.телефон.isEmpty {
                        Button {
                            действие(.скопировать(п.телефон))
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.акцент)
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(т("hov_copy"))
                    }
                }
                каналы
                if let адрес = Config.страницаСайта("seller.php?id=" + СделкиAPI.вАдрес(п.id)) {
                    Button {
                        открыть(адрес)
                    } label: {
                        HStack {
                            Label(т(п.роль == "seller" ? "hov_prof_seller" : "hov_prof_buyer"), systemImage: "person.crop.circle")
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .accessibilityHidden(true)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                    }
                    .buttonStyle(.plain)
                }
                if п.чатЗакрыт { ПодписьСделки(т("hov_closed")) }
            }
        }
    }

    private var имя: String { п.имя.isEmpty ? т("peer_fallback") : п.имя }

    private var каналы: some View {
        HStack(spacing: 8) {
            if !п.чатЗакрыт {
                if Config.нативныйЧат {
                    NavigationLink(value: ЧатЦель.продавец(id: п.id, имя: имя, объявление: сделка.товар)) {
                        ярлык(т("hov_chat"), "bubble.left", главный: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { действие(.наСайт) } label: { ярлык(т("hov_chat"), "bubble.left", главный: true) }
                        .buttonStyle(.plain)
                }
            }
            if !п.телефон.isEmpty, let звонок = URL(string: "tel:" + п.телефон.filter { $0.isNumber || $0 == "+" }) {
                Button { действие(.ссылка(звонок)) } label: { ярлык(т("hov_call"), "phone", главный: false) }
                    .buttonStyle(.plain)
            }
            if let wa = URL(string: п.whatsApp), !п.whatsApp.isEmpty {
                Button { действие(.ссылка(wa)) } label: { ярлык("WhatsApp", "message", главный: false) }
                    .buttonStyle(.plain)
            }
            if let tg = URL(string: п.telegram), !п.telegram.isEmpty {
                Button { действие(.ссылка(tg)) } label: { ярлык("Telegram", "paperplane", главный: false) }
                    .buttonStyle(.plain)
            }
        }
    }

    private func ярлык(_ текст: String, _ символ: String, главный: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: символ)
                .font(.system(size: 16, weight: .semibold))
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(главный ? Color.white : Theme.текст)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(главный ? Theme.зелёный : Theme.поверхность2,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }
}

import SwiftUI
import UIKit

/**
 «ЗАЯВКИ РЯДОМ» — ЭКРАН, ЭТАП 45 (владелец 26.09.2026: «всё одно и то же, просто код разный»;
 Config.нативныеСообщенияКабинета).

 #requests-screen кабинета: «Заявки рядом», подзаголовок, вкладки «Новые» / «Все», карточки заявок (reqCardHTML):
 буква клиента, имя и значок («Вы откликнулись», «Заказ ваш», «Вас выбрали»), «N мин назад», справа отсчёт или
 состояние («Заказ занят», «Время вышло», «Закреплено», «Подтверждено»), текст, «По вашему объявлению», город и
 специальность, кнопки: «Откликнуться» и «Скрыть»; после отклика — «Открыть чат» и «Ждём, кого выберет клиент ·
 откликов: N»; заказ мой — «Принять заказ» (после вопроса), «Чат», «Позвонить», WhatsApp, «Такси», «Маршрут · 2ГИС»,
 «Найти адрес · 2ГИС». Рабочее место мастера (#master-workspace: профессия, ссылки, заметки) — пока на сайте.
 Живёт в стеке вкладки «Кабинет» (строка «Заявки рядом», ссылки ?s=requests и ?go=requests).
 */
struct ЭкранЗаявок: View {
    @ObservedObject private var модель = ЗаявкиМодель.shared
    let открыть: (URL) -> Void

    @State private var чат: ЧатЦель? = nil
    @State private var принять: Заявка? = nil
    @State private var входОткрыт = false

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }

    var body: some View {
        содержимое
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ИнбоксКраска.фон)
            .modifier(ШапкаСделок(заголовок: т("req_title")))
            .task { await модель.загрузить() }
            .task { await модель.тик() }
            .refreshable { await модель.загрузить() }
            .navigationDestination(item: $чат) { цель in
                ЭкранЧатаЗаявки(цель: цель, открыть: открыть)
            }
            .confirmationDialog(т("req_accept_title"), isPresented: вопросПринять, titleVisibility: .visible,
                                presenting: принять) { заявка in
                Button(т("req_accept_ok")) {
                    Task {
                        let итог = await модель.принять(заявка.id)
                        if итог == .неактивна { модель.неактивна = true }
                    }
                }
                Button(т("cancel"), role: .cancel) {}
            } message: { _ in
                Text(т("req_accept_text"))
            }
            .alert(т("req_closed_title"), isPresented: $модель.неактивна) {
                Button(т("ok_btn"), role: .cancel) {}
            } message: {
                Text(т("req_closed_text"))
            }
            .sheet(isPresented: $входОткрыт) {
                ЭкранВхода(eGovВключён: true, открыть: открыть, вошли: {
                    Task { await модель.загрузить() }
                })
            }
            .overlay(alignment: .bottom) { ПлашкаИнбокса(текст: модель.плашка) }
    }

    private var вопросПринять: Binding<Bool> {
        Binding(get: { принять != nil }, set: { показан in
            if !показан { принять = nil }
        })
    }

    @ViewBuilder
    private var содержимое: some View {
        if !модель.загружено {
            Text(т("loading"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if модель.нуженВход {
            ПустоСайта(значок: "person.crop.circle", заголовок: CabinetText.т("signed_out"),
                       подпись: CabinetText.т("signed_out_sub"), кнопка: CabinetText.т("login"),
                       действие: { войти() })
        } else {
            список
        }
    }

    private var список: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                /* #requests-screen: подзаголовок 13 с отступом 14, чипы — ещё 14 до списка (12 промежутка + 2). */
                Text(т("req_sub"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 2)
                фильтры
                    .padding(.bottom, 2)
                if let ошибка = модель.ошибка, модель.заявки.isEmpty {
                    Text(ошибка)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else if модель.видимые.isEmpty {
                    пусто
                } else {
                    ForEach(модель.видимые) { заявка in
                        КарточкаЗаявки(заявка: заявка, сейчас: модель.сейчас,
                                       занята: модель.занято.contains(заявка.id),
                                       действие: { д in выполнить(д, заявка) })
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
    }

    /// #req-filters: «Новые» / «Все» — чипы .msg-chip.
    private var фильтры: some View {
        HStack(spacing: 8) {
            ForEach(ЗаявкиМодель.Фильтр.allCases, id: \.self) { ф in
                let выбран = модель.фильтр == ф
                Button {
                    модель.фильтр = ф
                } label: {
                    /* .msg-chip: 13 полужирным, 6/14, кромка 1,5; выбранный — градиент --g → --g2 с тенью. */
                    Text(ф.название)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(выбран ? Color.white : Theme.текстВторой)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if выбран {
                                Capsule()
                                    .fill(ИнбоксКраска.градиент)
                                    .shadow(color: Theme.цвет(0x34C997, 0x34C997).opacity(0.5), radius: 5, x: 0, y: 4)
                            } else {
                                Capsule().fill(ИнбоксКраска.карточка)
                            }
                        }
                        .overlay {
                            Capsule().strokeBorder(выбран ? Color.clear : ИнбоксКраска.линия, lineWidth: 1.5)
                        }
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
                .accessibilityAddTraits(выбран ? .isSelected : [])
            }
        }
    }

    private var пусто: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            Text(т(модель.фильтр == .new ? "req_empty_new" : "req_empty_all"))
                .font(.system(size: 15))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func выполнить(_ д: КарточкаЗаявки.Действие, _ заявка: Заявка) {
        switch д {
        case .откликнуться:
            Task {
                if let цель = await модель.откликнуться(заявка) { чат = цель }
            }
        case .скрыть:
            модель.скрыть(заявка)
        case .чат:
            чат = .продавец(id: заявка.клиент, имя: заявка.имя, объявление: заявка.id)
        case .принять:
            принять = заявка
        case .объявление:
            if Config.нативнаяКарточка {
                NativeRouter.shared.цель = .объявление(id: заявка.объявлениеID)
            } else if let адрес = Config.url("/marketplace.php?item=" + ИнбоксAPI.вАдрес(заявка.объявлениеID)) {
                открыть(адрес)
            }
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

/// Переписка с клиентом из «Заявок» — тот же экран, что у «Чата» (openDM сайта).
private struct ЭкранЧатаЗаявки: View {
    let цель: ЧатЦель
    let открыть: (URL) -> Void

    var body: some View {
        switch цель {
        case .продавец(let id, let имя, let объявление):
            ChatThreadView(модель: ChatThreadModel(собеседник: id, объявление: объявление), заголовок: имя,
                           открыть: открыть)
        default:
            EmptyView()
        }
    }
}

/// .req-card.
struct КарточкаЗаявки: View {
    enum Действие { case откликнуться, скрыть, чат, принять, объявление }

    let заявка: Заявка
    let сейчас: Date
    let занята: Bool
    let действие: (Действие) -> Void

    @Environment(\.openURL) private var открытьСсылку

    init(заявка: Заявка, сейчас: Date, занята: Bool, действие: @escaping (Действие) -> Void) {
        self.заявка = заявка
        self.сейчас = сейчас
        self.занята = занята
        self.действие = действие
    }

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }

    private var состояние: String { заявка.состояние(сейчас) }
    private var моя: Bool { (состояние == "assigned" || состояние == "confirmed") && заявка.мне }
    private var закрыта: Bool { состояние != "open" && !моя }
    private var имя: String { заявка.имя.isEmpty ? т("req_client") : заявка.имя }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            верх
            if !заявка.текст.isEmpty {
                /* .req-text: 14 с высотой строки 1.5 в серой рамке. */
                Text(заявка.текст)
                    .font(.system(size: 14))
                    .lineSpacing(7)
                    .foregroundStyle(ИнбоксКраска.текст)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(ИнбоксКраска.подложка, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(ИнбоксКраска.линия, lineWidth: 1)
                    }
            }
            if !заявка.объявление.isEmpty { объявление }
            if !заявка.город.isEmpty || !заявка.специальность.isEmpty { мета }
            подсказка
            кнопки
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
            if ждёт || моя {
                форма.fill(LinearGradient(colors: [ИнбоксКраска.подложка, ИнбоксКраска.карточка],
                                          startPoint: .top, endPoint: .bottom))
            } else {
                форма.fill(ИнбоксКраска.карточка)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(ждёт ? ИнбоксКраска.акцент : ИнбоксКраска.линия, lineWidth: 1)
        }
        .opacity(закрыта ? 0.5 : (занята ? 0.8 : 1))
    }

    /// .is-waiting: откликнулся и жду выбора клиента — кромка --acc-on и подложка сверху вниз.
    private var ждёт: Bool { состояние == "open" && заявка.откликнулся }

    private var верх: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(String(имя.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(LinearGradient(colors: [Theme.цвет(0x1D7D4A, 0x34C997), Theme.цвет(0x0F5132, 0x22A05B)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                ПереносСтрок(промежуток: 8, междуСтрок: 4) {
                    Text(имя)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ИнбоксКраска.текст)
                        .lineLimit(1)
                    значок
                }
                let когда = ИнбоксВремя.назад(заявка.когда)
                if !когда.isEmpty {
                    Text(когда)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            Spacer(minLength: 6)
            справа
        }
    }

    /// .req-badge: 10 жирным заглавными --acc-on на --acc-tint; «Вас выбрали» — --on-warn на --tint-warn.
    @ViewBuilder
    private var значок: some View {
        if состояние == "open" && заявка.откликнулся {
            метка(т("req_you_responded"), текст: ИнбоксКраска.акцент, фон: ИнбоксКраска.оттенок)
        } else if моя {
            if состояние == "confirmed" {
                метка(т("req_order_yours"), текст: ИнбоксКраска.акцент, фон: ИнбоксКраска.оттенок)
            } else {
                метка(т("req_you_chosen"), текст: ИнбоксКраска.вниманиеТекст, фон: ИнбоксКраска.вниманиеФон)
            }
        }
    }

    private func метка(_ подпись: String, текст: Color, фон: Color) -> some View {
        Text(подпись)
            .font(.system(size: 10, weight: .bold))
            .tracking(0.3)
            .textCase(.uppercase)
            .foregroundStyle(текст)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(фон, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// .req-timer (12 жирным на --acc-tint; меньше минуты — --tint-warn) или .req-state (11 серым на --surf2; ok — --tint-ok).
    @ViewBuilder
    private var справа: some View {
        if состояние == "open" {
            let осталось = заявка.осталось(сейчас)
            let срочно = осталось <= 60
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
                Text(Заявка.отсчёт(осталось))
                    .font(.system(size: 12, weight: .heavy))
                    .monospacedDigit()
            }
            .foregroundStyle(срочно ? ИнбоксКраска.вниманиеТекст : ИнбоксКраска.акцент)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(срочно ? ИнбоксКраска.вниманиеФон : ИнбоксКраска.оттенок,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: т("req_left_a11y"), Заявка.отсчёт(осталось)))
        } else if моя {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .accessibilityHidden(true)
                Text(т(состояние == "confirmed" ? "req_confirmed" : "req_assigned"))
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(ИнбоксКраска.окТекст)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(ИнбоксКраска.окФон, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Text(т(состояние == "assigned" ? "req_taken" : "req_expired"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(ИнбоксКраска.подложка, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    /// .req-listing: фото 42 на --tint-ok, «По вашему объявлению» 11 и название 13 жирным; карточка с кромкой 1,5.
    private var объявление: some View {
        Button {
            действие(.объявление)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    ИнбоксКраска.окФон
                    if let адрес = Config.url(заявка.фото) {
                        КартинкаЛенты(адрес, пунктов: 42) {
                            ИнбоксКраска.окФон
                        }
                    } else {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 17))
                            .foregroundStyle(ИнбоксКраска.окТекст)
                    }
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(т("req_by_your_ad"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                    Text(заявка.объявление)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ИнбоксКраска.текст)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .flipsForRightToLeftLayoutDirection(true)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(ИнбоксКраска.карточка, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(ИнбоксКраска.линия, lineWidth: 1.5)
            }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }

    /// .req-meta: город 12 серым и специальность .req-tag (11 жирным --acc-on на --acc-tint).
    private var мета: some View {
        HStack(spacing: 8) {
            if !заявка.город.isEmpty {
                Label(заявка.город, systemImage: "mappin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
            if !заявка.специальность.isEmpty {
                Text(заявка.специальность)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ИнбоксКраска.акцент)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(ИнбоксКраска.оттенок, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var подсказка: some View {
        if состояние == "open" && заявка.откликнулся {
            Text(т("req_waiting_client") + String(max(1, заявка.откликов)))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
        } else if моя && !заявка.адрес.isEmpty {
            /* .req-addr: 13 полужирным на карточке с пунктирной кромкой. */
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "mappin")
                    .font(.system(size: 13))
                    .accessibilityHidden(true)
                Text(заявка.адрес)
                    .font(.system(size: 13, weight: .semibold))
                    .lineSpacing(2.6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(ИнбоксКраска.текст)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(ИнбоксКраска.карточка, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(ИнбоксКраска.линия, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
    }

    /// .req-acts: главная (--go) во всю ширину, остальные — сеткой от 94 с промежутком 8.
    @ViewBuilder
    private var кнопки: some View {
        let сетка = [GridItem(.adaptive(minimum: 94), spacing: 8)]
        if состояние == "open" {
            if заявка.откликнулся {
                кнопка(т("req_open_chat"), значок: "bubble.left", вид: .главная) { действие(.чат) }
            } else {
                VStack(spacing: 8) {
                    кнопка(т("req_respond"), значок: "arrowshape.turn.up.left", вид: .главная) { действие(.откликнуться) }
                    LazyVGrid(columns: сетка, spacing: 8) {
                        кнопка(т("req_hide"), значок: "flag", вид: .серая) { действие(.скрыть) }
                            .accessibilityHint(т("req_report_hide"))
                    }
                }
            }
        } else if моя {
            VStack(spacing: 8) {
                if заявка.нуженОтвет {
                    кнопка(т("req_accept_order"), значок: "checkmark", вид: .главная) { действие(.принять) }
                } else {
                    кнопка(т("nav_chat"), значок: "bubble.left", вид: .главная) { действие(.чат) }
                }
                LazyVGrid(columns: сетка, spacing: 8) {
                    if заявка.нуженОтвет {
                        кнопка(т("nav_chat"), значок: "bubble.left", вид: .рамка) { действие(.чат) }
                    }
                    ForEach(ссылки, id: \.подпись) { с in
                        кнопка(с.подпись, значок: с.значок, вид: с.вид) { открытьСсылку(с.адрес) }
                    }
                }
            }
        }
    }

    /// Виды .req-btn: --go (градиент), --out (карточка с кромкой), --x (серый текст), --wa, --taxi, --map.
    private enum ВидКнопки {
        case главная, рамка, серая, ватсап, такси, карта
    }

    private struct Ссылка {
        let подпись: String
        let значок: String
        let адрес: URL
        let вид: ВидКнопки
    }

    /// Телефон, WhatsApp, такси и маршрут (reqTaxiButtons): точка есть — Яндекс Go и 2ГИС до неё, нет — поиск адреса.
    private var ссылки: [Ссылка] {
        var список: [Ссылка] = []
        let тел = заявка.телефон.filter { $0.isNumber || $0 == "+" }
        if !тел.isEmpty, let u = URL(string: "tel:" + тел) {
            список.append(Ссылка(подпись: т("req_call"), значок: "phone", адрес: u, вид: .рамка))
        }
        let цифры = заявка.телефон.filter { $0.isNumber }
        if !цифры.isEmpty, let u = URL(string: "https://wa.me/" + цифры) {
            список.append(Ссылка(подпись: "WhatsApp", значок: "message", адрес: u, вид: .ватсап))
        }
        if заявка.широта != 0 && заявка.долгота != 0 {
            let ш = String(заявка.широта)
            let д = String(заявка.долгота)
            if let u = URL(string: "https://3.redirect.appmetrica.yandex.com/route?end-lat=" + ш + "&end-lon=" + д
                           + "&appmetrica_tracking_id=25395763362139037&lang=ru&ref=klikokz") {
                список.append(Ссылка(подпись: т("req_taxi"), значок: "car", адрес: u, вид: .такси))
            }
            if let u = URL(string: "https://2gis.kz/directions/points/%7C" + д + "%2C" + ш) {
                список.append(Ссылка(подпись: т("req_route") + " · 2ГИС", значок: "arrow.triangle.turn.up.right.diamond",
                                     адрес: u, вид: .карта))
            }
        } else if !заявка.адрес.isEmpty,
                  let u = URL(string: "https://2gis.kz/search/" + ИнбоксAPI.вАдрес(заявка.адрес)) {
            список.append(Ссылка(подпись: т("req_find_addr") + " · 2ГИС", значок: "mappin", адрес: u, вид: .карта))
        }
        return список
    }

    /// .req-btn: высота 42, 13 жирным, скругление 12, кромка 1,5.
    private func кнопка(_ подпись: String, значок: String, вид: ВидКнопки,
                        _ нажать: @escaping () -> Void) -> some View {
        let текст: Color
        let фон: Color
        let кромка: Color?
        switch вид {
        case .главная:
            текст = Color.white
            фон = Color.clear
            кромка = nil
        case .рамка:
            текст = ИнбоксКраска.текст
            фон = ИнбоксКраска.карточка
            кромка = ИнбоксКраска.линия
        case .серая:
            текст = Theme.текстВторой
            фон = ИнбоксКраска.карточка
            кромка = ИнбоксКраска.линия
        case .ватсап:
            текст = Color.white
            фон = Color(uiColor: Theme.hex(0x25D366))
            кромка = nil
        case .такси:
            текст = Color(uiColor: Theme.hex(0x1A1A1A))
            фон = Color(uiColor: Theme.hex(0xFFCE00))
            кромка = nil
        case .карта:
            текст = ИнбоксКраска.акцент
            фон = ИнбоксКраска.карточка
            кромка = ИнбоксКраска.линия
        }
        return Button(action: нажать) {
            HStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text(подпись)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(текст)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background {
                let форма = RoundedRectangle(cornerRadius: 12, style: .continuous)
                if вид == .главная {
                    форма.fill(LinearGradient(colors: [Theme.цвет(0x1D7D4A, 0x34C997), Theme.цвет(0x0F5132, 0x22A05B)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    форма.fill(фон)
                }
            }
            .overlay {
                if let кромка {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(кромка, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .disabled(занята)
    }
}

// MARK: - Заявка в переписке (dm.php, meta.request)

/**
 Карточка заявки в личной переписке (_dmRender кабинета, карта §6.9.1): «Сделка подтверждена»; клиент выбрал мастера —
 мастеру «Принять заказ» (act accept, после «Принять заказ?»), остальным «Ждём подтверждения мастера…»; отклик мастера —
 профиль мастера, текст, «По вашему объявлению» и для клиента «Закрепить за мастером» (act confirm, после «Закрепить
 заказ за мастером?») или «Исполнитель выбран», если мастер уже выбран.
 */
struct КарточкаЗаявкиВЧате: View {
    let заявка: ЗаявкаВЧате
    let текст: String
    let естьНазначенный: Bool
    let открыть: (URL) -> Void

    @ObservedObject private var заявки = ЗаявкиМодель.shared
    @State private var я = ""
    @State private var спроситьПринять = false
    @State private var спроситьЗакрепить = false
    /// Ответ сервера: заказ принят / мастер закреплён — кнопка сменяется подписью, как у сайта.
    @State private var сделано = false
    /// «Заявка уже неактивна» — своё окно у карточки: карточек в переписке может быть несколько.
    @State private var неактивна = false

    init(заявка: ЗаявкаВЧате, текст: String, естьНазначенный: Bool, открыть: @escaping (URL) -> Void) {
        self.заявка = заявка
        self.текст = текст
        self.естьНазначенный = естьНазначенный
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }

    /// .dm-reqcard: значок слева (галочка или ответ), --tint-ok с кромкой --edge-ok 1,5 (подтверждена — --on-ok).
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: заявка.назначена || заявка.подтверждена ? "checkmark.circle" : "arrowshape.turn.up.left")
                .font(.system(size: 17))
                .foregroundStyle(ИнбоксКраска.окТекст)
                .accessibilityHidden(true)
            содержимое
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ИнбоксКраска.окФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(заявка.подтверждена ? ИнбоксКраска.окТекст : ИнбоксКраска.окКромка, lineWidth: 1.5)
        }
        .padding(.vertical, 4)
        .task { я = await ИнбоксAPI.номерБыстро() }
        .confirmationDialog(т("req_accept_title"), isPresented: $спроситьПринять, titleVisibility: .visible) {
            Button(т("req_accept_ok")) {
                Task {
                    let итог = await заявки.принять(заявка.номер)
                    применить(итог)
                }
            }
            Button(т("cancel"), role: .cancel) {}
        } message: {
            Text(т("req_accept_text"))
        }
        .confirmationDialog(т("req_pin_title"), isPresented: $спроситьЗакрепить, titleVisibility: .visible) {
            Button(т("req_pin_btn")) {
                Task {
                    let итог = await заявки.закрепить(заявка.номер, мастер: заявка.мастер)
                    применить(итог)
                }
            }
            Button(т("cancel"), role: .cancel) {}
        } message: {
            Text(т("req_pin_text"))
        }
        .alert(т("req_closed_title"), isPresented: $неактивна) {
            Button(т("ok_btn"), role: .cancel) {}
        } message: {
            Text(т("req_closed_text"))
        }
    }

    private func применить(_ итог: ЗаявкиМодель.ИтогЗаявки) {
        switch итог {
        case .готово: сделано = true
        case .неактивна: неактивна = true
        case .нет: break
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        if заявка.подтверждена {
            подпись(т("dm_deal_confirmed"))
        } else if заявка.назначена {
            VStack(alignment: .leading, spacing: 8) {
                Text(т("dm_client_chose"))
                    .font(.system(size: 13, weight: .bold))
                    .lineSpacing(5)
                    .foregroundStyle(ИнбоксКраска.окТекст)
                if !я.isEmpty && я == заявка.мастер {
                    if сделано {
                        подпись(т("req_deal_confirmed"))
                    } else {
                        кнопка(т("dm_accept_order")) { спроситьПринять = true }
                    }
                } else {
                    Text(т("dm_wait_master"))
                        .font(.system(size: 12))
                        .italic()
                        .foregroundStyle(Theme.текстВторой)
                }
            }
        } else if !заявка.мастер.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if заявка.естьПрофиль { профиль }
                if !текст.isEmpty {
                    Text(текст)
                        .font(.system(size: 13, weight: .bold))
                        .lineSpacing(5)
                        .foregroundStyle(ИнбоксКраска.окТекст)
                }
                if !заявка.объявление.isEmpty {
                    Button {
                        if Config.нативнаяКарточка {
                            NativeRouter.shared.цель = .объявление(id: заявка.объявлениеID)
                        } else if let u = Config.url("/marketplace.php?item=" + ИнбоксAPI.вАдрес(заявка.объявлениеID)) {
                            открыть(u)
                        }
                    } label: {
                        Label(заявка.объявление, systemImage: "shippingbox")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.акцент)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
                if !я.isEmpty && я != заявка.мастер {
                    if естьНазначенный || сделано {
                        подпись(т("dm_master_selected"))
                    } else {
                        кнопка(т("dm_pin_master")) { спроситьЗакрепить = true }
                    }
                }
            }
        } else {
            ПилюляСлужебнаяКабинета(текст: текст, рамка: true)
        }
    }

    /// _reqMasterProfile: имя (или «Мастер»), «Проверенный», звёзды · отзывы, «Выполнил N из M», «N сделок» или «новый».
    private var профиль: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(заявка.имяМастера.isEmpty ? т("req_master") : заявка.имяМастера)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                if заявка.проверен {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.проверен)
                        .accessibilityLabel(т("req_verified"))
                }
            }
            HStack(spacing: 8) {
                if заявка.рейтинг > 0 {
                    Label(СделкиФормат.дробь(заявка.рейтинг) + (заявка.отзывов > 0 ? " · " + String(заявка.отзывов) : ""),
                          systemImage: "star.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.звезда)
                }
                if заявка.услугВсего > 0 {
                    Text(т("req_svc_done").replacingOccurrences(of: "{d}", with: String(заявка.услугВыполнено))
                        .replacingOccurrences(of: "{t}", with: String(заявка.услугВсего)))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
                if заявка.сделок > 0 {
                    Text(String(format: т("req_deals_n"), заявка.сделок))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                } else if заявка.услугВсего <= 0 {
                    Text(т("req_new"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                }
            }
        }
    }

    private func подпись(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 13, weight: .bold))
            .lineSpacing(5)
            .foregroundStyle(ИнбоксКраска.окТекст)
    }

    /// .dm-pin-btn: 13 жирным белым на градиенте #1d9e5e → #0f7a44, 10/16, скругление 10.
    private func кнопка(_ подпись: String, _ нажать: @escaping () -> Void) -> some View {
        Button(action: нажать) {
            Label(подпись, systemImage: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(LinearGradient(colors: [Color(uiColor: Theme.hex(0x1D9E5E)), Color(uiColor: Theme.hex(0x0F7A44))],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        .disabled(заявки.занято.contains(заявка.номер))
    }
}

// MARK: - «Сделка состоялась?»

/**
 Окно checkPendingFeedback / showFeedback сайта: «Сделка состоялась?», «Заявка «<первые 90 знаков>» · с <мастер>»,
 комментарий до 1000 знаков, «Нет» / «Да, всё ок». Закрыть его можно только ответом — как у сайта.
 */
struct ОкноОтзываЗаявки: View {
    let отзыв: ОжидаетОтзыва
    @ObservedObject var модель: ЗаявкиМодель

    @State private var комментарий = ""
    @State private var отправляем = false

    init(отзыв: ОжидаетОтзыва, модель: ЗаявкиМодель) {
        self.отзыв = отзыв
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }

    var body: some View {
        ScrollView {
            содержимое
                .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        /* По высоте содержимого, без пустоты снизу; смахнуть нельзя — без полоски. */
        .листПоВысоте(полоска: false)
        .interactiveDismissDisabled(true)
    }

    private var содержимое: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 56, height: 56)
                .background(КраскаОбъявлений.хорошоФон, in: Circle())
                .accessibilityHidden(true)
            Text(т("fb_title"))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            Text(String(format: т("fb_text"), String(отзыв.текст.prefix(90)),
                        отзыв.мастер.isEmpty ? т("fb_master") : отзыв.мастер))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
            TextField(т("fb_comment"), text: $комментарий, axis: .vertical)
                .lineLimit(2...4)
                .padding(10)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .onChange(of: комментарий) { _, стало in
                    if стало.count > 1000 { комментарий = String(стало.prefix(1000)) }
                }
            HStack(spacing: 10) {
                Button {
                    ответить(false)
                } label: {
                    Text(т("fb_no"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                Button {
                    ответить(true)
                } label: {
                    Text(т("fb_yes"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.зелёный2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
            }
            .disabled(отправляем)
        }
        .padding(20)
    }

    private func ответить(_ состоялась: Bool) {
        guard !отправляем else { return }
        отправляем = true
        let о = отзыв
        let текст = комментарий
        Task { @MainActor in
            await модель.ответитьНаОтзыв(о, состоялась: состоялась, комментарий: текст)
            отправляем = false
        }
    }
}

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
            .background(Theme.фонСтраницы)
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
                .font(.system(size: 15))
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
                Text(т("req_sub"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                фильтры
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
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
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
                    Text(ф.название)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(выбран ? Color.white : Theme.текстВторой)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 34)
                        .background(выбран ? Theme.зелёный : Theme.поверхность, in: Capsule())
                        .overlay {
                            Capsule().strokeBorder(выбран ? Color.clear : Theme.линия, lineWidth: 1)
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
                Text(заявка.текст)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !заявка.объявление.isEmpty { объявление }
            if !заявка.город.isEmpty || !заявка.специальность.isEmpty { мета }
            подсказка
            кнопки
        }
        .padding(14)
        .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(кромка, lineWidth: 1)
        }
        .opacity(закрыта ? 0.65 : (занята ? 0.8 : 1))
    }

    private var фон: Color { моя ? КраскаОбъявлений.хорошоФон : Theme.поверхность }
    private var кромка: Color { моя ? КраскаОбъявлений.хорошоКромка : Theme.линия }

    private var верх: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(имя.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(Theme.зелёный2, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(имя)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.текст)
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

    @ViewBuilder
    private var значок: some View {
        if состояние == "open" && заявка.откликнулся {
            ТегИнбокса(id: "b", текст: т("req_you_responded"), значок: nil, фон: КраскаОбъявлений.хорошоФон,
                       цвет: КраскаОбъявлений.хорошоТекст)
        } else if моя {
            if состояние == "confirmed" {
                ТегИнбокса(id: "b", текст: т("req_order_yours"), значок: nil, фон: КраскаОбъявлений.хорошоФон,
                           цвет: КраскаОбъявлений.хорошоТекст)
            } else {
                ТегИнбокса(id: "b", текст: т("req_you_chosen"), значок: nil, фон: КраскаОбъявлений.предупреждениеФон,
                           цвет: КраскаОбъявлений.предупреждениеТекст)
            }
        }
    }

    @ViewBuilder
    private var справа: some View {
        if состояние == "open" {
            let осталось = заявка.осталось(сейчас)
            Label(Заявка.отсчёт(осталось), systemImage: "clock")
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(осталось <= 60 ? КраскаОбъявлений.плохоТекст : Theme.текст)
                .accessibilityLabel(String(format: т("req_left_a11y"), Заявка.отсчёт(осталось)))
        } else if моя {
            Label(т(состояние == "confirmed" ? "req_confirmed" : "req_assigned"), systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(КраскаОбъявлений.хорошоТекст)
        } else {
            Text(т(состояние == "assigned" ? "req_taken" : "req_expired"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
        }
    }

    /// .req-listing: «По вашему объявлению» + название.
    private var объявление: some View {
        Button {
            действие(.объявление)
        } label: {
            HStack(spacing: 10) {
                if let адрес = Config.url(заявка.фото) {
                    AsyncImage(url: адрес) { картинка in
                        картинка.resizable().scaledToFill()
                    } placeholder: {
                        Theme.поверхность2
                    }
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                } else {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 36, height: 36)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(т("req_by_your_ad"))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.текстВторой)
                    Text(заявка.объявление)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(8)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }

    private var мета: some View {
        HStack(spacing: 8) {
            if !заявка.город.isEmpty {
                Label(заявка.город, systemImage: "mappin")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
            }
            if !заявка.специальность.isEmpty {
                ТегИнбокса(id: "sp", текст: заявка.специальность, значок: nil, фон: КраскаОбъявлений.инфоФон,
                           цвет: КраскаОбъявлений.инфоТекст)
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
            Label(заявка.адрес, systemImage: "mappin.and.ellipse")
                .font(.system(size: 13))
                .foregroundStyle(Theme.текст)
        }
    }

    @ViewBuilder
    private var кнопки: some View {
        if состояние == "open" {
            if заявка.откликнулся {
                кнопка(т("req_open_chat"), значок: "bubble.left", главная: true) { действие(.чат) }
            } else {
                HStack(spacing: 8) {
                    кнопка(т("req_respond"), значок: "arrowshape.turn.up.left", главная: true) { действие(.откликнуться) }
                    кнопка(т("req_hide"), значок: "flag", главная: false) { действие(.скрыть) }
                        .accessibilityHint(т("req_report_hide"))
                }
            }
        } else if моя {
            ПереносСтрок(промежуток: 8, междуСтрок: 8) {
                if заявка.нуженОтвет {
                    кнопка(т("req_accept_order"), значок: "checkmark", главная: true) { действие(.принять) }
                }
                кнопка(т("nav_chat"), значок: "bubble.left", главная: !заявка.нуженОтвет) { действие(.чат) }
                ForEach(ссылки, id: \.подпись) { с in
                    кнопка(с.подпись, значок: с.значок, главная: false) { открытьСсылку(с.адрес) }
                }
            }
        }
    }

    private struct Ссылка {
        let подпись: String
        let значок: String
        let адрес: URL
    }

    /// Телефон, WhatsApp, такси и маршрут (reqTaxiButtons): точка есть — Яндекс Go и 2ГИС до неё, нет — поиск адреса.
    private var ссылки: [Ссылка] {
        var список: [Ссылка] = []
        let тел = заявка.телефон.filter { $0.isNumber || $0 == "+" }
        if !тел.isEmpty, let u = URL(string: "tel:" + тел) {
            список.append(Ссылка(подпись: т("req_call"), значок: "phone", адрес: u))
        }
        let цифры = заявка.телефон.filter { $0.isNumber }
        if !цифры.isEmpty, let u = URL(string: "https://wa.me/" + цифры) {
            список.append(Ссылка(подпись: "WhatsApp", значок: "message", адрес: u))
        }
        if заявка.широта != 0 && заявка.долгота != 0 {
            let ш = String(заявка.широта)
            let д = String(заявка.долгота)
            if let u = URL(string: "https://3.redirect.appmetrica.yandex.com/route?end-lat=" + ш + "&end-lon=" + д
                           + "&appmetrica_tracking_id=25395763362139037&lang=ru&ref=klikokz") {
                список.append(Ссылка(подпись: т("req_taxi"), значок: "car", адрес: u))
            }
            if let u = URL(string: "https://2gis.kz/directions/points/%7C" + д + "%2C" + ш) {
                список.append(Ссылка(подпись: т("req_route") + " · 2ГИС", значок: "arrow.triangle.turn.up.right.diamond",
                                     адрес: u))
            }
        } else if !заявка.адрес.isEmpty,
                  let u = URL(string: "https://2gis.kz/search/" + ИнбоксAPI.вАдрес(заявка.адрес)) {
            список.append(Ссылка(подпись: т("req_find_addr") + " · 2ГИС", значок: "mappin", адрес: u))
        }
        return список
    }

    private func кнопка(_ подпись: String, значок: String, главная: Bool,
                        _ нажать: @escaping () -> Void) -> some View {
        Button(action: нажать) {
            Label(подпись, systemImage: значок)
                .font(.system(size: 13, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(главная ? Color.white : Theme.текст)
                .padding(.horizontal, 12)
                .frame(minHeight: 38)
                .background(главная ? Theme.зелёный : Theme.поверхность2,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .overlay {
                    if !главная {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
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

    var body: some View {
        содержимое
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(КраскаОбъявлений.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(КраскаОбъявлений.хорошоКромка, lineWidth: 1)
            }
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
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                if !я.isEmpty && я == заявка.мастер {
                    if сделано {
                        подпись(т("req_deal_confirmed"))
                    } else {
                        кнопка(т("dm_accept_order")) { спроситьПринять = true }
                    }
                } else {
                    Text(т("dm_wait_master"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
        } else if !заявка.мастер.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if заявка.естьПрофиль { профиль }
                if !текст.isEmpty {
                    Text(текст)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
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
        Label(текст, systemImage: "checkmark.circle.fill")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(КраскаОбъявлений.хорошоТекст)
    }

    private func кнопка(_ подпись: String, _ нажать: @escaping () -> Void) -> some View {
        Button(action: нажать) {
            Label(подпись, systemImage: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 40)
                .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
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
        .presentationDetents([.medium])
        .interactiveDismissDisabled(true)
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

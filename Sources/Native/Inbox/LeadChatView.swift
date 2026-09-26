import SwiftUI
import UIKit

/**
 ЧАТ ПО ЛИДУ (Я ПРОДАВЕЦ) — ЭКРАН, ЭТАП 45 (владелец 26.09.2026: «всё одно и то же, просто код разный»;
 Config.нативныеСообщенияКабинета).

 #lead-chat-modal кабинета сверху вниз: шапка (имя покупателя, «Kliko AI-ассистент ведёт диалог / Горячий лид / Вы в
 диалоге / Завершён · покупатель <присутствие>», меню «⋯»: метка, «Заблокировать покупателя», «Пожаловаться»), карточка
 товара с «Объявление», полоса «Покупатель оформил сделку — Перейти к сделке», полоса горячего лида с «Позвонить» и
 WhatsApp, полоса «Покупатель хочет купить безопасно» (если я не верифицирован), переписка (служебные — зелёной пилюлей
 без рамки, гео — карточкой с Яндекс Go и 2ГИС, предложения цены — карточками с «Принять», встречной ценой и отказом),
 полоса «Подключитесь, чтобы ответить лично», внизу — поле «Ответить…» или плашка блокировки.
 Модель и запросы — ЛидМодель (LeadChatModel.swift).
 */
struct ЭкранЛида: View {
    @StateObject private var модель: ЛидМодель
    let открыть: (URL) -> Void

    @FocusState private var полеВФокусе: Bool
    /// «Повторить» после ошибки открытия — задача экрана перезапускается (открыть и опрос).
    @State private var попытка = 0
    @State private var спроситьБлок = false
    @State private var жалоба = false
    @Environment(\.scenePhase) private var фаза
    @Environment(\.openURL) private var открытьСсылку

    init(номер: String, имя: String, открыть: @escaping (URL) -> Void) {
        _модель = StateObject(wrappedValue: ЛидМодель(номер: номер, имя: имя))
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            if !модель.загружено {
                ProgressView()
                    .tint(Theme.акцент)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let ошибка = модель.ошибка {
                ПустоСайта(значок: "exclamationmark.bubble", заголовок: ошибка, кнопка: ChatText.т("retry"),
                           действие: { попытка += 1 },
                           вторая: ChatText.т("open_site"),
                           второеДействие: { Task { await модель.открытьНаСайте(открыть) } })
            } else {
                верх
                лента
                if модель.нужноПодключиться { полосаПодключения }
                низ
            }
        }
        .background(Theme.поверхность)
        .navigationTitle(модель.имя)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { заголовок }
            ToolbarItem(placement: .topBarTrailing) { меню }
        }
        .toolbarBackground(Theme.поверхность, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(Theme.акцент)
        .task(id: попытка) {
            await модель.начать()
            await модель.опрос()
        }
        .onChange(of: фаза) { _, стала in
            if стала == .background { модель.ушлиВФон() }
        }
        .confirmationDialog(т("blk_t"), isPresented: $спроситьБлок, titleVisibility: .visible) {
            Button(т("blk_ok"), role: .destructive) { Task { await модель.заблокировать() } }
            Button(т("cancel"), role: .cancel) {}
        } message: {
            Text(т("blk_m"))
        }
        .sheet(isPresented: $жалоба) {
            ОкноЖалобыНаПокупателя(имя: модель.имя, модель: модель)
        }
        .overlay(alignment: .bottom) {
            ПлашкаИнбокса(текст: модель.плашка)
                .padding(.bottom, 60)
        }
    }

    // MARK: - Шапка

    private var заголовок: some View {
        VStack(spacing: 1) {
            Text(модель.имя)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
            let подпись = модель.подзаголовок
            if !подпись.isEmpty {
                Text(подпись)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(модель.нетСвязи ? КраскаОбъявлений.плохоТекст : Theme.текстВторой)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var меню: some View {
        Menu {
            Menu {
                Button {
                    Task { await модель.поставитьМетку("") }
                } label: {
                    if модель.метка.isEmpty { Label(т("lbl_pick"), systemImage: "checkmark") } else { Text(т("lbl_pick")) }
                }
                ForEach(МеткаДиалога.allCases) { метка in
                    Button {
                        Task { await модель.поставитьМетку(метка.rawValue) }
                    } label: {
                        if модель.метка == метка.rawValue {
                            Label(метка.название, systemImage: "checkmark")
                        } else {
                            Text(метка.название)
                        }
                    }
                }
            } label: {
                Label(т("label_title"), systemImage: "tag")
            }
            if !модель.заблокирован {
                Button(role: .destructive) {
                    спроситьБлок = true
                } label: {
                    Label(т("lcm_block"), systemImage: "hand.raised")
                }
            }
            Button(role: .destructive) {
                жалоба = true
            } label: {
                Label(т("lcm_report"), systemImage: "exclamationmark.bubble")
            }
            Button {
                Task { await модель.открытьНаСайте(открыть) }
            } label: {
                Label(ChatText.т("open_site"), systemImage: "arrow.up.right.square")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .semibold))
        }
        .disabled(!модель.загружено || модель.ошибка != nil || модель.занято)
        .accessibilityLabel(т("more"))
    }

    // MARK: - Полосы над перепиской

    @ViewBuilder
    private var верх: some View {
        if let товар = модель.товар, !товар.id.isEmpty { КарточкаТовараЛида(товар: товар, открыть: открыть) }
        if !модель.сделка.isEmpty { полосаСделки }
        if let контакт = модель.контакт { полосаКонтакта(контакт) }
        if !модель.продавецПроверен { полосаВерификации }
    }

    /// _lcmDealBar: «Покупатель оформил сделку» — «Перейти к сделке» (карточка сделки во вкладке «Кабинет»).
    private var полосаСделки: some View {
        HStack(spacing: 10) {
            Text(т("lcm_deal_live"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(КраскаОбъявлений.хорошоТекст)
            Spacer(minLength: 6)
            Button {
                let номер = модель.сделка
                if NativeRouter.доступна(.сделка(id: номер)) {
                    NativeRouter.shared.цель = .сделка(id: номер)
                } else if let адрес = Config.страницаСайта("cabinet.php?deal=" + СделкиAPI.вАдрес(номер)) {
                    открыть(адрес)
                }
            } label: {
                Text(т("co_goto"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(КраскаОбъявлений.хорошоФон)
    }

    /// _lcmRenderContact: «Горячий лид — свяжитесь сразу», номер, «Позвонить», WhatsApp.
    private func полосаКонтакта(_ к: КонтактЛида) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Label(т("lcm_hot"), systemImage: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(КраскаОбъявлений.предупреждениеТекст)
                if !к.показ.isEmpty {
                    Text(к.показ)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(КраскаОбъявлений.предупреждениеТекст)
                }
            }
            Spacer(minLength: 4)
            Button {
                let номер = к.телефон.filter({ $0.isNumber || $0 == "+" })
                if let адрес = URL(string: "tel:" + номер) { открытьСсылку(адрес) }
            } label: {
                Label(т("call"), systemImage: "phone.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(uiColor: Theme.hex(0x0E1411)),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
            if let адрес = URL(string: к.whatsApp), !к.whatsApp.isEmpty {
                Button {
                    открытьСсылку(адрес)
                } label: {
                    Text("WhatsApp")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Theme.whatsApp, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(КраскаОбъявлений.предупреждениеФон)
    }

    /// #lcm-verify-bar: «Покупатель хочет купить безопасно» — «Пройти верификацию» (страница сайта ?go=verify).
    private var полосаВерификации: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(т("vbar_t"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(КраскаОбъявлений.инфоТекст)
                Text(т("vbar_d"))
                    .font(.system(size: 12))
                    .foregroundStyle(КраскаОбъявлений.инфоТекст)
            }
            Spacer(minLength: 4)
            Button {
                if let адрес = Config.страницаСайта("cabinet?go=verify") { открыть(адрес) }
            } label: {
                Text(т("verify_go"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(КраскаОбъявлений.инфоФон)
    }

    // MARK: - Переписка

    private var лента: some View {
        ScrollViewReader { прокрутка in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if модель.сообщения.isEmpty {
                        Text(т("lcm_no_msgs"))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.текстВторой)
                            .padding(.top, 30)
                    }
                    ForEach(модель.сообщения) { м in
                        строка(м).id(м.id)
                    }
                    if модель.печатает {
                        HStack {
                            Text("• • •")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(Theme.текстВторой)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Theme.пузырьЧужой, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityLabel(т("typing"))
                            Spacer(minLength: 48)
                        }
                    }
                    Color.clear.frame(height: 1).id("низ")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Theme.фонСтраницы)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: модель.сообщения.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { прокрутка.scrollTo("низ", anchor: .bottom) }
            }
            .onChange(of: полеВФокусе) { _, вФокусе in
                if вФокусе { прокрутка.scrollTo("низ", anchor: .bottom) }
            }
            .onAppear { прокрутка.scrollTo("низ", anchor: .bottom) }
        }
    }

    @ViewBuilder
    private func строка(_ м: СообщениеЛида) -> some View {
        if м.роль == "system" {
            /* role === "system" — зелёная пилюля без рамки (CAB @1193300). */
            ПилюляСлужебнаяКабинета(текст: м.текст, рамка: false)
        } else if м.служебное {
            /* Виды MK_CHAT_SYS_KINDS и фразы-уведомления — строкой по центру (карта §6.4.10). */
            СтрокаСлужебнаяЧата(текст: м.текст, хорошая: м.вид == "offer_ok" || м.вид == "offer_funded", значок: false)
        } else if м.вид == "offer", let п = м.предложение {
            КарточкаПредложенияЛида(предложение: п, текст: м.текст, заменено: м.заменено,
                                    согласовано: модель.согласовано, ценаОбъявления: модель.товар?.цена ?? 0,
                                    занято: модель.занято, деньги: Config.деньгиСделок,
                                    действие: { д in выполнить(д) })
        } else if м.вид == "counter", let в = м.встречная {
            КарточкаВстречнойЛида(встречная: в, заменено: м.заменено)
        } else if м.тип == "geo", let ш = м.широта, let д = м.долгота, ш != 0, д != 0 {
            КарточкаГеоЧата(моё: м.моё, широта: ш, долгота: д, изTelegram: м.изTelegram)
        } else if м.тип == "image", let адрес = Config.url(м.медиа) {
            ФотоЛида(адрес: адрес, моё: м.моё)
        } else {
            ОблакоЛида(сообщение: м)
        }
    }

    private func выполнить(_ д: КарточкаПредложенияЛида.Действие) {
        switch д {
        case .принять:
            Task { await модель.принятьПредложение() }
        case .встречная(let шаг):
            Task { await модель.встречная(шаг) }
        case .отказ, .окончательная:
            let окончательная: Bool
            if case .окончательная = д { окончательная = true } else { окончательная = false }
            Task {
                let сделано = await модель.отказ(окончательная: окончательная)
                if !сделано { await модель.открытьНаСайте(открыть) }
            }
        case .напомнить:
            модель.напомнить()
            полеВФокусе = true
        }
    }

    // MARK: - Низ

    /// «Подключитесь, чтобы ответить лично» — «Подключиться» (seller_join).
    private var полосаПодключения: some View {
        HStack(spacing: 10) {
            Text(т("lcm_join_t"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текст)
            Spacer(minLength: 6)
            Button {
                Task { await модель.подключиться() }
            } label: {
                Text(т("lcm_join_b"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
            .disabled(модель.занято)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.мята)
    }

    @ViewBuilder
    private var низ: some View {
        if модель.заблокирован {
            /* _lcmSetBlocked: я заблокировал — «Разблокировать»; меня — «Запросить разблокировку». */
            VStack(spacing: 8) {
                Text(т(модель.мнойЗаблокирован ? "lcm_blocked_me" : "lcm_blocked_by"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await модель.кнопкаБлокировки() }
                } label: {
                    Text(т(модель.мнойЗаблокирован ? "lcm_unblock" : "lcm_req_unblock"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                }
                .buttonStyle(.plain)
                .disabled(модель.занято)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(Theme.поверхность2)
            .overlay(alignment: .top) { Theme.линия.frame(height: 1) }
        } else {
            ПолеПерепискиСайта(текст: $модель.черновик, можно: можноОтправить,
                               отправить: { Task { await модель.отправить() } }, фокус: $полеВФокусе,
                               подсказка: т("reply_ph"))
        }
    }

    private var можноОтправить: Bool {
        !модель.отправляем && !модель.черновик.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Части лид-чата

/// _lcmRenderCtx: фото, название, цена и «Объявление» (нативная карточка, иначе страница сайта).
struct КарточкаТовараЛида: View {
    let товар: ТоварЛида
    let открыть: (URL) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let адрес = Config.url(товар.фото) {
                AsyncImage(url: адрес) { картинка in
                    картинка.resizable().scaledToFill()
                } placeholder: {
                    Theme.поверхность2
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(товар.название.isEmpty ? ИнбоксText.т("listing") : товар.название)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                if товар.цена > 0 {
                    Text(СделкиФормат.тенге(товар.цена))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            Spacer(minLength: 6)
            Button {
                if Config.нативнаяКарточка {
                    NativeRouter.shared.цель = .объявление(id: товар.id)
                } else if let адрес = Config.url("/marketplace.php?item=" + ИнбоксAPI.вАдрес(товар.id) + "&ret=chat") {
                    открыть(адрес)
                }
            } label: {
                Label(ИнбоксText.т("listing"), systemImage: "eye")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.поверхность2)
        .overlay(alignment: .bottom) { Theme.линия.frame(height: 1) }
    }
}

/// .kc-msg: продавец и ассистент — справа зелёным (у сайта обе стороны «me»), покупатель — слева; у ассистента подпись
/// «Kliko AI-ассистент», из Telegram — «из Telegram»; время внутри.
struct ОблакоЛида: View {
    let сообщение: СообщениеЛида

    private var текст: String {
        switch сообщение.тип {
        case "voice": return "🎤 " + ChatText.т("voice")
        case "video": return "🎬 " + ИнбоксText.т("video")
        case "image": return "📷 " + ChatText.т("photo")
        default: return сообщение.текст
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if сообщение.моё { Spacer(minLength: 48) }
            VStack(alignment: сообщение.моё ? .trailing : .leading, spacing: 3) {
                if сообщение.роль == "ai" {
                    Label(ИнбоксText.т("who_ai"), systemImage: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                }
                if сообщение.изTelegram {
                    Text(ИнбоксText.т("via_tg"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                }
                ОблакоСайта(текст: текст, время: ИнбоксВремя.время(сообщение.когда), моё: сообщение.моё)
            }
            if !сообщение.моё { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Фото в лид-чате (.kc-msg.media).
struct ФотоЛида: View {
    let адрес: URL
    let моё: Bool
    @Environment(\.openURL) private var открытьСсылку

    var body: some View {
        HStack(spacing: 0) {
            if моё { Spacer(minLength: 48) }
            Button {
                открытьСсылку(адрес)
            } label: {
                AsyncImage(url: адрес) { картинка in
                    картинка.resizable().scaledToFill()
                } placeholder: {
                    Theme.поверхность2
                }
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(ChatText.т("photo"))
            if !моё { Spacer(minLength: 48) }
        }
    }
}

/// _lcmOfferCard: предложение покупателя с кнопками продавца.
struct КарточкаПредложенияЛида: View {
    enum Действие {
        case принять, отказ, окончательная, напомнить
        case встречная(Int)
    }

    let предложение: ПредложениеЛида
    let текст: String
    let заменено: Bool
    let согласовано: Int
    let ценаОбъявления: Int
    let занято: Bool
    /// Config.деньгиСделок: выключен — «Отказаться» и «Цена окончательная» ведут на сайт (стрелка «наружу»).
    let деньги: Bool
    let действие: (Действие) -> Void

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }

    private var способ: String {
        let п = предложение
        var s: String
        switch п.способ {
        case "inst": s = т("of_m_inst")
        case "cred": s = т("of_m_cred")
        default: s = т("of_m_cash")
        }
        if (п.способ == "inst" || п.способ == "cred") && п.срок > 0 { s += " · " + String(п.срок) + " " + т("of_mon") }
        return s
    }

    private var скидка: Int {
        let ц = предложение.цена
        guard ценаОбъявления > 0, ц > 0, ц < ценаОбъявления else { return 0 }
        return Int((Double(ценаОбъявления - ц) / Double(ценаОбъявления) * 100).rounded())
    }

    private var погасла: Bool { предложение.отозвано || заменено }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(т("of_head"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                Spacer(minLength: 4)
                Text(способ)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(СделкиФормат.тенге(предложение.цена))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(погасла ? Theme.текстВторой : Theme.текст)
                    .strikethrough(погасла)
                if скидка > 0 && !погасла {
                    Text("−" + String(скидка) + "%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(КраскаОбъявлений.плохоТекст)
                }
            }
            if погасла {
                состояние(т(предложение.отозвано ? "of_gone" : "of_replaced"), хорошее: false)
            } else {
                подробности
                итог
            }
        }
        .padding(12)
        .frame(maxWidth: 330, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .opacity(погасла ? 0.7 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var подробности: some View {
        if !текст.isEmpty {
            Text(текст)
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
        }
        if предложение.заберёт || предложение.доставкаПокупателя {
            HStack(spacing: 6) {
                if предложение.заберёт { метка(т("arg_pickup")) }
                if предложение.доставкаПокупателя { метка(т("arg_ship")) }
            }
        }
        if предложение.подкреплено > 0 {
            Label(т("of_funded") + " · " + СделкиФормат.тенге(предложение.подкреплено), systemImage: "checkmark.shield")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(КраскаОбъявлений.хорошоТекст)
        }
    }

    @ViewBuilder
    private var итог: some View {
        if предложение.принято && согласовано <= 0 {
            состояние(т("of_used"), хорошее: false)
        } else if согласовано > 0 {
            состояние(т("of_done") + " · " + СделкиФормат.тенге(согласовано), хорошее: true)
            Text(т("of_next"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
            кнопка(т("of_nudge"), главная: false, наружу: false) { действие(.напомнить) }
        } else if предложение.встречная > 0 {
            состояние(т("of_ctr_sent").replacingOccurrences(of: "{sum}", with: СделкиФормат.тенге(предложение.встречная)),
                      хорошее: false)
        } else {
            кнопки
        }
    }

    private var кнопки: some View {
        var варианты: [ВариантВстречной] = []
        for шаг in ЛидМодель.шаги {
            let цена = ЛидМодель.встречнаяЦена(предложение.цена, шаг: шаг, объявление: ценаОбъявления)
            if цена > 0 { варианты.append(ВариантВстречной(шаг: шаг, цена: цена)) }
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                кнопка(т("of_accept_n").replacingOccurrences(of: "{sum}", with: СделкиФормат.тенге(предложение.цена)),
                       главная: true, наружу: false) { действие(.принять) }
                кнопка(т("of_decline"), главная: false, наружу: !деньги) { действие(.отказ) }
            }
            if !варианты.isEmpty {
                Text(т("of_ctr_h"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                HStack(spacing: 6) {
                    ForEach(варианты, id: \.шаг) { вариант in
                        Button {
                            действие(.встречная(вариант.шаг))
                        } label: {
                            VStack(spacing: 1) {
                                Text("+" + String(вариант.шаг) + "%")
                                    .font(.system(size: 13, weight: .heavy))
                                Text(СделкиФормат.тенге(вариант.цена))
                                    .font(.system(size: 10, weight: .semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .foregroundStyle(Theme.акцент)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                        }
                        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
                        .disabled(занято)
                    }
                }
            }
            кнопка(т("of_final"), главная: false, наружу: !деньги) { действие(.окончательная) }
        }
    }

    private func кнопка(_ подпись: String, главная: Bool, наружу: Bool, _ нажать: @escaping () -> Void) -> some View {
        Button(action: нажать) {
            HStack(spacing: 4) {
                Text(подпись)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if наружу {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(главная ? Color.white : Theme.текст)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(главная ? Theme.зелёный : Theme.поверхность2,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        .disabled(занято)
    }

    private func метка(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.текстВторой)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.поверхность2, in: Capsule())
    }

    private func состояние(_ текст: String, хорошее: Bool) -> some View {
        Text(текст)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(хорошее ? КраскаОбъявлений.хорошоТекст : Theme.текстВторой)
    }
}

/// Вариант встречной цены: шаг в процентах и цена (_lcmCounterPrice).
struct ВариантВстречной: Hashable {
    let шаг: Int
    let цена: Int
}

/// _lcmCounterCard: моя встречная цена справа — «+N%», цена и ответ покупателя.
struct КарточкаВстречнойЛида: View {
    let встречная: ВстречнаяЛида
    let заменено: Bool

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }

    private var состояние: (String, Bool) {
        if заменено { return (т("of_replaced"), false) }
        if встречная.принята { return (т("of_ctr_ok_s"), true) }
        if встречная.отклонена { return (т("of_ctr_no_s"), false) }
        if встречная.устарела { return (т("of_ctr_gone_s"), false) }
        return (т("of_ctr_wait"), false)
    }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 40)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(т("of_ctr_mine"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                    Spacer(minLength: 4)
                    Text("+" + String(встречная.шаг) + "%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                }
                Text(СделкиФормат.тенге(встречная.цена))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                Text(состояние.0)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(состояние.1 ? КраскаОбъявлений.хорошоТекст : Theme.текстВторой)
            }
            .padding(12)
            .frame(maxWidth: 280, alignment: .leading)
            .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .opacity(заменено ? 0.7 : 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// reportUserModal: «Пожаловаться · <имя>», причины, комментарий до 600 знаков, «Отмена» / «Отправить».
struct ОкноЖалобыНаПокупателя: View {
    let имя: String
    @ObservedObject var модель: ЛидМодель

    @Environment(\.dismiss) private var закрыть
    @State private var причина = "other"
    @State private var комментарий = ""
    @State private var отправляем = false
    @State private var ошибка: String? = nil

    private static let причины: [String] = ["fraud", "abuse", "spam", "prohibited", "other"]

    init(имя: String, модель: ЛидМодель) {
        self.имя = имя
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(т("rep_sub"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                    ForEach(Self.причины, id: \.self) { ключ in
                        Button {
                            причина = ключ
                        } label: {
                            HStack {
                                Text(т("rep_" + ключ))
                                    .font(.system(size: 15))
                                    .foregroundStyle(Theme.текст)
                                Spacer(minLength: 6)
                                if причина == ключ {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(Theme.акцент)
                                }
                            }
                            .padding(12)
                            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                    .strokeBorder(причина == ключ ? Theme.акцент : Theme.линия, lineWidth: 1.5)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(причина == ключ ? .isSelected : [])
                    }
                    TextField(т("rep_comment"), text: $комментарий, axis: .vertical)
                        .lineLimit(2...5)
                        .padding(12)
                        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                .strokeBorder(Theme.линия, lineWidth: 1.5)
                        }
                        .onChange(of: комментарий) { _, стало in
                            if стало.count > 600 { комментарий = String(стало.prefix(600)) }
                        }
                    if let ошибка {
                        Text(ошибка)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(КраскаОбъявлений.плохоТекст)
                    }
                    Button {
                        отправить()
                    } label: {
                        Text(т(отправляем ? "rep_sending" : "rep_send"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Theme.непрочитано, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                    .disabled(отправляем)
                }
                .padding(16)
            }
            .background(Theme.фонСтраницы)
            .navigationTitle(т("lcm_report") + (имя.isEmpty ? "" : " · " + имя))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("cancel")) { закрыть() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func отправить() {
        guard !отправляем else { return }
        отправляем = true
        ошибка = nil
        Task { @MainActor in
            let итог = await модель.пожаловаться(причина: причина, комментарий: комментарий)
            отправляем = false
            switch итог {
            case .отправлена:
                закрыть()
            case .ошибка(let текст):
                ошибка = текст
            }
        }
    }
}

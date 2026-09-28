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
    /// «Назад» своей шапки — системная панель спрятана, как у переписки dm.php (стеклянная кнопка iOS 26 с тенью).
    @Environment(\.dismiss) private var закрытьЭкран

    init(номер: String, имя: String, покупатель: String = "", открыть: @escaping (URL) -> Void) {
        _модель = StateObject(wrappedValue: ЛидМодель(номер: номер, имя: имя, покупатель: покупатель))
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            шапка
            if !модель.загружено {
                SiteSpinner.цвета(Theme.акцент)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let ошибка = модель.ошибка {
                ПустоСайта(значок: "exclamationmark.bubble", заголовок: ошибка, кнопка: ChatText.т("retry"),
                           действие: { попытка += 1 })
            } else {
                верх
                лента
                if модель.нужноПодключиться { полосаПодключения }
                if !модель.продавецПроверен { полосаВерификации }
                низ
            }
        }
        .background(ИнбоксКраска.карточка)
        .navigationTitle(модель.имя)
        .navigationBarTitleDisplayMode(.inline)
        /* Системная панель спрятана (на iOS 26 SDK «Назад» — стеклянный круг с широкой тенью, см. ChatThreadView);
           шапка .cm-head — своя, смахивание от края возвращает СмахнутьНазад. */
        .toolbar(.hidden, for: .navigationBar)
        .background {
            СмахнутьНазад().frame(width: 0, height: 0)
        }
        .tint(Theme.акцент)
        .task(id: попытка) {
            await модель.начать()
            await модель.опрос()
        }
        .onChange(of: фаза) { _, стала in
            if стала == .background { модель.ушлиВФон() }
        }
        /* Закрыли чат лида — список «Чата» заново, как _afterChatClose сайта. */
        .onDisappear { ИнбоксМодель.shared.перепискаЗакрыта() }
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

    /// #lead-chat-modal .cm-head на телефоне: «Назад», кружок 36 --acc-on с буквой, имя 15 жирным и подпись 12, справа
    /// «⋯» 32×36; отступ 12, линия снизу.
    private var шапка: some View {
        HStack(spacing: 6) {
            Button { закрытьЭкран() } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ИнбоксКраска.текст)
                    .frame(width: 36, height: 36)
                    .background(ИнбоксКраска.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .strokeBorder(ИнбоксКраска.линия, lineWidth: 1)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.94))
            .accessibilityLabel(ListingPageText.т("back"))
            заголовок
            Spacer(minLength: 0)
            меню
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(ИнбоксКраска.карточка)
        .overlay(alignment: .bottom) {
            ИнбоксКраска.линия
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    /// Имя в шапке — витрина покупателя (seller.php?id= сайта, «Профиль покупателя»), когда его номер известен: из
    /// строки инбокса или buyer_id ответа seller_chat. Номера нет — шапка не нажимается.
    @ViewBuilder
    private var заголовок: some View {
        if let номер = модель.витринаПокупателя {
            Button {
                ОкноПродавца.открыть(id: номер, имя: модель.имя)
            } label: {
                надпись.contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        } else {
            надпись
        }
    }

    private var надпись: some View {
        HStack(spacing: 6) {
            Text(String(модель.имя.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(ИнбоксКраска.наАкценте)
                .frame(width: 36, height: 36)
                .background(ИнбоксКраска.акцент, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(модель.имя)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ИнбоксКраска.текст)
                    .lineLimit(1)
                let подпись = модель.подзаголовок
                if !подпись.isEmpty {
                    Text(подпись)
                        .font(.system(size: 12))
                        .foregroundStyle(модель.нетСвязи ? Color(uiColor: Theme.hex(0xC0392B)) : Theme.текстВторой)
                        .lineLimit(1)
                }
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
        } label: {
            /* .cm-ibtn: вертикальное «⋯» 32×36 серым. */
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
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
    }

    /// _lcmDealBar (.kc-dealbar): «Покупатель оформил сделку» — «Перейти к сделке» во всю ширину (до 420 px) под текстом.
    private var полосаСделки: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("lcm_deal_live"))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(ИнбоксКраска.окТекст)
            Button {
                let номер = модель.сделка
                if NativeRouter.доступна(.сделка(id: номер)) {
                    NativeRouter.shared.цель = .сделка(id: номер)
                } else if let адрес = Config.страницаСайта("cabinet.php?deal=" + СделкиAPI.вАдрес(номер)) {
                    открыть(адрес)
                }
            } label: {
                Text(т("co_goto"))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(ИнбоксКраска.облакоМоё, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ИнбоксКраска.окФон)
        .overlay(alignment: .bottom) { ИнбоксКраска.линия.frame(height: 1) }
    }

    /// _lcmRenderContact: «Горячий лид — свяжитесь сразу», номер, «Позвонить», WhatsApp.
    private func полосаКонтакта(_ к: КонтактЛида) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Label(т("lcm_hot"), systemImage: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ИнбоксКраска.вниманиеТекст)
                if !к.показ.isEmpty {
                    Text(к.показ)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ИнбоксКраска.вниманиеТекст)
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
        .background(ИнбоксКраска.вниманиеФон)
    }

    /// «Пройти верификацию» — окно «Стать продавцом» (ЛистВерификации); сама проверка eGov — страницей сайта из него.
    private func пройтиВерификацию() {
        let адрес = Config.страницаСайта("cabinet?go=verify")
        if !ОкнаПриложения.shared.показать(.верификация, запасной: адрес), let адрес { открыть(адрес) }
    }

    /// #lcm-verify-bar — прямо над полем ввода (ПолосаВерификацииКабинета).
    private var полосаВерификации: some View {
        ПолосаВерификацииКабинета { пройтиВерификацию() }
    }

    // MARK: - Переписка

    private var лента: some View {
        ScrollViewReader { прокрутка in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if модель.сообщения.isEmpty {
                        Text(т("lcm_no_msgs"))
                            .font(.system(size: 13))
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
                                .foregroundStyle(ИнбоксКраска.облакоВремя)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(ИнбоксКраска.облакоЧужое, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .accessibilityLabel(т("typing"))
                            Spacer(minLength: 48)
                        }
                    }
                    Color.clear.frame(height: 1).id("низ")
                }
                .padding(14)
            }
            .background(ИнбоксКраска.карточка)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: модель.сообщения.count) { _, _ in
                withAnimation(ДвижениеСайта.прокрутка) { прокрутка.scrollTo("низ", anchor: .bottom) }
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
            ФотоПерепискиКабинета(адрес: адрес, моё: м.моё, время: ИнбоксВремя.время(м.когда))
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
        case .отказ(let подкреплено), .окончательная(let подкреплено):
            let окончательная: Bool
            if case .окончательная = д { окончательная = true } else { окончательная = false }
            Task {
                let сделано = await модель.отказ(окончательная: окончательная, подкреплено: подкреплено)
                if !сделано { await модель.открытьНаСайте(открыть) }
            }
        case .напомнить:
            модель.напомнить()
            полеВФокусе = true
        }
    }

    // MARK: - Низ

    /// .lcm-join: «Подключитесь, чтобы ответить лично» — «Подключиться» (seller_join); на телефоне кнопка во всю ширину
    /// под текстом, --tint-warn с кромкой сверху.
    private var полосаПодключения: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("lcm_join_t"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(ИнбоксКраска.вниманиеТекст)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                Task { await модель.подключиться() }
            } label: {
                Text(т("lcm_join_b"))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(ИнбоксКраска.акцент, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
            .disabled(модель.занято)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ИнбоксКраска.вниманиеФон)
        .overlay(alignment: .top) { ИнбоксКраска.вниманиеКромка.frame(height: 1) }
    }

    @ViewBuilder
    private var низ: some View {
        if модель.заблокирован {
            /* _lcmSetBlocked: я заблокировал — «Разблокировать»; меня — «Запросить разблокировку». */
            /* #lcm-block: красноватая плашка, текст #9b1c1c по центру, кнопка — карточка с кромкой во всю ширину. */
            VStack(spacing: 10) {
                Text(т(модель.мнойЗаблокирован ? "lcm_blocked_me" : "lcm_blocked_by"))
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.цвет(0x9B1C1C, 0xFF8A8F))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await модель.кнопкаБлокировки() }
                } label: {
                    Text(т(модель.мнойЗаблокирован ? "lcm_unblock" : "lcm_req_unblock"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ИнбоксКраска.текст)
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(ИнбоксКраска.карточка, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(ИнбоксКраска.линия, lineWidth: 1.5)
                        }
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                .disabled(модель.занято)
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(Theme.цвет(светлый: Theme.hex(0xFFF7F7), тёмный: Theme.hex(0xFF6168, 0.15)))
            .overlay(alignment: .top) {
                Theme.цвет(светлый: Theme.hex(0xF3C6C6), тёмный: Theme.hex(0xFF6168, 0.34)).frame(height: 1.5)
            }
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

/// #lcm-verify-bar и #dm-verify-bar: «Покупатель хочет купить безопасно» — «Пройти верификацию» (окно «Стать продавцом»).
/// У сайта — прямо над полем ввода: щит, текст --on-warn на --tint-warn, кромка сверху, кнопка градиентом кабинета.
struct ПолосаВерификацииКабинета: View {
    let действие: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.shield")
                .font(.system(size: 20))
                .foregroundStyle(ИнбоксКраска.вниманиеТекст)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(ИнбоксText.т("vbar_t"))
                    .font(.system(size: 13, weight: .semibold))
                Text(ИнбоксText.т("vbar_d"))
                    .font(.system(size: 11))
            }
            .foregroundStyle(ИнбоксКраска.вниманиеТекст)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                действие()
            } label: {
                Text(ИнбоксText.т("verify_go"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(ИнбоксКраска.градиент, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(ИнбоксКраска.вниманиеФон)
        .overlay(alignment: .top) { ИнбоксКраска.вниманиеКромка.frame(height: 1.5) }
    }
}

/// _lcmRenderCtx: фото 42, название 13, цена 12 и «Объявление» (нативная карточка, иначе страница сайта); подложка
/// --surf2, линия снизу 1.5.
struct КарточкаТовараЛида: View {
    let товар: ТоварЛида
    let открыть: (URL) -> Void

    var body: some View {
        HStack(spacing: 10) {
            if let адрес = Config.url(товар.фото) {
                КартинкаЛенты(адрес, пунктов: 42) {
                    ИнбоксКраска.карточка
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(товар.название.isEmpty ? ИнбоксText.т("listing") : товар.название)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ИнбоксКраска.текст)
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
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 14))
                        .accessibilityHidden(true)
                    Text(ИнбоксText.т("listing"))
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(ИнбоксКраска.подложка)
        .overlay(alignment: .bottom) { ИнбоксКраска.линия.frame(height: 1.5) }
    }
}

/// .kc-msg: продавец и ассистент — справа (у сайта обе стороны «me»), покупатель — слева; «Kliko AI-ассистент» и «из
/// Telegram» — внутри облака, время внутри (ОблакоКабинета).
struct ОблакоЛида: View {
    let сообщение: СообщениеЛида

    private var текст: String {
        switch сообщение.тип {
        case "voice": return ChatText.т("voice")
        case "video": return ИнбоксText.т("video")
        case "image": return ChatText.т("photo")
        default: return сообщение.текст
        }
    }

    private var значок: String? {
        switch сообщение.тип {
        case "voice": return "mic"
        case "video": return "video"
        case "image": return "photo"
        default: return nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if сообщение.моё { Spacer(minLength: 48) }
            ОблакоКабинета(текст: текст, время: ИнбоксВремя.время(сообщение.когда), моё: сообщение.моё,
                           кто: сообщение.роль == "ai" ? ИнбоксText.т("who_ai") : nil,
                           изTelegram: сообщение.изTelegram, значок: значок)
            if !сообщение.моё { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// _lcmOfferCard (.kc-ofr): предложение покупателя с кнопками продавца — во всю ширину переписки на --kc-soft с кромкой
/// --kc-line, скругление 14, отступ 12, промежутки 8.
struct КарточкаПредложенияЛида: View {
    enum Действие {
        case принять, напомнить
        /// Отказ и «Цена окончательная» — с суммой обеспечения предложения (0 — денег нет, всё здесь).
        case отказ(Int)
        case окончательная(Int)
        case встречная(Int)
    }

    let предложение: ПредложениеЛида
    let текст: String
    let заменено: Bool
    let согласовано: Int
    let ценаОбъявления: Int
    let занято: Bool
    /// Config.деньгиСделок: выключен — «Отказаться» и «Цена окончательная» у подкреплённого деньгами ведут на сайт
    /// (стрелка «наружу»).
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

    /// Стрелка «наружу» и сайт — только у подкреплённого деньгами при выключенных деньгах сделок.
    private var наружу: Bool { !деньги && предложение.подкреплено > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(т("of_head"))
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.4)
                    .textCase(.uppercase)
                    .foregroundStyle(погасла ? ИнбоксКраска.облакоВремя : ИнбоксКраска.глубокий)
                Spacer(minLength: 4)
                Text(способ)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ИнбоксКраска.облакоВремя)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(СделкиФормат.тенге(предложение.цена))
                    .font(.system(size: 22, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(погасла ? ИнбоксКраска.облакоВремя : ИнбоксКраска.текст)
                    .strikethrough(погасла)
                    .opacity(погасла ? 0.7 : 1)
                if скидка > 0 && !погасла {
                    Text("−" + String(скидка) + "%")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(ИнбоксКраска.вниманиеТекст)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(ИнбоксКраска.вниманиеФон, in: Capsule())
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ИнбоксКраска.мягкий, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ИнбоксКраска.мягкаяЛиния, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var подробности: some View {
        if !текст.isEmpty {
            Text(текст)
                .font(.system(size: 13))
                .lineSpacing(3)
                .foregroundStyle(ИнбоксКраска.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
        if предложение.заберёт || предложение.доставкаПокупателя {
            HStack(spacing: 6) {
                if предложение.заберёт { метка(т("arg_pickup")) }
                if предложение.доставкаПокупателя { метка(т("arg_ship")) }
            }
        }
        if предложение.подкреплено > 0 {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 13))
                    .accessibilityHidden(true)
                Text(т("of_funded") + " · " + СделкиФормат.тенге(предложение.подкреплено))
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(ИнбоксКраска.окТекст)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ИнбоксКраска.окФон, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                .lineSpacing(3)
                .foregroundStyle(ИнбоксКраска.облакоВремя)
            второстепенная(т("of_nudge"), стрелка: false) { действие(.напомнить) }
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
        /* .kc-ofr-steps: n1 — одна колонка, n2 и n4 — две, иначе три. */
        let колонок = варианты.count == 1 ? 1 : (варианты.count == 2 || варианты.count == 4 ? 2 : 3)
        let сетка = Array(repeating: GridItem(.flexible(), spacing: 8), count: колонок)
        let подкреплено = предложение.подкреплено
        return VStack(alignment: .leading, spacing: 8) {
            РядДолейКабинета(доли: [2, 1], промежуток: 8) {
                Button {
                    действие(.принять)
                } label: {
                    Text(т("of_accept_n").replacingOccurrences(of: "{sum}", with: СделкиФормат.тенге(предложение.цена)))
                        .font(.system(size: 14, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(ИнбоксКраска.облакоМоё, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                .disabled(занято)
                Button {
                    действие(.отказ(подкреплено))
                } label: {
                    HStack(spacing: 4) {
                        Text(т("of_decline"))
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if наружу { стрелкаНаружу }
                    }
                    .foregroundStyle(ИнбоксКраска.плохоТекст)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(ИнбоксКраска.плохоФон, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(ИнбоксКраска.плохоКромка, lineWidth: 1)
                    }
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                .disabled(занято)
            }
            if !варианты.isEmpty {
                Text(т("of_ctr_h"))
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(0.3)
                    .textCase(.uppercase)
                    .foregroundStyle(ИнбоксКраска.облакоВремя)
                    .padding(.top, 4)
                LazyVGrid(columns: сетка, spacing: 8) {
                    ForEach(варианты, id: \.шаг) { вариант in
                        Button {
                            действие(.встречная(вариант.шаг))
                        } label: {
                            VStack(spacing: 1) {
                                Text("+" + String(вариант.шаг) + "%")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(ИнбоксКраска.глубокий)
                                Text(СделкиФормат.тенге(вариант.цена))
                                    .font(.system(size: 14, weight: .heavy))
                                    .monospacedDigit()
                                    .foregroundStyle(ИнбоксКраска.текст)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(ИнбоксКраска.карточка, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(ИнбоксКраска.мягкаяЛиния, lineWidth: 1)
                            }
                        }
                        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
                        .disabled(занято)
                    }
                }
            }
            второстепенная(т("of_final"), стрелка: наружу) { действие(.окончательная(подкреплено)) }
        }
    }

    private var стрелкаНаружу: some View {
        Image(systemName: "arrow.up.right")
            .font(.system(size: 10, weight: .bold))
            .accessibilityHidden(true)
    }

    /// .kc-ofr-b2: карточка с кромкой --kc-line, высота 40, 13.
    private func второстепенная(_ подпись: String, стрелка: Bool, _ нажать: @escaping () -> Void) -> some View {
        Button(action: нажать) {
            HStack(spacing: 4) {
                Text(подпись)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if стрелка { стрелкаНаружу }
            }
            .foregroundStyle(ИнбоксКраска.текст)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(ИнбоксКраска.карточка, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(ИнбоксКраска.мягкаяЛиния, lineWidth: 1)
            }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .disabled(занято)
    }

    /// .kc-ofr-tags span: 12 жирным на --kc-card пилюлей.
    private func метка(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(ИнбоксКраска.текст)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(ИнбоксКраска.карточка, in: Capsule())
    }

    /// .kc-ofr-s: 12 жирным серым, .ok — --on-ok.
    private func состояние(_ текст: String, хорошее: Bool) -> some View {
        Text(текст)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(хорошее ? ИнбоксКраска.окТекст : ИнбоксКраска.облакоВремя)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Вариант встречной цены: шаг в процентах и цена (_lcmCounterPrice).
struct ВариантВстречной: Hashable {
    let шаг: Int
    let цена: Int
}

/// _lcmCounterCard (.kc-ofr.mine): моя встречная цена справа, не шире 80 % — «+N%», цена и ответ покупателя.
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

    /// .gone: цена зачёркнута и бледнее.
    private var погасла: Bool { заменено || встречная.устарела }

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 64)
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(т("of_ctr_mine"))
                        .font(.system(size: 11, weight: .heavy))
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(ИнбоксКраска.облакоВремя)
                    Spacer(minLength: 4)
                    Text("+" + String(встречная.шаг) + "%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(ИнбоксКраска.облакоВремя)
                }
                Text(СделкиФормат.тенге(встречная.цена))
                    .font(.system(size: 22, weight: .black))
                    .monospacedDigit()
                    .foregroundStyle(ИнбоксКраска.текст)
                    .strikethrough(погасла)
                    .opacity(погасла ? 0.7 : 1)
                Text(состояние.0)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(состояние.1 ? ИнбоксКраска.окТекст : ИнбоксКраска.облакоВремя)
            }
            .padding(12)
            .background(ИнбоксКраска.мягкий, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(ИнбоксКраска.мягкаяЛиния, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// reportUserModal: «Пожаловаться · <имя>», подпись, причины, комментарий до 600 знаков, внизу «Отмена» и «Отправить»
/// рядом. У сайта — карточка по центру; здесь — лист с тем же содержимым.
struct ОкноЖалобыНаПокупателя: View {
    let имя: String
    @ObservedObject var модель: ЛидМодель

    @Environment(\.dismiss) private var закрыть
    @State private var причина = "other"
    @State private var комментарий = ""
    @State private var отправляем = false
    @State private var ошибка: String? = nil

    private static let причины: [String] = ["fraud", "abuse", "spam", "prohibited", "other"]
    /// Выбранная причина: кромка #0f7a44, подложка #f0fdf4.
    private static let выбранаКромка = Color(uiColor: Theme.hex(0x0F7A44))
    private static let выбранаФон = Theme.цвет(0xF0FDF4, 0x14261B)

    init(имя: String, модель: ЛидМодель) {
        self.имя = имя
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(т("lcm_report") + (имя.isEmpty ? "" : " · " + имя))
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(ИнбоксКраска.текст)
                        .accessibilityAddTraits(.isHeader)
                    Text(т("rep_sub"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 2)
                ForEach(Self.причины, id: \.self) { ключ in
                    let выбрана = причина == ключ
                    Button {
                        причина = ключ
                    } label: {
                        Text(т("rep_" + ключ))
                            .font(.system(size: 14))
                            .foregroundStyle(ИнбоксКраска.текст)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(выбрана ? Self.выбранаФон : ИнбоксКраска.карточка,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(выбрана ? Self.выбранаКромка : ИнбоксКраска.линия, lineWidth: 1.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(выбрана ? .isSelected : [])
                }
                TextField(т("rep_comment"), text: $комментарий, axis: .vertical)
                    .font(.system(size: 14))
                    .lineLimit(2...5)
                    .padding(12)
                    .background(ИнбоксКраска.карточка, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(ИнбоксКраска.линия, lineWidth: 1.5)
                    }
                    .onChange(of: комментарий) { _, стало in
                        if стало.count > 600 { комментарий = String(стало.prefix(600)) }
                    }
                if let ошибка {
                    Text(ошибка)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ИнбоксКраска.плохоТекст)
                }
                HStack(spacing: 10) {
                    Button {
                        закрыть()
                    } label: {
                        Text(т("cancel"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(ИнбоксКраска.текст)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(ИнбоксКраска.карточка, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(ИнбоксКраска.линия, lineWidth: 1.5)
                            }
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                    Button {
                        отправить()
                    } label: {
                        Text(т(отправляем ? "rep_sending" : "rep_send"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(uiColor: Theme.hex(0xDC2626)),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                    .disabled(отправляем)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ИнбоксКраска.карточка)
        /* По высоте причин и кнопок — без пустоты снизу. */
        .листПоВысоте()
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

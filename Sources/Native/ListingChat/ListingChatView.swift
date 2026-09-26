import SwiftUI
import UIKit

/**
 ЧАТ ПО ОБЪЯВЛЕНИЮ — ЭКРАН (этап 38, владелец 25.09.2026: «почти 100% похоже на сайт»).

 Вид — виджет #mk-chat-scrim страницы объявления сайта и облака переписки этапа 30 (css/chat.min.css, .mk-* из
 css/marketplace.min.css): шапка .mk-chat-head — «Назад», зелёный кружок ассистента, «Чат с продавцом» и подпись по статусу
 («Kliko AI-ассистент отвечает · имя», «Продавец · на связи», «Продавец скоро подключится», без сети — «Нет соединения —
 переподключение…»); под ней объявление .mk-chat-ctx — фото 44, название, цена и зелёная «Объявление» (снятое — серое фото,
 «Продано» / «Услуга больше не актуальна» / «Объект сдан» и «Все товары продавца»); полоса .kc-dealbar, если цена
 согласована; переписка .kc-thread — облака .kc-msg с подписью «Продавец» / «Kliko AI-ассистент», строки .kc-sys,
 карточки предложения .mk-ofc, гео .mk-geo, «✓ Отправлено» / «✓✓ Прочитано» под последним своим, три точки, пока
 собеседник пишет, и строка статуса («Продавец на связи», «С вами продавец», «Продавец уведомлён и скоро подключится»);
 окно входа .mk-chat-gate; внизу «Позвать продавца» (.mk-chat-callbar), строка ввода .kc-bar этапа 30 или, при
 блокировке, .mk-chat-block с «Разблокировать» / «Запросить разблокировку». Краски — динамические Theme: светлая и тёмная.
 */
struct ЭкранЧатаОбъявления: View {
    @StateObject private var модель: МодельЧатаОбъявления
    /// Этап 37: снятие блокировки идёт его запросом — по нему экран узнаёт, что пора перечитать чат.
    @ObservedObject private var действия = ДействияСПродавцом.shared
    let открыть: (URL) -> Void
    @State private var окноПредложения = false
    @FocusState private var полеВФокусе: Bool
    @Environment(\.dismiss) private var закрыть

    init(товар: Listing, предложить: Bool, открыть: @escaping (URL) -> Void) {
        _модель = StateObject(wrappedValue: МодельЧатаОбъявления(товар: товар, предложить: предложить))
        self.открыть = открыть
    }

    var body: some View {
        VStack(spacing: 0) {
            ШапкаЧатаОбъявления(подпись: модель.подписьШапки, назад: { закрыть() })
            КонтекстЧатаОбъявления(товар: модель.товар, изЧата: модель.товарЧата,
                                   кОбъявлению: { закрыть() }, кПродавцу: открытьПродавца)
            полосаСделки
            лента
            низ
        }
        .background(Theme.поверхность)
        .navigationTitle(ListingChatText.т("title"))
        .navigationBarTitleDisplayMode(.inline)
        /* Как переписка этапа 30 и страница объявления: системная панель спрятана (у iOS 26 её «Назад» — стеклянный круг
           с широкой тенью), шапка своя; жест «смахнуть от края — назад» возвращает СмахнутьНазад. */
        .toolbar(.hidden, for: .navigationBar)
        .background {
            СмахнутьНазад().frame(width: 0, height: 0)
        }
        .tint(Theme.акцент)
        .overlay(alignment: .bottom) { плашка }
        .sheet(isPresented: $окноПредложения) {
            ЛистПредложенияЦены(товар: модель.товар) { цена, процент, забрать in
                Task { await модель.предложитьЦену(цена, процент: процент, забрать: забрать) }
            }
        }
        /* «Разблокировать» ушло запросом этапа 37 — когда он снял блокировку, перечитываем чат (blocked придёт false). */
        .onChange(of: действия.заблокирован(модель.продавецID)) { было, стало in
            if было && !стало && модель.заблокировалЯ {
                Task { await модель.перезагрузить() }
            }
        }
        /* Вошли своим листом входа (ОкнаПриложения) — чат читается заново уже вошедшим. */
        .onReceive(NotificationCenter.default.publisher(for: ОкнаПриложения.вошли)) { _ in
            Task { await модель.перезагрузить() }
        }
        .task {
            await модель.начать()
            if await модель.открытьПредложениеСразу() { окноПредложения = true }
            await модель.опрос()
        }
        /* Этап 16: переписка на экране — просьба оценить её не перебивает (ПросьбаОценить). */
        .onAppear { ПросьбаОценить.shared.делоНаЭкране() }
        .onDisappear { ПросьбаОценить.shared.делоУшло(карточка: false) }
    }

    // MARK: - Переписка

    private var лента: some View {
        ScrollViewReader { прокрутка in
            ScrollView {
                LazyVStack(spacing: 8) {
                    содержимоеЛенты
                    Color.clear
                        .frame(height: 1)
                        .id("низ")
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await модель.обновить() }
            .onChange(of: модель.сообщения.count) { _, _ in вниз(прокрутка) }
            .onChange(of: модель.барьер) { _, _ in вниз(прокрутка) }
            .onChange(of: модель.ждёмОтвет) { _, _ in вниз(прокрутка) }
            .onChange(of: модель.печатает) { _, _ in вниз(прокрутка) }
            .onChange(of: полеВФокусе) { _, вФокусе in
                guard вФокусе else { return }
                /* Клавиатура ещё выезжает и сжимает ленту — вниз, когда доедет. */
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    вниз(прокрутка)
                }
            }
            .onAppear { прокрутка.scrollTo("низ", anchor: .bottom) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var содержимоеЛенты: some View {
        if !модель.загружено {
            УведомлениеЧатаСайта(текст: ListingChatText.т("loading"))
                .padding(.top, 24)
        } else if let текстСбоя = модель.сбой {
            VStack(spacing: 12) {
                УведомлениеЧатаСайта(текст: текстСбоя)
                Button(ListingChatText.т("retry")) {
                    Task { await модель.повторить() }
                }
                .font(.system(size: 15, weight: .bold))
                .tint(Theme.акцент)
            }
            .padding(.top, 24)
        } else {
            сообщенияЛенты
            if модель.ждёмОтвет || модель.печатает {
                ТочкиПечатиЧата()
            }
            СостояниеЧатаОбъявления(статус: модель.статус, наСвязи: модель.продавецНаСвязи,
                                    присутствие: модель.присутствие)
            if let барьер = модель.барьер {
                БарьерЧата(барьер: барьер, войти: войти)
            }
        }
    }

    /// Облака и карточки по порядку; под последним своим — отметка прочтения.
    private var сообщенияЛенты: some View {
        let заменённые = модель.заменённые
        let последнее = модель.последнееМоё
        let безГаранта = модель.безГаранта || модель.товар.безГаранта
        return ForEach(модель.сообщения) { с in
            СтрокаЧатаОбъявления(сообщение: с, заменено: заменённые.contains(с.id), согласовано: модель.согласовано,
                                  безГаранта: безГаранта, ответитьНаСайте: открытьЧатНаСайте)
            if с.id == последнее {
                ОтметкаПрочтенияЧата(прочитано: модель.прочитано(с))
            }
        }
    }

    private func вниз(_ прокрутка: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { прокрутка.scrollTo("низ", anchor: .bottom) }
    }

    // MARK: - Низ

    @ViewBuilder
    private var низ: some View {
        if модель.загружено && модель.сбой == nil {
            if модель.заблокирован {
                ПолосаБлокировкиЧата(заблокировалЯ: модель.заблокировалЯ,
                                      кнопка: кнопкаБлокировки,
                                      ждём: ждёмБлокировку,
                                      действие: действиеБлокировки)
            } else {
                VStack(spacing: 0) {
                    if модель.можноПозвать {
                        КнопкаПозватьПродавца {
                            Task { await модель.позватьПродавца() }
                        }
                    }
                    if модель.неОтправлено {
                        Text(ChatText.т("not_sent") + (модель.причина.isEmpty ? "" : " (\(модель.причина))"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.малиновый)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    ПолеПерепискиСайта(текст: $модель.черновик, можно: можноОтправить,
                                       отправить: { Task { await модель.отправить() } }, фокус: $полеВФокусе,
                                       подсказка: ListingChatText.т("placeholder"))
                }
                .background(Theme.поверхность)
            }
        }
    }

    private var можноОтправить: Bool {
        !модель.отправляем && !модель.черновик.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Под текстом блокировки — «Разблокировать» (заблокировал я; этап 37 включён) или «Запросить разблокировку» (один раз).
    private var кнопкаБлокировки: String? {
        guard !модель.продавецID.isEmpty else { return nil }
        if модель.заблокировалЯ {
            return Config.жалобы ? ListingChatText.т("unblock") : nil
        }
        return модель.просьбаУшла ? nil : ListingChatText.т("request_unblock")
    }

    private var ждёмБлокировку: Bool {
        модель.заблокировалЯ ? действия.блокировкаВПути.contains(модель.продавецID) : модель.просимРазблокировать
    }

    private func действиеБлокировки() {
        if модель.заблокировалЯ {
            модель.разблокировать()
        } else {
            Task { await модель.попроситьРазблокировать() }
        }
    }

    @ViewBuilder
    private var полосаСделки: some View {
        if модель.сделкаИдёт && !модель.сделка.isEmpty {
            ПолосаСделкиЧата(заголовок: ListingChatText.т("deal_live"), кнопка: ListingChatText.т("deal_open"),
                             нажать: открытьСделку)
        } else if модель.согласовано > 0 && !(модель.безГаранта || модель.товар.безГаранта) {
            ПолосаСделкиЧата(заголовок: String(format: ListingChatText.т("agreed"), суммаСогласия),
                             кнопка: String(format: ListingChatText.т("deal_go"), суммаСогласия),
                             нажать: открытьОбъявлениеНаСайте)
        }
    }

    private var суммаСогласия: String { ListingCard.тенге(Double(модель.согласовано)) }

    /// Плашка модели (.mk-toast) — над строкой ввода.
    private var плашка: some View {
        ZStack(alignment: .bottom) {
            if let сообщение = модель.плашка {
                ПлашкаИзбранного(сообщение: сообщение, войти: войти)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 76)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .id(сообщение.id)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: модель.плашка?.id)
    }

    // MARK: - Переходы на сайт

    /// Свой экран входа листом поверх вкладок (ОкнаПриложения); слоя окон нет — страница входа сайта, как раньше.
    private func войти() {
        let адрес = МодельЧатаОбъявления.адресВхода
        if ОкнаПриложения.shared.показать(.вход, запасной: адрес) { return }
        if let адрес { открыть(адрес) }
    }

    /// Всё, что держит деньги (подкрепить, отозвать, встречная цена, оформление), — на сайте: объявление с открытым чатом,
    /// ?item=<номер>&chat=1 (сайт сам открывает чат по chat=1).
    private func открытьЧатНаСайте() {
        guard let основа = модель.товар.адрес,
              var части = URLComponents(url: основа, resolvingAgainstBaseURL: false) else { return }
        var поля = части.queryItems ?? []
        поля.append(URLQueryItem(name: "chat", value: "1"))
        части.queryItems = поля
        if let адрес = части.url { открыть(адрес) }
    }

    /// «Оформить за …» — страница объявления на сайте: сделку оформляет сайт (как «Купить безопасно» этапа 29).
    private func открытьОбъявлениеНаСайте() {
        if let адрес = модель.товар.адрес { открыть(адрес) }
    }

    /// «Перейти к сделке» — своя карточка сделки во вкладке «Кабинет» (этап 43, как у лид-чата); без неё —
    /// /kz/<язык>/cabinet.php?deal=<номер> (mkChatGoDeal).
    private func открытьСделку() {
        let сделка = модель.сделка
        if СделкиAPI.годныйНомер(сделка) && NativeRouter.доступна(.сделка(id: сделка)) {
            NativeRouter.shared.цель = .сделка(id: сделка)
            return
        }
        let номер = сделка.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? сделка
        if let адрес = Config.страницаСайта("cabinet.php?deal=" + номер) { открыть(адрес) }
    }

    /// «Все товары продавца» у снятого — его страница на сайте.
    private func открытьПродавца() {
        let номер = модель.продавецID
        guard !номер.isEmpty else { return }
        if ОкноПродавца.открыть(id: номер) { return }
        if let адрес = СинхронПодписок.страницаПродавца(номер) { открыть(адрес) }
    }
}

// MARK: - Шапка (.mk-chat-head)

/// «Назад» как у переписки этапа 30, кружок ассистента (.mk-chat-ava) и две строки: «Чат с продавцом» и подпись статуса.
struct ШапкаЧатаОбъявления: View {
    let подпись: String
    let назад: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: назад) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .frame(width: 36, height: 36)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.94))
            .accessibilityLabel(ListingPageText.т("back"))
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(colors: [Theme.зелёный2, Theme.зелёныйЯркий], startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    in: Circle()
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(ListingChatText.т("title"))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(подпись)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            Spacer(minLength: 0)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Theme.поверхность)
        .overlay(alignment: .bottom) {
            Theme.линия
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Объявление под шапкой (.mk-chat-ctx)

/// Фото 44 со скруглением, название жирным, цена серым и зелёная «Объявление» с глазом; снятое — фото серее, вместо цены
/// метка цветом вида (продано — малиновым, аренда — оранжевым, услуга — серым) и «Все товары продавца» рамкой.
struct КонтекстЧатаОбъявления: View {
    let товар: Listing
    /// product из widget_data; пока не пришёл — то, что известно по странице объявления (mkChatCtx сайта).
    let изЧата: ЧатОбъявленияAPI.Товар?
    let кОбъявлению: () -> Void
    let кПродавцу: () -> Void

    private var снято: Bool { изЧата?.снято ?? false }
    private var вид: String { изЧата?.вид ?? (товар.услуга ? "service" : (товар.forRent ? "rent" : "goods")) }

    private var название: String {
        let сайта = изЧата?.название ?? ""
        return сайта.isEmpty ? товар.title : сайта
    }

    private var фото: URL? {
        if let адрес = изЧата?.фото, let url = Config.url(адрес) { return url }
        return товар.обложка ?? товар.фотоАдреса.first
    }

    private var цена: String? {
        if let сумма = изЧата?.цена, сумма > 0 { return ListingCard.тенге(сумма) }
        let строка = ListingCard.цена(товар)
        return строка.isEmpty ? nil : строка
    }

    var body: some View {
        HStack(spacing: 10) {
            обложка
            VStack(alignment: .leading, spacing: 3) {
                Text(название)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                if снято {
                    Label(ListingChatText.т(ключСнятого), systemImage: "tag")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(цветСнятого)
                        .labelStyle(МеткаСайта())
                } else if let строкаЦены = цена {
                    Text(строкаЦены)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            кнопка
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Theme.поверхность2)
        .overlay(alignment: .bottom) {
            Theme.линия
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    private var ключСнятого: String {
        switch вид {
        case "service": return "gone_service"
        case "rent": return "gone_rent"
        default: return "gone_goods"
        }
    }

    private var цветСнятого: Color {
        switch вид {
        case "service": return Theme.текстВторой
        case "rent": return Theme.оранжевый
        default: return Theme.малиновый
        }
    }

    private var обложка: some View {
        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
            .fill(Theme.поверхность)
            .overlay {
                if let адрес = фото {
                    AsyncImage(url: адрес) { картинка in
                        картинка.resizable().scaledToFill()
                    } placeholder: {
                        Theme.поверхность
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .grayscale(снято ? 0.7 : 0)
                    .opacity(снято ? 0.85 : 1)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var кнопка: some View {
        if снято {
            Button(action: кПродавцу) {
                HStack(spacing: 4) {
                    Text(ListingChatText.т(вид == "service" ? "seller_services" : "seller_goods"))
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 11, weight: .bold))
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Theme.текст)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
            .accessibilityHint(ListingPageText.т("on_site"))
        } else {
            Button(action: кОбъявлению) {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(ListingChatText.т("listing"))
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        }
    }
}

// MARK: - Полоса сделки (.kc-dealbar)

/// Мятная полоса под объявлением: жирный заголовок цветом --on-ok и зелёная кнопка на всю ширину со щитом.
struct ПолосаСделкиЧата: View {
    let заголовок: String
    let кнопка: String
    let нажать: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(заголовок)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.акцент)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: нажать) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(кнопка)
                        .font(.system(size: 15, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            .accessibilityHint(ListingPageText.т("on_site"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.мята)
        .overlay(alignment: .bottom) {
            Theme.линия
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Строки переписки

/// Одна запись переписки — как mkChatBubble: служебная — строкой .kc-sys (offer_ok / offer_funded — зелёной), гео —
/// карточкой, своё предложение и встречная цена — карточками .mk-ofc, остальное — облаком.
struct СтрокаЧатаОбъявления: View {
    let сообщение: СообщениеЧатаОбъявления
    let заменено: Bool
    let согласовано: Int
    let безГаранта: Bool
    let ответитьНаСайте: () -> Void

    var body: some View {
        if сообщение.роль == "system" {
            СтрокаСлужебнаяЧата(текст: сообщение.текст, хорошая: false, значок: false)
        } else if СообщениеЧатаОбъявления.видыУведомлений.contains(сообщение.вид) {
            СтрокаСлужебнаяЧата(текст: сообщение.текст,
                                хорошая: сообщение.вид == "offer_ok" || сообщение.вид == "offer_funded", значок: false)
        } else if сообщение.тип == "geo", let широта = сообщение.широта, let долгота = сообщение.долгота {
            КарточкаГеоЧата(моё: сообщение.моё, широта: широта, долгота: долгота, изTelegram: сообщение.изTelegram)
        } else if сообщение.вид == "offer", сообщение.моё, let предложение = сообщение.предложение {
            КарточкаПредложенияЧата(предложение: предложение, заменено: заменено, согласовано: согласовано,
                                    безГаранта: безГаранта)
        } else if сообщение.вид == "counter", let встречная = сообщение.встречная {
            КарточкаВстречнойЦены(встречная: встречная, заменено: заменено, ответитьНаСайте: ответитьНаСайте)
        } else {
            ОблакоЧатаОбъявления(сообщение: сообщение)
        }
    }
}

/// Облако .kc-msg: своё — справа на --kc-acc с «хвостом» справа, продавца и ассистента — слева на --kc-peer с кромкой и
/// подписью «Продавец» / «Kliko AI-ассистент» (.kc-who); из Telegram — плашка «из Telegram» (.mk-cvia). Времени в облаке
/// у виджета сайта нет — нет и здесь.
struct ОблакоЧатаОбъявления: View {
    let сообщение: СообщениеЧатаОбъявления

    private var моё: Bool { сообщение.моё }

    private var кто: String? {
        switch сообщение.роль {
        case "seller": return ListingChatText.т("who_seller")
        case "ai": return ListingChatText.т("who_ai")
        default: return nil
        }
    }

    private var текст: String {
        ЧатСообщение.подпись(тип: сообщение.тип == "voice" || сообщение.тип == "image" ? сообщение.тип : "text",
                              текст: сообщение.текст)
    }

    private var форма: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: моё ? 14 : 5,
                               bottomTrailingRadius: моё ? 5 : 14, topTrailingRadius: 14, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 0) {
            if моё { Spacer(minLength: 48) }
            облако
            if !моё { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(голос)
        .modifier(КопироватьДляГолоса(текст: Config.удобныйЧат && !сообщение.текст.isEmpty ? сообщение.текст : nil))
    }

    @ViewBuilder
    private var облако: some View {
        if Config.удобныйЧат && !сообщение.текст.isEmpty {
            основа
                .contentShape(.contextMenuPreview, форма)
                .contextMenu {
                    Button {
                        ЧатБуфер.скопировать(сообщение.текст)
                    } label: {
                        Label(ChatComfortText.т("copy"), systemImage: "doc.on.doc")
                    }
                }
        } else {
            основа
        }
    }

    private var основа: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let подписьКто = кто {
                Text(подписьКто)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(моё ? Color.white : Theme.акцент)
                    .opacity(0.85)
            }
            if сообщение.изTelegram {
                ПлашкаТелеграмаЧата(моё: моё)
            }
            if let адрес = сообщение.фото.flatMap({ Config.url($0) }) {
                AsyncImage(url: адрес) { картинка in
                    картинка.resizable().scaledToFill()
                } placeholder: {
                    Theme.поверхность2
                }
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                Text(текст)
                    .font(.system(size: 16))
                    .foregroundStyle(моё ? Color.white : Theme.текст)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(моё ? Theme.пузырьМой : Theme.пузырьЧужой, in: форма)
        .overlay {
            if !моё {
                форма.stroke(Theme.линия, lineWidth: 1)
            }
        }
    }

    /// «Вы: …», «Продавец: …», «Kliko AI-ассистент: …».
    private var голос: String {
        let начало = моё ? ChatText.т("you") : ((кто ?? ChatText.т("peer")) + ": ")
        return начало + текст
    }
}

/// «из Telegram» — голубая плашка над текстом (.mk-cvia), в своём облаке — полупрозрачная белая.
struct ПлашкаТелеграмаЧата: View {
    let моё: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 9, weight: .bold))
                .accessibilityHidden(true)
            Text(ListingChatText.т("via_tg"))
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(моё ? Color.white : Theme.проверен)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(моё ? Color.white.opacity(0.22) : Theme.проверен.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.xxs, style: .continuous))
    }
}

/// Строка .kc-sys: по центру, мелко, серым на --kc-soft; «хорошая» (offer_ok, offer_funded, «Продавец на связи») — цветом
/// --on-ok на мятном, со значком галочки у строк статуса (mkIco("check")).
struct СтрокаСлужебнаяЧата: View {
    let текст: String
    let хорошая: Bool
    let значок: Bool

    var body: some View {
        HStack(spacing: 5) {
            if значок {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(текст)
                .font(.system(size: 12))
                .lineSpacing(2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(хорошая ? Theme.акцент : Theme.текстВторой)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(хорошая ? Theme.мята : Theme.поверхность2,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Строка статуса после переписки (mkChatRender): seller_active — «Продавец на связи» (зелёная) или «С вами продавец,
/// <присутствие>»; hot_lead — «Продавец уведомлён и скоро подключится»; иначе — ничего.
struct СостояниеЧатаОбъявления: View {
    let статус: String
    let наСвязи: Bool
    let присутствие: String

    var body: some View {
        switch статус {
        case "seller_active":
            if наСвязи {
                СтрокаСлужебнаяЧата(текст: ListingChatText.т("st_online"), хорошая: true, значок: true)
            } else {
                СтрокаСлужебнаяЧата(текст: ListingChatText.т("st_with") + (присутствие.isEmpty ? "" : ", " + присутствие),
                                    хорошая: false, значок: true)
            }
        case "hot_lead":
            СтрокаСлужебнаяЧата(текст: ListingChatText.т("st_hot"), хорошая: false, значок: true)
        default:
            EmptyView()
        }
    }
}

/// «✓ Отправлено» / «✓✓ Прочитано» (.mk-cread) — справа, мелко; прочитано — зелёным.
struct ОтметкаПрочтенияЧата: View {
    let прочитано: Bool

    var body: some View {
        Text(ListingChatText.т(прочитано ? "read" : "sent"))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(прочитано ? Theme.зелёный2 : Theme.текстВторой)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 4)
            .padding(.top, -4)
    }
}

/// Три точки в облаке собеседника (.mk-typing): ассистент отвечает или продавец пишет.
struct ТочкиПечатиЧата: View {
    @State private var шаг = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { номер in
                    Circle()
                        .fill(Theme.текстВторой)
                        .frame(width: 6, height: 6)
                        .opacity(шаг ? (номер == 1 ? 0.9 : 0.4) : (номер == 1 ? 0.4 : 0.9))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.пузырьЧужой,
                        in: UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 5, bottomTrailingRadius: 14,
                                                   topTrailingRadius: 14, style: .continuous))
            .opacity(0.8)
            Spacer(minLength: 48)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { шаг = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ListingChatText.т("typing"))
    }
}

// MARK: - Карточки предложения (.mk-ofc)

/// Общая рамка карточки: --mk-surf2 с кромкой, скругление 14, у своей стороны снизу — 6; погасшая — бледнее.
private struct РамкаКарточкиЧата<Содержимое: View>: View {
    let справа: Bool
    let погасла: Bool
    let содержимое: Содержимое

    init(справа: Bool, погасла: Bool, @ViewBuilder содержимое: () -> Содержимое) {
        self.справа = справа
        self.погасла = погасла
        self.содержимое = содержимое()
    }

    private var форма: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: справа ? 14 : 6,
                               bottomTrailingRadius: справа ? 6 : 14, topTrailingRadius: 14, style: .continuous)
    }

    var body: some View {
        HStack(spacing: 0) {
            if справа { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 0) {
                содержимое
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minWidth: 180, alignment: .leading)
            .background(Theme.поверхность2, in: форма)
            .overlay { форма.stroke(Theme.линия, lineWidth: 1) }
            .opacity(погасла ? 0.6 : 1)
            if !справа { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Заголовок, сумма и строка под ней — общие у своей карточки и встречной.
private struct ВерхКарточкиЧата: View {
    let заголовок: String
    let сумма: Int
    let зачёркнута: Bool

    var body: some View {
        Text(заголовок)
            .font(.system(size: 11, weight: .heavy))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(Theme.текстВторой)
            .padding(.bottom, 6)
        Text(ListingCard.тенге(Double(сумма)))
            .font(.system(size: 22, weight: .black))
            .strikethrough(зачёркнута)
            .foregroundStyle(Theme.текст)
    }
}

/// Строка «Принято продавцом», «Подкреплено · …», «Цена согласована» (.mk-ofc-ok): щит с галочкой на зелёном оттенке.
private struct ОтметкаКарточкиЧата: View {
    let текст: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 12, weight: .bold))
        }
        .foregroundStyle(Theme.зелёный2)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .padding(.top, 8)
    }
}

private struct СтрокаКарточкиЧата: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.текстВторой)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
}

/// Своё предложение (mkOfferOwnCard) — справа. Отозвано или заменено новым — бледное, сумма зачёркнута; принята встречная
/// цена — «Вы приняли встречную цену · …»; договорились — способ оплаты и «Принято продавцом»; договорённость
/// использована — бледное; иначе — способ оплаты и, если подкреплено, «Подкреплено · …». Кнопок «Подкрепить деньгами» и
/// «Отозвать предложение» нет: деньги — на сайте.
struct КарточкаПредложенияЧата: View {
    let предложение: ПредложениеВЧате
    let заменено: Bool
    let согласовано: Int
    let безГаранта: Bool

    private enum Вид {
        case погасло(String)
        case приняласьВстречная
        case принято
        case использовано
        case ждёт
    }

    private var вид: Вид {
        if предложение.отозвано || заменено {
            return .погасло(ListingChatText.т(предложение.отозвано ? "of_gone" : "of_replaced"))
        }
        if предложение.встречнаяПринята > 0 && согласовано == предложение.встречнаяПринята { return .приняласьВстречная }
        if согласовано > 0 { return .принято }
        if предложение.принято { return .использовано }
        return .ждёт
    }

    /// «Наличными», «В рассрочку · 12 мес», «В кредит · 24 мес».
    private var способ: String {
        let название: String
        switch предложение.способ {
        case "inst": название = ListingChatText.т("of_m_inst")
        case "cred": название = ListingChatText.т("of_m_cred")
        default: название = ListingChatText.т("of_m_cash")
        }
        let срок = (предложение.способ == "inst" || предложение.способ == "cred") && предложение.срок > 0
            ? " · \(предложение.срок) " + ListingChatText.т("of_mon") : ""
        return название + срок
    }

    var body: some View {
        switch вид {
        case .погасло(let строка):
            РамкаКарточкиЧата(справа: true, погасла: true) {
                ВерхКарточкиЧата(заголовок: ListingChatText.т("of_mine"), сумма: предложение.цена, зачёркнута: true)
                СтрокаКарточкиЧата(текст: строка)
            }
        case .приняласьВстречная:
            РамкаКарточкиЧата(справа: true, погасла: false) {
                ВерхКарточкиЧата(заголовок: ListingChatText.т("of_mine"), сумма: предложение.цена, зачёркнута: false)
                СтрокаКарточкиЧата(текст: ListingChatText.т("of_ctr_answered")
                    .replacingOccurrences(of: "{sum}", with: ListingCard.тенге(Double(предложение.встречнаяПринята))))
            }
        case .принято:
            РамкаКарточкиЧата(справа: true, погасла: false) {
                ВерхКарточкиЧата(заголовок: ListingChatText.т("of_mine"), сумма: предложение.цена, зачёркнута: false)
                СтрокаКарточкиЧата(текст: способ)
                ОтметкаКарточкиЧата(текст: ListingChatText.т("of_accepted"))
            }
        case .использовано:
            РамкаКарточкиЧата(справа: true, погасла: true) {
                ВерхКарточкиЧата(заголовок: ListingChatText.т("of_mine"), сумма: предложение.цена, зачёркнута: true)
                СтрокаКарточкиЧата(текст: ListingChatText.т("of_used"))
            }
        case .ждёт:
            РамкаКарточкиЧата(справа: true, погасла: false) {
                ВерхКарточкиЧата(заголовок: ListingChatText.т("of_mine"), сумма: предложение.цена, зачёркнута: false)
                СтрокаКарточкиЧата(текст: способ)
                if !безГаранта && предложение.подкреплено > 0 {
                    ОтметкаКарточкиЧата(текст: ListingChatText.т("of_held") + " · "
                        + ListingCard.тенге(Double(предложение.подкреплено)))
                }
            }
        }
    }
}

/// Встречная цена продавца (mkCounterCard) — слева: сумма и «+5% к вашим …». Заменена, отклонена или неактуальна — бледная
/// с пояснением; принята — «Цена согласована». Ждёт ответа — «Ответить на сайте»: «Принять» и «Отказаться» меняют сделку и
/// остаются на сайте (объявление с открытым чатом).
struct КарточкаВстречнойЦены: View {
    let встречная: ВстречнаяВЧате
    let заменено: Bool
    let ответитьНаСайте: () -> Void

    private var пояснение: String? {
        guard встречная.база > 0 else { return nil }
        return ListingChatText.т("of_ctr_plus")
            .replacingOccurrences(of: "{step}", with: String(встречная.шаг))
            .replacingOccurrences(of: "{sum}", with: ListingCard.тенге(Double(встречная.база)))
    }

    /// Бледная карточка с причиной или nil — карточка живая.
    private var погасла: String? {
        if заменено { return ListingChatText.т("of_replaced") }
        if встречная.принята { return nil }
        if встречная.отклонена { return ListingChatText.т("of_ctr_refused") }
        if встречная.устарела { return ListingChatText.т("of_ctr_gone") }
        return nil
    }

    var body: some View {
        РамкаКарточкиЧата(справа: false, погасла: погасла != nil) {
            ВерхКарточкиЧата(заголовок: ListingChatText.т("of_ctr_seller"), сумма: встречная.цена,
                             зачёркнута: погасла != nil)
            if let строкаПояснения = пояснение {
                СтрокаКарточкиЧата(текст: строкаПояснения)
            }
            if let причина = погасла {
                СтрокаКарточкиЧата(текст: причина)
            } else if встречная.принята {
                ОтметкаКарточкиЧата(текст: ListingChatText.т("of_ctr_took"))
            } else {
                Button(action: ответитьНаСайте) {
                    Text(ChatText.т("reply_site"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                                .strokeBorder(Theme.линия, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                .accessibilityHint(ListingPageText.т("on_site"))
                .padding(.top, 10)
            }
        }
    }
}

// MARK: - Гео (.mk-geo)

/// Точка на карте: «Вы отправили геолокацию» / «Геолокация — точка доставки» и три ссылки сайта — маршрут Яндекса, 2ГИС и
/// «На карте» (2ГИС). Открываются вне приложения, как target="_blank" у сайта.
struct КарточкаГеоЧата: View {
    let моё: Bool
    let широта: Double
    let долгота: Double
    let изTelegram: Bool
    @Environment(\.openURL) private var открытьСсылку

    /// Этап 45: явный init — карточку берёт и лид-чат кабинета (LeadChatView.swift), а скрытое окружение делает
    /// встроенный init видимым только внутри этого файла.
    init(моё: Bool, широта: Double, долгота: Double, изTelegram: Bool) {
        self.моё = моё
        self.широта = широта
        self.долгота = долгота
        self.изTelegram = изTelegram
    }

    private var ссылки: [(String, URL?)] {
        let ш = String(широта)
        let д = String(долгота)
        return [
            (ListingChatText.т("call_yandex"),
             URL(string: "https://3.redirect.appmetrica.yandex.com/route?end-lat=" + ш + "&end-lon=" + д
                 + "&appmetrica_tracking_id=25395763362139037&lang=ru&ref=klikokz")),
            (ListingChatText.т("gis"), URL(string: "https://2gis.kz/directions/points/%7C" + д + "%2C" + ш)),
            (ListingChatText.т("on_map"), URL(string: "https://2gis.kz/geo/" + д + "%2C" + ш))
        ]
    }

    var body: some View {
        HStack(spacing: 0) {
            if моё { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 8) {
                if изTelegram { ПлашкаТелеграмаЧата(моё: false) }
                Label(ListingChatText.т(моё ? "geo_me" : "geo_seller"), systemImage: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
                ПереносСтрок(промежуток: 6, междуСтрок: 6) {
                    ForEach(Array(ссылки.enumerated()), id: \.offset) { номер, ссылка in
                        кнопка(ссылка.0, адрес: ссылка.1, первая: номер == 0)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
            if !моё { Spacer(minLength: 40) }
        }
    }

    private func кнопка(_ подпись: String, адрес: URL?, первая: Bool) -> some View {
        Button {
            if let адрес { открытьСсылку(адрес) }
        } label: {
            Text(подпись)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(первая ? Color.white : Theme.текст)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(первая ? Theme.зелёный : Theme.поверхность2,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .overlay {
                    if !первая {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        .disabled(адрес == nil)
    }
}

// MARK: - Окно входа (.mk-chat-gate)

/// Мятная карточка по центру: слова сайта зелёным и кнопка «Войти / Регистрация» или «Пройти верификацию» (страница
/// кабинета сайта). Лимит ассистента — только текст.
struct БарьерЧата: View {
    let барьер: МодельЧатаОбъявления.Барьер
    let войти: () -> Void

    private var текст: String {
        switch барьер {
        case .вход(let т), .верификация(let т), .лимит(let т): return т
        }
    }

    private var кнопка: String? {
        switch барьер {
        case .вход: return ListingChatText.т("gate_login")
        case .верификация: return ListingChatText.т("gate_verify_btn")
        case .лимит: return nil
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(текст)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(Theme.акцент)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let надпись = кнопка {
                Button(action: войти) {
                    Text(надпись)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 24)
                        .frame(minHeight: 46)
                        .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                .accessibilityHint(ListingPageText.т("on_site"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.зелёный2.opacity(0.3), lineWidth: 1)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }
}

// MARK: - Низ: позвать продавца, блокировка

/// «Позвать продавца» (.mk-chat-callbar): на всю ширину, рамка --mk-line 1,5 на --mk-surf2, значок человека с плюсом.
struct КнопкаПозватьПродавца: View {
    let нажать: () -> Void

    var body: some View {
        Button(action: нажать) {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                Text(ListingChatText.т("call_seller"))
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(Theme.текст)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }
}

/// Вместо строки ввода при блокировке (.mk-chat-block): розовая полоса с линией сверху, текст по центру тёмно-красным и
/// кнопка рамкой. Краски — оттенки скидки Theme: в тёмной теме полоса тёмная, текст светлее.
struct ПолосаБлокировкиЧата: View {
    let заблокировалЯ: Bool
    /// Подпись кнопки или nil — кнопки нет.
    let кнопка: String?
    let ждём: Bool
    let действие: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(ListingChatText.т(заблокировалЯ ? "you_blocked" : "seller_blocked"))
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Theme.скидкаТекст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            if let надпись = кнопка {
                Button(action: действие) {
                    ZStack {
                        Text(надпись)
                            .font(.system(size: 15, weight: .bold))
                            .opacity(ждём ? 0 : 1)
                        if ждём {
                            ProgressView()
                                .tint(Theme.текст)
                        }
                    }
                    .foregroundStyle(Theme.текст)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1.5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                .disabled(ждём)
                .accessibilityLabel(надпись)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity)
        .background(Theme.скидкаФон)
        .overlay(alignment: .top) {
            Theme.скидкаТекст
                .opacity(0.25)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Лиды в списке диалогов

/// Карточка «Покупатели» наверху «Сообщений» (этап 38): непрочитанные чаты по моим объявлениям (chat.php?action=leads)
/// входят в число на вкладке, как у нижней панели сайта; сами чаты продавца — в кабинете на сайте. Вид — строка диалога
/// этапа 30: зелёный квадрат, имя, «Открыть на сайте» акцентом и красный счётчик.
struct КарточкаЛидовЧата: View {
    let непрочитано: Int
    let открыть: () -> Void

    var body: some View {
        Button(action: открыть) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.зелёный2, Theme.зелёныйЯркий], startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .overlay {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ListingChatText.т("buyers"))
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    Text(ChatText.т("open_site"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.акцент)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if непрочитано > 0 {
                    Text(непрочитано > 99 ? "99+" : String(непрочитано))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Theme.непрочитано, in: Capsule())
                        .accessibilityLabel(String(format: AccessText.т("unread"), непрочитано))
                }
            }
            .padding(12)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .теньКарточкиСайта()
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .accessibilityHint(ListingPageText.т("on_site"))
    }
}

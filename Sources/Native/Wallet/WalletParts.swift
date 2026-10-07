import SwiftUI

/**
 КОШЕЛЁК — ЧАСТИ ЭКРАНА, ЭТАП 47 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Всё — по разметке и коду сайта: карточка «Кошелёк» шапки кабинета (.hero-wallet: подпись, баланс, строка под ним,
 кнопки «Пополнить | Вывести» в белой плашке), строка истории (#tx-list: значок, подпись типа, дата, заметка, сумма
 зелёным «+» или «−»; строки гаранта подсвечены и ведут в сделку и чек), «Заморожено сейчас» (.frz-card), баннер
 «Выплата … готова» (.wd-payout), карточки «На удержании» и «Пополнение с карты» (.wdh) и окно итога (.tpm / .wdr).
 Значки сайта — SVG; здесь — ближайшие системные символы.
 */

/// Что сделать, открыв экран кошелька из карточки вкладки «Кабинет».
enum ДействиеКошелька: String, Hashable {
    case показать
    case пополнить
    case вывести
}

/**
 ПОПОЛНЕНИЕ В ПРИЛОЖЕНИИ — ТОЛЬКО НА СДЕЛКИ (App Review 3.1.1). Деньги с карты в кошелёк — это оплата сделок за товары
 и услуги продавцов, пока работает Безопасная сделка. Гарант на паузе — пополненное тратилось бы только на цифровые услуги
 Kliko мимо In-App Purchase; поэтому «Пополнить» открывает пополнение, только когда гарант работает ПО СВЕРКЕ
 (ПаузаГаранта.работаетПоСверке: страницу кабинета читали и паузы на ней нет). На паузе или пока состояние неизвестно
 (свежая установка, страница не прочиталась) — окно «Пополнение откроется, когда заработает Безопасная сделка», без
 ссылок на сайт. ПополнениеМодель.пополнить перед оплатой ещё раз сверяет паузу сама.
 */
enum ПополнениеВПриложении {
    static var открыто: Bool { ПаузаГаранта.работаетПоСверке }
}

// MARK: - Карточка «Кошелёк» (.hero-wallet)

struct КарточкаКошелька: View {
    @ObservedObject var кошелёк: КошелёкМодель
    let пополнить: () -> Void
    let вывести: () -> Void

    init(кошелёк: КошелёкМодель, пополнить: @escaping () -> Void, вывести: @escaping () -> Void) {
        self.кошелёк = кошелёк
        self.пополнить = пополнить
        self.вывести = вывести
    }

    @Environment(\.colorScheme) private var схема
    /// «Пополнение откроется, когда заработает Безопасная сделка» (ПополнениеВПриложении).
    @State private var пополнениеЗакрыто = false

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    /* .hero: 135deg --g 0% → --g 52% → --g2 100%; в тёмной теме сверху слой rgba(6,10,14,.42 → .52). */
    private var градиент: LinearGradient {
        LinearGradient(stops: [.init(color: Theme.зелёный, location: 0), .init(color: Theme.зелёный, location: 0.52),
                               .init(color: Theme.зелёный2, location: 1)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private static let тьма = Color(red: 6 / 255, green: 10 / 255, blue: 14 / 255)

    var body: some View {
        /* Владелец 29.09.2026 («сверху резка»): подпись с глазом, баланс, строка под ним, внизу — пилюля
        «Пополнить | Вывести» во всю ширину карточки. */
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 13))
                        .accessibilityHidden(true)
                    Text(т("title").uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.44)
                }
                .foregroundStyle(Color.white.opacity(0.72))
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                Button {
                    кошелёк.переключитьСкрытие()
                } label: {
                    Image(systemName: кошелёк.скрыто ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 30)
                        .background(Theme.шапкаКнопка, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(т(кошелёк.скрыто ? "a11y_show" : "a11y_hide"))
            }
            баланс
                .padding(.top, 10)
            Text(строкаПод)
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            кнопки
                .padding(.top, 16)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                градиент
                if схема == .dark {
                    LinearGradient(colors: [Self.тьма.opacity(0.42), Self.тьма.opacity(0.52)], startPoint: .top,
                                   endPoint: .bottom)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .теньКарточкиСайта(радиус: Theme.Радиус.md)
        /* Пауза гаранта — не чаще раза в 10 минут: к нажатию «Пополнить» состояние уже известно. */
        .task { await ПаузаГаранта.shared.сверить() }
        .alert(т("topup_wait"), isPresented: $пополнениеЗакрыто) {
            Button(т("ok"), role: .cancel) {}
        }
    }

    /// «Пополнить»: гарант работает по сверке — дальше (лист пополнения или кабинет сайта); на паузе или не сверен —
    /// окно «Пополнение откроется, когда заработает Безопасная сделка» и ещё одна сверка паузы.
    private func нажатоПополнить() {
        guard ПополнениеВПриложении.открыто else {
            пополнениеЗакрыто = true
            Task { await ПаузаГаранта.shared.сверить() }
            return
        }
        пополнить()
    }

    @ViewBuilder
    private var баланс: some View {
        if let с = кошелёк.сведения {
            Text(кошелёк.показ(с.баланс))
                .font(.system(size: 26, weight: .heavy))
                .tracking(-0.52)
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .monospacedDigit()
                .accessibilityLabel(кошелёк.скрыто ? т("a11y_hidden") : КошелёкФормат.тенге(с.баланс))
        } else {
            Text("…")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(Color.white)
                .accessibilityLabel(т("loading"))
        }
    }

    /// #top-info-line: части через « · », нет частей — cab_wallet_sub.
    private var строкаПод: String {
        guard let с = кошелёк.сведения else { return "…" }
        var части: [String] = []
        if с.доступно < с.баланс {
            части.append(КошелёкText.т("out_can", n: КошелёкФормат.деньги(с.доступно)))
        }
        if с.удержано > 0 {
            let первое = с.удержания.first?.секунд ?? 0
            части.append(КошелёкText.т("held_line", ["n": КошелёкФормат.деньги(с.удержано),
                                                     "t": КошелёкФормат.освободится(первое)]))
        }
        if с.пополнениеКартой > 0 {
            части.append(КошелёкText.т("lock_line", n: КошелёкФормат.деньги(с.пополнениеКартой)))
        }
        /* 3.1.1: строка не зовёт платить кошельком за продвижение и слоты (sub_app) — их в приложении не продают. */
        return части.isEmpty ? т("sub_app") : части.joined(separator: " · ")
    }

    /// .hero-wpay: белая плашка радиуса 10 с тенью, «Пополнить» | «Вывести» (второй — с оттенком).
    private var кнопки: some View {
        HStack(spacing: 0) {
            кнопка(т("topup"), значок: "plus", оттенок: false,
                   наСайт: !Config.деньгиКошелька && ПополнениеВПриложении.открыто, действие: { нажатоПополнить() })
            Rectangle()
                .fill(Color(red: 52 / 255, green: 201 / 255, blue: 151 / 255).opacity(0.22))
                .frame(width: 1)
                .padding(.vertical, 8)
                .accessibilityHidden(true)
            кнопка(т("withdraw"), значок: "arrow.up.right", оттенок: true, наСайт: !Config.деньгиКошелька,
                   действие: вывести)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .shadow(color: Color.black.opacity(0.25), radius: 7, x: 0, y: 5)
    }

    /// наСайт — нажатие откроет кабинет сайта (стрелка «наружу» и подсказка VoiceOver).
    private func кнопка(_ подпись: String, значок: String, оттенок: Bool, наСайт: Bool,
                        действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
                Text(подпись)
                    .font(.system(size: 12, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if наСайт {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(КраскаСделокКабинета.акцент)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(оттенок ? Color(red: 15 / 255, green: 81 / 255, blue: 50 / 255).opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityHint(наСайт ? т("a11y_site") : "")
    }
}

// MARK: - Строка истории (#tx-list .tx-row)

struct СтрокаОперации: View {
    let операция: ОперацияКошелька
    let чекГрузится: Bool
    let сделка: (String) -> Void
    let чек: (String) -> Void

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    private var зачисление: Bool { операция.сумма > 0 }

    /// (a?"+":"−") + Math.abs(n).toLocaleString("ru-RU") + " ₸".
    private var сумма: String {
        let модуль = тенгеБезПереполнения(abs(операция.сумма))
        return (зачисление ? "+" : "−") + КошелёкФормат.тенге(модуль)
    }

    var body: some View {
        /* .tx-row: по центру, зазор 10, поля 10/0; значок 34 в круге (.in — --tint-ok, .out — --tint-bad). */
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: СтрокаОперации.значок(операция.тип))
                .font(.system(size: 16))
                .foregroundStyle(Theme.текст)
                .frame(width: 34, height: 34)
                .background(зачисление ? КраскаСделокКабинета.хорошоФон : КраскаСделокКабинета.плохоФон, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(СтрокаОперации.подпись(операция.тип))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                /* Заметка сайта идёт до даты. */
                if !операция.заметка.isEmpty {
                    Text(операция.заметка)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                let когда = СделкиФормат.сВременем(операция.когда)
                if !когда.isEmpty {
                    Text(когда)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.текстВторой)
                }
                ссылки
            }
            Spacer(minLength: 6)
            Text(сумма)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(зачисление ? КраскаСделокКабинета.хорошоТекст : КраскаСделокКабинета.плохоТекст)
                .monospacedDigit()
                .accessibilityLabel(т(зачисление ? "a11y_in" : "a11y_out") + " " + КошелёкФормат.тенге(тенгеБезПереполнения(abs(операция.сумма))))
        }
        .padding(.vertical, 10)
        .padding(.leading, операция.гарант ? 3 : 0)
        .background {
            /* Строка гаранта: --tint-ok и полоса 3px --acc-on слева, углы прямые. */
            if операция.гарант {
                HStack(spacing: 0) {
                    КраскаСделокКабинета.акцент.frame(width: 3)
                    КраскаСделокКабинета.хорошоФон
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// «сделка» — у escrow_* с deal_id; «чек» — у escrow_release и escrow_hold.
    @ViewBuilder
    private var ссылки: some View {
        if операция.гарант && !операция.сделка.isEmpty {
            HStack(spacing: 12) {
                Button {
                    сделка(операция.сделка)
                } label: {
                    Label(т("tx_deal"), systemImage: "arrow.right.circle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(КраскаСделокКабинета.инфоТекст)
                }
                .buttonStyle(.borderless)
                if операция.естьЧек {
                    Button {
                        чек(операция.сделка)
                    } label: {
                        HStack(spacing: 4) {
                            if чекГрузится {
                                SiteSpinner.крошечный
                            } else {
                                Image(systemName: "doc.text")
                                    .accessibilityHidden(true)
                            }
                            Text(т("tx_receipt"))
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(КраскаСделокКабинета.акцент)
                    }
                    .buttonStyle(.borderless)
                    .disabled(чекГрузится)
                    .accessibilityLabel(чекГрузится ? т("rc_loading") : т("tx_receipt"))
                }
            }
            .padding(.top, 2)
        }
    }

    /// Подписи типов (объект e loadWalletInfo); неизвестный — «Операция».
    static func подпись(_ тип: String) -> String {
        let ключ = "tx_" + тип
        let текст = КошелёкText.т(ключ)
        return (тип.isEmpty || текст == ключ) ? КошелёкText.т("tx_generic") : текст
    }

    static func значок(_ тип: String) -> String {
        let значки: [String: String] = [
            "topup": "plus.circle", "admin_topup": "person.badge.plus", "top": "flame", "discount": "tag",
            "escrow_hold": "lock", "escrow_release": "checkmark.shield", "escrow_refund": "arrow.uturn.backward",
            "topup_refund": "creditcard", "topup_refund_back": "arrow.uturn.left.circle", "escrow_cancel": "xmark.circle",
            "withdraw": "arrow.up.right", "escrow_new": "doc.badge.plus", "escrow_delivered": "shippingbox",
            "escrow_payout": "banknote", "sale": "cart", "earn": "chart.line.uptrend.xyaxis", "ai_scan": "sparkles",
            "ai_scan_refund": "sparkles", "buy_ai": "sparkles", "admin_deduct": "minus.circle",
            "promote": "arrow.up.circle", "promote_bulk": "arrow.up.circle", "promote_bulk_refund": "arrow.uturn.backward",
            "jobs_top": "briefcase", "slots": "square.grid.2x2", "combo": "gift", "pro": "crown", "buy_storefront": "bag",
            "escrow_advance": "banknote", "eds_fee": "signature", "eds_fee_back": "arrow.uturn.backward",
            "eds_ship": "car", "eds_ship_back": "arrow.uturn.backward"
        ]
        return значки[тип] ?? "circle.dashed"
    }
}

// MARK: - «Заморожено сейчас» (.frz-card)

struct БлокЗаморожено: View {
    let заморожено: ЗамороженоКошелька
    let занято: Set<String>
    /// Кнопки строки: «Сделка», «Вернуть деньги» (сделка / предложение), «Спор».
    let сделка: (String) -> Void
    let вернутьСделку: (String) -> Void
    let вернутьПредложение: (String) -> Void
    let спор: (String) -> Void

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    var body: some View {
        /* .frz-card: --card, рамка 1px --line, радиус 18, поля 16/14/12. */
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.system(size: 14))
                    .foregroundStyle(КраскаСделокКабинета.предупреждениеТекст)
                    .accessibilityHidden(true)
                Text(т("frz_title"))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 6)
                Text(КошелёкФормат.тенге(заморожено.всего))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(КраскаСделокКабинета.предупреждениеТекст)
                    .monospacedDigit()
            }
            .padding(.bottom, 4)
            Text(т("frz_sub"))
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
            ForEach(заморожено.строки) { строка in
                /* .frz-row: черта 1px --line сверху у каждой строки, и у первой тоже. */
                Rectangle()
                    .fill(Theme.линия)
                    .frame(height: 1)
                    .accessibilityHidden(true)
                self.строка(строка)
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private func строка(_ е: ЗамороженоСтрока) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: е.сделка ? "lock" : "tag")
                .font(.system(size: 16))
                .foregroundStyle(КраскаСделокКабинета.предупреждениеТекст)
                .frame(width: 34, height: 34)
                .background(КраскаСделокКабинета.предупреждениеФон,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityHidden(true)
            /* Кнопки и «почему нельзя» — внутри колонки текста (.frz-btns), не под значком. */
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(е.название.isEmpty ? т("no_title") : е.название)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    Text(КошелёкФормат.тенге(е.сумма))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .monospacedDigit()
                        .fixedSize()
                }
                Text(е.сделка ? т("frz_in_deal") + " · " + е.номер : т("frz_in_offer"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                кнопки(е)
                    .padding(.top, 6)
                /* .frz-lock: сделку нельзя отменить — почему (незнакомая причина — как «stage»). */
                if е.сделка && !е.можноОтменить {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .accessibilityHidden(true)
                        Text(причина(е.почему))
                            .font(.system(size: 12))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(КраскаСделокКабинета.инфоТекст)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(КраскаСделокКабинета.инфоФон,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                            .strokeBorder(КраскаСделокКабинета.инфоКромка, lineWidth: 1)
                    }
                    .padding(.top, 6)
                }
            }
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func кнопки(_ е: ЗамороженоСтрока) -> some View {
        HStack(spacing: 6) {
            if е.сделка {
                маленькая(т("frz_open"), опасная: false, наСайт: false, занята: false) { сделка(е.номер) }
                if е.можноОтменить {
                    маленькая(т("frz_cancel_deal"), опасная: true, наСайт: !Config.деньгиСделок, занята: false) {
                        вернутьСделку(е.номер)
                    }
                } else if е.почему == "after_ship" || е.почему == "meet_lock" {
                    маленькая(т("frz_dispute"), опасная: true, наСайт: false, занята: false) { спор(е.номер) }
                }
            } else {
                маленькая(т("frz_unfund"), опасная: true, наСайт: !Config.деньгиСделок, занята: занято.contains(е.номер)) {
                    вернутьПредложение(е.номер)
                }
            }
        }
    }

    private func маленькая(_ подпись: String, опасная: Bool, наСайт: Bool, занята: Bool,
                           действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                if занята { SiteSpinner.крошечный }
                Text(подпись)
                    .font(.system(size: 12, weight: .bold))
                if наСайт {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                        .accessibilityHidden(true)
                }
            }
            /* .frz-btn: --surf2, рамка 1.5 --line, радиус 10, 12/700; .stop — --on-bad и --edge-bad. */
            .foregroundStyle(опасная ? КраскаСделокКабинета.плохоТекст : Theme.текст)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(опасная ? КраскаСделокКабинета.плохоКромка : Theme.линия, lineWidth: 1.5)
            }
        }
        .buttonStyle(.borderless)
        .disabled(занята)
        .accessibilityHint(наСайт ? т("a11y_site") : "")
    }

    private func причина(_ почему: String) -> String {
        switch почему {
        case "after_ship": return т("frz_why_ship")
        case "meet_lock": return т("frz_why_meet")
        case "denied": return т("frz_why_denied")
        default: return т("frz_why_stage")
        }
    }
}

// MARK: - «Выплата … готова» (.wd-payout)

struct БаннерВыплаты: View {
    let выплата: ГотоваяВыплата
    let открываем: Bool
    let указать: () -> Void
    /// Под карточкой кошелька во вкладке «Кабинет» (#payout-ready-hero): белая, кнопка — во всю ширину снизу.
    var подШапкой = false

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    private var подпись: String {
        let срок = КошелёкФормат.срокВыплаты(выплата.до)
        let до = срок.isEmpty ? "" : КошелёкText.т("po_until", ["d": срок])
        return КошелёкText.т("po_sub", ["d": до])
    }

    var body: some View {
        /* .wd-safe.wd-payout: зазор 12, поля 12/16, радиус 14, рамка 1.5 --edge-ok на --tint-ok. */
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "creditcard")
                    .font(.system(size: 18))
                    .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                    .frame(width: 36, height: 36)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(КошелёкText.т("po_ready", n: КошелёкФормат.деньги(выплата.сумма)))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(подпись)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !подШапкой {
                    Spacer(minLength: 6)
                    кнопка
                }
            }
            if подШапкой {
                кнопка
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(подШапкой ? Theme.поверхность : КраскаСделокКабинета.хорошоФон,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(подШапкой ? Theme.линия : КраскаСделокКабинета.хорошоКромка, lineWidth: 1.5)
        }
    }

    /// .wd-payout-btn: поля 10/16, радиус 10, фон --on-ok, текст --card, 13/700.
    private var кнопка: some View {
        Button(action: указать) {
            HStack(spacing: 4) {
                Text(т(открываем ? "po_opening" : "po_go"))
                    .font(.system(size: 13, weight: .bold))
                if !Config.деньгиКошелька {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Theme.поверхность)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: подШапкой ? .infinity : nil)
            .background(КраскаСделокКабинета.хорошоТекст,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
        .buttonStyle(.borderless)
        .disabled(открываем)
        .accessibilityHint(Config.деньгиКошелька ? "" : т("a11y_site"))
    }
}

// MARK: - «На удержании» и «Пополнение с карты» (.wdh: wdHeldCard, wdTopupLockCard)

struct КарточкаУдержания: View {
    let сумма: Int
    let удержания: [УдержаниеКошелька]

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ШапкаКарточкиУдержания(символ: "lock", заголовок: т("held"), сумма: сумма)
                .padding(.bottom, 8)
            ForEach(Array(удержания.enumerated()), id: \.offset) { пара in
                строка(пара.element)
            }
            Text(т("held_note"))
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .modifier(ФонКарточкиУдержания())
    }

    /// .wdh-row: черта --edge-rent сверху, поля 8/0. «освободится через N» сайт прячет до 420px (.wdh-when) — срок первого
    /// удержания и так в строке под балансом.
    private func строка(_ у: УдержаниеКошелька) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(КраскаСделокКабинета.арендаКромка)
                .frame(height: 1)
                .accessibilityHidden(true)
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .font(.system(size: 16))
                    .foregroundStyle(КраскаСделокКабинета.арендаТекст.opacity(0.75))
                    .accessibilityHidden(true)
                Text(у.почему.isEmpty ? т("held_why") : у.почему)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(КошелёкФормат.тенге(у.сумма))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текст)
                    .monospacedDigit()
                    .fixedSize()
            }
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Шапка .wdh: значок 30×30 на --card радиуса 10, заголовок 13/800 и сумма 15/900 в --on-rent.
private struct ШапкаКарточкиУдержания: View {
    let символ: String
    let заголовок: String
    let сумма: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: символ)
                .font(.system(size: 15))
                .frame(width: 30, height: 30)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            Text(заголовок)
                .font(.system(size: 13, weight: .heavy))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Text(КошелёкФормат.тенге(сумма))
                .font(.system(size: 15, weight: .black))
                .monospacedDigit()
                .fixedSize()
        }
        .foregroundStyle(КраскаСделокКабинета.арендаТекст)
        .accessibilityElement(children: .combine)
    }
}

/// Фон .wdh: --tint-rent, рамка 1.5 --edge-rent, радиус 18, поля 14.
private struct ФонКарточкиУдержания: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(КраскаСделокКабинета.арендаФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .strokeBorder(КраскаСделокКабинета.арендаКромка, lineWidth: 1.5)
            }
    }
}

struct КарточкаПополненияКартой: View {
    let сумма: Int
    let поддержка: () -> Void

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ШапкаКарточкиУдержания(символ: "creditcard", заголовок: т("lock_t"), сумма: сумма)
            Text(т("lock_note"))
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
            Button(т("lock_sup"), action: поддержка)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(КраскаСделокКабинета.арендаТекст)
                .buttonStyle(.borderless)
        }
        .modifier(ФонКарточкиУдержания())
    }
}

// MARK: - Окно итога (.tpm сайта: tpmOpen; .wdr: wdResultModal, wdOutcomeModal)

/**
 Два вида окна, как у сайта. .wdr (вывод и итог выплаты, снизу: true) — лист снизу: верх радиуса 20, значок 60×60 радиуса 20,
 заголовок 19/800, серый подзаголовок, сумма 30/900, строки в рамке 1.5 радиуса 14, кнопка 15/700 радиуса 14.
 .tpm (пополнение) — карточка по центру радиуса 24: круг 104 со свечением, заголовок 21/800, сумма 30/900 в --g2,
 баланс строкой 14/700.
 */
struct ОкноИтогаКошелька: View {
    enum Вид { case хорошо, плохо, ждём }

    struct Кнопка {
        let подпись: String
        let главная: Bool
        let действие: () -> Void
    }

    let вид: Вид
    let заголовок: String
    var сумма: String? = nil
    var строки: [(String, String)] = []
    var текст: String? = nil
    var кнопки: [Кнопка] = []
    /// .wdr-s: серая строка под заголовком (13, межстрочный 1.5).
    var подзаголовок: String? = nil
    /// .wdr: лист снизу; иначе — .tpm по центру.
    var снизу = false

    var body: some View {
        ZStack(alignment: снизу ? .bottom : .center) {
            (снизу ? Color(red: 15 / 255, green: 23 / 255, blue: 42 / 255) : Color(red: 8 / 255, green: 16 / 255, blue: 12 / 255))
                .opacity(0.55)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            if снизу { листСнизу } else { карточкаПоЦентру }
        }
    }

    // MARK: .wdr

    private var листСнизу: some View {
        VStack(spacing: 0) {
            значокЛиста
                .padding(.bottom, 14)
            Text(заголовок)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            if let подзаголовок {
                Text(подзаголовок)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 16)
            } else {
                Color.clear.frame(height: 10)
            }
            if let сумма {
                Text(сумма)
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(вид == .плохо ? Theme.текст : КраскаСделокКабинета.хорошоТекст)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, 14)
            }
            if !строки.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(строки.enumerated()), id: \.offset) { пара in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(пара.element.0)
                                .foregroundStyle(Theme.текстВторой)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(пара.element.1)
                                .fontWeight(.bold)
                                .foregroundStyle(Theme.текст)
                                .monospacedDigit()
                                .fixedSize()
                        }
                        .font(.system(size: 14))
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                }
                .padding(.bottom, 14)
            }
            if let текст {
                Text(текст)
                    .font(.system(size: 13))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 14)
            }
            VStack(spacing: 8) {
                ForEach(Array(кнопки.enumerated()), id: \.offset) { пара in
                    кнопка(пара.element)
                }
            }
        }
        .padding(.top, 24)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: 420)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: Theme.Радиус.xl, bottomLeadingRadius: 0, bottomTrailingRadius: 0,
                                   topTrailingRadius: Theme.Радиус.xl, style: .continuous)
                .fill(Theme.поверхность)
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private var значокЛиста: some View {
        switch вид {
        case .ждём:
            SiteSpinner.крупный
                .frame(width: 60, height: 60)
        case .хорошо, .плохо:
            let плохо = вид == .плохо
            Image(systemName: плохо ? "xmark" : "checkmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(плохо ? КраскаСделокКабинета.плохоТекст : КраскаСделокКабинета.хорошоТекст)
                .frame(width: 60, height: 60)
                .background(плохо ? КраскаСделокКабинета.плохоФон : КраскаСделокКабинета.хорошоФон,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    /// .wdr-btn: градиент --g → --g2, радиус 14, поля 14, 15/700; .wdr-btn2: рамка 1.5 --line, серый 14/600.
    private func кнопка(_ к: Кнопка) -> some View {
        Button(action: к.действие) {
            Text(к.подпись)
                .font(.system(size: к.главная ? 15 : 14, weight: к.главная ? .bold : .semibold))
                .foregroundStyle(к.главная ? Color.white : Theme.текстВторой)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: к.главная ? 50 : 44)
                .background {
                    if к.главная {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .fill(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .shadow(color: КраскаСделокКабинета.теньКнопки, radius: 4, x: 0, y: 5)
                    } else {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1.5)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.985))
    }

    // MARK: .tpm

    private var карточкаПоЦентру: some View {
        VStack(spacing: 0) {
            значокКарточки
                .padding(.bottom, 14)
            Text(заголовок)
                .font(.system(size: 21, weight: .heavy))
                .tracking(-0.2)
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 4)
            if let сумма {
                Text(сумма)
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(Theme.зелёный2)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, 4)
            }
            ForEach(Array(строки.enumerated()), id: \.offset) { пара in
                Text(пара.element.0 + ": " + пара.element.1)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .monospacedDigit()
                    .padding(.bottom, 6)
            }
            if let текст {
                Text(текст)
                    .font(.system(size: 14))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
            }
            if !кнопки.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(кнопки.enumerated()), id: \.offset) { пара in
                        кнопкаКарточки(пара.element)
                    }
                }
                .padding(.top, 20)
            }
        }
        .padding(.top, 34)
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: 390)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.3), radius: 28, x: 0, y: 20)
        .padding(20)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// .tpm-ic: круг 104 с мягким свечением (--g2 или #e0563a), знак внутри.
    @ViewBuilder
    private var значокКарточки: some View {
        switch вид {
        case .ждём:
            SiteSpinner.крупный
                .frame(width: 104, height: 104)
        case .хорошо, .плохо:
            let краска = вид == .плохо ? Color(uiColor: Theme.hex(0xE0563A)) : Theme.зелёный2
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [краска.opacity(0.2), краска.opacity(0)], center: .center,
                                         startRadius: 0, endRadius: 52))
                Circle()
                    .strokeBorder(краска.opacity(0.18), lineWidth: 2)
                    .padding(8)
                Image(systemName: вид == .плохо ? "xmark.circle" : "checkmark.circle")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(краска)
            }
            .frame(width: 104, height: 104)
            .accessibilityHidden(true)
        }
    }

    /// .tpm-btn: радиус 14, поля 14, 15/800; .tpm-pri — градиент, .tpm-gh — --surf2.
    private func кнопкаКарточки(_ к: Кнопка) -> some View {
        Button(action: к.действие) {
            Text(к.подпись)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(к.главная ? Color.white : Theme.текст)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background {
                    if к.главная {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .fill(вид == .плохо
                                  ? LinearGradient(colors: [Color(uiColor: Theme.hex(0xE0563A)), Color(uiColor: Theme.hex(0xF0764F))],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                                  : LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                                   endPoint: .bottomTrailing))
                    } else {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .fill(Theme.поверхность2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.985))
    }
}

// MARK: - Лист страницы банка (оплата пополнения, карта выплаты)

/// Общий лист страницы банка (ЛистШлюза, MoneyGatewaySheet.swift): возврат ?topup= / ?payout=back ловит
/// ВозвратКошелька; «Закрыть», window.close() и уход на свой домен без итога — закрыть.
struct ОкноБанкаКошелька: View {
    let адрес: URL
    let вернулись: (ВозвратКошелька) -> Void
    let закрыть: () -> Void

    var body: some View {
        ЛистШлюза(адрес: адрес, заголовок: КошелёкText.т("gw_title"), подписьЗакрыть: КошелёкText.т("close"),
                  перехват: { url in
                      guard let итог = ВозвратКошелька.разобрать(url) else { return false }
                      DispatchQueue.main.async { вернулись(итог) }
                      return true
                  }, закрыть: закрыть)
    }
}

/// Плашка внизу (toast сайта).
struct ПлашкаКошелька: View {
    let текст: String

    var body: some View {
        Text(текст)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.82), in: Capsule())
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
    }
}

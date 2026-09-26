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

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Label(т("title").uppercased(), systemImage: "wallet.pass")
                    .font(.system(size: 12, weight: .semibold))
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
            Text(строкаПод)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
            кнопки
                .padding(.top, 6)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Theme.шапкаВерх, Theme.шапкаСередина, Theme.шапкаНиз], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        )
        .теньКарточкиСайта(радиус: Theme.Радиус.lg)
    }

    @ViewBuilder
    private var баланс: some View {
        if let с = кошелёк.сведения {
            Text(кошелёк.показ(с.баланс))
                .font(.system(size: 26, weight: .heavy))
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
        /* 3.1.1: без Config.цифровыеПокупки строка не зовёт платить кошельком за продвижение и слоты (sub_app). */
        let подпись = Config.цифровыеПокупки ? "sub" : "sub_app"
        return части.isEmpty ? т(подпись) : части.joined(separator: " · ")
    }

    /// .hero-wpay: белая плашка, «Пополнить» | «Вывести» (второй — с оттенком).
    private var кнопки: some View {
        HStack(spacing: 0) {
            кнопка(т("topup"), значок: "plus", оттенок: false, действие: пополнить)
            Rectangle()
                .fill(Theme.зелёный2.opacity(0.22))
                .frame(width: 1)
                .padding(.vertical, 8)
                .accessibilityHidden(true)
            кнопка(т("withdraw"), значок: "arrow.up.right", оттенок: true, действие: вывести)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
    }

    private func кнопка(_ подпись: String, значок: String, оттенок: Bool, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.system(size: 13, weight: .bold))
                    .accessibilityHidden(true)
                Text(подпись)
                    .font(.system(size: 14, weight: .heavy))
                if !Config.деньгиКошелька {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 11))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Theme.акцент)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(оттенок ? Theme.оттенокАкцента : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityHint(Config.деньгиКошелька ? "" : т("a11y_site"))
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: СтрокаОперации.значок(операция.тип))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(зачисление ? КраскаОбъявлений.хорошоТекст : Theme.текстВторой)
                .frame(width: 34, height: 34)
                .background(зачисление ? КраскаОбъявлений.хорошоФон : Theme.поверхность2,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(СтрокаОперации.подпись(операция.тип))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                let когда = СделкиФормат.сВременем(операция.когда)
                if !когда.isEmpty {
                    Text(когда)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
                if !операция.заметка.isEmpty {
                    Text(операция.заметка)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                ссылки
            }
            Spacer(minLength: 6)
            Text(сумма)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(зачисление ? КраскаОбъявлений.хорошоТекст : Theme.текст)
                .monospacedDigit()
                .accessibilityLabel(т(зачисление ? "a11y_in" : "a11y_out") + " " + КошелёкФормат.тенге(тенгеБезПереполнения(abs(операция.сумма))))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, операция.гарант ? 10 : 0)
        .background {
            if операция.гарант {
                HStack(spacing: 0) {
                    Theme.зелёныйЯркий.frame(width: 3)
                    КраскаОбъявлений.хорошоФон
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(КраскаОбъявлений.инфоТекст)
                }
                .buttonStyle(.borderless)
                if операция.естьЧек {
                    Button {
                        чек(операция.сделка)
                    } label: {
                        HStack(spacing: 4) {
                            if чекГрузится {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "doc.text")
                                    .accessibilityHidden(true)
                            }
                            Text(т("tx_receipt"))
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.акцент)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(КраскаОбъявлений.предупреждениеТекст)
                    .accessibilityHidden(true)
                Text(т("frz_title"))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 6)
                Text(КошелёкФормат.тенге(заморожено.всего))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .monospacedDigit()
            }
            Text(т("frz_sub"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(заморожено.строки) { строка in
                self.строка(строка)
                if строка.id != заморожено.строки.last?.id { Divider() }
            }
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(КраскаОбъявлений.предупреждениеКромка, lineWidth: 1.5)
        }
    }

    private func строка(_ е: ЗамороженоСтрока) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: е.сделка ? "lock" : "tag")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(КраскаОбъявлений.предупреждениеТекст)
                    .frame(width: 30, height: 30)
                    .background(КраскаОбъявлений.предупреждениеФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(е.название.isEmpty ? т("no_title") : е.название)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(2)
                    Text(е.сделка ? т("frz_in_deal") + " · " + е.номер : т("frz_in_offer"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 6)
                Text(КошелёкФормат.тенге(е.сумма))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .monospacedDigit()
            }
            кнопки(е)
            /* .frz-lock: сделку нельзя отменить — почему (незнакомая причина — как «stage»). */
            if е.сделка && !е.можноОтменить {
                Label(причина(е.почему), systemImage: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func кнопки(_ е: ЗамороженоСтрока) -> some View {
        HStack(spacing: 8) {
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
            HStack(spacing: 4) {
                if занята { ProgressView().controlSize(.mini) }
                Text(подпись)
                    .font(.system(size: 12, weight: .bold))
                if наСайт {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 10))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(опасная ? КраскаОбъявлений.плохоТекст : Theme.акцент)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(опасная ? КраскаОбъявлений.плохоФон : Theme.оттенокАкцента, in: Capsule())
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

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    private var подпись: String {
        let срок = КошелёкФормат.срокВыплаты(выплата.до)
        let до = срок.isEmpty ? "" : КошелёкText.т("po_until", ["d": срок])
        return КошелёкText.т("po_sub", ["d": до])
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20))
                .foregroundStyle(КраскаОбъявлений.хорошоТекст)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(КошелёкText.т("po_ready", n: КошелёкФормат.деньги(выплата.сумма)))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                Text(подпись)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Button(action: указать) {
                HStack(spacing: 4) {
                    Text(т(открываем ? "po_opening" : "po_go"))
                        .font(.system(size: 13, weight: .heavy))
                    if !Config.деньгиКошелька {
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10))
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Theme.зелёный2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(.borderless)
            .disabled(открываем)
            .accessibilityHint(Config.деньгиКошелька ? "" : т("a11y_site"))
        }
        .padding(12)
        .background(КраскаОбъявлений.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(КраскаОбъявлений.хорошоКромка, lineWidth: 1.5)
        }
    }
}

// MARK: - «На удержании» и «Пополнение с карты» (.wdh: wdHeldCard, wdTopupLockCard)

struct КарточкаУдержания: View {
    let сумма: Int
    let удержания: [УдержаниеКошелька]

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .foregroundStyle(КраскаОбъявлений.предупреждениеТекст)
                    .accessibilityHidden(true)
                Text(т("held"))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 6)
                Text(КошелёкФормат.тенге(сумма))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .monospacedDigit()
            }
            ForEach(Array(удержания.enumerated()), id: \.offset) { пара in
                строка(пара.element)
            }
            Text(т("held_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(КраскаОбъявлений.предупреждениеФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    private func строка(_ у: УдержаниеКошелька) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            Text(у.почему.isEmpty ? т("held_why") : у.почему)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текст)
            Text(т("held_left") + " " + КошелёкФормат.освободится(у.секунд))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 4)
            Text(КошелёкФормат.тенге(у.сумма))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.текст)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

struct КарточкаПополненияКартой: View {
    let сумма: Int
    let поддержка: () -> Void

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "creditcard")
                    .foregroundStyle(КраскаОбъявлений.предупреждениеТекст)
                    .accessibilityHidden(true)
                Text(т("lock_t"))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 6)
                Text(КошелёкФормат.тенге(сумма))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .monospacedDigit()
            }
            Text(т("lock_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            Button(т("lock_sup"), action: поддержка)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .buttonStyle(.borderless)
        }
        .padding(12)
        .background(КраскаОбъявлений.предупреждениеФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }
}

// MARK: - Окно итога (.tpm сайта: tpmOpen; .wdr: wdResultModal, wdOutcomeModal)

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

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                значок
                Text(заголовок)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let сумма {
                    Text(сумма)
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(вид == .плохо ? Theme.текст : КраскаОбъявлений.хорошоТекст)
                        .monospacedDigit()
                }
                if !строки.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(Array(строки.enumerated()), id: \.offset) { пара in
                            HStack {
                                Text(пара.element.0)
                                    .foregroundStyle(Theme.текстВторой)
                                Spacer(minLength: 8)
                                Text(пара.element.1)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Theme.текст)
                                    .monospacedDigit()
                            }
                            .font(.system(size: 14))
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(12)
                    .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                }
                if let текст {
                    Text(текст)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(кнопки.enumerated()), id: \.offset) { пара in
                    КнопкаСделки(пара.element.подпись, вид: пара.element.главная ? .главная : .вторая,
                                 действие: пара.element.действие)
                }
            }
            .padding(22)
            .frame(maxWidth: 380)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.xl, style: .continuous))
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    @ViewBuilder
    private var значок: some View {
        switch вид {
        case .ждём:
            ProgressView()
                .controlSize(.large)
                .frame(width: 56, height: 56)
        case .хорошо:
            Image(systemName: "checkmark")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(КраскаОбъявлений.хорошоТекст)
                .frame(width: 56, height: 56)
                .background(КраскаОбъявлений.хорошоФон, in: Circle())
                .accessibilityHidden(true)
        case .плохо:
            Image(systemName: "xmark")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(КраскаОбъявлений.плохоТекст)
                .frame(width: 56, height: 56)
                .background(КраскаОбъявлений.плохоФон, in: Circle())
                .accessibilityHidden(true)
        }
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

import SwiftUI

/**
 КНОПКИ ПРОДАВЦА В КАРТОЧКАХ АРЕНДЫ И ОБМЕНА — _dmCardRental / _dmCardExchange кабинета (.dm-cact).

 Видит только продавец (meta.seller_id == _dmMe()). Аренда: «Ожидает ответа» — «Подтвердить» и «Отклонить»
 (rentals.php action "respond", decision confirm / decline); «Подтверждено» — «Передал товар» (action "activate");
 «Активна» — «Принял возврат» (action "return"). Обмен «ожидает» — «Принять» и «Отклонить» (exchange.php action "respond",
 decision accept / decline). Сайт шлёт сразу; приложение сначала спрашивает листом по высоте содержимого.
 Деньги сделок (залог) двигает сервер по этим же вызовам; при выключенных деньгах сделок кнопки с залогом не показываем.
 */
enum ДействиеСделкиЧата: String, Identifiable {
    case подтвердить, отклонитьАренду, передал, принялВозврат, принять, отклонитьОбмен

    var id: String { rawValue }

    /// Кнопки карточки по статусу — как _dmCardRental / _dmCardExchange.
    static func для(_ сделка: СделкаВЧате) -> [ДействиеСделкиЧата] {
        guard !сделка.номер.isEmpty else { return [] }
        if сделка.аренда {
            let сЗалогом = сделка.залог > 0
            switch сделка.статус {
            case "requested":
                return [.подтвердить, .отклонитьАренду]
            case "confirmed":
                return сЗалогом && !Config.деньгиСделок ? [] : [.передал]
            case "active":
                return сЗалогом && !Config.деньгиСделок ? [] : [.принялВозврат]
            default:
                return []
            }
        }
        return сделка.статус == "pending" ? [.принять, .отклонитьОбмен] : []
    }

    /// Поля тела запроса: action и decision.
    var поля: [String: String] {
        switch self {
        case .подтвердить: return ["action": "respond", "decision": "confirm"]
        case .отклонитьАренду: return ["action": "respond", "decision": "decline"]
        case .передал: return ["action": "activate"]
        case .принялВозврат: return ["action": "return"]
        case .принять: return ["action": "respond", "decision": "accept"]
        case .отклонитьОбмен: return ["action": "respond", "decision": "decline"]
        }
    }

    /// .dm-b.pri — главная: всё, кроме «Отклонить».
    var главное: Bool {
        switch self {
        case .отклонитьАренду, .отклонитьОбмен: return false
        default: return true
        }
    }

    var отказ: Bool { !главное }

    /// ic("check") у сайта — только у «Подтвердить» и «Принять».
    var сГалочкой: Bool { self == .подтвердить || self == .принять }

    var кнопка: String {
        switch self {
        case .подтвердить: return ИнбоксText.т("dm_confirm")
        case .отклонитьАренду, .отклонитьОбмен: return ИнбоксText.т("dm_decline")
        case .передал: return ИнбоксText.т("dm_handed_item")
        case .принялВозврат: return ИнбоксText.т("dm_accepted_return")
        case .принять: return ИнбоксText.т("dm_accept")
        }
    }

    var вопрос: String {
        switch self {
        case .подтвердить: return ИнбоксText.т("dmq_confirm")
        case .отклонитьАренду: return ИнбоксText.т("dmq_decline")
        case .передал: return ИнбоксText.т("dmq_activate")
        case .принялВозврат: return ИнбоксText.т("dmq_return")
        case .принять: return ИнбоксText.т("dmq_accept")
        case .отклонитьОбмен: return ИнбоксText.т("dmq_xdecline")
        }
    }
}

/// Что спросить: сделка карточки и нажатая кнопка.
struct ВопросСделкиЧата: Identifiable {
    let сделка: СделкаВЧате
    let действие: ДействиеСделкиЧата

    var id: String { сделка.номер + "|" + действие.rawValue }
}

/// Лист подтверждения по высоте содержимого: вопрос, суть сделки, «Отмена» и кнопка действия.
struct ЛистДействияСделкиЧата: View {
    let вопрос: ВопросСделкиЧата
    let выполнить: () -> Void
    @Environment(\.dismiss) private var закрыть

    private func т(_ ключ: String) -> String { ИнбоксText.т(ключ) }

    /// Даты и сумма аренды или «что на что» у обмена.
    private var суть: String {
        let с = вопрос.сделка
        if с.аренда {
            let даты = с.начало + " – " + с.конец
            return с.всего > 0 ? даты + " · " + СделкиФормат.тенге(с.всего) : даты
        }
        let предлагают = с.предлагают.isEmpty ? т("dm_they_offer") : с.предлагают
        return с.заВаш.isEmpty ? предлагают : предлагают + " ⇄ " + с.заВаш
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(вопрос.действие.вопрос)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(ИнбоксКраска.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Text(суть)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ИнбоксКраска.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Text(т("dmq_note"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button {
                        закрыть()
                    } label: {
                        Text(т("cancel"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ИнбоксКраска.текст)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(ИнбоксКраска.подложка,
                                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button {
                        закрыть()
                        выполнить()
                    } label: {
                        Text(вопрос.действие.кнопка)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(вопрос.действие.отказ ? Color.white : ИнбоксКраска.наАкценте)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(вопрос.действие.отказ ? Color.red : ИнбоксКраска.акцент,
                                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
            .padding(20)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(ИнбоксКраска.карточка.ignoresSafeArea())
        .листПоВысоте()
    }
}

/// Ярлык select #dm-label: без метки — «Метка» серой кромкой, с меткой — плашка её цвета (_styleLabelSelect).
struct ЯрлыкМеткиПереписки: View {
    let метка: МеткаДиалога?

    var body: some View {
        HStack(spacing: 4) {
            Text(метка?.название ?? ИнбоксText.т("lbl_pick"))
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(метка?.цвет ?? Theme.текстВторой)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(метка?.фон ?? ИнбоксКраска.карточка,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                .strokeBorder(метка == nil ? ИнбоксКраска.линия : Color.clear, lineWidth: 1)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

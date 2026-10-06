import SwiftUI

/**
 «МОИ СДЕЛКИ» — БЛОК «СДЕЛКИ С ПОДПИСЬЮ eGov» (edsListInject сайта).

 После списка сделок гаранта сайт зовёт edsListInject(role): GET /eds.php?action=my&role=<seller|buyer> и, если сделки
 есть, ставит над ними блок «Сделки с подписью eGov» — строки с картинкой, названием, «номер · цена ₸ · вы продаёте /
 вы покупаете» и плашкой статуса (_edsSt). Нажатие — окно сделки (edsOpen), здесь — ЭкранСделкиEDS листом. Закрыли окно —
 список перечитывается (edsClose → loadDeals). Сделок нет или ответ не пришёл — блока нет, как у сайта.
 */
@MainActor
final class СписокСделокEDS: ObservableObject {
    static let shared = СписокСделокEDS()

    @Published private(set) var сделки: [КраткоEDS] = []
    /// Для какой вкладки список (сделки другой вкладки не показываем ни секунды).
    @Published private(set) var роль: РольСделок? = nil
    private var номер = 0

    private init() {}

    func загрузить(_ роль: РольСделок) async {
        номер += 1
        let мой = номер
        if self.роль != роль {
            сделки = []
            self.роль = роль
        }
        do {
            guard let j = try await EDSAPI.мои(роль.rawValue) else { return }
            guard мой == номер else { return }
            guard РазборEDS.да(j["ok"]) else {
                сделки = []
                return
            }
            let сырые: [Any] = (j["deals"] as? [Any]) ?? []
            let новые = сырые.compactMap { з -> КраткоEDS? in
                guard let d = з as? [String: Any] else { return nil }
                return КраткоEDS(d)
            }
            /* Сделка закрылась с прошлой загрузки — её объявление перечитывают экраны (DealListingBack.swift). */
            var прежние: [String: String] = [:]
            for с in сделки { прежние[с.id] = с.статус }
            for с in новые {
                ОбъявлениеПослеСделки.сверить(сделка: с.id, товар: с.товарИд, было: прежние[с.id], стало: с.статус)
            }
            сделки = новые
        } catch {
            /* Нет связи — прежний список этой вкладки остаётся. */
        }
    }

    /// Выход из аккаунта или другой вход — чужие сделки не показываем.
    func забыть() {
        номер += 1
        сделки = []
        роль = nil
    }
}

/// Открытая из списка сделка (лист «Моих сделок»).
struct ОткрытаяСделкаEDS: Identifiable, Equatable {
    let id: String
}

/// Блок над сделками гаранта; пусто — ничего (и без отступа в списке).
struct СекцияСделокEDS: View {
    let роль: РольСделок
    /// true — только закончившиеся (идут в конце списка), false — только незакрытые (сверху).
    let закрытые: Bool
    let открыть: (String) -> Void
    @ObservedObject private var список = СписокСделокEDS.shared

    init(роль: РольСделок, закрытые: Bool = false, открыть: @escaping (String) -> Void) {
        self.роль = роль
        self.закрытые = закрытые
        self.открыть = открыть
    }

    private var свои: [КраткоEDS] { список.сделки.filter { $0.закрыта == закрытые } }

    var body: some View {
        if список.роль == роль && !свои.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "signature")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(КраскаСделокКабинета.хорошоТекст)
                        .accessibilityHidden(true)
                    Text(EDSText.т("eds_list_h"))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                }
                .accessibilityAddTraits(.isHeader)
                ForEach(свои) { сделка in
                    Button {
                        открыть(сделка.id)
                    } label: {
                        СтрокаСделкиEDS(сделка: сделка)
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                }
            }
            .padding(.bottom, 4)
        }
    }
}

/// .eds-card: картинка 46, название, «номер · цена ₸ · роль», плашка статуса.
struct СтрокаСделкиEDS: View {
    let сделка: КраткоEDS

    var body: some View {
        let плашка = СтатусEDS.плашка(сделка.статус, способ: сделка.способ)
        /* Ровная схема (владелец 06.10.2026): название и статус — первой строкой (плашка по верху, в одну строку),
           под ними «номер · цена · роль» одной строкой с многоточием; миниатюра одна на всех. */
        HStack(alignment: .top, spacing: 12) {
            КартинкаЛенты(Config.url(сделка.фото), пунктов: 46) {
                ZStack {
                    Theme.поверхность2
                    Image(systemName: "signature")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text(сделка.название)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ПилюляEDS(вид: плашка.вид, текст: плашка.текст, вОднуСтроку: true)
                        .frame(maxWidth: 140, alignment: .trailing)
                }
                Text(подпись)
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var подпись: String {
        let роль = EDSText.т(сделка.продавец ? "eds_you_seller" : "eds_you_buyer")
        return [сделка.id, ФорматEDS.тенге(сделка.цена), роль].joined(separator: " · ")
    }
}

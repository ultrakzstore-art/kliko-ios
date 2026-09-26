import SwiftUI

/**
 «ТРАНСПОРТНАЯ КОМПАНИЯ ПО УМОЛЧАНИЮ» В НАСТРОЙКАХ ДОСТАВКИ ОБЪЯВЛЕНИЯ (openDelivery сайта, #del-carrier; владелец:
 «кабинет полностью SwiftUI»).

 Магазину (IS_SHOP) сайт показывает список компаний — GET chat.php?action=logistics_partners → {ok, partners[{id, name,
 tariff}]}, первая строка «Аукцион — компании предложат цену» (пусто). Выбранная уходит в save_delivery как ship_carrier
 (MyListings/PublishedSettings.swift). Остальным — плашка «Только для PRO» и сноска сайта; перевозчик не меняется.
 */
struct ВыборПеревозчика: View {
    let pro: Bool
    @Binding var перевозчик: String

    @State private var компании: [(id: String, подпись: String)] = []
    @State private var грузим = false

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("del_carrier_default"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.текст)
            if pro {
                Picker(т("del_carrier_default"), selection: $перевозчик) {
                    Text(т("del_auction")).tag("")
                    ForEach(варианты, id: \.id) { к in
                        Text(к.подпись).tag(к.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.акцент)
                .overlay(alignment: .trailing) {
                    if грузим { ProgressView().padding(.trailing, 4) }
                }
                Text(т("del_carrier_note"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ЗаметкаБизнеса("\(т("del_pro_only")). \(т("del_pro_note"))", тон: .предупреждение, значок: "crown")
                Text(т("del_pro_footer"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            guard pro, компании.isEmpty else { return }
            await загрузить()
        }
    }

    /// Список сервера; выбранная раньше компания, которой в нём нет, остаётся строкой — чтобы не потерять выбор.
    private var варианты: [(id: String, подпись: String)] {
        if перевозчик.isEmpty || компании.contains(where: { $0.id == перевозчик }) { return компании }
        return компании + [(id: перевозчик, подпись: перевозчик.uppercased())]
    }

    private func загрузить() async {
        грузим = true
        defer { грузим = false }
        guard let j = try? await МоиОбъявленияAPI.получить("chat.php?action=logistics_partners"),
              МоиОбъявленияAPI.да(j["ok"]) else { return }
        компании = ((j["partners"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.compactMap { п -> (id: String, подпись: String)? in
            let номер = МоиОбъявленияAPI.строка(п["id"])
            guard !номер.isEmpty else { return nil }
            let тариф = МоиОбъявленияAPI.строка(п["tariff"])
            let имя = МоиОбъявленияAPI.строка(п["name"])
            return (id: номер, подпись: (имя.isEmpty ? номер.uppercased() : имя) + (тариф.isEmpty ? "" : " · " + тариф))
        }
    }
}

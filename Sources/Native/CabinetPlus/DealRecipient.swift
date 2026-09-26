import SwiftUI

/**
 «ОТПРАВИТЬ ДРУГОМУ ЧЕЛОВЕКУ — ПОДАРОК» В КАРТОЧКЕ СДЕЛКИ (rcpRowHtml / rcpEdit / rcpSave модуля js/cabinet.min.js;
 владелец: «кабинет полностью SwiftUI»).

 Строка «Получатель: имя, телефон» (продавцу — «Подарок — получатель: имя. Курьер созвонится с ним сам.») и, пока сервер
 разрешает (recipient_editable), кнопка «Отправить другому человеку — подарок» / «Изменить получателя». Окно «Кому
 передать»: имя (от 2 знаков) и телефон (+7 и 10 цифр), «Получу сам» убирает получателя. Сохранение —
 escrow.php?action=set_recipient {deal_id, name, phone, clear} (КарточкаСделкиМодель.сохранитьПолучателя). Денег здесь нет.
 */
struct СтрокаПолучателя: View {
    let сделка: Сделка
    @ObservedObject var модель: КарточкаСделкиМодель

    @State private var окно = false

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !сделка.имяПолучателя.isEmpty {
                Label {
                    Text(строка)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "gift")
                        .foregroundStyle(Theme.акцент)
                }
            }
            if сделка.получательМеняется && !сделка.продавец {
                Button {
                    окно = true
                } label: {
                    Label(т(сделка.имяПолучателя.isEmpty ? "rcp_add" : "rcp_edit"), systemImage: "gift")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.акцент)
                }
                .buttonStyle(.plain)
                .disabled(модель.занято)
            }
        }
        .sheet(isPresented: $окно) {
            ЛистПолучателя(имя: сделка.имяПолучателя, телефон: сделка.телефонПолучателя,
                           естьПолучатель: !сделка.имяПолучателя.isEmpty) { имя, телефон, сам in
                окно = false
                модель.сохранитьПолучателя(имя: имя, телефон: телефон, сам: сам)
            }
        }
    }

    private var строка: String {
        if сделка.продавец {
            return т("rcp_line_s").replacingOccurrences(of: "{name}", with: сделка.имяПолучателя)
        }
        return т("rcp_line_b").replacingOccurrences(of: "{name}", with: сделка.имяПолучателя)
            .replacingOccurrences(of: "{phone}", with: сделка.телефонПолучателя)
    }
}

/// rcpEdit: «Кому передать» — имя, телефон, «Получу сам», «Сохранить».
private struct ЛистПолучателя: View {
    let готово: (String, String, Bool) -> Void
    let естьПолучатель: Bool

    @Environment(\.dismiss) private var закрыть
    @State private var имя: String
    @State private var телефон: String
    @State private var ошибка: String? = nil

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    init(имя: String, телефон: String, естьПолучатель: Bool, готово: @escaping (String, String, Bool) -> Void) {
        self.готово = готово
        self.естьПолучатель = естьПолучатель
        _имя = State(initialValue: имя)
        _телефон = State(initialValue: телефон)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(т("co_rcp_name"), text: $имя)
                        .textContentType(.name)
                    TextField("+7 (7__) ___-__-__", text: $телефон)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } footer: {
                    Text(т("rcp_h"))
                }
                if let ошибка {
                    Section {
                        Text(ошибка)
                            .foregroundStyle(КраскаОбъявлений.плохоТекст)
                    }
                }
                if естьПолучатель {
                    Section {
                        Button(т("rcp_self")) { готово("", "", true) }
                            .tint(Theme.акцент)
                    }
                }
            }
            .navigationTitle(т("rcp_t"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CabinetText.т("cancel")) { закрыть() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(т("rcp_save")) { сохранить() }
                }
            }
        }
        .tint(Theme.акцент)
    }

    private func сохранить() {
        let чистоеИмя = String(имя.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let чистыйТелефон = телефон.trimmingCharacters(in: .whitespacesAndNewlines)
        if чистоеИмя.count < 2 {
            ошибка = т("rcp_e_name")
            return
        }
        if чистыйТелефон.filter({ $0.isASCII && $0.isNumber }).count < 10 {
            ошибка = т("rcp_e_phone")
            return
        }
        готово(чистоеИмя, чистыйТелефон, false)
    }
}

import UIKit
import WebKit
import ContactsUI

/// Выбор получателя из контактов телефона (мост klikoContacts).
///
/// Владелец 15.09.2026 (скрин окна «Кому передать» в оформлении): «в приложении доступ к контактам, где телефон
/// получателя — авто подхват + имя, когда контакт выбран».
///
/// CNContactPickerViewController показывается системой в отдельном процессе и НЕ требует разрешения на доступ к
/// контактам: приложение получает только тот контакт и тот номер, которые человек выбрал сам. Поэтому ни окна
/// «Разрешить доступ к контактам», ни ключа NSContactsUsageDescription не нужно — и App Review нечего спрашивать.
///
/// Страница зовёт window.KlikoContacts.pick() и получает обещание {ok, name, phone} (см. WebContainer.liveBridgeJS).
final class ContactsBridge: NSObject, CNContactPickerDelegate {
    weak var webView: WKWebView?
    private var ждёт: Int = 0

    func pick(id: Int) {
        ждёт = id
        DispatchQueue.main.async {
            let пикер = CNContactPickerViewController()
            пикер.delegate = self
            // Показываем номера: у контакта с несколькими номерами человек тапает нужный.
            пикер.displayedPropertyKeys = [CNContactPhoneNumbersKey]
            // Контакт без номеров выбрать нельзя — получателю курьер звонит.
            пикер.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
            // Один номер — контакт возвращается сразу, без второго тапа.
            пикер.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count == 1")
            guard let верх = ContactsBridge.верхнийЭкран() else {
                self.ответ(["ok": false, "code": "no_view"])
                return
            }
            верх.present(пикер, animated: true)
        }
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        let номер = contact.phoneNumbers.first?.value.stringValue ?? ""
        ответ(["ok": true, "name": ContactsBridge.имя(contact), "phone": номер])
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
        let номер = (contactProperty.value as? CNPhoneNumber)?.stringValue ?? ""
        ответ(["ok": true, "name": ContactsBridge.имя(contactProperty.contact), "phone": номер])
    }

    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        ответ(["ok": false, "code": "cancel"])
    }

    /// Ответ в страницу: window.__klikoContact(id, данные). Ничего не сохраняем и никуда не отправляем —
    /// имя и номер уходят только в поля формы, которая их запросила по нажатию кнопки.
    private func ответ(_ данные: [String: Any]) {
        let id = ждёт
        let json = String(data: (try? JSONSerialization.data(withJSONObject: данные)) ?? Data(), encoding: .utf8) ?? "{}"
        DispatchQueue.main.async { [weak self] in
            self?.webView?.evaluateJavaScript("window.__klikoContact && window.__klikoContact(\(id), \(json))")
        }
    }

    private static func имя(_ контакт: CNContact) -> String {
        let полное = CNContactFormatter.string(from: контакт, style: .fullName) ?? ""
        return полное.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func верхнийЭкран() -> UIViewController? {
        let окна = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        var верх = (окна.first { $0.isKeyWindow } ?? окна.first)?.rootViewController
        while let дальше = верх?.presentedViewController { верх = дальше }
        return верх
    }
}

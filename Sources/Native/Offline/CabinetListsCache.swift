import SwiftUI

/**
 СКОРОСТЬ: СПИСКИ КАБИНЕТА НА ДИСКЕ (владелец 30.09.2026: «чтобы моментально открывалось независимо от сети»).

 «Мои объявления» и «Мои сделки» до сих пор на первом показе за запуск ждали страницу кабинета и ответ API — секунды
 пустого «Загружаем» на плохой связи. Теперь последний удачный ответ (строки как пришли, JSON) лежит в Caches, и экран
 сразу рисует его, а свежий ответ подменяет. Нет связи — копия остаётся на экране с плашкой «Нет связи».

 🔴 ТОЛЬКО СВОЁ. В файле — номер вошедшего (uid), на чьих куках пришёл ответ. Копию показываем, только когда человек
 вошёл (СессияПриложения), а модель, увидев на странице кабинета другой uid, сама сбрасывает список — как и прежде при
 смене аккаунта. Выход из аккаунта стирает всю папку (ВыходНачисто). Версия в имени папки: сменится формат — старые копии
 просто не найдутся. Чтение и запись — одной очередью, не на главной.
 */
enum КэшКабинета {
    /// Копия списка: чья она и строки ответа как пришли.
    struct Копия {
        let uid: String
        let строки: [[String: Any]]
    }

    private static let размер = 4 * 1024 * 1024
    private static let очередь = DispatchQueue(label: "kz.kliko.cabinet-lists", qos: .utility)
    private static let допустимые: Set<Character> = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")

    private static var папка: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("kliko-cabinet-lists-v1", isDirectory: true)
    }

    private static func файл(_ имя: String) -> URL? {
        guard !имя.isEmpty, имя.count <= 64, имя.allSatisfy({ допустимые.contains($0) }) else { return nil }
        return папка?.appendingPathComponent(имя + ".json")
    }

    /// Положить строки ответа (только с номером вошедшего — без него копия ничья).
    static func сохранить(_ строки: [Any], имя: String, uid: String) {
        guard !uid.isEmpty, let путь = файл(имя), let корень = папка else { return }
        let запись: [String: Any] = ["uid": uid, "rows": строки]
        guard JSONSerialization.isValidJSONObject(запись),
              let данные = try? JSONSerialization.data(withJSONObject: запись),
              данные.count <= размер else { return }
        очередь.async {
            do {
                try FileManager.default.createDirectory(at: корень, withIntermediateDirectories: true)
                try данные.write(to: путь, options: .atomic)
            } catch {
                // Диск полон — копия удобство, а не обязанность.
            }
        }
    }

    /// Копия списка или nil.
    static func прочитать(_ имя: String) async -> Копия? {
        guard let путь = файл(имя) else { return nil }
        return await withCheckedContinuation { (готово: CheckedContinuation<Копия?, Never>) in
            очередь.async {
                guard let данные = try? Data(contentsOf: путь),
                      let запись = (try? JSONSerialization.jsonObject(with: данные)) as? [String: Any],
                      let uid = запись["uid"] as? String, !uid.isEmpty,
                      let строки = запись["rows"] as? [[String: Any]] else {
                    готово.resume(returning: nil)
                    return
                }
                готово.resume(returning: Копия(uid: uid, строки: строки))
            }
        }
    }

    static func стереть() {
        guard let корень = папка else { return }
        очередь.async { try? FileManager.default.removeItem(at: корень) }
    }
}

/// Плашка над списком, показанным с диска без связи. Офлайн-режим (08.10.2026): та же общая плашка, что у остальных
/// экранов с копией, — «Нет сети — показана сохранённая версия» (ПлашкаБезСети).
struct ПлашкаСохранённогоСписка: View {
    init() {}

    var body: some View {
        ПлашкаБезСети()
    }
}

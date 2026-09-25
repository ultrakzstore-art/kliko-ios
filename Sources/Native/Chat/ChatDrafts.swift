import Foundation

/**
 ЧЕРНОВИКИ ПЕРЕПИСКИ — ЭТАП 17 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «давай следующие этапы»).

 Недописанное сообщение переживает уход с экрана, закрытие приложения и перезапуск: лежит по номеру диалога (tid) и
 возвращается в поле, когда переписка открылась снова. Сообщение ушло — черновик стирается; не ушло — остаётся.

 🔴 ТОЛЬКО НА ТЕЛЕФОНЕ. Черновиков у dm.php нет (приложению известны лишь list/poll/open/send), поэтому на сайте и на
 другом телефоне недописанного не видно. Один JSON в Application Support вне резервной копии: текст переписки в копию
 iCloud не уезжает. Не больше 30 диалогов — лишними уходят самые давние. Стирается при выходе (WebContainer, bye=1).

 Пока номера диалога нет («Написать» из карточки, а open не прошёл), черновик живёт только в поле: класть его не под
 какой номер. Файл пишем не на каждую букву, а через 0,6 с после последней и сразу, когда переписка ушла с экрана.
 */
@MainActor
final class ЧерновикиЧата {
    static let shared = ЧерновикиЧата()

    /// Больше диалогов с недописанным не держим: столько сразу не пишут, а файл не растёт без края.
    static let предел = 30

    private var записи: [String: ЧерновикЗапись]
    /// Отложенная запись файла: каждая буква отменяет прежнюю и ставит новую.
    private var запись: Task<Void, Never>?

    private init() {
        записи = ЧерновикиФайл.прочитать() ?? [:]
    }

    /// Сохранённый черновик диалога или nil.
    func черновик(_ tid: String) -> String? {
        guard !tid.isEmpty, let з = записи[tid], !з.текст.isEmpty else { return nil }
        return з.текст
    }

    /// Поле изменилось. Пустое или одни пробелы — черновика у диалога больше нет.
    func запомнить(_ текст: String, для tid: String) {
        guard !tid.isEmpty else { return }
        if текст.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard записи.removeValue(forKey: tid) != nil else { return }
        } else {
            guard записи[tid]?.текст != текст else { return }
            записи[tid] = ЧерновикЗапись(текст: текст, когда: Date())
            if записи.count > Self.предел {
                let лишние = записи.sorted { $0.value.когда > $1.value.когда }.dropFirst(Self.предел).map { $0.key }
                for ключ in лишние { записи.removeValue(forKey: ключ) }
            }
        }
        записатьПозже()
    }

    /// Переписка ушла с экрана — отложенную запись делаем сейчас: следом приложение могут и закрыть.
    func сохранитьСейчас() {
        guard let ждёт = запись else { return }
        ждёт.cancel()
        запись = nil
        ЧерновикиФайл.записать(записи)
    }

    /// Выход из аккаунта: недописанное ушедшим следующему не показываем.
    func стереть() {
        запись?.cancel()
        запись = nil
        записи = [:]
        ЧерновикиФайл.стереть()
    }

    private func записатьПозже() {
        запись?.cancel()
        запись = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            self.запись = nil
            ЧерновикиФайл.записать(self.записи)
        }
    }
}

/// Черновик одного диалога. Новые поля — только необязательные, иначе файл прежней версии не разберётся.
struct ЧерновикЗапись: Codable, Equatable {
    var текст: String
    var когда: Date

    enum CodingKeys: String, CodingKey {
        case текст = "text"
        case когда = "at"
    }
}

/**
 ФАЙЛ ЧЕРНОВИКОВ: один JSON в Application Support, вне резервной копии — как недавнее (НедавниеФайл).

 Пишем не на главном потоке, но по порядку: одна последовательная очередь, чтобы стирание при выходе не обогнало
 последнюю запись и не оставило файл.
 */
enum ЧерновикиФайл {
    private static let очередь = DispatchQueue(label: "kz.kliko.chat-drafts", qos: .utility)

    private static var адрес: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
            .appendingPathComponent("kliko-chat-drafts.json")
    }

    static func прочитать() -> [String: ЧерновикЗапись]? {
        guard let файл = адрес, let данные = try? Data(contentsOf: файл) else { return nil }
        return try? JSONDecoder().decode([String: ЧерновикЗапись].self, from: данные)
    }

    static func записать(_ записи: [String: ЧерновикЗапись]) {
        guard let файл = адрес else { return }
        guard !записи.isEmpty else {
            очередь.async { try? FileManager.default.removeItem(at: файл) }
            return
        }
        guard let данные = try? JSONEncoder().encode(записи) else { return }
        очередь.async {
            do {
                try данные.write(to: файл, options: .atomic)
                var значения = URLResourceValues()
                значения.isExcludedFromBackup = true
                var изменяемый = файл
                try? изменяемый.setResourceValues(значения)
            } catch {
                // Диск полон — черновик есть в поле до конца запуска; следующая буква попробует снова.
            }
        }
    }

    static func стереть() {
        guard let файл = адрес else { return }
        очередь.async { try? FileManager.default.removeItem(at: файл) }
    }
}

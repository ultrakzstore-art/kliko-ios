import Foundation

/**
 ГДЕ ЛЕЖИТ СНИМОК ЛЕНТЫ.

 Один маленький файл (пара килобайт) в Application Support. Не UserDefaults: туда кладут настройки, а не
 данные, и система читает их целиком при каждом запуске — лента там была бы лишним весом на старте всего
 приложения. Не Documents: это не документ человека, в «Файлах» ему делать нечего.

 🔴 СРОК — СУТКИ, КАК И НА САЙТЕ. Цены и наличие меняются; вчерашняя лента на запуске — помощь, позавчерашняя —
 обман. Просрочку просто не показываем: человек увидит обычный сплэш, как раньше.

 Из резервной копии файл исключаем: восстанавливать чужую вчерашнюю ленту на новом телефоне незачем, а место в
 iCloud у человека своё.
 */
enum FeedStore {

    /// Сутки — столько снимок считается годным к показу.
    static let срок: TimeInterval = 24 * 3600

    private static var файл: URL? {
        guard let папка = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                       in: .userDomainMask,
                                                       appropriateFor: nil,
                                                       create: true) else { return nil }
        return папка.appendingPathComponent("kliko-feed.json")
    }

    /// Положить то, что прислала страница. Строка — уже готовый JSON, разбирать её здесь незачем.
    static func сохранить(_ строка: String) {
        guard let файл, let данные = строка.data(using: .utf8) else { return }
        /* Полмегабайта — потолок с большим запасом: страница шлёт десять товаров на раздел, это пара
           килобайт. Больше — значит что-то пошло не так, и класть это на диск не надо. */
        guard данные.count <= 512 * 1024 else { return }
        do {
            try данные.write(to: файл, options: .atomic)
            var значения = URLResourceValues()
            значения.isExcludedFromBackup = true
            var изменяемый = файл
            try? изменяемый.setResourceValues(значения)
        } catch {
            // Диск полон или нет доступа — снимок не обязанность, а удобство. Молчим.
        }
    }

    /// Прочитать снимок, если он есть и не протух. Читается синхронно: файл крошечный, а нужен он на первом
    /// же кадре — уйдя в фон, мы бы сначала показали сплэш и только потом подменили его лентой.
    static func прочитать() -> FeedSnapshot? {
        guard let файл, let данные = try? Data(contentsOf: файл) else { return nil }
        guard let снимок = try? JSONDecoder().decode(FeedSnapshot.self, from: данные) else { return nil }
        guard снимок.возраст <= срок, !снимок.пустой else { return nil }
        return снимок
    }

    /// Убрать снимок. Зовётся при выходе из аккаунта вместе с остальными данными страницы: лента могла быть
    /// подобрана под город и историю прежнего человека, и показывать её следующему нельзя.
    static func стереть() {
        guard let файл else { return }
        try? FileManager.default.removeItem(at: файл)
    }
}

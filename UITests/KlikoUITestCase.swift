import XCTest

/// Общая основа автотестов ключевых сценариев (KlikoUITests). Тесты ходят в живой сайт kliko.kz без входа в аккаунт
/// и без оплаты: лента, карточка, фильтры, поиск, «Поделиться» и нижняя панель. Селекторы — по русским подписям и
/// ролям (язык телефона ru), потому что accessibilityIdentifier в приложении пока нет; когда их добавят, достаточно
/// поменять запросы здесь, в одном месте.
class KlikoUITestCase: XCTestCase {
    var app: XCUIApplication!

    /// Сколько ждать первой карточки ленты после запуска: холодный старт симулятора и сеть раннера бывают медленными.
    let ожиданиеЛенты: TimeInterval = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Системные вопросы (уведомления, геопозиция) — отказываем: тесты не должны от них зависеть.
        addUIInterruptionMonitor(withDescription: "Системный вопрос") { окно in
            for подпись in ["Не разрешать", "Запретить", "Don’t Allow", "Don't Allow", "Не сейчас", "OK", "ОК"] {
                let кнопка = окно.buttons[подпись]
                if кнопка.exists {
                    кнопка.tap()
                    return true
                }
            }
            return false
        }
    }

    override func tearDownWithError() throws {
        if let app, app.state == .runningForeground {
            let снимок = XCTAttachment(screenshot: app.screenshot())
            снимок.name = name
            снимок.lifetime = .keepAlways
            add(снимок)
        }
        app = nil
    }

    /// Запуск на русском, без вопроса о пушах; `ещё` — отладочные аргументы (-klikoSheet и т. п.).
    @discardableResult
    func запустить(_ ещё: [String] = []) -> XCUIApplication {
        let приложение = XCUIApplication()
        приложение.launchArguments += ["-AppleLanguages", "(ru)", "-AppleLocale", "ru_KZ", "-klikoNoPushPrompt", "YES"]
        приложение.launchArguments += ещё
        приложение.launch()
        app = приложение
        return приложение
    }

    // MARK: Запросы

    /// Карточки объявлений: у карточки одна подпись для VoiceOver — «название, цена тенге, город…».
    var карточки: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                                         "тенге", "Договорная", "Цена по запросу"))
    }

    /// Загрузочный экран запуска (SitePreloader): подпись «Загрузка…».
    var заставка: XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Загрузка…")).firstMatch
    }

    /// Пункт нижней панели («Главная», «Избранное», «Чат», «Профиль»).
    func вкладка(_ подпись: String) -> XCUIElement {
        let панель = app.otherElements["Основная навигация"]
        if панель.exists {
            let внутри = панель.buttons[подпись]
            if внутри.exists { return внутри }
        }
        return app.buttons.matching(NSPredicate(format: "label == %@", подпись)).firstMatch
    }

    /// Любой элемент с подписью, начинающейся с `начало`.
    func элемент(начинаетсяС начало: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", начало)).firstMatch
    }

    /// Кнопка с подписью, начинающейся с `начало`.
    func кнопка(начинаетсяС начало: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", начало)).firstMatch
    }

    // MARK: Ожидания

    /// Ждём, пока `элемент` пропадёт (или и не появлялся).
    @discardableResult
    func дождатьсяИсчезновения(_ элемент: XCUIElement, за секунд: TimeInterval) -> Bool {
        let ожидание = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: элемент)
        return XCTWaiter().wait(for: [ожидание], timeout: секунд) == .completed
    }

    /// Запуск → заставка ушла → в ленте есть карточка. Возвращает первую карточку, которую можно нажать.
    @discardableResult
    func дождатьсяЛенты(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(дождатьсяИсчезновения(заставка, за: ожиданиеЛенты),
                      "Заставка «Загрузка…» не ушла за \(Int(ожиданиеЛенты)) с", file: file, line: line)
        let первая = карточки.firstMatch
        XCTAssertTrue(первая.waitForExistence(timeout: ожиданиеЛенты),
                      "В ленте нет ни одной карточки объявления за \(Int(ожиданиеЛенты)) с", file: file, line: line)
        return нажимаемаяКарточка() ?? первая
    }

    /// Первая карточка, которую видно и можно нажать (верхние могут прятаться под шапкой); иначе листаем вниз.
    func нажимаемаяКарточка() -> XCUIElement? {
        for _ in 0..<4 {
            let все = карточки.allElementsBoundByIndex.prefix(12)
            if let годная = все.first(where: { $0.exists && $0.isHittable }) { return годная }
            app.swipeUp()
        }
        return nil
    }

    /// Нажатие с повтором поиска элемента: SwiftUI перерисовывает ленту, и ссылка на элемент может устареть.
    func нажать(_ элемент: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(элемент.waitForExistence(timeout: 10), "Нет элемента для нажатия: \(элемент)", file: file, line: line)
        if элемент.isHittable {
            элемент.tap()
        } else {
            элемент.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }
}

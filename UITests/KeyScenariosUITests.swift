import XCTest

/// Ключевые сценарии без входа в аккаунт и без денег. Каждый тест запускает приложение заново: падение одного не тянет
/// за собой остальные, а снимок экрана в конце (KlikoUITestCase.tearDown) показывает, где именно остановились.
final class KeyScenariosUITests: KlikoUITestCase {

    /// Запуск: заставка «Загрузка…» уходит, в ленте появляются карточки объявлений (до 30 с).
    func test01_ЗапускЛентаПоказываетКарточки() throws {
        запустить()
        дождатьсяЛенты()
        XCTAssertGreaterThan(карточки.count, 0, "Карточек в ленте нет")
        XCTAssertTrue(вкладка("Главная").exists, "Нет нижней панели с «Главная»")
    }

    /// Карточка объявления: открывается, видна цена, «Поделиться» и хотя бы одна кнопка связи или покупки.
    func test02_КарточкаОбъявленияЦенаИКнопки() throws {
        запустить()
        let карточка = дождатьсяЛенты()
        нажать(карточка)

        let цена = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@",
                                                        "₸", "Договорная", "Цена по запросу")).firstMatch
        XCTAssertTrue(цена.waitForExistence(timeout: 20), "На карточке объявления не видно цены")

        XCTAssertTrue(app.buttons["Поделиться"].waitForExistence(timeout: 10), "На карточке нет «Поделиться»")
        let действия = app.buttons.matching(NSPredicate(
            format: "label IN %@",
            ["Написать продавцу", "Позвонить", "WhatsApp", "Купить безопасно", "Предложить цену", "Заказать безопасно"]))
        XCTAssertTrue(действия.firstMatch.waitForExistence(timeout: 10),
                      "На карточке нет ни одной кнопки: «Написать продавцу», «Позвонить», «Купить безопасно»…")
        // Над объявлением нижней панели нет — как у сайта.
        XCTAssertFalse(вкладка("Профиль").isHittable, "Нижняя панель видна поверх объявления")
    }

    /// Лист «Параметры»: открывается сам отладочным -klikoSheet filters; есть заголовок и «Показать N».
    func test03_ФильтрыЛистПараметры() throws {
        запустить(["-klikoSheet", "filters"])
        дождатьсяЛенты()
        XCTAssertTrue(app.staticTexts["Параметры"].waitForExistence(timeout: 20), "Лист «Параметры» не открылся")
        let показать = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label == %@",
                                                        "Показать", "Ничего не найдено")).firstMatch
        XCTAssertTrue(показать.waitForExistence(timeout: 20), "В листе нет кнопки «Показать N»")
    }

    /// Раздел «Электроника» с главной → «Фильтры» → в листе «Параметры» есть строка «Раздел ›» и «Показать N».
    func test04_ФильтрыРазделаСтрокаРаздел() throws {
        запустить()
        дождатьсяЛенты()
        let плитка = кнопка(начинаетсяС: "Электроника")
        XCTAssertTrue(плитка.waitForExistence(timeout: 15), "На главной нет плитки «Электроника»")
        нажать(плитка)

        let фильтры = app.buttons.matching(NSPredicate(format: "label == %@", "Фильтры")).firstMatch
        XCTAssertTrue(фильтры.waitForExistence(timeout: 20), "В разделе нет кнопки «Фильтры»")
        XCTAssertTrue(карточки.firstMatch.waitForExistence(timeout: ожиданиеЛенты), "В разделе нет карточек")
        нажать(фильтры)

        XCTAssertTrue(app.staticTexts["Параметры"].waitForExistence(timeout: 15), "Лист «Параметры» не открылся")
        let раздел = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Раздел")).firstMatch
        XCTAssertTrue(раздел.waitForExistence(timeout: 20), "В листе «Параметры» нет строки «Раздел ›»")
        let показать = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label == %@",
                                                        "Показать", "Ничего не найдено")).firstMatch
        XCTAssertTrue(показать.waitForExistence(timeout: 20), "В листе нет кнопки «Показать N»")
    }

    /// Поиск: ввести «iphone» и отправить — в выдаче есть объявление про iPhone.
    func test05_ПоискIphone() throws {
        запустить()
        дождатьсяЛенты()
        let поле = app.textFields.firstMatch
        XCTAssertTrue(поле.waitForExistence(timeout: 10), "Нет поля поиска")
        нажать(поле)
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) {
            // Нажатие открыло окно поиска со своим полем, а фокус не встал — нажимаем уже его.
            let полеОкна = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Поиск по объявлениям")).firstMatch
            if полеОкна.waitForExistence(timeout: 5) { нажать(полеОкна) }
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Клавиатура не появилась")
        app.typeText("iphone\n")

        let найдено = app.buttons.matching(NSPredicate(format: "(label CONTAINS[c] %@ OR label CONTAINS[c] %@) AND (label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@)",
                                                       "iphone", "айфон", "тенге", "Договорная", "Цена по запросу")).firstMatch
        XCTAssertTrue(найдено.waitForExistence(timeout: ожиданиеЛенты), "По запросу «iphone» нет ни одной карточки iPhone")
    }

    /// «Поделиться» на карточке ленты → лист «Поделиться» → «QR-код» открывает окно с кодом.
    func test06_ПоделитьсяQRКод() throws {
        запустить()
        дождатьсяЛенты()
        let поделиться = app.buttons.matching(NSPredicate(format: "label == %@", "Поделиться"))
            .allElementsBoundByIndex.first(where: { $0.isHittable }) ?? app.buttons["Поделиться"].firstMatch
        нажать(поделиться)

        let qr = app.buttons["QR-код"]
        XCTAssertTrue(qr.waitForExistence(timeout: 10), "В листе «Поделиться» нет «QR-код»")
        нажать(qr)

        let окно = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label == %@",
                                                                       "QR-код объявления", "QR-код ссылки на объявление")).firstMatch
        XCTAssertTrue(окно.waitForExistence(timeout: 10), "Окно «QR-код объявления» не открылось")
    }

    /// Нижняя панель: Главная → Избранное → Чат → Профиль → Главная, выбранный пункт меняется.
    func test07_ВкладкиПереключаются() throws {
        запустить()
        дождатьсяЛенты()
        for подпись in ["Избранное", "Чат", "Профиль", "Главная"] {
            let пункт = вкладка(подпись)
            XCTAssertTrue(пункт.waitForExistence(timeout: 10), "Нет пункта панели «\(подпись)»")
            нажать(пункт)
            let выбран = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: вкладка(подпись))
            XCTAssertEqual(XCTWaiter().wait(for: [выбран], timeout: 10), .completed, "Пункт «\(подпись)» не стал выбранным")
            XCTAssertEqual(app.state, .runningForeground, "Приложение закрылось на «\(подпись)»")
        }
        XCTAssertTrue(карточки.firstMatch.waitForExistence(timeout: 10), "После возврата на «Главная» нет карточек")
    }

    /// Повторное нажатие выбранной вкладки не кладёт поверх тот же экран: нет «Назад», панель на месте.
    func test08_ПовторныйТапНеОткрываетДубль() throws {
        запустить()
        дождатьсяЛенты()
        for подпись in ["Профиль", "Избранное", "Чат", "Главная"] {
            нажать(вкладка(подпись))
            sleep(1)
            нажать(вкладка(подпись))
            sleep(1)
            нажать(вкладка(подпись))
            sleep(1)
            XCTAssertFalse(app.navigationBars.buttons["BackButton"].exists,
                           "После повторного нажатия «\(подпись)» появилась кнопка «Назад» — открылся дубль экрана")
            XCTAssertTrue(вкладка(подпись).isHittable,
                          "После повторного нажатия «\(подпись)» нижняя панель пропала — поверх открылся экран")
            XCTAssertTrue(вкладка(подпись).isSelected, "После повторного нажатия «\(подпись)» пункт не выбран")
        }
    }
}

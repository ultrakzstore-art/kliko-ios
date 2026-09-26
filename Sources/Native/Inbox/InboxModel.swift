import Foundation
import SwiftUI
import UIKit

/**
 ЕДИНЫЙ ИНБОКС «ЧАТ» — МОДЕЛЬ, ЭТАП 45 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Экран «Чат» кабинета сайта (#messages-screen, карта §6.4.1): строки трёх источников после склейки (ИнбоксAPI.собрать),
 вкладки «Все / Покупатели / Аренда / Обмен» со счётчиками непрочитанных, кнопка «Корзина», поиск по строкам и серверный
 поиск по переписке, закрепление (не больше пяти, закреплённые — сверху, кроме корзины), корзина и «Удалить навсегда».
 Правила — msgFilter, renderMessages, _msgTabCounts, msgPin, msgHide, msgRestore, msgPurge сайта.

 Одна модель на приложение: число на вкладке «Сообщения» и на иконке считает ChatListModel по этим же строкам. Данные —
 одного человека: при выходе стираются (ВыходНачисто), ответ, пришедший после выхода, не принимается (поколение).
 */
@MainActor
final class ИнбоксМодель: ObservableObject {
    static let shared = ИнбоксМодель()

    /// Вкладки #msg-filters и корзина; rawValue — data-k сайта.
    enum Фильтр: String, CaseIterable, Hashable {
        case all, lead, rental, exchange, trash

        /// Вкладки над списком (корзина — отдельной кнопкой рядом с поиском).
        static let вкладки: [Фильтр] = [.all, .lead, .rental, .exchange]

        var название: String {
            switch self {
            case .all: return ИнбоксText.т("f_all")
            case .lead: return ИнбоксText.т("f_lead")
            case .rental: return ИнбоксText.т("f_rental")
            case .exchange: return ИнбоксText.т("f_exchange")
            case .trash: return ИнбоксText.т("trash")
            }
        }
    }

    @Published private(set) var строки: [СтрокаИнбокса] = []
    /// CHAT_PINS страницы, после chat_pin — pins[] ответа.
    @Published private(set) var закреплённые: [String] = []
    @Published private(set) var фильтр: Фильтр = .all
    @Published var поиск: String = "" {
        didSet {
            if поиск != oldValue { поискИзменён() }
        }
    }
    /// Номера, найденные сервером по тексту переписки, и отрывки (_msgDeepIds, _msgDeepSnip). nil — поиска нет.
    @Published private(set) var найденоСервером: [String: String]? = nil
    @Published private(set) var загружено = false
    @Published private(set) var нуженВход = false
    @Published private(set) var ошибка = false
    /// Короткая плашка внизу — toast сайта.
    @Published private(set) var плашка: String? = nil
    /// Строки, по которым сейчас идёт запрос: вторая кнопка ждёт первого ответа.
    @Published private(set) var занято: Set<String> = []

    private var закреплённыеИзвестны = false
    private var задачаПоиска: Task<Void, Never>? = nil
    private var поколение = 0
    /// Идущая загрузка списка: второй вызов ждёт её, а не отвечает старыми строками.
    private var текущаяЗагрузка: Task<ИнбоксAPI.Итог, Never>? = nil
    private var началоЗагрузки = Date.distantPast
    private var поколениеЗагрузки = 0
    private var ещёРаз = false
    private var ещёРазЖдать = false

    private init() {}

    // MARK: - Загрузка

    /**
     Список заново. ждать = false — фоновое обновление (опрос числа, 12 с): страницу под слоем не трогает. Закреплённые
     сервер печатает только в страницу кабинета (CHAT_PINS) — её читаем один раз за сеанс, дальше знаем их из ответов
     chat_pin.

     TestFlight, владелец: «последние сообщения в чате не отразились в общем списке». Раньше второй вызов, пришедший,
     пока шёл первый (опрос 12 с и возврат из переписки почти всегда совпадают), сразу возвращал «готово» со старыми
     строками — список после переписки оставался прежним до следующего опроса. И загрузка шла в задаче экрана: уход в
     переписку отменял её посреди трёх запросов, и строки собирались из одного-двух источников. Теперь загрузка — своя
     задача (отмена экрана её не рвёт), а вызов во время неё ждёт её и, если пришёл не в самом начале, — ещё одну.
     */
    @discardableResult
    func загрузить(ждать: Bool) async -> ИнбоксAPI.Итог {
        if let идёт = текущаяЗагрузка {
            if Date().timeIntervalSince(началоЗагрузки) > 0.3 || поколениеЗагрузки != поколение {
                ещёРаз = true
                if ждать { ещёРазЖдать = true }
            }
            return await идёт.value
        }
        началоЗагрузки = Date()
        поколениеЗагрузки = поколение
        let задача = Task { @MainActor () -> ИнбоксAPI.Итог in
            var итог = await self.загрузитьОдинРаз(ждать: ждать)
            while self.ещёРаз {
                let ждатьСнова = self.ещёРазЖдать
                self.ещёРаз = false
                self.ещёРазЖдать = false
                self.началоЗагрузки = Date()
                self.поколениеЗагрузки = self.поколение
                итог = await self.загрузитьОдинРаз(ждать: ждатьСнова)
            }
            self.текущаяЗагрузка = nil
            return итог
        }
        текущаяЗагрузка = задача
        return await задача.value
    }

    /**
     Переписка закрылась (_afterChatClose сайта: loadMessages, если «Чат» на экране) — список заново в фоне. Экран списка
     при возврате тоже просит загрузку; оба вызова сходятся в одну (см. загрузить).
     */
    func перепискаЗакрыта() {
        guard загружено && !нуженВход else { return }
        Task { @MainActor in _ = await self.загрузить(ждать: false) }
    }

    private func загрузитьОдинРаз(ждать: Bool) async -> ИнбоксAPI.Итог {
        let моё = поколение
        let сборка = await ИнбоксAPI.собрать(ждать: ждать)
        guard моё == поколение else { return .сбой }
        switch сборка.итог {
        case .готово:
            let новые = применитьМестные(сборка.строки)
            if новые != строки { строки = новые }
            нуженВход = false
            ошибка = false
            загружено = true
            if !закреплённыеИзвестны {
                if let страница = try? await КабинетСайта.страницаКабинета(ждать: ждать), моё == поколение,
                   let список = ИнбоксAPI.закреплённые(страница.html) {
                    запомнитьЗакреплённые(список)
                }
            }
        case .нуженВход:
            строки = []
            закреплённые = []
            закреплённыеИзвестны = false
            местные = [:]
            нуженВход = true
            ошибка = false
            загружено = true
        case .сбой:
            ошибка = true
            загружено = true
        }
        return сборка.итог
    }

    // MARK: - Последнее сообщение открытой переписки — сразу в строку

    /// Номер строки → последнее из переписки, пока ответ списка не догонит его (сервер отдал то же время или новее).
    private var местные: [String: ПоследнееВПереписке] = [:]

    /**
     Открытая переписка (dm.php poll/send или лид chat.php) знает последнее сообщение раньше списка: превью («Вы: …»),
     время и место строки меняются сразу, а непрочитанные гаснут (poll сам помечает переписку прочитанной). номера —
     tid и номер открытия (chat_id покупки): строка могла прийти под любым из них.
     */
    func вПереписке(номера: [String], последнее: ПоследнееВПереписке?, прочитано: Bool) {
        let свои = Set(номера.filter { !$0.isEmpty })
        guard !свои.isEmpty, let i = строки.firstIndex(where: { свои.contains($0.номер) }) else { return }
        var строка = строки[i]
        if прочитано { строка.непрочитано = 0 }
        if let последнее, строка.принять(последнее) {
            местные[строка.номер] = последнее
        }
        guard строка != строки[i] else { return }
        var новые = строки
        новые[i] = строка
        строки = ИнбоксAPI.упорядочить(новые)
    }

    /// Ответ списка ещё не знает того, что уже видно в переписке, — оставляем известное; догнал — забываем.
    private func применитьМестные(_ пришли: [СтрокаИнбокса]) -> [СтрокаИнбокса] {
        guard !местные.isEmpty else { return пришли }
        var итог = пришли
        var изменено = false
        for i in итог.indices {
            guard let последнее = местные[итог[i].номер] else { continue }
            if итог[i].принять(последнее) {
                изменено = true
            } else {
                местные[итог[i].номер] = nil
            }
        }
        let есть = Set(пришли.map { $0.номер })
        for номер in Array(местные.keys) where !есть.contains(номер) { местные[номер] = nil }
        return изменено ? ИнбоксAPI.упорядочить(итог) : итог
    }

    /// CHAT_PINS со страницы кабинета (её читает и вкладка «Кабинет»).
    func запомнитьЗакреплённые(_ список: [String]) {
        закреплённыеИзвестны = true
        if список != закреплённые { закреплённые = список }
    }

    // MARK: - Что на экране (renderMessages)

    /// Непрочитанные строк без корзины — число на вкладке «Сообщения».
    var непрочитано: Int {
        строки.filter { !$0.скрыт }.reduce(0) { $0 + $1.непрочитано }
    }

    /// _msgTabCounts: сколько строк с непрочитанными (и не в корзине) у вкладки.
    func счётчик(_ ф: Фильтр) -> Int {
        строки.filter { с in
            guard с.непрочитано > 0 && !с.скрыт else { return false }
            switch ф {
            case .all: return true
            case .lead: return с.источник == .lead
            case .rental: return с.виды.contains("rental")
            case .exchange: return с.виды.contains("exchange")
            case .trash: return false
            }
        }.count
    }

    /// Строки выбранной вкладки: корзина — только убранные (поиск на неё не действует, как у сайта); иначе убранные не
    /// показываются, поиск — по имени, товару и последнему сообщению или по находке сервера; закреплённые — сверху.
    var видимые: [СтрокаИнбокса] {
        let запрос = поиск.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let выбран = фильтр
        let сервер = найденоСервером
        let отобранные: [СтрокаИнбокса] = строки.filter { с in
            if выбран == .trash { return с.скрыт }
            if с.скрыт { return false }
            if !запрос.isEmpty {
                let нашёлСервер = сервер?[с.номер] != nil
                if !с.стог.contains(запрос) && !нашёлСервер { return false }
            }
            switch выбран {
            case .all, .trash: return true
            case .lead: return с.источник == .lead
            case .rental: return с.виды.contains("rental")
            case .exchange: return с.виды.contains("exchange")
            }
        }
        guard выбран != .trash else { return отобранные }
        let пронумерованные = Array(отобранные.enumerated())
        let закреп = Set(закреплённые)
        return пронумерованные.sorted { a, b in
            let aЗ = закреп.contains(a.element.номер) ? 1 : 0
            let bЗ = закреп.contains(b.element.номер) ? 1 : 0
            if aЗ != bЗ { return aЗ > bЗ }
            return a.offset < b.offset
        }.map { $0.element }
    }

    /// Отрывок, найденный сервером, — вместо превью, пока идёт поиск.
    func отрывок(_ с: СтрокаИнбокса) -> String? {
        guard !поиск.trimmingCharacters(in: .whitespaces).isEmpty,
              let отрывок = найденоСервером?[с.номер], !отрывок.isEmpty else { return nil }
        return отрывок
    }

    func закреплена(_ с: СтрокаИнбокса) -> Bool {
        закреплённые.contains(с.номер)
    }

    /// msgFilter: повторное нажатие «Корзины» возвращает ко «Всем».
    func выбрать(_ ф: Фильтр) {
        if ф == .trash && фильтр == .trash {
            фильтр = .all
        } else {
            фильтр = ф
        }
    }

    // MARK: - Поиск (msgSearchInput)

    /// Серверный поиск — с двух букв, через 0,3 с после последней; пришёл к старому запросу — не применяем.
    private func поискИзменён() {
        задачаПоиска?.cancel()
        let запрос = поиск.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard запрос.count >= 2 else {
            найденоСервером = nil
            return
        }
        задачаПоиска = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let найдено = await ИнбоксAPI.найти(запрос)
            guard let self, !Task.isCancelled else { return }
            let сейчас = self.поиск.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if сейчас == запрос, let найдено { self.найденоСервером = найдено }
        }
    }

    // MARK: - Действия (меню «⋯» строки)

    /// msgPin: больше пяти — отказ до запроса; ответ — новый список закреплённых.
    func закрепить(_ с: СтрокаИнбокса) async {
        let включить = !закреплена(с)
        if включить && закреплённые.count >= 5 {
            показатьПлашку(ИнбоксText.т("pin_max"))
            return
        }
        guard начать(с) else { return }
        defer { закончить(с) }
        let моё = поколение
        let (итог, список) = await ИнбоксAPI.закрепить(с.номер, да: включить)
        guard моё == поколение else { return }
        switch итог {
        case .готово:
            if let список { запомнитьЗакреплённые(список) }
            показатьПлашку(ИнбоксText.т(включить ? "pinned" : "unpinned"))
        case .ошибка(let текст):
            показатьПлашку(текст)
        }
    }

    /// msgHide («Убрать в корзину») и msgRestore («Вернуть»).
    func вКорзину(_ с: СтрокаИнбокса, вернуть: Bool) async {
        guard начать(с) else { return }
        defer { закончить(с) }
        let моё = поколение
        let итог = await ИнбоксAPI.корзина(с, оп: вернуть ? "restore" : "hide")
        guard моё == поколение else { return }
        switch итог {
        case .готово:
            if let i = строки.firstIndex(where: { $0.номер == с.номер }) { строки[i].скрыт = !вернуть }
            показатьПлашку(ИнбоксText.т(вернуть ? "restored" : "trash_done"))
        case .ошибка(let текст):
            показатьПлашку(текст)
        }
    }

    /// msgPurge — только после вопроса «Удалить переписку навсегда?» (его задаёт экран).
    func удалитьНавсегда(_ с: СтрокаИнбокса) async {
        guard начать(с) else { return }
        defer { закончить(с) }
        let моё = поколение
        let итог = await ИнбоксAPI.корзина(с, оп: "purge")
        guard моё == поколение else { return }
        switch итог {
        case .готово:
            строки.removeAll { $0.номер == с.номер && $0.тип == с.тип }
            показатьПлашку(ИнбоксText.т("purge_done"))
        case .ошибка(let текст):
            показатьПлашку(текст)
        }
    }

    private func начать(_ с: СтрокаИнбокса) -> Bool {
        guard !занято.contains(с.номер) else { return false }
        занято.insert(с.номер)
        return true
    }

    private func закончить(_ с: СтрокаИнбокса) {
        занято.remove(с.номер)
    }

    func показатьПлашку(_ текст: String) {
        withAnimation(ДвижениеСайта.появление) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard let self, self.плашка == текст else { return }
            withAnimation(ДвижениеСайта.уход) { self.плашка = nil }
        }
    }

    // MARK: - Выход

    func стереть() {
        поколение += 1
        задачаПоиска?.cancel()
        строки = []
        закреплённые = []
        закреплённыеИзвестны = false
        фильтр = .all
        поиск = ""
        найденоСервером = nil
        загружено = false
        нуженВход = false
        ошибка = false
        плашка = nil
        занято = []
        местные = [:]
        ИнбоксAPI.забыть()
    }
}

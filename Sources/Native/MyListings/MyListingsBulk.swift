import Foundation
import SwiftUI
import UIKit

/**
 «МОИ ОБЪЯВЛЕНИЯ» — РЕЖИМ «ВЫБРАТЬ» И МАСС-РЕДАКТОР (владелец 28.09.2026: «добавить, как на сайте, „+ Добавить“,
 „Выбрать“ — галочки, „Выбрать все“, счётчик — и масс-редактор с теми же действиями»).

 Всё по js/cabinet.min.js сайта (advSelToggleMode, _advSelectable, advSelAll, advSelBar, advBulk, advBulkPurge,
 advBulkPrice, advBulkMore, advTableOpen, _advBulkApply, advBulkDelete, pubqOpen / pubqGo) и карте кабинета §2.13:
   · выбрать можно: «Опубликованные» — approved и не истёкшие; «Удалённые» — deleted; «Неактивные» — rejected,
     inactive и истёкшие;
   · «Снять» / «Активировать» / «Восстановить» — по одному deactivate_item / activate_item {id}; pending,
     pending_manual, deleted_permanent пропускаются; на ai_blocked цикл останавливается;
   · «Удалить навсегда» — по одному delete_permanent {id}; «В корзину» из «Ещё» — delete_item {id, reason:
     «Массовое удаление»};
   · правки полей — mass_edit_items {changes:[{id, …}]} пачками по 40: price / rent_price_day, condition, city, stock,
     warranty_days, ship{free} / ship{days}, wholesale:false, category, payment, shop_section;
   · «По расписанию» — pubq_schedule {ids, from, to, every, batch, dates};
   · «Продвинуть» — у сайта окно оплаты; здесь только покупка App Store (ЛистУслугиApple) и только при
     Config.цифровыеПокупки. Выключено — кнопки нет, ссылок на оплату на сайте нет никогда.
 Кнопки ряда — как у сайта: без права massedit (proHasClient) — «Таблицей» и «Продвинуть» / «Активировать»,
 «По расписанию»; с ним — ещё «Снять», «Цена», «Ещё». Кнопка «Выбрать» — у PRO (IS_PRO), как у сайта.

 Отличия от сайта (просьба владельца): перед каждой записью — вопрос со сводкой (что, сколько, что пропустится);
 после — окно хода с итогом и списком того, что не вышло, по каждому объявлению.
 */

// MARK: - Права из страницы кабинета

/// Что сервер вписал в страницу кабинета: IS_PRO, PRO_TIER_CUR, PRO_FEATURE_MIN.massedit и адреса справочников.
struct ПраваМассовых: Equatable {
    /// false — страница ещё не прочитана.
    var известно = false
    var про = false
    var уровень: Int? = nil
    var минимум = 1
    var путьСправочников = "/js/cab-refs.js"
    var путьРазделов = "/js/cats-ru.js"

    init() {}

    init(_ html: String) {
        известно = true
        про = Self.найти(#"const IS_PRO\s*=\s*(true|false)"#, html) == "true"
        if let т = Self.найти(#"PRO_TIER_CUR\s*=\s*(\d+)"#, html) { уровень = Int(т) }
        if let м = Self.найти(#"PRO_FEATURE_MIN\s*=\s*\{[^}]*"massedit"\s*:\s*(\d+)"#, html), let ч = Int(м) {
            минимум = ч
        }
        if let п = Self.найти(#"src="(/js/cab-refs\.js[^"]*)""#, html) { путьСправочников = п }
        if let п = Self.найти(#"src="(/js/cats-[a-z]+\.js[^"]*)""#, html) { путьРазделов = п }
    }

    /// Кнопка «Выбрать» (у сайта — только PRO). Страница не прочитана — кнопка есть.
    var выбор: Bool { !известно || про }

    /// proHasClient("massedit"): уровень PRO не ниже нужного.
    var правка: Bool {
        guard известно else { return true }
        if let уровень { return уровень >= минимум }
        return про
    }

    private static func найти(_ шаблон: String, _ текст: String) -> String? {
        guard let выражение = try? NSRegularExpression(pattern: шаблон, options: []) else { return nil }
        let весь = NSRange(текст.startIndex..<текст.endIndex, in: текст)
        guard let совпадение = выражение.firstMatch(in: текст, options: [], range: весь),
              совпадение.numberOfRanges > 1,
              let диапазон = Range(совпадение.range(at: 1), in: текст) else { return nil }
        return String(текст[диапазон])
    }
}

extension МоёОбъявление {
    /// _advSelectable сайта.
    func выбирается(_ вкладка: ВкладкаОбъявлений, сейчас: Double) -> Bool {
        switch вкладка {
        case .published: return статус == "approved" && !истёк(сейчас)
        case .deleted:   return статус == "deleted"
        case .inactive:  return статус == "rejected" || статус == "inactive" || истёк(сейчас)
        }
    }
}

/// «Уточнить тип» (advCatPickerHtml / catRefine): все выбранные — из одной подкатегории с ≥2 листьями.
struct УточнениеТипа: Equatable {
    /// «Электроника › Компьютеры ›».
    let путь: String
    let варианты: [ВариантПоля]
    let текущий: String
}

// MARK: - Масс-редактор

@MainActor
final class МассовыйРедактор: ObservableObject {
    static let shared = МассовыйРедактор()

    enum Лист: String, Identifiable {
        case цена, ещё, таблица, расписание, продвижение
        var id: String { rawValue }
    }

    enum ПоОдному {
        case снять, активировать, восстановить, вКорзину, навсегда
    }

    /// Вопрос перед записью: заголовок, сводка, кнопка.
    struct Вопрос: Identifiable {
        let id = UUID()
        let заголовок: String
        let строки: [String]
        let кнопка: String
        let опасно: Bool
        let действие: () -> Void
    }

    /// Не вышло с одним объявлением.
    struct Сбой: Identifiable, Equatable {
        let id: String
        let название: String
        let причина: String
    }

    /// Окно хода (advProgress сайта) и итог.
    struct Ход: Equatable {
        var заголовок: String
        var всего: Int
        var сделано: Int = 0
        var итог: String? = nil
        var сбои: [Сбой] = []
    }

    @Published private(set) var включён = false
    @Published private(set) var выбрано: Set<String> = []
    @Published var лист: Лист? = nil
    @Published var вопрос: Вопрос? = nil
    @Published private(set) var ход: Ход? = nil

    /// Справочники листа «Ещё»: города GEO_CITIES, разделы магазина, дерево разделов для «Уточнить тип».
    @Published private(set) var города: [String] = []
    @Published private(set) var разделыМагазина: [РазделМагазина]? = nil
    @Published private(set) var справочники: СправочникиПодачи? = nil

    private var идёт = false
    /// Окно, которое сайт показывает после цикла (блокировка Kliko AI) — после закрытия окна хода.
    private var послеХода: МоиОбъявленияМодель.Окно? = nil
    private var путьГородов = ""

    private init() {}

    private var модель: МоиОбъявленияМодель { МоиОбъявленияМодель.shared }
    private var сейчас: Double { Date().timeIntervalSince1970 }
    private func т(_ ключ: String) -> String { МассовыйРедакторText.т(ключ) }
    private typealias A = МоиОбъявленияAPI

    // MARK: Режим и отметки

    /// «Выбрать» / «Отмена» (advSelToggleMode): отметки сбрасываются.
    func переключить() {
        включён.toggle()
        выбрано = []
        лист = nil
    }

    func выйти() {
        включён = false
        выбрано = []
        лист = nil
    }

    /// Выход из аккаунта — всё прочь.
    func сбросить() {
        выйти()
        вопрос = nil
        ход = nil
        послеХода = nil
        разделыМагазина = nil
    }

    /// Смена вкладки: отметки другой вкладки не переносятся.
    func вкладкаСменилась() {
        выбрано = []
        лист = nil
    }

    func отмечено(_ товар: МоёОбъявление) -> Bool { выбрано.contains(товар.id) }

    /// Список перечитан: отметки тех, кого больше нет, прочь.
    func сверить() {
        guard !выбрано.isEmpty else { return }
        let есть = Set(модель.товары.map { $0.id })
        let оставить = выбрано.intersection(есть)
        if оставить != выбрано { выбрано = оставить }
    }

    /// _advSelPick: только то, что можно выбрать на этой вкладке.
    func отметить(_ товар: МоёОбъявление) {
        guard товар.выбирается(модель.вкладка, сейчас: сейчас) else { return }
        if выбрано.contains(товар.id) {
            выбрано.remove(товар.id)
        } else {
            выбрано.insert(товар.id)
        }
    }

    /// Видимые (вкладка и поиск), которые можно выбрать.
    private var доступные: [String] {
        let вкладка = модель.вкладка
        let момент = сейчас
        return модель.видимые.filter { $0.выбирается(вкладка, сейчас: момент) }.map { $0.id }
    }

    /// _advAllOn: все доступные отмечены — кнопка «Снять все».
    var всеОтмечены: Bool {
        let д = доступные
        return !д.isEmpty && д.allSatisfy { выбрано.contains($0) }
    }

    /// advSelAll: все доступные — или снять все.
    func всеИлиНикого() {
        let д = доступные
        guard !д.isEmpty else {
            модель.показать(т("nothing_avail"))
            return
        }
        if всеОтмечены {
            выбрано.subtract(д)
        } else {
            выбрано.formUnion(д)
        }
    }

    /// Отмеченные, что есть в списке, — в порядке сервера.
    var выбранные: [МоёОбъявление] {
        модель.товары.filter { выбрано.contains($0.id) }
    }

    /// Открыть лист, если что-то отмечено.
    func открыть(_ новый: Лист) {
        guard !выбрано.isEmpty else {
            модель.показать(т("nosel"))
            return
        }
        лист = новый
    }

    // MARK: Сводка для вопроса

    /// «Объявлений: 5» и до пяти названий.
    private func сводка(_ список: [МоёОбъявление]) -> [String] {
        var строки = [String(format: т("q_count"), список.count)]
        let названия = список.prefix(5).map { $0.название.isEmpty ? "· #" + $0.id : "· " + $0.название }
        строки.append(contentsOf: названия)
        if список.count > 5 { строки.append(String(format: т("q_more"), список.count - 5)) }
        return строки
    }

    // MARK: По одному: снять, активировать, восстановить, в корзину, навсегда

    func спросить(_ д: ПоОдному) {
        var список = выбранные
        guard !список.isEmpty else {
            модель.показать(т("nosel"))
            return
        }
        var пропущено = 0
        switch д {
        case .активировать, .восстановить:
            let можно = список.filter { !["pending", "pending_manual", "deleted_permanent"].contains($0.статус) }
            пропущено = список.count - можно.count
            список = можно
            guard !список.isEmpty else {
                модель.показать(т("onreview"))
                return
            }
        case .навсегда:
            список = список.filter { $0.статус == "deleted" }
            guard !список.isEmpty else {
                модель.показать(т("nosel"))
                return
            }
        case .снять, .вКорзину:
            break
        }
        var строки: [String] = []
        let заголовок: String
        let кнопка: String
        switch д {
        case .снять:
            заголовок = String(format: т("q_deact_t"), список.count)
            кнопка = т("q_deact_b")
        case .активировать:
            заголовок = String(format: т("q_act_t"), список.count)
            кнопка = т("q_act_b")
            строки.append(т("q_act_s"))
        case .восстановить:
            заголовок = String(format: т("q_rest_t"), список.count)
            кнопка = т("q_rest_b")
            строки.append(т("q_act_s"))
        case .вКорзину:
            заголовок = String(format: т("q_trash_t"), список.count)
            кнопка = т("q_trash_b")
            строки.append(т("q_trash_s"))
        case .навсегда:
            заголовок = т("q_purge_t")
            кнопка = т("q_purge_b")
            строки.append(String(format: т("q_purge_s"), список.count))
        }
        строки.append(contentsOf: сводка(список))
        if пропущено > 0 { строки.append(String(format: т("q_skip_review"), пропущено)) }
        let опасно = д == .снять || д == .вКорзину || д == .навсегда
        let итогПропущено = пропущено
        let итоговый = список
        лист = nil
        вопрос = Вопрос(заголовок: заголовок, строки: строки, кнопка: кнопка, опасно: опасно) { [weak self] in
            self?.поОдному(д, итоговый, пропущено: итогПропущено)
        }
    }

    private func поОдному(_ д: ПоОдному, _ список: [МоёОбъявление], пропущено: Int) {
        guard !идёт, !список.isEmpty else { return }
        идёт = true
        let хвост: String
        let заголовок: String
        switch д {
        case .снять:
            хвост = "cabinet.php?action=deactivate_item"
            заголовок = т("pr_deactivating")
        case .активировать, .восстановить:
            хвост = "cabinet.php?action=activate_item"
            заголовок = т("pr_activating")
        case .вКорзину:
            хвост = "cabinet.php?action=delete_item"
            заголовок = т("pr_deleting")
        case .навсегда:
            хвост = "cabinet.php?action=delete_permanent"
            заголовок = т("pr_purging")
        }
        ход = Ход(заголовок: заголовок, всего: список.count)
        Task { @MainActor in
            var удачно = 0
            var сбои: [Сбой] = []
            var стоп = false
            for товар in список {
                var тело: [String: Any] = ["id": товар.id]
                if д == .вКорзину { тело["reason"] = "Массовое удаление" }
                do {
                    let j = try await A.отправить(хвост, тело: тело)
                    if A.да(j["ok"]) {
                        удачно += 1
                    } else if A.нетСессии(j) {
                        self.ход = nil
                        self.идёт = false
                        self.выйти()
                        self.модель.нуженВход()
                        return
                    } else if A.да(j["ai_blocked"]) {
                        /* Сайт останавливает цикл и показывает окно блокировки Kliko AI. */
                        let часы = A.строка(j["hours"])
                        self.послеХода = .блокИИ(часы: часы.isEmpty ? "24" : часы, id: nil)
                        сбои.append(Сбой(id: товар.id, название: товар.название, причина: self.т("ai_blocked")))
                        стоп = true
                    } else {
                        сбои.append(Сбой(id: товар.id, название: товар.название, причина: self.причина(j)))
                    }
                } catch {
                    сбои.append(Сбой(id: товар.id, название: товар.название, причина: self.т("conn_err")))
                }
                self.ход?.сделано += 1
                if стоп { break }
            }
            var итог: String
            switch д {
            case .вКорзину:
                итог = String(format: self.т("res_trash"), удачно)
            case .навсегда:
                итог = String(format: self.т("res_purged"), удачно, список.count)
            case .снять, .активировать, .восстановить:
                итог = String(format: self.т("res_done"), удачно, список.count)
            }
            if пропущено > 0 { итог += String(format: self.т("res_review"), пропущено) }
            await self.закончить(итог, сбои: сбои)
        }
    }

    /// Причина отказа по одному объявлению: слова сервера или общие.
    private func причина(_ j: [String: Any]) -> String {
        if A.да(j["prohibited"]) {
            let метка = A.строка(j["cat_label"])
            return метка.isEmpty ? т("prohibited") : т("prohibited") + ": " + метка
        }
        let текст = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if A.да(j["slots_full"]) && текст.isEmpty { return т("slots_full") }
        return текст.isEmpty || КабинетСайта.машинныйКод(текст) ? т("err_generic") : текст
    }

    /// Итог в окне хода, отметки и режим прочь, список заново (loadMyItems сайта). Без сбоев окно уходит само.
    private func закончить(_ итог: String, сбои: [Сбой]) async {
        ход?.итог = итог
        ход?.сбои = сбои
        идёт = false
        выйти()
        UIAccessibility.post(notification: .announcement, argument: итог)
        await модель.загрузить(страницу: false)
        if сбои.isEmpty {
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            if ход?.итог == итог { закрытьХод() }
        }
    }

    /// «Готово» в окне хода.
    func закрытьХод() {
        guard !идёт else { return }
        ход = nil
        if let окно = послеХода {
            послеХода = nil
            модель.окно = окно
        }
    }

    // MARK: Правки полей (mass_edit_items)

    /**
     _advBulkApply: для каждого выбранного — правка или nil (не подходит). Вопрос со сводкой, потом пачки по 40.
     описание — что меняется («Цена: −10 %»), итог — подпись результата сайта («Цена снижена»).
     */
    func применить(описание: String, итог: String, пропуск: String? = nil,
                   изменения: (МоёОбъявление) -> [String: Any]?) {
        let список = выбранные
        guard !список.isEmpty else {
            модель.показать(т("nosel"))
            return
        }
        var правки: [[String: Any]] = []
        var годные: [МоёОбъявление] = []
        for товар in список {
            guard var правка = изменения(товар) else { continue }
            правка["id"] = товар.id
            правки.append(правка)
            годные.append(товар)
        }
        guard !правки.isEmpty else {
            лист = nil
            модель.показать(т("none_applicable"))
            return
        }
        var строки = [описание]
        строки.append(contentsOf: сводка(годные))
        let пропущено = список.count - правки.count
        if пропущено > 0 { строки.append(String(format: т("q_skip"), пропущено) + (пропуск.map { " — " + $0 } ?? "")) }
        let готово = правки
        лист = nil
        вопрос = Вопрос(заголовок: т("q_edit_t"), строки: строки, кнопка: т("q_apply"), опасно: false) { [weak self] in
            self?.править(итог, готово)
        }
    }

    /// «Таблицей»: у каждой строки свои правки (только изменённые поля).
    func сохранитьТаблицу(_ правки: [String: [String: Any]]) {
        let список = выбранные.filter { правки[$0.id] != nil }
        guard !список.isEmpty else {
            модель.показать(т("tbl_nochange"))
            return
        }
        var готово: [[String: Any]] = []
        for товар in список {
            guard var п = правки[товар.id] else { continue }
            п["id"] = товар.id
            готово.append(п)
        }
        var строки = [String(format: т("tbl_changed"), список.count)]
        строки.append(contentsOf: сводка(список))
        лист = nil
        вопрос = Вопрос(заголовок: т("q_edit_t"), строки: строки, кнопка: т("tbl_save"), опасно: false) { [weak self] in
            self?.править(self?.т("tbl_saving") ?? "", готово)
        }
    }

    private func править(_ итог: String, _ правки: [[String: Any]]) {
        guard !идёт, !правки.isEmpty else { return }
        идёт = true
        ход = Ход(заголовок: т("pr_applying"), всего: правки.count)
        Task { @MainActor in
            var обновлено = 0
            var неВлезло = 0
            var ждутНомер = 0
            var тест = false
            var нуженПро = false
            var ошибка: String? = nil
            var начало = 0
            while начало < правки.count {
                let конец = min(начало + 40, правки.count)
                let пачка = Array(правки[начало..<конец])
                do {
                    let j = try await A.отправить("cabinet.php?action=mass_edit_items", тело: ["changes": пачка])
                    if !A.да(j["ok"]) {
                        if A.нетСессии(j) {
                            self.ход = nil
                            self.идёт = false
                            self.выйти()
                            self.модель.нуженВход()
                            return
                        }
                        if A.да(j["shop_required"]) {
                            нуженПро = true
                        } else {
                            ошибка = self.причина(j)
                        }
                        break
                    }
                    обновлено += A.целое(j["updated"])
                    неВлезло += A.целое(j["slots_skipped"])
                    if A.да(j["need_phone"]) { ждутНомер += A.целое(j["phone_skipped"]) }
                    if A.да(j["test_capped"]) {
                        тест = true
                        self.ход?.сделано = конец
                        break
                    }
                } catch {
                    ошибка = self.т("conn_err")
                    break
                }
                self.ход?.сделано = конец
                начало = конец
            }
            if нуженПро {
                /* shopToolsUpsell сайта: PRO — только покупкой App Store и только при Config.цифровыеПокупки. */
                self.ход = nil
                self.идёт = false
                self.модель.показать(self.т("need_pro"))
                if Config.цифровыеПокупки { ЛистУслугиApple.показать(.про) }
                return
            }
            if let ошибка {
                self.идёт = false
                self.ход?.итог = self.т("res_fail")
                self.ход?.сбои = [Сбой(id: "-", название: self.т("res_fail"), причина: ошибка)]
                await self.модель.загрузить(страницу: false)
                return
            }
            var текст = (итог.isEmpty ? self.т("pr_done") : итог) + ": " + String(обновлено)
            if неВлезло > 0 { текст += String(format: self.т("res_noslot"), неВлезло) }
            if ждутНомер > 0 { текст += String(format: self.т("res_phone"), ждутНомер) }
            if тест { текст += self.т("res_test") }
            var сбои: [Сбой] = []
            let мимо = правки.count - обновлено
            if мимо > 0 && !тест {
                сбои.append(Сбой(id: "-", название: String(format: self.т("res_not_updated"), мимо),
                                 причина: неВлезло > 0 ? self.т("slots_full") : self.т("res_not_updated_why")))
            }
            await self.закончить(текст, сбои: сбои)
        }
    }

    // MARK: По расписанию (pubq_schedule)

    /// advBulkSchedule: неактивные, отклонённые и истёкшие.
    var дляРасписания: [МоёОбъявление] {
        let момент = сейчас
        return выбранные.filter { $0.статус == "inactive" || $0.статус == "rejected" || $0.истёк(момент) }
    }

    func открытьРасписание() {
        guard !выбрано.isEmpty else {
            модель.показать(т("nosel"))
            return
        }
        guard !дляРасписания.isEmpty else {
            модель.показать(т("pq_pick_pub"))
            return
        }
        лист = .расписание
    }

    func спроситьРасписание(с: String, по: String, каждые: Int, поСколько: Int, дни: [String], подписиДней: [String]) {
        let список = дляРасписания
        guard !список.isEmpty else {
            модель.показать(т("pq_pick_pub"))
            return
        }
        guard !дни.isEmpty else {
            модель.показать(т("pq_one_day"))
            return
        }
        var строки = [String(format: т("pq_sum"), с, по, поСколько, каждые), подписиДней.joined(separator: ", ")]
        строки.append(contentsOf: сводка(список))
        let ids = список.map { $0.id }
        лист = nil
        вопрос = Вопрос(заголовок: т("pq_title"), строки: строки, кнопка: т("pq_go"), опасно: false) { [weak self] in
            self?.поставить(ids: ids, с: с, по: по, каждые: каждые, поСколько: поСколько, дни: дни)
        }
    }

    private func поставить(ids: [String], с: String, по: String, каждые: Int, поСколько: Int, дни: [String]) {
        guard !идёт else { return }
        идёт = true
        ход = Ход(заголовок: т("pq_go_wait"), всего: ids.count)
        Task { @MainActor in
            let тело: [String: Any] = ["ids": ids, "from": с, "to": по, "every": каждые, "batch": поСколько,
                                       "dates": дни]
            do {
                let j = try await A.отправить("cabinet.php?action=pubq_schedule", тело: тело)
                if A.нетСессии(j) {
                    self.ход = nil
                    self.идёт = false
                    self.выйти()
                    self.модель.нуженВход()
                    return
                }
                guard A.да(j["ok"]) else {
                    self.идёт = false
                    let слова = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
                    self.ход?.итог = self.т("pq_fail")
                    self.ход?.сбои = [Сбой(id: "-", название: self.т("pq_fail"),
                                          причина: слова.isEmpty || КабинетСайта.машинныйКод(слова)
                                            ? self.т("err_generic") : слова)]
                    return
                }
                self.ход?.сделано = ids.count
                var итог = String(format: self.т("pq_queued"), A.целое(j["queued"]))
                let следующее = A.число(j["next"])
                if следующее > 0 { итог += " — " + String(format: self.т("pq_first"), self.когда(следующее)) }
                let пропущено = A.целое(j["skipped"])
                if пропущено > 0 { итог += " · " + String(format: self.т("pq_skipped"), пропущено) }
                let невлезло = A.целое(j["nofit"])
                if невлезло > 0 { итог += " · " + String(format: self.т("pq_nofit_s"), невлезло) }
                await self.закончить(итог, сбои: [])
            } catch {
                self.идёт = false
                self.ход?.итог = self.т("pq_fail")
                self.ход?.сбои = [Сбой(id: "-", название: self.т("pq_fail"), причина: self.т("conn_err"))]
            }
        }
    }

    /// _pqWhenShort: «сегодня, 14:30» / «завтра, 09:00» / «3 окт., 10:00» по Алматы.
    private func когда(_ секунды: Double) -> String {
        let пояс = TimeZone(identifier: "Asia/Almaty") ?? TimeZone.current
        var календарь = Calendar(identifier: .gregorian)
        календарь.timeZone = пояс
        let дата = Date(timeIntervalSince1970: секунды)
        let часы = DateFormatter()
        часы.locale = Locale(identifier: "en_US_POSIX")
        часы.timeZone = пояс
        часы.dateFormat = "HH:mm"
        let день: String
        if календарь.isDateInToday(дата) {
            день = т("pq_today")
        } else if календарь.isDateInTomorrow(дата) {
            день = т("pq_tomorrow")
        } else {
            let ф = DateFormatter()
            ф.locale = МоиОбъявленияText.локаль
            ф.timeZone = пояс
            ф.setLocalizedDateFormatFromTemplate("dMMM")
            день = ф.string(from: дата)
        }
        return день + ", " + часы.string(from: дата)
    }

    // MARK: Продвинуть (только App Store)

    /// advBulkPromote: только опубликованные. Одно — сразу окно покупки; несколько — список, покупка по одному.
    func продвинуть() {
        guard Config.цифровыеПокупки else { return }
        let список = выбранные.filter { $0.статус == "approved" }
        guard !список.isEmpty else {
            модель.показать(т("pick_pub"))
            return
        }
        if список.count == 1, let первое = список.first {
            ЛистУслугиApple.показать(.продвижение, цель: первое.id)
            return
        }
        лист = .продвижение
    }

    // MARK: Справочники листа «Ещё»

    /// Города (GEO_CITIES из js/cab-refs.js), разделы магазина (shop_sections_list) и дерево разделов (js/cats-*.js).
    func загрузитьСправочники() async {
        let права = модель.массовые
        if города.isEmpty || путьГородов != права.путьСправочников {
            let прочитано = try? await КабинетСайта.вызвать(права.путьСправочников, отКорня: true)
            if let ответ = прочитано, ответ.код == 200 {
                let текст = ответ.текст
                let список = await Task.detached(priority: .userInitiated) { () -> [String] in
                    let данные = РазборJSON.после("\"GEO_CITIES\":", в: Array(текст.utf8))
                    return (данные?.элементы ?? []).map { $0.текст }.filter { !$0.isEmpty }
                }.value
                if !список.isEmpty {
                    города = список
                    путьГородов = права.путьСправочников
                }
            }
        }
        if разделыМагазина == nil {
            let список = try? await БизнесРазделыAPI.разделы()
            if let список { разделыМагазина = список }
        }
        if справочники == nil {
            var страница = СтраницаПодачи()
            страница.путьРазделов = права.путьРазделов
            страница.путьСправочников = права.путьСправочников
            let загружено = try? await ЗагрузкаСправочников.загрузить(страница)
            if let загружено { справочники = загружено }
        }
    }

    /// advCityFilter: до 10 городов, где есть введённое, — раньше те, где оно ближе к началу.
    func подсказкиГородов(_ ввод: String) -> [String] {
        let q = ввод.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var найдено: [(Int, String)] = []
        for город in города {
            let низ = город.lowercased()
            if let r = низ.range(of: q) {
                найдено.append((низ.distance(from: низ.startIndex, to: r.lowerBound), город))
            }
        }
        найдено.sort { $0.0 < $1.0 }
        return найдено.prefix(10).map { $0.1 }
    }

    /// Город из списка без учёта регистра (advBulkCity) — nil, если такого нет.
    func городИзСписка(_ ввод: String) -> String? {
        let q = ввод.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }
        return города.first { $0.lowercased() == q }
    }

    /// advCatPickerHtml: общий родитель у всех выбранных, у него ≥ 2 листьев.
    var уточнение: УточнениеТипа? {
        guard let с = справочники else { return nil }
        var база: String? = nil
        var образец: (варианты: [String], текущий: String)? = nil
        for товар in выбранные {
            guard let р = уточнить(товар.раздел, с) else { return nil }
            if let б = база {
                if б != р.база { return nil }
            } else {
                база = р.база
                образец = (варианты: р.варианты, текущий: р.текущий)
            }
        }
        guard let б = база, let о = образец else { return nil }
        let корень = с.корень(б)
        let путь = (корень == б ? с.имя(б) : с.имя(корень) + " › " + с.имя(б)) + " ›"
        let варианты = о.варианты.map { ВариантПоля(ключ: $0, подпись: с.имя($0).isEmpty ? $0 : с.имя($0)) }
        return УточнениеТипа(путь: путь, варианты: варианты, текущий: о.текущий)
    }

    /// catRefine: не лист — его дети-листья; лист — листья его родителя. Меньше двух — нечего выбирать.
    private func уточнить(_ раздел: String, _ с: СправочникиПодачи) -> (база: String, варианты: [String], текущий: String)? {
        let ключ = раздел.isEmpty ? "other" : раздел
        guard let узел = с.разделы[ключ] else { return nil }
        let база = узел.дети.isEmpty ? узел.родитель : ключ
        guard let б = база, let родитель = с.разделы[б] else { return nil }
        let листья = родитель.дети.filter { (с.разделы[$0]?.дети.isEmpty) ?? true }
        guard листья.count >= 2 else { return nil }
        return (б, листья, ключ)
    }
}

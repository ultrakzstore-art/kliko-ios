import Foundation
import SwiftUI
import PhotosUI
import UIKit

/**
 ПОДАЧА — ЗАПРОСЫ: ФОТО, KLIKO AI, ТОП, SUBMIT, EDIT_ITEM, «ДОПОЛНИТЕЛЬНО», ЭТАП 42 (владелец 26.09.2026).

 Тела — как у сайта (_doSubmitReal, _doEditSaveReal, uploadImageSmart, doRecognize, cfgReplayToItem, publishTopPick;
 карта §2.4). Всё пишущее — только по нажатию:
   · upload_photo — когда человек выбрал или снял фото (сайт грузит каждое сразу, по очереди);
   · recognize {paid: 0} — только «Распознать»; платный глубокий разбор и пакеты — страницей сайта;
   · submit — «Опубликовать» в окне «Проверьте перед публикацией»; edit_item — «Сохранить изменения»;
   · save_payment / save_delivery / save_trust — сразу после удачной подачи, как у сайта, и только то, что человек
     настроил в «Дополнительно» (не удалось — один повтор через 1,5 с, как cfgReplayToItem);
   · media_keep_alive — после «Продолжить» черновика.
 🔴 Submit с ТОПом (top_preset) — денежный: при «csrf» и обрыве сети не повторяется (§8.0.2–3).
 */
extension ПодачаМодель {

    // MARK: - Фото: выбор и загрузка

    var местоФото: Int { max(0, лимитФото - плитки.count) }

    /// Галерея: первые «сколько осталось места» (photoRoom), лишние отбрасываются молча, как у сайта; больше 15 МБ —
    /// «Фото больше 15 МБ».
    func принять(_ элементы: [PhotosPickerItem]) async {
        var место = местоФото
        var данные: [Data] = []
        for элемент in элементы {
            guard место > 0 else { break }
            guard let файл = try? await элемент.loadTransferable(type: Data.self) else { continue }
            if файл.count > ОбработкаФото.предел {
                показать(т("ph_big"))
                continue
            }
            данные.append(файл)
            место -= 1
        }
        await загрузитьНовые(данные)
    }

    /// Камера: снимок — в JPEG высокого качества здесь, ужатие и знак — в фоне тем же путём, что у галереи.
    func принять(снимок: UIImage) {
        guard местоФото > 0 else {
            показать(String(format: т("photo_cap_full"), лимитФото))
            return
        }
        guard let данные = снимок.jpegData(compressionQuality: 0.95) else { return }
        Task { @MainActor in await self.загрузитьНовые([данные]) }
    }

    /// photoIngest: плитки появляются сразу, файлы обрабатываются и уходят на сервер по очереди.
    private func загрузитьНовые(_ файлы: [Data]) async {
        guard !файлы.isEmpty else { return }
        var номера: [UUID] = []
        for _ in файлы {
            let id = UUID()
            номера.append(id)
            плитки.append(ПлиткаФото(id: id, url: "", превью: nil, картинка: nil, миниатюра: nil, грузится: true,
                                     ошибка: nil))
        }
        for (i, файл) in файлы.enumerated() {
            let id = номера[i]
            let готово: ГотовоеФото? = await Task.detached(priority: .userInitiated) { () -> ГотовоеФото? in
                ОбработкаФото.подготовить(файл)
            }.value
            guard let место = плитки.firstIndex(where: { $0.id == id }) else { continue }
            guard let готово else {
                плитки[место].грузится = false
                плитки[место].ошибка = т("ph_fail_process")
                continue
            }
            плитки[место].картинка = готово.картинка
            плитки[место].миниатюра = готово.миниатюра
            плитки[место].превью = UIImage(data: готово.миниатюра) ?? UIImage(data: готово.картинка)
            await загрузить(id)
        }
    }

    /// «повторить» на плитке (phRetry).
    func повторить(_ id: UUID) {
        guard let место = плитки.firstIndex(where: { $0.id == id }), !плитки[место].грузится,
              плитки[место].картинка != nil else { return }
        Task { @MainActor in await self.загрузить(id) }
    }

    /// makeMain: первое фото — главное.
    func сделатьГлавным(_ id: UUID) {
        guard let место = плитки.firstIndex(where: { $0.id == id }), место > 0 else { return }
        let плитка = плитки.remove(at: место)
        плитки.insert(плитка, at: 0)
        показать(т("made_main"))
    }

    /// removePhoto: только на телефоне — запроса «удалить фото» у сайта нет, порядок уходит массивом images.
    func удалитьФото(_ id: UUID) {
        /* Удалил постер-обложку сам — при публикации он не вернётся (включить снова — в карточке постера). */
        if let плитка = плитки.first(where: { $0.id == id }), этоОбложка(плитка) {
            забытьОбложку(выключить: true)
        }
        плитки.removeAll { $0.id == id }
        if плитки.isEmpty {
            заполненоИИ = false
            статусИИ = nil
        }
    }

    /// Не private: постер-обложка услуги (PostingService.swift) грузится тем же путём.
    func загрузить(_ id: UUID) async {
        guard let место = плитки.firstIndex(where: { $0.id == id }), let картинка = плитки[место].картинка else { return }
        плитки[место].грузится = true
        плитки[место].ошибка = nil
        плитки[место].этап = 1
        let основное = ОбработкаФото.dataURL(картинка)
        let мини = плитки[место].миниатюра.map { $0.isEmpty ? "" : ОбработкаФото.dataURL($0) } ?? ""
        var код = 0
        var ответ: [String: Any] = [:]
        do {
            var повторили = false
            while true {
                let токен = try await МоиОбъявленияAPI.токенСейчас()
                if токен.isEmpty {
                    ответ = ["ok": false, "error": "auth"]
                    break
                }
                let итог = try await КабинетСайта.загрузитьФото(картинка: основное, миниатюра: мини, токен: токен)
                код = итог.код
                ответ = итог.json
                if МоиОбъявленияAPI.строка(ответ["error"]) == "csrf" && !повторили {
                    повторили = true
                    МоиОбъявленияAPI.забыть()
                    continue
                }
                break
            }
        } catch {
            код = 0
            ответ = ["ok": false, "error": ""]
        }
        guard let сейчас = плитки.firstIndex(where: { $0.id == id }) else { return }
        typealias A = МоиОбъявленияAPI
        let адрес = A.строка(ответ["url"])
        if A.да(ответ["ok"]) && !адрес.isEmpty {
            плитки[сейчас].url = адрес
            плитки[сейчас].грузится = false
            плитки[сейчас].картинка = nil
            плитки[сейчас].миниатюра = nil
            return
        }
        if A.да(ответ["prohibited"]) {
            плитки.remove(at: сейчас)
            сообщение = Self.окноЗапрета(ответ)
            return
        }
        плитки[сейчас].грузится = false
        if A.нетСессии(ответ) {
            плитки[сейчас].ошибка = т("ph_fail_unknown")
            войти = true
            return
        }
        let почему = причинаСбоя(код: код, ошибка: A.строка(ответ["error"]))
        плитки[сейчас].ошибка = почему
        показать(т("ph_fail_toast").replacingOccurrences(of: "{why}", with: почему))
    }

    /// phFailShort: текст сервера (не длиннее 38) или по коду: нет связи, файл велик, сервер отклонил, ошибка сервера.
    private func причинаСбоя(код: Int, ошибка: String) -> String {
        let текст = ошибка.trimmingCharacters(in: .whitespacesAndNewlines)
        if !текст.isEmpty && !КабинетСайта.машинныйКод(текст) {
            return текст.count > 38 ? String(текст.prefix(36)) + "…" : текст
        }
        switch код {
        case 0: return т("ph_fail_net")
        case 413: return т("ph_fail_big")
        case 403, 406, 429: return т("ph_fail_block") + " · " + String(код)
        case 500...599: return т("ph_fail_srv") + " · " + String(код)
        default: return "HTTP " + String(код)
        }
    }

    /// showProhibitedWarning сайта — те же тексты, что у «Моих объявлений».
    static func окноЗапрета(_ j: [String: Any]) -> СообщениеПодачи {
        typealias A = МоиОбъявленияAPI
        let т = МоиОбъявленияText.т
        let метка = A.строка(j["cat_label"])
        let категория = метка.isEmpty ? т("prh_cat") : метка
        if A.да(j["soft"]) {
            return СообщениеПодачи(заголовок: т("prh_soft_t"), текст: String(format: т("prh_soft_b"), категория))
        }
        if A.да(j["first"]) {
            return СообщениеПодачи(заголовок: т("prh_t"), текст: String(format: т("prh_first"), категория))
        }
        let минут = A.целое(j["block_min"])
        if минут > 0 {
            var текст = String(format: т("prh_blk"), категория, A.строка(j["block_label"]))
            if минут < 10080 { текст += " " + т("prh_blk_more") }
            return СообщениеПодачи(заголовок: т("prh_blk_t"), текст: текст)
        }
        return СообщениеПодачи(заголовок: т("prh_t"), текст: String(format: т("prh_now"), категория))
    }

    // MARK: - Справочники мастеров (только чтение)

    /// GET /api/auto_models.php?brands=1 → {groups:[{region, brands:[{brand, models}]}]} — марки группами по порядку
    /// сайта (_awLoadBrands); не ответил — пусто, мастер предложит вписать марку.
    func загрузитьМарки() async {
        guard маркиАвто.isEmpty else { return }
        маркиНеДоступны = false
        typealias A = МоиОбъявленияAPI
        guard let j = try? await A.получить("/api/auto_models.php?brands=1", отКорня: true), A.да(j["ok"]) else {
            маркиНеДоступны = true
            return
        }
        var список: [String] = []
        var группы: [ГруппаМарок] = []
        var были = Set<String>()
        for группа in (j["groups"] as? [Any]) ?? [] {
            guard let г = группа as? [String: Any] else { continue }
            var свои: [String] = []
            for марка in (г["brands"] as? [Any]) ?? [] {
                let имя = A.строка((марка as? [String: Any])?["brand"]).trimmingCharacters(in: .whitespaces)
                if !имя.isEmpty && !были.contains(имя) {
                    были.insert(имя)
                    список.append(имя)
                    свои.append(имя)
                }
            }
            guard !свои.isEmpty else { continue }
            let регион = A.строка(г["region"]).trimmingCharacters(in: .whitespaces)
            let подпись = регион.isEmpty ? МастерПодачиText.т("aw_others") : регион
            if let был = группы.firstIndex(where: { $0.регион == подпись }) {
                группы[был] = ГруппаМарок(регион: подпись, марки: группы[был].марки + свои)
            } else {
                группы.append(ГруппаМарок(регион: подпись, марки: свои))
            }
        }
        маркиНеДоступны = список.isEmpty
        маркиАвто = список
        группыМарок = группы
    }

    /// GET /api/auto_models.php?brand=<марка> → {models:[{name, body, gens:[{name, from, to}]}]}; кэш — как _AW_MODELS.
    func моделиМарки(_ марка: String) async -> [МодельАвто] {
        let чистая = марка.trimmingCharacters(in: .whitespaces)
        guard !чистая.isEmpty else { return [] }
        if let были = кэшМоделейАвто[чистая] { return были }
        typealias A = МоиОбъявленияAPI
        let код = чистая.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? чистая
        guard let j = try? await A.получить("/api/auto_models.php?brand=" + код, отКорня: true), A.да(j["ok"]) else {
            return []
        }
        let модели = ((j["models"] as? [Any]) ?? []).compactMap { запись -> МодельАвто? in
            guard let м = запись as? [String: Any] else { return nil }
            let имя = A.строка(м["name"])
            guard !имя.isEmpty else { return nil }
            let поколения = ((м["gens"] as? [Any]) ?? []).compactMap { п -> ПоколениеАвто? in
                guard let г = п as? [String: Any] else { return nil }
                let название = A.строка(г["name"])
                guard !название.isEmpty else { return nil }
                return ПоколениеАвто(имя: название, с: A.целое(г["from"]), по: A.целое(г["to"]))
            }
            let кузов = ((м["body"] as? [Any]) ?? []).map { A.строка($0) }.filter { !$0.isEmpty }
            return МодельАвто(имя: имя, поколения: поколения, кузов: кузов)
        }
        кэшМоделейАвто[чистая] = модели
        return модели
    }

    /// Модели выбранной марки формы (поколения на шаге «Характеристики»).
    func загрузитьМодели(_ марка: String) async {
        моделиАвто = []
        let чистая = марка.trimmingCharacters(in: .whitespaces)
        let модели = await моделиМарки(чистая)
        guard !чистая.isEmpty, форма.бренд.trimmingCharacters(in: .whitespaces) == чистая else { return }
        моделиАвто = модели
    }

    /// GET /api/parts_types.php?syn=1 → {groups:[{items:[{k, n, s}]}]} — «Что за деталь».
    func загрузитьТипыЗапчастей() async {
        guard типыЗапчастей.isEmpty else { return }
        typealias A = МоиОбъявленияAPI
        guard let j = try? await A.получить("/api/parts_types.php?syn=1", отКорня: true) else { return }
        var список: [ВариантПоля] = []
        for группа in (j["groups"] as? [Any]) ?? [] {
            guard let г = группа as? [String: Any] else { continue }
            for пункт in (г["items"] as? [Any]) ?? [] {
                guard let п = пункт as? [String: Any] else { continue }
                let ключ = A.строка(п["k"])
                if !ключ.isEmpty { список.append(ВариантПоля(ключ: ключ, подпись: A.строка(п["n"]))) }
            }
        }
        типыЗапчастей = список
    }

    // MARK: - Kliko AI: «Распознать» (recognize, paid: 0) — только по нажатию

    var распознаваниеДоступно: Bool {
        Config.распознаваниеВПодаче && !правка && страница.ключИИ && !страница.иИЗаблокирован
            && режим != .недвижимость && режим != .услуга && !готовыеФото.isEmpty
    }

    func распознать() {
        guard !распознаём else {
            показать(т("aiu_busy"))
            return
        }
        let адреса = Array(готовыеФото.prefix(5))
        guard !адреса.isEmpty else { return }
        распознаём = true
        шагРаспознавания = 1
        статусИИ = nil
        номерРаспознавания += 1
        let мой = номерРаспознавания
        let тело: [String: Any] = ["mode": "add", "image_urls": адреса, "hint": форма.подсказка, "cat": форма.раздел,
                                   "atype": форма.тип, "entry": форма.плитка, "also_sell": форма.тожеПродаю, "paid": 0]
        Task { @MainActor in
            let шаги = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard let модель = self, модель.распознаём, мой == модель.номерРаспознавания else { return }
                модель.шагРаспознавания = 2
            }
            let итог = await self.сПределом(55) {
                try await МоиОбъявленияAPI.отправить("cabinet.php?action=recognize", тело: тело)
            }
            шаги.cancel()
            /* «Заполнить вручную» (airecManual сайта): запуск отменён — ответ никуда не ложится. */
            guard мой == self.номерРаспознавания else { return }
            switch итог {
            case .ответ(let j):
                self.разобратьРаспознавание(j)
            case .долго:
                self.статусИИ = self.т("ai_timeout")
            case .сбой:
                self.статусИИ = self.т("conn_err")
            }
            if self.шагРаспознавания < 4 { self.распознаём = false }
        }
    }

    /// «Заполнить вручную» в окне распознавания (airecManual): окно прочь, запуск забыт, с «Фото» — дальше.
    func отменитьРаспознавание() {
        номерРаспознавания += 1
        распознаём = false
        шагРаспознавания = 0
        /* Короткий путь: человек заполнит сам — «Далее» с камеры второй раз не распознаёт. */
        if быстрый { быстроРаспознано = true }
        if шаг == .фото { далее() }
    }

    enum ИтогЗапроса {
        case ответ([String: Any])
        case сбой
        case долго
    }

    /// Ящик для ответа: запрос кладёт, ожидание забирает. Всё на главном потоке — без передачи между потоками.
    final class ЯщикОтвета {
        var итог: ИтогЗапроса? = nil
    }

    /// AbortController сайта (55 с): не дождались — «долго», поздний ответ никуда не ляжет.
    func сПределом(_ секунд: Int, _ работа: @escaping @MainActor () async throws -> [String: Any]) async -> ИтогЗапроса {
        let ящик = ЯщикОтвета()
        Task { @MainActor in
            do {
                let j = try await работа()
                if ящик.итог == nil { ящик.итог = .ответ(j) }
            } catch {
                if ящик.итог == nil { ящик.итог = .сбой }
            }
        }
        var прошло = 0
        while ящик.итог == nil && прошло < секунд * 4 {
            try? await Task.sleep(nanoseconds: 250_000_000)
            прошло += 1
        }
        if let готово = ящик.итог { return готово }
        ящик.итог = .долго
        return .долго
    }

    private func разобратьРаспознавание(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        if A.да(j["ok"]), let поля = j["fields"] as? [String: Any] {
            шагРаспознавания = 3
            if A.да(j["from_cache"]) {
                let заметка = A.строка(j["notice"])
                показать(заметка.isEmpty ? т("ai_cache") : заметка)
            }
            let было = форма.раздел
            /* Авто: марку, модель и поколение человек выбрал в мастере — Kliko AI их не трогает (владелец: «AI не
               должен перезаписывать выбранные бренд и модель»); год, пробег, объём, коробку и топливо дописывает только
               в пустые. Марка без мастера — к написанию справочника (autoWizFromAi сайта). */
            let авто = режим == .авто
            let маркаВыбрана = авто && !форма.бренд.trimmingCharacters(in: .whitespaces).isEmpty
            заполняем = true
            var ф = форма
            if маркаВыбрана {
                if ф.cpu.isEmpty { ф.cpu = A.строка(поля["cpu"]) }
                if ф.gpu.isEmpty { ф.gpu = A.строка(поля["gpu"]) }
                if ф.ram.isEmpty { ф.ram = A.строка(поля["ram"]) }
                if ф.storage.isEmpty { ф.storage = A.строка(поля["storage"]) }
                if ф.year.isEmpty { ф.year = A.строка(поля["year"]) }
            } else {
                ф.бренд = авто ? каноническаяМарка(A.строка(поля["brand"])) : A.строка(поля["brand"])
                ф.cpu = A.строка(поля["cpu"])
                ф.gpu = A.строка(поля["gpu"])
                ф.ram = A.строка(поля["ram"])
                ф.storage = A.строка(поля["storage"])
                ф.year = A.строка(поля["year"])
            }
            ф.описание = A.строка(поля["description"])
            if !авто { ф.название = Self.полноеИмя(A.строка(поля["brand"]), A.строка(поля["title"])) }
            ф.состояние = A.строка(поля["condition"]) == "new" ? "new" : "used"
            форма = ф
            заполняем = false
            if авто {
                /* Название авто — только из параметров (autoTitleCompose), не из ответа Kliko AI. */
                let собранное = ПределыПодачи.обрезать(составитьНазваниеАвто(), ПределыПодачи.название)
                if !собранное.isEmpty && форма.название != собранное { форма.название = собранное }
            }
            var новый = A.строка(поля["category"])
            /* Авто остаётся транспортом: раздел не из транспорта (или запчасти) Kliko AI не подставляет. */
            if авто && (!справочники.внутри(новый, ["transport"]) || справочники.внутри(новый, ["auto-parts"])) {
                новый = ""
            }
            if !новый.isEmpty && справочники.разделы[новый] != nil {
                выбратьРаздел(новый)
                if !было.isEmpty && было != новый {
                    let старое = справочники.имя(было)
                    let новое = справочники.имя(новый)
                    if !старое.isEmpty && !новое.isEmpty {
                        вопрос = ВопросПодачи(заголовок: т("ai_cat_swap_t"),
                                              текст: т("ai_cat_swap_s").replacingOccurrences(of: "{new}", with: новое)
                                                .replacingOccurrences(of: "{old}", with: старое),
                                              да: т("ai_cat_swap_ok"),
                                              нет: т("ai_cat_swap_back").replacingOccurrences(of: "{old}", with: старое),
                                              действие: {},
                                              отказ: { [weak self] in
                                                  self?.выбратьРаздел(было)
                                                  self?.показать(ПодачаText.т("ai_cat_swap_back_ok"))
                                              })
                    }
                }
            }
            let середина = A.целое(поля["price_mid"])
            if середина > 0 {
                let низ = A.целое(поля["price_low"])
                let верх = A.целое(поля["price_high"])
                подсказкаЦены = ПодсказкаЦены(подпись: т("ai_estimate"),
                                              низ: низ > 0 ? низ : Int((Double(середина) * 0.85).rounded()),
                                              середина: середина,
                                              верх: верх > 0 ? верх : Int((Double(середина) * 1.2).rounded()))
            }
            шагРаспознавания = 4
            заполненоИИ = true
            let мой = номерРаспознавания
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard let модель = self, мой == модель.номерРаспознавания else { return }
                модель.распознаём = false
                модель.статусИИ = модель.т("airec_done_l")
                if модель.быстрый {
                    модель.послеРаспознаванияБыстро()
                } else if модель.шаг == .фото {
                    модель.далее()
                }
            }
            return
        }
        if A.нетСессии(j) {
            войти = true
            return
        }
        if A.да(j["slots_full"]) {
            /* Места нет: одно действие — освободить место; платное — только App Store при Config.цифровыеПокупки. */
            вопросОМесте(верификация: false)
            return
        }
        let причина = A.строка(j["ai_reason"])
        if причина == "need_verify" {
            вопрос = ВопросПодачи(заголовок: т("verify_t"), текст: т("ai_need_verify"), да: т("held_verify_go"),
                                  нет: т("later"), действие: { [weak self] in self?.открытьСтраницу = "cabinet.php?go=verify" })
            return
        }
        if причина == "need_paid" || A.да(j["need_payment"]) {
            /* Пакет Kliko AI и платный разбор в приложении не продаются: только сведения. */
            статусИИ = т("ai_need_paid")
            return
        }
        if A.да(j["ai_off"]) {
            let ошибка = A.строка(j["error"])
            статусИИ = (ошибка.isEmpty ? т("ai_off") : ошибка) + " — " + т("ai_fill_manual")
            return
        }
        статусИИ = т("ai_fail")
    }

    /// autoWizFromAi сайта: марку из ответа — к написанию справочника («тойота» → Toyota, «Mercedes» → Mercedes-Benz).
    func каноническаяМарка(_ марка: String) -> String {
        let чистая = марка.trimmingCharacters(in: .whitespaces)
        guard !чистая.isEmpty, !маркиАвто.isEmpty else { return чистая }
        func ключ(_ с: String) -> String {
            String(с.lowercased().filter { !" -_.".contains($0) })
        }
        let русские: [String: String] = [
            "тойота": "Toyota", "лексус": "Lexus", "ниссан": "Nissan", "хонда": "Honda", "мазда": "Mazda",
            "митсубиси": "Mitsubishi", "мицубиси": "Mitsubishi", "субару": "Subaru", "сузуки": "Suzuki",
            "хендай": "Hyundai", "хёндай": "Hyundai", "хундай": "Hyundai", "киа": "Kia", "дэу": "Daewoo",
            "мерседес": "Mercedes-Benz", "мерседесбенц": "Mercedes-Benz", "бмв": "BMW", "ауди": "Audi",
            "фольксваген": "Volkswagen", "порше": "Porsche", "опель": "Opel", "шкода": "Skoda", "вольво": "Volvo",
            "рено": "Renault", "пежо": "Peugeot", "шевроле": "Chevrolet", "форд": "Ford", "лада": "Lada",
            "ваз": "Lada", "уаз": "UAZ", "газ": "GAZ", "чери": "Chery", "хавал": "Haval", "джили": "Geely",
            "джилли": "Geely", "чанган": "Changan"
        ]
        func найти(_ слово: String) -> String? {
            var к = ключ(слово)
            if let р = русские[к] { к = ключ(р) }
            return маркиАвто.first(where: { ключ($0) == к })
        }
        if let точно = найти(чистая) { return точно }
        let первое = чистая.split(separator: " ").first.map(String.init) ?? чистая
        return найти(первое) ?? чистая
    }

    /// cabFullName сайта: «бренд название», если название бренда ещё не содержит.
    static func полноеИмя(_ бренд: String, _ название: String) -> String {
        let б = бренд.trimmingCharacters(in: .whitespaces)
        let н = название.trimmingCharacters(in: .whitespaces)
        if б.isEmpty { return н }
        if н.isEmpty { return б }
        return н.lowercased().contains(б.lowercased()) ? н : б + " " + н
    }

    // MARK: - Отправка новой (doSubmit → showPublishConfirm → _doSubmitReal)

    /// «Выставить на продажу»: проверки настоящего doSubmit, потом окно «Проверьте перед публикацией».
    func выставить() {
        /* Короткий путь с камеры: раздел мог не определиться — его выбирают на «Проверьте». */
        if быстрый && !правка && форма.раздел.isEmpty {
            пометить("category", т("need_cat"))
            return
        }
        if форма.название.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if режим == .авто {
                /* doSubmit сайта: «Заполните параметры автомобиля — название соберётся само» и сразу мастер авто. */
                пометить("auto", т("need_auto"))
                шаг = .характеристики
                мастер = .авто(кузов: false)
            } else {
                пометить("title", т("need_title"))
                шаг = .данные
            }
            return
        }
        if форма.описание.trimmingCharacters(in: .whitespacesAndNewlines).count < 10 {
            пометить("desc", т("need_desc"))
            шаг = .данные
            return
        }
        if let ошибка = ошибкаЦены() {
            пометить("price", ошибка)
            шаг = .цена
            return
        }
        guard проверитьГород() else { return }
        if let ошибка = ошибкаЧасов() {
            пометить("hours", ошибка)
            шаг = .адрес
            return
        }
        /* doSubmit сайта: у услуги перед окном проверки — svcPosterGenerateCover (без своих фото — первым фото). */
        if нужнаОбложкаУслуги {
            Task { @MainActor in
                _ = await self.сделатьОбложкуУслуги()
                self.подтверждение = true
            }
            return
        }
        подтверждение = true
    }

    /// geoRequire: «Не хватает города» — тот же текст сайта строкой под полем города, мастер сам ведёт на «Адрес».
    private func проверитьГород() -> Bool {
        guard форма.город.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        пометить("city", т("form_geo_required"))
        шаг = .адрес
        return false
    }

    /// pcPublish: «Вещь работает?» обязателен; фото ещё грузятся — «секунду» (sniCheckThenSubmit).
    func опубликовать() {
        if нужнаИсправность && форма.работает.isEmpty {
            пометить("works", т("wrk_need_s"))
            return
        }
        if фотоГрузятся {
            показать(т("photos_busy"))
            return
        }
        подтверждение = false
        Task { @MainActor in await self.отправитьНовое() }
    }

    private func отправитьНовое() async {
        guard !отправляем else { return }
        отправляем = true
        defer { отправляем = false }
        let тело = телоПодачи()
        do {
            let j = try await МоиОбъявленияAPI.отправить("cabinet.php?action=submit", тело: тело)
            разобратьПодачу(j)
        } catch {
            показать(т("no_conn"))
        }
    }

    /// Тело submit — поля _doSubmitReal по порядку (карта §2.4.1). Опт, вариации, раздел магазина мастер не
    /// показывает — они уходят «пустыми», как у нового объявления сайта без них.
    func телоПодачи() -> [String: Any] {
        let ф = форма
        var характеристики: [String: String] = ["cpu": ф.cpu, "gpu": ф.gpu, "ram": ф.ram, "storage": ф.storage, "year": ф.year]
        if режим == .недвижимость { характеристики = зеркалоНедвижимости() }
        let аренда = ф.аренда
        var тело: [String: Any] = [
            "brand": ф.бренд.trimmingCharacters(in: .whitespaces),
            "title": ф.название.trimmingCharacters(in: .whitespacesAndNewlines),
            "price": ценаЧислом,
            "price_negotiable": ф.торг,
            "condition": ф.состояние,
            "category": ф.раздел.isEmpty ? "other" : ф.раздел,
            "broken": нужнаИсправность && ф.работает == "bad",
            "escrow_off": !ф.гарант,
            "model": ф.модель.trimmingCharacters(in: .whitespaces),
            "import_url": "",
            "gen": ф.поколение.trimmingCharacters(in: .whitespaces),
            "for_rent": аренда,
            "rent_price_day": аренда ? ставкаЧислом : 0,
            "rent_deposit": аренда ? залогЧислом : 0,
            "rent_min_days": аренда ? (Int(ф.минСрок) ?? 1) : 1,
            "rent_period": аренда ? ф.период : "day",
            "rent_kit": ф.комплект,
            "also_sell": ф.тожеПродаю,
            "for_exchange": ф.обмен,
            "region": ф.регион.trimmingCharacters(in: .whitespaces),
            "city": ф.город.trimmingCharacters(in: .whitespaces),
            "district": ф.район.trimmingCharacters(in: .whitespaces),
            "address": ф.адрес.trimmingCharacters(in: .whitespaces),
            "lat": ф.lat,
            "lon": ф.lon,
            "description": ф.описание.trimmingCharacters(in: .whitespacesAndNewlines),
            "wholesale": false,
            "wholesale_tiers": [Any](),
            "stock": Int(ф.склад) ?? 0,
            "variants": [Any](),
            "shop_section": "",
            "sn_hidden": false,
            "top_preset": "",
            "vin": vinРазрешён ? ф.vin.trimmingCharacters(in: .whitespaces) : "",
            "images": готовыеФото,
            "shot_slots": [String: String]()
        ]
        for (ключ, значение) in характеристики {
            тело[ключ] = значение.trimmingCharacters(in: .whitespaces)
        }
        for (ключ, значение) in часыЗапроса() { тело[ключ] = значение }
        if let realty = телоНедвижимости() {
            тело["realty"] = realty
        } else {
            тело["realty"] = NSNull()
        }
        if let parts = телоЗапчасти() {
            тело["parts"] = parts
        } else {
            тело["parts"] = NSNull()
        }
        return тело
    }

    /// hoursPayload: режим, а «с» и «до» — только у «range».
    private func часыЗапроса() -> [String: String] {
        let режимЧасов = форма.часы
        let диапазон = режимЧасов == "range"
        return ["hours_mode": режимЧасов, "hours_from": диапазон ? форма.часыС : "",
                "hours_to": диапазон ? форма.часыДо : ""]
    }

    /// REALTY_DATA + plan: значения строками, переключатели — true/false, как _rw2 сайта.
    private func телоНедвижимости() -> [String: Any]? {
        guard режим == .недвижимость, !форма.вид.isEmpty else { return nil }
        var итог: [String: Any] = ["deal": форма.сделка, "kind": форма.вид, "plan": ""]
        for (ключ, значение) in форма.недвижимость where !значение.isEmpty { итог[ключ] = значение }
        for (ключ, флаг) in форма.флагиНедвижимости where флаг { итог[ключ] = true }
        return итог
    }

    /// PARTS_DATA: {kind, …} без пустых значений (partsWizApply).
    private func телоЗапчасти() -> [String: Any]? {
        guard режим == .запчасти else { return nil }
        var итог: [String: Any] = ["kind": видЗапчасти]
        for (ключ, значение) in форма.запчасть where !значение.trimmingCharacters(in: .whitespaces).isEmpty {
            итог[ключ] = значение.trimmingCharacters(in: .whitespaces)
        }
        return итог.count > 1 ? итог : nil
    }

    /// Разбор ответа submit — §2.5.2, в том же порядке, что у сайта.
    private func разобратьПодачу(_ j: [String: Any]) {
        typealias A = МоиОбъявленияAPI
        if A.да(j["ok"]) {
            let id = A.строка(j["id"])
            var плашки: [String] = []
            if A.да(j["top_skipped"]) {
                плашки.append(т("top_skipped"))
            } else if let топ = j["top_applied"] as? NSNumber {
                плашки.append(топ.boolValue ? т("top_applied") : т("top_failed"))
            }
            if !id.isEmpty { применитьДополнительно(id) }
            if !правка { отметитьПубликацию() }
            ПодачаМодель.стеретьЧерновик()
            плашкаПосле = плашки.joined(separator: "\n")
            топПослеПодачи = (j["top_applied"] as? NSNumber)?.boolValue ?? false
            let авто = A.строка(j["auto"])
            let чисто = авто == "approved" && !A.да(j["held"]) && !A.да(j["held_verify"]) && !A.да(j["no_phone"])
            if !чисто && (A.да(j["held_verify"]) || A.да(j["need_verify"]) || A.да(j["no_phone"])) {
                итог = .ждётВерификации(A.строка(j["error"]))
            } else if A.да(j["held"]) {
                let текст = A.строка(j["msg"])
                итог = .неактивные(текст: текст.isEmpty ? т("held_d") : текст, верификация: A.да(j["verify_required"]))
            } else if A.да(j["ai_blocked"]) {
                итог = .сохраненоИИ(часы: A.строка(j["hours"]))
            } else if авто == "approved" {
                итог = .опубликовано(id: id)
            } else if авто == "rejected" {
                let причина = A.строка(j["reason"])
                итог = .отклонено(причина.isEmpty ? т("mod_rej_d") : причина)
            } else {
                итог = .наПроверке(id: id)
            }
            return
        }
        if A.нетСессии(j) {
            войти = true
            return
        }
        if A.да(j["slots_full"]) {
            /* Владелец (обход новичком): простое предложение вместо текста сервера про «слоты» и одно действие. */
            вопросОМесте(верификация: A.да(j["verify_required"]))
            return
        }
        if A.да(j["prohibited"]) {
            сообщение = Self.окноЗапрета(j)
            return
        }
        if A.да(j["need_topup"]) {
            let текст = A.строка(j["error"])
            показать(текст.isEmpty ? т("need_topup") : текст)
            return
        }
        показать(String(format: т("err_prefix"), текстОшибки(j)))
    }

    /**
     Нет места для нового объявления: с верификацией — «Подтвердите личность через eGov», иначе — «Освободить место»
     («Мои объявления», черновик остаётся). «Расширить лимит» — окно App Store, только при Config.цифровыеПокупки.
     */
    private func вопросОМесте(верификация: Bool) {
        let купить: String? = Config.цифровыеПокупки ? т("limit_more") : nil
        let покупка: (() -> Void)? = Config.цифровыеПокупки ? { ЛистУслугиApple.показать(.слоты) } : nil
        if верификация {
            вопрос = ВопросПодачи(заголовок: т("limit_t"), текст: т("limit_d_verify"), да: т("verify_egov_1m"),
                                  нет: т("later"),
                                  действие: { [weak self] in self?.открытьСтраницу = "cabinet.php?go=verify" },
                                  ещё: купить, ещёДействие: покупка)
        } else {
            вопрос = ВопросПодачи(заголовок: т("limit_t"), текст: т("limit_d"), да: т("free_place"), нет: т("later"),
                                  действие: { [weak self] in self?.освободитьМесто() },
                                  ещё: купить, ещёДействие: покупка)
        }
    }

    /// «Освободить место»: черновик сохранить, мастер закрыть — «Мои объявления», опубликованные.
    func освободитьМесто() {
        итог = nil
        записатьЧерновик()
        закрытьМастер(вкладка: .published)
    }

    /// «Ошибка: {error|попробуйте ещё раз}» — машинный код человеку не показываем (ulxErr).
    private func текстОшибки(_ j: [String: Any]) -> String {
        let ошибка = МоиОбъявленияAPI.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if ошибка.isEmpty || КабинетСайта.машинныйКод(ошибка) { return т("try_again") }
        return ошибка
    }

    /// cfgReplayToItem: настройки «Дополнительно» — по новому id; не вышло — один повтор через 1,5 с.
    private func применитьДополнительно(_ id: String) {
        let ф = форма
        var запросы: [(хвост: String, тело: [String: Any], что: String)] = []
        if ф.рассрочка || ф.кредит {
            let тело: [String: Any] = ["item_id": id, "installment": ф.рассрочка, "installment_mode": "bank",
                                       "installment_commission": 10, "installment_banks": [String](),
                                       "credit": ф.кредит, "credit_rate": 25, "credit_banks": [String]()]
            запросы.append((хвост: "save_payment", тело: тело, что: т("cfg_what_pay")))
        }
        if ф.доставкаЗадана {
            let тело: [String: Any] = ["item_id": id, "ship_free": ф.доставкаБесплатно, "ship_days": ф.доставкаДней,
                                       "ship_carrier": "", "ship_scope": "all", "ship_regions": [String]()]
            запросы.append((хвост: "save_delivery", тело: тело, что: т("cfg_what_del")))
        }
        if ф.доверияЗадано {
            var знаки: [String: Bool] = [:]
            for ключ in ф.знаки { знаки[ключ] = true }
            let тело: [String: Any] = ["item_id": id, "warranty_days": ф.гарантияДней, "trust": знаки]
            запросы.append((хвост: "save_trust", тело: тело, что: т("cfg_what_trust")))
        }
        guard !запросы.isEmpty else { return }
        let неВышлоШаблон = т("cfg_replay_fail")
        let урезаноТекст = т("wr_clamped")
        Task { @MainActor in
            var неВышло: [String] = []
            var урезано = false
            for запрос in запросы {
                let хвост = "cabinet.php?action=" + запрос.хвост
                var j = try? await МоиОбъявленияAPI.отправить(хвост, тело: запрос.тело)
                let первыйУдачен = j.map { МоиОбъявленияAPI.да($0["ok"]) } ?? false
                if !первыйУдачен {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    j = try? await МоиОбъявленияAPI.отправить(хвост, тело: запрос.тело)
                }
                if let ответ = j, МоиОбъявленияAPI.да(ответ["ok"]) {
                    if МоиОбъявленияAPI.да(ответ["clamped"]) { урезано = true }
                } else {
                    неВышло.append(запрос.что)
                }
            }
            if !неВышло.isEmpty {
                МоиОбъявленияМодель.shared.показать(неВышлоШаблон.replacingOccurrences(of: "{what}",
                                                                                     with: неВышло.joined(separator: ", ")))
            } else if урезано {
                МоиОбъявленияМодель.shared.показать(урезаноТекст)
            }
        }
    }

    // MARK: - Правка (_doEditSaveReal → edit_item)

    /// «Сохранить изменения»: цена, город, «Вещь работает?», режим работы — как у сайта, потом edit_item.
    func сохранить() {
        guard !отправляем else { return }
        if let ошибка = ошибкаЦены() {
            пометить("price", ошибка)
            шаг = .цена
            return
        }
        guard проверитьГород() else { return }
        if нужнаИсправность && форма.работает.isEmpty {
            пометить("works", т("wrk_need_s"))
            шаг = .цена
            return
        }
        if let ошибка = ошибкаЧасов() {
            пометить("hours", ошибка)
            шаг = .адрес
            return
        }
        if фотоГрузятся {
            показать(т("photos_busy"))
            return
        }
        Task { @MainActor in await self.отправитьПравку() }
    }

    /// Тело edit_item (§2.4.2): поля формы плюс всё, чего мастер не показывает, — из записи my_items как было.
    func телоПравки() -> [String: Any] {
        typealias A = МоиОбъявленияAPI
        let ф = форма
        let з = исходник
        var характеристики: [String: String] = ["cpu": ф.cpu, "gpu": ф.gpu, "ram": ф.ram, "storage": ф.storage, "year": ф.year]
        if режим == .недвижимость && !ф.вид.isEmpty { характеристики = зеркалоНедвижимости() }
        let аренда = ф.аренда
        let фото = готовыеФото
        var метки: [String: Any] = [:]
        if let были = з["shot_slots"] as? [String: Any] {
            for (адрес, метка) in были where фото.contains(адрес) { метки[адрес] = метка }
        }
        let склад = ф.склад.isEmpty ? A.целое(з["stock"]) : (Int(ф.склад) ?? 0)
        var тело: [String: Any] = [
            "id": номерПравки,
            "price": ценаЧислом,
            "price_negotiable": ф.торг,
            "condition": ф.состояние,
            "broken": нужнаИсправность && ф.работает == "bad",
            "escrow_off": !ф.гарант,
            "category": ф.раздел.isEmpty ? "other" : ф.раздел,
            "images": фото,
            "shot_slots": метки,
            "also_sell": ф.тожеПродаю,
            "sn_hidden": A.да(з["sn_hidden"]),
            "for_rent": аренда,
            "rent_price_day": аренда ? ставкаЧислом : 0,
            "rent_deposit": аренда ? залогЧислом : 0,
            "rent_min_days": аренда ? (Int(ф.минСрок) ?? 1) : 1,
            "rent_period": аренда ? ф.период : "day",
            "rent_kit": ф.комплект,
            "wholesale": A.да(з["wholesale"]),
            "wholesale_tiers": (з["wholesale_tiers"] as? [Any]) ?? [Any](),
            "stock": склад,
            "variants": ф.состояние == "new" ? ((з["variants"] as? [Any]) ?? [Any]()) : [Any](),
            "shop_section": A.строка(з["shop_section"]),
            "for_exchange": ф.обмен,
            "region": ф.регион.trimmingCharacters(in: .whitespaces),
            "city": ф.город.trimmingCharacters(in: .whitespaces),
            "district": ф.район.trimmingCharacters(in: .whitespaces),
            "address": ф.адрес.trimmingCharacters(in: .whitespaces),
            "lat": ф.lat,
            "lon": ф.lon,
            "brand": ф.бренд.trimmingCharacters(in: .whitespaces),
            "model": ф.модель.trimmingCharacters(in: .whitespaces),
            "gen": ф.поколение.trimmingCharacters(in: .whitespaces),
            "description": ф.описание.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        let название = ф.название.trimmingCharacters(in: .whitespacesAndNewlines)
        тело["title"] = название.isEmpty ? ф.модель.trimmingCharacters(in: .whitespaces) : название
        for (ключ, значение) in характеристики { тело[ключ] = значение.trimmingCharacters(in: .whitespaces) }
        for (ключ, значение) in часыЗапроса() { тело[ключ] = значение }
        /* vin: только там, где он допустим, и заглавными; иначе поля нет вовсе (undefined у сайта). */
        if vinРазрешён { тело["vin"] = ф.vin.trimmingCharacters(in: .whitespaces).uppercased() }
        /* realty — только у недвижимости с видом; parts сайт в правке не шлёт никогда (§2.4.2) — и мы не шлём. */
        if режим == .недвижимость, let realty = телоНедвижимости() {
            var с = realty
            if let был = з["realty"] as? [String: Any] { с["plan"] = A.строка(был["plan"]) }
            тело["realty"] = с
        }
        return тело
    }

    private func отправитьПравку() async {
        guard !отправляем else { return }
        отправляем = true
        defer { отправляем = false }
        typealias A = МоиОбъявленияAPI
        let id = номерПравки
        do {
            let j = try await A.отправить("cabinet.php?action=edit_item", тело: телоПравки())
            if A.да(j["ok"]) {
                разобратьПравку(j, id: id)
                return
            }
            if A.нетСессии(j) {
                войти = true
                return
            }
            if A.да(j["prohibited"]) {
                сообщение = Self.окноЗапрета(j)
                return
            }
            показать(String(format: т("err_prefix"), текстОшибки(j)))
        } catch {
            показать(т("no_conn"))
        }
    }

    /// Ответ edit_item: итог показывают «Мои объявления» — туда ведёт сайт (showMain) после сохранения.
    private func разобратьПравку(_ j: [String: Any], id: String) {
        typealias A = МоиОбъявленияAPI
        let список = МоиОбъявленияМодель.shared
        let заметка = A.строка(j["notice"])
        закрытьМастер(вкладка: nil)
        if !заметка.isEmpty { список.показать(заметка) }
        if A.да(j["ai_blocked"]) {
            let часы = A.строка(j["hours"])
            список.окно = .блокИИ(часы: часы.isEmpty ? "24" : часы, id: nil)
        } else if A.да(j["need_phone"]) || A.да(j["need_verify"]) {
            список.окно = .верификация(A.строка(j["error"]))
        } else if A.да(j["silent"]) {
            список.показать(т("edit_saved"))
        } else if A.да(j["manual"]) {
            список.показать(т("edit_manual"))
        } else if A.да(j["redacting"]) {
            список.показать(т("edit_redacting"))
        } else if A.строка(j["auto"]) == "approved" {
            список.показать(т("published"))
        } else if A.строка(j["auto"]) == "rejected" {
            let причина = A.строка(j["reason"])
            список.окно = .отклонено(причина.isEmpty ? т("edit_rej_d") : причина)
        } else {
            список.проверитьПослеПравки(id)
        }
    }

    // MARK: - Конец: «Мои объявления»

    /// Итог закрыт — мастер прочь, «Мои объявления» на нужной вкладке (showMain / advSetTab сайта).
    func закрытьМастер(вкладка: ВкладкаОбъявлений?) {
        остановить()
        let плашки = плашкаПосле
        плашкаПосле = ""
        let список = МоиОбъявленияМодель.shared
        if let вкладка { список.вкладка = вкладка }
        ПодачаОкно.shared.цель = nil
        if NativeRouter.доступна(.моиОбъявления) {
            NativeRouter.shared.цель = .моиОбъявления
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            await список.загрузить(страницу: false)
            if !плашки.isEmpty { список.показать(плашки) }
        }
    }
}

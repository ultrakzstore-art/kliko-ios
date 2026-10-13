import SwiftUI
import UIKit

/**
 ПРИМЕРОЧНАЯ — СОСТОЯНИЕ ОКНА (одно на открытое окно, не синглтон; держит его ЭкранПримерочной).

 Шаги: фото (камера с контуром или галерея) → проверка (своё фото, какое фото вещи, согласие) → ожидание (status раз в
 1,5 с, до 90 с) → итог (шторка «Вы / В вещи», Фото, «Поделиться», «Ещё раз», «Удалить фото»). Отказы — готовым текстом
 сервера; отказ своего ИИ — ещё и окном ОкноСвоегоИИ.показатьОтказ. Окно закрыли или нажали «Отменить» — опрос стоит, а
 примерка на сервере удаляется (delete), не дожидаясь суток. Ответ, пришедший после выхода из аккаунта, не принимается.
 */
@MainActor
final class МодельПримерочной: ObservableObject {
    enum Шаг: Hashable {
        case фото, проверка, ждём, готово, отказ, вход, скоро
    }

    let товар: Listing
    @Published private(set) var шаг: Шаг = .фото
    /// Какое фото вещи примерить (photo_index).
    @Published private(set) var номерФото: Int
    @Published private(set) var фотоЧеловека: UIImage? = nil
    /// Человек в кадре по Vision на телефоне; nil — не знаем.
    @Published private(set) var человекВКадре: Bool? = nil
    /// Снимок ужимается и проверяется.
    @Published private(set) var готовим = false
    @Published private(set) var фотоВещи: UIImage? = nil
    @Published private(set) var прогресс = 0
    @Published private(set) var вОчереди = false
    @Published private(set) var итог: UIImage? = nil
    @Published private(set) var отказ: ОтказПримерочной? = nil
    /// Отказ посреди опроса (долго, связь): «Проверить ещё раз» продолжает ту же примерку, а не начинает новую.
    @Published private(set) var продолжаемая = false
    @Published private(set) var удаляем = false
    @Published private(set) var сохраняем = false
    /// Короткая весть внизу окна («Сохранено в Фото»).
    @Published private(set) var весть: String? = nil

    private var адресФото = ""
    private var итогДанные: Data? = nil
    private var задача = ""
    private var опрос: Task<Void, Never>? = nil
    private var запуск: Task<Void, Never>? = nil
    private var подготовка: Task<Void, Never>? = nil
    private var загрузкаВещи: Task<Void, Never>? = nil
    private var поколение: Int
    private var номерВести = 0
    private var закрыто = false

    /// Согласие на обработку фото дано на этом телефоне (кнопка «Согласен, примерить»).
    static let ключСогласия = "kliko.tryon.consent.v1"

    init(товар: Listing, номерФото: Int) {
        self.товар = товар
        let всего = товар.фотоАдреса.count
        self.номерФото = всего > 0 ? min(max(0, номерФото), всего - 1) : 0
        self.поколение = СессияПриложения.shared.поколение
    }

    private func т(_ ключ: String) -> String { ПримерочнаяText.т(ключ) }

    var согласиеДано: Bool { UserDefaults.standard.bool(forKey: Self.ключСогласия) }

    /// Кто обработает фото — для согласия: ai из info (свой ИИ — «ваш ИИ — …»), иначе Kliko AI.
    var ктоОбработает: String {
        guard let с = ГотовностьПримерочной.shared.сведения, !с.ии.isEmpty else { return т("to_ai_kliko") }
        return с.свойИИ ? String(format: т("to_ai_own"), с.ии) : с.ии
    }

    var осталось: Int? { ГотовностьПримерочной.shared.сведения?.осталось }

    // MARK: - Открыли и закрыли

    /// Окно открыли: гость — сразу «Войдите»; фото вещи — для ожидания; сведения и свой ИИ — лениво.
    func открыт() {
        if СессияПриложения.shared.вошёл == false { шаг = .вход }
        загрузитьВещь()
        Task { @MainActor in
            await ГотовностьПримерочной.shared.проверить()
            if СессияПриложения.shared.вошёл != false { await СвойИИМодель.shared.загрузитьЛениво() }
        }
    }

    /// Окно закрыли: всё стоит, примерку на сервере — удалить (фото человека больше не нужно).
    func закрыть() {
        guard !закрыто else { return }
        закрыто = true
        опрос?.cancel()
        запуск?.cancel()
        подготовка?.cancel()
        загрузкаВещи?.cancel()
        забытьЗадачу()
    }

    /// Удалить примерку на сервере, не дожидаясь ответа (страховка — 24 часа на сервере).
    private func забытьЗадачу() {
        let номер = задача
        задача = ""
        guard !номер.isEmpty else { return }
        Task { @MainActor in _ = await ПримерочнаяAPI.удалить(номер) }
    }

    // MARK: - Фото человека

    /// Снимок камеры.
    func принять(_ снимок: UIImage) {
        guard !готовим else { return }
        готовим = true
        подготовка = Task { @MainActor [weak self] in
            let готовое = await Task.detached(priority: .userInitiated) { () -> ФотоПримерочной.Готовое? in
                ФотоПримерочной.подготовить(снимок)
            }.value
            self?.принятьГотовое(готовое)
        }
    }

    /// Фото из галереи (PhotosPicker отдаёт файл).
    func принять(данные: Data) {
        guard !готовим else { return }
        готовим = true
        подготовка = Task { @MainActor [weak self] in
            let готовое = await Task.detached(priority: .userInitiated) { () -> ФотоПримерочной.Готовое? in
                ФотоПримерочной.подготовить(данные)
            }.value
            self?.принятьГотовое(готовое)
        }
    }

    private func принятьГотовое(_ готовое: ФотоПримерочной.Готовое?) {
        готовим = false
        guard !закрыто else { return }
        guard let готовое, let картинка = UIImage(data: готовое.jpeg) else {
            ОткликСайта.предупреждение()
            показатьВесть(т("to_bad_image"))
            return
        }
        адресФото = готовое.адрес
        фотоЧеловека = картинка
        человекВКадре = готовое.человек
        перейти(.проверка)
    }

    func переснять() {
        адресФото = ""
        фотоЧеловека = nil
        человекВКадре = nil
        отказ = nil
        продолжаемая = false
        перейти(.фото)
    }

    func показатьВесть(_ текст: String) {
        номерВести += 1
        let номер = номерВести
        withAnimation(ДвижениеСайта.появление) { весть = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard let self, номер == self.номерВести else { return }
            withAnimation(ДвижениеСайта.уход) { self.весть = nil }
        }
    }

    // MARK: - Фото вещи

    func выбратьФотоВещи(_ номер: Int) {
        guard товар.фотоАдреса.indices.contains(номер), номер != номерФото else { return }
        ОткликСайта.выбор()
        номерФото = номер
        загрузитьВещь()
    }

    /// Фото вещи для ожидания и угла снимка — из того же кэша, что у ленты.
    private func загрузитьВещь() {
        let адреса = товар.фотоАдреса
        guard адреса.indices.contains(номерФото) else { return }
        let номер = номерФото
        let адрес = адреса[номер]
        загрузкаВещи?.cancel()
        загрузкаВещи = Task { @MainActor [weak self] in
            let картинка = await КартинкиЛенты.shared.загрузить(адрес, пикселей: 900, заполнить: false)
            guard let self, !Task.isCancelled, self.номерФото == номер else { return }
            self.фотоВещи = картинка
        }
    }

    // MARK: - Примерка

    /// «Примерить»: согласие запоминается, фото уходит на сервер, дальше — опрос.
    func примерить() {
        guard !адресФото.isEmpty, шаг != .ждём, !закрыто else { return }
        UserDefaults.standard.set(true, forKey: Self.ключСогласия)
        опрос?.cancel()
        запуск?.cancel()
        забытьЗадачу()
        прогресс = 0
        вОчереди = true
        отказ = nil
        продолжаемая = false
        итог = nil
        итогДанные = nil
        перейти(.ждём)
        let фото = адресФото
        let номер = номерФото
        let свой = СвойИИМодель.shared.активен
        let товарID = товар.id
        let моё = СессияПриложения.shared.поколение
        поколение = моё
        запуск = Task { @MainActor [weak self] in
            let ответ = await ПримерочнаяAPI.начать(товар: товарID, фото: фото, номерФото: номер, свой: свой)
            /* Окно закрыли или нажали «Отменить», пока start был в пути: примерка уже заведена — сразу удалить. */
            guard let self, !Task.isCancelled, !self.закрыто else {
                if case .готово(let j) = ответ {
                    let номерЗадачи = МоиОбъявленияAPI.строка(j["job"])
                    if !номерЗадачи.isEmpty { _ = await ПримерочнаяAPI.удалить(номерЗадачи) }
                }
                return
            }
            guard моё == СессияПриложения.shared.поколение else {
                self.показатьВход()
                return
            }
            guard case .готово(let j) = ответ else {
                self.неУдалось(ответ, вОпросе: false)
                return
            }
            let номерЗадачи = МоиОбъявленияAPI.строка(j["job"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !номерЗадачи.isEmpty else {
                self.показатьОтказ(ОтказПримерочной(код: "fail", текст: self.т("to_err_fail")))
                return
            }
            self.задача = номерЗадачи
            if j["left"] != nil { ГотовностьПримерочной.shared.осталось(МоиОбъявленияAPI.целое(j["left"])) }
            self.опрашивать()
        }
    }

    /// «Проверить ещё раз» после «долго» или обрыва связи: та же примерка, ещё 90 с.
    func продолжить() {
        guard !задача.isEmpty else {
            примерить()
            return
        }
        отказ = nil
        продолжаемая = false
        перейти(.ждём)
        опрашивать()
    }

    /// «Отменить» во время ожидания: опрос стоит, примерка удаляется, человек — снова у своего фото.
    func отменить() {
        опрос?.cancel()
        запуск?.cancel()
        забытьЗадачу()
        перейти(адресФото.isEmpty ? .фото : .проверка)
    }

    /// status раз в 1,5 с, до 90 с; связь пропала 4 раза подряд — «Нет соединения» с «Повторить» той же примерки.
    private func опрашивать() {
        опрос?.cancel()
        let номерЗадачи = задача
        let моё = поколение
        опрос = Task { @MainActor [weak self] in
            let начало = Date()
            var сбоев = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if Task.isCancelled { return }
                if Date().timeIntervalSince(начало) > 90 {
                    self?.показатьОтказ(ОтказПримерочной(код: "slow", текст: ПримерочнаяText.т("to_err_slow")),
                                        продолжаемая: true)
                    return
                }
                let ответ = await ПримерочнаяAPI.ход(номерЗадачи)
                guard let self, !Task.isCancelled, !self.закрыто, self.задача == номерЗадачи else { return }
                guard моё == СессияПриложения.shared.поколение else {
                    self.показатьВход()
                    return
                }
                switch ответ {
                case .готово(let j):
                    сбоев = 0
                    let ход = ХодПримерочной(j)
                    switch ход.состояние {
                    case .done:
                        await self.получить(ход.картинка, задача: номерЗадачи)
                        return
                    case .failed:
                        self.неУдалось(ПримерочнаяAPI.разобратьОтказ(j), вОпросе: false)
                        return
                    case .queued, .working:
                        self.принятьХод(ход)
                    }
                case .сеть, .сбой:
                    сбоев += 1
                    if сбоев >= 4 {
                        self.неУдалось(ответ, вОпросе: true)
                        return
                    }
                case .отказ, .нуженВход, .нетСервера:
                    self.неУдалось(ответ, вОпросе: false)
                    return
                }
            }
        }
    }

    /// Ход примерки: проценты не убывают; между опросами полоса сама чуть подтягивается (не выше 92 до done).
    private func принятьХод(_ ход: ХодПримерочной) {
        let вОчередиСейчас = ход.состояние == .queued
        if вОчереди != вОчередиСейчас { вОчереди = вОчередиСейчас }
        let предел = вОчередиСейчас ? 8 : 92
        let новое = max(прогресс, min(ход.прогресс, 99), min(предел, прогресс + 2))
        guard новое != прогресс else { return }
        withAnimation(ДвижениеСайта.прогресс) { прогресс = новое }
    }

    /// done: скачать картинку (две попытки) и показать итог.
    private func получить(_ адрес: URL?, задача номерЗадачи: String) async {
        guard let адрес else {
            показатьОтказ(ОтказПримерочной(код: "fail", текст: т("to_err_fail")))
            return
        }
        withAnimation(ДвижениеСайта.прогресс) { прогресс = max(прогресс, 96) }
        var данные: Data? = nil
        for попытка in 0..<2 where данные == nil {
            if попытка > 0 { try? await Task.sleep(nanoseconds: 800_000_000) }
            данные = await ФотоПримерочной.скачать(адрес)
        }
        guard !закрыто, задача == номерЗадачи else { return }
        guard let данные, let картинка = UIImage(data: данные) else {
            показатьОтказ(ОтказПримерочной(код: "fail", текст: т("to_err_fail")))
            return
        }
        итогДанные = данные
        итог = картинка
        withAnimation(ДвижениеСайта.прогресс) { прогресс = 100 }
        ОткликСайта.успех()
        перейти(.готово)
    }

    // MARK: - Отказы

    private func неУдалось(_ ответ: ПримерочнаяAPI.Ответ, вОпросе: Bool) {
        switch ответ {
        case .готово:
            показатьОтказ(ОтказПримерочной(код: "fail", текст: т("to_err_fail")))
        case .отказ(let о):
            показатьОтказ(о)
        case .нуженВход:
            показатьВход()
        case .нетСервера:
            ГотовностьПримерочной.shared.отметитьНетСервера()
            опрос?.cancel()
            перейти(.скоро)
        case .сеть:
            показатьОтказ(ОтказПримерочной(код: "net", текст: т("to_err_net")), продолжаемая: вОпросе)
        case .сбой:
            показатьОтказ(ОтказПримерочной(код: "fail", текст: т("to_err_fail")), продолжаемая: вОпросе)
        }
    }

    private func показатьОтказ(_ о: ОтказПримерочной, продолжаемая можно: Bool = false) {
        guard !закрыто else { return }
        опрос?.cancel()
        /* Примерка не удалась — её фото на сервере больше не нужны (кроме «продолжить ту же»). */
        if !можно { забытьЗадачу() }
        отказ = о
        продолжаемая = можно
        ОткликСайта.предупреждение()
        перейти(.отказ)
        if let свой = о.свойИИ {
            /* Свой ИИ: окно с «Настройки своего ИИ» и «Выключить свой ИИ» — поверх примерочной. */
            ОкноСвоегоИИ.показатьОтказ(свой)
        }
    }

    private func показатьВход() {
        guard !закрыто else { return }
        опрос?.cancel()
        запуск?.cancel()
        задача = ""
        перейти(.вход)
    }

    /// Вошли из окна примерочной: та же примерка с тем же фото, или камера, если фото ещё нет.
    func послеВхода() {
        поколение = СессияПриложения.shared.поколение
        ГотовностьПримерочной.shared.устарели()
        Task { @MainActor in await ГотовностьПримерочной.shared.проверить() }
        перейти(адресФото.isEmpty ? .фото : .проверка)
    }

    // MARK: - Итог

    func сохранить() {
        guard let данные = итогДанные, !сохраняем else { return }
        сохраняем = true
        Task { @MainActor [weak self] in
            let итог = await ФотоПримерочной.вФото(данные)
            guard let self else { return }
            self.сохраняем = false
            switch итог {
            case .готово:
                ОткликСайта.успех()
                self.показатьВесть(self.т("to_saved"))
            case .нетДоступа:
                ОткликСайта.предупреждение()
                self.показатьВесть(self.т("to_save_denied"))
            case .сбой:
                ОткликСайта.предупреждение()
                self.показатьВесть(self.т("to_save_fail"))
            }
        }
    }

    /// Системный лист: картинка и ссылка на объявление.
    func поделиться() {
        guard let итог else { return }
        var предметы: [Any] = [итог]
        if let адрес = товар.адрес { предметы.append(адрес) }
        ПоделитьсяСайта.системныйЛист(предметы)
    }

    /// «Ещё раз»: прежняя примерка удаляется, человек — у своего фото (можно выбрать другое фото вещи или переснять).
    func ещёРаз() {
        опрос?.cancel()
        забытьЗадачу()
        итог = nil
        итогДанные = nil
        отказ = nil
        продолжаемая = false
        перейти(адресФото.isEmpty ? .фото : .проверка)
    }

    /// «Удалить фото»: delete на сервере и всё на телефоне; не дошло — сервер сотрёт сам через сутки.
    func удалить() {
        guard !удаляем else { return }
        опрос?.cancel()
        let номер = задача
        удаляем = true
        Task { @MainActor [weak self] in
            var удалено = true
            if !номер.isEmpty { удалено = await ПримерочнаяAPI.удалить(номер) }
            guard let self else { return }
            self.удаляем = false
            if удалено && self.задача == номер { self.задача = "" }
            self.итог = nil
            self.итогДанные = nil
            self.адресФото = ""
            self.фотоЧеловека = nil
            self.человекВКадре = nil
            self.отказ = nil
            self.перейти(.фото)
            self.показатьВесть(self.т(удалено ? "to_deleted" : "to_delete_fail"))
        }
    }

    private func перейти(_ новый: Шаг) {
        guard шаг != новый else { return }
        withAnimation(ДвижениеСайта.шаг) { шаг = новый }
    }
}

import Foundation

/**
 «МОЁ» — ПРОГРЕСС ПРОФИЛЕЙ И ФАЙЛЫ НА ТЕЛЕФОНЕ (часть хранилища, MyThingsStore.swift).

 Прогресс (0…1) и следующий шаг каждого профиля считаются из записи, без хранения: гараж, устройства, рост и мерки, а с
 пачки 16.10.2026 — дом (первая минута: кровать → лифт → цоколи), компьютер (процессор, память, накопитель — БП и
 корпус по желанию) и гардероб. Ни серий, ни напоминаний — только кольцо и чип следующего шага. Файлы — последовательная
 очередь «kz.kliko.mythings»: снимок записи кодируется и пишется на ней же, фото, удаление, размер для кабинета. Ничего
 не уходит на сервер.
 */

// MARK: - Прогресс

/// Заполненность профиля и следующий шаг (ключ текста my_next_*; nil — всё заполнено).
struct ПрогрессМоего: Equatable, Sendable {
    /// 0…1.
    let доля: Double
    let шаг: String?

    init(сотых: Int, шаг: String?) {
        доля = Double(min(100, max(0, сотых))) / 100
        self.шаг = шаг
    }
}

extension ЗаписьМоего {
    /// По главной машине: марка и модель 35, параметры колёс 35, фото 30.
    var прогрессГаража: ПрогрессМоего {
        guard let м = главнаяМашина else { return ПрогрессМоего(сотых: 0, шаг: "my_next_car") }
        let посадка = м.посадка.map { !$0.пустая } ?? false
        var сотых = 0
        if м.авто != nil { сотых += 35 }
        if посадка { сотых += 35 }
        if м.фото != nil { сотых += 30 }
        let шаг: String?
        if м.авто == nil && !посадка {
            шаг = "my_next_car"
        } else if !посадка {
            шаг = "my_next_params"
        } else if м.фото == nil {
            шаг = "my_next_car_photo"
        } else {
            шаг = nil
        }
        return ПрогрессМоего(сотых: сотых, шаг: шаг)
    }

    /// Телефон 40, ноутбук или «нет» 30, монитор или ТВ или «нет» 30.
    var прогрессУстройств: ПрогрессМоего {
        let ноутбук = ноутбуки.contains(where: \.заполнено) || нет.contains(Self.нетНоутбука)
        let экран = экраны.contains(where: \.заполнено) || нет.contains(Self.нетЭкрана)
        var сотых = 0
        if телефон != nil { сотых += 40 }
        if ноутбук { сотых += 30 }
        if экран { сотых += 30 }
        let шаг: String?
        if телефон == nil {
            шаг = "my_next_phone"
        } else if !ноутбук {
            шаг = "my_next_laptop"
        } else if !экран {
            шаг = "my_next_screen"
        } else {
            шаг = nil
        }
        return ПрогрессМоего(сотых: сотых, шаг: шаг)
    }

    /// Рост 20, обувь 15, одежда или джинсы 15, мерки 25 (по трети за каждую, до трёх), фото 25.
    var прогрессТела: ПрогрессМоего {
        let т = тело
        let обувь = т.размеры.contains { $0.вид.обувь }
        let одежда = т.размеры.contains { $0.вид.одежда }
        let мерок = min(3, т.мерки.count)
        var сотых = 0
        if т.рост != nil { сотых += 20 }
        if обувь { сотых += 15 }
        if одежда { сотых += 15 }
        сотых += мерок == 3 ? 25 : мерок * 8
        if т.фото != nil { сотых += 25 }
        let шаг: String?
        if т.рост == nil {
            шаг = "my_next_height"
        } else if !обувь || !одежда {
            шаг = "my_next_sizes"
        } else if мерок < 3 {
            шаг = "my_next_measures"
        } else if т.фото == nil {
            шаг = "my_next_body_photo"
        } else {
            шаг = nil
        }
        return ПрогрессМоего(сотых: сотых, шаг: шаг)
    }

    /// Кровать 25, лифт или «лифта нет» 15, лампы 20, входная или межкомнатная дверь 10, комнаты 15, окна или ТВ 15.
    var прогрессДома: ПрогрессМоего {
        let д = дом
        let кровать = д.кровати.contains(where: \.заполнена)
        let лифт = д.лифтаНет || д.проёмы.contains { $0.вид == .лифт && $0.заполнен }
        let лампы = !д.лампы.isEmpty
        let дверь = д.проёмы.contains { ($0.вид == .входная || $0.вид == .дверь) && $0.заполнен }
        let комнаты = !д.комнаты.isEmpty
        let окна = д.окна.contains(where: \.заполнено) || д.экраны.contains(where: \.заполнен)
        var сотых = 0
        if кровать { сотых += 25 }
        if лифт { сотых += 15 }
        if лампы { сотых += 20 }
        if дверь { сотых += 10 }
        if комнаты { сотых += 15 }
        if окна { сотых += 15 }
        let шаг: String?
        if !кровать {
            шаг = "my_next_bed"
        } else if !лифт {
            шаг = "my_next_lift"
        } else if !лампы {
            шаг = "my_next_lamps"
        } else if !дверь {
            шаг = "my_next_door"
        } else if !комнаты {
            шаг = "my_next_rooms"
        } else if !окна {
            шаг = "my_next_windows"
        } else {
            шаг = nil
        }
        return ПрогрессМоего(сотых: сотых, шаг: шаг)
    }

    /// По главному компьютеру: память (тип, форма, слоты) 40, процессор или сокет 30, накопитель 30.
    var прогрессКомпьютера: ПрогрессМоего {
        guard let к = главныйКомпьютер else { return ПрогрессМоего(сотых: 0, шаг: "my_next_pc") }
        var сотых = 0
        if к.естьПамять { сотых += 40 }
        if к.естьПроцессор { сотых += 30 }
        if к.естьНакопитель { сотых += 30 }
        let шаг: String?
        if !к.естьПамять {
            шаг = "my_next_ram"
        } else if !к.естьПроцессор {
            шаг = "my_next_cpu"
        } else if !к.естьНакопитель {
            шаг = "my_next_storage"
        } else {
            шаг = nil
        }
        return ПрогрессМоего(сотых: сотых, шаг: шаг)
    }

    /// Первая вещь 25, пять вещей 20 (по 4 за каждую), фото у трёх вещей 20 (по 7), заметка посадки 20, образ 15.
    var прогрессГардероба: ПрогрессМоего {
        let г = гардероб
        let вещей = г.вещи.count
        let сФото = г.вещи.filter { $0.фото != nil }.count
        var сотых = 0
        if вещей > 0 { сотых += 25 }
        сотых += вещей >= 5 ? 20 : max(0, вещей - 1) * 4
        сотых += сФото >= 3 ? 20 : сФото * 7
        if !г.посадка.isEmpty { сотых += 20 }
        if !г.образы.isEmpty { сотых += 15 }
        let шаг: String?
        if вещей == 0 {
            шаг = "my_next_wear_item"
        } else if вещей < 5 {
            шаг = "my_next_wear_more"
        } else if сФото < 3 {
            шаг = "my_next_wear_photo"
        } else if г.посадка.isEmpty {
            шаг = "my_next_fit_note"
        } else if г.образы.isEmpty {
            шаг = "my_next_outfit"
        } else {
            шаг = nil
        }
        return ПрогрессМоего(сотых: сотых, шаг: шаг)
    }

    /// Среднее включённых профилей: три первых и дом, компьютер, гардероб (по рубильникам).
    var готовность: Double {
        var доли = [прогрессГаража.доля, прогрессУстройств.доля, прогрессТела.доля]
        if Config.мойДом { доли.append(прогрессДома.доля) }
        if Config.мойКомпьютер { доли.append(прогрессКомпьютера.доля) }
        if Config.мойГардероб { доли.append(прогрессГардероба.доля) }
        return доли.reduce(0, +) / Double(доли.count)
    }

    /// Всё заполнено (с допуском на округление).
    var всёГотово: Bool { готовность > 0.995 }
}

// MARK: - Файлы

/**
 Файлы «Моего» — не на главной: последовательная очередь «kz.kliko.mythings» (запись, удаление, размер). Папка —
 Application Support/MyThings, фото — в её photos/. Имена фото — только свои («<uuid>.jpg»), без папок.
 */
enum ФайлыМоего {
    private static let очередь = DispatchQueue(label: "kz.kliko.mythings", qos: .utility)
    private static let имяЗаписи = "my-things.json"

    /// Application Support/MyThings; создать — папка появляется и помечается «не в резервную копию».
    static func папка(создать: Bool = false) -> URL? {
        guard let корень = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: создать) else { return nil }
        let папка = корень.appendingPathComponent("MyThings", isDirectory: true)
        if создать { подготовитьПапку(папка) }
        return папка
    }

    static func папкаФото(создать: Bool = false) -> URL? {
        guard let папка = папка(создать: создать) else { return nil }
        let фото = папка.appendingPathComponent("photos", isDirectory: true)
        if создать { подготовитьПапку(фото) }
        return фото
    }

    /// Адрес фото по имени; чужое имя (с папками) — nil.
    static func адресФото(_ имя: String) -> URL? {
        guard !имя.isEmpty, !имя.contains("/"), !имя.contains("..") else { return nil }
        return папкаФото()?.appendingPathComponent(имя)
    }

    private static func подготовитьПапку(_ адрес: URL) {
        if !FileManager.default.fileExists(atPath: адрес.path) {
            try? FileManager.default.createDirectory(at: адрес, withIntermediateDirectories: true)
        }
        внеКопии(адрес)
    }

    private static func внеКопии(_ адрес: URL) {
        var значения = URLResourceValues()
        значения.isExcludedFromBackup = true
        var изменяемый = адрес
        try? изменяемый.setResourceValues(значения)
    }

    /// Итог чтения записи: файла нет (первый запуск), прочитан — или есть, но сейчас не читается.
    enum ЧтениеМоего {
        case нет
        case данные(Data)
        /// Защита «до первой разблокировки» (запуск в фоне после перезагрузки), сбой диска — перезаписывать нельзя.
        case недоступно
    }

    /// Запись целиком. Синхронно: файл маленький.
    static func прочитать() -> ЧтениеМоего {
        guard let файл = папка()?.appendingPathComponent(имяЗаписи) else { return .недоступно }
        guard FileManager.default.fileExists(atPath: файл.path) else { return .нет }
        guard let данные = try? Data(contentsOf: файл) else { return .недоступно }
        return .данные(данные)
    }

    /// Снимок записи: кодирование и запись — на очереди (главная нить не ждёт JSON большого гардероба), порядок правок
    /// сохраняется.
    static func записать(_ запись: ЗаписьМоего) {
        очередь.async {
            guard let данные = try? JSONEncoder().encode(запись) else { return }
            записатьСейчас(данные)
        }
    }

    /// JSON записи — на очереди, атомарно, с защитой «до первой разблокировки»; готово — на очереди, удалось ли.
    static func записать(_ данные: Data, готово: (@Sendable (Bool) -> Void)? = nil) {
        очередь.async {
            let удачно = записатьСейчас(данные)
            готово?(удачно)
        }
    }

    /// Только на очереди: файл записи атомарно. false — диск не принял.
    @discardableResult
    private static func записатьСейчас(_ данные: Data) -> Bool {
        guard let своя = папка(создать: true) else { return false }
        let файл = своя.appendingPathComponent(имяЗаписи)
        do {
            try данные.write(to: файл, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            внеКопии(файл)
            return true
        } catch {
            /* Диск полон — на экране всё есть до конца запуска; следующая правка попробует снова. */
            return false
        }
    }

    /// Фото — на очереди, атомарно, с полной защитой файла. false — не записалось.
    static func записатьФото(_ данные: Data, имя: String) async -> Bool {
        await withCheckedContinuation { (продолжение: CheckedContinuation<Bool, Never>) in
            очередь.async {
                guard let папка = папкаФото(создать: true), !имя.contains("/") else {
                    продолжение.resume(returning: false)
                    return
                }
                let файл = папка.appendingPathComponent(имя)
                do {
                    try данные.write(to: файл, options: [.atomic, .completeFileProtection])
                    внеКопии(файл)
                    продолжение.resume(returning: true)
                } catch {
                    продолжение.resume(returning: false)
                }
            }
        }
    }

    static func удалить(_ имя: String) {
        guard let файл = адресФото(имя) else { return }
        очередь.async { try? FileManager.default.removeItem(at: файл) }
    }

    /// Папка MyThings целиком.
    static func стереть() {
        guard let папка = папка() else { return }
        очередь.async { try? FileManager.default.removeItem(at: папка) }
    }

    /// Сколько занимают файлы, байт: размер файлов (fileSize), даты не читаются.
    static func байт() async -> Int {
        await withCheckedContinuation { (продолжение: CheckedContinuation<Int, Never>) in
            очередь.async {
                продолжение.resume(returning: посчитать())
            }
        }
    }

    private static func посчитать() -> Int {
        guard let папка = папка(), FileManager.default.fileExists(atPath: папка.path),
              let обход = FileManager.default.enumerator(at: папка, includingPropertiesForKeys: [.fileSizeKey])
        else { return 0 }
        var итог = 0
        for case let адрес as URL in обход {
            итог += (try? адрес.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return итог
    }
}

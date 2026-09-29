import Foundation
import Security

/**
 СВЯЗКА КЛЮЧЕЙ ДЛЯ ПАРОЛЯ НОВОГО АККАУНТА (путь новичка, владелец 29.09.2026).

 После регистрации сервер выдаёт пароль один раз. Вместо совета «сделайте скриншот» приложение само предлагает
 сохранить доступ в Связку ключей iCloud системным окном «Сохранить пароль?» (SecAddSharedWebCredential) — под доменом
 kliko.kz, общим с сайтом: тот же пароль потом подставится и в приложении, и в Safari.

 Работает, только если у приложения есть associated domain webcredentials:kliko.kz (project.yml, он есть) И сервер
 отдаёт https://kliko.kz/.well-known/apple-app-site-association с разделом "webcredentials": {"apps": ["<TeamID>.<bundle>"]}.
 Нет файла, отказ человека или сбой — .нет: окно «Аккаунт создан» предлагает скопировать пароль или сохранить файлом.
 Логин — номер в маске поля входа «+7 (7XX) XXX-XX-XX»: так его подставит система в поле номера, а маска его не тронет.
 */
enum СвязкаКлючей {
    enum Итог: Equatable {
        case идёт
        case сохранено
        case нет
    }

    static let домен = "kliko.kz"

    static func сохранить(логин: String, пароль: String) async -> Итог {
        guard !логин.isEmpty, !пароль.isEmpty else { return .нет }
        let удалось = await withCheckedContinuation { (продолжение: CheckedContinuation<Bool, Never>) in
            SecAddSharedWebCredential(домен as CFString, логин as CFString, пароль as CFString) { ошибка in
                продолжение.resume(returning: ошибка == nil)
            }
        }
        return удалось ? .сохранено : .нет
    }
}

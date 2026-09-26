import SwiftUI
import UIKit

/**
 НАСТРОЙКИ И ПРОФИЛЬ — СОСТОЯНИЕ, ЭТАП 46 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Одна модель на вкладку «Кабинет»: профиль и настройки, прочитанные со страницы кабинета (ПрофильКабинета), какое окно
 настроек открыто, вопрос «Применить к объявлениям?» после сохранения адреса, режима работы или гаранта (cabApplyPrefAsk),
 мастер «Начало работы» и короткая плашка (toast сайта).

 Мастер сам открывается так же, как у сайта (cabWizMaybe): CAB_ONBOARD_DUE, раз за запуск (у сайта — раз за сессию
 вкладки, sessionStorage.klk_wiz_shown), через 1,4 с и только когда ничего другого не открыто. Ничего не пишет, пока
 человек не нажмёт: «Начать» — save_onboard started, «Пропустить» самооткрывшегося — skipped.

 Выход (ВыходНачисто): всё личное стирается, открытые окна закрываются; ответ, пришедший после выхода, не примется
 (поколение).
 */
@MainActor
final class НастройкиМодель: ObservableObject {
    static let shared = НастройкиМодель()

    /// Что открыто поверх кабинета.
    enum Окно: String, Identifiable {
        case пароль, номер, чаты, категории, регион, часы, фото, гарант, оплата, бронь, устройства, язык
        var id: String { rawValue }

        var заголовок: String {
            switch self {
            case .пароль: return ""
            case .номер: return НастройкиText.т("ph_title")
            case .чаты: return НастройкиText.т("cabset_chat")
            case .категории: return НастройкиText.т("cabset_cats")
            case .регион: return НастройкиText.т("cabset_geo")
            case .часы: return НастройкиText.т("cabset_hours")
            case .фото: return НастройкиText.т("cabset_redact")
            case .гарант: return НастройкиText.т("cabset_escrow")
            case .оплата: return НастройкиText.т("cabset_pay")
            case .бронь: return НастройкиText.т("cabset_reserve")
            case .устройства: return НастройкиText.т("sec_devices")
            case .язык: return НастройкиText.т("cabset_lang")
            }
        }
    }

    /// Мастер «Начало работы»: сам (авто) или из настроек.
    struct Мастер: Identifiable {
        let id = UUID()
        let авто: Bool
    }

    @Published private(set) var профиль: ПрофильКабинета? = nil
    @Published var окно: Окно? = nil
    @Published var применить: ПолеПрименения? = nil
    @Published var мастер: Мастер? = nil
    @Published var плашка: String? = nil
    /// «Номер сохранён» после change_phone с need_confirm / need_verify — вопрос «Пройти верификацию?».
    @Published var номерЖдётВерификации = false

    /// Мастер уже открывался сам в этот запуск.
    private var мастерБыл = false
    private var поколение = 0

    private init() {}

    // MARK: - Профиль

    /// Страница кабинета, которую вкладка уже скачала: разбор вне главного потока, итог — если за это время не вышли.
    func обновить(html: String) async {
        let моё = поколение
        let готовый = await Task.detached(priority: .userInitiated) { () -> ПрофильКабинета in
            ПрофильКабинета.разобрать(html)
        }.value
        guard моё == поколение, !готовый.uid.isEmpty else { return }
        профиль = готовый
        мастерСам()
    }

    /// Окно открыто, а профиля ещё нет (ссылка ?open=password сразу после запуска) — страница кабинета с ожиданием.
    func загрузить() async {
        guard let страница = try? await КабинетСайта.страницаКабинета(ждать: true) else { return }
        guard страница.состояние.вошёл == true else { return }
        МоиОбъявленияAPI.запомнитьТокен(страница.состояние.csrf)
        await обновить(html: страница.html)
    }

    /// Страница сказала «гость» — профиль ушедшего не показываем (данные телефона стирает ВыходНачисто).
    func забытьПрофиль() {
        поколение += 1
        профиль = nil
    }

    /// Правка профиля после ответа сервера — то, что сайт меняет в CAB_USER / CAB_PREF_* на месте.
    func изменить(_ правка: (inout ПрофильКабинета) -> Void) {
        guard var п = профиль else { return }
        правка(&п)
        профиль = п
    }

    // MARK: - Окна

    func открыть(_ новое: Окно) {
        окно = новое
    }

    /// ?open=password (ссылка из окна «Это были вы?», карта §1.3.3): окно пароля поверх кабинета.
    func открытьПароль() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            окно = .пароль
        }
    }

    /// cabApplyPrefAsk: после закрытия окна настройки — вопрос «Применить к объявлениям?» (не в самооткрывшемся мастере).
    func спроситьПрименить(_ поле: ПолеПрименения) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard окно == nil, мастер == nil else { return }
            применить = поле
        }
    }

    func показать(_ текст: String) {
        withAnimation(.easeOut(duration: 0.2)) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard плашка == текст else { return }
            withAnimation(.easeIn(duration: 0.2)) { плашка = nil }
        }
    }

    // MARK: - Мастер «Начало работы»

    /// Нужна ли в мастере строка «Верификация через eGov» (_cabWizНужнаВерификация): не верифицирован и KYC включён.
    var мастерСВерификацией: Bool {
        guard let п = профиль else { return false }
        return !п.верифицирован && п.eGovВкл
    }

    func открытьМастер() {
        окно = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            мастер = Мастер(авто: false)
        }
    }

    /// cabWizMaybe: CAB_ONBOARD_DUE — раз за запуск, через 1,4 с, если ничего не открыто и нет окна соглашения.
    private func мастерСам() {
        guard Config.нативныеНастройки, !мастерБыл, let п = профиль, п.мастерНужен, !п.новоеСоглашение else { return }
        мастерБыл = true
        let моё = поколение
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard моё == поколение, окно == nil, применить == nil, мастер == nil else { return }
            мастер = Мастер(авто: true)
        }
    }

    /// cabWizSave: save_onboard {state} — ответ сайт не читает. Не денежный, без повторов.
    func отметитьМастер(_ состояние: String) {
        if состояние != "started" { изменить { $0.мастерНужен = false } }
        Task { @MainActor in
            _ = try? await НастройкиAPI.отправить("cabinet.php?action=save_onboard", ["state": состояние])
        }
    }

    // MARK: - Оформление (тема аккаунта)

    /**
     Тема выбрана в приложении (раздел «Оформление» этапа 15 или шаг мастера) — та же тема и в аккаунте сайта, как у
     cabSetTheme → uipSet({theme}) → _uipPost: __UIP_ACC целиком с новой theme. Тема приложения — настройка телефона
     (этап 15) и ставится сразу; аккаунт — вдогонку, только вошедшему. Не ушло — «Не сохранилось на аккаунт».
     */
    func темаВыбрана(_ тема: ТемаОформления) {
        guard Config.нативныеНастройки, let п = профиль, п.оформлениеВкл, п.оформление != nil else { return }
        let значение: String
        switch тема {
        case .системная: значение = "auto"
        case .светлая: значение = "light"
        case .тёмная: значение = "dark"
        }
        guard значение != п.темаАккаунта else { return }
        let моё = поколение
        Task { @MainActor in
            let итог = await НастройкиAPI.сохранитьОформление(поле: "theme", значение: значение, профиль: п)
            guard моё == поколение else { return }
            if let новое = итог {
                изменить { $0.оформление = новое }
            } else {
                показать(НастройкиText.т("ap_save_fail"))
            }
        }
    }

    // MARK: - Выход

    func стереть() {
        поколение += 1
        профиль = nil
        окно = nil
        применить = nil
        мастер = nil
        плашка = nil
        номерЖдётВерификации = false
        мастерБыл = false
    }
}

/// Что предлагают применить ко всем объявлениям (apply_pref_field {field}).
enum ПолеПрименения: Identifiable, Equatable {
    case гео
    case часы
    /// Гарант: включён ли он теперь (от этого зависит заголовок вопроса).
    case гарант(включён: Bool)

    var id: String { поле }

    var поле: String {
        switch self {
        case .гео: return "geo"
        case .часы: return "hours"
        case .гарант: return "escrow"
        }
    }

    var заголовок: String {
        switch self {
        case .гео: return НастройкиText.т("capp_geo_t")
        case .часы: return НастройкиText.т("capp_hours_t")
        case .гарант(let включён): return НастройкиText.т(включён ? "esc_apply_on_t" : "esc_apply_off_t")
        }
    }

    var пояснение: String {
        switch self {
        case .гео: return НастройкиText.т("capp_geo_s")
        case .часы: return НастройкиText.т("capp_hours_s")
        case .гарант: return НастройкиText.т("esc_apply_s")
        }
    }

    var значок: String {
        switch self {
        case .гео: return "mappin.and.ellipse"
        case .часы: return "clock"
        case .гарант: return "checkmark.shield"
        }
    }
}

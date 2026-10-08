import Foundation

/// Тексты карточки без сети (этап 13) и офлайн-режима (плашка, очередь сообщений) на языке телефона (kk/ru/en/ar) — тем
/// же способом, что лента (FeedText).
enum OfflineText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    /// «3 часа назад» — когда легла копия; на языке телефона, как остальные тексты, а не на языке региона.
    static func когда(_ дата: Date) -> String {
        относительно.localizedString(for: дата, relativeTo: Date())
    }

    private static let относительно: RelativeDateTimeFormatter = {
        let ф = RelativeDateTimeFormatter()
        ф.unitsStyle = .full
        ф.dateTimeStyle = .named
        ф.locale = Locale(identifier: Locale.preferredLanguages.first ?? "ru")
        return ф
    }()

    private static let тексты: [String: [String: String]] = [
        "ru": ["copy": "Сохранённая копия · %@",
               "copy_sub": "Нет связи с сайтом — цена и наличие могли измениться.",
               "list_copy": "Нет связи — показан сохранённый список",
               /* Офлайн-режим (08.10.2026): общая плашка и очередь исходящих сообщений. */
               "offline_copy": "Нет сети — показана сохранённая версия",
               "saved_ago": "Сохранено %@",
               "q_wait": "Ждёт отправки",
               "q_sending": "Отправляем…",
               "q_sent": "Отправлено",
               "q_failed": "Не отправлено — нажмите, чтобы повторить",
               "q_tap_retry": "нажмите, чтобы повторить",
               "q_retry": "Повторить",
               "q_delete": "Удалить",
               "q_you": "Вы"],
        "kk": ["copy": "Сақталған көшірме · %@",
               "copy_sub": "Сайтпен байланыс жоқ — бағасы мен бар-жоғы өзгеруі мүмкін.",
               "list_copy": "Байланыс жоқ — сақталған тізім көрсетілуде",
               "offline_copy": "Желі жоқ — сақталған нұсқа көрсетілуде",
               "saved_ago": "Сақталды: %@",
               "q_wait": "Жіберуді күтуде",
               "q_sending": "Жіберілуде…",
               "q_sent": "Жіберілді",
               "q_failed": "Жіберілмеді — қайталау үшін басыңыз",
               "q_tap_retry": "қайталау үшін басыңыз",
               "q_retry": "Қайталау",
               "q_delete": "Жою",
               "q_you": "Сіз"],
        "en": ["copy": "Saved copy · %@",
               "copy_sub": "Can't reach the website — the price and availability may have changed.",
               "list_copy": "No connection — showing the saved list",
               "offline_copy": "No network — showing the saved version",
               "saved_ago": "Saved %@",
               "q_wait": "Waiting to send",
               "q_sending": "Sending…",
               "q_sent": "Sent",
               "q_failed": "Not sent — tap to retry",
               "q_tap_retry": "tap to retry",
               "q_retry": "Retry",
               "q_delete": "Delete",
               "q_you": "You"],
        "ar": ["copy": "نسخة محفوظة · %@",
               "copy_sub": "تعذّر الاتصال بالموقع — ربما تغيّر السعر أو التوفر.",
               "list_copy": "لا يوجد اتصال — نعرض القائمة المحفوظة",
               "offline_copy": "لا توجد شبكة — نعرض النسخة المحفوظة",
               "saved_ago": "حُفظت %@",
               "q_wait": "بانتظار الإرسال",
               "q_sending": "جارٍ الإرسال…",
               "q_sent": "تم الإرسال",
               "q_failed": "لم يُرسل — اضغط لإعادة المحاولة",
               "q_tap_retry": "اضغط لإعادة المحاولة",
               "q_retry": "إعادة المحاولة",
               "q_delete": "حذف",
               "q_you": "أنت"]
    ]
}

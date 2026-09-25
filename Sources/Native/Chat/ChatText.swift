import Foundation

/// Тексты чата на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText) и замок (AppLock.т).
enum ChatText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["title": "Сообщения", "peer": "Собеседник", "you": "Вы: ", "photo": "Фото", "voice": "Голосовое сообщение",
               "empty": "Сообщений пока нет", "empty_sub": "Напишите продавцу из карточки объявления.",
               "login": "Войдите в аккаунт", "login_sub": "Переписка доступна после входа.", "login_btn": "Войти",
               "failed": "Не удалось загрузить переписку", "retry": "Повторить",
               "placeholder": "Сообщение…", "send": "Отправить", "not_sent": "Сообщение не отправлено. Попробуйте ещё раз.",
               "blocked": "Диалог недоступен", "first": "Напишите первым — задайте вопрос по объявлению",
               "reply_site": "Ответить на сайте", "open_site": "Открыть на сайте", "write": "Написать", "buy": "Купить безопасно"],
        "kk": ["title": "Хабарламалар", "peer": "Әңгімелесуші", "you": "Сіз: ", "photo": "Фото", "voice": "Дауыстық хабарлама",
               "empty": "Әзірге хабарлама жоқ", "empty_sub": "Хабарландыру карточкасынан сатушыға жазыңыз.",
               "login": "Аккаунтқа кіріңіз", "login_sub": "Хат алмасу кіргеннен кейін қолжетімді.", "login_btn": "Кіру",
               "failed": "Хат алмасу жүктелмеді", "retry": "Қайталау",
               "placeholder": "Хабарлама…", "send": "Жіберу", "not_sent": "Хабарлама жіберілмеді. Қайталап көріңіз.",
               "blocked": "Диалог қолжетімсіз", "first": "Бірінші болып жазыңыз — хабарландыру туралы сұраңыз",
               "reply_site": "Сайтта жауап беру", "open_site": "Сайтта ашу", "write": "Жазу", "buy": "Қауіпсіз сатып алу"],
        "en": ["title": "Messages", "peer": "Contact", "you": "You: ", "photo": "Photo", "voice": "Voice message",
               "empty": "No messages yet", "empty_sub": "Message a seller from a listing.",
               "login": "Sign in", "login_sub": "Messages are available after you sign in.", "login_btn": "Sign in",
               "failed": "Couldn't load messages", "retry": "Try again",
               "placeholder": "Message…", "send": "Send", "not_sent": "Message not sent. Please try again.",
               "blocked": "This conversation is unavailable", "first": "Say hello — ask about the listing",
               "reply_site": "Reply on website", "open_site": "Open on website", "write": "Message", "buy": "Buy safely"],
        "ar": ["title": "الرسائل", "peer": "المحاور", "you": "أنت: ", "photo": "صورة", "voice": "رسالة صوتية",
               "empty": "لا توجد رسائل بعد", "empty_sub": "راسل البائع من صفحة الإعلان.",
               "login": "سجّل الدخول", "login_sub": "الرسائل متاحة بعد تسجيل الدخول.", "login_btn": "تسجيل الدخول",
               "failed": "تعذّر تحميل الرسائل", "retry": "إعادة المحاولة",
               "placeholder": "رسالة…", "send": "إرسال", "not_sent": "لم تُرسل الرسالة. حاول مرة أخرى.",
               "blocked": "المحادثة غير متاحة", "first": "ابدأ المحادثة — اسأل عن الإعلان",
               "reply_site": "الرد في الموقع", "open_site": "فتح في الموقع", "write": "راسل", "buy": "اشترِ بأمان"]
    ]
}

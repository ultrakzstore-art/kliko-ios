import Foundation

/// Тексты сохранённых поисков на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText) и кабинет.
/// Уведомление пишется ими же: его готовит само приложение, в фоне, без страницы сайта.
enum SavedSearchText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["save": "Сохранить поиск", "unsave": "Удалить сохранённый поиск",
               "full": "Сохранённых поисков слишком много",
               "full_msg": "Можно сохранить до %d поисков. Удалите ненужные в Кабинете → «Сохранённые поиски», чтобы сохранить новый.",
               "ok": "Понятно",
               "title": "Сохранённые поиски",
               "empty": "Нажмите на колокольчик в ленте, когда ищете или выбрали раздел, — пришлём уведомление о новых объявлениях.",
               "checked": "Проверено %@", "not_checked": "Ещё не проверяли", "open_hint": "Открыть в ленте",
               "footer": "Kliko проверяет эти поиски в фоне — не чаще раза в час, когда позволит iOS, — и присылает одно уведомление о новых объявлениях. Поиски хранятся только на этом телефоне, до 20, и стираются при выходе из аккаунта.",
               "notif_off": "Уведомления выключены — включите их выше или в Настройках iPhone, иначе о новых объявлениях не узнать.",
               "refresh_off": "Обновление контента для Kliko выключено в Настройках iPhone — проверок не будет.",
               "notif_title": "Новые объявления: «%@»", "notif_count": "Новых объявлений: %d",
               "notif_more": "Ещё: %@", "notif_item": "«%@» — %d"],
        "kk": ["save": "Іздеуді сақтау", "unsave": "Сақталған іздеуді жою",
               "full": "Сақталған іздеулер тым көп",
               "full_msg": "%d іздеуге дейін сақтауға болады. Жаңасын сақтау үшін Кабинет → «Сақталған іздеулер» бөлімінен қажетсіздерін жойыңыз.",
               "ok": "Түсінікті",
               "title": "Сақталған іздеулер",
               "empty": "Іздеген немесе бөлім таңдаған кезде лентадағы қоңыраушаны басыңыз — жаңа хабарландырулар туралы push-хабарландыру жібереміз.",
               "checked": "Тексерілді: %@", "not_checked": "Әлі тексерілмеген", "open_hint": "Лентада ашу",
               "footer": "Kliko бұл іздеулерді фонда тексереді — сағатына бір реттен жиі емес, iOS мүмкіндік бергенде — және жаңа хабарландырулар туралы бір push-хабарландыру жібереді. Іздеулер тек осы телефонда сақталады, 20-ға дейін, және аккаунттан шыққанда өшіріледі.",
               "notif_off": "Push-хабарландырулар өшірулі — оларды жоғарыда немесе iPhone баптауларында қосыңыз, әйтпесе жаңа хабарландырулар туралы білмейсіз.",
               "refresh_off": "iPhone баптауларында Kliko үшін контентті фондық жаңарту өшірулі — тексеру болмайды.",
               "notif_title": "Жаңа хабарландырулар: «%@»", "notif_count": "Жаңа хабарландырулар саны: %d",
               "notif_more": "Тағы: %@", "notif_item": "«%@» — %d"],
        "en": ["save": "Save search", "unsave": "Remove saved search",
               "full": "Too many saved searches",
               "full_msg": "You can save up to %d searches. Remove the ones you no longer need in Account → Saved searches to save a new one.",
               "ok": "OK",
               "title": "Saved searches",
               "empty": "Tap the bell in the feed while searching or browsing a category, and we'll notify you about new listings.",
               "checked": "Checked %@", "not_checked": "Not checked yet", "open_hint": "Opens in the feed",
               "footer": "Kliko checks these searches in the background — at most once an hour, when iOS allows — and sends one notification about new listings. Searches are stored only on this phone, up to 20, and are erased when you sign out.",
               "notif_off": "Notifications are off — turn them on above or in iPhone Settings, or you won't hear about new listings.",
               "refresh_off": "Background App Refresh is off for Kliko in iPhone Settings, so searches won't be checked.",
               "notif_title": "New listings: “%@”", "notif_count": "New listings: %d",
               "notif_more": "Also: %@", "notif_item": "“%@” — %d"],
        "ar": ["save": "حفظ البحث", "unsave": "حذف البحث المحفوظ",
               "full": "عمليات البحث المحفوظة كثيرة جدًا",
               "full_msg": "يمكنك حفظ ما يصل إلى %d عملية بحث. احذف ما لا تحتاجه في الحساب ← عمليات البحث المحفوظة لتحفظ بحثًا جديدًا.",
               "ok": "حسنًا",
               "title": "عمليات البحث المحفوظة",
               "empty": "اضغط على الجرس في الإعلانات أثناء البحث أو عند اختيار قسم، وسنرسل إليك إشعارًا بالإعلانات الجديدة.",
               "checked": "تم التحقق %@", "not_checked": "لم يتم التحقق بعد", "open_hint": "يفتح في الإعلانات",
               "footer": "يتحقق ‏Kliko من عمليات البحث هذه في الخلفية — مرة في الساعة على الأكثر، عندما يسمح iOS — ويرسل إشعارًا واحدًا بالإعلانات الجديدة. تُحفظ عمليات البحث على هذا الهاتف فقط، حتى 20، وتُمحى عند تسجيل الخروج.",
               "notif_off": "الإشعارات متوقفة — فعّلها أعلاه أو في إعدادات iPhone، وإلا فلن تعرف بالإعلانات الجديدة.",
               "refresh_off": "تحديث التطبيقات في الخلفية متوقف لـ Kliko في إعدادات iPhone، لذا لن يتم التحقق من عمليات البحث.",
               "notif_title": "إعلانات جديدة: «%@»", "notif_count": "عدد الإعلانات الجديدة: %d",
               "notif_more": "أيضًا: %@", "notif_item": "«%@» — %d"]
    ]
}

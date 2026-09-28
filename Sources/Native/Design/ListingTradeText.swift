import Foundation

/**
 Тексты «Счёт для юрлица» (mkB2bOpen и лист .mk-b2b) и «Обмены» (mkExchOpen, #mk-exch-overlay) страницы объявления.

 Русские — слово в слово из js/i18n-marketplace-ru.js (b2b_…, exch_…) и разметки листа обмена сайта. Заголовок и
 подпись листа обмена у сайта — exch_title «Обмены» и exch_sub «Входящие и исходящие предложения» (так в словаре
 витрины), у услуг — exch_barter_title и exch_barter_sub.
 */
enum ТекстыСчётаИОбмена {
    static func т(_ ключ: String) -> String {
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static var язык: String { String((Locale.preferredLanguages.first ?? "ru").prefix(2)) }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "b2b_order_cta": "Счёт для юрлица", "b2b_sheet_title": "Счёт для юрлица",
        "b2b_sheet_sub": "Отметьте позиции и количество — счёт придёт в раздел «Документы»",
        "b2b_price_ask": "цена по запросу", "b2b_ask_btn": "Узнать цену", "b2b_in_stock": "в наличии",
        "b2b_has_tiers": "есть опт", "b2b_bin": "БИН", "b2b_pos": "поз.", "pcs": "шт.",
        "b2b_saved": "скидка по объёму", "b2b_pick": "Отметьте позиции", "b2b_send": "Сформировать счёт",
        "b2b_sending": "Выписываем счёт…", "b2b_no_goods": "У продавца нет товаров для заказа",
        "b2b_req_title": "Ваши реквизиты",
        "b2b_req_sub": "Счёт выписывается на юридическое лицо — укажите, на кого его оформить",
        "b2b_req_name": "Название (ТОО / ИП)", "b2b_req_bin": "БИН / ИИН", "b2b_req_save": "Сохранить и выписать счёт",
        "b2b_back": "Назад к позициям", "b2b_req_need_name": "Укажите название юрлица",
        "b2b_req_need_bin": "БИН или ИИН — 12 цифр", "b2b_saving": "Сохраняем…",
        "b2b_name_ph": "ТОО «…»", "b2b_bin_ph": "12 цифр",
        "b2b_done_title": "Счёт выписан",
        "b2b_done_sub": "Оплатите по реквизитам ниже. Счёт сохранён в разделе «Документы».",
        "b2b_pay_to": "Получатель", "b2b_iik": "Счёт (IBAN)", "b2b_bank": "Банк", "b2b_bik": "БИК",
        "b2b_pay_by": "Оплатить до", "b2b_done_ok": "Готово", "b2b_to_docs": "Открыть в «Документах»",
        "b2b_login": "Войдите, чтобы запросить счёт", "login_btn": "Войти",
        "err_generic": "Ошибка", "no_conn": "Нет связи", "close": "Закрыть", "loading": "Загрузка…",
        "exch_title": "Обмены", "exch_barter": "Бартер", "exch_barter_title": "Предложить бартер",
        "exch_sub": "Входящие и исходящие предложения",
        "exch_barter_sub": "Выберите свой товар или услугу в обмен на эту услугу",
        "negotiable": "Договорная",
        "exch_empty": "У вас нет опубликованных объявлений для обмена.", "exch_add": "Добавить объявление →",
        "exch_load_err": "Ошибка загрузки объявлений",
        "exch_negot": "Цена договорная — доплату укажите вручную или обсудите в чате",
        "exch_equal": "Равноценный обмен · ",
        "exch_cheaper_a": "Ваш товар дешевле на ", "exch_cheaper_b": " — обычно доплачивает предлагающий",
        "exch_pricier_a": "Ваш товар дороже на ", "exch_pricier_b": " — можно попросить доплату продавца",
        "exch_who_pays": "Кто доплачивает?", "exch_i_pay": "Я", "exch_seller_pays": "Продавец", "exch_no_pay": "Никто",
        "exch_sur_ph": "Сумма доплаты", "exch_comment_ph": "Комментарий — по желанию",
        "exch_send": "Отправить предложение", "sending": "Отправляем…",
        "exch_sent": "Предложение обмена отправлено продавцу!", "exch_err": "Ошибка: ",
        "exch_retry": "попробуйте ещё раз", "exch_login": "Войдите в кабинет чтобы предложить обмен"
    ]

    private static let kk: [String: String] = [
        "b2b_order_cta": "Заңды тұлғаға шот", "b2b_sheet_title": "Заңды тұлғаға шот",
        "b2b_sheet_sub": "Позициялар мен санын белгілеңіз — шот «Құжаттар» бөліміне түседі",
        "b2b_price_ask": "бағасы сұрау бойынша", "b2b_ask_btn": "Бағасын білу", "b2b_in_stock": "қоймада",
        "b2b_has_tiers": "көтерме бар", "b2b_bin": "БСН", "b2b_pos": "поз.", "pcs": "дана",
        "b2b_saved": "көлем бойынша жеңілдік", "b2b_pick": "Позицияларды белгілеңіз", "b2b_send": "Шот құру",
        "b2b_sending": "Шот жазылуда…", "b2b_no_goods": "Сатушыда тапсырысқа тауар жоқ",
        "b2b_req_title": "Сіздің деректемелеріңіз",
        "b2b_req_sub": "Шот заңды тұлғаға жазылады — кімге рәсімдеу керегін көрсетіңіз",
        "b2b_req_name": "Атауы (ЖШС / ЖК)", "b2b_req_bin": "БСН / ЖСН", "b2b_req_save": "Сақтап, шот жазу",
        "b2b_back": "Позицияларға оралу", "b2b_req_need_name": "Заңды тұлғаның атауын көрсетіңіз",
        "b2b_req_need_bin": "БСН немесе ЖСН — 12 сан", "b2b_saving": "Сақталуда…",
        "b2b_name_ph": "ЖШС «…»", "b2b_bin_ph": "12 сан",
        "b2b_done_title": "Шот жазылды",
        "b2b_done_sub": "Төмендегі деректемелер бойынша төлеңіз. Шот «Құжаттар» бөлімінде сақталды.",
        "b2b_pay_to": "Алушы", "b2b_iik": "Шот (IBAN)", "b2b_bank": "Банк", "b2b_bik": "БСК",
        "b2b_pay_by": "Төлеу мерзімі", "b2b_done_ok": "Дайын", "b2b_to_docs": "«Құжаттарда» ашу",
        "b2b_login": "Шот сұрау үшін кіріңіз", "login_btn": "Кіру",
        "err_generic": "Қате", "no_conn": "Байланыс жоқ", "close": "Жабу", "loading": "Жүктелуде…",
        "exch_title": "Айырбастар", "exch_barter": "Бартер", "exch_barter_title": "Бартер ұсыну",
        "exch_sub": "Кіріс және шығыс ұсыныстар",
        "exch_barter_sub": "Осы қызметке айырбасқа өз тауарыңызды немесе қызметіңізді таңдаңыз",
        "negotiable": "Келісімді",
        "exch_empty": "Айырбасқа жарияланған хабарландыруларыңыз жоқ.", "exch_add": "Хабарландыру қосу →",
        "exch_load_err": "Хабарландыруларды жүктеу қатесі",
        "exch_negot": "Баға келісімді — қосымша төлемді қолмен көрсетіңіз немесе чатта талқылаңыз",
        "exch_equal": "Тең айырбас · ",
        "exch_cheaper_a": "Сіздің тауарыңыз арзан: ", "exch_cheaper_b": " — әдетте ұсынушы қосып төлейді",
        "exch_pricier_a": "Сіздің тауарыңыз қымбат: ", "exch_pricier_b": " — сатушыдан қосымша төлем сұрауға болады",
        "exch_who_pays": "Кім қосып төлейді?", "exch_i_pay": "Мен", "exch_seller_pays": "Сатушы", "exch_no_pay": "Ешкім",
        "exch_sur_ph": "Қосымша төлем сомасы", "exch_comment_ph": "Пікір — қалауыңыз бойынша",
        "exch_send": "Ұсыныс жіберу", "sending": "Жіберілуде…",
        "exch_sent": "Айырбас ұсынысы сатушыға жіберілді!", "exch_err": "Қате: ",
        "exch_retry": "қайталап көріңіз", "exch_login": "Айырбас ұсыну үшін кабинетке кіріңіз"
    ]

    private static let en: [String: String] = [
        "b2b_order_cta": "Invoice for a company", "b2b_sheet_title": "Invoice for a company",
        "b2b_sheet_sub": "Tick the items and quantities — the invoice will appear in «Documents»",
        "b2b_price_ask": "price on request", "b2b_ask_btn": "Ask the price", "b2b_in_stock": "in stock",
        "b2b_has_tiers": "wholesale", "b2b_bin": "BIN", "b2b_pos": "items", "pcs": "pcs",
        "b2b_saved": "volume discount", "b2b_pick": "Tick the items", "b2b_send": "Create invoice",
        "b2b_sending": "Issuing the invoice…", "b2b_no_goods": "The seller has no goods to order",
        "b2b_req_title": "Your company details",
        "b2b_req_sub": "The invoice is issued to a legal entity — tell us who it is for",
        "b2b_req_name": "Name (LLP / IE)", "b2b_req_bin": "BIN / IIN", "b2b_req_save": "Save and issue the invoice",
        "b2b_back": "Back to items", "b2b_req_need_name": "Enter the company name",
        "b2b_req_need_bin": "BIN or IIN — 12 digits", "b2b_saving": "Saving…",
        "b2b_name_ph": "LLP «…»", "b2b_bin_ph": "12 digits",
        "b2b_done_title": "Invoice issued",
        "b2b_done_sub": "Pay using the details below. The invoice is saved in «Documents».",
        "b2b_pay_to": "Recipient", "b2b_iik": "Account (IBAN)", "b2b_bank": "Bank", "b2b_bik": "BIC",
        "b2b_pay_by": "Pay by", "b2b_done_ok": "Done", "b2b_to_docs": "Open in «Documents»",
        "b2b_login": "Sign in to request an invoice", "login_btn": "Sign in",
        "err_generic": "Error", "no_conn": "No connection", "close": "Close", "loading": "Loading…",
        "exch_title": "Swaps", "exch_barter": "Barter", "exch_barter_title": "Offer a barter",
        "exch_sub": "Incoming and outgoing offers",
        "exch_barter_sub": "Pick your item or service to swap for this service",
        "negotiable": "Negotiable",
        "exch_empty": "You have no published listings to swap.", "exch_add": "Add a listing →",
        "exch_load_err": "Could not load listings",
        "exch_negot": "The price is negotiable — enter the extra payment yourself or discuss it in chat",
        "exch_equal": "Even swap · ",
        "exch_cheaper_a": "Your item is cheaper by ", "exch_cheaper_b": " — usually the one offering pays extra",
        "exch_pricier_a": "Your item is pricier by ", "exch_pricier_b": " — you can ask the seller to pay extra",
        "exch_who_pays": "Who pays extra?", "exch_i_pay": "Me", "exch_seller_pays": "Seller", "exch_no_pay": "Nobody",
        "exch_sur_ph": "Extra amount", "exch_comment_ph": "Comment — optional",
        "exch_send": "Send offer", "sending": "Sending…",
        "exch_sent": "Swap offer sent to the seller!", "exch_err": "Error: ",
        "exch_retry": "please try again", "exch_login": "Sign in to offer a swap"
    ]

    private static let ar: [String: String] = [
        "b2b_order_cta": "فاتورة لشركة", "b2b_sheet_title": "فاتورة لشركة",
        "b2b_sheet_sub": "حدّد الأصناف والكميات — ستصل الفاتورة إلى قسم «المستندات»",
        "b2b_price_ask": "السعر عند الطلب", "b2b_ask_btn": "اسأل عن السعر", "b2b_in_stock": "متوفر",
        "b2b_has_tiers": "بالجملة", "b2b_bin": "BIN", "b2b_pos": "صنف", "pcs": "قطعة",
        "b2b_saved": "خصم الكمية", "b2b_pick": "حدّد الأصناف", "b2b_send": "إنشاء الفاتورة",
        "b2b_sending": "جارٍ إصدار الفاتورة…", "b2b_no_goods": "لا توجد لدى البائع سلع للطلب",
        "b2b_req_title": "بيانات شركتك",
        "b2b_req_sub": "تُصدر الفاتورة لكيان قانوني — حدّد لمن تُصدر",
        "b2b_req_name": "الاسم (شركة / فردي)", "b2b_req_bin": "BIN / IIN", "b2b_req_save": "حفظ وإصدار الفاتورة",
        "b2b_back": "العودة إلى الأصناف", "b2b_req_need_name": "أدخل اسم الشركة",
        "b2b_req_need_bin": "BIN أو IIN — 12 رقمًا", "b2b_saving": "جارٍ الحفظ…",
        "b2b_name_ph": "شركة «…»", "b2b_bin_ph": "12 رقمًا",
        "b2b_done_title": "تم إصدار الفاتورة",
        "b2b_done_sub": "ادفع وفق البيانات أدناه. الفاتورة محفوظة في «المستندات».",
        "b2b_pay_to": "المستلم", "b2b_iik": "الحساب (IBAN)", "b2b_bank": "البنك", "b2b_bik": "BIC",
        "b2b_pay_by": "الدفع قبل", "b2b_done_ok": "تم", "b2b_to_docs": "فتح في «المستندات»",
        "b2b_login": "سجّل الدخول لطلب فاتورة", "login_btn": "تسجيل الدخول",
        "err_generic": "خطأ", "no_conn": "لا يوجد اتصال", "close": "إغلاق", "loading": "جارٍ التحميل…",
        "exch_title": "المقايضات", "exch_barter": "مقايضة", "exch_barter_title": "اقترح مقايضة",
        "exch_sub": "العروض الواردة والصادرة",
        "exch_barter_sub": "اختر سلعتك أو خدمتك مقابل هذه الخدمة",
        "negotiable": "قابل للتفاوض",
        "exch_empty": "ليست لديك إعلانات منشورة للمقايضة.", "exch_add": "أضف إعلانًا ←",
        "exch_load_err": "تعذّر تحميل الإعلانات",
        "exch_negot": "السعر قابل للتفاوض — أدخل المبلغ الإضافي يدويًا أو ناقشه في المحادثة",
        "exch_equal": "مقايضة متكافئة · ",
        "exch_cheaper_a": "سلعتك أرخص بـ ", "exch_cheaper_b": " — عادةً يدفع صاحب العرض الفرق",
        "exch_pricier_a": "سلعتك أغلى بـ ", "exch_pricier_b": " — يمكنك طلب فرق من البائع",
        "exch_who_pays": "من يدفع الفرق؟", "exch_i_pay": "أنا", "exch_seller_pays": "البائع", "exch_no_pay": "لا أحد",
        "exch_sur_ph": "مبلغ الفرق", "exch_comment_ph": "تعليق — اختياري",
        "exch_send": "إرسال العرض", "sending": "جارٍ الإرسال…",
        "exch_sent": "تم إرسال عرض المقايضة إلى البائع!", "exch_err": "خطأ: ",
        "exch_retry": "حاول مرة أخرى", "exch_login": "سجّل الدخول لاقتراح مقايضة"
    ]
}

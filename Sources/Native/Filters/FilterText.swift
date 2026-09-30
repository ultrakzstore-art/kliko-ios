import Foundation

/**
 Тексты фильтров и сортировки (этап 33) на языке телефона (kk/ru/en/ar) — тем же способом, что лента (FeedText).

 Русские слова — с сайта (js/i18n-marketplace-ru.js и разметка главной): «Фильтры» — filters, «Сначала показывать» —
 sort_title, «Рекомендуемые», «Новые», «Дешевле», «Дороже» — sort_reco, sort_new, sort_cheap, sort_expensive, «Цена, ₸» —
 f_price, «от» и «до» — from и f_to, «Год выпуска» — af_year, «Комнаты» — af_rooms, «Студия» и «5 и больше» — MK_AF_ROOMS,
 «Состояние» — af_cond, «Новое» и «Б/У» — cond_new и cond_used, у транспорта «Новая» и «С пробегом» — af_cond_new и
 af_cond_used, «Продавец» и «Проверенные» — af_seller и af_verified, «Фото» и «Только с фото» — af_photo_lbl и
 af_photo_only, чипы «Проверенные продавцы» и «С фото» — verified_sellers и af_photo, «Сбросить», «Показать», «Сбросить
 всё», «Закрыть» — f_reset, f_show, reset_all, close; «×» на чипе читается «Сбросить: …», как aria-label сайта.
 «Коробка» и «Топливо» — af_gear и af_fuel мастера авто, их значения («Автомат», «Бензин», …) — fac_auto … fac_electric
 (MKF_TR сайта). Марка и модель — af_brand, af_model, af_brand_for, af_model_for, af_any_f, af_brand_find,
 af_model_find, af_brand_none, af_model_none, af_pt_miss, af_model_first, af_model_many, af_model_load, af_pt_loading,
 af_popular, af_all_brands мастера авто сайта.
 */
enum FilterText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["filters": "Фильтры", "sort_title": "Сначала показывать",
               "sort_reco": "Рекомендуемые", "sort_new": "Новые", "sort_old": "Старые", "sort_rating": "По рейтингу", "sort_cheap": "Дешевле", "sort_expensive": "Дороже",
               "price": "Цена, ₸", "from": "от", "to": "до", "from_x": "от %@", "to_x": "до %@",
               "year": "Год выпуска", "rooms": "Комнаты", "studio": "Студия", "rooms_5": "5 и больше",
               "cond": "Состояние", "cond_new": "Новое", "cond_used": "Б/У",
               "cond_new_auto": "Новая", "cond_used_auto": "С пробегом",
               "seller": "Продавец", "verified": "Проверенные", "verified_chip": "Проверенные продавцы",
               "photo": "Фото", "photo_only": "Только с фото", "photo_chip": "С фото",
               "reset": "Сбросить", "reset_all": "Сбросить всё", "show": "Показать", "close": "Закрыть",
               "remove_a11y": "Сбросить: %@", "facet": "%@: %@",
               "search_chip": "Поиск: %@", "price_short": "Цена", "rent": "Аренда",
               "gear": "Коробка", "fuel": "Топливо",
               "fac_auto": "Автомат", "fac_manual": "Механика", "fac_robot": "Робот", "fac_cvt": "Вариатор",
               "fac_petrol": "Бензин", "fac_diesel": "Дизель", "fac_gas": "Газ", "fac_hybrid": "Гибрид",
               "fac_electric": "Электро",
               "brand": "Марка", "model": "Модель", "brand_for": "Для какой марки", "model_for": "Для какой модели",
               "any_f": "Любая", "any_m": "Любой", "brand_find": "Найти марку", "model_find": "Найти модель",
               "brand_none": "Марка не найдена", "model_none": "Моделей нет", "nothing_found": "Не нашли — уточните запрос",
               "model_first": "Сначала марка", "model_many": "Выберите одну марку — тогда появятся её модели",
               "model_load": "Загружаем модели…", "brand_load": "Загружаем каталог…", "popular": "Популярные",
               "all_brands": "Все марки", "brands_fail": "Не удалось загрузить марки", "retry": "Повторить",
               "done": "Готово",
               "x_params": "Параметры", "x_new_pl": "Новые", "x_none": "Ничего не найдено", "x_rent_price": "Цена за месяц, ₸", "x_tags": "Уточнения", "x_master": "Исполнитель", "x_gpu": "Видеокарта", "x_gpu_disc": "Дискретная", "x_ram": "Оперативная память", "x_part": "Тип запчасти", "x_any_n": "Любое", "x_find": "Найти", "x_back": "Назад",
               "cond_new_realty": "Новостройка", "cond_used_realty": "Вторичка", "mileage": "Пробег, км", "engine": "Объём двигателя, л", "area": "Площадь, м²", "land": "Участок, соток", "floor": "Этаж", "build_year": "Год постройки", "deal": "Сделка", "deal_sale": "Купить", "deal_rent": "Снять", "place": "Где помещение", "pl_bc": "Бизнес-центр", "pl_mall": "Торговый центр", "pl_house": "В жилом доме", "pl_standalone": "Отдельное здание", "pl_warehouse": "Склад / промзона", "pl_basement": "Цоколь / подвал", "rtg_term": "Срок", "rtg_cond": "Условия", "rtg_docs": "Документы", "rtg_reno": "Ремонт", "rtg_bld": "Дом", "rtg_bath": "Санузел", "rtg_owner": "Кто сдаёт", "rt_term_long": "Долгосрочно", "rt_term_daily": "Посуточно", "rt_furniture": "С мебелью", "rt_utilities": "Коммуналка включена", "rt_parking": "Есть парковка", "rt_kids": "Можно с детьми", "rt_pets": "Можно с животными", "rt_docs_private": "Частная собственность", "rt_mortgage_ok": "Можно в ипотеку", "rt_reno_euro": "Евроремонт", "rt_reno_design": "Дизайнерский", "rt_reno_cosmetic": "Косметический", "rt_bld_brick": "Кирпичный", "rt_bld_monolith": "Монолитный", "rt_bld_panel": "Панельный", "rt_bath_separate": "Раздельный", "rt_bath_combined": "Совмещённый", "rt_owner_owner": "Собственник", "part_type": "Тип детали", "part_find": "Найти деталь", "part_none": "Ничего не нашли", "part_load": "Загружаем справочник…", "cpu": "Процессор", "ram": "ОЗУ, ГБ", "storage": "Накопитель", "storage_phone": "Встроенная память", "discrete": "Только с дискретной", "gb_plus": "%@ ГБ+", "tb_plus": "%@ ТБ+", "fs_chipset": "Чипсет", "fs_size": "Размер", "fs_color": "Цвет", "fs_material": "Материал", "fs_type": "Тип", "fs_age": "Возраст", "fs_gender": "Пол", "fs_weight": "Вес / объём", "fs_sort": "Тип / сорт", "fs_volume": "Объём (мл/г)", "fs_species": "Вид", "fs_breed": "Порода / для кого", "any_v": "Не важно", "all": "Все"],
        "kk": ["filters": "Сүзгілер", "sort_title": "Алдымен көрсету",
               "sort_reco": "Ұсынылатындар", "sort_new": "Жаңалары", "sort_old": "Ескілері", "sort_rating": "Рейтинг бойынша", "sort_cheap": "Арзанырақ", "sort_expensive": "Қымбатырақ",
               "price": "Бағасы, ₸", "from": "бастап", "to": "дейін", "from_x": "%@ бастап", "to_x": "%@ дейін",
               "year": "Шығарылған жылы", "rooms": "Бөлмелер", "studio": "Студия", "rooms_5": "5 және одан көп",
               "cond": "Жағдайы", "cond_new": "Жаңа", "cond_used": "Қолданылған",
               "cond_new_auto": "Жаңа", "cond_used_auto": "Жүрген",
               "seller": "Сатушы", "verified": "Тексерілгендер", "verified_chip": "Тексерілген сатушылар",
               "photo": "Фото", "photo_only": "Тек фотосы барлар", "photo_chip": "Фотосы бар",
               "reset": "Тазалау", "reset_all": "Барлығын тазалау", "show": "Көрсету", "close": "Жабу",
               "remove_a11y": "Тазалау: %@", "facet": "%@: %@",
               "search_chip": "Іздеу: %@", "price_short": "Баға", "rent": "Жалға алу",
               "gear": "Беріліс қорабы", "fuel": "Отын",
               "fac_auto": "Автомат", "fac_manual": "Механика", "fac_robot": "Робот", "fac_cvt": "Вариатор",
               "fac_petrol": "Бензин", "fac_diesel": "Дизель", "fac_gas": "Газ", "fac_hybrid": "Гибрид",
               "fac_electric": "Электр",
               "brand": "Маркасы", "model": "Моделі", "brand_for": "Қай маркаға", "model_for": "Қай модельге",
               "any_f": "Кез келген", "any_m": "Кез келген", "brand_find": "Марканы табу", "model_find": "Модельді табу",
               "brand_none": "Марка табылмады", "model_none": "Модельдер жоқ", "nothing_found": "Табылмады — сұрауды нақтылаңыз",
               "model_first": "Алдымен марка", "model_many": "Бір марканы таңдаңыз — сонда оның модельдері шығады",
               "model_load": "Модельдерді жүктеп жатырмыз…", "brand_load": "Каталогты жүктеп жатырмыз…", "popular": "Танымал",
               "all_brands": "Барлық маркалар", "brands_fail": "Маркаларды жүктеу мүмкін болмады", "retry": "Қайталау",
               "done": "Дайын",
               "x_params": "Параметрлер", "x_new_pl": "Жаңа", "x_none": "Ештеңе табылмады", "x_rent_price": "Айлық баға, ₸", "x_tags": "Нақтылаулар", "x_master": "Орындаушы", "x_gpu": "Бейнекарта", "x_gpu_disc": "Дискретті", "x_ram": "Жедел жады", "x_part": "Қосалқы бөлшек түрі", "x_any_n": "Кез келген", "x_find": "Табу", "x_back": "Артқа",
               "cond_new_realty": "Жаңа құрылыс", "cond_used_realty": "Екінші нарық", "mileage": "Жүрісі, км", "engine": "Қозғалтқыш көлемі, л", "area": "Ауданы, м²", "land": "Жер телімі, сотық", "floor": "Қабат", "build_year": "Салынған жылы", "deal": "Мәміле", "deal_sale": "Сатып алу", "deal_rent": "Жалға алу", "place": "Үй-жай қайда", "pl_bc": "Бизнес-орталық", "pl_mall": "Сауда орталығы", "pl_house": "Тұрғын үйде", "pl_standalone": "Жеке ғимарат", "pl_warehouse": "Қойма / өнеркәсіп аймағы", "pl_basement": "Цоколь / жертөле", "rtg_term": "Мерзімі", "rtg_cond": "Шарттары", "rtg_docs": "Құжаттар", "rtg_reno": "Жөндеу", "rtg_bld": "Үй", "rtg_bath": "Санжайы", "rtg_owner": "Кім береді", "rt_term_long": "Ұзақ мерзімге", "rt_term_daily": "Тәулікпен", "rt_furniture": "Жиһазымен", "rt_utilities": "Коммуналдық төлем кірген", "rt_parking": "Тұрақ бар", "rt_kids": "Балалармен болады", "rt_pets": "Жануарлармен болады", "rt_docs_private": "Жеке меншік", "rt_mortgage_ok": "Ипотекаға болады", "rt_reno_euro": "Еуроремонт", "rt_reno_design": "Дизайнерлік", "rt_reno_cosmetic": "Косметикалық", "rt_bld_brick": "Кірпіш", "rt_bld_monolith": "Монолит", "rt_bld_panel": "Панельді", "rt_bath_separate": "Бөлек", "rt_bath_combined": "Біріктірілген", "rt_owner_owner": "Меншік иесі", "part_type": "Бөлшек түрі", "part_find": "Бөлшекті табу", "part_none": "Ештеңе табылмады", "part_load": "Анықтамалықты жүктеп жатырмыз…", "cpu": "Процессор", "ram": "ЖЖҚ, ГБ", "storage": "Жинақтауыш", "storage_phone": "Ішкі жады", "discrete": "Тек дискретті", "gb_plus": "%@ ГБ+", "tb_plus": "%@ ТБ+", "fs_chipset": "Чипсет", "fs_size": "Өлшемі", "fs_color": "Түсі", "fs_material": "Материал", "fs_type": "Түрі", "fs_age": "Жасы", "fs_gender": "Жынысы", "fs_weight": "Салмағы / көлемі", "fs_sort": "Түрі / сорты", "fs_volume": "Көлемі (мл/г)", "fs_species": "Түрі", "fs_breed": "Тұқымы / кімге", "any_v": "Маңызды емес", "all": "Барлығы"],
        "en": ["filters": "Filters", "sort_title": "Show first",
               "sort_reco": "Recommended", "sort_new": "Newest", "sort_old": "Oldest", "sort_rating": "By rating", "sort_cheap": "Cheapest", "sort_expensive": "Most expensive",
               "price": "Price, ₸", "from": "from", "to": "to", "from_x": "from %@", "to_x": "up to %@",
               "year": "Year", "rooms": "Rooms", "studio": "Studio", "rooms_5": "5 or more",
               "cond": "Condition", "cond_new": "New", "cond_used": "Used",
               "cond_new_auto": "New", "cond_used_auto": "Used",
               "seller": "Seller", "verified": "Verified", "verified_chip": "Verified sellers",
               "photo": "Photo", "photo_only": "With photos only", "photo_chip": "With photos",
               "reset": "Reset", "reset_all": "Reset all", "show": "Show", "close": "Close",
               "remove_a11y": "Remove: %@", "facet": "%@: %@",
               "search_chip": "Search: %@", "price_short": "Price", "rent": "Rent",
               "gear": "Gearbox", "fuel": "Fuel",
               "fac_auto": "Automatic", "fac_manual": "Manual", "fac_robot": "Robotic", "fac_cvt": "CVT",
               "fac_petrol": "Petrol", "fac_diesel": "Diesel", "fac_gas": "Gas", "fac_hybrid": "Hybrid",
               "fac_electric": "Electric",
               "brand": "Make", "model": "Model", "brand_for": "For which make", "model_for": "For which model",
               "any_f": "Any", "any_m": "Any", "brand_find": "Find a make", "model_find": "Find a model",
               "brand_none": "Make not found", "model_none": "No models", "nothing_found": "Nothing found — refine your search",
               "model_first": "Choose a make first", "model_many": "Choose one make to see its models",
               "model_load": "Loading models…", "brand_load": "Loading catalog…", "popular": "Popular",
               "all_brands": "All makes", "brands_fail": "Couldn't load makes", "retry": "Retry",
               "done": "Done",
               "x_params": "Filters", "x_new_pl": "New", "x_none": "Nothing found", "x_rent_price": "Price per month, ₸", "x_tags": "Details", "x_master": "Provider", "x_gpu": "GPU", "x_gpu_disc": "Dedicated", "x_ram": "RAM", "x_part": "Part type", "x_any_n": "Any", "x_find": "Find", "x_back": "Back",
               "cond_new_realty": "New build", "cond_used_realty": "Resale", "mileage": "Mileage, km", "engine": "Engine, L", "area": "Floor area, m²", "land": "Land, sotkas", "floor": "Floor", "build_year": "Year built", "deal": "Deal", "deal_sale": "Buy", "deal_rent": "Rent", "place": "Where the space is", "pl_bc": "Business centre", "pl_mall": "Shopping mall", "pl_house": "In a residential building", "pl_standalone": "Standalone building", "pl_warehouse": "Warehouse / industrial", "pl_basement": "Basement / lower ground", "rtg_term": "Term", "rtg_cond": "Terms", "rtg_docs": "Documents", "rtg_reno": "Renovation", "rtg_bld": "Building", "rtg_bath": "Bathroom", "rtg_owner": "Who lets it", "rt_term_long": "Long-term", "rt_term_daily": "Daily", "rt_furniture": "Furnished", "rt_utilities": "Utilities included", "rt_parking": "Parking", "rt_kids": "Kids allowed", "rt_pets": "Pets allowed", "rt_docs_private": "Private ownership", "rt_mortgage_ok": "Mortgage available", "rt_reno_euro": "Euro renovation", "rt_reno_design": "Designer", "rt_reno_cosmetic": "Cosmetic", "rt_bld_brick": "Brick", "rt_bld_monolith": "Monolithic", "rt_bld_panel": "Panel", "rt_bath_separate": "Separate", "rt_bath_combined": "Combined", "rt_owner_owner": "Owner", "part_type": "Part type", "part_find": "Find a part", "part_none": "Nothing found", "part_load": "Loading catalog…", "cpu": "CPU", "ram": "RAM, GB", "storage": "Storage", "storage_phone": "Built-in storage", "discrete": "Discrete only", "gb_plus": "%@ GB+", "tb_plus": "%@ TB+", "fs_chipset": "Chipset", "fs_size": "Size", "fs_color": "Color", "fs_material": "Material", "fs_type": "Type", "fs_age": "Age", "fs_gender": "Gender", "fs_weight": "Weight / volume", "fs_sort": "Type / variety", "fs_volume": "Volume (ml/g)", "fs_species": "Species", "fs_breed": "Breed / for whom", "any_v": "Any", "all": "All"],
        "ar": ["filters": "عوامل التصفية", "sort_title": "اعرض أولًا",
               "sort_reco": "المقترحة", "sort_new": "الأحدث", "sort_old": "الأقدم", "sort_rating": "حسب التقييم", "sort_cheap": "الأرخص", "sort_expensive": "الأغلى",
               "price": "السعر، ₸", "from": "من", "to": "إلى", "from_x": "من %@", "to_x": "حتى %@",
               "year": "سنة الصنع", "rooms": "الغرف", "studio": "استوديو", "rooms_5": "5 أو أكثر",
               "cond": "الحالة", "cond_new": "جديد", "cond_used": "مستعمل",
               "cond_new_auto": "جديدة", "cond_used_auto": "مستعملة",
               "seller": "البائع", "verified": "الموثّقون", "verified_chip": "بائعون موثّقون",
               "photo": "الصور", "photo_only": "مع صور فقط", "photo_chip": "مع صور",
               "reset": "إعادة الضبط", "reset_all": "إعادة ضبط الكل", "show": "عرض", "close": "إغلاق",
               "remove_a11y": "إزالة: %@", "facet": "%@: %@",
               "search_chip": "بحث: %@", "price_short": "السعر", "rent": "إيجار",
               "gear": "ناقل الحركة", "fuel": "الوقود",
               "fac_auto": "أوتوماتيك", "fac_manual": "يدوي", "fac_robot": "روبوتي", "fac_cvt": "CVT",
               "fac_petrol": "بنزين", "fac_diesel": "ديزل", "fac_gas": "غاز", "fac_hybrid": "هجين",
               "fac_electric": "كهربائي",
               "brand": "الماركة", "model": "الطراز", "brand_for": "لأي ماركة", "model_for": "لأي طراز",
               "any_f": "أي", "any_m": "أي", "brand_find": "ابحث عن ماركة", "model_find": "ابحث عن طراز",
               "brand_none": "لم يتم العثور على الماركة", "model_none": "لا توجد طرازات", "nothing_found": "لم نجد شيئًا — دقّق طلبك",
               "model_first": "اختر الماركة أولًا", "model_many": "اختر ماركة واحدة لتظهر طرازاتها",
               "model_load": "جارٍ تحميل الطرازات…", "brand_load": "جارٍ تحميل الدليل…", "popular": "الشائعة",
               "all_brands": "كل الماركات", "brands_fail": "تعذّر تحميل الماركات", "retry": "أعد المحاولة",
               "done": "تم",
               "x_params": "عوامل التصفية", "x_new_pl": "جديدة", "x_none": "لم يُعثر على شيء", "x_rent_price": "السعر شهريًا، ₸", "x_tags": "تفاصيل", "x_master": "مقدّم الخدمة", "x_gpu": "كرت الشاشة", "x_gpu_disc": "منفصلة", "x_ram": "الذاكرة العشوائية", "x_part": "نوع القطعة", "x_any_n": "أي", "x_find": "بحث", "x_back": "رجوع",
               "cond_new_realty": "بناء جديد", "cond_used_realty": "إعادة بيع", "mileage": "المسافة، كم", "engine": "سعة المحرك، لتر", "area": "المساحة، م²", "land": "الأرض، سوتكا", "floor": "الطابق", "build_year": "سنة البناء", "deal": "الصفقة", "deal_sale": "شراء", "deal_rent": "استئجار", "place": "أين يقع المكان", "pl_bc": "مركز أعمال", "pl_mall": "مركز تجاري", "pl_house": "في مبنى سكني", "pl_standalone": "مبنى مستقل", "pl_warehouse": "مستودع / منطقة صناعية", "pl_basement": "طابق أرضي / قبو", "rtg_term": "المدة", "rtg_cond": "الشروط", "rtg_docs": "المستندات", "rtg_reno": "التشطيب", "rtg_bld": "المبنى", "rtg_bath": "الحمّام", "rtg_owner": "من يؤجّر", "rt_term_long": "طويل الأمد", "rt_term_daily": "يومي", "rt_furniture": "مفروش", "rt_utilities": "المرافق مشمولة", "rt_parking": "يوجد موقف", "rt_kids": "يُسمح بالأطفال", "rt_pets": "يُسمح بالحيوانات", "rt_docs_private": "ملكية خاصة", "rt_mortgage_ok": "متاح بالرهن العقاري", "rt_reno_euro": "تشطيب أوروبي", "rt_reno_design": "تصميمي", "rt_reno_cosmetic": "تجميلي", "rt_bld_brick": "طوب", "rt_bld_monolith": "خرساني مصبوب", "rt_bld_panel": "ألواح", "rt_bath_separate": "منفصل", "rt_bath_combined": "مشترك", "rt_owner_owner": "المالك", "part_type": "نوع القطعة", "part_find": "ابحث عن قطعة", "part_none": "لم نجد شيئًا", "part_load": "جارٍ تحميل الدليل…", "cpu": "المعالج", "ram": "الذاكرة، غيغابايت", "storage": "التخزين", "storage_phone": "الذاكرة المدمجة", "discrete": "بكرت شاشة منفصل فقط", "gb_plus": "%@ غيغابايت+", "tb_plus": "%@ تيرابايت+", "fs_chipset": "الشريحة", "fs_size": "المقاس", "fs_color": "اللون", "fs_material": "الخامة", "fs_type": "النوع", "fs_age": "العمر", "fs_gender": "الجنس", "fs_weight": "الوزن / الحجم", "fs_sort": "النوع / الصنف", "fs_volume": "الحجم (مل/غ)", "fs_species": "النوع", "fs_breed": "السلالة / لمن", "any_v": "لا يهم", "all": "الكل"]
    ]
}

import Foundation
import WebKit

/**
 РАЗДЕЛЫ САЙТА ДЛЯ СТРАНИЦЫ ОБЪЯВЛЕНИЯ (этап 28, владелец 25.09.2026: «почти 100% похоже на сайт»).

 Сайт решает по разделу объявления, что рисовать: «Б/У» или «С пробегом» на фото (mkCond), «от» перед ценой и
 «Связаться» вместо «Предложить цену» у услуг (mkIsService), какой совет «… — на что смотреть» показать (mkBuyTipsKey),
 будут ли в «Продавец утверждает» гарантия и доставка (mkTrustBlock, mkIsDeliverable). Раздел в ответе API — лист дерева
 («pc-repair»), а решение — по его корню («services»). Дерево сайта (js/cats-ru.js, MK_CATS → MK_CFLAT) приложению
 нужно целиком, поэтому здесь — его снимок: «раздел:родитель[:класс]» на каждый из 561 раздела. Класс — у разделов
 недвижимости (residential, commercial, land, garage): по нему «Новостройка» или «Вторичный рынок» (mkRealtyClass).

 🔴 НАЗВАНИЯ — СО СТРАНИЦЫ, А НЕ ИЗ СНИМКА. Хлебные крошки («Ремонт техники › Ремонт компьютеров») сайт пишет на языке
 страницы (mkCatName), а у снимка только русские имена. Поэтому имена спрашиваем у загруженной страницы сайта тем же
 mkCatName (SiteSession.названияРазделов) — язык там тот же, что у приложения (Config.страницаСайта). Страница не
 ответила — крошки показывают один корень названием из текстов приложения (ListingPageText, «root_<раздел>»). Снимок
 устареет — новый раздел просто не найдётся: карточка покажет его как товар, крошкой — одним названием со страницы.
 */
enum РазделыСайта {
    struct Узел {
        let родитель: String?
        let класс: String?
    }

    /// Раздел → родитель и класс. Строится один раз, при первом обращении.
    static let дерево: [String: Узел] = {
        var д: [String: Узел] = [:]
        for запись in снимок.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            let части = запись.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard let раздел = части.first, !раздел.isEmpty else { continue }
            let родитель = части.count > 1 && !части[1].isEmpty ? части[1] : nil
            let класс = части.count > 2 && !части[2].isEmpty ? части[2] : nil
            д[раздел] = Узел(родитель: родитель, класс: класс)
        }
        return д
    }()

    /// Корень раздела — mkCatRoot сайта. Неизвестный раздел — сам себе корень.
    static func корень(_ раздел: String?) -> String {
        guard var текущий = раздел, !текущий.isEmpty else { return "" }
        var шаги = 0
        while let родитель = дерево[текущий]?.родитель, шаги < 25 {
            текущий = родитель
            шаги += 1
        }
        return текущий
    }

    /// Раздел или кто-то из его предков — один из данных (mkUnderAnyCat сайта).
    static func внутри(_ раздел: String?, _ предки: Set<String>) -> Bool {
        var текущий = раздел
        var шаги = 0
        while let т = текущий, шаги < 25 {
            if предки.contains(т) { return true }
            текущий = дерево[т]?.родитель
            шаги += 1
        }
        return false
    }

    /// Родитель раздела — первая крошка (n.parent в mkOpenModal).
    static func родитель(_ раздел: String?) -> String? {
        guard let раздел else { return nil }
        return дерево[раздел]?.родитель
    }

    /// Услуга или вакансия — mkIsService.
    static func услуга(_ раздел: String?) -> Bool {
        let к = корень(раздел)
        return к == "services" || к == "jobs"
    }

    /// Значок корня — ближайший SF Symbol к SVG раздела в js/cats-ru.js (иконка в начале хлебных крошек).
    static func значок(_ раздел: String?) -> String {
        switch корень(раздел) {
        case "electronics": return "iphone"
        case "transport": return "car"
        case "realty": return "house"
        case "clothing": return "tshirt"
        case "home-garden": return "sofa"
        case "kids": return "teddybear"
        case "sport": return "basketball"
        case "animals": return "pawprint"
        case "jobs": return "briefcase"
        case "services": return "wrench.adjustable"
        case "hobby": return "paintpalette"
        case "food-farm": return "carrot"
        case "beauty": return "sparkles"
        default: return "square.grid.2x2"
        }
    }

    /// Снимок MK_CATS сайта (js/cats-ru.js, 25.09.2026): «раздел:родитель[:класс]» через пробел, корни — без родителя.
    private static let снимок = """
        electronics: phones-tablets:electronics smartphones:phones-tablets tablets:phones-tablets
        smartwatches:phones-tablets phone-accessories:phones-tablets phone-cases:phones-tablets
        phone-chargers:phones-tablets phone-parts:phones-tablets computers:electronics laptops:computers
        desktops:computers all-in-one:computers monitors:computers pc-components:computers cpu:pc-components
        gpu:pc-components ram:pc-components ssd-hdd:pc-components motherboards:pc-components
        power-supplies:pc-components pc-cases:pc-components cooling:pc-components printers:computers
        keyboards-mice:computers networking:computers ups-batteries:computers tv-audio:electronics tv:tv-audio
        headphones:tv-audio speakers:tv-audio projectors:tv-audio home-theater:tv-audio receivers:tv-audio
        media-players:tv-audio photo-video:electronics cameras:photo-video mirrorless:photo-video lenses:photo-video
        camcorders:photo-video action-cameras:photo-video drones:photo-video photo-accessories:photo-video
        tripods:photo-video games:electronics consoles:games video-games:games gamepads:games gaming-chairs:games
        vr-headsets:games office-equipment:electronics scanners:office-equipment cash-registers:office-equipment
        transport: cars:transport cars-sedan:cars cars-suv:cars cars-minivan:cars cars-electric:cars cars-hybrid:cars
        cars-sport:cars motorcycles:transport motorcycles-road:motorcycles motorcycles-off:motorcycles
        scooters:motorcycles atvs:motorcycles e-scooters:motorcycles trucks-special:transport trucks:trucks-special
        buses:trucks-special agricultural:trucks-special construction-equip:trucks-special forklifts:trucks-special
        auto-parts:transport auto-parts-items:auto-parts tires-wheels:auto-parts auto-accessories:auto-parts
        auto-audio:auto-parts auto-oils:auto-parts auto-lighting:auto-parts water-transport:transport
        boats:water-transport jet-skis:water-transport realty::residential apartments:realty:residential
        apartments-sale:apartments:residential apartments-rent:apartments:residential
        apartments-daily:apartments:residential rooms:apartments:residential houses:realty:residential
        houses-sale:houses:residential houses-rent:houses:residential cottages:houses:residential
        commercial-realty:realty:commercial offices:commercial-realty:commercial retail:commercial-realty:commercial
        warehouses:commercial-realty:commercial land:realty:land land-housing:land:land land-commercial:land:land
        land-farm:land:land garages-parking:realty:garage garage-sale:garages-parking:garage
        garage-rent:garages-parking:garage parking-space:garages-parking:garage clothing: mens-clothing:clothing
        mens-tops:mens-clothing mens-bottoms:mens-clothing mens-outerwear:mens-clothing mens-suits:mens-clothing
        mens-sportswear:mens-clothing womens-clothing:clothing womens-dresses:womens-clothing
        womens-tops:womens-clothing womens-bottoms:womens-clothing womens-outerwear:womens-clothing
        womens-sportswear:womens-clothing kids-clothing:clothing kids-clothing-0-3:kids-clothing
        kids-clothing-3-7:kids-clothing kids-clothing-7-14:kids-clothing shoes:clothing mens-shoes:shoes
        womens-shoes:shoes kids-shoes:shoes sport-shoes:shoes bags-accessories:clothing handbags:bags-accessories
        backpacks:bags-accessories wallets:bags-accessories belts-scarves:bags-accessories hats:bags-accessories
        sunglasses:bags-accessories jewelry:clothing rings:jewelry necklaces:jewelry bracelets:jewelry earrings:jewelry
        watches:jewelry home-garden: furniture:home-garden sofas:furniture beds:furniture tables:furniture
        wardrobes:furniture kitchen-furniture:furniture hall-furniture:furniture office-furniture:furniture
        outdoor-furniture:furniture appliances:home-garden fridges:appliances washing-machines:appliances
        dishwashers:appliances stoves:appliances microwaves:appliances air-conditioners:appliances
        vacuum-cleaners:appliances small-appliances:appliances kettles-coffee:appliances water-heaters:appliances
        kitchenware:home-garden cookware:kitchenware cutlery:kitchenware tableware:kitchenware repair:home-garden
        tools:repair power-tools:repair building-materials:repair windows-doors:repair plumbing:repair electrical:repair
        flooring:repair wallpaper-paint:repair heating-cooling:repair lighting:home-garden chandeliers:lighting
        lamps:lighting led-strips:lighting plants-gardening:home-garden plants:plants-gardening seeds:plants-gardening
        garden-tools:plants-gardening lawn-mowers:plants-gardening textiles-decor:home-garden bedding:textiles-decor
        curtains:textiles-decor carpets:textiles-decor decor-items:textiles-decor kids: toys:kids toys-0-3:toys
        toys-3-7:toys toys-7plus:toys lego-constructors:toys radio-toys:toys dolls-figures:toys strollers-carseats:kids
        strollers:strollers-carseats car-seats:strollers-carseats baby-carriers:strollers-carseats kids-furniture:kids
        kids-beds:kids-furniture cribs:kids-furniture highchairs:kids-furniture kids-clothing-0-12:kids
        kids-newborn:kids-clothing-0-12 kids-clothing-boys:kids-clothing-0-12 kids-clothing-girls:kids-clothing-0-12
        kids-outerwear:kids-clothing-0-12 school-supplies:kids school-backpacks:school-supplies
        school-stationery:school-supplies school-uniform:school-supplies school-books:school-supplies kids-sports:kids
        kids-bikes-scooters:kids-sports kids-playgrounds:kids-sports kids-swimming:kids-sports baby-food:kids
        baby-formula:baby-food baby-puree:baby-food baby-feeding:baby-food baby-care:kids baby-diapers:baby-care
        baby-hygiene:baby-care baby-monitors:baby-care sport: bicycles:sport mtb:bicycles road-bikes:bicycles
        kids-bikes:bicycles e-bikes:bicycles bike-accessories:bicycles fitness:sport treadmills:fitness
        exercise-bikes:fitness weights-barbells:fitness yoga-mats:fitness sports-nutrition:fitness winter-sport:sport
        skis:winter-sport snowboards:winter-sport ice-skates:winter-sport water-sport:sport surfing:water-sport
        diving:water-sport team-sports:sport football-gear:team-sports basketball-gear:team-sports
        volleyball-gear:team-sports racket-sports:sport camping:sport tents:camping sleeping-bags:camping
        backpacks-camping:camping hiking-boots:camping hunting-fishing:sport fishing-rods:hunting-fishing
        hunting-equipment:hunting-fishing animals: dogs:animals dogs-puppies:dogs dogs-adults:dogs cats:animals
        cats-kittens:cats cats-adults:cats birds:animals parrots:birds canaries:birds pigeons:birds birds-exotic:birds
        birds-other:birds fish-aquariums:animals aquariums:fish-aquariums fish:fish-aquariums rodents:animals
        rodents-hamsters:rodents rodents-rabbits:rodents rodents-guinea:rodents rodents-cages:rodents reptiles:animals
        reptiles-turtles:reptiles reptiles-lizards:reptiles reptiles-snakes:reptiles reptiles-terrariums:reptiles
        livestock:animals cattle:livestock sheep-goats:livestock horses:livestock camels:livestock pigs:livestock
        poultry:livestock poultry-chickens:poultry poultry-ducks-geese:poultry poultry-turkeys:poultry
        poultry-quails:poultry pet-food-care:animals dog-food:pet-food-care cat-food:pet-food-care
        vet-supplies:pet-food-care pet-accessories:animals cages-carriers:pet-accessories
        collars-leashes:pet-accessories jobs: vacancies:jobs jobs-it:vacancies jobs-marketing:vacancies
        jobs-trade:vacancies jobs-finance:vacancies jobs-driver:vacancies jobs-builder:vacancies jobs-security:vacancies
        jobs-logistics:vacancies jobs-part-time:vacancies resumes:jobs services: tech-repair:services
        phone-repair:tech-repair iphone-repair:phone-repair android-repair:phone-repair screen-replacement:phone-repair
        battery-replacement:phone-repair laptop-repair:tech-repair laptop-screen-rep:laptop-repair
        laptop-battery-rep:laptop-repair laptop-keyboard-rep:laptop-repair pc-repair:tech-repair pc-upgrade:pc-repair
        virus-removal:pc-repair os-install:pc-repair tablet-repair:tech-repair tv-repair:tech-repair
        appliance-repair:tech-repair fridge-repair:appliance-repair washer-repair:appliance-repair
        ac-repair:appliance-repair microwave-repair:appliance-repair printer-repair:tech-repair
        camera-repair:tech-repair repair-construction:services apartment-repair:repair-construction
        cosmetic-repair:repair-construction major-repair:repair-construction plumbing-service:repair-construction
        electrical-service:repair-construction window-service:repair-construction window-install:window-service
        window-repair-svc:window-service window-mosquito:window-service door-service:repair-construction
        flooring-service:repair-construction painting-service:repair-construction ceiling-service:repair-construction
        construction-gen:repair-construction welding:repair-construction furniture-assembly:repair-construction
        moving-service:repair-construction cleaning-service:repair-construction dry-cleaning:repair-construction
        auto-services:services car-service:auto-services tire-service:auto-services car-wash:auto-services
        auto-painting:auto-services car-detailing:auto-services auto-electrician:auto-services auto-glass:auto-services
        auto-diagnostics:auto-services evacuation:auto-services beauty-health:services hairdresser:beauty-health
        manicure:beauty-health eyelashes-brows:beauty-health massage:beauty-health cosmetology:beauty-health
        makeup:beauty-health tattooing:beauty-health epilation:beauty-health medical-services:beauty-health
        psychologist:beauty-health fitness-trainer:beauty-health tutors-education:services math-tutor:tutors-education
        english-tutor:tutors-education russian-tutor:tutors-education kazakh-tutor:tutors-education
        music-lessons:tutors-education driving-lessons:tutors-education courses-online:tutors-education
        kids-development:tutors-education drawing-art:tutors-education it-development:services web-dev:it-development
        mobile-dev:it-development seo:it-development smm:it-development design:it-development 1c-it:it-development
        it-support:it-development delivery-courier:services city-courier:delivery-courier
        same-day-delivery:delivery-courier express-delivery:delivery-courier cargo-intercity:delivery-courier
        cargo-transport:delivery-courier movers:delivery-courier package-delivery:delivery-courier
        food-delivery:delivery-courier motorcycle-courier:delivery-courier photo-video-svc:services
        photographer:photo-video-svc videographer:photo-video-svc wedding-photo:photo-video-svc
        drone-photo:photo-video-svc reels-creation:photo-video-svc events:services toastmaster:events dj:events
        animators:events event-decoration:events catering:events legal-financial:services lawyer:legal-financial
        notary:legal-financial accountant:legal-financial business-reg:legal-financial tax-consulting:legal-financial
        insurance:legal-financial translation:services written-translation:translation oral-translation:translation
        other-services:services handyman:other-services pet-walking:other-services laundry:other-services
        tailoring:other-services shoe-repair:other-services key-copy:other-services printing:other-services
        security-cameras:other-services hobby: books:hobby fiction:books educational-books:books textbooks:books
        comics-manga:books musical-instruments:hobby guitars:musical-instruments keyboards-piano:musical-instruments
        drums:musical-instruments wind-instruments:musical-instruments studio-gear:musical-instruments collecting:hobby
        coins:collecting stamps:collecting antiques:collecting handmade:hobby knitting:handmade embroidery:handmade
        board-games:hobby chess:board-games puzzles:board-games art-supplies:hobby art-paints:art-supplies
        art-canvas:art-supplies art-graphics:art-supplies art-easels:art-supplies model-making:hobby
        models-kits:model-making models-rc:model-making models-3d:model-making models-tools:model-making food-farm:
        fruits-vegetables:food-farm local-produce:fruits-vegetables greens:fruits-vegetables honey-natural:food-farm
        honey:honey-natural dairy:honey-natural eggs:honey-natural meat-farm:honey-natural dried-fruits:honey-natural
        jam-preserves:honey-natural seedlings:food-farm fruit-seedlings:seedlings veg-seedlings:seedlings
        farm-equipment:food-farm farm-tractors:farm-equipment farm-tools:farm-equipment farm-irrigation:farm-equipment
        beekeeping:food-farm bee-hives:beekeeping bee-tools:beekeeping bee-families:beekeeping fertilizers:food-farm
        fert-mineral:fertilizers fert-organic:fertilizers fert-protection:fertilizers grocery:food-farm
        grocery-sauces:grocery grocery-oil:grocery grocery-cereals:grocery grocery-canned:grocery grocery-sweets:grocery
        grocery-drinks:grocery grocery-tea-coffee:grocery grocery-bakery:grocery grocery-frozen:grocery
        grocery-other:grocery beauty: beauty-perfume:beauty perfume-women:beauty-perfume perfume-men:beauty-perfume
        perfume-unisex:beauty-perfume perfume-sets:beauty-perfume beauty-makeup:beauty makeup-face:beauty-makeup
        makeup-eyes:beauty-makeup makeup-lips:beauty-makeup makeup-brushes:beauty-makeup makeup-sets:beauty-makeup
        beauty-skincare:beauty skincare-face:beauty-skincare skincare-masks:beauty-skincare skincare-sun:beauty-skincare
        skincare-problem:beauty-skincare beauty-haircare:beauty hair-shampoo:beauty-haircare
        hair-treatment:beauty-haircare hair-color:beauty-haircare hair-styling:beauty-haircare beauty-bodycare:beauty
        body-shower:beauty-bodycare body-cream:beauty-bodycare body-hygiene:beauty-bodycare body-shaving:beauty-bodycare
        beauty-manicure:beauty nails-polish:beauty-manicure nails-tools:beauty-manicure nails-lamps:beauty-manicure
        nails-care:beauty-manicure beauty-appliances:beauty beauty-hairdryers:beauty-appliances
        beauty-clippers:beauty-appliances beauty-epilators:beauty-appliances beauty-face-devices:beauty-appliances
        beauty-vitamins:beauty vitamins-complex:beauty-vitamins vitamins-sport:beauty-vitamins
        vitamins-herbal:beauty-vitamins beauty-medical:beauty med-diagnostic:beauty-medical med-rehab:beauty-medical
        med-massage:beauty-medical med-supplies:beauty-medical beauty-optics:beauty optics-glasses:beauty-optics
        optics-sun:beauty-optics optics-lenses:beauty-optics beauty-other:beauty
        """
}

extension SiteSession {
    /**
     Названия разделов для хлебных крошек — у загруженной страницы сайта, её же mkCatName: на языке страницы и ровно так,
     как их пишет сайт. Ответ — словарь «раздел → название» только для найденных. Страница не загружена, скрипта нет или
     ответ не разобрался — пусто, и крошки покажут то, что знают сами.
     */
    @MainActor
    static func названияРазделов(_ разделы: [String]) async -> [String: String] {
        guard !разделы.isEmpty, let web = WebBridge.shared.webView, WebBridge.shared.isLoaded,
              let данные = try? JSONSerialization.data(withJSONObject: разделы),
              let список = String(data: данные, encoding: .utf8) else { return [:] }
        /* Список разделов — JSON-литералом, а не склейкой строк: имя раздела не должно стать кодом страницы. */
        /* 🔴 mkCatName без раздела в MK_CFLAT (страница кабинета, раздел новее страницы) отдаёт tt("category") —
           «Категория». Это не имя: владелец увидел его в крошках (TestFlight 26.09.2026). Такой ответ отбрасываем, и
           крошки берут имя из снимка (ИменаРазделовСайта) или показывают корень. */
        var js = "(function(a){try{var F=(typeof MK_CFLAT!=='undefined')?MK_CFLAT:null;var r={};"
        js += "var fb='';try{fb=(typeof tt==='function')?String(tt('category')||''):'';}catch(e){}"
        js += "a.forEach(function(k){var n='';if(F&&F[k])n=String(F[k].name||'');"
        js += "if(!n){try{n=(typeof mkCatName==='function')?String(mkCatName(k)||''):'';}catch(e){}}"
        js += "if(n&&n!==fb&&n!=='Категория')r[k]=n;});return JSON.stringify(r);}catch(e){return '{}';}})("
        js += список + ")"
        guard let строка = try? await web.evaluateJavaScript(js) as? String,
              let ответ = строка.data(using: .utf8),
              let словарь = try? JSONSerialization.jsonObject(with: ответ) as? [String: String] else { return [:] }
        return словарь
    }
}

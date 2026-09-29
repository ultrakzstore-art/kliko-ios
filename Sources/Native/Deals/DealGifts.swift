import SwiftUI

/**
 «ПОДАРКИ МНЕ» В «МОИХ СДЕЛКАХ» — получатель подарка видит, что ему отправили.

 Покупатель может отправить товар другому человеку («Кому передать», DealRecipient.swift). Получатель — не сторона
 сделки: в my_deals её нет. Сервер отдаёт свой список: GET escrow.php?action=gifts → {ok, gifts:[{id, title, img, from,
 stage, created_at, track{carrier, carrier_name, track_no, status}}]} (docs/SERVER_TRACKING.md §9) — только вошедшему с
 подтверждённым номером, равным номеру получателя, и без цены и данных покупателя. Раздел виден, только когда список
 не пуст. Нажатие — экран подарка: шапка «Вам отправили подарок» и отслеживание (action=track пускает role=recipient).
 Действий покупателя (подтвердить, спор) здесь нет — их у получателя нет и на сайте.
 */
struct ПодарокМне: Identifiable, Equatable {
    let id: String
    let название: String
    let фото: String
    let отКого: String
    let этап: String
    let создана: String
    let перевозчик: String
    let имяПеревозчика: String
    let трек: String
    let статусТрека: String

    init?(_ d: [String: Any]) {
        let номер = СделкиAPI.строка(d["id"])
        guard СделкиAPI.годныйНомер(номер) else { return nil }
        id = номер
        название = СделкиAPI.строка(d["title"]).trimmingCharacters(in: .whitespaces)
        фото = СделкиAPI.строка(d["img"]).trimmingCharacters(in: .whitespaces)
        отКого = СделкиAPI.строка(d["from"]).trimmingCharacters(in: .whitespaces)
        этап = СделкиAPI.строка(d["stage"])
        создана = СделкиAPI.строка(d["created_at"])
        let т = d["track"] as? [String: Any] ?? [:]
        перевозчик = СделкиAPI.строка(т["carrier"])
        имяПеревозчика = СделкиAPI.строка(т["carrier_name"]).trimmingCharacters(in: .whitespaces)
        трек = СделкиAPI.строка(т["track_no"]).trimmingCharacters(in: .whitespaces)
        статусТрека = СделкиAPI.строка(т["status"])
    }

    /// «СДЭК · В пути · 1234567890»; нечего сказать — пусто.
    var строкаДоставки: String {
        var части: [String] = []
        if !имяПеревозчика.isEmpty {
            части.append(имяПеревозчика)
        } else if !перевозчик.isEmpty {
            части.append(ПеревозчикТрека(код: перевозчик).название)
        }
        let статус = СтатусТрека(код: статусТрека)
        if !статусТрека.isEmpty && статус != .неизвестно { части.append(статус.коротко) }
        if !трек.isEmpty { части.append(трек.слеваНаправо) }
        return части.joined(separator: " · ")
    }

    /// Плашка этапа: preparing · on_way · delivered · closed.
    var плашка: (вид: ВидСтатусаСделки, символ: String, текст: String) {
        switch этап {
        case "preparing": return (.инфо, "shippingbox", ПодаркиText.т("st_preparing"))
        case "on_way":    return (.предупреждение, "box.truck", ПодаркиText.т("st_on_way"))
        case "delivered": return (.хорошо, "checkmark.seal", ПодаркиText.т("st_delivered"))
        case "closed":    return (.серый, "xmark", ПодаркиText.т("st_closed"))
        default:          return (.серый, "gift", ПодаркиText.т("st_gift"))
        }
    }
}

/// Список «Подарки мне» экрана «Мои сделки»: живёт, пока открыт экран; выход — пусто.
@MainActor
final class ПодаркиМнеМодель: ObservableObject {
    @Published private(set) var список: [ПодарокМне] = []
    private var поколение = 0

    /// Тихо: нет сети, нет входа или сервер без action=gifts — список прежний (или пустой, раздела нет).
    func загрузить() async {
        let моё = поколение
        guard let j = try? await СделкиAPI.получить("escrow.php?action=gifts"), моё == поколение else { return }
        guard СделкиAPI.да(j["ok"]) else {
            if МоиОбъявленияAPI.нетСессии(j) { список = [] }
            return
        }
        let сырые: [Any] = (j["gifts"] as? [Any]) ?? []
        список = сырые.compactMap { з -> ПодарокМне? in
            guard let d = з as? [String: Any] else { return nil }
            return ПодарокМне(d)
        }
    }

    func стереть() {
        поколение += 1
        список = []
    }
}

// MARK: - Раздел в списке

struct СекцияПодарковМне: View {
    @ObservedObject var модель: ПодаркиМнеМодель

    var body: some View {
        if !модель.список.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.акцент)
                        .accessibilityHidden(true)
                    Text(ПодаркиText.т("section"))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                ForEach(модель.список) { подарок in
                    NavigationLink {
                        ЭкранПодаркаМне(подарок: подарок)
                    } label: {
                        КарточкаПодаркаМне(подарок: подарок)
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                }
            }
            .padding(.bottom, 4)
        }
    }
}

/// Строка подарка: фото, название, «От: имя · дата», плашка этапа, перевозчик и трек.
struct КарточкаПодаркаМне: View {
    let подарок: ПодарокМне

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                ФотоПодаркаМне(адрес: подарок.фото, размер: 46)
                VStack(alignment: .leading, spacing: 1) {
                    Text(подарок.название.isEmpty ? ПодаркиText.т("item_fallback") : подарок.название)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    Text(мета)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ПлашкаПодаркаМне(подарок: подарок)
            }
            if !подарок.строкаДоставки.isEmpty {
                Label(подарок.строкаДоставки, systemImage: "shippingbox")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var мета: String {
        var части: [String] = []
        if !подарок.отКого.isEmpty {
            части.append(String(format: ПодаркиText.т("from"), подарок.отКого))
        }
        let дата = СделкиФормат.деньМесяц(подарок.создана)
        if !дата.isEmpty { части.append(дата) }
        return части.joined(separator: " · ")
    }
}

struct ПлашкаПодаркаМне: View {
    let подарок: ПодарокМне

    var body: some View {
        let п = подарок.плашка
        HStack(spacing: 6) {
            Image(systemName: п.символ)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(п.текст)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .foregroundStyle(п.вид.текст)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(п.вид.фон, in: Capsule())
        .frame(maxWidth: 150, alignment: .trailing)
    }
}

struct ФотоПодаркаМне: View {
    let адрес: String
    let размер: CGFloat

    var body: some View {
        КартинкаЛенты(Config.url(адрес), пунктов: размер) {
            ZStack {
                Theme.поверхность2
                Image(systemName: "gift")
                    .font(.system(size: размер * 0.35))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .frame(width: размер, height: размер)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Экран подарка

/// «Вам отправили подарок» и отслеживание доставки. Без цены, без данных покупателя, без действий сделки.
struct ЭкранПодаркаМне: View {
    let подарок: ПодарокМне

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                шапка
                БлокОтслеживания(сделка: подарок.id)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(ПодаркиText.т("screen_title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var шапка: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(ПодаркиText.т("hero"), systemImage: "gift.fill")
                .font(.headline)
                .foregroundStyle(Theme.акцент)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .center, spacing: 12) {
                ФотоПодаркаМне(адрес: подарок.фото, размер: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(подарок.название.isEmpty ? ПодаркиText.т("item_fallback") : подарок.название)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                    if !подарок.отКого.isEmpty {
                        Text(String(format: ПодаркиText.т("from"), подарок.отКого))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.текстВторой)
                    }
                    ПлашкаПодаркаМне(подарок: подарок)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(ПодаркиText.т("hero_sub"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Тексты

/// Тексты «Подарков мне»: ru, kk, en, ar (язык — как у сделок).
enum ПодаркиText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? ru
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = ["ru": ru, "kk": kk, "en": en, "ar": ar]

    private static let ru: [String: String] = [
        "section": "Подарки мне",
        "screen_title": "Подарок",
        "hero": "Вам отправили подарок",
        "hero_sub": "Цену и данные отправителя мы не показываем. Когда курьер или перевозчик повезёт посылку, статусы появятся ниже.",
        "from": "От: %@",
        "item_fallback": "Товар",
        "st_preparing": "Готовят к отправке",
        "st_on_way": "В пути",
        "st_delivered": "Доставлен",
        "st_closed": "Закрыт",
        "st_gift": "Подарок",
    ]

    private static let kk: [String: String] = [
        "section": "Маған сыйлықтар",
        "screen_title": "Сыйлық",
        "hero": "Сізге сыйлық жіберілді",
        "hero_sub": "Бағасы мен жіберушінің деректерін көрсетпейміз. Курьер не тасымалдаушы жолға шыққанда, мәртебелер төменде пайда болады.",
        "from": "Жіберген: %@",
        "item_fallback": "Тауар",
        "st_preparing": "Жөнелтуге дайындалуда",
        "st_on_way": "Жолда",
        "st_delivered": "Жеткізілді",
        "st_closed": "Жабылды",
        "st_gift": "Сыйлық",
    ]

    private static let en: [String: String] = [
        "section": "Gifts for me",
        "screen_title": "Gift",
        "hero": "Someone sent you a gift",
        "hero_sub": "We don't show the price or the sender's details. Once a courier or carrier is on the way, the statuses will appear below.",
        "from": "From: %@",
        "item_fallback": "Item",
        "st_preparing": "Being prepared",
        "st_on_way": "On the way",
        "st_delivered": "Delivered",
        "st_closed": "Closed",
        "st_gift": "Gift",
    ]

    private static let ar: [String: String] = [
        "section": "هدايا لي",
        "screen_title": "هدية",
        "hero": "لقد أُرسلت إليك هدية",
        "hero_sub": "لا نعرض السعر ولا بيانات المرسل. عندما ينطلق الساعي أو شركة الشحن بالطرد ستظهر الحالات أدناه.",
        "from": "من: %@",
        "item_fallback": "منتج",
        "st_preparing": "قيد التجهيز للإرسال",
        "st_on_way": "في الطريق",
        "st_delivered": "تم التوصيل",
        "st_closed": "مغلق",
        "st_gift": "هدية",
    ]
}

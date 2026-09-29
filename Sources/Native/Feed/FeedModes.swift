import Foundation
import SwiftUI

/**
 ПОРЯДОК ЛЕНТЫ У СЕБЯ: «СТАРЫЕ», «ПО РЕЙТИНГУ», «РЯДОМ СО МНОЙ» И РЕЖИМ «АРЕНДА» — как mkRender сайта
 (js/marketplace.min.js, 26.09.2026).

   · Режим аренды (mkSt.intent = "rent"): в выдаче только сдаваемое — s = n.filter(!(rent && !t.for_rent)); запрос несёт
     intent=rent (ListingsAPI.Запрос.аренда);
   · «Старые» (date_asc) и «По рейтингу» (rating): сервер отдаёт sort=new и sort=reco, а страница сортирует ВСЁ
     загруженное у себя — created_ts от старых к новым и seller_rating от высокого к низкому; золота нет (_top=false у всех).
     Так же «новые подряд» — date_desc ссылки ?sort=new: сервер — sort=new, страница — created_ts от новых к старым.
     Поэтому, как у сайта, с каждой подгрузкой лента этих порядков перестраивается целиком;
   · «Рядом со мной» (mkSt.near, при известной точке): после любого порядка — всё по расстоянию (без координат — в конец,
     99999 км) и mkNearRhythm: ТОП (is_top и не снятые) и прочие по расстоянию, вместе — mkGoldRhythm с тактом раздела
     (mkGoldBeat: 1 и 5 у транспорта и недвижимости, иначе 3 и 10); в услугах золота нет — просто по расстоянию.
 */
extension FeedModel {

    /// Порядок ставит телефон по всему загруженному: «Старые», «По рейтингу», «новые подряд» (date_desc ссылки ?sort=new)
    /// или «Рядом со мной».
    static func порядокНаТелефоне(_ сортировка: СортировкаЛенты, рядом: Bool) -> Bool {
        рядом || сортировка == .старые || сортировка == .поРейтингу || сортировка == .новыеПодряд
    }

    /// Режим аренды — только сдаваемое (for_rent), как фильтр s в mkRender.
    static func поРежиму(_ товары: [Listing], аренда: Bool) -> [Listing] {
        guard аренда else { return товары }
        return товары.filter { $0.forRent }
    }

    /// Вся лента заново из загруженного: порядок сайта для «Старых», «По рейтингу» и «Рядом».
    func собратьНаТелефоне(_ з: ListingsAPI.Запрос) -> [ЯчейкаЛенты] {
        var были = Set<String>()
        var товары: [Listing] = []
        for товар in Self.поРежиму(items, аренда: з.аренда) where !были.contains(товар.id) {
            были.insert(товар.id)
            товары.append(товар)
        }
        switch з.фильтры.сортировка {
        case .старые:
            товары = Self.устойчиво(товары) { $0.созданоСекунд < $1.созданоСекунд }
        case .поРейтингу:
            товары = Self.устойчиво(товары) { ($0.рейтингПродавца ?? 0) > ($1.рейтингПродавца ?? 0) }
        case .новыеПодряд:
            /* date_desc: mkRender — s.sort((t, e) => e.created_ts - t.created_ts), золота нет. */
            товары = Self.устойчиво(товары) { $0.созданоСекунд > $1.созданоСекунд }
        case .новые, .рекомендуемые, .дешевле, .дороже:
            break
        }
        guard рядом, ГеоЛенты.shared.точка != nil else {
            return ЯчейкаЛенты.подряд(товары, начиная: 0, топ: { _ in false })
        }
        let гео = ГеоЛенты.shared
        func даль(_ т: Listing) -> Double { гео.км(до: т) ?? 99_999 }
        let поРасстоянию = Self.устойчиво(товары) { даль($0) < даль($1) }
        if РазделыСайта.корень(з.cat) == "services" {
            return ЯчейкаЛенты.подряд(поРасстоянию, начиная: 0, топ: { _ in false })
        }
        let топ = поРасстоянию.filter { $0.isTop && $0.активно }
        let прочие = поРасстоянию.filter { !($0.isTop && $0.активно) }
        let места = Self.золотойРитмСайта(топ, прочие, такт: ЗолотойРитм.Такт.для(раздела: з.cat))
        return места.enumerated().map { пара in
            ЯчейкаЛенты(id: String(пара.offset) + "-" + пара.element.товар.id, товар: пара.element.товар,
                        топ: пара.element.золото)
        }
    }

    /// Устойчивая сортировка, как Array.prototype.sort современных движков: равные — в прежнем порядке.
    static func устойчиво(_ товары: [Listing], _ раньше: (Listing, Listing) -> Bool) -> [Listing] {
        товары.enumerated()
            .sorted { a, b in
                if раньше(a.element, b.element) { return true }
                if раньше(b.element, a.element) { return false }
                return a.offset < b.offset
            }
            .map { $0.element }
    }

    /**
     mkGoldRhythm сайта как есть (для «Рядом»): блок из `такт.топ` золотых мест — ТОП по очереди, кончились — по кругу без
     повтора в блоке; затем `такт.обычных` прочих; прочие кончились — не бывшие в золоте ТОП идут обычными местами.
     */
    static func золотойРитмСайта(_ топ: [Listing], _ прочие: [Listing],
                                 такт: ЗолотойРитм.Такт) -> [(товар: Listing, золото: Bool)] {
        let g = max(1, такт.топ)
        let f = max(1, такт.обычных)
        let i = топ.count
        let a = прочие.count
        var итог: [(товар: Listing, золото: Bool)] = []
        var c = 0
        var l = 0
        var m = 0
        var шагов = 0
        while (c < a || l < i) && шагов < 100_000 {
            шагов += 1
            var вБлоке = Set<Int>()
            if i > 0 {
                for _ in 0..<g {
                    var p = -1
                    if l < i {
                        p = l
                        l += 1
                    } else {
                        for _ in 0..<i {
                            let v = m % i
                            m += 1
                            if !вБлоке.contains(v) {
                                p = v
                                break
                            }
                        }
                    }
                    if p < 0 { break }
                    вБлоке.insert(p)
                    итог.append((товар: топ[p], золото: true))
                }
            }
            for _ in 0..<f {
                if c < a {
                    итог.append((товар: прочие[c], золото: false))
                    c += 1
                } else if l < i {
                    итог.append((товар: топ[l], золото: false))
                    l += 1
                } else {
                    break
                }
            }
        }
        return итог
    }
}

// MARK: - Режим аренды у карточки

private struct КлючРежимаАренды: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Лента в режиме «Аренда»: цена карточки — аренды (mkPriceHTML, ветка intent == "rent").
    var режимАренды: Bool {
        get { self[КлючРежимаАренды.self] }
        set { self[КлючРежимаАренды.self] = newValue }
    }
}

import SwiftUI
import UIKit

/**
 ДОЛГОЕ НАЖАТИЕ — КОНТЕКСТНЫЕ МЕНЮ (владелец 07.10.2026: «где есть возможность 3D Touch — были функции»).

 На нынешних iPhone 3D Touch заменило долгое нажатие (Haptic Touch): карточка приподнимается крупным превью, под ним —
 меню. Здесь — меню карточки объявления (лента, главная, избранное, витрина продавца, поиск по фото, похожие), общее для
 всех мест: «Открыть», «В избранное» / «Убрать из избранного», «Поделиться», «QR-код», «Написать продавцу».

 Только существующие действия, без новых запросов: избранное — FavoritesStore, «Поделиться» — лист ленты
 (ЛистПоделитьсяСайта), «QR-код» — окно ЛистQRОбъявления, «Написать продавцу» — намерение карточки ?chat=1
 (НамеренияОбъявления): карточка открывается и сама ведёт в чат — гостю сначала вход, своё объявление чат не открывает.

 «Открыть» кладёт объявление в стек, где лежит карточка, — путь стека даёт окружение открытьОбъявлениеВСтеке (ставят
 стеки с маршрутом Listing: лента, «Избранное», «Кабинет», витрина продавца). Нет его — пункта нет, карточку открывает
 обычное нажатие. Отдельного экрана «Похожие» в приложении нет (только полоса внизу карточки) — такого пункта тоже нет.

 Отклик: системный «тик» долгого нажатия даёт само меню; сердце карточки (КнопкаИзбранного) отзывается на смену
 избранного своим откликВыбора.
 */

private struct КлючОткрытьОбъявлениеВСтеке: EnvironmentKey {
    static let defaultValue: ((Listing) -> Void)? = nil
}

extension EnvironmentValues {
    /// Положить объявление в стек, где лежит карточка (пункт «Открыть» меню долгого нажатия); nil — стека с путём нет.
    var открытьОбъявлениеВСтеке: ((Listing) -> Void)? {
        get { self[КлючОткрытьОбъявлениеВСтеке.self] }
        set { self[КлючОткрытьОбъявлениеВСтеке.self] = newValue }
    }
}

extension View {
    /// Меню долгого нажатия карточки объявления с крупным превью (фото, цена, название).
    func менюКарточкиОбъявления(_ товар: Listing) -> some View {
        modifier(МенюКарточкиОбъявления(товар: товар))
    }
}

/// Пункты и превью меню карточки объявления.
struct МенюКарточкиОбъявления: ViewModifier {
    let товар: Listing
    @Environment(\.открытьОбъявлениеВСтеке) private var открытьВСтеке
    @ObservedObject private var избранное = FavoritesStore.shared

    private func т(_ ключ: String) -> String { МенюДолгогоНажатияText.т(ключ) }

    /// Своё объявление вошедшего — «Написать продавцу» не нужен. Номер продавца в карточке ленты бывает не всегда:
    /// тогда пункт есть, а своё распознает уже сама карточка.
    private var своё: Bool {
        let я = СессияПриложения.shared.id
        guard !я.isEmpty, let продавец = товар.продавецID else { return false }
        return я == продавец
    }

    private var можноОткрыть: Bool { Config.нативнаяКарточка && открытьВСтеке != nil }

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if можноОткрыть {
                    Button {
                        НамеренияОбъявления.shared.положить(.нет, для: товар.id)
                        открытьВСтеке?(товар)
                    } label: {
                        Label(т("open"), systemImage: "arrow.up.forward.square")
                    }
                }
                if Config.избранное {
                    let есть = избранное.есть(товар.id)
                    Button {
                        избранное.переключить(товар)
                    } label: {
                        Label(FavoritesText.т(есть ? "remove" : "add"), systemImage: есть ? "heart.slash" : "heart")
                    }
                }
                if товар.адрес != nil {
                    Button {
                        Task { @MainActor in ЛистПоделитьсяСайта.показать(товар) }
                    } label: {
                        Label(т("share"), systemImage: "square.and.arrow.up")
                    }
                    Button {
                        Task { @MainActor in ОкноQRПоверх.показать(ДанныеОтправкиСайта(товар)) }
                    } label: {
                        Label(т("qr"), systemImage: "qrcode")
                    }
                }
                if можноОткрыть && Config.нативныйЧат && !своё {
                    Button {
                        НамеренияОбъявления.shared.положить(.чат, для: товар.id)
                        открытьВСтеке?(товар)
                    } label: {
                        Label(т("write"), systemImage: "bubble.left.and.bubble.right")
                    }
                }
            } preview: {
                ПревьюОбъявленияМеню(товар: товар)
            }
    }
}

/// Превью долгого нажатия: крупное фото 4:3, цена и название в две строки.
struct ПревьюОбъявленияМеню: View {
    let товар: Listing
    private let вид: ВидКарточки

    init(товар: Listing) {
        self.товар = товар
        self.вид = КэшВидаКарточек.shared.вид(товар)
    }

    private var цена: String {
        let сумма = товар.price ?? 0
        return сумма > 0 ? ЦенаКарточкиСайта.полная(сумма) : ListingPageText.т("negotiable")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            КартинкаЛенты(вид.обложка, пунктов: 320) {
                ZStack {
                    Theme.поверхность2
                    Image(systemName: вид.значокЗаглушки)
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            .frame(width: 320, height: 240)
            .clipped()
            VStack(alignment: .leading, spacing: 4) {
                Text(цена)
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(товар.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !товар.city.isEmpty {
                    Text(товар.city)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(width: 320, alignment: .leading)
        }
        .background(Theme.поверхность)
    }
}

/// Окно QR-кода объявления поверх всего — из меню долгого нажатия, где своего листа у экрана нет.
@MainActor
enum ОкноQRПоверх {
    static func показать(_ данные: ДанныеОтправкиСайта, ссылка: URL? = nil) {
        guard let верх = ПоделитьсяСайта.верхнийЭкран() else { return }
        let хост = UIHostingController(rootView: ЛистQRОбъявления(данные: данные, ссылка: ссылка))
        хост.view.backgroundColor = UIColor(Theme.поверхность)
        верх.present(хост, animated: true)
    }
}

/// Подписи пунктов меню долгого нажатия на языке телефона (kk/ru/en/ar).
enum МенюДолгогоНажатияText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["open": "Открыть", "share": "Поделиться", "qr": "QR-код", "write": "Написать продавцу",
               "copy_deal": "Скопировать номер", "copied": "Номер скопирован"],
        "kk": ["open": "Ашу", "share": "Бөлісу", "qr": "QR-код", "write": "Сатушыға жазу",
               "copy_deal": "Нөмірді көшіру", "copied": "Нөмір көшірілді"],
        "en": ["open": "Open", "share": "Share", "qr": "QR code", "write": "Message seller",
               "copy_deal": "Copy number", "copied": "Number copied"],
        "ar": ["open": "فتح", "share": "مشاركة", "qr": "رمز QR", "write": "راسل البائع",
               "copy_deal": "نسخ الرقم", "copied": "تم نسخ الرقم"]
    ]
}

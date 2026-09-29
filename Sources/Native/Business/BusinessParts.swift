import SwiftUI

/**
 ОБЩИЕ ДЕТАЛИ ЭКРАНОВ ЭТАПА 48 (владелец 26.09.2026: «всё одно и то же, просто код разный»): карточка раздела в краске
 сайта (.promo-facts, .split-card, .club-card), заметка, строка «название — значение», цена со старой зачёркнутой и
 «ворота» цифровой покупки. Краски — только динамические Theme / КраскаОбъявлений (светлая и тёмная тема, этап 31).
 */

/// Краски бизнес-экранов, которые у сайта одинаковы в светлой и тёмной теме.
enum КраскаБизнеса {
    /// .split-cta, .club-btn.pri: linear-gradient(135deg,#16a34a,#0f7a44).
    static let градиентКнопки = LinearGradient(colors: [Color(uiColor: Theme.hex(0x16A34A)), Color(uiColor: Theme.hex(0x0F7A44))],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Заметка без подложки (.split-note, .club-note): значок акцентом и серый текст 12.
struct СтрокаЗаметкиБизнеса: View {
    let текст: String
    let значок: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: значок)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Карточка раздела: заголовок со значком и содержимое.
struct КарточкаБизнеса<Содержимое: View>: View {
    let заголовок: String
    let значок: String
    let содержимое: Содержимое

    init(_ заголовок: String, значок: String, @ViewBuilder содержимое: () -> Содержимое) {
        self.заголовок = заголовок
        self.значок = значок
        self.содержимое = содержимое()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(заголовок, systemImage: значок)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            содержимое
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }
}

/// Заметка сайта (.split-note, .ai-note, .promo-fact): значок и текст на цветной подложке.
struct ЗаметкаБизнеса: View {
    enum Тон: Equatable {
        case серый
        case предупреждение
        case хорошо
        case плохо
        case инфо
    }

    let текст: String
    let тон: Тон
    let значок: String

    init(_ текст: String, тон: Тон = .серый, значок: String = "info.circle") {
        self.текст = текст
        self.тон = тон
        self.значок = значок
    }

    private var краска: Color {
        switch тон {
        case .серый: return Theme.текстВторой
        case .предупреждение: return КраскаОбъявлений.предупреждениеТекст
        case .хорошо: return КраскаОбъявлений.хорошоТекст
        case .плохо: return КраскаОбъявлений.плохоТекст
        case .инфо: return КраскаОбъявлений.инфоТекст
        }
    }

    private var фон: Color {
        switch тон {
        case .серый: return Theme.поверхность2
        case .предупреждение: return КраскаОбъявлений.предупреждениеФон
        case .хорошо: return КраскаОбъявлений.хорошоФон
        case .плохо: return КраскаОбъявлений.плохоФон
        case .инфо: return КраскаОбъявлений.инфоФон
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: значок)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(краска)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 13))
                .foregroundStyle(тон == .серый ? Theme.текстВторой : краска)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Строка «название — значение» (.promo-fact, .rw-rev .r сайта).
struct СтрокаЗначенияБизнеса: View {
    let название: String
    let значение: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(название)
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 8)
            Text(значение)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Цена «<s>старая</s> новая ₸» (promoFmt / numFmt сайта). Старая — только если больше новой.
struct ЦенаБизнеса: View {
    let старая: Int?
    let цена: Int
    var бесплатно: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let бесплатно {
                Text(бесплатно)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(КраскаОбъявлений.хорошоТекст)
            } else {
                if let старая, старая > цена {
                    Text(СделкиФормат.тенге(старая))
                        .font(.system(size: 12))
                        .strikethrough()
                        .foregroundStyle(Theme.текстВторой)
                }
                Text(СделкиФормат.тенге(цена))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Значок-метка («Максимум», «текущий», «Выгоднее всего», «Ваш тариф»).
struct МеткаБизнеса: View {
    let текст: String
    var золото = false

    var body: some View {
        Text(текст)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(золото ? КраскаОбъявлений.топТекст : КраскаОбъявлений.хорошоТекст)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(золото ? Theme.топФон : КраскаОбъявлений.хорошоФон, in: Capsule())
    }
}

/**
 Ворота платной цифровой услуги (ТОП, PRO, слоты, комбо, пакеты Kliko AI). Правило App Store 3.1.1: в приложении —
 только In-App Purchase.
   · Config.цифровыеПокупки = false — текст сайта «Эта возможность недоступна в приложении.» (NOTE klkAppNoDigital),
     без кнопок и без ссылок на оплату на сайте;
   · true — кнопка окна покупки App Store (ЛистУслугиApple, StoreKit 2).
 По умолчанию услуга — PRO: так звучат замки «Доступно в тарифе PRO» разделов бизнеса. Кошелёк сайта (promote_*,
 buy_*) приложение не вызывает никогда.
 */
struct ЦифроваяПокупка: View {
    var услуга: ВидУслугиApple = .про
    /// id объявления (продвижение) или резюме (ТОП резюме).
    var цель: String? = nil
    /// Подпись кнопки; nil — своя подпись услуги.
    var подпись: String? = nil

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    var body: some View {
        if Config.цифровыеПокупки {
            КнопкаПокупкиApple(подпись: подпись ?? ПокупкиAppleText.подписьУслуги(услуга), значок: услуга.значок) {
                ЛистУслугиApple.показать(услуга, цель: цель)
            }
        } else {
            ЗаметкаБизнеса(т("no_digital"), тон: .серый, значок: "lock")
        }
    }
}

/// Кнопка перехода (верификация eGov — своим окном в приложении; сайт не открывается).
struct КнопкаСайтаБизнеса: View {
    let подпись: String
    let главная: Bool
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                Text(подпись)
                    .font(.system(size: 15, weight: .bold))
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(главная ? Color.white : Theme.акцент)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(главная ? Theme.акцент : Theme.оттенокАкцента,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint(БизнесText.т("a11y_site"))
    }
}

/// Главная кнопка действия приложения (не сайт): зелёная, с колесом, пока идёт запрос.
struct КнопкаБизнеса: View {
    let подпись: String
    var занято = false
    var второстепенная = false
    let действие: () -> Void

    var body: some View {
        Button(action: действие) {
            HStack(spacing: 8) {
                if занято {
                    ProgressView()
                        .tint(второстепенная ? Theme.акцент : Color.white)
                }
                Text(подпись)
                    .font(.system(size: 15, weight: .bold))
            }
            .foregroundStyle(второстепенная ? Theme.акцент : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(второстепенная ? Theme.оттенокАкцента : Theme.акцент,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(занято)
    }
}

/// Колесо «Загрузка…» посреди экрана.
struct ЗагрузкаБизнеса: View {
    var body: some View {
        VStack(spacing: 12) {
            SiteSpinner()
            Text(БизнесText.т("loading"))
                .font(.system(size: 15))
                .foregroundStyle(Theme.текстВторой)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

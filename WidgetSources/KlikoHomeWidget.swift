import SwiftUI
import WidgetKit

/**
 ВИДЖЕТ «Kliko» НА ДОМАШНЕМ ЭКРАНЕ.
   · малый — непрочитанные сообщения и активные сделки; нажатие — «Сообщения», если есть непрочитанные, иначе «Мои сделки»;
   · средний — то же числами и до трёх активных сделок со статусом и доставкой; нажатие на сделку — её карточка.
 Данные — СнимокВиджетаKliko из App Group: пишет приложение (HomeWidgetFeed.swift) и само просит перерисовку. Свой
 запасной срок — раз в полчаса перечитать снимок (вдруг приложение обновило его, а перерисовка не дошла).
 */
private let kWidgetGreen = Color(red: 0.10, green: 0.62, blue: 0.41)

struct KlikoHomeEntry: TimelineEntry {
    let date: Date
    let снимок: СнимокВиджетаKliko
}

struct KlikoHomeProvider: TimelineProvider {
    func placeholder(in context: Context) -> KlikoHomeEntry {
        var образец = СнимокВиджетаKliko()
        образец.вошёл = true
        образец.непрочитано = 3
        образец.активных = 2
        образец.сделки = [
            .init(id: "1", название: "iPhone 15 Pro", статус: "Деньги у Kliko", символ: "lock", роль: "buyer",
                  доставка: "СДЭК · В пути"),
            .init(id: "2", название: "Диван угловой", статус: "Отправлено", символ: "square.and.arrow.up", роль: "seller")
        ]
        return KlikoHomeEntry(date: Date(), снимок: образец)
    }

    func getSnapshot(in context: Context, completion: @escaping (KlikoHomeEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(KlikoHomeEntry(date: Date(), снимок: СнимокВиджетаKliko.прочитать()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KlikoHomeEntry>) -> Void) {
        let запись = KlikoHomeEntry(date: Date(), снимок: СнимокВиджетаKliko.прочитать())
        let потом = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [запись], policy: .after(потом)))
    }
}

struct KlikoHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KlikoHome", provider: KlikoHomeProvider()) { entry in
            KlikoHomeWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Kliko")
        .description(KlikoWidgetText.т("desc"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct KlikoHomeWidgetView: View {
    @Environment(\.widgetFamily) private var семейство
    let entry: KlikoHomeEntry

    private var с: СнимокВиджетаKliko { entry.снимок }

    var body: some View {
        if !с.вошёл {
            KlikoHomeSignedOut()
                .widgetURL(СнимокВиджетаKliko.ссылкаСделок)
        } else if семейство == .systemMedium {
            KlikoHomeMedium(снимок: с)
                .widgetURL(СнимокВиджетаKliko.ссылкаСделок)
        } else {
            KlikoHomeSmall(снимок: с)
                .widgetURL(с.непрочитано > 0 ? СнимокВиджетаKliko.ссылкаСообщений : СнимокВиджетаKliko.ссылкаСделок)
        }
    }
}

// MARK: - Части

private struct KlikoHomeLogo: View {
    let size: CGFloat
    var body: some View {
        Image("KlikoLogo")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
    }
}

private struct KlikoHomeSignedOut: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            KlikoHomeLogo(size: 28)
            Spacer(minLength: 0)
            Text(KlikoWidgetText.т("signed_out"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Число и подпись: «3» / «непрочитанных».
private struct KlikoHomeCounter: View {
    let число: Int
    let подпись: String
    let символ: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: символ)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(число > 0 ? kWidgetGreen : Color.secondary)
                Text("\(число)")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
            Text(подпись)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct KlikoHomeSmall: View {
    let снимок: СнимокВиджетаKliko

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            KlikoHomeLogo(size: 26)
            Spacer(minLength: 0)
            KlikoHomeCounter(число: снимок.непрочитано, подпись: KlikoWidgetText.т("unread"),
                             символ: "bubble.left.and.bubble.right.fill")
            KlikoHomeCounter(число: снимок.активных, подпись: KlikoWidgetText.т("deals"),
                             символ: "shield.lefthalf.filled")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct KlikoHomeMedium: View {
    let снимок: СнимокВиджетаKliko

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                KlikoHomeLogo(size: 26)
                Spacer(minLength: 0)
                Link(destination: СнимокВиджетаKliko.ссылкаСообщений ?? URL(fileURLWithPath: "/")) {
                    KlikoHomeCounter(число: снимок.непрочитано, подпись: KlikoWidgetText.т("unread"),
                                     символ: "bubble.left.and.bubble.right.fill")
                }
                KlikoHomeCounter(число: снимок.активных, подпись: KlikoWidgetText.т("deals"),
                                 символ: "shield.lefthalf.filled")
            }
            .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                if снимок.сделки.isEmpty {
                    Spacer(minLength: 0)
                    Text(KlikoWidgetText.т("no_deals"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else {
                    ForEach(снимок.сделки) { сделка in
                        Link(destination: СнимокВиджетаKliko.ссылкаСделки(сделка.id) ?? URL(fileURLWithPath: "/")) {
                            KlikoHomeDealRow(сделка: сделка)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct KlikoHomeDealRow: View {
    let сделка: СнимокВиджетаKliko.Сделка

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: сделка.символ)
                .font(.caption2.weight(.bold))
                .foregroundStyle(kWidgetGreen)
                .frame(width: 14)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(сделка.название)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(сделка.доставка.isEmpty ? сделка.статус : сделка.доставка)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Тексты

enum KlikoWidgetText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": ["desc": "Непрочитанные сообщения и активные сделки", "unread": "непрочитанных",
               "deals": "активных сделок", "no_deals": "Активных сделок нет", "signed_out": "Войдите в Kliko"],
        "kk": ["desc": "Оқылмаған хабарламалар мен белсенді мәмілелер", "unread": "оқылмаған",
               "deals": "белсенді мәміле", "no_deals": "Белсенді мәміле жоқ", "signed_out": "Kliko-ға кіріңіз"],
        "en": ["desc": "Unread messages and active deals", "unread": "unread",
               "deals": "active deals", "no_deals": "No active deals", "signed_out": "Sign in to Kliko"]
    ]
}

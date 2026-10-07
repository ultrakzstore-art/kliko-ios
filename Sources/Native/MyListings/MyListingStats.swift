import SwiftUI
import Charts

/**
 СТАТИСТИКА ОБЪЯВЛЕНИЯ (владелец: «сделай всё, что предлагаешь»).

 Источник — тот же ответ my_items, что и счётчики карточки (stats сайта, inc/cabinet/bulk_deals.php): итоги
 views / likes / msgs / calls / shares / wait и списки «кто» с датой события (по 30 последних на вид). Новых запросов нет.
 По дням сайт хранит только события «кто» (избранное, сообщения, «Позвонить», «Поделились») — их и рисует график
 за 7 или 30 дней; просмотры сайт считает одним числом — у них только итог. Когда событий больше, чем последних
 записей «кто», под графиком — пометка, что по дням видны только последние.
 Вход — «Статистика» на карточке «Моих объявлений» и пункт долгого нажатия.
 */
struct ЭкранСтатистикиОбъявления: View {
    let товар: МоёОбъявление
    @Environment(\.dismiss) private var закрыть
    @State private var дней = 7

    init(товар: МоёОбъявление) {
        self.товар = товар
    }

    private func т(_ ключ: String) -> String { СтатистикаОбъявленияText.т(ключ) }
    private func м(_ ключ: String) -> String { МоиОбъявленияText.т(ключ) }

    /// Вид события сайта: ключ «кто», ключ подписи МоиОбъявленияText, значок, цвет.
    private struct Вид: Identifiable {
        let ключ: String
        let подпись: String
        let значок: String
        let цвет: Color
        var id: String { ключ }
    }

    private var виды: [Вид] {
        [
            Вид(ключ: "like", подпись: т("st_likes"), значок: "heart.fill", цвет: Color(uiColor: Theme.hex(0xE5484D))),
            Вид(ключ: "msg", подпись: т("st_msgs"), значок: "bubble.left.fill", цвет: Color(uiColor: Theme.hex(0x3B82F6))),
            Вид(ключ: "call", подпись: т("st_calls"), значок: "phone.fill", цвет: Color(uiColor: Theme.hex(0x16A34A))),
            Вид(ключ: "share", подпись: т("st_shares"), значок: "square.and.arrow.up.fill",
                цвет: Color(uiColor: Theme.hex(0xF59E0B)))
        ]
    }

    /// Одна точка графика: день, вид события, сколько.
    private struct Точка: Identifiable {
        let день: Date
        let вид: String
        let число: Int
        var id: String { вид + String(день.timeIntervalSince1970) }
    }

    private static let разборДаты: DateFormatter = {
        let ф = DateFormatter()
        ф.locale = Locale(identifier: "en_US_POSIX")
        ф.calendar = Calendar(identifier: .gregorian)
        ф.dateFormat = "yyyy-MM-dd"
        return ф
    }()

    private var началоПериода: Date {
        let сегодня = Calendar.current.startOfDay(for: Date())
        return Calendar.current.date(byAdding: .day, value: -(дней - 1), to: сегодня) ?? сегодня
    }

    /// События вида по дням внутри периода.
    private func поДням(_ ключ: String) -> [Date: Int] {
        var итог: [Date: Int] = [:]
        let начало = началоПериода
        for запись in товар.статистика.кто[ключ] ?? [] {
            guard let дата = Self.разборДаты.date(from: String(запись.когда.prefix(10))) else { continue }
            let день = Calendar.current.startOfDay(for: дата)
            guard день >= начало else { continue }
            итог[день, default: 0] += 1
        }
        return итог
    }

    private var точки: [Точка] {
        var итог: [Точка] = []
        for вид in виды {
            for (день, число) in поДням(вид.ключ) {
                итог.append(Точка(день: день, вид: вид.подпись, число: число))
            }
        }
        return итог.sorted { $0.день < $1.день }
    }

    private func всего(_ ключ: String) -> Int {
        let с = товар.статистика
        switch ключ {
        case "like": return с.избранное
        case "msg": return с.сообщения
        case "call": return с.звонки
        default: return с.поделились
        }
    }

    /// Событий больше, чем записей «кто» с датой, — по дням видны только последние.
    private var неполно: Bool {
        виды.contains { всего($0.ключ) > (товар.статистика.кто[$0.ключ]?.count ?? 0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(товар.название)
                        .font(.headline)
                        .foregroundStyle(Theme.текст)
                        .lineLimit(2)
                    итоги
                    Picker(т("st_period"), selection: $дней) {
                        Text(т("st_7")).tag(7)
                        Text(т("st_30")).tag(30)
                    }
                    .pickerStyle(.segmented)
                    график
                    заметки
                }
                .padding(16)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("st_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(т("st_done")) { закрыть() }
                }
            }
        }
    }

    // MARK: Итоги

    private var итоги: some View {
        let с = товар.статистика
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            плитка(значок: "eye.fill", подпись: м("views"), число: с.просмотры, цвет: Theme.текстВторой)
            ForEach(виды) { вид in
                плитка(значок: вид.значок, подпись: вид.подпись, число: всего(вид.ключ), цвет: вид.цвет)
            }
            if с.ждут > 0 {
                плитка(значок: "hand.raised.fill", подпись: м("wl_pill"), число: с.ждут, цвет: Theme.акцент)
            }
        }
    }

    private func плитка(значок: String, подпись: String, число: Int, цвет: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: значок)
                .font(.subheadline)
                .foregroundStyle(цвет)
                .accessibilityHidden(true)
            Text(String(число))
                .font(.title2.weight(.heavy).monospacedDigit())
                .foregroundStyle(Theme.текст)
            Text(подпись)
                .font(.caption)
                .foregroundStyle(Theme.текстВторой)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: График

    @ViewBuilder
    private var график: some View {
        let данные = точки
        VStack(alignment: .leading, spacing: 10) {
            Text(т("st_by_day"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            if данные.isEmpty {
                Text(т("st_empty"))
                    .font(.footnote)
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .multilineTextAlignment(.center)
            } else {
                Chart(данные) { точка in
                    BarMark(x: .value("day", точка.день, unit: .day), y: .value("count", точка.число))
                        .foregroundStyle(by: .value("kind", точка.вид))
                }
                .chartForegroundStyleScale(domain: виды.map { $0.подпись }, range: виды.map { $0.цвет })
                .chartXScale(domain: началоПериода...Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400))
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 220)
                .accessibilityLabel(т("st_by_day"))
            }
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private var заметки: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(т("st_views_note"))
            if неполно { Text(т("st_partial")) }
        }
        .font(.caption)
        .foregroundStyle(Theme.текстВторой)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// «Статистика» под счётчиками карточки.
struct КнопкаСтатистикиОбъявления: View {
    let действие: () -> Void

    init(действие: @escaping () -> Void) {
        self.действие = действие
    }

    var body: some View {
        Button(action: действие) {
            Label(СтатистикаОбъявленияText.т("st_title"), systemImage: "chart.bar.xaxis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.акцент)
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}

// MARK: - Тексты (ru / kk / en / ar)

enum СтатистикаОбъявленияText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь: [String: String]
        switch язык {
        case "kk": словарь = kk
        case "en": словарь = en
        case "ar": словарь = ar
        default: словарь = ru
        }
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let ru: [String: String] = [
        "st_title": "Статистика", "st_done": "Готово", "st_period": "Период",
        "st_7": "7 дней", "st_30": "30 дней", "st_by_day": "По дням",
        "st_likes": "В избранное", "st_msgs": "Сообщения", "st_calls": "Показы телефона", "st_shares": "Поделились",
        "st_empty": "За этот период событий не было",
        "st_views_note": "Просмотры сайт считает общим числом — по дням их нет.",
        "st_partial": "По дням показаны последние события каждого вида — итоги выше полные."
    ]

    private static let kk: [String: String] = [
        "st_title": "Статистика", "st_done": "Дайын", "st_period": "Кезең",
        "st_7": "7 күн", "st_30": "30 күн", "st_by_day": "Күндер бойынша",
        "st_likes": "Таңдаулыға", "st_msgs": "Хабарламалар", "st_calls": "Телефонды ашқандар", "st_shares": "Бөлісті",
        "st_empty": "Бұл кезеңде оқиға болған жоқ",
        "st_views_note": "Қаралымдарды сайт жалпы санмен есептейді — күндер бойынша жоқ.",
        "st_partial": "Күндер бойынша әр түрдің соңғы оқиғалары көрсетілген — жоғарыдағы қорытынды толық."
    ]

    private static let en: [String: String] = [
        "st_title": "Statistics", "st_done": "Done", "st_period": "Period",
        "st_7": "7 days", "st_30": "30 days", "st_by_day": "By day",
        "st_likes": "Favorites", "st_msgs": "Messages", "st_calls": "Phone reveals", "st_shares": "Shares",
        "st_empty": "No activity in this period",
        "st_views_note": "Views are counted as a single total — there is no daily breakdown.",
        "st_partial": "The daily chart shows the latest events of each kind — totals above are complete."
    ]

    private static let ar: [String: String] = [
        "st_title": "الإحصاءات", "st_done": "تم", "st_period": "الفترة",
        "st_7": "7 أيام", "st_30": "30 يومًا", "st_by_day": "حسب اليوم",
        "st_likes": "المفضلة", "st_msgs": "الرسائل", "st_calls": "إظهار الهاتف", "st_shares": "المشاركات",
        "st_empty": "لا نشاط في هذه الفترة",
        "st_views_note": "تُحسب المشاهدات كرقم إجمالي — بلا تفصيل يومي.",
        "st_partial": "يعرض الرسم اليومي آخر الأحداث من كل نوع — الإجماليات أعلاه كاملة."
    ]
}

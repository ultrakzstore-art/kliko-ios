import SwiftUI

/**
 ЛЕНТА НА ЗАПУСКЕ — ВМЕСТО ПУСТОГО СПЛЭША.

 Владелец 24.09.2026: «когда интернет кончается — очень долго работает»; «а если пересобрать на Swift».

 Полностью нативным приложение делать не стали: ядро продукта (гарант-сделка, проверка личности через eGov,
 оплата) всё равно живёт веб-страницами, а переписать 64 тысячи строк клиентского кода значит потерять главное
 — выкладку за минуту вместо ожидания ревью Apple. Но экран, на котором человек проводит почти всё время, —
 лента — на старте показывается нативно, и это снимает самое заметное ожидание.

 Что видно: те же разделы в том же порядке и с теми же красками, что на сайте, по десять карточек в ряд.
 Данные — снимок, присланный страницей в прошлый заход (FeedSnapshot), поэтому лента открывается мгновенно и
 без сети. Под ней в это же время грузится настоящая страница; как только она готова, обёртка убирает превью.

 🔴 ЭТО ПОКАЗ, А НЕ ВТОРАЯ ВИТРИНА. Здесь нет фильтров, поиска, избранного и корзины: всё это уже есть на
 странице, и вторая их копия неизбежно разойдётся с первой. Нажатие на карточку не открывает товар здесь —
 оно говорит странице, куда идти, и та открывает объявление у себя. Одна витрина, один набор правил.
 */
struct FeedPreview: View {
    let снимок: FeedSnapshot
    /// Нажали карточку: отдаём адрес обёртке, страница откроет объявление сама.
    let открыть: (URL) -> Void

    @State private var ждём: String?          // номер объявления, которое уже попросили открыть

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground).ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    шапка
                    ForEach(снимок.rows) { ряд in
                        if !ряд.items.isEmpty { полка(ряд) }
                    }
                    Color.clear.frame(height: 72)      // место под нижнюю строку «загружаем свежее»
                }
                .padding(.top, 8)
            }
            /* Листать можно, а нажимать по карточкам — пока не попросили открыть: два запроса подряд отправили
               бы страницу сначала на одно объявление, потом на другое. */
            .disabled(ждём != nil)

            строкаВнизу
        }
    }

    // MARK: - Части

    private var шапка: some View {
        HStack(spacing: 10) {
            KlikoLogoIcon(size: 26)
            KlikoWordmark(height: 17)
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private func полка(_ ряд: FeedSnapshot.Row) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Self.краска(ряд.c))
                    .frame(width: 8, height: 8)
                Text(ряд.название)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
            .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(ряд.items) { товар in
                        карточка(товар)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func карточка(_ товар: FeedSnapshot.Item) -> some View {
        Button {
            guard ждём == nil, let адрес = товар.адрес else { return }
            ждём = товар.id
            открыть(адрес)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    обложка(товар)
                    if товар.вТопе {
                        Text("ТОП")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.green2, in: Capsule())
                            .padding(8)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.цена(товар))
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(товар.название)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: 34, alignment: .top)
                    if !товар.город.isEmpty {
                        Text(товар.город)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 9)
                .padding(.bottom, 11)
            }
            .frame(width: 168, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .opacity(ждём == nil || ждём == товар.id ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }

    private func обложка(_ товар: FeedSnapshot.Item) -> some View {
        /* Снимок берётся из того же кэша, что и страница: адреса у фотографий постоянные, и то, что человек
           уже видел, второй раз по сети не поедет. */
        AsyncImage(url: товар.обложка) { фаза in
            switch фаза {
            case .success(let картинка):
                картинка.resizable().aspectRatio(contentMode: .fill)
            default:
                Rectangle().fill(Color(.tertiarySystemBackground))
            }
        }
        .frame(width: 168, height: 126)
        .clipped()
    }

    private var строкаВнизу: some View {
        HStack(spacing: 9) {
            ProgressView().scaleEffect(0.7)
            Text(ждём == nil ? "Загружаем свежее" : "Открываем объявление")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .padding(.bottom, 18)
    }

    // MARK: - Мелочи

    /// Краска раздела приходит строкой «#DC2626». Не разобрали — берём бренд: лента важнее точного оттенка.
    static func краска(_ hex: String?) -> Color {
        guard var s = hex, s.hasPrefix("#") else { return Theme.green }
        s.removeFirst()
        guard s.count == 6, let n = UInt32(s, radix: 16) else { return Theme.green }
        return Color(red: Double((n >> 16) & 0xFF) / 255,
                     green: Double((n >> 8) & 0xFF) / 255,
                     blue: Double(n & 0xFF) / 255)
    }

    /// «14 900 000 ₸». Цены нет — «Цена по запросу»: пустое место под ценой читается как сломанная карточка.
    static func цена(_ товар: FeedSnapshot.Item) -> String {
        guard let p = товар.p, p > 0 else { return товар.торг ? "Договорная" : "Цена по запросу" }
        let ф = NumberFormatter()
        ф.numberStyle = .decimal
        ф.groupingSeparator = "\u{00A0}"          // неразрывный пробел: цена не переносится посреди числа
        ф.maximumFractionDigits = 0
        let число = ф.string(from: NSNumber(value: p)) ?? String(Int(p))
        return число + "\u{00A0}₸"
    }
}

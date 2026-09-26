import SwiftUI

/**
 ПРОДАВЕЦ В ОБЪЯВЛЕНИИ — ЭТАП 37 (владелец 25.09.2026: «почти 100% похоже на сайт, только нативное SwiftUI»).

 На странице объявления сайта (mkOpenModal в js/marketplace.min.js) карточка продавца .mk-msc — кнопка со стрелкой
 .mk-msc-prof справа: нажатие открывает отзывы о продавце (mkSellerRevOpen). Под ней .mk-sfollow: широкая «Подписаться на
 продавца» (этап 36) и квадратная «⋮» .mk-kebab-btn с меню: «Заблокировать» / «Разблокировать» (#mk-block-mi) и
 красное «Пожаловаться» (.mk-kebab-danger). На своём объявлении и без seller_id строки нет. Здесь — то же:
   · карточка (Config.продавецОтзывы) — кнопка с зелёной стрелкой, лист отзывов в виде #mk-srev-ov;
   · «⋮» (Config.жалобы) — меню в порядке сайта; «Заблокировать» сначала спрашивает «Заблокировать продавца?» с
     красной «Заблокировать» (mkConfirm сайта, danger), «Разблокировать» — сразу; «Пожаловаться» — окно жалобы;
   · заблокирован (blocked из subs.php?action=status) — пункт меню «Разблокировать», а под строкой — «Вы заблокировали
     продавца — общение недоступно. История сохранена.» (chat_you_blocked сайта).
 Краски — динамические Theme, как у остальных экранов сайта.
 */
struct БлокПродавца: View {
    let товар: Listing
    let продавецID: String
    @ObservedObject private var подписки = СинхронПодписок.shared
    @ObservedObject private var действия = ДействияСПродавцом.shared
    @State private var лист: ЛистУПродавца?
    @State private var вопросБлокировки = false

    /// Явный init: блок создаёт страница объявления из другого файла.
    init(товар: Listing, продавецID: String) {
        self.товар = товар
        self.продавецID = продавецID
    }

    private var имя: String { товар.продавец ?? "" }

    /// Своё объявление — как getMkMe() === seller_id у сайта: номер вошедшего знают подписки (этап 36) и действия.
    private var свой: Bool { подписки.мой == продавецID || действия.мой == продавецID }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            карточка
            if !свой && (Config.подпискиССайтом || Config.жалобы) {
                СтрокаДействийПродавца(продавецID: продавецID, имя: имя,
                                       заблокировать: { вопросБлокировки = true },
                                       пожаловаться: { начатьЖалобу() })
            }
            if Config.жалобы && !свой && действия.заблокирован(продавецID) {
                заметкаБлокировки
            }
        }
        .onAppear {
            /* mkSellerActionsSync: подписан ли, заблокирован ли и сколько подписчиков — при показе карточки. */
            if Config.подпискиССайтом { подписки.узнать(продавца: продавецID) }
            if Config.жалобы { действия.узнать(продавца: продавецID) }
        }
        .sheet(item: $лист) { вид in
            switch вид {
            case .отзывы:
                ЛистОтзывовПродавца(продавецID: продавецID, имя: имя, свой: свой)
            case .жалоба:
                ЛистЖалобы(продавецID: продавецID, объявление: товар.id)
            }
        }
        .alert(SellerText.т("block_q"), isPresented: $вопросБлокировки) {
            Button(SellerText.т("cancel"), role: .cancel) {}
            Button(SellerText.т("block"), role: .destructive) {
                действия.переключитьБлокировку(продавецID, имя: имя)
            }
        } message: {
            Text(SellerText.т("block_msg"))
        }
    }

    /// Карточка .mk-msc: у сайта по умолчанию (MK_SELLER_PAGE) — ссылка на страницу продавца seller.php; здесь — своя
    /// витрина продавца поверх объявления (ОкноПродавца). Номер негодный — отзывы, как на этапе 37.
    @ViewBuilder
    private var карточка: some View {
        if ВитринаПродавцаAPI.годный(продавецID) {
            Button {
                ОкноПродавца.открыть(id: продавецID, имя: имя)
            } label: {
                КарточкаПродавцаСайта(товар: товар, подписчики: подписчики, стрелка: true)
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            .accessibilityHint(StorefrontText.т("all_goods"))
        } else if Config.продавецОтзывы {
            Button {
                лист = .отзывы
            } label: {
                КарточкаПродавцаСайта(товар: товар, подписчики: подписчики, стрелка: true)
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            .accessibilityHint(SellerText.т("reviews_hint"))
        } else {
            КарточкаПродавцаСайта(товар: товар, подписчики: подписчики)
        }
    }

    /// Свежее число с сайта (status, follow), пока его нет — seller_followers объявления; без подписок — не пишем.
    private var подписчики: Int? {
        guard Config.подпискиССайтом else { return nil }
        return подписки.подписчиков(продавецID) ?? товар.подписчикиПродавца
    }

    private var заметкаБлокировки: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "nosign")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            Text(SellerText.т("you_blocked"))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.текстВторой)
        .accessibilityElement(children: .combine)
    }

    /// «Пожаловаться»: гостю — плашка «Войдите, чтобы пожаловаться», остальным — окно жалобы.
    private func начатьЖалобу() {
        Task { @MainActor in
            if await действия.можноЖаловаться() { лист = .жалоба }
        }
    }
}

/// Какой лист открыт из блока продавца.
enum ЛистУПродавца: String, Identifiable {
    case отзывы, жалоба

    var id: String { rawValue }
}

/// .mk-sfollow: «Подписаться на продавца» (этап 36) на всю ширину и «⋮» 46 × 46 справа — одной высоты.
struct СтрокаДействийПродавца: View {
    let продавецID: String
    let имя: String
    /// «Заблокировать» — экран сначала спросит.
    let заблокировать: () -> Void
    let пожаловаться: () -> Void
    @ObservedObject private var действия = ДействияСПродавцом.shared

    init(продавецID: String, имя: String, заблокировать: @escaping () -> Void, пожаловаться: @escaping () -> Void) {
        self.продавецID = продавецID
        self.имя = имя
        self.заблокировать = заблокировать
        self.пожаловаться = пожаловаться
    }

    var body: some View {
        HStack(spacing: 8) {
            if Config.подпискиССайтом {
                КнопкаПодпискиНаПродавца(продавецID: продавецID, имя: имя)
            } else {
                Spacer(minLength: 0)
            }
            if Config.жалобы {
                меню
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// .mk-kebab-btn: квадрат 46 на --mk-surf, рамка 1 --mk-line, скругление --r-md, точки цветом --mk-muted. Пункты — в
    /// порядке сайта; «Пожаловаться» — красным, как .mk-kebab-danger.
    private var меню: some View {
        let блок = действия.заблокирован(продавецID)
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return Menu {
            Button {
                if блок {
                    действия.переключитьБлокировку(продавецID, имя: имя)
                } else {
                    заблокировать()
                }
            } label: {
                Label(SellerText.т(блок ? "unblock" : "block"), systemImage: "nosign")
            }
            .disabled(действия.блокировкаВПути.contains(продавецID))
            Button(role: .destructive) {
                пожаловаться()
            } label: {
                Label(SellerText.т("report"), systemImage: "flag")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .bold))
                .rotationEffect(.degrees(90))
                .foregroundStyle(Theme.текстВторой)
                .frame(width: 46)
                .frame(minHeight: 46, maxHeight: .infinity)
                .background(Theme.поверхность, in: форма)
                .overlay {
                    форма.strokeBorder(Theme.линия, lineWidth: 1)
                }
                .contentShape(форма)
        }
        .menuStyle(.button)
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .accessibilityLabel(SellerText.т("more"))
    }
}

// MARK: - Лист отзывов (#mk-srev-ov)

/**
 Отзывы о продавце — как .mksr-box сайта (_mkSellerRevPaint): имя крупно, под ним «Загружаем отзывы…», «Не удалось
 загрузить отзывы» или «7 сделок · 5 отзывов» (число сделок жирным, нет сделок — только отзывы); отзывы есть — плашка
 .mksr-top: крупная оценка «4.8», звёзды ★☆, «5 отзывов», справа полосы «5…1» с числами; ниже — отзывы (.mksr-rv: буква
 в мятном квадрате, имя, звёзды, дата справа, текст, товар) или «Отзывов пока нет» с пояснением; внизу «Закрыть». От
 себя: «Подписаться на продавца» этапа 36 под шапкой (не на своём) и «Профиль» — страница продавца на сайте, куда ведёт
 карточка сайта (seller.php?id=).
 */
struct ЛистОтзывовПродавца: View {
    let продавецID: String
    let имя: String
    let свой: Bool
    /// «Профиль» — витрина продавца; из самой витрины его нет.
    let профиль: Bool
    @ObservedObject private var действия = ДействияСПродавцом.shared
    @State private var состояние: Состояние = .загрузка
    @Environment(\.dismiss) private var закрыть

    enum Состояние: Equatable {
        case загрузка
        case ошибка
        case готово(ОтзывыПродавца.Сводка)
    }

    init(продавецID: String, имя: String, свой: Bool, профиль: Bool = true) {
        self.продавецID = продавецID
        self.имя = имя
        self.свой = свой
        self.профиль = профиль
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ШапкаОтзывов(имя: имя, состояние: состояние, повторить: { Task { @MainActor in await загрузить() } })
                if Config.подпискиССайтом && !свой {
                    КнопкаПодпискиНаПродавца(продавецID: продавецID, имя: имя)
                        .padding(.top, 14)
                }
                switch состояние {
                case .готово(let сводка):
                    СодержимоеОтзывов(сводка: сводка)
                case .загрузка, .ошибка:
                    EmptyView()
                }
                низ
            }
            .padding(.horizontal, 16)
            .padding(.top, 22)
            .padding(.bottom, 16)
        }
        .background(Theme.поверхность.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            ПлашкиВЛистеПродавца(закрытьЛист: { закрыть() })
        }
        .presentationBackground(Theme.поверхность)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task(id: продавецID) { await загрузить() }
    }

    /// Из памяти или с сайта; «Повторить» после отказа — снова с сайта (отказ в память не ложится).
    private func загрузить() async {
        if case .готово = состояние { return }
        состояние = .загрузка
        if let сводка = await действия.загрузитьОтзывы(продавецID) {
            состояние = .готово(сводка)
        } else {
            состояние = .ошибка
        }
    }

    /// «Профиль» и «Закрыть» (.mksr-x: на всю ширину, 44, без фона, серым).
    private var низ: some View {
        VStack(spacing: 4) {
            if профиль && ВитринаПродавцаAPI.годный(продавецID) {
                Button {
                    закрыть()
                    ОкноПродавца.открыть(id: продавецID, имя: имя)
                } label: {
                    HStack(spacing: 6) {
                        Text(SellerText.т("profile"))
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 12, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.зелёный2)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                .accessibilityHint(SellerText.т("open_profile"))
            }
            Button {
                закрыть()
            } label: {
                Text(SellerText.т("close"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        }
        .padding(.top, 12)
    }
}

/// .mksr-h и .mksr-sub.
private struct ШапкаОтзывов: View {
    let имя: String
    let состояние: ЛистОтзывовПродавца.Состояние
    let повторить: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(имя.isEmpty ? SellerText.т("seller") : имя)
                .font(.system(size: 21, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            подпись
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var подпись: some View {
        switch состояние {
        case .загрузка:
            HStack(spacing: 8) {
                SiteSpinner.мелкий
                Text(SellerText.т("loading"))
            }
        case .ошибка:
            HStack(spacing: 12) {
                Text(SellerText.т("fail"))
                Button(SellerText.т("retry"), action: повторить)
                    .font(.system(size: 14, weight: .bold))
                    .tint(Theme.акцент)
            }
        case .готово(let сводка):
            сводкаСделок(сводка)
        }
    }

    /// «<b>7</b> сделок · 5 отзывов» — сделок нет, только «5 отзывов», как у сайта.
    private func сводкаСделок(_ сводка: ОтзывыПродавца.Сводка) -> Text {
        let отзывы = ListingPageText.число(сводка.отзывов, "reviews")
        guard сводка.сделок > 0 else { return Text(отзывы) }
        let число = String(сводка.сделок)
        // Как у сайта: слово — noun() без числа в начале, а само число — отдельно, жирным (<b>).
        let слово = String(ListingPageText.число(сводка.сделок, "deals").dropFirst(число.count + 1))
        let жирное = Text(число).bold()
        return Text("\(жирное) \(слово) · \(отзывы)")
    }
}

/// .mksr-top (есть отзывы) и .mksr-list или .mksr-empty.
private struct СодержимоеОтзывов: View {
    let сводка: ОтзывыПродавца.Сводка

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if сводка.отзывов > 0 {
                ИтогОценок(сводка: сводка)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
            }
            if сводка.отзывы.isEmpty {
                ПустоОтзывов()
            } else {
                VStack(spacing: 10) {
                    ForEach(сводка.отзывы) { отзыв in
                        СтрокаОтзыва(отзыв: отзыв)
                    }
                }
                .padding(.top, 12)
            }
        }
    }
}

/// .mksr-top: слева крупная оценка, звёзды и «N отзывов» (min 74), справа полосы 5…1 (.mksr-dist).
private struct ИтогОценок: View {
    let сводка: ОтзывыПродавца.Сводка

    /// Самая длинная полоса — во всю ширину (l = max(1, …) у сайта).
    private var наибольшее: Int {
        max(1, (1...5).map { сводка.распределение[$0] ?? 0 }.max() ?? 1)
    }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        return HStack(spacing: 16) {
            VStack(spacing: 4) {
                Text(String(format: "%.1f", сводка.оценка))
                    .font(.system(size: 30, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(Theme.текст)
                ЗвёздыОтзыва(оценка: сводка.оценка, размер: 14)
                Text(ListingPageText.число(сводка.отзывов, "reviews"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(minWidth: 74)
            .accessibilityElement(children: .combine)
            VStack(spacing: 4) {
                ForEach([5, 4, 3, 2, 1], id: \.self) { звёзд in
                    СтрокаРаспределения(звёзд: звёзд, число: сводка.распределение[звёзд] ?? 0,
                                        наибольшее: наибольшее)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(КраскиОтзывов.фонБлока, in: форма)
        .overlay {
            форма.strokeBorder(Theme.линия, lineWidth: 1)
        }
    }
}

/// .mksr-drow: «5», полоса 6 pt (--mk-line, заливка янтарём по доле), число.
private struct СтрокаРаспределения: View {
    let звёзд: Int
    let число: Int
    let наибольшее: Int

    /// Math.round(e / l * 100) % сайта.
    private var доля: CGFloat {
        CGFloat((Double(число) / Double(max(1, наибольшее)) * 100).rounded() / 100)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(String(звёзд))
                .frame(width: 10, alignment: .trailing)
            Capsule()
                .fill(Theme.линия)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { рамка in
                        Capsule()
                            .fill(КраскиОтзывов.полоса)
                            .frame(width: рамка.size.width * доля)
                    }
                }
            Text(String(число))
                .frame(minWidth: 18, alignment: .trailing)
                .fixedSize()
        }
        .font(.system(size: 12).monospacedDigit())
        .foregroundStyle(Theme.текстВторой)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: SellerText.т("rating_of"), звёзд) + ": " + ListingPageText.число(число, "reviews"))
    }
}

/// _mkSrevStars: оценка до целого (Math.round), от 0 до 5: «★★★★☆» цветом #b45309 (в тёмной — #fbbf24).
private struct ЗвёздыОтзыва: View {
    let оценка: Double
    var размер: CGFloat = 14

    var body: some View {
        /* Сначала в пределы 0…5, потом в целое: Int() от огромного числа или nan уронил бы приложение. */
        let полных = Int(min(5, max(0, оценка)).rounded())
        return Text(String(repeating: "★", count: полных) + String(repeating: "☆", count: 5 - полных))
            .font(.system(size: размер))
            .tracking(1)
            .foregroundStyle(КраскиОтзывов.звезда)
            .lineLimit(1)
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// .mksr-rv: буква имени в мятном квадрате 34 (--r-ms), имя жирным, звёзды, дата справа, текст, товар серым.
private struct СтрокаОтзыва: View {
    let отзыв: ОтзывыПродавца.Отзыв

    /// Имени нет — «Покупатель», буква — «?», как у сайта.
    private var имя: String { отзыв.имя.isEmpty ? SellerText.т("buyer") : отзыв.имя }
    private var буква: String { String((отзыв.имя.isEmpty ? "?" : отзыв.имя).prefix(1)).uppercased() }
    private var дата: String? { отзыв.дата.map { Listing.датаСайта($0) } }

    var body: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return HStack(alignment: .top, spacing: 12) {
            Text(буква)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.зелёный2)
                .frame(width: 34, height: 34)
                .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(имя)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    ЗвёздыОтзыва(оценка: отзыв.оценка, размер: 13)
                    Spacer(minLength: 4)
                    if let когда = дата {
                        Text(когда)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                if let текст = отзыв.текст {
                    Text(текст)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текст)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let товар = отзыв.товар {
                    Text(товар)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(КраскиОтзывов.фонБлока, in: форма)
        .overlay {
            форма.strokeBorder(Theme.линия, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(подписьДоступности)
    }

    /// VoiceOver одной фразой: имя, оценка, дата, текст, товар.
    private var подписьДоступности: String {
        let полных = Int(min(5, max(0, отзыв.оценка)).rounded())
        var части = [имя, String(format: SellerText.т("rating_of"), полных)]
        if let когда = дата { части.append(когда) }
        if let текст = отзыв.текст { части.append(текст) }
        if let товар = отзыв.товар { части.append(товар) }
        return части.joined(separator: ". ")
    }
}

/// .mksr-empty: «Отзывов пока нет» жирным и пояснение серым, по центру.
private struct ПустоОтзывов: View {
    var body: some View {
        VStack(spacing: 6) {
            Text(SellerText.т("none"))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.текст)
            Text(SellerText.т("none_sub"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }
}

/// Краски листа отзывов из CSS сайта (.mksr-*): звёзды #b45309 / #fbbf24, полосы #d97706 / #f59e0b, плашки —
/// --mk-surf2, в тёмной — белый 3 %.
private enum КраскиОтзывов {
    static let звезда = Theme.цвет(0xB45309, 0xFBBF24)
    static let полоса = Theme.цвет(0xD97706, 0xF59E0B)
    static let фонБлока = Theme.цвет(светлый: Theme.hex(0xF4F8F6), тёмный: Theme.hex(0xFFFFFF, 0.03))
}

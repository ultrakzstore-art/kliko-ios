import SwiftUI

/**
 «ОБМЕНЫ» НА СТРАНИЦЕ ОБЪЯВЛЕНИЯ — .mk-exch-btn и лист #mk-exch-overlay сайта (mkExchOpen), своим листом.

 Кнопка — под блоком аренды, как it = mkRentBlock(r) + кнопка у сайта: объявление for_exchange, человек вошёл
 (getMkMe), это не его объявление и раздел допускает обмен (mkExchAllowed: не «Животные»). У услуги подпись — «Бартер».
 Лист: что хотят (картинка, название, цена), мои опубликованные объявления (cabinet.php?action=my_items: approved, не это
 и тоже из раздела с обменом), выбор одного, баланс цен (mkExchBalance) и «Кто доплачивает?» с суммой, комментарий до
 300 знаков. «Отправить предложение» — POST exchange.php {action:"offer", csrf, me_id, item_id, offer_item_id, comment,
 surcharge, surcharge_dir}. Доплата — только условие предложения: деньги не двигаются.
 */
struct КнопкаОбменаОбъявления: View {
    let товар: Listing
    let открыть: ((URL) -> Void)?
    @ObservedObject private var сессия = СессияПриложения.shared
    @State private var лист = false
    @State private var отправлено = false

    init(товар: Listing, открыть: ((URL) -> Void)?) {
        self.товар = товар
        self.открыть = открыть
    }

    /// mkExchAllowed: раздел не из MK_NO_EXCHANGE (animals).
    static func разделДопускает(_ раздел: String?) -> Bool {
        РазделыСайта.корень(раздел) != "animals"
    }

    /// for_exchange и раздел; «вошёл и не я» — в body.
    static func есть(_ товар: Listing) -> Bool {
        товар.поляВида.обмен && разделДопускает(товар.категория)
    }

    var body: some View {
        if !сессия.id.isEmpty && сессия.id != (товар.продавецID ?? "") {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    отправлено = false
                    лист = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(ТекстыСчётаИОбмена.т(товар.услуга ? "exch_barter" : "exch_title"))
                            .font(.system(size: 16, weight: .heavy))
                    }
                    .foregroundStyle(Theme.зелёныйЯркий)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(LinearGradient(colors: [Theme.оттенокАкцента, Theme.оттенокАкцента.opacity(0.3)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                            .strokeBorder(Theme.зелёный2.opacity(0.4), lineWidth: 1.5)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
                if отправлено {
                    Label(ТекстыСчётаИОбмена.т("exch_sent"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.зелёный2)
                        .transition(.opacity)
                }
            }
            .padding(.top, 4)
            .sheet(isPresented: $лист) {
                ЛистОбменаОбъявления(товар: товар, открыть: открыть) {
                    withAnimation(ДвижениеСайта.появление) { отправлено = true }
                }
            }
        }
    }
}

// MARK: - Модель

@MainActor
final class МодельОбменаОбъявления: ObservableObject {
    /// Баланс цен (.mk-exch-balance): neutral, even, minus, plus.
    enum Баланс: Equatable {
        case договорная
        case равно(Int, Int)
        case дешевле(Int)
        case дороже(Int)
    }

    @Published private(set) var мои: [МоёОбъявление] = []
    @Published private(set) var загружено = false
    @Published private(set) var ошибкаЗагрузки = false
    @Published private(set) var выбран = ""
    /// surcharge_dir: buyer — доплачиваю я, seller — продавец, "" — никто.
    @Published private(set) var кто = ""
    @Published private(set) var сумма = 0
    @Published private(set) var суммаТекст = ""
    @Published var комментарий = ""
    @Published private(set) var отправляем = false
    @Published private(set) var ошибка: String? = nil

    /// Пока человек сам не тронул доплату, баланс подставляет её (_mkExchAuto).
    private var авто = true
    let цель: Listing

    private typealias A = МоиОбъявленияAPI

    init(цель: Listing) {
        self.цель = цель
    }

    /// Цена цели: договорная или без цены — 0 (_mkExchTPrice).
    private var ценаЦели: Int {
        guard !цель.negotiable, let цена = цель.price, цена > 0 else { return 0 }
        return Int(цена.rounded())
    }

    private func цена(_ о: МоёОбъявление) -> Int { о.торг ? 0 : Int(о.цена.rounded()) }

    var баланс: Баланс? {
        guard let о = мои.first(where: { $0.id == выбран }) else { return nil }
        let м = ценаЦели
        let с = цена(о)
        if цель.negotiable || о.торг || м == 0 || с == 0 { return .договорная }
        let разница = м - с
        if разница == 0 { return .равно(м, с) }
        return разница > 0 ? .дешевле(разница) : .дороже(-разница)
    }

    /// mkExchOpen: мои объявления для обмена.
    func загрузить() async {
        guard !загружено else { return }
        do {
            guard let j = try await A.получить("cabinet.php?action=my_items") else {
                ошибкаЗагрузки = true
                загружено = true
                return
            }
            let сырые = (j["items"] as? [[String: Any]]) ?? []
            мои = сырые.compactMap { МоёОбъявление($0) }.filter { о in
                о.статус == "approved" && о.id != цель.id && КнопкаОбменаОбъявления.разделДопускает(о.раздел)
            }
        } catch {
            ошибкаЗагрузки = true
        }
        загружено = true
    }

    /// mkExchSelect → mkExchBalance.
    func выбрать(_ номер: String) {
        выбран = номер
        ошибка = nil
        guard авто, let б = баланс else { return }
        switch б {
        case .договорная, .равно:
            поставить(кто: "", сумма: 0)
        case .дешевле(let р):
            поставить(кто: "buyer", сумма: р)
        case .дороже(let р):
            поставить(кто: "seller", сумма: р)
        }
    }

    /// mkExchSurDir.
    func ктоДоплачивает(_ направление: String) {
        авто = false
        поставить(кто: направление, сумма: направление.isEmpty ? 0 : сумма)
    }

    /// mkExchSurInput: только цифры, с пробелами тысяч; сумма без направления — «доплачиваю я».
    func ввелиСумму(_ текст: String) {
        авто = false
        let цифры = String(текст.filter { $0.isASCII && $0.isNumber }.prefix(12))
        let значение = Int(цифры) ?? 0
        сумма = max(0, значение)
        суммаТекст = цифры.isEmpty ? "" : Self.тысячи(значение)
        if сумма > 0 && кто.isEmpty { кто = "buyer" }
    }

    private func поставить(кто новый: String, сумма новая: Int) {
        кто = новый
        сумма = новая
        суммаТекст = новая > 0 ? Self.тысячи(новая) : ""
    }

    static func тысячи(_ n: Int) -> String {
        let ф = NumberFormatter()
        ф.numberStyle = .decimal
        ф.groupingSeparator = " "
        ф.usesGroupingSeparator = true
        ф.maximumFractionDigits = 0
        return ф.string(from: NSNumber(value: n)) ?? String(n)
    }

    /// mkExchSend. true — ушло.
    func отправить() async -> Bool {
        guard !выбран.isEmpty, !отправляем else { return false }
        отправляем = true
        defer { отправляем = false }
        ошибка = nil
        let я = СессияПриложения.shared.id
        let тело: [String: Any] = [
            "action": "offer", "me_id": я, "item_id": цель.id, "offer_item_id": выбран,
            "comment": комментарий.trimmingCharacters(in: .whitespacesAndNewlines),
            "surcharge": сумма, "surcharge_dir": кто
        ]
        do {
            let j = try await A.отправить("exchange.php", тело: тело)
            if A.да(j["ok"]) { return true }
            let причина = A.строка(j["error"])
            ошибка = ТекстыСчётаИОбмена.т("exch_err") + (причина.isEmpty ? ТекстыСчётаИОбмена.т("exch_retry") : причина)
        } catch {
            ошибка = ТекстыСчётаИОбмена.т("no_conn")
        }
        return false
    }
}

// MARK: - Лист

struct ЛистОбменаОбъявления: View {
    @StateObject private var модель: МодельОбменаОбъявления
    let открыть: ((URL) -> Void)?
    let отправлено: () -> Void
    @Environment(\.dismiss) private var закрыть

    init(товар: Listing, открыть: ((URL) -> Void)?, отправлено: @escaping () -> Void) {
        _модель = StateObject(wrappedValue: МодельОбменаОбъявления(цель: товар))
        self.открыть = открыть
        self.отправлено = отправлено
    }

    private func т(_ ключ: String) -> String { ТекстыСчётаИОбмена.т(ключ) }

    private var цель: Listing { модель.цель }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                шапка
                карточкаЦели
                Text(т(цель.услуга ? "exch_barter_sub" : "exch_sub"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                список
                if модель.баланс != nil {
                    Group {
                        строкаБаланса
                        доплата
                    }
                }
                комментарий
                if let ошибка = модель.ошибка {
                    Text(ошибка)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.скидкаТекст)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)
            .мерилоЛиста()
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.поверхность.ignoresSafeArea())
        .листСКнопкойВнизу { кнопкаОтправить }
        .task { await модель.загрузить() }
    }

    private var шапка: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
                .accessibilityHidden(true)
            Text(т(цель.услуга ? "exch_barter_title" : "exch_title"))
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .frame(maxWidth: .infinity, alignment: .leading)
            КнопкаЗакрытьМеста { закрыть() }
        }
    }

    /// #mk-exch-target-box: фото, название, цена («Договорная» / «—»).
    private var карточкаЦели: some View {
        HStack(spacing: 12) {
            картинка(цель.обложка ?? цель.фотоАдреса.first)
            VStack(alignment: .leading, spacing: 3) {
                Text(цель.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                Text(ценаСтрокой(цена: цель.price ?? 0, торг: цель.negotiable))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    private func ценаСтрокой(цена: Double, торг: Bool) -> String {
        if торг { return т("negotiable") }
        return цена > 0 ? СделкиФормат.тенге(Int(цена.rounded())) : "—"
    }

    private func картинка(_ адрес: URL?) -> some View {
        AsyncImage(url: адрес) { фаза in
            if let изображение = фаза.image {
                изображение.resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.поверхность2
                    Image(systemName: "photo")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityHidden(true)
    }

    // MARK: Мои объявления (#mk-exch-list)

    @ViewBuilder
    private var список: some View {
        if !модель.загружено {
            SiteSpinner()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else if модель.ошибкаЗагрузки {
            пусто(т("exch_load_err"), добавить: false)
        } else if модель.мои.isEmpty {
            пусто(т("exch_empty"), добавить: true)
        } else {
            VStack(spacing: 8) {
                ForEach(модель.мои) { о in строка(о) }
            }
        }
    }

    private func пусто(_ текст: String, добавить: Bool) -> some View {
        VStack(spacing: 8) {
            Text(текст)
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if добавить {
                Button {
                    закрыть()
                    if let адрес = Config.url("/cabinet.php?go=add") { открыть?(адрес) }
                } label: {
                    Text(т("exch_add"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.зелёный2)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func строка(_ о: МоёОбъявление) -> some View {
        let выбран = модель.выбран == о.id
        return Button {
            модель.выбрать(о.id)
        } label: {
            HStack(spacing: 12) {
                картинка(о.фото.isEmpty ? nil : Config.url(о.фото))
                VStack(alignment: .leading, spacing: 3) {
                    Text(о.название)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(ценаСтрокой(цена: о.цена, торг: о.торг))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 0)
                if выбран {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.зелёный2)
                        .accessibilityHidden(true)
                }
            }
            .padding(10)
            .background(выбран ? Theme.мята : Theme.поверхность,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(выбран ? Theme.зелёный2 : Theme.линия, lineWidth: выбран ? 1.5 : 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбран ? .isSelected : [])
    }

    // MARK: Баланс и доплата

    @ViewBuilder
    private var строкаБаланса: some View {
        if let б = модель.баланс {
            Group {
                switch б {
                case .договорная:
                    Text(т("exch_negot"))
                case .равно(let м, let с):
                    Text(т("exch_equal") + СделкиФормат.тенге(м) + " ≈ " + СделкиФормат.тенге(с))
                case .дешевле(let р):
                    Text(т("exch_cheaper_a")) + Text(СделкиФормат.тенге(р)).bold() + Text(т("exch_cheaper_b"))
                case .дороже(let р):
                    Text(т("exch_pricier_a")) + Text(СделкиФормат.тенге(р)).bold() + Text(т("exch_pricier_b"))
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(цветБаланса(б))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(фонБаланса(б), in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
    }

    private func цветБаланса(_ б: МодельОбменаОбъявления.Баланс) -> Color {
        switch б {
        case .договорная: return Theme.текстВторой
        case .равно: return Theme.зелёный2
        case .дешевле: return Theme.меткаБУ
        case .дороже: return Theme.зелёный2
        }
    }

    private func фонБаланса(_ б: МодельОбменаОбъявления.Баланс) -> Color {
        switch б {
        case .договорная: return Theme.поверхность2
        case .равно, .дороже: return Theme.мята
        case .дешевле: return Theme.топФон
        }
    }

    /// #mk-exch-sur: «Кто доплачивает?» — Я / Продавец / Никто и сумма.
    private var доплата: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(т("exch_who_pays"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.текст)
            HStack(spacing: 8) {
                кнопкаКто("buyer", т("exch_i_pay"))
                кнопкаКто("seller", т("exch_seller_pays"))
                кнопкаКто("", т("exch_no_pay"))
            }
            if !модель.кто.isEmpty {
                HStack(spacing: 6) {
                    TextField(т("exch_sur_ph"), text: Binding(get: { модель.суммаТекст },
                                                             set: { модель.ввелиСумму($0) }))
                        .keyboardType(.numberPad)
                        .font(.system(size: 15, weight: .semibold))
                    Text("₸")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1)
                }
            }
        }
    }

    private func кнопкаКто(_ направление: String, _ подпись: String) -> some View {
        let выбрано = модель.кто == направление
        return Button {
            модель.ктоДоплачивает(направление)
        } label: {
            Text(подпись)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(выбрано ? Color.white : Theme.текст)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(выбрано ? Theme.зелёный2 : Theme.поверхность2,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбрано ? .isSelected : [])
    }

    /// .mk-exch-comment: до 300 знаков.
    private var комментарий: some View {
        TextField(т("exch_comment_ph"), text: $модель.комментарий, axis: .vertical)
            .lineLimit(2...4)
            .font(.system(size: 14))
            .padding(10)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
            .onChange(of: модель.комментарий) { _, новое in
                if новое.count > 300 { модель.комментарий = String(новое.prefix(300)) }
            }
    }

    private var кнопкаОтправить: some View {
        let можно = !модель.выбран.isEmpty && !модель.отправляем
        return Button {
            Task {
                if await модель.отправить() {
                    закрыть()
                    отправлено()
                }
            }
        } label: {
            Text(т(модель.отправляем ? "sending" : "exch_send"))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.зелёный2.opacity(можно ? 1 : 0.45),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(!можно)
    }
}

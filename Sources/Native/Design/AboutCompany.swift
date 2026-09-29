import SwiftUI
import UIKit

/**
 «О компании» профиля — нативный экран iOS (владелец: «Подвал тоже как Swift сделать»). Подвал сайта (.ulxsf) в лентах
 больше не показывается; всё его содержимое — здесь, сгруппированными карточками в краске приложения (Theme):
   · бренд — надпись Kliko.kz и одна фраза о площадке (без «Безопасной сделки» на паузе гаранта);
   · компания и реквизиты — название, БИН, адрес (долгое нажатие — «Скопировать»);
   · контакты — почта и телефон открываются системными «Почтой» и «Телефоном», под ними часы работы;
   · документы — оферта, конфиденциальность, соглашение; помощь — справка, оплата, услуги, правила: своими окнами
     (НативныеОкна.перехватить), иначе корневым «открыть»;
   · способы оплаты — плашки Visa и Mastercard, 3-D Secure, платёжная организация (сведения, не кнопки оплаты);
   · соцсети — раздел появляется, когда в ЭкранОКомпании.соцсети есть адреса (своих страниц у сайта в снимке нет);
   · версия приложения, копирайт, строка о марках и реестр — внизу.
 Тексты — стилями Dynamic Type; тёмная тема — токенами Theme; ru/kk/en/ar — DesignText (строки подвала) и ТекстыОКомпании.
 */
struct ЭкранОКомпании: View {
    let открыть: (URL) -> Void

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    @ScaledMetric(relativeTo: .title2) private var высотаНадписи: CGFloat = 26

    private struct СсылкаСтраницы: Identifiable {
        let ключ: String
        let хвост: String
        let значок: String
        var id: String { ключ }
    }

    /// Страница соцсети: название, значок SF Symbols и адрес.
    private struct Соцсеть: Identifiable {
        let название: String
        let значок: String
        let адрес: String
        var id: String { адрес }
    }

    private static let документы = [
        СсылкаСтраницы(ключ: "f_offer", хвост: "oferta", значок: "doc.text"),
        СсылкаСтраницы(ключ: "f_privacy", хвост: "privacy", значок: "hand.raised"),
        СсылкаСтраницы(ключ: "f_agreement", хвост: "soglashenie", значок: "doc.plaintext")
    ]

    private static let помощь = [
        СсылкаСтраницы(ключ: "f_help", хвост: "help", значок: "questionmark.circle"),
        СсылкаСтраницы(ключ: "f_safe", хвост: "help#safe", значок: "checkmark.shield"),
        СсылкаСтраницы(ключ: "f_pay", хвост: "oplata", значок: "arrow.uturn.backward.circle"),
        СсылкаСтраницы(ключ: "f_tariffs", хвост: "tarify", значок: "tag"),
        СсылкаСтраницы(ключ: "f_pro", хвост: "help#pro", значок: "star"),
        СсылкаСтраницы(ключ: "f_rules", хвост: "help#rules", значок: "nosign")
    ]

    /// Соцсети компании — пусто, пока у площадки нет своих страниц; раздел тогда не показывается.
    private static let соцсети: [Соцсеть] = []

    private static let почта = "support@kliko.kz"
    private static let телефон = "+7 778 000 83 72"
    private static let телефонАдрес = "tel:+77780008372"
    private static let бин = "260840012679"
    private static let платёжка = "https://freedompay.kz"

    /// «Как работает Безопасная сделка» — только пока гарант не на паузе.
    private var ссылкиПомощи: [СсылкаСтраницы] {
        ПаузаГаранта.наПаузеСейчас ? Self.помощь.filter { $0.ключ != "f_safe" } : Self.помощь
    }

    private func т(_ ключ: String) -> String { ТекстыОКомпании.т(ключ) }
    private func д(_ ключ: String) -> String { DesignText.т(ключ) }

    var body: some View {
        List {
            разделБренда
            разделРеквизитов
            разделКонтактов
            разделСсылок(т("docs"), Self.документы)
            разделСсылок(т("help"), ссылкиПомощи)
            разделОплаты
            if !Self.соцсети.isEmpty {
                разделСоцсетей
            }
            разделВерсии
        }
        .listStyle(.insetGrouped)
        .списокСайта()
        .navigationTitle(HomeText.т("about_co"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Бренд

    private var разделБренда: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    Image("WmKliko")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(Theme.текст)
                    Image("WmKz")
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(Theme.зелёный2)
                }
                .frame(width: 296 * высотаНадписи / 74, height: высотаНадписи)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "Kliko.kz"))
                .accessibilityAddTraits(.isHeader)
                Text(д(ПаузаГаранта.наПаузеСейчас ? "f_about_np" : "f_about"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 6)
            .строкиСайта()
        }
    }

    // MARK: Компания и реквизиты

    private var разделРеквизитов: some View {
        Section {
            Group {
                строкаСведений(т("name"), д("f_company"))
                строкаСведений(т("bin"), Self.бин)
                строкаСведений(т("address"), д("f_address"))
            }
            .строкиСайта()
        } header: {
            ЗаголовокГруппыКабинета(т("company"))
        }
    }

    /// Подпись сверху, значение под ней — длинный адрес переносится на любом размере текста; долгое нажатие — копия.
    private func строкаСведений(_ название: String, _ значение: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(название)
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
            Text(verbatim: значение)
                .font(.body)
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .contextMenu {
            кнопкаКопии(значение)
        }
    }

    private func кнопкаКопии(_ значение: String) -> some View {
        Button {
            UIPasteboard.general.string = значение
        } label: {
            Label(т("copy"), systemImage: "doc.on.doc")
        }
    }

    // MARK: Контакты

    private var разделКонтактов: some View {
        Section {
            Group {
                строкаСвязи(значок: "envelope", название: т("mail"), значение: Self.почта,
                            адрес: "mailto:" + Self.почта, подсказка: д("f_mail"))
                /* Номер — изолированно слева направо, чтобы в арабском «+» не уехал в конец. */
                строкаСвязи(значок: "phone", название: т("phone"), значение: "\u{2066}" + Self.телефон + "\u{2069}",
                            адрес: Self.телефонАдрес, подсказка: д("f_call"))
            }
            .строкиСайта()
        } header: {
            ЗаголовокГруппыКабинета(т("contacts"))
        } footer: {
            Text(String(format: т("hours"), д("f_hours")))
        }
    }

    private func строкаСвязи(значок: String, название: String, значение: String, адрес: String,
                             подсказка: String) -> some View {
        Button {
            if let ссылка = URL(string: адрес) { UIApplication.shared.open(ссылка) }
        } label: {
            HStack(spacing: 12) {
                ЗначокСтрокиСайта(значок: значок)
                VStack(alignment: .leading, spacing: 2) {
                    Text(название)
                        .font(.footnote)
                        .foregroundStyle(Theme.текстВторой)
                    Text(verbatim: значение)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.акцент)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(подсказка + ": " + значение)
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            кнопкаКопии(значение)
        }
    }

    // MARK: Документы и помощь

    private func разделСсылок(_ заголовок: String, _ ссылки: [СсылкаСтраницы]) -> some View {
        Section {
            ForEach(ссылки) { ссылка in
                Button {
                    открытьСтраницу(ссылка.хвост)
                } label: {
                    HStack(spacing: 12) {
                        ЗначокСтрокиСайта(значок: ссылка.значок)
                        Text(д(ссылка.ключ))
                            .font(.body)
                            .foregroundStyle(Theme.текст)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        СтрелкаСтрокиКабинета()
                    }
                    .contentShape(Rectangle())
                }
                .строкиСайта()
            }
        } header: {
            ЗаголовокГруппыКабинета(заголовок)
        }
    }

    // MARK: Способы оплаты

    private var разделОплаты: some View {
        Section {
            Group {
                VStack(alignment: .leading, spacing: 10) {
                    ЛоготипыКартОКомпании()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(д("f_pay_cards"))
                    Label(д("f_pay_secure"), systemImage: "lock.shield")
                        .font(.subheadline)
                        .foregroundStyle(Theme.текст)
                    Label(т("nostore"), systemImage: "creditcard")
                        .font(.subheadline)
                        .foregroundStyle(Theme.текстВторой)
                }
                .padding(.vertical, 4)
                Button {
                    if let адрес = URL(string: Self.платёжка) { UIApplication.shared.open(адрес) }
                } label: {
                    HStack(spacing: 12) {
                        ЗначокСтрокиСайта(значок: "building.columns")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(т("psp"))
                                .font(.footnote)
                                .foregroundStyle(Theme.текстВторой)
                            Text(д("f_pay_psp"))
                                .font(.body)
                                .foregroundStyle(Theme.текст)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.текстВторой.opacity(0.6))
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityHint(д("f_pay_open"))
            }
            .строкиСайта()
        } header: {
            ЗаголовокГруппыКабинета(т("payment"))
        }
    }

    // MARK: Соцсети

    private var разделСоцсетей: some View {
        Section {
            ForEach(Self.соцсети) { сеть in
                Button {
                    if let адрес = URL(string: сеть.адрес) { UIApplication.shared.open(адрес) }
                } label: {
                    HStack(spacing: 12) {
                        ЗначокСтрокиСайта(значок: сеть.значок)
                        Text(verbatim: сеть.название)
                            .font(.body)
                            .foregroundStyle(Theme.текст)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.текстВторой.opacity(0.6))
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .строкиСайта()
            }
        } header: {
            ЗаголовокГруппыКабинета(т("social"))
        }
    }

    // MARK: Версия и правовые строки

    private var разделВерсии: some View {
        Section {
            LabeledContent(т("version"), value: Self.версия)
                .font(.body)
                .foregroundStyle(Theme.текст)
                .строкиСайта()
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text(т("copyright"))
                Text(д("f_tm"))
                Text(д("f_reg"))
            }
            .padding(.top, 4)
        }
    }

    /// «1.9 (42)» — CFBundleShortVersionString и CFBundleVersion.
    private static var версия: String {
        let сведения = Bundle.main.infoDictionary ?? [:]
        let номер = (сведения["CFBundleShortVersionString"] as? String) ?? "—"
        let сборка = (сведения["CFBundleVersion"] as? String) ?? "—"
        return номер + " (" + сборка + ")"
    }

    /// Справка, правила, соглашение, оферта, конфиденциальность, оплата, тарифы — своим окном поверх; иначе — корневым «открыть».
    @MainActor
    private func открытьСтраницу(_ хвост: String) {
        guard let адрес = Config.страницаСайта(хвост) else { return }
        if НативныеОкна.перехватить(адрес) { return }
        открыть(адрес)
    }
}

/// Плашки Visa и Mastercard — белые (как логотипы платёжных систем) с тонкой рамкой линии, видной и на белой строке.
struct ЛоготипыКартОКомпании: View {
    init() {}

    var body: some View {
        HStack(spacing: 10) {
            плашка {
                Text(verbatim: "VISA")
                    .font(.system(size: 15, weight: .heavy).italic())
                    .tracking(0.5)
                    .foregroundStyle(Color(red: 20 / 255, green: 52 / 255, blue: 203 / 255))
                    .fixedSize()
            }
            плашка {
                Canvas { контекст, размер in
                    let k = размер.width / 40
                    let r = 9.5 * k
                    let красный = Path(ellipseIn: CGRect(x: (16 - 9.5) * k, y: (12.5 - 9.5) * k, width: 2 * r, height: 2 * r))
                    let жёлтый = Path(ellipseIn: CGRect(x: (24 - 9.5) * k, y: (12.5 - 9.5) * k, width: 2 * r, height: 2 * r))
                    контекст.fill(красный, with: .color(Color(red: 235 / 255, green: 0, blue: 27 / 255)))
                    контекст.fill(жёлтый, with: .color(Color(red: 247 / 255, green: 158 / 255, blue: 27 / 255)))
                    контекст.clip(to: красный)
                    контекст.fill(жёлтый, with: .color(Color(red: 1, green: 95 / 255, blue: 0)))
                }
                .frame(width: 34, height: 21)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    private func плашка<Логотип: View>(@ViewBuilder _ логотип: () -> Логотип) -> some View {
        логотип()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(height: 29)
            .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Радиус.xxs, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.xxs, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
    }
}

/// Строки экрана «О компании» (ru/kk/en/ar); строки самого подвала — DesignText (f_*).
enum ТекстыОКомпании {
    static func т(_ ключ: String) -> String {
        let язык = DesignText.язык
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "company": "Компания и реквизиты", "name": "Название", "bin": "БИН", "address": "Адрес",
            "copy": "Скопировать", "contacts": "Контакты", "mail": "Почта", "phone": "Телефон",
            "hours": "Поддержка отвечает: %@", "docs": "Документы", "help": "Помощь",
            "payment": "Способы оплаты", "nostore": "Данные карты не хранятся в Kliko.kz",
            "psp": "Платёжная организация", "social": "Мы в соцсетях", "version": "Версия приложения",
            "copyright": "© 2026 Kliko.kz · Казахстан. Все права защищены."
        ],
        "kk": [
            "company": "Компания және деректемелер", "name": "Атауы", "bin": "БСН", "address": "Мекенжай",
            "copy": "Көшіру", "contacts": "Байланыс", "mail": "Пошта", "phone": "Телефон",
            "hours": "Қолдау жұмыс уақыты: %@", "docs": "Құжаттар", "help": "Көмек",
            "payment": "Төлем тәсілдері", "nostore": "Карта деректері Kliko.kz-те сақталмайды",
            "psp": "Төлем ұйымы", "social": "Біз әлеуметтік желілерде", "version": "Қолданба нұсқасы",
            "copyright": "© 2026 Kliko.kz · Қазақстан. Барлық құқықтар қорғалған."
        ],
        "en": [
            "company": "Company details", "name": "Name", "bin": "BIN", "address": "Address",
            "copy": "Copy", "contacts": "Contacts", "mail": "Email", "phone": "Phone",
            "hours": "Support hours: %@", "docs": "Documents", "help": "Help",
            "payment": "Payment methods", "nostore": "Kliko.kz does not store card details",
            "psp": "Payment provider", "social": "Follow us", "version": "App version",
            "copyright": "© 2026 Kliko.kz · Kazakhstan. All rights reserved."
        ],
        "ar": [
            "company": "بيانات الشركة", "name": "الاسم", "bin": "رقم التعريف (BIN)", "address": "العنوان",
            "copy": "نسخ", "contacts": "التواصل", "mail": "البريد الإلكتروني", "phone": "الهاتف",
            "hours": "ساعات عمل الدعم: %@", "docs": "المستندات", "help": "المساعدة",
            "payment": "طرق الدفع", "nostore": "لا يخزّن Kliko.kz بيانات البطاقة",
            "psp": "مزوّد الدفع", "social": "تابعونا", "version": "إصدار التطبيق",
            "copyright": "© 2026 Kliko.kz · كازاخستان. جميع الحقوق محفوظة."
        ]
    ]
}

/**
 «Язык приложения» профиля — тот же выбор, что был у пилюли «тема │ язык» шапки главной (ЯзыкПриложения): RU «Рус»,
 KZ «Қаз», EN «Eng», AR «عربي», у текущего галочка. Нужен и гостю: язык аккаунта (настройка «Язык») — только вошедшему.
 */
struct СтрокаЯзыкаПриложения: View {
    @ObservedObject private var язык = ЯзыкПриложения.shared

    init() {}

    var body: some View {
        Menu {
            ForEach(ЯзыкПриложения.варианты) { вариант in
                Button {
                    язык.выбрать(вариант)
                } label: {
                    if вариант.код == язык.код {
                        Label(вариант.метка + "  " + вариант.имя, systemImage: "checkmark")
                    } else {
                        Text(вариант.метка + "  " + вариант.имя)
                    }
                }
            }
        } label: {
            HStack {
                ПодписьСтрокиКабинета(HomeText.т("app_lang"), значок: "globe")
                Spacer(minLength: 8)
                Text(язык.текущий.имя)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityValue(язык.текущий.имя)
    }
}

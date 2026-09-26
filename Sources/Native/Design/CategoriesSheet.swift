import SwiftUI
import UIKit

/**
 ОКНО «КАТЕГОРИИ» НИЖНЕЙ ПАНЕЛИ (владелец, TestFlight 1.10: «в модалке карта и снизу доп. услуг типа часто задаваемые
 вопросы, товар, услуга и т.д. как на сайте не доработаны»).

 У сайта «Категории» нижней панели на главной (ulxBBCats → mhCats) открывают режим категорий: поле «Найти категорию»
 (#mh-cq) и плитки разделов (Работа, Услуги, Животные, Электроника, Авто, Товары, Недвижимость — MK_HOME_V), а «Карта»
 (#mk-map-btn → mkMapOpen) и справочные ссылки подвала (.ulxsf: «Покупателям» — Справочный центр, Как работает Гарант,
 Оплата и возврат; «Продавцам» — Возможности PRO, Услуги и цены, Что запрещено; «Документы» — Соглашение, Оферта,
 Конфиденциальность; реквизиты поддержки) живут рядом на той же странице. В приложении кнопка на главной раньше ничего не
 делала (vitrina-diff.md, X1). Теперь — нижний лист с тем же набором:

   · «Карта» — нативная карта объявлений (Native/Map, КартаЦель в стеке ленты);
   · разделы — лента раздела (как плитка главной); «Работа» — вакансии на сайте, своего экрана у приложения нет;
   · «Частые вопросы» (help#faq), «Как работает Гарант» (help#safe) и прочие справочные страницы и документы — живые
     страницы сайта своим экраном (НативныеОкна → ОкноСтраницСайта): текст правит команда сайта, в приложении его нет;
   · почта и телефон поддержки — системой.
 Поиск по полю — по названиям разделов и строк окна, как mhCatsQ сайта сужает плитки.
 */
enum ДействиеЛистаКатегорий: Equatable {
    /// Карта объявлений.
    case карта
    /// Раздел ленты по ключу («transport», «goods»…); «jobs» — вакансии сайта.
    case раздел(String)
    /// Страница сайта.
    case страница(URL)
}

struct ЛистКатегорийСайта: View {
    /// Есть ли карта объявлений (Config.картаОбъявлений).
    let карта: Bool
    let выбрать: (ДействиеЛистаКатегорий) -> Void

    @Environment(\.dismiss) private var закрыть
    @State private var запрос = ""

    init(карта: Bool, выбрать: @escaping (ДействиеЛистаКатегорий) -> Void) {
        self.карта = карта
        self.выбрать = выбрать
    }

    /// Строка справки: страница сайта (/kz/<язык>/<хвост>) — открывается своим экраном справки.
    private struct Строка: Identifiable {
        let id: String
        let название: String
        let значок: String
        let хвост: String
    }

    private struct Группа: Identifiable {
        let id: String
        let заголовок: String
        let строки: [Строка]
    }

    private var группы: [Группа] {
        let покупателям = [
            Строка(id: "faq", название: КатегорииText.т("faq"), значок: "questionmark.circle", хвост: "help#faq"),
            Строка(id: "safe", название: DesignText.т("f_safe"), значок: "checkmark.shield", хвост: "help#safe"),
            Строка(id: "pay", название: DesignText.т("f_pay"), значок: "creditcard", хвост: "oplata")
        ]
        let продавцам = [
            Строка(id: "pro", название: DesignText.т("f_pro"), значок: "star", хвост: "help#pro"),
            Строка(id: "tariffs", название: DesignText.т("f_tariffs"), значок: "tag", хвост: "tarify"),
            Строка(id: "rules", название: DesignText.т("f_rules"), значок: "nosign", хвост: "help#rules")
        ]
        let документы = [
            Строка(id: "agreement", название: DesignText.т("f_agreement"), значок: "doc.text", хвост: "soglashenie"),
            Строка(id: "offer", название: DesignText.т("f_offer"), значок: "doc.plaintext", хвост: "oferta"),
            Строка(id: "privacy", название: DesignText.т("f_privacy"), значок: "lock.shield", хвост: "privacy")
        ]
        return [
            Группа(id: "buyers", заголовок: DesignText.т("f_buyers"), строки: покупателям),
            Группа(id: "sellers", заголовок: DesignText.т("f_sellers"), строки: продавцам),
            Группа(id: "docs", заголовок: DesignText.т("f_docs"), строки: документы)
        ]
    }

    private var чистыйЗапрос: String {
        запрос.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func подходит(_ текст: String) -> Bool {
        чистыйЗапрос.isEmpty || текст.localizedCaseInsensitiveContains(чистыйЗапрос)
    }

    private var разделы: [РазделГлавной] {
        РазделГлавной.полоса.filter { раздел in
            подходит(DesignText.т("v_" + раздел.ключ)) || подходит(DesignText.т("sub_" + раздел.ключ))
        }
    }

    private var картаВидна: Bool {
        карта && (подходит(MapText.т("map")) || подходит(КатегорииText.т("map_s")))
    }

    private var найденныеГруппы: [Группа] {
        группы.compactMap { группа in
            let строки = группа.строки.filter { подходит($0.название) }
            return строки.isEmpty ? nil : Группа(id: группа.id, заголовок: группа.заголовок, строки: строки)
        }
    }

    private var поддержкаВидна: Bool {
        чистыйЗапрос.isEmpty || подходит(КатегорииText.т("support"))
    }

    private var пусто: Bool {
        !картаВидна && разделы.isEmpty && найденныеГруппы.isEmpty && !поддержкаВидна
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                шапка
                поле
                if картаВидна {
                    строкаКарты
                }
                if !разделы.isEmpty {
                    заголовок(КатегорииText.т("sections"))
                    сеткаРазделов
                }
                ForEach(найденныеГруппы) { группа in
                    заголовок(группа.заголовок)
                    блок(группа.строки)
                }
                if поддержкаВидна {
                    заголовок(КатегорииText.т("support"))
                    поддержка
                }
                if пусто {
                    Text(КатегорииText.т("none"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.фонСтраницы)
        .task {
            /* Справка откроется сразу: страница /help на языке приложения — в память и на диск, пока окно открыто. */
            await ЗагрузкаСтатьи.прогреть(СтраницаСайта(слаг: "help", якорь: nil))
        }
    }

    // MARK: - Части

    private var шапка: some View {
        HStack(alignment: .center) {
            Text(DesignText.т("categories"))
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button { закрыть() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(width: 34, height: 34)
                    .background(Theme.поверхность, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(DesignText.т("close"))
        }
    }

    /// .mh-csearch: лупа и поле «Найти категорию».
    private var поле: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            TextField(КатегорииText.т("find"), text: $запрос)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(Theme.текст)
            if !запрос.isEmpty {
                Button { запрос = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.текстВторой)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DesignText.т("clear"))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    /// «Карта» — крупной строкой, как зелёная кнопка #mk-map-btn.
    private var строкаКарты: some View {
        Button { выбрать(.карта) } label: {
            HStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [Theme.кнопкаКамерыКонец, Theme.кнопкаКамерыНачало],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(MapText.т("map"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(КатегорииText.т("map_s"))
                        .font(.footnote)
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текстВторой.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
    }

    private func заголовок(_ текст: String) -> some View {
        Text(текст.uppercased())
            .font(.system(size: 12, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(Theme.текстВторой)
            .padding(.bottom, -8)
            .accessibilityAddTraits(.isHeader)
    }

    /// Плитки разделов — цвет раздела, значок полосы разделов, название и подпись (vsub_*).
    private var сеткаРазделов: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(разделы) { раздел in
                плиткаРаздела(раздел)
            }
        }
    }

    private func плиткаРаздела(_ раздел: РазделГлавной) -> some View {
        let краска = Color(uiColor: Theme.hex(раздел.краска))
        return Button { выбрать(.раздел(раздел.ключ)) } label: {
            HStack(spacing: 10) {
                Image(systemName: раздел.значок)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(краска)
                    .frame(width: 36, height: 36)
                    .background(краска.opacity(0.13),
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(DesignText.т("v_" + раздел.ключ))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(DesignText.т("sub_" + раздел.ключ))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        .accessibilityHint(раздел.вакансии ? DesignText.т("on_site") : "")
    }

    private func блок(_ строки: [Строка]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(строки.enumerated()), id: \.element.id) { номер, строка in
                if номер > 0 {
                    Theme.линия
                        .frame(height: 1)
                        .padding(.leading, 52)
                        .accessibilityHidden(true)
                }
                строкаСправки(строка)
            }
        }
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private func строкаСправки(_ строка: Строка) -> some View {
        Button {
            if let адрес = Config.страницаСайта(строка.хвост) {
                выбрать(.страница(адрес))
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: строка.значок)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(строка.название)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.текстВторой.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Реквизиты поддержки подвала: почта и телефон открывает система, часы работы — подписью.
    private var поддержка: some View {
        VStack(spacing: 0) {
            if let почта = URL(string: "mailto:support@kliko.kz") {
                Link(destination: почта) {
                    строкаСвязи(значок: "envelope", текст: "support@kliko.kz")
                }
            }
            Theme.линия
                .frame(height: 1)
                .padding(.leading, 52)
                .accessibilityHidden(true)
            if let телефон = URL(string: "tel:+77780008372") {
                Link(destination: телефон) {
                    строкаСвязи(значок: "phone", текст: "+7 778 000 83 72")
                }
            }
            Text(DesignText.т("f_hours"))
                .font(.footnote)
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 52)
                .padding(.bottom, 12)
        }
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private func строкаСвязи(значок: String, текст: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: значок)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.текст)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}

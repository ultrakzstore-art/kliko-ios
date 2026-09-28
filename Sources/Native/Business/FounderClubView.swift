import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/**
 «КЛУБ ОСНОВАТЕЛЕЙ» — ЭТАП 48 (владелец 26.09.2026: «всё одно и то же, просто код разный»). Пункт «Акции» меню кабинета.

 Окно clubOpen / _clubRender сайта и блок «Партнёрская программа» экрана showFounder (_founderPartner): GET
 cabinet.php?action=ref_stats → stats. Номер участника и «−N%» пожизненной скидки с полосой «база + друзья» и подсказкой
 «База −N% · за друзей +M%/друг · до K%», «Друзей активировано», без номера — «Скидка до −90% ждёт»; акций нет
 (promos_on === false) — «Акций пока нет». Ссылка: «Копировать», «Поделиться» (системный лист с текстом club_share_text),
 WhatsApp и Telegram — теми же адресами, что clubWa / clubTg. «Картинка с QR для поста» (clubIg / clubTt,
 _clubBuildCard сайта): подпись со ссылкой — в буфер, тост «Подпись скопирована — …», картинка 1080×1920 с тем же
 рисунком, что canvas сайта, QR — CoreImage (qrCodeGenerator) по ссылке клуба, и системный лист (файл + подпись).
 Промокод (redeem_coupon) — только при Config.цифровыеПокупки и ПродуктыApple.промокодКлуба (сайт прячет его вместе
 с покупками, klkAppNoDigital); выключено — карточки промокода нет вовсе, без ссылок на сайт.
 */
struct ЭкранКлуба: View {
    let открыть: (URL) -> Void

    @ObservedObject private var модель = БизнесМодель.shared
    @State private var входОткрыт = false
    @State private var листПоста: ЛистПостаКлуба? = nil
    @State private var промокод = ""
    @State private var применяем = false
    @State private var итог: ИтогПромокода? = nil

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    /// Окно результата промокода (clubPromoResult сайта).
    struct ИтогПромокода: Identifiable {
        let id = UUID()
        let заголовок: String
        let текст: String
    }

    /// Промокод виден только при покупках через App Store.
    private var естьПромокод: Bool { Config.цифровыеПокупки && ПродуктыApple.промокодКлуба }

    var body: some View {
        содержимое
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("club_title"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await модель.загрузитьКлуб() }
            .sheet(isPresented: $входОткрыт) {
                ЭкранВхода(eGovВключён: true, открыть: открыть, вошли: {
                    Task { await модель.загрузитьКлуб() }
                })
            }
            .overlay(alignment: .bottom) {
                if let текст = модель.плашка { ПлашкаКошелька(текст: текст) }
            }
            .sheet(item: $листПоста) { лист in
                ЛистПоделитьсяКабинета(предметы: [лист.картинка, лист.подпись])
            }
            .alert(item: $итог) { окно in
                Alert(title: Text(окно.заголовок), message: Text(окно.текст), dismissButton: .default(Text(т("close"))))
            }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.клубЗагрузка {
        case .нуженВход:
            ПустоСайта(значок: "person.crop.circle", заголовок: CabinetText.т("signed_out"),
                       подпись: CabinetText.т("signed_out_sub"), кнопка: CabinetText.т("login"),
                       действие: { войти() })
        case .ошибка(let текст):
            if let клуб = модель.клуб {
                список(клуб)
            } else {
                ПустоСайта(значок: "wifi.exclamationmark", заголовок: текст, кнопка: т("retry"),
                           действие: { Task { await модель.загрузитьКлуб() } })
            }
        case .нет, .идёт, .готово:
            if let клуб = модель.клуб {
                список(клуб)
            } else {
                ЗагрузкаБизнеса()
            }
        }
    }

    private func список(_ к: КлубОснователей) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if к.акцииИдут {
                    ГеройКлуба(клуб: к)
                    ссылка(к)
                    if естьПромокод { промо }
                } else {
                    ГеройБезАкций()
                }
                if let партнёр = к.партнёр { ПартнёрКлубаВид(партнёр: партнёр) }
            }
            .padding(12)
        }
        .refreshable { await модель.загрузитьКлуб() }
    }

    // MARK: - Ссылка

    /// .club-bd: подпись, ссылка в рамке, сетки кнопок по две и заметка по центру внизу.
    private func ссылка(_ к: КлубОснователей) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            метка(т("club_your_link_label"), значок: "link")
                .padding(.top, 4)
                .padding(.bottom, 8)
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .accessibilityHidden(true)
                Text(к.ссылка.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
            HStack(spacing: 10) {
                Button { скопировать(к.ссылка) } label: {
                    видКнопки(т("club_copy"), значок: "doc.on.doc", цвет: Theme.текст)
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                поделиться(к.ссылка)
            }
            .padding(.top, 10)
            метка(ТекстыQRКлуба.т("label"), значок: "qrcode")
                .padding(.top, 16)
            HStack(spacing: 10) {
                внешняя("WhatsApp", значок: "message.fill", цвет: Theme.whatsApp) {
                    "https://wa.me/?text=" + ПоделитьсяСайта.код(т("club_share_text") + " " + к.ссылка)
                }
                внешняя("Telegram", значок: "paperplane.fill", цвет: Color(uiColor: Theme.hex(0x2AABEE))) {
                    "https://t.me/share/url?url=" + ПоделитьсяСайта.код(к.ссылка) + "&text="
                        + ПоделитьсяСайта.код(т("club_share_text"))
                }
            }
            .padding(.top, 10)
            .disabled(к.ссылка.isEmpty)
            HStack(spacing: 10) {
                соцсеть("Instagram", значок: "camera", цвет: Color(uiColor: Theme.hex(0xE1306C)), ссылка: к.ссылка)
                соцсеть("TikTok", значок: "music.note", цвет: Color(uiColor: Theme.hex(0xFE2C55)), ссылка: к.ссылка)
            }
            .padding(.top, 10)
            .disabled(к.ссылка.isEmpty)
            Text(т("club_note"))
                .font(.system(size: 12))
                .lineSpacing(4)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
        }
    }

    /// .club-lbl: значок 15 акцентом и серая подпись 13.
    private func метка(_ текст: String, значок: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: значок)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
        }
        .padding(.horizontal, 2)
        .accessibilityAddTraits(.isHeader)
    }

    /// .club-btn: серая плашка с рамкой, цветной значок 17 и подпись 14.
    private func видКнопки(_ подпись: String, значок: String, цвет: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: значок)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(цвет)
                .accessibilityHidden(true)
            Text(подпись)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    /// .club-btn.pri: зелёный градиент, белые значок и подпись.
    private func видГлавной(_ подпись: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .semibold))
                .accessibilityHidden(true)
            Text(подпись)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(КраскаБизнеса.градиентКнопки, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    /// clubIg / clubTt сайта: кнопка своей соцсети.
    private func соцсеть(_ имя: String, значок: String, цвет: Color, ссылка: String) -> some View {
        Button {
            Task { @MainActor in готовитьПост(имя, ссылка: ссылка) }
        } label: {
            видКнопки(имя, значок: значок, цвет: цвет)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
    }

    /// _clubSocialShare: подпись со ссылкой — в буфер, тост с именем соцсети, картинка 9:16 — в системный лист.
    @MainActor
    private func готовитьПост(_ имя: String, ссылка: String) {
        guard !ссылка.isEmpty else {
            модель.показать(т("club_no_link"))
            return
        }
        let подпись = т("club_share_text") + " " + ссылка
        UIPasteboard.general.string = подпись
        модель.показать(ТекстыQRКлуба.т("hint").replacingOccurrences(of: "{app}", with: имя))
        guard let картинка = КарточкаКлубаДляПоста.нарисовать(ссылка: ссылка) else {
            модель.показать(ТекстыQRКлуба.т("failed"))
            return
        }
        листПоста = ЛистПостаКлуба(картинка: картинка, подпись: подпись)
    }

    /// «Поделиться» — navigator.share({title, text, url}) сайта: системный лист с текстом и ссылкой.
    @ViewBuilder
    private func поделиться(_ ссылка: String) -> some View {
        if let адрес = URL(string: ссылка), !ссылка.isEmpty {
            ShareLink(item: адрес, subject: Text("Kliko.kz"), message: Text(т("club_share_text"))) {
                видГлавной(т("club_share"))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        } else {
            Button { модель.показать(т("club_no_link")) } label: {
                видГлавной(т("club_share"))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
        }
    }

    private func внешняя(_ подпись: String, значок: String, цвет: Color, адрес: @escaping () -> String) -> some View {
        Button {
            if let u = URL(string: адрес()) { UIApplication.shared.open(u, options: [:], completionHandler: nil) }
        } label: {
            видКнопки(подпись, значок: значок, цвет: цвет)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
    }

    /// cabRefCopy сайта: «Скопировано!»; ссылки нет — «Ссылка недоступна».
    private func скопировать(_ ссылка: String) {
        guard !ссылка.isEmpty else {
            модель.показать(т("club_no_link"))
            return
        }
        UIPasteboard.general.string = ссылка
        модель.показать(т("copied_excl"))
    }

    // MARK: - Промокод (Config.цифровыеПокупки и ПродуктыApple.промокодКлуба)

    private var промо: some View {
        КарточкаБизнеса(т("club_promo_label"), значок: "ticket") {
            HStack(spacing: 8) {
                TextField(т("club_promo_placeholder"), text: $промокод)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .font(.system(size: 15, weight: .bold))
                    .padding(10)
                    .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                            .strokeBorder(Theme.линия, lineWidth: 1)
                    }
                    .onChange(of: промокод) { _, стало in
                        let верх = стало.uppercased()
                        if верх != стало { промокод = верх }
                    }
                КнопкаБизнеса(подпись: т("club_promo_apply"), занято: применяем) { применить() }
                    .frame(width: 130)
            }
        }
    }

    /// clubApplyPromo → redeem_coupon {csrf, code}: только по нажатию «Применить», один запрос за раз.
    private func применить() {
        let код = промокод.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !код.isEmpty else {
            модель.показать(т("club_promo_empty"))
            return
        }
        guard !применяем else { return }
        применяем = true
        Task { @MainActor in
            let j = await модель.применитьПромокод(код)
            применяем = false
            итог = разобрать(j)
            if МоиОбъявленияAPI.да(j["ok"]) {
                промокод = ""
                await модель.загрузитьКлуб()
            }
        }
    }

    /// clubPromoResult: успех — «Промокод активирован!», «−N%», «Действует до …»; отказ — по reason
    /// (used / expired / limit / notfound) или «К сожалению, не получилось» и текст сервера.
    private func разобрать(_ j: [String: Any]) -> ИтогПромокода {
        typealias A = МоиОбъявленияAPI
        if A.да(j["ok"]) {
            var текст = "−" + КлубОснователей.процент(A.число(j["pct"])) + "% " + т("club_promo_ok_scope")
            if let дата = СделкиФормат.дата(A.строка(j["until"])) {
                let ф = DateFormatter()
                ф.locale = Locale(identifier: "ru_RU")
                ф.dateFormat = "dd.MM.yyyy"
                текст += "\n" + БизнесText.т("club_promo_ok_until", ["date": ф.string(from: дата),
                                                                    "days": String(A.целое(j["days"]))])
            }
            return ИтогПромокода(заголовок: т("club_promo_ok_title"), текст: текст)
        }
        let причина = A.строка(j["reason"])
        switch причина {
        case "used", "expired", "limit", "notfound":
            return ИтогПромокода(заголовок: т("club_promo_" + причина + "_title"), текст: т("club_promo_" + причина + "_sub"))
        default:
            let ошибка = A.строка(j["error"])
            return ИтогПромокода(заголовок: т("club_promo_err_title"),
                                 текст: ошибка.isEmpty ? т("club_promo_apply_failed") : ошибка)
        }
    }

    private func войти() {
        if Config.нативныйВход {
            входОткрыт = true
        } else if let u = Config.страницаСайта("cabinet.php") {
            открыть(u)
        }
    }
}

// MARK: - Верх окна клуба (.club-hero)

private struct ГеройКлуба: View {
    let клуб: КлубОснователей

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    /// Доли полосы: база и друзья от потолка, в процентах (l и d у сайта).
    private var доли: (Double, Double) {
        let потолок = клуб.потолок > 0 ? клуб.потолок : 90
        let база = max(0, min(100, (клуб.база / потолок * 100).rounded()))
        let друзья = max(0, min(100 - база, (клуб.бонус / потолок * 100).rounded()))
        return (база / 100, друзья / 100)
    }

    private var подсказка: String {
        let рост: String
        if клуб.шаг > 0 {
            рост = БизнесText.т("club_growth_per_friend", ["step": КлубОснователей.процент(клуб.шаг),
                                                          "cap": КлубОснователей.процент(клуб.потолок)])
        } else {
            рост = БизнесText.т("club_growth_fixed", ["cap": КлубОснователей.процент(клуб.потолок)])
        }
        return БизнесText.т("club_base_hint", ["base": КлубОснователей.процент(клуб.база), "growth": рост])
    }

    var body: some View {
        VStack(spacing: 0) {
            if клуб.номер > 0 {
                участник
            } else {
                ЗамокКлуба(значок: "lock.fill")
                Text(т("club_locked_title"))
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 4)
                Text(т("club_locked_sub"))
                    .font(.system(size: 13))
                    .foregroundStyle(КраскаКлуба.подпись)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .modifier(ФонГерояКлуба())
    }

    @ViewBuilder
    private var участник: some View {
        Label(клуб.ступень.uppercased() + " #" + String(клуб.номер), systemImage: "medal.fill")
            .font(.system(size: 12, weight: .heavy))
            .tracking(0.6)
            .foregroundStyle(Color(uiColor: Theme.hex(0x4A3708)))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(LinearGradient(colors: [Color(uiColor: Theme.hex(0xF7E08A)), Color(uiColor: Theme.hex(0xE6BB50))],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
            .shadow(color: Color(uiColor: Theme.hex(0xE9C15A, 0.5)), radius: 6, y: 5)
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("−" + КлубОснователей.процент(клуб.скидка))
                .font(.system(size: 60, weight: .black))
            Text("%")
                .font(.system(size: 29, weight: .heavy))
        }
        .foregroundStyle(Color.white)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .shadow(color: КраскаКлуба.зелёный.opacity(0.5), radius: 17, y: 6)
        .environment(\.layoutDirection, .leftToRight)
        .padding(.top, 14)
        .padding(.bottom, 4)
        Text(т("club_lifetime_discount_sub"))
            .font(.system(size: 13))
            .foregroundStyle(КраскаКлуба.подпись)
            .multilineTextAlignment(.center)
        GeometryReader { гео in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16))
                HStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.5)).frame(width: гео.size.width * доли.0)
                    Rectangle()
                        .fill(LinearGradient(colors: [КраскаКлуба.зелёный, КраскаКлуба.мята],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: гео.size.width * доли.1)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 9)
        .padding(.horizontal, 6)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .accessibilityHidden(true)
        Text(подсказка)
            .font(.system(size: 12))
            .foregroundStyle(Color(uiColor: Theme.hex(0x9FE6BD)))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Краски .club-hero: в обеих темах одинаковые.
private enum КраскаКлуба {
    static let зелёный = Color(uiColor: Theme.hex(0x25D366))
    static let мята = Color(uiColor: Theme.hex(0x8AFFC4))
    static let подпись = Color(uiColor: Theme.hex(0xBFF5D4))
    static let фон = LinearGradient(stops: [
        .init(color: Color(uiColor: Theme.hex(0x0E5A34)), location: 0),
        .init(color: Color(uiColor: Theme.hex(0x0B3D24)), location: 0.52),
        .init(color: Color(uiColor: Theme.hex(0x07130D)), location: 1)
    ], startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// .club-hero: тёмно-зелёный градиент 140° с зелёным свечением справа сверху, отступы 24 / 24 / 20.
private struct ФонГерояКлуба: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.top, 24)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    КраскаКлуба.фон
                    RadialGradient(colors: [КраскаКлуба.зелёный.opacity(0.28), КраскаКлуба.зелёный.opacity(0)],
                                   center: UnitPoint(x: 0.85, y: 0.1), startRadius: 0, endRadius: 170)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            }
            .accessibilityElement(children: .combine)
    }
}

/// .club-lock: круг 48 с мятным значком 24.
private struct ЗамокКлуба: View {
    let значок: String

    var body: some View {
        Image(systemName: значок)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(КраскаКлуба.мята)
            .frame(width: 48, height: 48)
            .background(Color.white.opacity(0.12), in: Circle())
            .padding(.bottom, 12)
            .accessibilityHidden(true)
    }
}

/// promos_on === false: «Акций пока нет».
private struct ГеройБезАкций: View {
    var body: some View {
        VStack(spacing: 0) {
            ЗамокКлуба(значок: "ticket")
            Text(БизнесText.т("club_no_promos_title"))
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.bottom, 4)
            Text(БизнесText.т("club_no_promos_sub"))
                .font(.system(size: 13))
                .foregroundStyle(КраскаКлуба.подпись)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .modifier(ФонГерояКлуба())
    }
}

/// «Партнёрская программа» (_founderPartner сайта).
private struct ПартнёрКлубаВид: View {
    let партнёр: ПартнёрКлуба

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

    var body: some View {
        КарточкаБизнеса(т("pt_title") + " · " + КлубОснователей.процент(партнёр.ставка) + "%", значок: "banknote") {
            VStack(spacing: 2) {
                Text(СделкиФормат.тенге(партнёр.текущий))
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .monospacedDigit()
                Text(т("pt_month"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            Divider()
            СтрокаЗначенияБизнеса(название: т("pt_invited"), значение: СделкиФормат.деньги(партнёр.приведено))
            Divider()
            СтрокаЗначенияБизнеса(название: т("pt_pending"), значение: СделкиФормат.тенге(партнёр.накоплено))
            Divider()
            СтрокаЗначенияБизнеса(название: т("pt_paid"), значение: СделкиФормат.тенге(партнёр.выплачено))
            Text(т("pt_note").replacingOccurrences(of: "{n}", with: СделкиФормат.деньги(партнёр.порог)))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Картинка с QR для поста (_clubBuildCard сайта)

/// Что отдаём системному листу: картинка и подпись (navigator.share({files, text}) сайта).
private struct ЛистПостаКлуба: Identifiable {
    let id = UUID()
    let картинка: UIImage
    let подпись: String
}

/// Свои слова блока QR: у БизнесText их нет. Русские — с сайта (club_qr_image_label, club_social_hint, common_failed).
private enum ТекстыQRКлуба {
    static func т(_ ключ: String) -> String {
        let словарь: [String: String]
        switch БизнесText.язык {
        case "kk": словарь = kk
        case "en": словарь = en
        case "ar": словарь = ar
        default: словарь = ru
        }
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    static let ru: [String: String] = [
        "label": "Картинка с QR для поста",
        "hint": "Подпись скопирована — сохраните картинку и вставьте в {app}",
        "failed": "Не удалось",
        "scan": "Сканируй QR или переходи по ссылке",
        "a11y": "QR-код ссылки клуба"
    ]
    static let kk: [String: String] = [
        "label": "Жазбаға арналған QR суреті",
        "hint": "Жазба көшірілді — суретті сақтап, {app} ішіне қойыңыз",
        "failed": "Болмады",
        "scan": "QR-ды сканерле немесе сілтемеге өт",
        "a11y": "Клуб сілтемесінің QR-коды"
    ]
    static let en: [String: String] = [
        "label": "QR image for a post",
        "hint": "Caption copied — save the image and paste it into {app}",
        "failed": "Failed",
        "scan": "Scan the QR or follow the link",
        "a11y": "QR code of the club link"
    ]
    static let ar: [String: String] = [
        "label": "صورة QR للمنشور",
        "hint": "تم نسخ النص — احفظ الصورة والصقه في {app}",
        "failed": "تعذّر ذلك",
        "scan": "امسح رمز QR أو اتبع الرابط",
        "a11y": "رمز QR لرابط النادي"
    ]
}

/// QR ссылки — CoreImage, без сети (у сайта _cmpQrDataURL). Чёрные модули без сглаживания.
private enum QRКлуба {
    static func картинка(_ текст: String, сторона: CGFloat) -> UIImage? {
        let фильтр = CIFilter.qrCodeGenerator()
        фильтр.message = Data(текст.utf8)
        фильтр.correctionLevel = "M"
        guard let код = фильтр.outputImage, код.extent.width > 0 else { return nil }
        let масштаб = max(1, (сторона / код.extent.width).rounded(.up))
        let крупный = код.transformed(by: CGAffineTransform(scaleX: масштаб, y: масштаб))
        guard let готово = CIContext().createCGImage(крупный, from: крупный.extent) else { return nil }
        return UIImage(cgImage: готово)
    }
}

/**
 Картинка 1080×1920 — рисунок canvas сайта (формат 9x16): зелёный градиент с бликом, знак, «КЛУБ ОСНОВАТЕЛЕЙ»,
 «Тебя не кинут», белая карточка с QR (475 px, поля 26, скругление 26), ссылка и «Сканируй QR…». Слова на картинке
 сайт пишет по-русски на любом языке — так же и здесь. Всегда светлая, в пикселях 1:1.
 */
private struct КарточкаКлубаДляПоста: View {
    let ссылка: String
    let код: UIImage?

    private static let ширина: CGFloat = 1080
    private static let высота: CGFloat = 1920

    @MainActor
    static func нарисовать(ссылка: String) -> UIImage? {
        let вид = КарточкаКлубаДляПоста(ссылка: ссылка, код: QRКлуба.картинка(ссылка, сторона: 475))
        let рисовальщик = ImageRenderer(content: вид)
        рисовальщик.scale = 1
        return рисовальщик.uiImage
    }

    private static func цвет(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255)
    }

    private var мята: Color { Self.цвет(138, 255, 196) }

    var body: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Self.цвет(14, 90, 52), location: 0),
                .init(color: Self.цвет(11, 61, 36), location: 0.55),
                .init(color: Self.цвет(7, 19, 13), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Self.цвет(37, 211, 102).opacity(0.22), Self.цвет(37, 211, 102).opacity(0)],
                           center: UnitPoint(x: 0.82, y: 0.08), startRadius: 40, endRadius: 1080)
            знак.position(x: 540, y: 117)
            строка("КЛУБ ОСНОВАТЕЛЕЙ", 30, .bold, мята).position(x: 540, y: 226)
            строка("Тебя", 100, .black, .white).position(x: 540, y: 456)
            строка("не кинут", 100, .black, .white).position(x: 540, y: 568)
            строка("Маркетплейс безопасных сделок", 40, .medium, Self.цвет(223, 243, 231)).position(x: 540, y: 667)
            строка("Новичкам скидка до −90%", 48, .heavy, мята).position(x: 540, y: 730)
            qr.position(x: 540, y: 1293)
            строка(ссылка.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression), 36, .bold, .white)
                .position(x: 540, y: 1606)
            строка("Сканируй QR или переходи по ссылке", 34, .medium, Self.цвет(191, 245, 212))
                .position(x: 540, y: 1659)
            строка("Старт — 14 августа", 42, .heavy, мята).position(x: 540, y: 1821)
        }
        .frame(width: Self.ширина, height: Self.высота)
        .environment(\.colorScheme, .light)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func строка(_ текст: String, _ размер: CGFloat, _ вес: Font.Weight, _ цвет: Color) -> some View {
        Text(текст)
            .font(.system(size: размер, weight: вес))
            .foregroundStyle(цвет)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: 1000)
    }

    /// Знак Kliko белым (у сайта — иконка 146 px, без неё — «Kliko.kz»).
    private var знак: some View {
        let высота: CGFloat = 100
        let ширина = 296 * высота / 74
        return ZStack(alignment: .topLeading) {
            Image("WmKliko").resizable().renderingMode(.template).foregroundStyle(Color.white)
                .frame(width: ширина, height: высота)
            Image("WmKz").resizable().renderingMode(.original)
                .frame(width: ширина, height: высота)
        }
        .frame(width: ширина, height: высота)
    }

    @ViewBuilder
    private var qr: some View {
        if let код {
            Image(uiImage: код)
                .interpolation(.none)
                .resizable()
                .frame(width: 475, height: 475)
                .padding(26)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white)
                .frame(width: 527, height: 527)
        }
    }
}

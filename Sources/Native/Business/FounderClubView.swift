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
 Промокода (redeem_coupon) нет: сайт прячет его вместе с покупками (klkAppNoDigital), а платные услуги в приложении
 не продаются.
 */
struct ЭкранКлуба: View {
    let открыть: (URL) -> Void

    @ObservedObject private var модель = БизнесМодель.shared
    @State private var входОткрыт = false
    @State private var листПоста: ЛистПостаКлуба? = nil

    init(открыть: @escaping (URL) -> Void) {
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { БизнесText.т(ключ) }

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
                    ЗаметкаБизнеса(т("club_note"), тон: .серый, значок: "info.circle")
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

    private func ссылка(_ к: КлубОснователей) -> some View {
        КарточкаБизнеса(т("club_your_link_label"), значок: "link") {
            Text(к.ссылка.replacingOccurrences(of: "^https?://", with: "", options: .regularExpression))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.текст)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            HStack(spacing: 10) {
                КнопкаБизнеса(подпись: т("club_copy"), второстепенная: true) { скопировать(к.ссылка) }
                поделиться(к.ссылка)
            }
            Text(ТекстыQRКлуба.т("label"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .padding(.top, 2)
            if !к.ссылка.isEmpty { ПревьюQRКлуба(ссылка: к.ссылка) }
            HStack(spacing: 10) {
                внешняя("WhatsApp", цвет: Theme.whatsApp) {
                    "https://wa.me/?text=" + ПоделитьсяСайта.код(т("club_share_text") + " " + к.ссылка)
                }
                внешняя("Telegram", цвет: Theme.проверен) {
                    "https://t.me/share/url?url=" + ПоделитьсяСайта.код(к.ссылка) + "&text="
                        + ПоделитьсяСайта.код(т("club_share_text"))
                }
            }
            .disabled(к.ссылка.isEmpty)
            HStack(spacing: 10) {
                соцсеть("Instagram", цвет: Color(red: 0.84, green: 0.16, blue: 0.46), ссылка: к.ссылка)
                соцсеть("TikTok", цвет: Color(red: 0.07, green: 0.07, blue: 0.07), ссылка: к.ссылка)
            }
            .disabled(к.ссылка.isEmpty)
        }
    }

    /// clubIg / clubTt сайта: кнопка своей соцсети.
    private func соцсеть(_ имя: String, цвет: Color, ссылка: String) -> some View {
        Button {
            Task { @MainActor in готовитьПост(имя, ссылка: ссылка) }
        } label: {
            Text(имя)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(цвет, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
        .buttonStyle(.plain)
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
                Text(т("club_share"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.акцент, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            КнопкаБизнеса(подпись: т("club_share")) { модель.показать(т("club_no_link")) }
        }
    }

    private func внешняя(_ подпись: String, цвет: Color, адрес: @escaping () -> String) -> some View {
        Button {
            if let u = URL(string: адрес()) { UIApplication.shared.open(u) }
        } label: {
            Text(подпись)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(цвет, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
        .buttonStyle(.plain)
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
        VStack(spacing: 10) {
            if клуб.номер > 0 {
                участник
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.white)
                    .accessibilityHidden(true)
                Text(т("club_locked_title"))
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                Text(т("club_locked_sub"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.шапкаМята)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Theme.шапкаВерх, Theme.шапкаНиз], startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var участник: some View {
        Label(клуб.ступень.uppercased() + " #" + String(клуб.номер), systemImage: "medal.fill")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Theme.шапкаМятаТекст)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Theme.шапкаМята, in: Capsule())
        Text("−" + КлубОснователей.процент(клуб.скидка) + "%")
            .font(.system(size: 44, weight: .heavy))
            .foregroundStyle(Color.white)
            .monospacedDigit()
        Text(т("club_lifetime_discount_sub"))
            .font(.system(size: 14))
            .foregroundStyle(Theme.шапкаМята)
        GeometryReader { гео in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                HStack(spacing: 0) {
                    Rectangle().fill(Color.white).frame(width: гео.size.width * доли.0)
                    Rectangle().fill(Theme.шапкаМята).frame(width: гео.size.width * доли.1)
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
        Text(подсказка)
            .font(.system(size: 13))
            .foregroundStyle(Theme.шапкаМята)
            .multilineTextAlignment(.center)
        HStack {
            Text(БизнесText.т("club_friends", ["n": String(клуб.друзей), "b": КлубОснователей.процент(клуб.бонус)]))
            Spacer(minLength: 8)
            Text(БизнесText.т("club_cap", ["n": КлубОснователей.процент(клуб.потолок)]))
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.white.opacity(0.85))
    }
}

/// promos_on === false: «Акций пока нет».
private struct ГеройБезАкций: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "ticket")
                .font(.system(size: 26))
                .foregroundStyle(Color.white)
                .accessibilityHidden(true)
            Text(БизнесText.т("club_no_promos_title"))
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.white)
            Text(БизнесText.т("club_no_promos_sub"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.шапкаМята)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [Theme.шапкаВерх, Theme.шапкаНиз], startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .accessibilityElement(children: .combine)
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

/// QR на экране: белая скруглённая карточка, под ней — подпись, как на картинке сайта.
private struct ПревьюQRКлуба: View {
    let ссылка: String

    var body: some View {
        VStack(spacing: 8) {
            if let код = QRКлуба.картинка(ссылка, сторона: 480) {
                Image(uiImage: код)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 168, height: 168)
                    .padding(10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel(ТекстыQRКлуба.т("a11y"))
            }
            Text(ТекстыQRКлуба.т("scan"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
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

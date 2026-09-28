import SwiftUI
import UIKit

/**
 «КЛУБ ОСНОВАТЕЛЕЙ» — ЭТАП 48 (владелец 26.09.2026: «всё одно и то же, просто код разный»). Пункт «Акции» меню кабинета.

 Окно clubOpen / _clubRender сайта и блок «Партнёрская программа» экрана showFounder (_founderPartner): GET
 cabinet.php?action=ref_stats → stats. Номер участника и «−N%» пожизненной скидки с полосой «база + друзья» и подсказкой
 «База −N% · за друзей +M%/друг · до K%», «Друзей активировано», без номера — «Скидка до −90% ждёт»; акций нет
 (promos_on === false) — «Акций пока нет». Ссылка: «Копировать», «Поделиться» (системный лист с текстом club_share_text),
 WhatsApp и Telegram — теми же адресами, что clubWa / clubTg. Картинка с QR для Instagram и TikTok (canvas сайта) —
 не перенесена: это страница сайта.
 Промокода (redeem_coupon) нет: сайт прячет его вместе с покупками (klkAppNoDigital), а платные услуги в приложении
 не продаются.
 */
struct ЭкранКлуба: View {
    let открыть: (URL) -> Void

    @ObservedObject private var модель = БизнесМодель.shared
    @State private var входОткрыт = false

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
        }
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

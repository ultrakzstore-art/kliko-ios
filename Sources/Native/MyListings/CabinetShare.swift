import SwiftUI
import UIKit
import AVFoundation
import CoreVideo

/**
 «ПОДЕЛИТЬСЯ» КАБИНЕТА — окно showSocialModal сайта (владелец 26.09.2026: «поделиться в кабинете — как на сайте»).

 У сайта два разных окна. Лента и страница объявления — mkShare (ЛистПоделитьсяСайта, SiteShare.swift). Кабинет —
 showSocialModal(id, title, price, img, mode) из js/cabinet.min.js: его зовут advShare(id) у «Моих объявлений»
 (mode "share") и подача с auto = approved (без mode — «опубликовано»). Витрина продавца и прочие места кабинета этим
 окном не делятся (там navigator.share и свои листы) — здесь их нет.

 Окно #social-ov .soc-card сверху вниз:
   · крестик «Закрыть» справа; значок .soc-anim-ic 62 — круг рисуется (.55 с), затем бумажный самолётик (share) или
     галочка (опубликовано) с задержкой .4 с, всё «выпрыгивает» (.45 с); заголовок «Поделитесь объявлением» /
     «Опубликовано! Поделитесь роликом» (подзаголовок .soc-sub сайт прячет);
   · .soc-prev: фото 44, название в две строки, цена зелёным или «Договорная»;
   · только «опубликовано» — promoUpsellHTML: «Продвиньте — продайте быстрее», полосы «Без продвижения ×1» и «В ТОПе
     до ×7» (дорастают за 1 с), пояснение и «Продвинуть объявление» → openPromote; ТОП уже есть — «ТОП уже подключён»;
   · .soc-orshare — «или расскажите о нём» (у share пусто, остаётся отступ);
   · .soc-hero — «Сделать видео и поделиться» на градиенте Instagram (у сайта — студия роликов openReelForListing);
   · .soc-quick — WhatsApp, Telegram, «Ссылка» (socialQuickShare: «Название — 12 000 ₸» и адрес /marketplace.php?item=
     от корня сайта; «Ссылка» кладёт в буфер текст и адрес строкой ниже);
   · «Автопостинг в бизнес-аккаунт ⌄» — раскрывает кнопки Instagram и TikTok по social_status: включено и подключено —
     «Опубликовать в …» (@имя) → social_post; включено — «Подключить …» (один раз — потом постинг в 1 клик) →
     social_connect.php; выключено — серая «скоро — подключается администратором». Оба действия — за PRO
     (proGate("autopost"));
   · «Позже».

 Ролик: студии роликов сайта (модуль reel) в приложении нет — «Сделать видео и поделиться» собирает из постера «Для
 сторис» (у услуги — постер услуги) 5-секундный ролик 1080 × 1920 с медленным приближением (H.264, AVAssetWriter) и
 отдаёт его в системный лист (Reels, TikTok, Stories); подпись со ссылкой — в буфер.

 🔴 ДЕНЬГИ. «Продвинуть объявление» и PRO для автопостинга — при Config.цифровыеПокупки окно App Store
 (ЛистУслугиApple), иначе страница кабинета сайта (ПереходыКабинета.сайт), как у «Моих объявлений».
 */
enum ВидЛистаКабинета: Equatable {
    /// advShare — «Мои объявления».
    case поделиться
    /// После подачи с auto = approved: с блоком «Продвиньте».
    case опубликовано
}

/// Одна соцсеть social_status: enabled, connected, username.
struct СостояниеАвтопостинга: Equatable {
    var включено = false
    var подключено = false
    var имя = ""
}

@MainActor
struct ОкноПоделитьсяКабинета: View {
    let данные: ДанныеОтправкиСайта
    let вид: ВидЛистаКабинета
    /// window.__socialTopActive: ТОП уже подключён при подаче; подписьТопа — __socialTopLabel.
    let топ: Bool
    let подписьТопа: String
    private let закрытьЛист: (() -> Void)?
    private let высотаСодержимого: ((CGFloat) -> Void)?

    @Environment(\.dismiss) private var закрытьСреда
    @State private var фото: UIImage? = nil
    @State private var измерено: CGFloat = 0
    @State private var тост: String? = nil
    @State private var задачаТоста: Task<Void, Never>? = nil
    @State private var скопировано = false
    @State private var автопостингОткрыт = false
    /// nil — social_status ещё идёт («Загрузка…»).
    @State private var соцсети: [String: СостояниеАвтопостинга]? = nil
    @State private var публикуется: String? = nil
    @State private var опубликованоВ: Set<String> = []
    @State private var ролик = false
    @State private var появился = false
    @State private var круг = false
    @State private var знак = false
    @State private var полосы = false

    init(данные: ДанныеОтправкиСайта, вид: ВидЛистаКабинета = .поделиться, топ: Bool = false, подписьТопа: String = "",
         закрыть: (() -> Void)? = nil, высота: ((CGFloat) -> Void)? = nil) {
        self.данные = данные
        self.вид = вид
        self.топ = топ
        self.подписьТопа = подписьТопа
        self.закрытьЛист = закрыть
        self.высотаСодержимого = высота
    }

    private func т(_ ключ: String) -> String { CabinetShareText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                шапка
                превью
                    .padding(.vertical, 10)
                if вид == .опубликовано {
                    продвижение
                        .padding(.top, 2)
                    Text(т("or_share"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .padding(.top, 16)
                        .padding(.bottom, 10)
                } else {
                    Color.clear.frame(height: 16)
                }
                герой
                    .padding(.bottom, 10)
                быстрые
                    .padding(.bottom, 10)
                автопостинг
                Button(т("later")) { закрыть() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.поверхность.ignoresSafeArea())
        .overlay(alignment: .bottom) { плашкаТоста }
        .onPreferenceChange(ВысотаЛистаКлюч.self) { новое in
            if abs(новое - измерено) > 0.5 { измерено = новое }
        }
        .onChange(of: измерено) { _, новое in высотаСодержимого?(новое) }
        .task {
            if фото == nil { фото = await ПоделитьсяСайта.загрузить(данные.фото) }
        }
        .task { await загрузитьСоцсети() }
    }

    // MARK: Шапка и превью

    private var шапка: some View {
        VStack(spacing: 6) {
            HStack {
                Spacer(minLength: 0)
                Button { закрыть() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 32, height: 32)
                        .background(Theme.поверхность2, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.94))
                .accessibilityLabel(т("close"))
            }
            .padding(.top, 12)
            значокШапки
            Text(вид == .поделиться ? т("title_share") : т("title_pub"))
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// .soc-anim-ic: круг с заливкой 12 % рисуется, затем самолётик или галочка; всё выпрыгивает.
    private var значокШапки: some View {
        ZStack {
            Circle()
                .fill(Theme.акцент.opacity(0.12))
                .frame(width: 55, height: 55)
            Circle()
                .trim(from: 0, to: круг ? 1 : 0)
                .stroke(Theme.акцент, style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
                .frame(width: 55, height: 55)
            ЗнакОтправкиКабинета(галочка: вид == .опубликовано)
                .trim(from: 0, to: знак ? 1 : 0)
                .stroke(Theme.акцент, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 62, height: 62)
        .scaleEffect(появился ? 1 : 0.6)
        .opacity(появился ? 1 : 0)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(ДвижениеСайта.мягко(.spring(response: 0.45, dampingFraction: 0.62))) { появился = true }
            withAnimation(ДвижениеСайта.мягко(.easeOut(duration: 0.55))) { круг = true }
            withAnimation(ДвижениеСайта.мягко(.easeOut(duration: 0.45).delay(0.4))) { знак = true }
        }
    }

    /// .soc-prev: фото 44, название в две строки, цена зелёным.
    private var превью: some View {
        HStack(spacing: 10) {
            Group {
                if let фото {
                    Image(uiImage: фото).resizable().scaledToFill()
                } else {
                    Theme.поверхность2
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(данные.название)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(2)
                Text(данные.строкаЦены)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.акцент)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Продвижение (promoUpsellHTML)

    @ViewBuilder
    private var продвижение: some View {
        if топ {
            VStack(alignment: .leading, spacing: 8) {
                Label(т("pu_done"), systemImage: "checkmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.зелёный)
                Text(заметкаТопа)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .strokeBorder(Theme.акцент, lineWidth: 1.5)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label(т("pu_h"), systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                VStack(spacing: 10) {
                    полоса(т("pu_lo"), "×1", доля: 0.16, горячая: false)
                    полоса(т("pu_hi"), т("pu_x7"), доля: 1, горячая: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(т("pu_lo")) ×1, \(т("pu_hi")) \(т("pu_x7"))")
                Text(т("pu_note"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                Button { продвинуть() } label: {
                    Label(т("pu_cta"), systemImage: "arrow.up")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(LinearGradient(colors: [Theme.зелёный2, Theme.зелёныйЯркий],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        .shadow(color: Theme.зелёный2.opacity(0.35), radius: 10, x: 0, y: 8)
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            }
            .padding(14)
            .background(LinearGradient(colors: [Theme.мята, Theme.поверхность], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                    .strokeBorder(Theme.акцент, lineWidth: 1.5)
            }
            .onAppear {
                withAnimation(ДвижениеСайта.мягко(.timingCurve(0.2, 0.85, 0.25, 1, duration: 1).delay(0.07))) {
                    полосы = true
                }
            }
        }
    }

    /// «Объявление сразу в верху выдачи · до 12.10. Ничего доплачивать не нужно.»
    private var заметкаТопа: String {
        let хвост = подписьТопа.isEmpty ? "" : " · \(подписьТопа)"
        return "\(т("pu_done_a"))\(хвост). \(т("pu_done_b"))"
    }

    /// .pu-bar: подпись 104 справа, дорожка 15, значение 48.
    private func полоса(_ подпись: String, _ значение: String, доля: CGFloat, горячая: Bool) -> some View {
        HStack(spacing: 10) {
            Text(подпись)
                .font(.system(size: 12, weight: горячая ? .bold : .semibold))
                .foregroundStyle(горячая ? Theme.текст : Theme.текстВторой)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 104, alignment: .trailing)
            GeometryReader { г in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.поверхность2)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(горячая
                              ? AnyShapeStyle(LinearGradient(colors: [Theme.зелёный2, Theme.зелёныйЯркий],
                                                             startPoint: .leading, endPoint: .trailing))
                              : AnyShapeStyle(Theme.цвет(0xC2CCC7, 0x55625B)))
                        .frame(width: г.size.width * (полосы ? доля : 0))
                }
            }
            .frame(height: 15)
            Text(значение)
                .font(.system(size: 14, weight: .heavy).monospacedDigit())
                .foregroundStyle(горячая ? Theme.акцент : Theme.текстВторой)
                .lineLimit(1)
                .frame(width: 48, alignment: .leading)
        }
    }

    // MARK: Ролик, быстрые кнопки, автопостинг

    /// .soc-hero: градиент Instagram, значок камеры в полупрозрачном квадрате, стрелка.
    private var герой: some View {
        Button { сделатьРолик() } label: {
            HStack(spacing: 12) {
                ZStack {
                    if ролик {
                        ProgressView().tint(Color.white)
                    } else {
                        Image(systemName: "video")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.2), in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                Text(т("hero"))
                    .font(.system(size: 17, weight: .heavy))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("→")
                    .font(.system(size: 18, weight: .heavy))
                    .opacity(0.9)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(ЦветаКабинетаПоделиться.герой,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .shadow(color: Color(uiColor: Theme.hex(0xEE2A7B, 0.4)), radius: 12, x: 0, y: 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.985))
        .disabled(ролик)
        .accessibilityHint(т("hero_sub"))
    }

    /// .soc-quick: три кнопки в рамке — WhatsApp, Telegram, «Ссылка».
    private var быстрые: some View {
        HStack(spacing: 8) {
            быстрая("WhatsApp", действие: { whatsApp() }) {
                ЗнакWhatsApp().colorMultiply(Theme.whatsApp)
            }
            быстрая("Telegram", действие: { telegram() }) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(uiColor: Theme.hex(0x229ED9)))
            }
            быстрая(скопировано ? т("copied") : т("link"), действие: { скопировать() }) {
                Image(systemName: скопировано ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(скопировано ? Theme.акцент : Theme.цвет(0x475569, 0x94A3B8))
            }
        }
    }

    private func быстрая<Знак: View>(_ подпись: String, действие: @escaping () -> Void,
                                     @ViewBuilder знак: () -> Знак) -> some View {
        Button(action: действие) {
            VStack(spacing: 6) {
                знак()
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text(подпись)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 4)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.96))
        .accessibilityLabel(подпись)
    }

    /// .soc-more-t и #soc-btns.
    private var автопостинг: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(ДвижениеСайта.смена) { автопостингОткрыт.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(т("autopost"))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(автопостингОткрыт ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            .accessibilityAddTraits(автопостингОткрыт ? .isSelected : [])
            if автопостингОткрыт {
                VStack(spacing: 8) {
                    if let соцсети {
                        соцсеть("instagram", "Instagram", соцсети["instagram"] ?? СостояниеАвтопостинга())
                        соцсеть("tiktok", "TikTok", соцсети["tiktok"] ?? СостояниеАвтопостинга())
                    } else {
                        Text(т("loading"))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.текстВторой)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    /// .soc-btn: «Опубликовать в …» / «Подключить …» / серая «скоро».
    private func соцсеть(_ ключ: String, _ имя: String, _ с: СостояниеАвтопостинга) -> some View {
        let идёт = публикуется == ключ
        let готово = опубликованоВ.contains(ключ)
        let заголовок: String
        let подпись: String
        if !с.включено {
            заголовок = имя
            подпись = т("soon")
        } else if с.подключено {
            заголовок = готово ? т("posted") : (идёт ? т("posting") : String(format: т("post_to"), имя))
            подпись = с.имя.isEmpty ? "" : "@\(с.имя)"
        } else {
            заголовок = String(format: т("connect"), имя)
            подпись = т("connect_sub")
        }
        return Button { нажатаСоцсеть(ключ, имя, с) } label: {
            HStack(spacing: 12) {
                знакСоцсети(ключ)
                    .frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 16, weight: .heavy))
                    if !подпись.isEmpty {
                        Text(подпись)
                            .font(.system(size: 12, weight: .semibold))
                            .opacity(0.85)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if с.включено && !готово {
                    Text("→")
                        .font(.system(size: 18, weight: .heavy))
                        .opacity(0.9)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Color.white)
            .padding(14)
            .background(фонСоцсети(ключ, готово: готово),
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Color.white.opacity(ключ == "tiktok" ? 0.12 : 0), lineWidth: 1)
            }
            .opacity(с.включено ? (идёт ? 0.6 : 1) : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .disabled(!с.включено || идёт || готово)
    }

    private func фонСоцсети(_ ключ: String, готово: Bool) -> AnyShapeStyle {
        if готово { return AnyShapeStyle(Theme.зелёный) }
        if ключ == "instagram" { return AnyShapeStyle(ЦветаКабинетаПоделиться.instagram) }
        return AnyShapeStyle(Color(uiColor: Theme.hex(0x010101)))
    }

    @ViewBuilder
    private func знакСоцсети(_ ключ: String) -> some View {
        if ключ == "instagram" {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 22, height: 22)
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 9, height: 9)
                Circle()
                    .fill(Color.white)
                    .frame(width: 3, height: 3)
                    .offset(x: 5.5, y: -5.5)
            }
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 21, weight: .bold))
        }
    }

    @ViewBuilder
    private var плашкаТоста: some View {
        if let тост {
            Text(тост)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: Theme.hex(0x12271C, 0.94)), in: Capsule())
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    // MARK: Действия

    private func закрыть() {
        if let закрытьЛист { закрытьЛист() } else { закрытьСреда() }
    }

    private func показатьТост(_ текст: String, секунд: Double = 1.8) {
        задачаТоста?.cancel()
        withAnimation(ДвижениеСайта.появление) { тост = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        задачаТоста = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(секунд * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(ДвижениеСайта.уход) { тост = nil }
        }
    }

    /// socialQuickShare: location.origin + "/marketplace.php?item=" + id — от корня сайта, без языка.
    private var адресКабинета: URL {
        Config.url("/marketplace.php?item=" + ПоделитьсяСайта.код(данные.id)) ?? данные.адрес
    }

    /// «Название — 12 000 ₸»; без цены — одно название.
    private var подписьОтправки: String {
        guard данные.цена > 0 else { return данные.название }
        return "\(данные.название) — \(DesignText.число(Int(данные.цена.rounded()))) ₸"
    }

    private func whatsApp() {
        let текст = ПоделитьсяСайта.код("\(подписьОтправки) \(адресКабинета.absoluteString)")
        ПоделитьсяСайта.открыть("whatsapp://send?text=\(текст)", запасной: "https://wa.me/?text=\(текст)")
    }

    private func telegram() {
        let ссылка = ПоделитьсяСайта.код(адресКабинета.absoluteString)
        let текст = ПоделитьсяСайта.код(подписьОтправки)
        ПоделитьсяСайта.открыть("tg://msg_url?url=\(ссылка)&text=\(текст)",
                                запасной: "https://t.me/share/url?url=\(ссылка)&text=\(текст)")
    }

    /// «Ссылка»: в буфер «Название — цена ₸» и адрес строкой ниже; на кнопке — галочка (_copiedTick).
    private func скопировать() {
        UIPasteboard.general.string = "\(подписьОтправки)\n\(адресКабинета.absoluteString)"
        ОткликСайта.успех()
        withAnimation(ДвижениеСайта.выбор) { скопировано = true }
        показатьТост(т("link_copied"))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            withAnimation(ДвижениеСайта.выбор) { скопировано = false }
        }
    }

    /// openPromote: платно — App Store при Config.цифровыеПокупки, иначе cabinet.php?promote=<id> сайта.
    private func продвинуть() {
        let номер = данные.id
        закрыть()
        if Config.цифровыеПокупки {
            ЛистУслугиApple.показать(.продвижение, цель: номер)
        } else {
            ПереходыКабинета.сайт("cabinet.php?promote=" + ПоделитьсяСайта.код(номер))
        }
    }

    /// Ролик 1080 × 1920 из постера «Для сторис» — в системный лист; подпись со ссылкой — в буфер.
    private func сделатьРолик() {
        guard !ролик else { return }
        ролик = true
        показатьТост(т("video_making"), секунд: 2.5)
        Task { @MainActor in
            if фото == nil { фото = await ПоделитьсяСайта.загрузить(данные.фото) }
            var файл: URL? = nil
            if let постер = ПоделитьсяСайта.постер(данные, фото: фото, высота: 1920) {
                файл = await РоликПостера.сделать(постер)
            }
            ролик = false
            guard let файл else {
                ОткликСайта.предупреждение()
                показатьТост(т("video_fail"), секунд: 3)
                return
            }
            UIPasteboard.general.string = "\(подписьОтправки)\n\(адресКабинета.absoluteString)"
            ОткликСайта.успех()
            показатьТост(т("video_ready"), секунд: 3.5)
            ПоделитьсяСайта.системныйЛист([файл])
        }
    }

    /// cabinet.php?action=social_status → {ok, instagram: {enabled, connected, username}, tiktok: {…}}. Сбой — обе
    /// кнопки серые «скоро», как renderSocialBtns(null) сайта.
    private func загрузитьСоцсети() async {
        typealias A = МоиОбъявленияAPI
        var итог: [String: СостояниеАвтопостинга] = [:]
        if let j = try? await A.получить("cabinet.php?action=social_status"), A.да(j["ok"]) {
            for ключ in ["instagram", "tiktok"] {
                guard let запись = j[ключ] as? [String: Any] else { continue }
                итог[ключ] = СостояниеАвтопостинга(включено: A.да(запись["enabled"]), подключено: A.да(запись["connected"]),
                                                   имя: A.строка(запись["username"]))
            }
        }
        withAnimation(ДвижениеСайта.смена) { соцсети = итог }
    }

    private func нажатаСоцсеть(_ ключ: String, _ имя: String, _ с: СостояниеАвтопостинга) {
        guard с.включено, публикуется == nil else { return }
        Task { @MainActor in
            guard await естьАвтопостинг() else {
                нуженПРО()
                return
            }
            if с.подключено {
                await опубликовать(ключ, имя)
            } else {
                подключить(ключ, имя)
            }
        }
    }

    /// proGate("autopost"): уровень PRO со страницы кабинета; страница не прочиталась — пусть решит сервер.
    private func естьАвтопостинг() async -> Bool {
        let модель = БизнесМодель.shared
        if модель.страница == nil { await модель.загрузитьСтраницу() }
        guard let страница = модель.страница else { return true }
        return страница.естьФункция("autopost")
    }

    /// showProOffer: PRO — окно App Store при Config.цифровыеПокупки, иначе кабинет сайта.
    private func нуженПРО() {
        показатьТост(т("pro_need"), секунд: 2)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            закрыть()
            if Config.цифровыеПокупки {
                ЛистУслугиApple.показать(.про)
            } else {
                ПереходыКабинета.сайт("cabinet.php")
            }
        }
    }

    /// socialConnect: «Переходим к подключению …» и social_connect.php?platform=&do=start страницей сайта.
    private func подключить(_ ключ: String, _ имя: String) {
        показатьТост(String(format: т("connecting"), имя), секунд: 2)
        guard let адрес = Config.страницаСайта("social_connect.php?platform=\(ключ)&do=start") else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            закрыть()
            ПоверхВсего.открытьАдрес(адрес)
        }
    }

    /// socialPost: POST social_post {id, platform}; «Публикуем…», затем «Опубликовано ✓» или слова сервера.
    private func опубликовать(_ ключ: String, _ имя: String) async {
        typealias A = МоиОбъявленияAPI
        публикуется = ключ
        do {
            let j = try await A.отправить("cabinet.php?action=social_post", тело: ["id": данные.id, "platform": ключ])
            публикуется = nil
            if A.да(j["ok"]) {
                опубликованоВ.insert(ключ)
                ОткликСайта.успех()
                показатьТост(String(format: т("posted_to"), имя), секунд: 3.5)
            } else if A.да(j["need_connect"]) {
                подключить(ключ, имя)
            } else {
                let слова = A.строка(j["msg"])
                ОткликСайта.предупреждение()
                показатьТост(слова.isEmpty ? т("post_fail") : слова, секунд: 4)
            }
        } catch {
            публикуется = nil
            показатьТост(т("no_conn"))
        }
    }
}

// MARK: - Показ одной строкой

extension ОкноПоделитьсяКабинета {
    /// Лист кабинета поверх верхнего экрана: высота по содержимому, на iPad — окно по центру.
    @MainActor
    static func показать(_ данные: ДанныеОтправкиСайта, вид: ВидЛистаКабинета = .поделиться, топ: Bool = false,
                         подписьТопа: String = "") {
        guard let верх = ПоделитьсяСайта.верхнийЭкран() else { return }
        let мерка = МеркаЛистаПоделиться()
        let хост = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
        let экран = ОкноПоделитьсяКабинета(данные: данные, вид: вид, топ: топ, подписьТопа: подписьТопа,
                                           закрыть: { [weak хост] in хост?.dismiss(animated: true) },
                                           высота: { [weak хост] новая in мерка.обновить(новая, хост: хост) })
        хост.rootView = AnyView(экран)
        хост.view.backgroundColor = UIColor(Theme.поверхность)
        хост.modalPresentationStyle = .formSheet
        хост.preferredContentSize = CGSize(width: 440, height: 600)
        if let лист = хост.sheetPresentationController {
            лист.detents = [
                .custom(identifier: МеркаЛистаПоделиться.метка) { контекст in
                    мерка.высотаЛиста(контекст.maximumDetentValue)
                }
            ]
            лист.prefersGrabberVisible = true
            лист.preferredCornerRadius = 22
            лист.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        верх.present(хост, animated: true)
    }
}

// MARK: - Краски и знак

enum ЦветаКабинетаПоделиться {
    /// .soc-hero: linear-gradient(120deg, #f9ce34, #ee2a7b 44%, #6228d7).
    static let герой = LinearGradient(
        stops: [
            Gradient.Stop(color: Color(uiColor: Theme.hex(0xF9CE34)), location: 0),
            Gradient.Stop(color: Color(uiColor: Theme.hex(0xEE2A7B)), location: 0.44),
            Gradient.Stop(color: Color(uiColor: Theme.hex(0x6228D7)), location: 1)
        ],
        startPoint: UnitPoint(x: 0, y: 0.8), endPoint: UnitPoint(x: 1, y: 0.2))

    /// .soc-ig: linear-gradient(135deg, #feda75, #d62976 45%, #962fbf 75%, #4f5bd5).
    static let instagram = LinearGradient(
        stops: [
            Gradient.Stop(color: Color(uiColor: Theme.hex(0xFEDA75)), location: 0),
            Gradient.Stop(color: Color(uiColor: Theme.hex(0xD62976)), location: 0.45),
            Gradient.Stop(color: Color(uiColor: Theme.hex(0x962FBF)), location: 0.75),
            Gradient.Stop(color: Color(uiColor: Theme.hex(0x4F5BD5)), location: 1)
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Знак .soc-anim-k в поле 52 × 52: самолётик «M37 16 L15 24 L24 28 L28 37 Z» или галочка «M15 27 l7 7 15-15».
struct ЗнакОтправкиКабинета: Shape {
    let галочка: Bool

    func path(in прямоугольник: CGRect) -> Path {
        let k = min(прямоугольник.width, прямоугольник.height) / 52
        let x0 = прямоугольник.midX - 26 * k
        let y0 = прямоугольник.midY - 26 * k
        func точка(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: x0 + x * k, y: y0 + y * k)
        }
        var путь = Path()
        if галочка {
            путь.move(to: точка(15, 27))
            путь.addLine(to: точка(22, 34))
            путь.addLine(to: точка(37, 19))
        } else {
            путь.move(to: точка(37, 16))
            путь.addLine(to: точка(15, 24))
            путь.addLine(to: точка(24, 28))
            путь.addLine(to: точка(28, 37))
            путь.closeSubpath()
        }
        return путь
    }
}

// MARK: - Ролик из постера

/**
 Короткий ролик для Reels, TikTok и Stories: постер 1080 × 1920 медленно приближается (1,00 → 1,08, плавный ход) за
 5 секунд, 30 кадров в секунду, H.264 в .mp4 во временной папке. Пишется вне главной нити.
 */
enum РоликПостера {
    static func сделать(_ картинка: UIImage) async -> URL? {
        guard let кадр = картинка.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) {
            РоликПостера.записать(кадр)
        }.value
    }

    private static func записать(_ кадр: CGImage) -> URL? {
        let ширина = 1080
        let высота = 1920
        let кадров = 150
        let адрес = FileManager.default.temporaryDirectory.appendingPathComponent("kliko-\(UUID().uuidString).mp4")
        guard let писатель = try? AVAssetWriter(outputURL: адрес, fileType: .mp4) else { return nil }
        let настройки: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: ширина,
            AVVideoHeightKey: высота
        ]
        let вход = AVAssetWriterInput(mediaType: .video, outputSettings: настройки)
        вход.expectsMediaDataInRealTime = false
        let атрибуты: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: ширина,
            kCVPixelBufferHeightKey as String: высота
        ]
        let адаптер = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: вход, sourcePixelBufferAttributes: атрибуты)
        guard писатель.canAdd(вход) else { return nil }
        писатель.add(вход)
        guard писатель.startWriting() else { return nil }
        писатель.startSession(atSourceTime: .zero)

        let пространство = CGColorSpaceCreateDeviceRGB()
        let раскладка = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        var целиком = true
        for номер in 0..<кадров {
            var ждали = 0
            while !вход.isReadyForMoreMediaData && ждали < 2000 {
                Thread.sleep(forTimeInterval: 0.005)
                ждали += 1
            }
            guard let пул = адаптер.pixelBufferPool else { целиком = false; break }
            var буфер: CVPixelBuffer? = nil
            CVPixelBufferPoolCreatePixelBuffer(nil, пул, &буфер)
            guard let буфер else { целиком = false; break }
            CVPixelBufferLockBaseAddress(буфер, [])
            if let контекст = CGContext(data: CVPixelBufferGetBaseAddress(буфер), width: ширина, height: высота,
                                        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(буфер),
                                        space: пространство, bitmapInfo: раскладка) {
                let доля = CGFloat(номер) / CGFloat(кадров - 1)
                let ход = доля * доля * (3 - 2 * доля)
                let масштаб = 1 + 0.08 * ход
                let w = CGFloat(ширина) * масштаб
                let h = CGFloat(высота) * масштаб
                контекст.interpolationQuality = .high
                контекст.draw(кадр, in: CGRect(x: (CGFloat(ширина) - w) / 2, y: (CGFloat(высота) - h) / 2, width: w, height: h))
            }
            CVPixelBufferUnlockBaseAddress(буфер, [])
            if !адаптер.append(буфер, withPresentationTime: CMTime(value: CMTimeValue(номер), timescale: 30)) {
                целиком = false
                break
            }
        }
        вход.markAsFinished()
        let сигнал = DispatchSemaphore(value: 0)
        писатель.finishWriting { сигнал.signal() }
        сигнал.wait()
        guard целиком, писатель.status == .completed else {
            try? FileManager.default.removeItem(at: адрес)
            return nil
        }
        return адрес
    }
}

// MARK: - Тексты

/// Тексты окна кабинета (строки showSocialModal, promoUpsellHTML, renderSocialBtns сайта) — kk/ru/en/ar.
enum CabinetShareText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "title_share": "Поделитесь объявлением", "title_pub": "Опубликовано! Поделитесь роликом",
            "close": "Закрыть", "later": "Позже", "or_share": "или расскажите о нём",
            "pu_h": "Продвиньте — продайте быстрее", "pu_lo": "Без продвижения", "pu_hi": "В ТОПе", "pu_x7": "до ×7",
            "pu_note": "Объявление поднимается в ТОП выдачи и авто-поднимается в ленте — в разы больше просмотров и откликов.",
            "pu_cta": "Продвинуть объявление", "pu_done": "ТОП уже подключён",
            "pu_done_a": "Объявление сразу в верху выдачи", "pu_done_b": "Ничего доплачивать не нужно.",
            "hero": "Сделать видео и поделиться", "hero_sub": "Reels · TikTok · Stories — в один тап",
            "link": "Ссылка", "copied": "Скопировано!", "link_copied": "Ссылка скопирована",
            "autopost": "Автопостинг в бизнес-аккаунт", "loading": "Загрузка…",
            "post_to": "Опубликовать в %@", "connect": "Подключить %@",
            "connect_sub": "один раз — потом постинг в 1 клик", "soon": "скоро — подключается администратором",
            "posting": "Публикуем…", "posted": "Опубликовано ✓", "posted_to": "Опубликовано в %@ ✓",
            "post_fail": "Не удалось опубликовать", "connecting": "Переходим к подключению %@…",
            "no_conn": "Нет соединения с интернетом", "pro_need": "Автопостинг доступен в тарифе PRO",
            "video_making": "Готовим ролик…", "video_fail": "Не получилось сделать ролик",
            "video_ready": "Ролик готов — подпись со ссылкой скопирована"
        ],
        "kk": [
            "title_share": "Хабарландырумен бөлісіңіз", "title_pub": "Жарияланды! Роликпен бөлісіңіз",
            "close": "Жабу", "later": "Кейін", "or_share": "немесе ол туралы айтыңыз",
            "pu_h": "Жарнамалаңыз — тезірек сатыңыз", "pu_lo": "Жарнамасыз", "pu_hi": "ТОП-та", "pu_x7": "×7 дейін",
            "pu_note": "Хабарландыру іздеу нәтижесінің ТОП-ына көтеріліп, лентада автоматты көтеріледі — қаралым мен өтінім бірнеше есе көп.",
            "pu_cta": "Хабарландыруды жарнамалау", "pu_done": "ТОП қосылған",
            "pu_done_a": "Хабарландыру бірден іздеудің жоғарғы жағында", "pu_done_b": "Қосымша төлеудің қажеті жоқ.",
            "hero": "Бейне жасап, бөлісу", "hero_sub": "Reels · TikTok · Stories — бір түртумен",
            "link": "Сілтеме", "copied": "Көшірілді!", "link_copied": "Сілтеме көшірілді",
            "autopost": "Бизнес-аккаунтқа автопостинг", "loading": "Жүктелуде…",
            "post_to": "%@ желісіне жариялау", "connect": "%@ қосу",
            "connect_sub": "бір рет — кейін 1 рет басып жариялау", "soon": "жақында — әкімші қосады",
            "posting": "Жариялаудамыз…", "posted": "Жарияланды ✓", "posted_to": "%@ желісінде жарияланды ✓",
            "post_fail": "Жариялау мүмкін болмады", "connecting": "%@ қосуға өтудеміз…",
            "no_conn": "Интернет байланысы жоқ", "pro_need": "Автопостинг PRO тарифінде қолжетімді",
            "video_making": "Ролик дайындалуда…", "video_fail": "Ролик жасау мүмкін болмады",
            "video_ready": "Ролик дайын — сілтемесі бар жазба көшірілді"
        ],
        "en": [
            "title_share": "Share your listing", "title_pub": "Published! Share a video",
            "close": "Close", "later": "Later", "or_share": "or tell people about it",
            "pu_h": "Promote it — sell faster", "pu_lo": "Without promotion", "pu_hi": "In TOP", "pu_x7": "up to ×7",
            "pu_note": "The listing rises to the TOP of search and is auto-bumped in the feed — many times more views and replies.",
            "pu_cta": "Promote listing", "pu_done": "TOP is already on",
            "pu_done_a": "The listing is at the top of search right away", "pu_done_b": "Nothing more to pay.",
            "hero": "Make a video and share", "hero_sub": "Reels · TikTok · Stories — in one tap",
            "link": "Link", "copied": "Copied!", "link_copied": "Link copied",
            "autopost": "Autopost to a business account", "loading": "Loading…",
            "post_to": "Post to %@", "connect": "Connect %@",
            "connect_sub": "once — then post in 1 tap", "soon": "coming soon — being set up by the admin",
            "posting": "Posting…", "posted": "Posted ✓", "posted_to": "Posted to %@ ✓",
            "post_fail": "Could not post", "connecting": "Opening %@ connection…",
            "no_conn": "No internet connection", "pro_need": "Autoposting is part of the PRO plan",
            "video_making": "Making the video…", "video_fail": "Could not make the video",
            "video_ready": "Video ready — caption with the link copied"
        ],
        "ar": [
            "title_share": "شارك إعلانك", "title_pub": "تم النشر! شارك فيديو",
            "close": "إغلاق", "later": "لاحقًا", "or_share": "أو أخبر الآخرين عنه",
            "pu_h": "روّج له — بِع أسرع", "pu_lo": "بدون ترويج", "pu_hi": "في القمة", "pu_x7": "حتى ×7",
            "pu_note": "يرتفع الإعلان إلى قمة نتائج البحث ويُرفع تلقائيًا في الموجز — مشاهدات وردود أكثر بأضعاف.",
            "pu_cta": "روّج للإعلان", "pu_done": "القمة مفعّلة بالفعل",
            "pu_done_a": "الإعلان في أعلى نتائج البحث مباشرة", "pu_done_b": "لا حاجة لدفع أي شيء إضافي.",
            "hero": "أنشئ فيديو وشاركه", "hero_sub": "Reels · TikTok · Stories — بلمسة واحدة",
            "link": "الرابط", "copied": "تم النسخ!", "link_copied": "تم نسخ الرابط",
            "autopost": "النشر التلقائي في حساب الأعمال", "loading": "جارٍ التحميل…",
            "post_to": "انشر في %@", "connect": "اربط %@",
            "connect_sub": "مرة واحدة — ثم النشر بلمسة", "soon": "قريبًا — يربطه المسؤول",
            "posting": "جارٍ النشر…", "posted": "تم النشر ✓", "posted_to": "تم النشر في %@ ✓",
            "post_fail": "تعذّر النشر", "connecting": "جارٍ الانتقال لربط %@…",
            "no_conn": "لا يوجد اتصال بالإنترنت", "pro_need": "النشر التلقائي متاح في باقة PRO",
            "video_making": "جارٍ تجهيز الفيديو…", "video_fail": "تعذّر إنشاء الفيديو",
            "video_ready": "الفيديو جاهز — تم نسخ النص مع الرابط"
        ]
    ]
}

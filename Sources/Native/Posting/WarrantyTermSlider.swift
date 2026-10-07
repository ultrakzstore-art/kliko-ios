import SwiftUI
import UIKit

/**
 СРОК ГАРАНТИИ «КАК ГРОМКОСТЬ» И ОТМЕТКИ ДОВЕРИЯ ПЛИТКАМИ — openTrust и trsWarInput сайта (js/cabinet.js, владелец
 17.09.2026: «гарантию лучше как громкость и до 12 мес — выше 7 дней только для магазинов с PRO; галочки „чек есть“,
 „проверено“ — выстроить нормальный дизайн»). Один и тот же блок у мастера подачи и правки (ШагДополнительно) и у окна
 настроек опубликованного объявления (ЛистНастроекОбъявления).

 Шкала — шаги WR_STOPS сайта: нет · 3 · 7 · 14 дней · 1 · 2 · 3 · 6 · 9 · 12 месяцев (365 дней — «12 месяцев»). Без PRO
 дальше 7 дней (WR_FREE_MAX) ползунок не встаёт: часть шкалы за 7 днями заштрихована, ползунок возвращается на 7, а
 подсказка «Дольше 7 дней — для магазинов с PRO» вздрагивает. Сервер держит то же (listing_warranty_clamp) и отвечает
 clamped — «Без PRO гарантия — до 7 дней: сохранили 7 дней». Сохранённый срок вне шагов (пачкой можно было поставить
 21 день) показывается как есть, пока ползунок не тронули.

 Кнопка PRO у сайта в приложении iOS скрыта (klkAppNoDigital): цифровое — только покупкой App Store. Здесь так же:
 при Config.цифровыеПокупки — кнопка окна покупки App Store (ЦифроваяПокупка), иначе одно пояснение; ссылок на сайт нет.

 Подсказка про гарантийный талон («После оплаты вы подпишете гарантийный талон через eGov…») — только там, где талон
 бывает: товар через гарант, не услуги, работа, авто и жильё, не прокат без цены; и только когда срок выбран.
 */
struct ПолзунокГарантии: View {
    @Binding var дней: Int
    let pro: Bool
    /// Подпись поля: «Гарантия продавца» (или своя подпись знака из TRUST_SETS).
    let заголовок: String
    /// Показывать ли подсказку про талон (talon сайта).
    let талон: Bool

    /// WR_STOPS и WR_FREE_MAX сайта.
    static let шаги: [Int] = [0, 3, 7, 14, 30, 60, 90, 180, 270, 365]
    static let безPRO = 7

    @State private var встряска: CGFloat = 0
    @State private var тянут = false
    /// Уже упёрлись в 7 дней за это касание — встряска и отклик один раз, а не на каждое движение пальца.
    @State private var упёрся = false

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    /// _trsIdx: ближайший шаг снизу.
    static func индекс(_ дней: Int) -> Int {
        var i = 0
        for (k, шаг) in шаги.enumerated() where дней >= шаг { i = k }
        return i
    }

    private static var последний: Int { шаги.count - 1 }
    private static var свободныйИндекс: Int { шаги.firstIndex(of: безPRO) ?? 2 }

    private var значение: String { ШагДополнительно.срокГарантии(дней) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            шапка
            дорожка
                .frame(height: 30)
            шкала
                .frame(height: 16)
            if !pro { заметкаPRO }
            if талон && дней > 0 { заметкаТалона }
        }
        .padding(12)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    // MARK: Шапка (.trs-war-hd)

    private var шапка: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
                .frame(width: 32, height: 32)
                .background(Theme.мята, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(заголовок)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(т("wr_from_receipt"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text(значение)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(дней > 0 ? Theme.зелёный2 : Theme.текстВторой)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.18), value: дней)
        }
    }

    // MARK: Дорожка (.trs-rng)

    /// Шкала всегда слева направо: дни и месяцы читаются по возрастанию и в арабском.
    private var дорожка: some View {
        GeometryReader { гео in
            let ширина = max(1, гео.size.width - 26)
            let индекс = Self.индекс(дней)
            let доля = CGFloat(индекс) / CGFloat(Self.последний)
            let доляЗамка = CGFloat(Self.свободныйИндекс) / CGFloat(Self.последний)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.линия)
                    .frame(height: 6)
                    .padding(.horizontal, 13)
                if !pro {
                    ШтриховкаЗамкаГарантии()
                        .frame(width: ширина * (1 - доляЗамка), height: 6)
                        .clipShape(Capsule())
                        .offset(x: 13 + ширина * доляЗамка)
                }
                Capsule()
                    .fill(Theme.зелёный2)
                    .frame(width: max(6, ширина * доля), height: 6)
                    .offset(x: 13)
                ForEach(0..<Self.шаги.count, id: \.self) { k in
                    Circle()
                        .fill(k <= индекс ? Theme.зелёный2 : Theme.текстВторой.opacity(0.35))
                        .frame(width: 4, height: 4)
                        .offset(x: 13 + ширина * CGFloat(k) / CGFloat(Self.последний) - 2, y: 9)
                }
                Circle()
                    .fill(Color.white)
                    .frame(width: 26, height: 26)
                    .overlay { Circle().strokeBorder(Theme.зелёный2, lineWidth: 2.5) }
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                    .scaleEffect(тянут ? 1.12 : 1)
                    .offset(x: ширина * доля)
                    .animation(.snappy(duration: 0.16), value: индекс)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { жест in
                        тянут = true
                        выбрать(Int(((жест.location.x - 13) / ширина * CGFloat(Self.последний)).rounded()))
                    }
                    .onEnded { _ in
                        тянут = false
                        упёрся = false
                    }
            )
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityElement()
        .accessibilityLabel(т("wr_range_aria"))
        .accessibilityValue(значение)
        .accessibilityAdjustableAction { куда in
            let сейчас = Self.индекс(дней)
            упёрся = false
            switch куда {
            case .increment: выбрать(сейчас + 1)
            case .decrement: выбрать(сейчас - 1)
            @unknown default: break
            }
        }
    }

    /// trsWarInput: шаг → дни; без PRO дальше 7 дней не встаёт — обратно на 7 и встряхнуть подсказку.
    private func выбрать(_ сырой: Int) {
        var индекс = min(Self.последний, max(0, сырой))
        if !pro && индекс > Self.свободныйИндекс {
            индекс = Self.свободныйИндекс
            if !упёрся {
                упёрся = true
                withAnimation(.linear(duration: 0.4)) { встряска += 1 }
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        }
        let новые = Self.шаги[индекс]
        guard новые != дней else { return }
        дней = новые
        UISelectionFeedbackGenerator().selectionChanged()
    }

    // MARK: Подписи шкалы (.trs-scale)

    private var шкала: some View {
        GeometryReader { гео in
            let ширина = max(1, гео.size.width - 26)
            let места: [Int] = [0, 2, 4, 7, 9]
            let подписи: [String] = [т("wr_none"), т("wr_scale_7"), т("wr_scale_1m"), т("wr_scale_6m"), т("wr_scale_12m")]
            ZStack(alignment: .topLeading) {
                ForEach(0..<места.count, id: \.self) { k in
                    Text(подписи[k])
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                        .fixedSize()
                        .position(x: 13 + ширина * CGFloat(места[k]) / CGFloat(Self.последний), y: 8)
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    // MARK: Без PRO (.trs-pro)

    private var заметкаPRO: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(т("wr_pro_note"), systemImage: "lock")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(ВстряскаПодсказкиГарантии(сила: встряска))
            /* Цифровое в приложении — только покупкой App Store; без неё — одно пояснение (klkAppNoDigital сайта). */
            if Config.цифровыеПокупки {
                ЦифроваяПокупка(услуга: .про)
            }
        }
    }

    // MARK: Талон (.trs-talon)

    private var заметкаТалона: some View {
        Label(т("wr_talon_note"), systemImage: "doc.text")
            .font(.system(size: 12.5))
            .foregroundStyle(Theme.зелёный2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.мята, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// .trs-lock сайта: заштрихованная часть шкалы за 7 днями (без PRO).
private struct ШтриховкаЗамкаГарантии: View {
    var body: some View {
        Canvas { контекст, размер in
            контекст.fill(Path(CGRect(origin: .zero, size: размер)), with: .color(Theme.линия))
            var x: CGFloat = -размер.height
            while x < размер.width {
                var штрих = Path()
                штрих.move(to: CGPoint(x: x, y: размер.height))
                штрих.addLine(to: CGPoint(x: x + размер.height, y: 0))
                контекст.stroke(штрих, with: .color(Theme.текстВторой.opacity(0.35)), lineWidth: 1.2)
                x += 5
            }
        }
        .accessibilityHidden(true)
    }
}

/// .nudge сайта: подсказка вздрагивает, когда ползунок упёрся в 7 дней.
private struct ВстряскаПодсказкиГарантии: GeometryEffect {
    var сила: CGFloat

    var animatableData: CGFloat {
        get { сила }
        set { сила = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(сила * .pi * 4), y: 0))
    }
}

/**
 Отметки доверия плитками (.trs-chk сайта): значок знака, подпись и квадрат с галочкой; нажал — включил. Значки — по
 ключу знака (TRS_ICO сайта), нет своего — галочка в круге.
 */
struct ПлиткиЗнаковДоверия: View {
    let знаки: [ЗнакДоверия]
    @Binding var отмечено: [String]

    /// TRS_ICO сайта → SF Symbols.
    static func значок(_ ключ: String) -> String {
        let карта: [String: String] = [
            "receipt": "doc.plaintext", "working": "waveform.path.ecg", "complete": "shippingbox",
            "vin_clean": "doc.text.magnifyingglass", "not_crashed": "car", "service_book": "book.closed",
            "one_owner": "person", "docs_ok": "checkmark.seal", "no_liens": "lock.open",
            "lawyer_checked": "building.columns", "mortgage_ok": "house", "vet_passport": "pawprint",
            "sterilized": "cross.case", "vet_checked": "stethoscope", "pedigree": "tag", "trained": "medal",
            "original": "seal", "tags": "tag", "measured": "ruler", "no_defects": "checkmark.circle",
            "safety_cert": "shield", "clean": "drop", "not_recalled": "arrow.uturn.backward.circle",
            "guarantor": "checkmark.shield", "licensed": "person.text.rectangle", "portfolio": "briefcase",
            "deposit": "creditcard", "contract": "signature", "condition_act": "list.clipboard",
            "insured": "umbrella", "cleaned": "sparkles"
        ]
        return карта[ключ] ?? "checkmark.circle"
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(знаки) { знак in
                плитка(знак)
            }
        }
    }

    private func плитка(_ знак: ЗнакДоверия) -> some View {
        let вкл = отмечено.contains(знак.id)
        return Button {
            отмечено.removeAll { $0 == знак.id }
            if !вкл { отмечено.append(знак.id) }
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: Self.значок(знак.id))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(вкл ? Theme.зелёный2 : Theme.текстВторой)
                    .frame(width: 28, height: 28)
                    .background(вкл ? Theme.мята : Theme.поверхность2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                Text(знак.подпись)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: вкл ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18))
                    .foregroundStyle(вкл ? Theme.зелёный2 : Theme.линия)
                    .accessibilityHidden(true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(вкл ? Theme.зелёный2 : Theme.линия, lineWidth: вкл ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(знак.подпись)
        .accessibilityAddTraits(вкл ? [.isButton, .isSelected] : .isButton)
    }
}

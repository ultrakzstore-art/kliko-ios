import SwiftUI
import UIKit

/**
 ДОКУМЕНТ РЕЗЮМЕ — СВОИМ ВИДОМ (этап 50). jrDocHTML сайта (js/jobs-resume.min.js): те же восемь оформлений JR_TPL —
 боковая полоса слева или справа, шапка, простой лист; те же разделы («Контакты», «Навыки» полосами, «Языки», «О себе»,
 «Опыт работы» с точками, «Образование», «Ожидания: от N ₸», подпись «Резюме создано на Kliko.kz · Работа»).
 Лист всегда светлый, как бумага (и в тёмной теме), — так его увидит работодатель и так он печатается у сайта.
 */
struct ДокументРезюме: View {
    let запись: ЗаписьРаботы
    let шаблон: ШаблонРезюме

    private func т(_ ключ: String) -> String { РезюмеText.т(ключ) }

    private var акцент: Color { Color(uiColor: Theme.hex(шаблон.акцент)) }
    private var акцент2: Color { Color(uiColor: Theme.hex(шаблон.акцент2)) }
    private static let чернила = Color(uiColor: Theme.hex(0x12211A))
    private static let серый = Color(uiColor: Theme.hex(0x6B7C73))
    private static let текстАбзаца = Color(uiColor: Theme.hex(0x3A4A42))

    private var дизайн: Font.Design { шаблон.serif ? .serif : .default }

    var body: some View {
        Group {
            switch шаблон.раскладка {
            case .слева, .справа:
                HStack(alignment: .top, spacing: 0) {
                    if шаблон.раскладка == .слева { полоса }
                    основное
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    if шаблон.раскладка == .справа { полоса }
                }
            case .шапка:
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 14) {
                        фото(ширина: 78, рамка: Color.white.opacity(0.3))
                        шапкаИмени(наЦвете: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(LinearGradient(colors: [акцент, акцент2], startPoint: .topLeading, endPoint: .bottomTrailing))
                    VStack(alignment: .leading, spacing: 0) {
                        разделы
                        боковые(наЦвете: false)
                        подпись
                    }
                    .padding(16)
                }
            case .просто:
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 14) {
                        фото(ширина: 72, рамка: .clear)
                        VStack(alignment: .leading, spacing: 6) {
                            шапкаИмени(наЦвете: false)
                            контакты(наЦвете: false)
                        }
                    }
                    .padding(.bottom, 12)
                    Rectangle().fill(акцент).frame(height: 3)
                    разделы
                    навыки(наЦвете: false, заголовокРаздела: true)
                    языки(наЦвете: false, заголовокРаздела: true)
                    подпись
                }
                .padding(18)
            }
        }
        .font(.system(size: 13, design: дизайн))
        .foregroundStyle(Self.чернила)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .contain)
    }

    // MARK: Боковая полоса

    private var полоса: some View {
        VStack(alignment: .leading, spacing: 0) {
            фото(ширина: 96, рамка: Color.white.opacity(0.22))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
            боковые(наЦвете: true)
        }
        .padding(12)
        .frame(width: 132, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(LinearGradient(colors: [акцент, акцент2], startPoint: .topLeading, endPoint: .bottomTrailing))
        .foregroundStyle(Color.white)
    }

    @ViewBuilder
    private func боковые(наЦвете: Bool) -> some View {
        if !пустыеКонтакты {
            заголовокПолосы(т("doc_contacts"), наЦвете: наЦвете)
            контакты(наЦвете: наЦвете)
        }
        навыки(наЦвете: наЦвете, заголовокРаздела: !наЦвете)
        языки(наЦвете: наЦвете, заголовокРаздела: !наЦвете)
    }

    private var пустыеКонтакты: Bool {
        запись.телефон.isEmpty && запись.город.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func заголовокПолосы(_ текст: String, наЦвете: Bool) -> some View {
        Text(текст.uppercased())
            .font(.system(size: 10.5, weight: .heavy))
            .tracking(0.8)
            .foregroundStyle(наЦвете ? Color.white.opacity(0.85) : акцент)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func контакты(наЦвете: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !запись.телефон.isEmpty {
                Label(запись.телефон, systemImage: "phone")
            }
            let город = запись.город.trimmingCharacters(in: .whitespaces)
            if !город.isEmpty {
                Label(город, systemImage: "mappin.and.ellipse")
            }
        }
        .font(.system(size: 12, design: дизайн))
        .foregroundStyle(наЦвете ? Color.white.opacity(0.92) : Self.текстАбзаца)
    }

    @ViewBuilder
    private func навыки(наЦвете: Bool, заголовокРаздела: Bool) -> some View {
        let список = запись.навыки.filter { !$0.название.trimmingCharacters(in: .whitespaces).isEmpty }
        if !список.isEmpty {
            if заголовокРаздела {
                заголовокОсновы(т("doc_skills"))
            } else {
                заголовокПолосы(т("doc_skills"), наЦвете: наЦвете)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(список) { навык in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(навык.название)
                            .font(.system(size: 12, weight: .semibold, design: дизайн))
                        ПолосаНавыка(доля: Double(Int(навык.уровень) ?? 85) / 100,
                                     фон: наЦвете ? Color.white.opacity(0.18) : Color.black.opacity(0.12),
                                     цвет: наЦвете ? Color.white : акцент)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func языки(наЦвете: Bool, заголовокРаздела: Bool) -> some View {
        if !запись.языки.isEmpty {
            if заголовокРаздела {
                заголовокОсновы(т("doc_langs"))
            } else {
                заголовокПолосы(т("doc_langs"), наЦвете: наЦвете)
            }
            ForEach(Array(запись.языки.enumerated()), id: \.offset) { _, язык in
                HStack {
                    Text(язык.0)
                    Spacer(minLength: 4)
                    Text(язык.1).fontWeight(.bold)
                }
                .font(.system(size: 12, design: дизайн))
            }
        }
    }

    // MARK: Основное

    private var основное: some View {
        VStack(alignment: .leading, spacing: 0) {
            шапкаИмени(наЦвете: false)
            разделы
            подпись
        }
    }

    private func шапкаИмени(наЦвете: Bool) -> some View {
        let имя = запись.имя.trimmingCharacters(in: .whitespaces)
        let зарплата = Int(запись.зарплатаОт) ?? 0
        return VStack(alignment: .leading, spacing: 3) {
            Text(имя.isEmpty ? т("doc_seeker") : имя)
                .font(.system(size: 24, weight: .heavy, design: дизайн))
                .foregroundStyle(наЦвете ? Color.white : Self.чернила)
                .fixedSize(horizontal: false, vertical: true)
            if !запись.должность.isEmpty {
                Text(запись.должность)
                    .font(.system(size: 15, weight: .bold, design: дизайн))
                    .foregroundStyle(наЦвете ? Color.white.opacity(0.9) : акцент)
            }
            if зарплата > 0 {
                Text(т("doc_salary").replacingOccurrences(of: "{n}", with: СделкиФормат.деньги(зарплата)))
                    .font(.system(size: 12.5, weight: .heavy, design: дизайн))
                    .foregroundStyle(наЦвете ? Color.white : акцент)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(наЦвете ? Color.white.opacity(0.18) : акцент.opacity(0.12), in: Capsule())
                    .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private var разделы: some View {
        let оСебе = запись.оСебе.trimmingCharacters(in: .whitespacesAndNewlines)
        if !оСебе.isEmpty {
            заголовокОсновы(т("doc_about"))
            Text(оСебе)
                .font(.system(size: 13, design: дизайн))
                .lineSpacing(3)
                .foregroundStyle(Self.текстАбзаца)
                .fixedSize(horizontal: false, vertical: true)
        }
        let опыт = запись.опыт.filter { !$0.должность.isEmpty }
        if !опыт.isEmpty {
            заголовокОсновы(т("doc_exp"))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(опыт) { место in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(акцент)
                            .frame(width: 9, height: 9)
                            .overlay { Circle().stroke(акцент.opacity(0.15), lineWidth: 4) }
                            .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(место.должность)
                                .font(.system(size: 14, weight: .bold, design: дизайн))
                            if !место.компания.isEmpty {
                                Text(место.компания)
                                    .font(.system(size: 12.5, weight: .semibold, design: дизайн))
                                    .foregroundStyle(акцент)
                            }
                            if !место.период.isEmpty {
                                Text(место.период)
                                    .font(.system(size: 11.5, design: дизайн))
                                    .foregroundStyle(Self.серый)
                            }
                            if !место.описание.isEmpty {
                                Text(место.описание)
                                    .font(.system(size: 12.5, design: дизайн))
                                    .foregroundStyle(Self.текстАбзаца)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
        if !запись.образование.isEmpty {
            заголовокОсновы(т("doc_edu"))
            ForEach(Array(запись.образование.enumerated()), id: \.offset) { _, учёба in
                VStack(alignment: .leading, spacing: 2) {
                    Text(учёба.0)
                        .font(.system(size: 14, weight: .bold, design: дизайн))
                    Text(учёба.1)
                        .font(.system(size: 11.5, design: дизайн))
                        .foregroundStyle(Self.серый)
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func заголовокОсновы(_ текст: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(текст.uppercased())
                .font(.system(size: 12.5, weight: .heavy, design: дизайн))
                .tracking(0.6)
                .foregroundStyle(акцент)
            Rectangle()
                .fill(акцент.opacity(0.22))
                .frame(height: 2)
        }
        .padding(.top, 18)
        .padding(.bottom, 9)
    }

    private var подпись: some View {
        Text(т("doc_footer"))
            .font(.system(size: 10.5, design: дизайн))
            .foregroundStyle(Self.серый)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 18)
    }

    // MARK: Фото

    private func фото(ширина: CGFloat, рамка: Color) -> some View {
        let имя = запись.имя.trimmingCharacters(in: .whitespaces)
        let буква = имя.first.map { String($0).uppercased() } ?? "?"
        return ZStack {
            Color.black.opacity(0.06)
            if !запись.фото.isEmpty, let адрес = Config.url(запись.фото) {
                AsyncImage(url: адрес.absoluteURL) { фаза in
                    if let картинка = фаза.image {
                        картинка.resizable().scaledToFill()
                    } else {
                        Text(буква).font(.system(size: ширина * 0.45, weight: .heavy)).opacity(0.6)
                    }
                }
            } else {
                Text(буква).font(.system(size: ширина * 0.45, weight: .heavy)).opacity(0.6)
            }
        }
        .frame(width: ширина, height: ширина * 4 / 3)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(рамка, lineWidth: 3)
        }
        .accessibilityHidden(true)
    }
}

/// Полоса уровня навыка (.bar сайта).
private struct ПолосаНавыка: View {
    let доля: Double
    let фон: Color
    let цвет: Color

    var body: some View {
        GeometryReader { г in
            ZStack(alignment: .leading) {
                Capsule().fill(фон)
                Capsule().fill(цвет).frame(width: г.size.width * max(0.04, min(1, доля)))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// Окно предпросмотра (jrPreview): документ и «Другое оформление» по кругу.
struct ПредпросмотрРезюме: View {
    let запись: ЗаписьРаботы
    @Binding var шаблон: String

    @Environment(\.dismiss) private var закрыть

    var body: some View {
        NavigationStack {
            ScrollView {
                ДокументРезюме(запись: запись, шаблон: ШаблонРезюме.по(шаблон))
                    .shadow(color: Color.black.opacity(0.12), radius: 10, y: 4)
                    .padding(14)
                    .animation(.easeInOut(duration: 0.25), value: шаблон)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(ШаблонРезюме.по(шаблон).название)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(РезюмеText.т("close")) { закрыть() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(РезюмеText.т("doc_roll")) { следующий() }
                }
            }
        }
        .tint(Theme.акцент)
    }

    /// jrPreviewRoll.
    private func следующий() {
        let все = ШаблонРезюме.все
        let i = все.firstIndex(where: { $0.id == шаблон }) ?? 0
        шаблон = все[(i + 1) % все.count].id
    }
}

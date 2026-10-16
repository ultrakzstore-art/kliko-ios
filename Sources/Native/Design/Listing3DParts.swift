import SwiftUI

/**
 3D-ОБЗОР — ОБЩИЕ ЧАСТИ ЭКРАНОВ «3D» И «360°» (Listing3DViewer.swift, Listing3DSpin.swift): фон, загрузка с долей,
 ошибка с «Повторить» и подсказка жестов. Краски — токены Theme (тёмная тема сама), шрифты — текстовые стили (Dynamic
 Type), выравнивание — по началу строки (RTL).
 */

/// Фон окна просмотра — поверхность 2, тот же цвет, что у сцены RealityKit (ДвижокОбъёма3D.цветФона): шва нет.
struct ФонОбъёма: View {
    var body: some View {
        Theme.поверхность2
    }
}

/// Пока качается модель или ракурсы: постер блёкло на фоне, колесо, подпись, доля полосой и процентами (если известна).
struct ЗагрузкаОбъёма: View {
    let постер: URL?
    let доля: Double?
    let текст: String
    var подпись: String? = nil

    init(постер: URL?, доля: Double?, текст: String, подпись: String? = nil) {
        self.постер = постер
        self.доля = доля
        self.текст = текст
        self.подпись = подпись
    }

    var body: some View {
        ZStack {
            if let постер {
                /* КартинкаЛенты, а не AsyncImage: раскодирована вне главной нити, повторно — из памяти. */
                КартинкаЛенты(постер, пунктов: 320, заполнить: false) {
                    EmptyView()
                }
                .opacity(0.32)
                .padding(32)
                .accessibilityHidden(true)
            }
            VStack(spacing: 14) {
                SiteSpinner(размер: 28, толщина: 3)
                    .accessibilityHidden(true)
                Text(текст)
                    .font(.headline)
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                if let доля {
                    ProgressView(value: min(1, max(0, доля)))
                        .tint(Theme.акцент)
                        .frame(maxWidth: 220)
                        .accessibilityHidden(true)
                    Text(min(1, max(0, доля)), format: .percent.precision(.fractionLength(0)))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.текстВторой)
                }
                if let подпись {
                    Text(подпись)
                        .font(.footnote)
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            .padding(24)
            .background(Theme.поверхность.opacity(0.86), in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
            .padding(24)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// «Не удалось загрузить 3D» (или обзор), «Проверьте интернет…» и «Повторить».
struct ОшибкаОбъёма: View {
    let заголовок: String
    let повторить: () -> Void

    init(заголовок: String, повторить: @escaping () -> Void) {
        self.заголовок = заголовок
        self.повторить = повторить
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(Theme.оранжевый)
                .accessibilityHidden(true)
            Text(заголовок)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(ОбъёмText.т("o3_error_sub"))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: повторить) {
                Label(ОбъёмText.т("o3_retry"), systemImage: "arrow.clockwise")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 46)
                    .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: ДвижениеСайта.сжатие))
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Подсказка жестов — плашкой над низом экрана. VoiceOver её не читает: у сцены своя подсказка и действия.
struct ПодсказкаОбъёма: View {
    let значок: String
    let текст: String

    init(значок: String, текст: String) {
        self.значок = значок
        self.текст = текст
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: значок)
            Text(текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.текст)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

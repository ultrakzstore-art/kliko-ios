import SwiftUI

/**
 ПОДПИСИ КАДРОВ И «НАСТОЯЩИХ ФОТО НЕТ» В ОКНЕ ОБЪЯВЛЕНИЯ (ultra-site 14.10.2026: «Запись о фото и подпись «Фото
 обработано»» и «Картинка по описанию, часть 2: метки на витрине»).

 По записи photo_marks[i] открытого кадра (ОтметкаФотоОбъявления):
   · gen — «Иллюстрация создана ИИ — не фото товара», при gen.cover — «Обложка объявления — не фото товара»;
   · fx не пуст — «Фото обработано»; нажатие раскрывает, что именно (фон заменён, свет выровнен…).
 photos_real = 0 при непустых images — строка «Настоящих фото нет — это иллюстрация» и одна кнопка «Попросить настоящие
 фото»: чат с готовой фразой через панель окна (гостю — вход); у своего объявления кнопки нет.
 Старый ответ без полей — ни подписей, ни строки: окно как раньше.
 */
extension Listing {
    /// Запись о кадре номер, если о нём есть что сказать (рисунок ИИ или обработка); иначе nil.
    func отметкаКадра(_ номер: Int) -> ОтметкаФотоОбъявления? {
        guard отметкиФото.indices.contains(номер) else { return nil }
        let отметка = отметкиФото[номер]
        return отметка.рисунокИИ || !отметка.обработка.isEmpty ? отметка : nil
    }

    /// photos_real = 0 при непустых кадрах: все фото — иллюстрации.
    var безНастоящихФото: Bool { настоящихКадров == 0 && !фото.isEmpty }
}

/// Подпись на кадре галереи: тёмное стекло, как кнопки над фото, белый текст; меняется вместе с кадром.
struct ПодписьКадраОбъявления: View {
    let отметка: ОтметкаФотоОбъявления
    @State private var раскрыто = false

    init(отметка: ОтметкаФотоОбъявления) {
        self.отметка = отметка
    }

    private var рисунок: Bool { отметка.рисунокИИ }

    private var заголовок: String {
        if рисунок { return ТекстыДействийОкна.т(отметка.обложка ? "pm_cover" : "pm_gen") }
        return ТекстыДействийОкна.т("pm_fx")
    }

    /// «фон заменён, общий свет выровнен» — виды обработки словами сайта (pfx_*).
    private var виды: String {
        отметка.обработка.map { ТекстыДействийОкна.т("pm_fx_" + $0) }.joined(separator: ", ")
    }

    var body: some View {
        Button {
            guard !рисунок, !виды.isEmpty else { return }
            withAnimation(ДвижениеСайта.смена) { раскрыто.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: рисунок ? "wand.and.stars" : "slider.horizontal.3")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 11, weight: .bold))
                        .lineLimit(2)
                    if раскрыто && !виды.isEmpty {
                        Text(виды)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(3)
                            .transition(.opacity)
                    }
                }
                .multilineTextAlignment(.leading)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .стеклоНадФото()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(виды.isEmpty ? заголовок : заголовок + ": " + виды)
        .onChange(of: отметка) { _, _ in раскрыто = false }
    }
}

/// «Настоящих фото нет — это иллюстрация» и «Попросить настоящие фото» (не у своего объявления).
struct БлокНастоящихФото: View {
    let товар: Listing
    @ObservedObject private var сессия = СессияПриложения.shared

    init(товар: Listing) {
        self.товар = товар
    }

    private var своё: Bool { !сессия.id.isEmpty && сессия.id == товар.продавецID }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.оранжевый)
                    .accessibilityHidden(true)
                Text(ТекстыДействийОкна.т("pm_noreal"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if !своё && товар.продавецID != nil {
                Button {
                    ВестиОкнаОбъявления.послать(ВестиОкнаОбъявления.чат, товар: товар.id,
                                                 текст: ТекстыДействийОкна.т("pm_ask_text"))
                } label: {
                    Label(ТекстыДействийОкна.т("pm_ask_real"), systemImage: "camera")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Theme.зелёный2)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                                .strokeBorder(Theme.линия, lineWidth: 1)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(НажатиеСПружинкой(сжатие: 0.97))
            }
        }
        .padding(14)
        .background(Theme.оранжевый.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.оранжевый.opacity(0.25), lineWidth: 1)
        }
    }
}

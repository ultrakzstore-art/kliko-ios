import SwiftUI

/**
 «ПРИМЕРИТЬ НА СЕБЯ» — КНОПКА НА СТРАНИЦЕ ОБЪЯВЛЕНИЯ ОДЕЖДЫ И ОКНО ПРИМЕРОЧНОЙ (владелец 13.10.2026).

 Кнопка стоит под ценой и крошками (СтраницаОбъявленияСайта, SiteListing.swift), во всю ширину: зелёная, как панель
 связи сайта, с футболкой, подписью «ИИ покажет вещь на вашем фото» и бегущим бликом (при «Уменьшении движения» — без
 него). Её нет, пока: рубильник Config.примерочная выключен; у объявления нет фото или раздел не одежда; сервер не
 ответил info как надо (ГотовностьПримерочной). Нажатие — окно примерочной поверх всего (ПоверхВсего).
 */
struct КнопкаПримерочной: View {
    let товар: Listing
    /// Фото галереи на экране — его и примеряем (photo_index); другое можно выбрать в окне.
    let номерФото: Int
    @ObservedObject private var готовность = ГотовностьПримерочной.shared
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    @State private var блик = false

    init(товар: Listing, номерФото: Int) {
        self.товар = товар
        self.номерФото = номерФото
    }

    /// Ставить ли кнопку на страницу вообще — без сети: рубильник, фото, раздел одежды (по sections сервера, если они
    /// уже известны, иначе по списку приложения). Сервер спрашивает уже сама кнопка.
    @MainActor
    static func есть(_ т: Listing) -> Bool {
        guard Config.примерочная, !ГотовностьПримерочной.shared.нетСервера, !т.фотоАдреса.isEmpty else { return false }
        let свои = ГотовностьПримерочной.shared.сведения?.разделы ?? []
        return РазделыПримерочной.подходит(т.категория, свои: свои)
    }

    private func т(_ ключ: String) -> String { ПримерочнаяText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    var body: some View {
        VStack(spacing: 0) {
            /* Полоса нулевой высоты: на ней живёт .task, пока кнопки ещё нет (пустой вид задач не запускает). */
            Color.clear
                .frame(height: 0)
                .accessibilityHidden(true)
            if готовность.можно(товар) {
                кнопка
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .transition(.opacity)
            }
        }
        .animation(ДвижениеСайта.появление, value: готовность.можно(товар))
        .task { await готовность.проверить() }
    }

    private var кнопка: some View {
        Button {
            ОткликСайта.выбор()
            ОкноПримерочной.открыть(товар: товар, номерФото: номерФото)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tshirt.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.16), in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1) }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(т("to_btn"))
                        .font(.system(size: 16, weight: .heavy))
                    Text(т("to_btn_sub"))
                        .font(.system(size: 13))
                        .opacity(0.86)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.шапкаМята)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                LinearGradient(colors: [Theme.панельСвязиНачало, Theme.панельСвязиКонец],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .overlay { блеск }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .shadow(color: Theme.панельСвязиКонец.opacity(0.28), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: ДвижениеСайта.сжатие))
        .accessibilityLabel(т("to_btn"))
        .accessibilityHint(т("to_btn_hint"))
        .onAppear {
            guard !тихо, !блик else { return }
            withAnimation(.easeInOut(duration: 1.8).delay(0.8).repeatForever(autoreverses: false)) { блик = true }
        }
    }

    /// Косая светлая полоса пробегает по кнопке слева направо — намёк, что здесь «волшебство».
    @ViewBuilder
    private var блеск: some View {
        if !тихо {
            GeometryReader { место in
                LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.26), Color.white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: место.size.width * 0.34, height: место.size.height * 2)
                    .rotationEffect(.degrees(16))
                    .offset(x: блик ? место.size.width * 1.15 : -место.size.width * 0.5, y: -место.size.height * 0.5)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Окно

@MainActor
enum ОкноПримерочной {
    /// Окно примерочной во всю высоту поверх того, что на экране (страница объявления, лист продавца, iPad справа).
    static func открыть(товар: Listing, номерФото: Int) {
        guard Config.примерочная else { return }
        ПоверхВсего.показать(большой: true) { закрыть in
            ЭкранПримерочной(товар: товар, номерФото: номерФото, закрыть: закрыть)
        }
    }
}

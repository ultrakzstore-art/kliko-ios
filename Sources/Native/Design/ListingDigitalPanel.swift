import SwiftUI
import UIKit

/**
 ОКНО ЦИФРОВОГО ОБЪЯВЛЕНИЯ — НИЖНЯЯ ПАНЕЛЬ (ultra-site 16.10.2026, задание «Цифровые товары», Ц2).

 Цифровое объявление может открыться и при выключенном показе: ссылкой, пушем, из избранного, из «Моих объявлений»
 продавца. Тогда вместо панели связи (ПанельСвязиСайта: «Купить», «Торг», предложение цены, «Связаться») — эта: что за
 код (вид, платформа, регион активации, номинал), «Цифровых продаж: N, споров: M» продавца и строка «Эта возможность
 недоступна в приложении» — тот же текст, что у прочих цифровых функций (БизнесText «no_digital»). Ни кнопок, ни ссылок,
 ни слов о сайте (Apple 3.1.1). Чат («Связаться») скрыт вместе с покупкой — по умолчанию задания, чтобы он не стал
 обходом.

 Части страницы, которые зовут панель (вопрос продавцу из «Разбора», «Попросить настоящие фото», «Арендовать»,
 «Оформить» из чата), ответа панели связи не получат — её нет. Эта панель ловит те же вести и отвечает отказом: вибро и
 та же строка голосом VoiceOver, строка на экране чуть вздрагивает. Не тишина и не чат.
 */
struct ПанельЦифровогоОбъявления: View {
    let товар: Listing
    /// Отступ под домашней полосой — как у ПанельСвязиСайта: окно само прижимает панель к низу экрана.
    let низ: CGFloat
    /// Нажали то, чего здесь нет, — строка «недоступна» вздрагивает.
    @State private var толчок = false

    init(товар: Listing, низ: CGFloat = 0) {
        self.товар = товар
        self.низ = низ
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !сведения.isEmpty {
                Text(сведения)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let продавец = товар.цифровоеПродавца {
                Text(String(format: ЦифровоеText.т("seller_stats"), продавец.продажи, продавец.споры))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ЗаметкаБизнеса(БизнесText.т("no_digital"), тон: .серый, значок: "lock")
                .scaleEffect(толчок ? 1.03 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        /* Отступы и подложка — как у ПанельСвязиСайта (.mk-mstickybar): 18 по краям, 12 сверху и снизу и «домой». */
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 12 + низ)
        .background(alignment: .top) { ПодложкаЦифровойПанели() }
        .onReceive(NotificationCenter.default.publisher(for: ВестиОкнаОбъявления.чат)) { весть in отказать(весть) }
        .onReceive(NotificationCenter.default.publisher(for: ВестиОкнаОбъявления.главное)) { весть in отказать(весть) }
        .onReceive(NotificationCenter.default.publisher(for: ВестиОкнаОбъявления.связаться)) { весть in отказать(весть) }
        .onReceive(NotificationCenter.default.publisher(for: ВестиОкнаОбъявления.аренда)) { весть in отказать(весть) }
        .onReceive(NotificationCenter.default.publisher(for: ВестиОкнаОбъявления.купить)) { весть in отказать(весть) }
    }

    /// «Игровой ключ · Платформа: Steam · Регион активации: Казахстан · Номинал: 5 000»; описания нет — пусто.
    private var сведения: String {
        guard let описание = товар.цифровоеОписание else { return "" }
        var части: [String] = []
        let видКода = ЦифровоеText.вид(описание.вид)
        if !видКода.isEmpty { части.append(видКода) }
        let площадка = описание.названиеПлатформы.isEmpty ? описание.платформа : описание.названиеПлатформы
        if !площадка.isEmpty { части.append(ЦифровоеText.т("platform") + ": " + площадка) }
        if !описание.регион.isEmpty {
            части.append(ЦифровоеText.т("region") + ": " + ЦифровоеText.регион(описание.регион))
        }
        if !описание.номинал.isEmpty { части.append(ЦифровоеText.т("nominal") + ": " + номиналСловами(описание.номинал)) }
        return части.joined(separator: " · ")
    }

    /// Номинал целым числом — с пробелами тысяч (5 000); с валютой или дробью — как пришёл: валюту сервер знает сам.
    private func номиналСловами(_ номинал: String) -> String {
        guard let n = Int(номинал), n >= 0 else { return номинал }
        return DesignText.число(n)
    }

    /// Весть части страницы этому объявлению — отказ вместо действия.
    private func отказать(_ весть: Notification) {
        guard (весть.object as? String) == товар.id else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        UIAccessibility.post(notification: .announcement, argument: БизнесText.т("no_digital"))
        withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { толчок = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { толчок = false }
        }
    }
}

/// Подложка панели — как у панели связи: сплошная поверхность и 24 pt мягкого перехода над ней.
private struct ПодложкаЦифровойПанели: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Theme.поверхность.opacity(0), Theme.поверхность], startPoint: .top, endPoint: .bottom)
                .frame(height: 24)
            Theme.поверхность
        }
        .padding(.top, -24)
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

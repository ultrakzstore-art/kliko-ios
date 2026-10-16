import SwiftUI

/**
 МЕСТО ПОД НОВОЕ ОБЪЯВЛЕНИЕ — СРАЗУ ПРИ ОТКРЫТИИ МАСТЕРА (владелец 16.10.2026: «Лимиты если достигнуты — в окне
 предлагать расширить сразу»; затем «по всем моментам разом»).

 Раньше человек узнавал о полных слотах только после съёмки (recognize: slots_full) или вовсе после всей формы (submit:
 slots_full, либо held — объявление тихо ложилось в «Неактивные»). Теперь мастер новой подачи спрашивает my_items сам,
 как только ушёл с «Загрузки», и при полных слотах сразу показывает окно в стиле окна итога подачи:
   · «Расширить лимит» — главная, покупка App Store (РасширениеЛимита.слоты: тариф слотов, комбо, PRO); товар ещё
     грузится — та же кнопка с колесом; после «Готово» место проверяется заново, и окно уходит само;
   · «Подтвердить личность через eGov (+5)» — если человек не верифицирован;
   · «Освободить место» — черновик сохраняется, мастер закрывается в «Опубликованные»;
   · «Заполнить — опубликую позже» — окно больше не показывается; на отправке сработает обычный вопрос о месте.
 Правка и пустые слоты — окна нет. Сеть не ответила — тоже нет: мешать подаче из-за сбоя незачем.
 */
@MainActor
final class МестоПодачи: ObservableObject {
    @Published private(set) var занято = 0
    @Published private(set) var лимит = 0
    @Published private(set) var полно = false
    /// «Заполнить — опубликую позже»: в этом мастере окно больше не показывать.
    @Published var скрыто = false

    private var идёт = false
    private var проверено = false

    /**
     slots из my_items (тот же запрос, что у «Моих объявлений» и платных услуг; отдельного API у сайта нет). Заодно —
     товары App Store настоящих тарифов слотов сервера. заново = false — только первый раз за мастер.
     */
    func проверить(заново: Bool = false) async {
        guard !идёт, заново || !проверено else { return }
        идёт = true
        defer { идёт = false }
        guard let j = try? await МоиОбъявленияAPI.получить("cabinet.php?action=my_items"),
              МоиОбъявленияAPI.да(j["ok"]) else { return }
        проверено = true
        let сырые = j["slots"] as? [String: Any]
        РасширениеЛимита.подгрузитьТарифыСлотов(сырые)
        guard let слоты = СлотыОбъявлений(сырые), слоты.лимит > 0 else {
            полно = false
            return
        }
        занято = слоты.занято
        лимит = слоты.лимит
        полно = слоты.занято >= слоты.лимит
    }

    /**
     «Подать ещё»: новое объявление — место спросить заново, и окно снова можно показать. Сначала ответ, потом окно:
     прежнее «полно» не мелькает, пока my_items в пути.
     */
    func заново() {
        Task { @MainActor in
            await проверить(заново: true)
            скрыто = false
        }
    }
}

/**
 Номер объявления, которое submit сохранил, но удержал сверх лимита (held), — для «Расширить лимит» в окне итога:
 после покупки оно активируется само. ИтогПодачи.неактивные номера пока не несёт (PostingModel.swift); когда понесёт —
 это место не нужно.
 */
@MainActor
enum ПослеПокупкиПодачи {
    static var удержанное: String? = nil
}

/**
 Мастер подачи и место: пора — мастер новой подачи ушёл с «Загрузки» (спросить my_items один раз); можно — на экране
 нет другого вопроса («Продолжить черновик?»), итога, распознавания и листов. Значения, а не модель: модификатор
 пересчитывается вместе с экраном. После покупки, поднявшей слоты (в том числе позднее одобрение), и после eGov место
 проверяется заново — окно уходит само.
 */
struct МестоПодачиНаЭкране: ViewModifier {
    @ObservedObject var место: МестоПодачи
    let пора: Bool
    let можно: Bool
    let верифицирован: Bool
    let верификация: () -> Void
    let освободить: () -> Void

    private var видно: Bool { пора && можно && место.полно && !место.скрыто }

    func body(content: Content) -> some View {
        content
            .task(id: пора) {
                if пора { await место.проверить() }
            }
            /* Итог ушёл — не повод спрашивать заново: «Позже», «Освободить место» и «Расширить» закрывают мастер, и окно
               всплыло бы поверх уезжающего мастера. Новое объявление («Подать ещё») зовёт место.заново() само. */
            .overlay {
                ZStack {
                    if видно {
                        ОкноМестаПодачи(занято: место.занято, лимит: место.лимит, верифицирован: верифицирован,
                                        расширить: { вид in
                                            ЛистУслугиApple.показать(вид, готово: {
                                                Task { @MainActor in await место.проверить(заново: true) }
                                            })
                                        },
                                        верификация: верификация, освободить: освободить,
                                        позже: { место.скрыто = true })
                        .transition(.opacity)
                    }
                }
                .animation(ДвижениеСайта.появление, value: видно)
            }
            .onReceive(NotificationCenter.default.publisher(for: .klikoУслугаAppleВключена)) { уведомление in
                guard пора, РасширениеЛимита.подняло(уведомление, РасширениеЛимита.слоты) else { return }
                Task { @MainActor in await место.проверить(заново: true) }
            }
            .onReceive(NotificationCenter.default.publisher(for: ОкноEgov.завершено)) { _ in
                guard пора else { return }
                Task { @MainActor in await место.проверить(заново: true) }
            }
    }
}

/// Окно «Нет места для нового объявления» на первом экране мастера — в стиле окна итога подачи (ОкноИтогаПодачи).
struct ОкноМестаПодачи: View {
    let занято: Int
    let лимит: Int
    /// Верифицирован (IS_VERIFIED): нет — «Подтвердить личность через eGov (+5)».
    let верифицирован: Bool
    let расширить: (ВидУслугиApple) -> Void
    let верификация: () -> Void
    let освободить: () -> Void
    let позже: () -> Void
    /// Товары App Store: пришли — «Расширить лимит» встаёт сама.
    @ObservedObject private var покупки = ПокупкиApple.shared
    @State private var видно = false

    init(занято: Int, лимит: Int, верифицирован: Bool, расширить: @escaping (ВидУслугиApple) -> Void,
         верификация: @escaping () -> Void, освободить: @escaping () -> Void, позже: @escaping () -> Void) {
        self.занято = занято
        self.лимит = лимит
        self.верифицирован = верифицирован
        self.расширить = расширить
        self.верификация = верификация
        self.освободить = освободить
        self.позже = позже
    }

    private func т(_ ключ: String) -> String { ПодачаText.т(ключ) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            ViewThatFits(in: .vertical) {
                карточка
                ScrollView {
                    карточка
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .padding(20)
        }
        .task { await ПокупкиApple.shared.подгрузить() }
    }

    private var карточка: some View {
        VStack(spacing: 0) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(КраскаПодачи.вниманиеТекст)
                .symbolEffect(.bounce, value: ДвижениеСайта.тихо ? false : видно)
                .padding(.bottom, 12)
                .accessibilityHidden(true)
            Text(т("limit_t"))
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(КраскаПодачи.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            счёт
            Text(ЛимитText.т(РасширениеЛимита.есть(РасширениеЛимита.слоты) ? "lu_gate_d" : "lu_gate_d_free"))
                .font(.system(size: 14))
                .lineSpacing(5)
                .foregroundStyle(КраскаПодачи.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .padding(.top, 12)
            VStack(spacing: 10) {
                кнопки
            }
            .padding(.top, 20)
        }
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .frame(maxWidth: 400)
        .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .shadow(color: Color.black.opacity(0.3), radius: 30, y: 20)
        .scaleEffect(видно ? 1 : 0.94)
        .opacity(видно ? 1 : 0)
        .onAppear {
            withAnimation(ДвижениеСайта.мягко(.spring(response: 0.38, dampingFraction: 0.8))) { видно = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// «Занято 25 из 25» — полоса заполнена до конца.
    private var счёт: some View {
        VStack(spacing: 6) {
            Text(ЛимитText.т("lu_used", ["n": String(занято), "m": String(лимит)]))
                .font(.system(size: 13, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(КраскаПодачи.вниманиеТекст)
            Capsule()
                .fill(КраскаПодачи.вниманиеТекст)
                .frame(height: 5)
                .frame(maxWidth: 160)
                .accessibilityHidden(true)
        }
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }

    /**
     Купить есть что (товар цепочки загружен или грузится) — «Расширить лимит» главной, остальное вторым. Нет — без
     пустого места в стопке: главной верификация (+5) или «Освободить место», как у окна итога «удержано»; товар придёт
     (.task окна спрашивает App Store) — кнопка встанет сама.
     */
    @ViewBuilder
    private var кнопки: some View {
        if РасширениеЛимита.есть(РасширениеЛимита.слоты) {
            КнопкаРасширения(цепочка: РасширениеЛимита.слоты, действие: расширить) { занятоКнопка, нажать in
                КнопкаПодачи(т("limit_more"), занято: занятоКнопка, действие: нажать)
            }
            if !верифицирован {
                КнопкаПодачиВторая(т("verify_plus5"), действие: верификация)
            }
            КнопкаПодачиВторая(т("free_place"), действие: освободить)
        } else if !верифицирован {
            КнопкаПодачи(т("verify_plus5"), действие: верификация)
            КнопкаПодачиВторая(т("free_place"), действие: освободить)
        } else {
            КнопкаПодачи(т("free_place"), действие: освободить)
        }
        Button(action: позже) {
            Text(ЛимитText.т("lu_anyway"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI
import UIKit

/**
 «ЧТО НОВОГО» — ЭТАП 16 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «давай следующие этапы»).

 Первый запуск новой версии (CFBundleShortVersionString) — лист над нативным слоем: что приложение теперь умеет само
 (лента, карточка, чат, избранное, сохранённые поиски, iPad, поиск iPhone, тёмная тема…), значками SF Symbols, и кнопка
 «Понятно». Пункты — только включённые рубильниками Config: показать выключенное значит пообещать то, чего нет.

 КОГДА. Только над нативным слоем (WebBridge.лентаВидна) и не под замком Face ID (AppLock): лист — отдельный контроллер
 поверх окна, и над замком он лёг бы выше LockView. Слой ушёл под страницу сайта или телефон заперт — ждём; в этом
 запуске так и не дождались — покажем в следующем. Виденной версия считается, когда лист появился на экране, а не когда
 его закрыли: второй раз одно и то же не показываем, как бы его ни убрали.

 🔴 НЕ НА ПЕРВОЙ УСТАНОВКЕ. Новому человеку всё и так новое, и первым кадром ему нужна лента, а не список. Поэтому нет
 записанной версии — записываем текущую и молчим. Версии до этапа 16 версию не записывали, так что и обновление на
 сборку с этапом 16 выглядит как первая установка: лист впервые покажется при следующем обновлении. Тот же список всегда
 открывается строкой «Что нового» в кабинете (CabinetView).

 Хранится в UserDefaults (ключ kliko.whatsnew.version) — это о телефоне, а не о человеке: при выходе (bye=1) не стирается.
 */
@MainActor
final class ЧтоНового: ObservableObject {
    static let shared = ЧтоНового()

    private static let ключ = "kliko.whatsnew.version"

    /// Этот запуск — первый в новой версии, и лист ещё не показан.
    @Published private(set) var ждёт: Bool

    private init() {
        let хранилище = UserDefaults.standard
        let текущая = ВерсияПриложения.текущая
        let виденная = хранилище.string(forKey: Self.ключ)
        if виденная == nil { хранилище.set(текущая, forKey: Self.ключ) }     // первая установка — не показываем
        ждёт = виденная != nil && виденная != текущая
    }

    /// Запуск (SceneDelegate): сверить версию сразу, даже если листа не будет (рубильник, веб-обёртка без нативного
    /// слоя), — иначе установка, на которой листа не было, позже сошла бы за первую и промолчала о следующем обновлении.
    static func отметитьЗапуск() {
        _ = shared
    }

    /// Лист на экране (ЭкранЧтоНового) — версия виденная.
    func показали() {
        ждёт = false
        UserDefaults.standard.set(ВерсияПриложения.текущая, forKey: Self.ключ)
    }
}

/// Версия приложения, как её видит человек в App Store.
enum ВерсияПриложения {
    /// CFBundleShortVersionString — туда её подставляет сборка (MARKETING_VERSION из тега, project.yml).
    static var текущая: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }
}

/// Пункт списка: ключ текста (WhatsNewText, подпись — ключ + "_sub") и значок SF Symbols.
struct ПунктНового: Identifiable {
    let id: String
    let значок: String

    /// Что умеет приложение с включёнными рубильниками. Лист виден только над нативным слоем, поэтому лента — всегда.
    /// @MainActor — из-за UIDevice: две колонки обещаем только на iPad.
    @MainActor
    static var список: [ПунктНового] {
        var пункты = [ПунктНового(id: "feed", значок: "square.grid.2x2")]
        if Config.нативнаяКарточка { пункты.append(ПунктНового(id: "card", значок: "photo.on.rectangle")) }
        if Config.нативныйЧат && Config.нижниеВкладки {
            пункты.append(ПунктНового(id: "chat", значок: "bubble.left.and.bubble.right"))
        }
        if Config.избранное { пункты.append(ПунктНового(id: "favorites", значок: "heart")) }
        if Config.недавние { пункты.append(ПунктНового(id: "recent", значок: "clock.arrow.circlepath")) }
        if Config.сохранённыеПоиски { пункты.append(ПунктНового(id: "saved", значок: "bell.badge")) }
        if Config.карточкиБезСети && Config.нативнаяКарточка {
            пункты.append(ПунктНового(id: "offline", значок: "wifi.slash"))
        }
        if Config.айпадДвеКолонки && Config.нативнаяКарточка && UIDevice.current.userInterfaceIdiom == .pad {
            пункты.append(ПунктНового(id: "ipad", значок: "rectangle.split.2x1"))
        }
        if Config.spotlight && Config.быстрыеДействия && Config.нижниеВкладки {
            пункты.append(ПунктНового(id: "system", значок: "magnifyingglass"))
        }
        if ТемаОформления.доступен { пункты.append(ПунктНового(id: "theme", значок: "circle.lefthalf.filled")) }
        if Config.нижниеВкладки && Config.нативныйКабинет {
            пункты.append(ПунктНового(id: "cabinet", значок: "person.crop.circle"))
        }
        return пункты
    }
}

/// Лист «Что нового»: заголовок, пункты со значками и «Понятно». Смахнуть вниз тоже можно — это то же «Понятно».
struct ЭкранЧтоНового: View {
    @Environment(\.dismiss) private var закрыть

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    шапка
                    ForEach(ПунктНового.список) { пункт in
                        СтрокаНового(пункт: пункт)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 40)
                .padding(.bottom, 20)
                .frame(maxWidth: 560)                   // на iPad строки не растягиваются во всю ширину листа
                .frame(maxWidth: .infinity)
            }
            Button {
                закрыть()
            } label: {
                Text(WhatsNewText.т("ok"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .foregroundStyle(.white)
                    .background(Theme.green2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: 504)
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
        /* Виденной версия считается здесь — и когда лист открыли строкой в кабинете: второй раз тот же список сам не
           всплывёт. */
        .onAppear { ЧтоНового.shared.показали() }
    }

    private var шапка: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Theme.green2)
                .accessibilityHidden(true)
            Text(WhatsNewText.т("title"))
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(String(format: WhatsNewText.т("version"), ВерсияПриложения.текущая))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(WhatsNewText.т("subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
    }
}

/// Строка списка: значок слева, название и подпись. VoiceOver читает её одной фразой.
private struct СтрокаНового: View {
    let пункт: ПунктНового

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: пункт.значок)
                .font(.title2)
                .foregroundStyle(Theme.green2)
                .frame(width: 36)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(WhatsNewText.т(пункт.id))
                    .font(.headline)
                Text(WhatsNewText.т(пункт.id + "_sub"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/**
 Лист «Что нового» над нативным слоем (RootWebView → .чтоНовогоИОценка()).

 Условия сошлись (новая версия, слой на экране, замка нет) — пауза, чтобы слой успел проявиться, а окно Face ID —
 уйти, и ещё раз проверка: приложение активно и поверх окна ничего нет. Лист, который SwiftUI не смог показать поверх
 чужого, так и висел бы «показанным» в состоянии, а на экран не вышел бы.
 */
struct СлойЧтоНового<Содержимое: View>: View {
    let содержимое: Содержимое
    @ObservedObject private var новое = ЧтоНового.shared
    @ObservedObject private var мост = WebBridge.shared
    @ObservedObject private var замок = AppLock.shared
    @State private var показать = false

    init(_ содержимое: Содержимое) {
        self.содержимое = содержимое
    }

    var body: some View {
        содержимое
            .task(id: можноПоказать) { await показатьПозже() }
            .sheet(isPresented: $показать) {
                ЭкранЧтоНового()
            }
    }

    private var можноПоказать: Bool {
        Config.чтоНового && новое.ждёт && мост.лентаВидна && !(замок.enabled && (замок.locked || замок.cover))
    }

    private func показатьПозже() async {
        guard можноПоказать, !показать else { return }
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard !Task.isCancelled, можноПоказать, !показать,
              UIApplication.shared.applicationState == .active, !ПоверхОкна.занято else { return }
        показать = true
    }
}

extension View {
    /// Этап 16: «Что нового» листом над нативным слоем и просьба оценить после удачных моментов в нём (RootWebView).
    @MainActor
    func чтоНовогоИОценка() -> some View {
        ОценкаВСлое(СлойЧтоНового(self))
    }
}

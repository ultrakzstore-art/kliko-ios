import SwiftUI
import UIKit
import ARKit

/**
 3D-ОБЗОР — ВХОД СО СТРАНИЦЫ ОБЪЯВЛЕНИЯ И ОКНО ПРОСМОТРА (владелец 14.10.2026: «3D-обзор надо сделать за счёт ИИ»).

 Страница объявления (СтраницаОбъявленияСайта, SiteListing.swift) ставит две вещи, если у объявления есть model3d
 (Listing.естьОбъём, Listing3DModel.swift):
   · ЗначокОбъёмаГалереи — в нижнем углу фото: «3D» (есть usdz) или «360°» (есть только ракурсы), стекло кнопок над
     фото; нажатие — окно просмотра;
   · КнопкаОбъёмаОбъявления — под ценой и крошками, перед примерочной: «Смотреть в 3D» / «Обзор 360°» с подписью.
     С 17.10.2026 вместо неё — капсула «3D» / «360°» рядом с «На столе» одной строкой (СтрокаСмотретьВещь,
     SiteListingLook.swift); карточка осталась на выключенный рубильник Config.строкаСмотретьВещь.
 Все зовут ОкноОбъёма.открыть(товар:) — окно во весь экран поверх того, что на экране (не лист: смахивание листа
 спорило бы с пальцем, которым вращают модель). В окне — ЭкранОбъёмаОбъявления: сверху название и ✕, при модели и
 ракурсах сразу — переключатель «3D | 360°», в середине — ПросмотрМодели3D (Listing3DViewer.swift) или ПросмотрОбзора360
 (Listing3DSpin.swift), внизу — честная подпись «3D-модель создана ИИ по фото — детали могут отличаться» и размеры.

 Ни цен, ни покупок здесь нет. Тёмная тема, Dynamic Type, VoiceOver, RTL — у каждой части; лёгкий режим — у сцен.
 */
enum РежимПросмотраОбъёма: Hashable {
    /// «3D»: модель USDZ.
    case модель
    /// «360°»: ракурсы.
    case обзор
}

@MainActor
enum ОкноОбъёма {
    private static var последнееОткрытие: Date? = nil

    /// Есть ли AR с поиском плоскостей — для «В комнате» (AR Quick Look). В симуляторе — нет.
    static var комнатаДоступна: Bool { поддержкаAR }

    private static let поддержкаAR: Bool = {
        #if targetEnvironment(simulator)
        return false
        #else
        return ARWorldTrackingConfiguration.isSupported
        #endif
    }()

    /// Открыть просмотр во весь экран. режим nil — «3D», если есть модель, иначе «360°». Нечего показывать — ничего.
    /// Защита от двойного нажатия: второе окно за секунду не кладём поверх первого.
    static func открыть(товар: Listing, режим: РежимПросмотраОбъёма? = nil) {
        guard Config.объёмОбъявления, let модель = товар.модельОбъёма, модель.естьЧтоПоказать else { return }
        let поУмолчанию: РежимПросмотраОбъёма = модель.есть3D ? .модель : .обзор
        var начальный = режим ?? поУмолчанию
        if начальный == .модель && !модель.есть3D { начальный = .обзор }
        if начальный == .обзор && !модель.есть360 { начальный = .модель }
        let сейчас = Date()
        if let прежнее = последнееОткрытие, сейчас.timeIntervalSince(прежнее) < 1 { return }
        последнееОткрытие = сейчас
        let название = товар.title
        let страница = товар.адрес
        let выбранный = начальный
        Task { @MainActor in
            for попытка in 0..<12 {
                if let верх = ПоверхВсего.верхний() {
                    let хост = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
                    let закрыть: () -> Void = { [weak хост] in
                        хост?.dismiss(animated: true)
                    }
                    let тёмная = верх.traitCollection.userInterfaceStyle == .dark
                    хост.rootView = AnyView(ЭкранОбъёмаОбъявления(название: название, страница: страница, модель: модель,
                                                                 режим: выбранный, тёмная: тёмная, закрыть: закрыть))
                    хост.modalPresentationStyle = .fullScreen
                    верх.present(хост, animated: true)
                    return
                }
                try? await Task.sleep(nanoseconds: попытка == 0 ? 120_000_000 : 250_000_000)
            }
        }
    }

    /// «В комнате»: AR Quick Look поверх окна просмотра. Нет AR (симулятор, старое устройство) — ничего.
    static func вКомнате(файл: URL, модель: МодельОбъёмаОбъявления, страница: URL?) {
        #if !targetEnvironment(simulator)
        guard комнатаДоступна, let верх = ПоверхВсего.верхний() else { return }
        КомнатаОбъёма.показать(файл: файл, размерыИзвестны: модель.размерыИзвестны, страница: страница, поверх: верх)
        #endif
    }
}

// MARK: - Окно просмотра

struct ЭкранОбъёмаОбъявления: View {
    let название: String
    let страница: URL?
    let модель: МодельОбъёмаОбъявления
    let закрыть: () -> Void
    @State private var режим: РежимПросмотраОбъёма
    /// Движок «3D» живёт с окном: «3D» → «360°» → «3D» не грузит модель заново.
    @StateObject private var движок: ДвижокОбъёма3D
    @ObservedObject private var устройство = РежимУстройства.shared
    @ScaledMetric(relativeTo: .body) private var кнопка: CGFloat = 44

    init(название: String, страница: URL?, модель: МодельОбъёмаОбъявления, режим: РежимПросмотраОбъёма, тёмная: Bool,
         закрыть: @escaping () -> Void) {
        self.название = название
        self.страница = страница
        self.модель = модель
        self.закрыть = закрыть
        _режим = State(initialValue: режим)
        _движок = StateObject(wrappedValue: ДвижокОбъёма3D(модель: модель, лёгкий: РежимУстройства.сейчас, тёмная: тёмная))
    }

    private func т(_ ключ: String) -> String { ОбъёмText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            шапка
            содержимое
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            подвал
        }
        .background(ФонОбъёма().ignoresSafeArea())
    }

    @ViewBuilder
    private var содержимое: some View {
        switch режим {
        case .модель:
            ПросмотрМодели3D(модель: модель, страница: страница, движок: движок)
        case .обзор:
            ПросмотрОбзора360(модель: модель, лёгкий: устройство.лёгкий)
        }
    }

    // MARK: Шапка

    private var шапка: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(т(режим == .модель ? "o3_title_3d" : "o3_title_360"))
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Theme.текст)
                        .accessibilityAddTraits(.isHeader)
                    if !название.isEmpty {
                        Text(название)
                            .font(.subheadline)
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    движок.разобрать()
                    закрыть()
                } label: {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.текст)
                        .frame(width: кнопка, height: кнопка)
                        .background(Theme.поверхность, in: Circle())
                        .overlay { Circle().strokeBorder(Theme.линия, lineWidth: 1) }
                        .contentShape(Circle())
                }
                .buttonStyle(НажатиеСПружинкой(сжатие: 0.9))
                .accessibilityLabel(т("o3_close"))
            }
            if модель.есть3D && модель.есть360 {
                Picker(т("o3_mode_a11y"), selection: $режим) {
                    Text(т("o3_mode_3d")).tag(РежимПросмотраОбъёма.модель)
                    Text(т("o3_mode_360")).tag(РежимПросмотраОбъёма.обзор)
                }
                .pickerStyle(.segmented)
                .откликВыбора(режим)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: Подвал

    /// Честно: модель — работа ИИ по фото; ракурсы — фото продавца без фона. Размеры — если пришли.
    private var подвал: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: режим == .модель && модель.созданаИИ ? "sparkles" : "camera")
                    .accessibilityHidden(true)
                Text(заметка)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.footnote)
            .foregroundStyle(Theme.текстВторой)
            if let размеры = модель.текстГабаритов {
                Text(String(format: т("o3_size"), размеры))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.текст)
                    .accessibilityLabel(озвучкаРазмеров ?? размеры)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .accessibilityElement(children: .combine)
    }

    private var заметка: String {
        switch режим {
        case .модель: return т(модель.созданаИИ ? "o3_note_ai" : "o3_note_seller")
        case .обзор: return т("o3_note_360")
        }
    }

    private var озвучкаРазмеров: String? {
        guard let г = модель.габаритыСм else { return nil }
        return String(format: т("o3_size_a11y"), МодельОбъёмаОбъявления.см(г.ширина),
                      МодельОбъёмаОбъявления.см(г.высота), МодельОбъёмаОбъявления.см(г.глубина))
    }
}

// MARK: - Значок на фото

/// «3D» или «360°» в нижнем углу фото галереи — то же стекло, что у кнопок над фото (стеклоНадФото).
struct ЗначокОбъёмаГалереи: View {
    let модель: МодельОбъёмаОбъявления
    let открыть: () -> Void

    init(модель: МодельОбъёмаОбъявления, открыть: @escaping () -> Void) {
        self.модель = модель
        self.открыть = открыть
    }

    var body: some View {
        Button(action: открыть) {
            HStack(spacing: 5) {
                Image(systemName: модель.есть3D ? "cube.transparent" : "rotate.3d")
                    .font(.footnote.weight(.bold))
                    .accessibilityHidden(true)
                Text(ОбъёмText.т(модель.есть3D ? "o3_badge_3d" : "o3_badge_360"))
                    .font(.footnote.weight(.heavy))
                    .tracking(0.3)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .frame(minHeight: МеркиКнопокНадФото.сторона)
            .стеклоНадФото()
            .padding(МеркиКнопокНадФото.поле)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеСПружинкой(сжатие: 0.92))
        /* Над фото места мало: самые крупные размеры текста — не больше первого «специального». */
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityLabel(ОбъёмText.т(модель.есть3D ? "o3_badge_3d_a11y" : "o3_badge_360_a11y"))
        .accessibilityHint(ОбъёмText.т("o3_btn_hint"))
    }
}

// MARK: - Кнопка под ценой

/// «Смотреть в 3D» / «Обзор 360°» во всю ширину: значок в круге, подпись, справа ✦ (модель ИИ) или стрелка.
struct КнопкаОбъёмаОбъявления: View {
    let товар: Listing
    @ScaledMetric(relativeTo: .body) private var круг: CGFloat = 42

    init(товар: Listing) {
        self.товар = товар
    }

    /// Ставить ли кнопку на страницу: есть model3d с моделью или ракурсами и рубильник включён.
    static func есть(_ т: Listing) -> Bool { т.естьОбъём }

    var body: some View {
        if let модель = товар.модельОбъёма, модель.естьЧтоПоказать {
            кнопка(модель)
                .padding(.horizontal, 20)
                .padding(.top, 14)
        }
    }

    private func кнопка(_ модель: МодельОбъёмаОбъявления) -> some View {
        let заголовок = ОбъёмText.т(модель.есть3D ? "o3_btn_3d" : "o3_btn_360")
        let подпись = ОбъёмText.т(модель.есть3D
                                  ? (ОкноОбъёма.комнатаДоступна ? "o3_btn_3d_sub_room" : "o3_btn_3d_sub")
                                  : "o3_btn_360_sub")
        return Button {
            ОткликСайта.выбор()
            ОкноОбъёма.открыть(товар: товар)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: модель.есть3D ? "cube.transparent" : "rotate.3d")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: круг, height: круг)
                    .background(Theme.акцент, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.callout.weight(.heavy))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(подпись)
                        .font(.footnote)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: модель.есть3D && модель.созданаИИ ? "sparkles" : "chevron.forward")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.акцент)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.панельКромка, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: ДвижениеСайта.сжатие))
        .accessibilityLabel(заголовок)
        .accessibilityValue(подпись)
        .accessibilityHint(ОбъёмText.т("o3_btn_hint"))
    }
}

import SwiftUI
import UIKit

/**
 «МОЁ» — ХАБ (владелец 16.10.2026: «по всем моментам разом»; «мощная анимированная подача»).

 Вход — карточка «Моё» в кабинете (гостю тоже) и «Мой гараж» в «Подойдут ли?». Экран — шапка с общим прогрессом,
 три карточки профилей ровной высоты (на iPad — в три колонки), строка «Только на этом телефоне» и «Удалить всё «Моё»»
 (то же — в меню «…» шапки). Подача — каскад ПоявлениеМоего (шапка 0, карточки 1–3, низ 4) и кольца, дорастающие
 пружиной; «Удалить всё» — кольца плавно уходят в 0, сводки сменяются проявлением, внизу весть «Удалено с телефона».

 В стеке кабинета переходы — через переходКабинета (КабинетЦель: .моё, .мойГараж, .моиУстройства, .моиМерки), в окне
 поверх любого экрана (ОкноМоего) — свой стек с той же регистрацией целей.
 */
struct ЭкранМоего: View {
    @ObservedObject private var хранилище = МоёХранилище.shared
    @Environment(\.horizontalSizeClass) private var класс
    @State private var спросить = false
    @State private var весть: String? = nil
    @State private var номерВести = 0

    init() {}

    private func т(_ ключ: String) -> String { МоёText.т(ключ) }

    var body: some View {
        let запись = хранилище.запись
        ScrollView {
            VStack(spacing: 16) {
                ШапкаМоего(доля: запись.готовность, всё: запись.всёГотово)
                    .появлениеМоего(0)
                карточки(запись)
                низ(запись)
                    .появлениеМоего(4)
            }
            .padding(16)
            .frame(maxWidth: класс == .regular ? 960 : 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .шапкаЭкранаСайта(т("my_title"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        спросить = true
                    } label: {
                        Label(т("my_delete_all"), systemImage: "trash")
                    }
                    .disabled(запись.пусто)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .accessibilityLabel(т("my_more_actions"))
                }
            }
        }
        .confirmationDialog(т("my_delete_all_q"), isPresented: $спросить, titleVisibility: .visible) {
            Button(т("my_delete"), role: .destructive) { стереть() }
            Button(т("my_cancel"), role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if let весть {
                ТостКабинета(текст: весть)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .accessibilityHidden(true)
            }
        }
        .onAppear { хранилище.подготовить() }
    }

    /// Три профиля: на iPhone — столбиком, на iPad — в три колонки.
    @ViewBuilder
    private func карточки(_ запись: ЗаписьМоего) -> some View {
        if класс == .regular {
            HStack(alignment: .top, spacing: 12) {
                ForEach(ПрофильМоего.allCases) { профиль in
                    карточка(профиль, запись)
                }
            }
        } else {
            VStack(spacing: 12) {
                ForEach(ПрофильМоего.allCases) { профиль in
                    карточка(профиль, запись)
                }
            }
        }
    }

    private func карточка(_ профиль: ПрофильМоего, _ запись: ЗаписьМоего) -> some View {
        ПереходМоего(цель: профиль.цель) {
            КарточкаПрофиляМоего(профиль: профиль, сводка: запись.сводка(профиль), прогресс: профиль.прогресс(запись),
                                 номер: профиль.rawValue)
        }
        .появлениеМоего(профиль.rawValue + 1)
    }

    /// Строка приватности и «Удалить всё «Моё»».
    private func низ(_ запись: ЗаписьМоего) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(т("my_local"))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Theme.акцент)
            }
            .font(.footnote)
            .foregroundStyle(Theme.текстВторой)
            Button {
                спросить = true
            } label: {
                Label(т("my_delete_all"), systemImage: "trash")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.скидкаТекст)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.96))
            .disabled(запись.пусто)
            .opacity(запись.пусто ? 0.45 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func стереть() {
        хранилище.стереть()
        ОткликСайта.успех()
        показатьВесть(т("my_deleted"))
    }

    private func показатьВесть(_ текст: String) {
        номерВести += 1
        let номер = номерВести
        withAnimation(ДвижениеСайта.появление) { весть = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard номер == номерВести else { return }
            withAnimation(ДвижениеСайта.уход) { весть = nil }
        }
    }
}

// MARK: - Цели стека

/// Экран «Моего» по цели стека (кабинет и окно поверх). Прочие цели сюда не приходят.
struct ЭкранРазделаМоего: View {
    let цель: КабинетЦель

    init(цель: КабинетЦель) {
        self.цель = цель
    }

    var body: some View {
        switch цель {
        case .моё:
            ЭкранМоего()
        case .мойГараж:
            ЭкранГаражаМоего()
        case .моиУстройства:
            ЭкранУстройствМоего()
        case .моиМерки:
            ЭкранТелаМоего()
        default:
            EmptyView()
        }
    }
}

// MARK: - Окно поверх любого экрана

/// «Моё» поверх любого экрана (из «Подойдут ли?», с плашки «Подходит моему» и чипа ленты): свой стек и «Закрыть».
@MainActor
enum ОкноМоего {
    static func открыть(_ цель: КабинетЦель = .моё) {
        guard Config.моё else { return }
        ПоверхВсего.показать(большой: true) { закрыть in
            ОкноМоегоВид(цель: цель, закрыть: закрыть)
        }
    }
}

private struct ОкноМоегоВид: View {
    let цель: КабинетЦель
    let закрыть: () -> Void

    var body: some View {
        NavigationStack {
            ЭкранРазделаМоего(цель: цель)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(МоёText.т("my_close"), action: закрыть)
                    }
                }
                .navigationDestination(for: КабинетЦель.self) { следующая in
                    ЭкранРазделаМоего(цель: следующая)
                }
        }
        .tint(Theme.акцент)
    }
}

// MARK: - Сводки карточек

extension ЗаписьМоего {
    func сводка(_ профиль: ПрофильМоего) -> String {
        switch профиль {
        case .гараж: return сводкаГаража
        case .устройства: return сводкаУстройств
        case .тело: return сводкаТела
        }
    }

    /// «Toyota Camry, 2018 · 5×114.3 · R17 · + ещё 1».
    var сводкаГаража: String {
        guard let м = главнаяМашина else { return МоёText.т("my_garage_empty") }
        var части = [м.заголовок]
        if let р = м.посадка?.разболтовка { части.append(р.подпись) }
        if let r = м.посадка?.штатныеДиаметры.first { части.append("R" + ЧислаАвтоподбора.ч(r)) }
        if машины.count > 1 { части.append(String(format: МоёText.т("my_more"), String(машины.count - 1))) }
        return части.joined(separator: " · ")
    }

    /// «iPhone 15 Pro · ноутбук 15.6″ · ТВ 55″».
    var сводкаУстройств: String {
        var части: [String] = []
        if let т = телефон { части.append(т.модель) }
        for у in устройства where у.заполнено {
            части.append(у.короткоВСводке)
        }
        guard !части.isEmpty else { return МоёText.т("my_devices_empty") }
        return части.prefix(3).joined(separator: " · ")
    }

    /// «176 см · EU 42 · RU 48».
    var сводкаТела: String {
        var части: [String] = []
        if let рост = тело.рост { части.append(String(рост) + " " + МоёТелоText.т("mb_cm")) }
        for размер in тело.размеры.prefix(3) { части.append(размер.коротко) }
        if части.isEmpty && !тело.мерки.isEmpty {
            части.append(МоёТелоText.т("mb_measures") + ": " + String(тело.мерки.count))
        }
        guard !части.isEmpty else { return МоёText.т("my_body_empty") }
        return части.joined(separator: " · ")
    }
}

extension УстройствоМоего {
    /// «ноутбук 15.6″», «ТВ 55″»; без диагонали — модель или вид.
    var короткоВСводке: String {
        let ключ: String
        switch вид {
        case .ноутбук: ключ = "md_s_laptop"
        case .монитор: ключ = "md_s_monitor"
        case .тв: ключ = "md_s_tv"
        }
        if let д = диагональ { return String(format: МоёТелоText.т(ключ), ЧислоМоего.дюймы(д)) }
        let своя = модель.trimmingCharacters(in: .whitespacesAndNewlines)
        return своя.isEmpty ? вид.название : своя
    }
}

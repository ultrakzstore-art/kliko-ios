import SwiftUI
import UIKit
import Photos

/**
 «ПОМЕСТИТСЯ ЛИ?» — ЛИСТЫ: «УКАЖИТЕ РАЗМЕРЫ» И СНИМОК (владелец 13.10.2026: «нужнее охват всего»).

 Лист размеров — три поля в сантиметрах (ширина, высота, глубина) с цифровой клавиатурой и «Далее» над ней. Что нашли
 в объявлении (РазборГабаритов) — уже в полях, и сверху сказано, откуда: из характеристик, из описания (с кусочком
 текста), примерно по диагонали или «не нашли»; под этим — «Размеры есть в описании или у продавца». Значение вне
 0,5–1000 см — поле краснеет и подсказывает пределы; «Готово» — когда все три в порядке. Запятая и точка, арабские
 цифры — всё понимается.

 Лист снимка — кадр с коробкой и подписями, «Сохранить в Фото» (доступ только на добавление) и «Поделиться»
 (системный лист); «Вернуться к камере» — закрыть.
 */
struct ЛистРазмеровГабаритов: View {
    let найдено: НайденныеГабариты
    let готово: (ГабаритыВещи) -> Void
    let отмена: () -> Void
    @State private var ширина: String
    @State private var высота: String
    @State private var глубина: String
    @FocusState private var поле: Поле?
    @Environment(\.dynamicTypeSize) private var размерТекста

    enum Поле: Hashable {
        case ширина
        case высота
        case глубина
    }

    init(найдено: НайденныеГабариты, текущие: ГабаритыВещи?, готово: @escaping (ГабаритыВещи) -> Void,
         отмена: @escaping () -> Void) {
        self.найдено = найдено
        self.готово = готово
        self.отмена = отмена
        _ширина = State(initialValue: Self.строка(текущие?.ширина ?? найдено.ширина))
        _высота = State(initialValue: Self.строка(текущие?.высота ?? найдено.высота))
        _глубина = State(initialValue: Self.строка(текущие?.глубина ?? найдено.глубина))
    }

    private func т(_ ключ: String) -> String { ГабаритыText.т(ключ) }

    private static func строка(_ значение: Double?) -> String {
        значение.map { ГабаритыВещи.число($0) } ?? ""
    }

    /// Текст поля → сантиметры: запятая или точка, арабские цифры; вне пределов — nil.
    static func значение(_ текст: String) -> Double? {
        var чисто = ""
        for знак in текст.unicodeScalars {
            switch знак.value {
            case 0x0660...0x0669:
                чисто.append(String(знак.value - 0x0660))
            case 0x06F0...0x06F9:
                чисто.append(String(знак.value - 0x06F0))
            case 0x002C, 0x066B:
                чисто.append(".")
            case 0x0030...0x0039, 0x002E:
                чисто.unicodeScalars.append(знак)
            default:
                continue
            }
        }
        guard let число = Double(чисто), ГабаритыВещи.пределы.contains(число) else { return nil }
        return число
    }

    private var итог: ГабаритыВещи? {
        guard let ш = Self.значение(ширина), let в = Self.значение(высота), let г = Self.значение(глубина) else {
            return nil
        }
        return ГабаритыВещи(ширина: ш, высота: в, глубина: г)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    шапка
                    источник
                    VStack(spacing: 10) {
                        строкаПоля(.ширина, подпись: т("fb_w"), значок: "arrow.left.and.right", текст: $ширина)
                        строкаПоля(.высота, подпись: т("fb_h"), значок: "arrow.up.and.down", текст: $высота)
                        строкаПоля(.глубина, подпись: т("fb_d"), значок: "arrow.up.left.and.arrow.down.right",
                                   текст: $глубина)
                    }
                    Text(т("fb_note"))
                        .font(.footnote)
                        .foregroundStyle(Theme.текстВторой)
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("fb_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("fb_cancel"), action: отмена)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(т("fb_done"), action: сохранить)
                        .fontWeight(.bold)
                        .disabled(итог == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(поле == .глубина ? т("fb_done") : т("fb_next"), action: дальше)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            /* Первое пустое поле — сразу под палец (когда лист доедет). */
            guard let пустое = первоеПустое else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                поле = пустое
            }
        }
    }

    private var первоеПустое: Поле? {
        if Self.значение(ширина) == nil { return .ширина }
        if Self.значение(высота) == nil { return .высота }
        if Self.значение(глубина) == nil { return .глубина }
        return nil
    }

    private func сохранить() {
        guard let итог else { return }
        ОткликСайта.успех()
        готово(итог)
    }

    private func дальше() {
        switch поле {
        case .some(.ширина):
            поле = .высота
        case .some(.высота):
            поле = .глубина
        case .some(.глубина), .none:
            поле = nil
            if итог != nil { сохранить() }
        }
    }

    // MARK: Части

    private var шапка: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cube.transparent")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 48, height: 48)
                .background(Theme.оттенокАкцента,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(т("fb_sizes_title"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                Text(т("fb_sizes_sub"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var текстИсточника: String {
        switch найдено.источник {
        case .подача:
            return найдено.полные != nil ? т("fb_src_form") : т("fb_src_partial")
        case .характеристики:
            return найдено.полные != nil ? т("fb_src_specs") : т("fb_src_partial")
        case .образец:
            return найдено.полные != nil ? т("fb_src_tpl") : т("fb_src_partial")
        case .описание:
            return найдено.полные != nil ? т("fb_src_desc") : т("fb_src_partial")
        case .диагональ(let дюймы):
            return ГабаритыText.т("fb_src_diag", ГабаритыВещи.число(дюймы))
        case .нет:
            return т("fb_src_none")
        }
    }

    private var значокИсточника: String {
        switch найдено.источник {
        case .подача: return "checkmark.seal.fill"
        case .характеристики: return "checkmark.seal"
        case .образец: return "ruler"
        case .описание: return "text.quote"
        case .диагональ: return "tv"
        case .нет: return "questionmark.circle"
        }
    }

    private var цитата: String? {
        if case .описание(let кусок) = найдено.источник, !кусок.isEmpty { return кусок }
        return nil
    }

    private var источник: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: значокИсточника)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.акцент)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(текстИсточника)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                if let цитата {
                    Text("«" + цитата + "»")
                        .font(.footnote.italic())
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(4)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Theme.мята, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func строкаПоля(_ своё: Поле, подпись: String, значок: String, текст: Binding<String>) -> some View {
        let плохо = !текст.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
            && Self.значение(текст.wrappedValue) == nil
        let выбрано = поле == своё
        let раскладка = размерТекста.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return VStack(alignment: .leading, spacing: 4) {
            раскладка {
                HStack(spacing: 12) {
                    Image(systemName: значок)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.акцент)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(подпись)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.текст)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    TextField("0", text: текст)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.текст)
                        .focused($поле, equals: своё)
                        .frame(minWidth: 64, maxWidth: 140)
                        .accessibilityLabel(подпись + ", " + т("fb_in_cm"))
                    Text(т("fb_cm"))
                        .font(.body)
                        .foregroundStyle(Theme.текстВторой)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 56)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(плохо ? Theme.ценаСкидка : (выбрано ? Theme.акцент : Theme.линия),
                                  lineWidth: выбрано || плохо ? 1.5 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .onTapGesture { поле = своё }
            if плохо {
                Text(т("fb_bad"))
                    .font(.footnote)
                    .foregroundStyle(Theme.скидкаТекст)
            }
        }
    }
}

// MARK: - Снимок

struct ЛистСнимкаГабаритов: View {
    let снимок: СнимокГабаритов
    let габариты: ГабаритыВещи?
    let закрыть: () -> Void
    @State private var сохраняем = false
    @State private var итог: String? = nil
    @State private var итогХорошо = false

    init(снимок: СнимокГабаритов, габариты: ГабаритыВещи?, закрыть: @escaping () -> Void) {
        self.снимок = снимок
        self.габариты = габариты
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ГабаритыText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(uiImage: снимок.картинка)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                        .accessibilityLabel(снимок.озвучка
                                            ?? габариты.map { ГабаритыText.т("fb_shot_img", $0.озвучка) }
                                            ?? т("fb_shot_title"))
                    кнопки
                    if let итог {
                        Label(итог, systemImage: итогХорошо ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(итогХорошо ? Theme.акцент : Theme.скидкаТекст)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }
                .padding(20)
                .animation(ДвижениеСайта.смена, value: итог)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("fb_shot_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("fb_back"), action: закрыть)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var кнопки: some View {
        let картинка = Image(uiImage: снимок.картинка)
        return VStack(spacing: 10) {
            Button(action: сохранить) {
                HStack(spacing: 8) {
                    if сохраняем {
                        SiteSpinner(размер: 18, толщина: 2.5, дорожка: Color.white.opacity(0.3), верх: Color.white,
                                    стоит: ДвижениеСайта.тихо)
                    } else {
                        Image(systemName: "square.and.arrow.down")
                            .accessibilityHidden(true)
                    }
                    Text(т("fb_save"))
                }
                .font(.body.weight(.bold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.97))
            .disabled(сохраняем)
            ShareLink(item: картинка, preview: SharePreview(т("fb_share_title"), image: картинка)) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityHidden(true)
                    Text(т("fb_share"))
                }
                .font(.body.weight(.bold))
                .foregroundStyle(Theme.акцент)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Theme.оттенокАкцента,
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(Theme.панельКромка, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.97))
        }
    }

    private func сохранить() {
        guard !сохраняем else { return }
        сохраняем = true
        итог = nil
        let картинка = снимок.картинка
        Task {
            /* JPEG — не на главной нити: кадр во весь экран сжимается заметное время. */
            let данные = await Task.detached(priority: .userInitiated) {
                картинка.jpegData(compressionQuality: 0.92)
            }.value
            let ответ: СохранениеГабаритов.Итог
            if let данные {
                ответ = await СохранениеГабаритов.вФото(данные)
            } else {
                ответ = .сбой
            }
            сохраняем = false
            switch ответ {
            case .готово:
                итогХорошо = true
                итог = т("fb_saved")
                ОткликСайта.успех()
            case .нетДоступа:
                итогХорошо = false
                итог = т("fb_save_denied")
                ОткликСайта.предупреждение()
            case .сбой:
                итогХорошо = false
                итог = т("fb_save_fail")
                ОткликСайта.предупреждение()
            }
            if let итог { UIAccessibility.post(notification: .announcement, argument: итог) }
        }
    }
}

/// Снимок в Фото iPhone: доступ только на добавление (NSPhotoLibraryAddUsageDescription уже в Info.plist).
enum СохранениеГабаритов {
    enum Итог: Sendable {
        case готово
        case нетДоступа
        case сбой
    }

    static func вФото(_ данные: Data) async -> Итог {
        let доступ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard доступ == .authorized || доступ == .limited else { return .нетДоступа }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: данные, options: nil)
            }
            return .готово
        } catch {
            return .сбой
        }
    }
}

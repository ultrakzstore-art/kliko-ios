import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

/**
 «ПЕРЕНЕСТИ ОБЪЯВЛЕНИЯ» — СВОЙ ЭКРАН (этап 50). Состояние — ИмпортМодель, запросы — ИмпортAPI.

 Открывается окном поверх (НативныеОкна) по адресам cabinet?go=import и ?go=aiimport: слайд главной «Перенесите
 объявления», «Перенести по ссылке» на старте подачи, ссылки из пушей и писем. Оформление — как у экрана сайта
 #aiimport-screen: плитки способов с ценой («бесплатно», «5 бесплатно», «PRO»), три шага «Переносим / Вы проверяете /
 Публикуете», полоса хода с найденными товарами, таблица строк на проверку и нижняя панель «Выбрано … · на …» с кнопкой
 «Добавить в «Неактивные»».
 */
struct МастерИмпорта: View {
    let открыть: (URL) -> Void
    let закрыть: () -> Void

    @StateObject private var модель: ИмпортМодель

    init(способ: СпособИмпорта, открыть: @escaping (URL) -> Void, закрыть: @escaping () -> Void) {
        self.открыть = открыть
        self.закрыть = закрыть
        _модель = StateObject(wrappedValue: ИмпортМодель(способ: способ))
    }

    private func т(_ ключ: String) -> String { ИмпортText.т(ключ) }

    var body: some View {
        NavigationStack {
            содержимое
                .background(Theme.фонСтраницы.ignoresSafeArea())
                .navigationTitle(т("imp_t"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(т("close")) { закрыть() }
                    }
                }
        }
        .tint(Theme.акцент)
        .task { await модель.начать() }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.этап {
        case .ввод:
            ВводИмпорта(модель: модель, открыть: открыть)
        case .идёт:
            ХодИмпорта(модель: модель)
        case .проверка:
            ПроверкаИмпорта(модель: модель, открыть: открыть)
        case .готово:
            ИтогИмпорта(модель: модель, открыть: открыть, закрыть: закрыть)
        }
    }
}

// MARK: - Ввод

private struct ВводИмпорта: View {
    @ObservedObject var модель: ИмпортМодель
    let открыть: (URL) -> Void

    @State private var файлОткрыт = false
    @State private var картинка: PhotosPickerItem? = nil
    @State private var фото: [PhotosPickerItem] = []

    private func т(_ ключ: String) -> String { ИмпортText.т(ключ) }
    private func т(_ ключ: String, _ з: [String: String]) -> String { ИмпортText.т(ключ, з) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(т("imp_sub"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                if let н = модель.незаконченный {
                    незаконченный(н)
                }
                Text(т("imp_q"))
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .accessibilityAddTraits(.isHeader)
                способы
                if let заметка = модель.заметка {
                    ЗаметкаБизнеса(заметка, тон: .предупреждение, значок: "exclamationmark.circle")
                }
                switch модель.способ {
                case .ссылка: однаСсылка
                case .список: список
                case .каталог: каталог
                }
                шаги
                ЗаметкаБизнеса(т("imp_draft"), тон: .инфо, значок: "tray")
            }
            .padding(14)
        }
        .scrollDismissesKeyboard(.interactively)
        .fileImporter(isPresented: $файлОткрыт, allowedContentTypes: ВводИмпорта.типыФайлов) { итог in
            if case .success(let адрес) = итог { модель.выбранФайл(адрес) }
        }
        .onChange(of: картинка) { _, элемент in
            guard let элемент else { return }
            Task {
                if let данные = try? await элемент.loadTransferable(type: Data.self) {
                    модель.выбранаКартинка(данные, имя: т("src_img"))
                }
                картинка = nil
            }
        }
        .onChange(of: фото) { _, элементы in
            guard !элементы.isEmpty else { return }
            Task {
                var снимки: [Data] = []
                for элемент in элементы {
                    if let данные = try? await элемент.loadTransferable(type: Data.self) { снимки.append(данные) }
                }
                модель.выбраныФото(снимки)
                фото = []
            }
        }
        .modifier(ОкнаИмпорта(модель: модель, открыть: открыть))
    }

    static let типыФайлов: [UTType] = {
        var типы: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText, .pdf, .spreadsheet]
        for расширение in ["xlsx", "xls", "docx", "doc", "ods"] {
            if let тип = UTType(filenameExtension: расширение) { типы.append(тип) }
        }
        return типы
    }()

    // MARK: Способы

    private var способы: some View {
        VStack(spacing: 8) {
            плитка(.ссылка, значок: "link", т("src_link_t"), т("src_link_s"), цена: т("src_free"), хорошо: true)
            плитка(.список, значок: "list.bullet", т("src_many_t"), т("src_many_s"),
                   цена: модель.pro ? т("src_in_tariff") : т("src_many_free"), хорошо: модель.pro)
            плитка(.каталог, значок: "sparkles", т("src_cat_t"), т("src_cat_s"),
                   цена: модель.pro ? т("src_in_tariff") : т("src_pro"), хорошо: модель.pro)
        }
    }

    private func плитка(_ способ: СпособИмпорта, значок: String, _ заголовок: String, _ подпись: String, цена: String,
                        хорошо: Bool) -> some View {
        let выбран = модель.способ == способ
        return Button {
            withAnimation(ДвижениеСайта.смена) {
                модель.способ = способ
                модель.заметка = nil
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: значок)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(выбран ? Color.white : Theme.акцент)
                    .frame(width: 38, height: 38)
                    .background(выбран ? Theme.акцент : Theme.оттенокАкцента,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(подпись)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 6)
                МеткаБизнеса(текст: цена, золото: !хорошо)
            }
            .padding(12)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(выбран ? Theme.акцент : Theme.линия, lineWidth: выбран ? 2 : 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбран ? [.isSelected] : [])
    }

    // MARK: Одна ссылка

    private var однаСсылка: some View {
        КарточкаБизнеса(т("li_q"), значок: "link") {
            Text(т("li_sub"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                TextField(т("li_ph"), text: $модель.ссылка)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { модель.перенестиСсылку() }
                    .font(.system(size: 15))
                    .padding(11)
                    .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                PasteButton(payloadType: String.self) { строки in
                    Task { @MainActor in модель.ссылка = строки.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.roundedRectangle)
            }
            галочка(т("li_own"), $модель.моё)
            КнопкаБизнеса(подпись: т("li_go")) { модель.перенестиСсылку() }
            Text(т("li_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
        }
    }

    // MARK: Список ссылок

    private var список: some View {
        let разбор = модель.разобранныеСсылки
        let годных = разбор.годные.count
        var счётчик = ""
        if годных > 0 {
            счётчик = т("lm_cnt", ["n": String(годных)])
            if разбор.чужие > 0 { счётчик += т("lm_foreign", ["n": String(разбор.чужие)]) }
        }
        let подписьКнопки = годных > 0 ? т("lm_go_n", ["n": String(годных)]) : т("lm_go")
        return КарточкаБизнеса(т("lm_q"), значок: "list.bullet") {
            Text(модель.pro ? т("lm_sub") : "\(т("lm_sub"))\n\(т("lm_free"))")
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $модель.ссылки)
                .font(.system(size: 14, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .frame(minHeight: 130)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            if !счётчик.isEmpty {
                Text(счётчик)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
            }
            галочка(т("lm_own"), $модель.моиВсе)
            КнопкаБизнеса(подпись: подписьКнопки) { модель.перенестиСписок() }
            Text(т("li_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
        }
    }

    // MARK: Каталог

    @ViewBuilder
    private var каталог: some View {
        if модель.pro {
            КарточкаБизнеса(т("src_cat_t"), значок: "sparkles") {
                Text(т("howto"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $модель.текст)
                        .font(.system(size: 14))
                        .frame(minHeight: 170)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(Theme.поверхность2,
                                    in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    if модель.текст.isEmpty {
                        Text(т("text_ph"))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.текстВторой.opacity(0.8))
                            .padding(12)
                            .allowsHitTesting(false)
                    }
                }
                Text(т("or_upload"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                источник(значок: "doc.text", т("src_file"),
                         модель.файлПодпись.isEmpty ? т("src_file_none") : модель.файлПодпись) {
                    Button(т("pick_file")) { файлОткрыт = true }
                }
                источник(значок: "camera.viewfinder", т("src_img"),
                         модель.картинкаПодпись.isEmpty ? т("src_img_hint") : модель.картинкаПодпись) {
                    if модель.естьКартинка {
                        Button(т("remove")) { модель.убратьКартинку() }
                    } else {
                        PhotosPicker(т("pick_photos"), selection: $картинка, matching: .images)
                    }
                }
                источник(значок: "photo.on.rectangle", т("src_photos"),
                         модель.фотоПодпись.isEmpty ? т("src_photos_hint") : модель.фотоПодпись) {
                    PhotosPicker(т("pick_photos"), selection: $фото, maxSelectionCount: 30, matching: .images)
                }
                КнопкаБизнеса(подпись: т("parse"), занято: модель.грузимВвод) { модель.разобрать() }
            }
        } else {
            КарточкаБизнеса(т("pro_t"), значок: "crown") {
                Text(т("pro_s"))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                ЦифроваяПокупка(подпись: БизнесText.т("cab_get_pro"), путь: "cabinet.php", открыть: открыть)
                КнопкаБизнеса(подпись: т("pro_alt"), второстепенная: true) {
                    withAnimation(ДвижениеСайта.смена) { модель.способ = .ссылка }
                }
            }
        }
    }

    private func источник<Кнопка: View>(значок: String, _ заголовок: String, _ подпись: String,
                                         @ViewBuilder кнопка: () -> Кнопка) -> some View {
        HStack(spacing: 10) {
            Image(systemName: значок)
                .foregroundStyle(Theme.акцент)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(заголовок)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(подпись)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            кнопка()
                .font(.system(size: 14, weight: .semibold))
                .buttonStyle(.bordered)
        }
        .padding(10)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }

    // MARK: Общее

    private func галочка(_ текст: String, _ значение: Binding<Bool>) -> some View {
        Toggle(isOn: значение) {
            Text(текст)
                .font(.system(size: 14))
                .foregroundStyle(Theme.текст)
        }
        .toggleStyle(ГалочкаИмпорта())
    }

    private var шаги: some View {
        VStack(alignment: .leading, spacing: 10) {
            шаг(1, т("imp_s1"), т("imp_s1s"))
            шаг(2, т("imp_s2"), т("imp_s2s"))
            шаг(3, т("imp_s3"), т("imp_s3s"))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    private func шаг(_ номер: Int, _ заголовок: String, _ подпись: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(String(номер))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Theme.акцент)
                .frame(width: 26, height: 26)
                .background(Theme.оттенокАкцента, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(заголовок)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Text(подпись)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func незаконченный(_ н: НезаконченныйРазбор) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(н.название.isEmpty ? т("unf_t") : "\(т("unf_t")): \(н.название)")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.текст)
            Text(т("unf_s", ["n": String(н.строк), "p": String(н.процент)]))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                КнопкаБизнеса(подпись: т("unf_go")) {
                    Task { await модель.продолжить(н.id) }
                }
                КнопкаБизнеса(подпись: т("unf_drop"), второстепенная: true) { модель.спроситьНачатьЗаново() }
            }
        }
        .padding(14)
        .background(КраскаОбъявлений.предупреждениеФон,
                    in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }
}

/// Галочка сайта (.li-own): квадрат с отметкой и подпись.
private struct ГалочкаИмпорта: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(configuration.isOn ? Theme.акцент : Theme.текстВторой)
                    .accessibilityHidden(true)
                configuration.label
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }
}

/// Окна-вопросы импорта: лимит объявлений, лимит Kliko AI, «Начать заново?», верификация.
private struct ОкнаИмпорта: ViewModifier {
    @ObservedObject var модель: ИмпортМодель
    let открыть: (URL) -> Void
    @State private var верификация = false

    private func т(_ ключ: String) -> String { ИмпортText.т(ключ) }

    func body(content: Content) -> some View {
        content
            .alert(заголовок, isPresented: Binding(get: { модель.окно != nil }, set: { if !$0 { модель.окно = nil } }),
                   presenting: модель.окно) { окно in
                switch окно {
                case .лимит(_, let нужнаВерификация):
                    if нужнаВерификация {
                        Button(т("lim_verify")) { верификация = true }
                    } else {
                        Button(т("on_site")) { наСайт() }
                    }
                    Button(т("later"), role: .cancel) {}
                case .лимитИИ(let нужнаВерификация):
                    if нужнаВерификация {
                        Button(т("verify")) { верификация = true }
                    }
                    Button(т("on_site")) { наСайт() }
                    Button(т("later"), role: .cancel) {}
                case .начатьЗаново(let номер):
                    Button(т("unf_drop"), role: .destructive) { модель.начатьЗаново(номер) }
                    Button(т("cancel"), role: .cancel) {}
                }
            } message: { окно in
                Text(сообщение(окно))
            }
            .sheet(isPresented: $верификация) {
                ЛистВерификации(открыть: открыть)
            }
    }

    private var заголовок: String {
        switch модель.окно {
        case .лимит: return т("lim_t")
        case .лимитИИ(let нужнаВерификация): return нужнаВерификация ? т("ai_ended_t") : т("ai_out_t")
        case .начатьЗаново: return т("unf_drop_q")
        case nil: return ""
        }
    }

    private func сообщение(_ окно: ИмпортМодель.Окно) -> String {
        switch окно {
        case .лимит(let текст, let нужнаВерификация):
            if нужнаВерификация || Config.цифровыеПокупки { return текст }
            return "\(текст)\n\(т("no_digital"))"
        case .лимитИИ(let нужнаВерификация):
            let основа = нужнаВерификация ? т("ai_ended_d") : т("ai_out_d")
            if Config.цифровыеПокупки { return основа }
            return "\(основа)\n\(т("no_digital"))"
        case .начатьЗаново:
            return т("unf_drop_s")
        }
    }

    private func наСайт() {
        if let u = Config.страницаСайта("cabinet.php") { открыть(u) }
    }
}

// MARK: - Ход разбора

private struct ХодИмпорта: View {
    @ObservedObject var модель: ИмпортМодель

    private func т(_ ключ: String, _ з: [String: String]) -> String { ИмпортText.т(ключ, з) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: модель.пауза == nil ? "sparkles" : "wifi.exclamationmark")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .symbolEffect(.pulse, isActive: модель.пауза == nil)
                    .frame(width: 76, height: 76)
                    .background(Theme.оттенокАкцента, in: Circle())
                    .accessibilityHidden(true)
                Text(модель.заголовокХода)
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                ProgressView(value: модель.прогресс)
                    .tint(Theme.акцент)
                    .accessibilityValue(String(Int(модель.прогресс * 100)) + "%")
                Text(модель.подписьХода)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                if !модель.найдено.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(т("prog_found", ["n": String(модель.найдено.count)]))
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(Theme.текстВторой)
                        ForEach(Array(модель.найдено.suffix(8).enumerated()), id: \.offset) { _, имя in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.акцент)
                                    .accessibilityHidden(true)
                                Text(имя.isEmpty ? "—" : имя)
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.текст)
                                    .lineLimit(1)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .animation(ДвижениеСайта.вставкаСписка, value: модель.найдено.count)
                }
                if let пауза = модель.пауза {
                    КнопкаБизнеса(подпись: пауза) { модель.продолжитьПосле() }
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Проверка строк

private struct ПроверкаИмпорта: View {
    @ObservedObject var модель: ИмпортМодель
    let открыть: (URL) -> Void

    @State private var разделДля: UUID? = nil
    @State private var разделВсем = false
    @State private var наценкаОткрыта = false
    @State private var наценка = ""
    @State private var плашка: String? = nil

    private func т(_ ключ: String) -> String { ИмпортText.т(ключ) }
    private func т(_ ключ: String, _ з: [String: String]) -> String { ИмпортText.т(ключ, з) }
    private func тК(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    private var всеВыбраны: Bool { !модель.строки.isEmpty && модель.строки.allSatisfy { $0.выбрана } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                сводка
                if let заметка = модель.заметка {
                    ЗаметкаБизнеса(заметка, тон: .предупреждение, значок: "exclamationmark.circle")
                }
                Toggle(isOn: Binding(get: { всеВыбраны }, set: { модель.выбратьВсе($0) })) {
                    Text(т("rv_all"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                }
                .toggleStyle(ГалочкаИмпорта())
                if !модель.колонки.isEmpty && !модель.сИИ && !модель.изСсылок {
                    РазметкаТаблицы(модель: модель)
                }
                массово
                ForEach($модель.строки) { $строка in
                    СтрокаПроверки(строка: $строка, имяРаздела: модель.имяРаздела(строка.раздел),
                                   выбратьРаздел: { разделДля = строка.id },
                                   убрать: { модель.убрать(строка.id) })
                }
                Text(т("rv_hint"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { панель }
        .sheet(item: Binding(get: { разделДля.map { ВыборРаздела.Цель(id: $0) } }, set: { разделДля = $0?.id })) { цель in
            ВыборРаздела(справочники: модель.справочники, выбрано: { ключ in
                if let i = модель.строки.firstIndex(where: { $0.id == цель.id }) { модель.строки[i].раздел = ключ }
                разделДля = nil
            })
        }
        .sheet(isPresented: $разделВсем) {
            ВыборРаздела(справочники: модель.справочники, выбрано: { ключ in
                модель.разделВсем(ключ)
                разделВсем = false
                показать(тК("imp_cat_done"))
            })
        }
        .alert(тК("imp_markup_t"), isPresented: $наценкаОткрыта) {
            TextField("15", text: $наценка)
                .keyboardType(.numbersAndPunctuation)
            Button(тК("imp_markup_apply")) {
                let число = Double(наценка.replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespaces))
                наценка = ""
                if let число {
                    модель.наценка(число)
                    let вид = число == число.rounded() ? String(Int(число)) : String(число)
                    показать(тК("imp_markup_done").replacingOccurrences(of: "{n}", with: вид))
                }
            }
            Button(ИмпортText.т("close"), role: .cancel) { наценка = "" }
        } message: {
            Text(тК("imp_markup_s"))
        }
        .overlay(alignment: .bottom) {
            if let плашка { ПлашкаКошелька(текст: плашка).padding(.bottom, 70) }
        }
        .modifier(ОкнаИмпорта(модель: модель, открыть: открыть))
    }

    /// aiBulk*: наценка ко всем ценам, раздел и состояние всем строкам.
    private var массово: some View {
        Menu {
            Button {
                наценкаОткрыта = true
            } label: {
                Label(тК("imp_markup_t"), systemImage: "percent")
            }
            Button {
                разделВсем = true
            } label: {
                Label(тК("imp_cat_all"), systemImage: "square.grid.2x2")
            }
            Button {
                модель.состояниеВсем("new")
                показать(тК("imp_cond_done"))
            } label: {
                Label(тК("imp_cond_new"), systemImage: "sparkles")
            }
            Button {
                модель.состояниеВсем("used")
                показать(тК("imp_cond_done"))
            } label: {
                Label(тК("imp_cond_used"), systemImage: "arrow.3.trianglepath")
            }
        } label: {
            Label(тК("imp_bulk"), systemImage: "slider.horizontal.3")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.акцент)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
        .disabled(модель.строки.isEmpty)
    }

    private func показать(_ текст: String) {
        withAnimation { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            withAnimation { плашка = nil }
        }
    }

    private var сводка: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(т("rv_n", ["n": String(модель.строки.count)]))
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 6)
                МеткаБизнеса(текст: значок)
                Button(т("rv_redo")) { модель.заново() }
                    .font(.system(size: 13, weight: .semibold))
            }
            Text(т("rv_sum", ["s": СделкиФормат.тенге(модель.сумма)]))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    private var значок: String {
        if модель.изСсылок { return т("rv_link") }
        guard модель.сИИ else { return т("rv_local") }
        if let осталось = модель.осталосьИИ { return т("rv_ai_left", ["n": String(осталось)]) }
        return т("rv_ai")
    }

    private var панель: some View {
        VStack(spacing: 8) {
            if let ошибка = модель.ошибкаПубликации {
                ЗаметкаБизнеса(ошибка, тон: .плохо, значок: "exclamationmark.triangle")
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(т("rv_sel", ["n": String(модель.выбранные.count), "l": String(модель.строки.count)]))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(СделкиФормат.тенге(модель.суммаВыбранных))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .monospacedDigit()
                }
                Spacer(minLength: 6)
                Button {
                    модель.опубликовать()
                } label: {
                    HStack(spacing: 6) {
                        if модель.публикуем != nil { SiteSpinner.белый }
                        Text(подписьКнопки)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if модель.публикуем == nil {
                            Image(systemName: "arrow.right")
                                .flipsForRightToLeftLayoutDirection(true)
                                .font(.system(size: 14, weight: .bold))
                                .accessibilityHidden(true)
                        }
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Theme.акцент, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(модель.выбранные.isEmpty || модель.публикуем != nil)
                .opacity(модель.выбранные.isEmpty ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var подписьКнопки: String {
        if let идёт = модель.публикуем { return идёт }
        return модель.ошибкаПубликации == nil ? т("rv_pub") : т("pub_continue")
    }
}

/// Строка на проверку (_aiRowHTML): галочка, фото, название, бренд, категория, цена, состояние, «Характеристики и
/// описание».
private struct СтрокаПроверки: View {
    @Binding var строка: СтрокаИмпорта
    let имяРаздела: String
    let выбратьРаздел: () -> Void
    let убрать: () -> Void

    @State private var подробно = false

    private func т(_ ключ: String) -> String { ИмпортText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    строка.выбрана.toggle()
                } label: {
                    Image(systemName: строка.выбрана ? "checkmark.square.fill" : "square")
                        .font(.system(size: 21))
                        .foregroundStyle(строка.выбрана ? Theme.акцент : Theme.текстВторой)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(т("rv_pick"))
                .accessibilityValue(строка.выбрана ? т("a11y_selected") : "")
                фото
                VStack(alignment: .leading, spacing: 6) {
                    поле(т("rv_title"), $строка.название)
                    поле(т("rv_brand"), $строка.бренд)
                }
                Button(role: .destructive, action: убрать) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 28, height: 28)
                        .background(Theme.поверхность2, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(т("rv_del"))
            }
            HStack(spacing: 8) {
                Button(action: выбратьРаздел) {
                    HStack(spacing: 4) {
                        Text(имяРаздела)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .accessibilityHidden(true)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстПункта)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.фонПункта, in: Capsule())
                    .overlay { Capsule().strokeBorder(Theme.рамкаПункта, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(т("rv_cat")): \(имяРаздела)")
                TextField(т("rv_price"), text: $строка.цена)
                    .keyboardType(.numberPad)
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.trailing)
                    .padding(8)
                    .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                    .frame(maxWidth: 140)
                    .onChange(of: строка.цена) { _, новое in
                        let цифры = String(новое.filter { $0.isASCII && $0.isNumber }.prefix(12))
                        if цифры != новое { строка.цена = цифры }
                    }
                Text("₸")
                    .foregroundStyle(Theme.текстВторой)
            }
            HStack(spacing: 8) {
                Picker("", selection: $строка.состояние) {
                    Text(т("used")).tag("used")
                    Text(т("new")).tag("new")
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
                Text(строка.готова ? т("rv_ok") : т("rv_warn"))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(строка.готова ? КраскаОбъявлений.хорошоТекст : КраскаОбъявлений.предупреждениеТекст)
                Spacer(minLength: 0)
            }
            DisclosureGroup(isExpanded: $подробно) {
                VStack(spacing: 6) {
                    поле(т("spec_cpu"), $строка.cpu)
                    поле(т("spec_gpu"), $строка.gpu)
                    поле(т("spec_ram"), $строка.ram)
                    поле(т("spec_storage"), $строка.storage)
                    поле(т("spec_year"), $строка.year)
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $строка.описание)
                            .font(.system(size: 14))
                            .frame(minHeight: 90)
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Theme.поверхность2,
                                        in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                        if строка.описание.isEmpty {
                            Text(т("rv_desc"))
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.текстВторой)
                                .padding(10)
                                .allowsHitTesting(false)
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(т("rv_more"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
            }
        }
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(строка.готова ? Theme.линия : КраскаОбъявлений.предупреждениеКромка, lineWidth: 1.5)
        }
        .opacity(строка.выбрана ? 1 : 0.62)
    }

    @ViewBuilder
    private var фото: some View {
        if let первое = строка.фото.first, let адрес = Config.url(первое) {
            AsyncImage(url: адрес.absoluteURL) { фаза in
                if let картинка = фаза.image {
                    картинка.resizable().scaledToFill()
                } else {
                    Theme.поверхность2
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
            .accessibilityHidden(true)
        } else {
            Image(systemName: "photo")
                .foregroundStyle(Theme.текстВторой)
                .frame(width: 56, height: 56)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                .accessibilityHidden(true)
        }
    }

    private func поле(_ подсказка: String, _ значение: Binding<String>) -> some View {
        TextField(подсказка, text: значение)
            .font(.system(size: 14))
            .padding(8)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
    }
}

/// Выбор категории строки (aiCatSelectHTML): корни и их листья, поиск по имени.
private struct ВыборРаздела: View {
    struct Цель: Identifiable {
        let id: UUID
    }

    let справочники: СправочникиПодачи?
    let выбрано: (String) -> Void

    @Environment(\.dismiss) private var закрыть
    @State private var поиск = ""

    var body: some View {
        NavigationStack {
            List {
                if let с = справочники {
                    ForEach(с.корни, id: \.self) { корень in
                        let найденные = отобрать(с, листья(с, корень))
                        if !найденные.isEmpty || совпадает(с.имя(корень)) {
                            Section(с.имя(корень)) {
                                if совпадает(с.имя(корень)) {
                                    строка(с.имя(корень), ключ: корень)
                                }
                                ForEach(найденные, id: \.self) { ключ in
                                    строка(с.имя(ключ), ключ: ключ)
                                }
                            }
                        }
                    }
                }
                Section {
                    строка(ИмпортText.т("cat_other"), ключ: "other")
                }
            }
            .searchable(text: $поиск)
            .navigationTitle(ИмпортText.т("rv_cat"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ИмпортText.т("close")) { закрыть() }
                }
            }
        }
        .tint(Theme.акцент)
    }

    private func строка(_ имя: String, ключ: String) -> some View {
        Button {
            выбрано(ключ)
        } label: {
            Text(имя.isEmpty ? ключ : имя)
                .foregroundStyle(Theme.текст)
        }
    }

    private func совпадает(_ имя: String) -> Bool {
        let запрос = поиск.trimmingCharacters(in: .whitespaces)
        return запрос.isEmpty || имя.localizedCaseInsensitiveContains(запрос)
    }

    private func отобрать(_ с: СправочникиПодачи, _ ключи: [String]) -> [String] {
        ключи.filter { совпадает(с.имя($0)) }
    }

    /// Все листья под корнем (дети без детей), по порядку дерева.
    private func листья(_ с: СправочникиПодачи, _ ключ: String) -> [String] {
        var итог: [String] = []
        var стопка: [String] = (с.разделы[ключ]?.дети ?? []).reversed()
        var шаги = 0
        while let следующий = стопка.popLast(), шаги < 2000 {
            шаги += 1
            let дети = с.разделы[следующий]?.дети ?? []
            if дети.isEmpty {
                итог.append(следующий)
            } else {
                стопка.append(contentsOf: дети.reversed())
            }
        }
        return итог
    }
}

// MARK: - Итог

private struct ИтогИмпорта: View {
    @ObservedObject var модель: ИмпортМодель
    let открыть: (URL) -> Void
    let закрыть: () -> Void

    private func т(_ ключ: String) -> String { ИмпортText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 46))
                        .foregroundStyle(Theme.акцент)
                        .accessibilityHidden(true)
                    Text(т("done_t"))
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                    Text(модель.итог)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .multilineTextAlignment(.center)
                    Text(модель.итогПодробно)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                if !модель.черновики.isEmpty {
                    КарточкаБизнеса(т("drafts"), значок: "tray") {
                        ForEach(модель.черновики) { черновик in
                            HStack(spacing: 10) {
                                Text(черновик.название)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.текст)
                                    .lineLimit(2)
                                Spacer(minLength: 6)
                                Button(т("edit")) {
                                    if let u = Config.страницаСайта("cabinet.php?edit=" + черновик.id) { открыть(u) }
                                }
                                .font(.system(size: 13, weight: .bold))
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                КнопкаБизнеса(подпись: т("open_items")) {
                    if let u = Config.страницаСайта("cabinet?go=items") { открыть(u) }
                }
                КнопкаБизнеса(подпись: т("more_import"), второстепенная: true) { модель.заново() }
            }
            .padding(16)
        }
    }
}


/// _aiLocalCard: разметка столбцов местной таблицы — поле → столбец; правка перестраивает строки и запоминается для
/// этого формата (import_fmt), как у сайта.
private struct РазметкаТаблицы: View {
    @ObservedObject var модель: ИмпортМодель

    @State private var открыта = false

    /// _AI_FLD_ORDER сайта — поля, которые читает разбор приложения.
    private static let поля = ["title", "price", "description", "images", "brand", "condition", "cpu", "ram", "storage",
                               "gpu", "year"]

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var body: some View {
        DisclosureGroup(isExpanded: $открыта) {
            VStack(alignment: .leading, spacing: 8) {
                Text(т(модель.разметкаИзБиблиотеки ? "imp_map_lib" : "imp_map_s"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Self.поля, id: \.self) { поле in
                    HStack {
                        Text(т("fld_" + поле))
                            .font(.system(size: 13.5, weight: поле == "title" || поле == "price" ? .bold : .regular))
                            .foregroundStyle(Theme.текст)
                        Spacer(minLength: 8)
                        Picker(т("fld_" + поле), selection: Binding<Int>(
                            get: { модель.разметка[поле] ?? -1 },
                            set: { модель.сменитьРазметку(поле, $0 < 0 ? nil : $0) })) {
                            Text(т("imp_map_none")).tag(-1)
                            ForEach(Array(модель.колонки.enumerated()), id: \.offset) { номер, подпись in
                                Text(подпись).tag(номер)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.акцент)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Label(т("imp_map_t"), systemImage: "tablecells")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.текст)
        }
        .tint(Theme.текстВторой)
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }
}

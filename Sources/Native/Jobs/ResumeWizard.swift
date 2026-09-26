import SwiftUI
import UIKit
import PhotosUI

/**
 МАСТЕР «РЕЗЮМЕ» И «ВАКАНСИЯ» — СВОИМ ЭКРАНОМ (этап 50). Данные и запросы — ResumeAPI.swift.

 Шаги — как jobWizOpen / _jw2Render сайта:
   · резюме (5): «С чего начнём» (Kliko AI собирает черновик по двум строкам — /api/jobs.php?action=ai_resume, или
     «Заполню сам») → «Кто вы и кем работаете» (фото 3×4, имя, должность, город) → «Условия» (зарплата от, «Готов к
     переезду») → «О себе» (текст, навыки до 20, опыт работы до 15) → «Оформление» (восемь шаблонов JR_TPL и
     «Посмотреть резюме» — свой документ ДокументРезюме);
   · вакансия (3): «Кого ищете» (должность, компания, город) → «Условия» (занятость, опыт, зарплата от–до) → «Описание».
 «Далее» на шаге «кто» доступна, когда есть должность и город (и имя у резюме) — _jw2Sync. Последний шаг — «Опубликовать»
 (create) или сохранение правки (update, из «Моих объявлений» → «Изменить»; у резюме правка начинается со второго шага,
 как у сайта). Отказы — словами сервера: need_verify — «Подача в разделе «Работа» — после верификации» и своё окно
 верификации, limit — «Достигнут предел активных резюме».

 Без номера и вида (ссылка cabinet?add=jobs) — сначала выбор «Резюме / Вакансия».
 */
struct МастерРезюме: View {
    let открыть: (URL) -> Void
    let закрыть: () -> Void
    let номер: String?

    @State private var вид: ВидРаботы?
    @State private var запись = ЗаписьРаботы()
    @State private var шаг = 0
    @State private var загружаем = false
    @State private var ненайдено = false
    @State private var ииРоль = ""
    @State private var ииОпыт = ""
    @State private var ииИдёт = false
    @State private var сохраняем = false
    @State private var сообщение: String? = nil
    @State private var хорошо = false
    @State private var нужнаВерификация = false
    @State private var верификация = false
    @State private var готово: String? = nil
    @State private var предпросмотр = false
    @State private var фотоЭлемент: PhotosPickerItem? = nil
    @State private var фотоГрузится = false
    @State private var новыйНавык = ""
    @State private var новаяДолжность = ""
    @State private var новаяКомпания = ""
    @State private var новыйПериод = ""

    init(вид: ВидРаботы?, номер: String?, открыть: @escaping (URL) -> Void, закрыть: @escaping () -> Void) {
        self.открыть = открыть
        self.закрыть = закрыть
        self.номер = номер
        _вид = State(initialValue: вид)
        var начальная = ЗаписьРаботы()
        начальная.вид = вид ?? .резюме
        _запись = State(initialValue: начальная)
    }

    private func т(_ ключ: String) -> String { РезюмеText.т(ключ) }
    private func т(_ ключ: String, _ з: [String: String]) -> String { РезюмеText.т(ключ, з) }

    private var резюме: Bool { запись.вид == .резюме }
    private var шагов: Int { резюме ? 5 : 3 }
    /// Шаг без «С чего начнём» у резюме (a = step-1 сайта).
    private var содержательный: Int { резюме ? шаг - 1 : шаг }

    var body: some View {
        NavigationStack {
            Group {
                if let готово {
                    итог(готово)
                } else if загружаем {
                    ЗагрузкаБизнеса()
                } else if ненайдено {
                    ПустоСайта(значок: "doc.questionmark", заголовок: т("not_found"), кнопка: т("retry"),
                               действие: { Task { await загрузить() } })
                } else if вид == nil {
                    выбор
                } else {
                    мастер
                }
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(вид == nil ? т("pick_q") : (резюме ? т("hov_resume") : т("hov_vacancy")))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                }
            }
        }
        .tint(Theme.акцент)
        .task { await загрузить() }
        .sheet(isPresented: $верификация) {
            ЛистВерификации(открыть: открыть)
        }
        .sheet(isPresented: $предпросмотр) {
            ПредпросмотрРезюме(запись: запись, шаблон: $запись.шаблон)
        }
        .onChange(of: фотоЭлемент) { _, элемент in
            guard let элемент else { return }
            загрузитьФото(элемент)
        }
    }

    // MARK: - Загрузка своей записи (jobsMineEdit)

    private func загрузить() async {
        guard let номер, !загружаем, запись.должность.isEmpty else { return }
        загружаем = true
        ненайдено = false
        let найдена = await РезюмеAPI.запись(номер)
        загружаем = false
        guard let найдена else {
            ненайдено = true
            return
        }
        запись = найдена
        вид = найдена.вид
        шаг = найдена.вид == .резюме ? 1 : 0
    }

    // MARK: - Выбор вида

    private var выбор: some View {
        ScrollView {
            VStack(spacing: 12) {
                плиткаВида(.резюме, значок: "person.text.rectangle", т("hov_resume"), т("pick_resume_s"))
                плиткаВида(.вакансия, значок: "briefcase", т("hov_vacancy"), т("pick_vacancy_s"))
            }
            .padding(16)
        }
    }

    private func плиткаВида(_ новый: ВидРаботы, значок: String, _ заголовок: String, _ подпись: String) -> some View {
        Button {
            var чистая = ЗаписьРаботы()
            чистая.вид = новый
            запись = чистая
            шаг = 0
            withAnimation(ДвижениеСайта.шаг) { вид = новый }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: значок)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 46, height: 46)
                    .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(заголовок)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                    Text(подпись)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .flipsForRightToLeftLayoutDirection(true)
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Мастер

    private var мастер: some View {
        VStack(spacing: 0) {
            прогресс
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    шагВид
                    if let сообщение {
                        ЗаметкаБизнеса(сообщение, тон: хорошо ? .хорошо : .предупреждение,
                                       значок: хорошо ? "checkmark.circle" : "exclamationmark.circle")
                    }
                    if нужнаВерификация {
                        КнопкаБизнеса(подпись: т("verify"), второстепенная: true) { верификация = true }
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            низ
        }
    }

    /// .rw2-prog: полоски шагов и «Шаг i из n».
    private var прогресс: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<шагов, id: \.self) { i in
                    Capsule()
                        .fill(i <= шаг ? Theme.акцент : Theme.линия)
                        .frame(height: 4)
                }
            }
            Text(т("step", ["i": String(шаг + 1), "n": String(шагов)]))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var шагВид: some View {
        if резюме && шаг == 0 {
            шагИИ
        } else {
            switch содержательный {
            case 0: шагКто
            case 1: шагУсловия
            case 2: шагТекст
            default: шагОформление
            }
        }
    }

    private func вопрос(_ заголовок: String, _ подпись: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(заголовок)
                .font(.system(size: 21, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            Text(подпись)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func поле(_ подпись: String, _ значение: Binding<String>, подсказка: String = "",
                      числа: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(подпись)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
            TextField(подсказка, text: значение)
                .keyboardType(числа ? .numberPad : .default)
                .font(.system(size: 16))
                .padding(12)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1)
                }
        }
    }

    private func текстовоеПоле(_ значение: Binding<String>, высота: CGFloat) -> some View {
        TextEditor(text: значение)
            .font(.system(size: 15))
            .frame(minHeight: высота)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1)
            }
    }

    // MARK: Шаг «С чего начнём» (резюме)

    private var шагИИ: some View {
        VStack(alignment: .leading, spacing: 14) {
            вопрос(т("jw_ai_q"), т("jw_ai_s"))
            поле(т("jw_ai_role"), $ииРоль, подсказка: т("jw_ai_role_ph"))
            VStack(alignment: .leading, spacing: 5) {
                Text(т("jw_ai_exp"))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                текстовоеПоле($ииОпыт, высота: 90)
            }
            КнопкаБизнеса(подпись: т("jw_ai_go"), занято: ииИдёт) { собратьИИ() }
            Button(т("jw_ai_skip")) {
                сообщение = nil
                withAnimation(ДвижениеСайта.шаг) { шаг = 1 }
            }
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
        }
    }

    /// _jw2AI.
    private func собратьИИ() {
        let роль = ииРоль.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !роль.isEmpty else {
            показать(т("jw_ai_need"), хорошо: false)
            return
        }
        ииИдёт = true
        Task {
            let итог = await РезюмеAPI.собрать(роль: роль, опыт: ииОпыт)
            ииИдёт = false
            guard let итог else {
                показать(т("jw_ai_fail"), хорошо: false)
                return
            }
            if !итог.title.isEmpty { запись.должность = итог.title }
            if !итог.about.isEmpty { запись.оСебе = итог.about }
            if !итог.skills.isEmpty { запись.навыки = итог.skills.map { НавыкРезюме(название: $0, уровень: "") } }
            if запись.должность.isEmpty { запись.должность = роль }
            withAnimation(ДвижениеСайта.шаг) { шаг = 1 }
            показать(т("jw_ai_ok"), хорошо: true)
        }
    }

    // MARK: Шаг «Кто»

    private var шагКто: some View {
        VStack(alignment: .leading, spacing: 14) {
            вопрос(резюме ? т("jw_who_res") : т("jw_who_vac"), резюме ? т("jw_who_res_s") : т("jw_who_vac_s"))
            if резюме {
                фото
                поле(т("jw_name"), $запись.имя, подсказка: т("jw_name_ph"))
            }
            поле(т("jw_title"), $запись.должность, подсказка: резюме ? т("jw_title_ph_res") : т("jw_title_ph_vac"))
            if !резюме {
                поле(т("jw_company"), $запись.компания, подсказка: т("jw_company_ph"))
            }
            поле(т("jw_city"), $запись.город, подсказка: т("jw_city_ph"))
        }
    }

    private var фото: some View {
        PhotosPicker(selection: $фотоЭлемент, matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .fill(Theme.поверхность)
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(Theme.линия, style: StrokeStyle(lineWidth: 1.5, dash: запись.фото.isEmpty ? [5] : []))
                if !запись.фото.isEmpty, let адрес = Config.url(запись.фото) {
                    AsyncImage(url: адрес.absoluteURL) { фаза in
                        if let картинка = фаза.image {
                            картинка.resizable().scaledToFill()
                        } else {
                            SiteSpinner()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 22))
                        Text(т("jw_photo"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(Theme.текстВторой)
                }
                if фотоГрузится {
                    Color.black.opacity(0.3)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    SiteSpinner.белый
                }
            }
            .frame(width: 96, height: 128)
        }
        .accessibilityLabel(т("jw_photo"))
    }

    private func загрузитьФото(_ элемент: PhotosPickerItem) {
        фотоГрузится = true
        Task {
            defer {
                фотоГрузится = false
                фотоЭлемент = nil
            }
            guard let данные = try? await элемент.loadTransferable(type: Data.self),
                  let адрес = await РезюмеAPI.загрузитьФото(данные) else {
                показать(т("jw_photo_fail"), хорошо: false)
                return
            }
            запись.фото = адрес
        }
    }

    // MARK: Шаг «Условия»

    private static let занятости: [String] = ["full", "part", "shift", "remote", "internship"]
    private static let опыты: [String] = ["Без опыта", "1–3 года", "3–5 лет", "5+ лет"]

    private var шагУсловия: some View {
        VStack(alignment: .leading, spacing: 14) {
            вопрос(т("jw_terms"), резюме ? т("jw_terms_res_s") : т("jw_terms_vac_s"))
            if !резюме {
                подписьГруппы(т("jw_emp"))
                чипы(Self.занятости, выбрано: запись.занятость, подпись: { т("emp_" + $0) }) { запись.занятость = $0 }
                подписьГруппы(т("jw_exp"))
                чипы(Self.опыты, выбрано: запись.опытНужен, подпись: { т("exp_" + $0) }) { запись.опытНужен = $0 }
            }
            HStack(spacing: 10) {
                поле(т("jw_sal_min"), цифры($запись.зарплатаОт), подсказка: "250000", числа: true)
                if !резюме {
                    поле(т("jw_sal_max"), цифры($запись.зарплатаДо), подсказка: "400000", числа: true)
                }
            }
            if резюме {
                Toggle(т("jw_relocate"), isOn: $запись.переезд)
                    .font(.system(size: 15, weight: .semibold))
                    .tint(Theme.акцент)
                    .padding(12)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
        }
    }

    /// Только цифры в поле зарплаты (parseInt сайта).
    private func цифры(_ значение: Binding<String>) -> Binding<String> {
        Binding(get: { значение.wrappedValue },
                set: { новое in значение.wrappedValue = String(новое.filter { $0.isASCII && $0.isNumber }.prefix(10)) })
    }

    private func подписьГруппы(_ текст: String) -> some View {
        Text(текст)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Theme.текст)
    }

    /// .rw2-chips: чипы с одним выбранным.
    private func чипы(_ значения: [String], выбрано: String, подпись: @escaping (String) -> String,
                      выбрать: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(значения, id: \.self) { значение in
                    let включён = значение == выбрано
                    Button {
                        выбрать(значение)
                    } label: {
                        Text(подпись(значение))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(включён ? Color.white : Theme.текстПункта)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(включён ? Theme.акцент : Theme.фонПункта, in: Capsule())
                            .overlay { Capsule().strokeBorder(включён ? Color.clear : Theme.рамкаПункта, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(включён ? [.isSelected] : [])
                }
            }
        }
    }

    // MARK: Шаг «О себе» / «Описание»

    private var шагТекст: some View {
        VStack(alignment: .leading, spacing: 14) {
            вопрос(резюме ? т("jw_about") : т("jw_desc"), резюме ? т("jw_about_s") : т("jw_desc_s"))
            if резюме {
                текстовоеПоле($запись.оСебе, высота: 130)
                навыки
                опыт
            } else {
                текстовоеПоле($запись.описание, высота: 190)
            }
        }
    }

    private var навыки: some View {
        VStack(alignment: .leading, spacing: 8) {
            подписьГруппы(т("jw_skills"))
            if !запись.навыки.isEmpty {
                ОбтеканиеЧипов(интервал: 6) {
                    ForEach(запись.навыки) { навык in
                        HStack(spacing: 4) {
                            Text(навык.название)
                                .font(.system(size: 13.5, weight: .semibold))
                            Button {
                                запись.навыки.removeAll { $0.id == навык.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(т("delete"))
                        }
                        .foregroundStyle(Theme.текстПункта)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.фонПункта, in: Capsule())
                        .overlay { Capsule().strokeBorder(Theme.рамкаПункта, lineWidth: 1) }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField(т("jw_skill_ph"), text: $новыйНавык)
                    .submitLabel(.done)
                    .onSubmit { добавитьНавык() }
                    .padding(10)
                    .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                Button(т("jw_add")) { добавитьНавык() }
                    .buttonStyle(.bordered)
                    .disabled(запись.навыки.count >= 20)
            }
        }
    }

    /// _jw2SkillAdd: до 20 навыков, 50 знаков.
    private func добавитьНавык() {
        let имя = новыйНавык.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !имя.isEmpty, запись.навыки.count < 20 else { return }
        запись.навыки.append(НавыкРезюме(название: String(имя.prefix(50)), уровень: ""))
        новыйНавык = ""
    }

    private var опыт: some View {
        VStack(alignment: .leading, spacing: 8) {
            подписьГруппы(т("jw_exp_work"))
            ForEach(запись.опыт) { место in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(место.должность)
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(Theme.текст)
                        let строка = [место.компания, место.период].filter { !$0.isEmpty }.joined(separator: " · ")
                        if !строка.isEmpty {
                            Text(строка)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Theme.текстВторой)
                        }
                    }
                    Spacer(minLength: 6)
                    Button {
                        запись.опыт.removeAll { $0.id == место.id }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(КраскаОбъявлений.плохоТекст)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(т("delete"))
                }
                .padding(12)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            VStack(spacing: 8) {
                поле(т("jw_exp_pos"), $новаяДолжность)
                поле(т("jw_exp_co"), $новаяКомпания)
                поле(т("jw_exp_per"), $новыйПериод, подсказка: т("jw_exp_per"))
                КнопкаБизнеса(подпись: т("jw_add"), второстепенная: true) { добавитьОпыт() }
                    .disabled(новаяДолжность.trimmingCharacters(in: .whitespaces).isEmpty || запись.опыт.count >= 15)
            }
            .padding(12)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
    }

    /// _jw2ExpAdd: до 15 мест; 80 / 80 / 40 знаков.
    private func добавитьОпыт() {
        let должность = новаяДолжность.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !должность.isEmpty, запись.опыт.count < 15 else { return }
        запись.опыт.append(ОпытРезюме(должность: String(должность.prefix(80)),
                                      компания: String(новаяКомпания.trimmingCharacters(in: .whitespaces).prefix(80)),
                                      период: String(новыйПериод.trimmingCharacters(in: .whitespaces).prefix(40)),
                                      описание: ""))
        новаяДолжность = ""
        новаяКомпания = ""
        новыйПериод = ""
    }

    // MARK: Шаг «Оформление» (резюме)

    private var шагОформление: some View {
        VStack(alignment: .leading, spacing: 14) {
            вопрос(т("jw_tpl"), т("jw_tpl_s"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                ForEach(ШаблонРезюме.все) { ш in
                    let выбран = ш.id == запись.шаблон
                    Button {
                        запись.шаблон = ш.id
                    } label: {
                        VStack(spacing: 6) {
                            LinearGradient(colors: [Color(uiColor: Theme.hex(ш.акцент)), Color(uiColor: Theme.hex(ш.акцент2))],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                                .frame(height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                            Text(ш.название)
                                .font(.system(size: 12.5, weight: .semibold, design: ш.serif ? .serif : .default))
                                .foregroundStyle(Theme.текст)
                        }
                        .padding(8)
                        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                                .strokeBorder(выбран ? Theme.акцент : Theme.линия, lineWidth: выбран ? 2 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(выбран ? [.isSelected] : [])
                }
            }
            ДокументРезюме(запись: запись, шаблон: ШаблонРезюме.по(запись.шаблон))
                .shadow(color: Color.black.opacity(0.1), radius: 8, y: 3)
                .allowsHitTesting(false)
            КнопкаБизнеса(подпись: т("jw_tpl_see"), второстепенная: true) { предпросмотр = true }
        }
    }

    // MARK: - Низ: «Назад» / «Далее»

    /// _jw2Sync: на шаге «кто» нужны должность и город (и имя у резюме).
    private var можноДальше: Bool {
        guard !(резюме && шаг == 0) else { return true }
        guard содержательный == 0 else { return true }
        let есть: (String) -> Bool = { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !есть(запись.должность) || !есть(запись.город) { return false }
        return !резюме || есть(запись.имя)
    }

    private var последний: Bool { шаг >= шагов - 1 }

    private var низ: some View {
        HStack(spacing: 10) {
            Button {
                сообщение = nil
                if шаг > 0 {
                    withAnimation(ДвижениеСайта.шаг) { шаг -= 1 }
                } else if номер == nil {
                    withAnimation(ДвижениеСайта.шаг) { вид = nil }
                } else {
                    закрыть()
                }
            } label: {
                Text(т("back"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.акцент)
                    .padding(.vertical, 13)
                    .padding(.horizontal, 18)
                    .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            Button {
                дальше()
            } label: {
                HStack(spacing: 6) {
                    if сохраняем { SiteSpinner.белый }
                    Text(последний ? (номер == nil ? т("publish") : т("save")) : т("next"))
                        .font(.system(size: 15, weight: .bold))
                    if !последний {
                        Image(systemName: "chevron.right")
                            .flipsForRightToLeftLayoutDirection(true)
                            .font(.system(size: 13, weight: .bold))
                            .accessibilityHidden(true)
                    }
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Theme.акцент, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!можноДальше || сохраняем)
            .opacity(можноДальше ? 1 : 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func дальше() {
        сообщение = nil
        нужнаВерификация = false
        if !последний {
            withAnimation(ДвижениеСайта.шаг) { шаг += 1 }
            return
        }
        сохранить()
    }

    /// _jw2Save.
    private func сохранить() {
        guard !сохраняем else { return }
        сохраняем = true
        Task {
            let итог = await РезюмеAPI.сохранить(запись, номер: номер)
            сохраняем = false
            switch итог {
            case .готово:
                if номер != nil {
                    готово = т("jw_ok_upd")
                } else {
                    готово = резюме ? т("jw_ok_res") : т("jw_ok_vac")
                }
                UIAccessibility.post(notification: .announcement, argument: готово ?? "")
            case .нужнаВерификация(let текст):
                показать(текст, хорошо: false)
                нужнаВерификация = true
            case .предел(let текст), .ошибка(let текст):
                показать(текст, хорошо: false)
            case .нуженВход:
                показать(CabinetText.т("signed_out"), хорошо: false)
            }
        }
    }

    private func показать(_ текст: String, хорошо: Bool) {
        withAnimation(ДвижениеСайта.появление) {
            сообщение = текст
            self.хорошо = хорошо
        }
        UIAccessibility.post(notification: .announcement, argument: текст)
    }

    // MARK: - Итог

    private func итог(_ текст: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.акцент)
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
            Text(т("done_after"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
            Spacer()
            КнопкаБизнеса(подпись: БизнесText.т("close")) { закрыть() }
        }
        .padding(20)
    }
}

/// Чипы с переносом строк (навыки .jw-rows сайта).
struct ОбтеканиеЧипов: Layout {
    var интервал: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ширина = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var высотаСтроки: CGFloat = 0
        var шире: CGFloat = 0
        for вид in subviews {
            let размер = вид.sizeThatFits(.unspecified)
            if x > 0 && x + размер.width > ширина {
                x = 0
                y += высотаСтроки + интервал
                высотаСтроки = 0
            }
            x += размер.width + интервал
            высотаСтроки = max(высотаСтроки, размер.height)
            шире = max(шире, x - интервал)
        }
        return CGSize(width: ширина.isFinite ? ширина : шире, height: y + высотаСтроки)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var высотаСтроки: CGFloat = 0
        for вид in subviews {
            let размер = вид.sizeThatFits(.unspecified)
            if x > bounds.minX && x + размер.width > bounds.maxX {
                x = bounds.minX
                y += высотаСтроки + интервал
                высотаСтроки = 0
            }
            вид.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(размер))
            x += размер.width + интервал
            высотаСтроки = max(высотаСтроки, размер.height)
        }
    }
}

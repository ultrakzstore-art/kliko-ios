import SwiftUI
import UIKit

/**
 «СОПОСТАВЛЕНИЕ ГРУПП 1С С РАЗДЕЛАМИ» И «ПРИМЕРЫ КОДА ДЛЯ 1С» — СВОИМИ ЭКРАНАМИ (экран интеграций, ЭкранИнтеграций).

 Сайт (js/cabinet-business.min.js):
   · c1Keys: группы из обмена — ключи c1_groups {код группы: название}; если есть c1_used (группы, где реально лежат
     товары) и среди них есть известные — только они;
   · intg1cOpen / c1Rows: лист «Разделы для номенклатуры», черновик — копия c1_map {код группы: slug раздела};
     «только несопоставленные», «Подставить подсказки» (c1Suggest по названию), у строки — «выбрать раздел» и «Убрать»;
   · intg1cPick / c1Res: второй лист — поиск по пути раздела (c1Norm, до 60 строк), без запроса — корни дерева;
     разделы — c1Flat по CAB_CATS (= MK_CATS, у приложения ЗагрузкаКаталогаПоиска и ДеревоКатегорийСайта), путь «A / B»;
   · intg1cSave: POST cabinet.php?action=intg_1c_map {csrf, map: черновик} → ok; тост c1_saved, иначе ulxErr или c1_savefail.
 Отдельного «не выгружать» у сервера нет: группа без раздела и есть невыгружаемая — её товары не заводятся и ждут (c1_gap).
 Поэтому «Не выгружать» в выборе раздела приложения — это «Убрать» сайта: пустое значение, группа уходит из карты.

 Примеры кода: intg1cBackHTML (обратный ход: адрес …/v1/orders/{id}, поля, функция на языке 1С с именем хоста сайта) и
 intgDocsHTML (curl …/ping с ключом). Сайт подставляет ВАШ_КЛЮЧ; приложение — ключ, выпущенный в этом окне (целиком его
 знает только момент выпуска), скрытый точками с кнопкой «Показать ключ». Копируется всегда настоящее значение.
 */
struct ГруппаОбмена1С: Identifiable, Equatable {
    let id: String
    let имя: String
}

/// Раздел Клико для группы 1С — запись c1Flat сайта.
struct РазделДляГруппы1С: Identifiable, Equatable {
    let id: String
    let имя: String
    /// «Корень / … / Раздел» — как c1Path сайта.
    let путь: String
    let родитель: String?
    let естьДети: Bool
    /// c1Norm(name) и c1Norm(path): заранее, чтобы подсказки и поиск не считали их на каждой строке.
    let нормаИмени: String
    let нормаПути: String
}

enum Подбор1С {
    /// c1Norm: нижний регистр, ё → е, всё кроме a-z, а-я и цифр — пробел (подряд идущие — один), края обрезаны.
    static func норма(_ строка: String) -> String {
        let нижняя = строка.lowercased().replacingOccurrences(of: "ё", with: "е")
        var итог = String.UnicodeScalarView()
        var былПробел = false
        for знак in нижняя.unicodeScalars {
            let код = знак.value
            let латиница = код >= 0x61 && код <= 0x7A
            let кириллица = код >= 0x430 && код <= 0x44F
            let цифра = код >= 0x30 && код <= 0x39
            if латиница || кириллица || цифра {
                итог.append(знак)
                былПробел = false
            } else if !былПробел {
                итог.append(" ")
                былПробел = true
            }
        }
        return String(итог).trimmingCharacters(in: .whitespaces)
    }

    /// c1Flat: обход дерева в глубину, путь через « / ».
    static func разделы(_ дерево: ДеревоКатегорийСайта) -> [РазделДляГруппы1С] {
        var итог: [РазделДляГруппы1С] = []
        func обойти(_ ключ: String, _ выше: String, _ глубина: Int) {
            guard глубина < 12 else { return }
            let имя = дерево.имя(ключ)
            let путь = выше.isEmpty ? имя : выше + " / " + имя
            let дети = дерево.подразделы(ключ)
            итог.append(РазделДляГруппы1С(id: ключ, имя: имя, путь: путь, родитель: дерево.родитель(ключ),
                                          естьДети: !дети.isEmpty, нормаИмени: норма(имя), нормаПути: норма(путь)))
            for ребёнок in дети {
                обойти(ребёнок, путь, глубина + 1)
            }
        }
        for корень in дерево.корни {
            обойти(корень, "", 0)
        }
        return итог
    }

    /// c1Suggest: последняя часть названия группы после «/»; совпадение — 100, вхождение — 60, общие слова — 20 за слово.
    static func подсказка(_ группа: String, в разделы: [РазделДляГруппы1С]) -> String {
        let хвост = группа.components(separatedBy: "/").last ?? группа
        let искомое = норма(хвост)
        guard искомое.count >= 3 else { return "" }
        let слова = искомое.split(separator: " ").map(String.init).filter { $0.count > 2 }
        var лучший = ""
        var балл = 0
        for раздел in разделы {
            let имя = раздел.нормаИмени
            guard !имя.isEmpty else { continue }
            var очки = 0
            if имя == искомое {
                очки = 100
            } else if искомое.contains(имя) || имя.contains(искомое) {
                очки = 60
            } else {
                очки = 20 * слова.filter { имя.contains($0) }.count
            }
            if очки > балл {
                балл = очки
                лучший = раздел.id
            }
        }
        return балл >= 40 ? лучший : ""
    }

    /// Ключ, скрытый точками: первые шесть знаков (префикс, который и так виден в списке ключей) и «••••••••».
    static func скрыть(_ ключ: String) -> String {
        String(ключ.prefix(6)) + "••••••••"
    }

    /// Функция 1С из intg1cBackHTML — дословно; хост — сайта.
    static func кодОбратногоХода(хост: String) -> String {
        let соединение = "    Соединение = Новый HTTPСоединение(\"" + хост + "\", 443, , , , 30,"
        let строки: [String] = [
            "Функция СообщитьСайтуОДокументе(ИдЗаказаНаСайте, Статус, НомерДок, ДатаДок, Токен) Экспорт",
            "",
            "    Заголовки = Новый Соответствие;",
            "    Заголовки.Вставить(\"Authorization\", \"Bearer \" + Токен);",
            "    Заголовки.Вставить(\"Content-Type\",  \"application/json\");",
            "",
            "    Тело = Новый Структура;",
            "    Тело.Вставить(\"status\",   Статус);          // confirmed | paid | shipped | done | cancelled",
            "    Тело.Вставить(\"doc_no\",   НомерДок);        // номер вашего документа",
            "    Тело.Вставить(\"doc_date\", Формат(ДатаДок, \"ДФ=yyyy-MM-dd\"));",
            "",
            "    Запись = Новый ЗаписьJSON;",
            "    Запись.УстановитьСтроку();",
            "    ЗаписатьJSON(Запись, Тело);",
            "    ТелоСтрокой = Запись.Закрыть();",
            "",
            соединение,
            "        Новый ЗащищенноеСоединениеOpenSSL);",
            "    Запрос = Новый HTTPЗапрос(\"/api/v1/orders/\" + ИдЗаказаНаСайте, Заголовки);",
            "    Запрос.УстановитьТелоИзСтроки(ТелоСтрокой, КодировкаТекста.UTF8);",
            "",
            "    Попытка",
            "        Ответ = Соединение.ВызватьHTTPМетод(\"PATCH\", Запрос);",
            "    Исключение",
            "        ЗаписьЖурналаРегистрации(\"Обмен с сайтом\", УровеньЖурналаРегистрации.Ошибка,,,",
            "            ОписаниеОшибки());",
            "        Возврат Ложь;",
            "    КонецПопытки;",
            "",
            "    Если Ответ.КодСостояния <> 200 Тогда",
            "        ЗаписьЖурналаРегистрации(\"Обмен с сайтом\", УровеньЖурналаРегистрации.Предупреждение,,,",
            "            \"Сайт ответил \" + Ответ.КодСостояния + \": \" + Ответ.ПолучитьТелоКакСтроку());",
            "        Возврат Ложь;",
            "    КонецЕсли;",
            "",
            "    Возврат Истина;",
            "",
            "КонецФункции",
        ]
        return строки.joined(separator: "\n")
    }
}

// MARK: - Лист сопоставления

/// intg1cOpen: группы из обмена, у каждой — раздел Клико; «только несопоставленные», подсказки, «Сохранить».
struct ЛистСопоставления1С: View {
    let группы: [ГруппаОбмена1С]
    let карта: [String: String]
    let сохранено: ([String: String]) -> Void

    @Environment(\.dismiss) private var закрыть
    @State private var черновик: [String: String] = [:]
    @State private var начато = false
    @State private var толькоПустые = false
    @State private var разделы: [РазделДляГруппы1С]? = nil
    @State private var пути: [String: String] = [:]
    @State private var подсказки: [String: String] = [:]
    @State private var сбойРазделов = false
    @State private var выбор: ГруппаОбмена1С? = nil
    @State private var сохраняем = false
    @State private var спросить = false
    @State private var плашка: String? = nil
    @State private var скрытие: Task<Void, Never>? = nil
    @State private var сохранилось = 0
    @State private var отказ = 0

    private func т(_ ключ: String) -> String { Интеграции1СText.т(ключ) }

    private var изменено: Bool { начато && черновик != исходная }

    /// c1_map только по группам листа — сравнение черновика с ней.
    private var исходная: [String: String] {
        var итог: [String: String] = [:]
        for г in группы {
            if let slug = карта[г.id], !slug.isEmpty { итог[г.id] = slug }
        }
        return итог
    }

    private var видимые: [ГруппаОбмена1С] {
        толькоПустые ? группы.filter { (черновик[$0.id] ?? "").isEmpty } : группы
    }

    var body: some View {
        NavigationStack {
            Group {
                if группы.isEmpty {
                    ПустоСайта(значок: "square.stack.3d.up.slash", заголовок: т("app_no_groups"), подпись: т("c1_first"))
                } else if разделы == nil && !сбойРазделов {
                    ЗагрузкаБизнеса()
                } else if сбойРазделов {
                    ПустоСайта(значок: "wifi.exclamationmark", заголовок: т("app_cats_fail"), кнопка: т("retry"),
                               действие: { Task { await загрузитьРазделы() } })
                } else {
                    список
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("c1_h"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("pq_cancel")) { уйти() }
                }
            }
            .overlay(alignment: .bottom) {
                if let текст = плашка { ПлашкаКошелька(текст: текст) }
            }
        }
        .tint(Theme.акцент)
        .interactiveDismissDisabled(изменено || сохраняем)
        .откликУспеха(сохранилось)
        .откликПредупреждения(отказ)
        .task {
            if !начато {
                черновик = исходная
                начато = true
            }
            await загрузитьРазделы()
        }
        .sheet(item: $выбор) { группа in
            ЛистВыбораРаздела1С(группа: группа, разделы: разделы ?? [], выбрано: черновик[группа.id] ?? "",
                                подсказка: подсказки[группа.id] ?? "") { slug in
                задать(группа, slug)
                выбор = nil
            }
        }
        .confirmationDialog(т("app_unsaved_t"), isPresented: $спросить, titleVisibility: .visible) {
            Button(т("c1_save")) { сохранить() }
            Button(т("app_discard"), role: .destructive) { закрыть() }
            Button(т("app_stay"), role: .cancel) {}
        } message: {
            Text(т("app_unsaved_s"))
        }
    }

    private var список: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(т("c1_gap"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                инструменты
                VStack(spacing: 0) {
                    let строки = видимые
                    if строки.isEmpty {
                        Text(т("c1_all"))
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.текстВторой)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 22)
                    }
                    ForEach(Array(строки.enumerated()), id: \.element.id) { номер, группа in
                        if номер > 0 {
                            Divider().overlay(Theme.линия)
                        }
                        строка(группа)
                    }
                }
                .padding(.horizontal, 12)
                .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(Theme.линия, lineWidth: 1.5)
                }
                .animation(ДвижениеСайта.вставкаСписка, value: толькоПустые)
            }
            .padding(12)
        }
        .safeAreaInset(edge: .bottom) {
            КнопкаБизнеса(подпись: сохраняем ? т("c1_saving") : т("c1_save"), занято: сохраняем) { сохранить() }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.фонСтраницы)
        }
    }

    private var инструменты: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $толькоПустые) {
                Text(т("c1_only"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
            .toggleStyle(.switch)
            .tint(Theme.акцент)
            .fixedSize()
            Spacer(minLength: 6)
            Button(т("c1_guess")) { подставить() }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.акцент)
        }
    }

    private func строка(_ группа: ГруппаОбмена1С) -> some View {
        let slug = черновик[группа.id] ?? ""
        let пусто = slug.isEmpty
        let подсказка = пусто ? (подсказки[группа.id] ?? "") : ""
        return VStack(alignment: .leading, spacing: 7) {
            Text(группа.имя.isEmpty ? группа.id : группа.имя)
                .font(.system(size: 13, weight: пусто ? .bold : .regular))
                .foregroundStyle(пусто ? Theme.текст : Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Button {
                    выбор = группа
                } label: {
                    HStack(spacing: 6) {
                        Text(пусто ? т("c1_pick") : (пути[slug] ?? slug))
                            .font(.system(size: 13, weight: пусто ? .regular : .semibold))
                            .foregroundStyle(пусто ? Theme.текстВторой : Theme.текст)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.текстВторой)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(пусто ? Color.clear : Theme.оттенокАкцента,
                                in: RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.xs, style: .continuous)
                            .strokeBorder(пусто ? Theme.линия : Theme.акцент,
                                          style: StrokeStyle(lineWidth: 1.5, dash: пусто ? [4, 3] : []))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(т("c1_pick_aria"))
                .accessibilityValue(пусто ? т("app_skip") : (пути[slug] ?? slug))
                if !пусто {
                    Button {
                        задать(группа, "")
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.текстВторой)
                            .frame(width: 30, height: 30)
                            .background(Theme.поверхность2, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(т("c1_clear"))
                }
            }
            if !подсказка.isEmpty {
                Button {
                    задать(группа, подсказка)
                } label: {
                    Label(т("app_suggest").replacingOccurrences(of: "{n}", with: пути[подсказка] ?? подсказка),
                          systemImage: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.акцент)
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.оттенокАкцента, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Действия

    private func загрузитьРазделы() async {
        сбойРазделов = false
        let каталог = await ЗагрузкаКаталогаПоиска.получить()
        guard !каталог.пустой else {
            if разделы == nil { сбойРазделов = true }
            return
        }
        let готовые = Подбор1С.разделы(ДеревоКатегорийСайта(каталог))
        var новыеПути: [String: String] = [:]
        for р in готовые {
            новыеПути[р.id] = р.путь
        }
        var новыеПодсказки: [String: String] = [:]
        for г in группы {
            let slug = Подбор1С.подсказка(г.имя, в: готовые)
            if !slug.isEmpty { новыеПодсказки[г.id] = slug }
        }
        пути = новыеПути
        подсказки = новыеПодсказки
        withAnimation(ДвижениеСайта.появление) { разделы = готовые }
    }

    /// intg1cSet: пусто — группа уходит из черновика.
    private func задать(_ группа: ГруппаОбмена1С, _ slug: String) {
        withAnimation(ДвижениеСайта.выбор) {
            if slug.isEmpty {
                черновик[группа.id] = nil
            } else {
                черновик[группа.id] = slug
            }
        }
        ОткликСайта.выбор()
    }

    /// intg1cGuess: подсказки — только несопоставленным.
    private func подставить() {
        var сколько = 0
        withAnimation(ДвижениеСайта.смена) {
            for г in группы where (черновик[г.id] ?? "").isEmpty {
                if let slug = подсказки[г.id], !slug.isEmpty {
                    черновик[г.id] = slug
                    сколько += 1
                }
            }
        }
        if сколько > 0 {
            ОткликСайта.успех()
            показать(т("c1_guessed").replacingOccurrences(of: "{n}", with: String(сколько)))
        } else {
            ОткликСайта.предупреждение()
            показать(т("c1_noguess"))
        }
    }

    private func уйти() {
        if изменено && !сохраняем {
            спросить = true
        } else if !сохраняем {
            закрыть()
        }
    }

    /// intg1cSave.
    private func сохранить() {
        guard !сохраняем else { return }
        сохраняем = true
        let новая = черновик
        Task { @MainActor in
            do {
                _ = try await ЗапросыКабинета.отправить("cabinet.php?action=intg_1c_map", ["map": новая])
                сохраняем = false
                сохранилось += 1
                сохранено(новая)
                закрыть()
            } catch {
                сохраняем = false
                отказ += 1
                let текст = ЗапросыКабинета.текст(error)
                показать(текст == КабинетПлюсText.т("err_generic") ? т("c1_savefail") : текст)
            }
        }
    }

    private func показать(_ текст: String) {
        withAnimation(ДвижениеСайта.появление) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        скрытие?.cancel()
        скрытие = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(ДвижениеСайта.уход) { плашка = nil }
        }
    }
}

// MARK: - Выбор раздела

/// intg1cPick: поиск по пути; без запроса — дерево (корни, «Подразделы» — внутрь), сверху «Не выгружать» и подсказка.
private struct ЛистВыбораРаздела1С: View {
    let группа: ГруппаОбмена1С
    let разделы: [РазделДляГруппы1С]
    let выбрано: String
    let подсказка: String
    let выбрать: (String) -> Void

    @Environment(\.dismiss) private var закрыть
    @State private var запрос = ""
    @State private var уровень: [String] = []

    private func т(_ ключ: String) -> String { Интеграции1СText.т(ключ) }

    private var текущий: String? { уровень.last }

    private var найденные: [РазделДляГруппы1С] {
        let искомое = Подбор1С.норма(запрос)
        guard !искомое.isEmpty else { return [] }
        var итог: [РазделДляГруппы1С] = []
        for р in разделы where р.нормаПути.contains(искомое) {
            итог.append(р)
            if итог.count >= 60 { break }
        }
        return итог
    }

    private var наУровне: [РазделДляГруппы1С] {
        let родитель = текущий
        return разделы.filter { $0.родитель == родитель }
    }

    private func раздел(_ slug: String) -> РазделДляГруппы1С? {
        разделы.first { $0.id == slug }
    }

    var body: some View {
        NavigationStack {
            List {
                if запрос.trimmingCharacters(in: .whitespaces).isEmpty {
                    дерево
                } else {
                    поиск
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.поверхность.ignoresSafeArea())
            .searchable(text: $запрос, placement: .navigationBarDrawer(displayMode: .always), prompt: т("c1_find"))
            .autocorrectionDisabled()
            .navigationTitle(группа.имя.isEmpty ? т("c1_group") : группа.имя)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("pq_cancel")) { закрыть() }
                }
            }
        }
        .tint(Theme.акцент)
    }

    @ViewBuilder
    private var дерево: some View {
        if текущий == nil {
            Section {
                строкаНеВыгружать
                if !подсказка.isEmpty, подсказка != выбрано, let р = раздел(подсказка) {
                    строкаРаздела(р, значок: "sparkles", внутрь: false)
                }
            }
            .listRowBackground(Theme.поверхность)
        }
        Section {
            if let ключ = текущий, let р = раздел(ключ) {
                Button {
                    withAnimation(ДвижениеСайта.шаг) { _ = уровень.popLast() }
                    ОткликСайта.выбор()
                } label: {
                    Label(р.родитель.flatMap { раздел($0)?.имя } ?? т("app_all_sections"), systemImage: "chevron.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.акцент)
                }
                .buttonStyle(.plain)
                строкаРаздела(р, значок: "checkmark.circle", внутрь: false)
            }
            ForEach(наУровне) { р in
                строкаРаздела(р, значок: nil, внутрь: true)
            }
        } header: {
            Text(текущий.flatMap { раздел($0)?.путь } ?? т("app_all_sections"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.текстВторой)
                .textCase(nil)
        }
        .listRowBackground(Theme.поверхность)
    }

    @ViewBuilder
    private var поиск: some View {
        let строки = найденные
        if строки.isEmpty {
            Text(т("c1_nores"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .listRowBackground(Theme.поверхность)
                .listRowSeparator(.hidden)
        } else {
            ForEach(строки) { р in
                строкаРаздела(р, значок: nil, внутрь: false)
                    .listRowBackground(Theme.поверхность)
            }
        }
    }

    private var строкаНеВыгружать: some View {
        Button {
            выбрать("")
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "nosign")
                    .foregroundStyle(КраскаОбъявлений.плохоТекст)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(т("app_skip"))
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(Theme.текст)
                    Text(т("app_skip_s"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 6)
                if выбрано.isEmpty {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(выбрано.isEmpty ? .isSelected : [])
    }

    /// Строка c1-r: имя жирным, путь серым; «›» справа — войти в подразделы.
    private func строкаРаздела(_ р: РазделДляГруппы1С, значок: String?, внутрь: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                выбрать(р.id)
            } label: {
                HStack(spacing: 10) {
                    if let значок {
                        Image(systemName: значок)
                            .foregroundStyle(Theme.акцент)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(р.имя)
                            .font(.system(size: 14.5, weight: .bold))
                            .foregroundStyle(р.id == выбрано ? Theme.акцент : Theme.текст)
                        if р.путь != р.имя {
                            Text(р.путь)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.текстВторой)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 6)
                    if р.id == выбрано {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.акцент)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(р.id == выбрано ? .isSelected : [])
            if внутрь && р.естьДети {
                Button {
                    withAnimation(ДвижениеСайта.шаг) { уровень.append(р.id) }
                    ОткликСайта.выбор()
                } label: {
                    Image(systemName: "chevron.forward")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(width: 34, height: 34)
                        .background(Theme.поверхность2, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(т("app_inside") + ": " + р.имя)
            }
        }
    }
}

// MARK: - Блок кода

/// .c1-code / .intg-copy-code сайта: моноширинный блок и «Копировать»; показ может быть со скрытым ключом — копируется
/// всегда настоящее.
struct БлокКода1С: View {
    let код: String
    var показ: String? = nil
    /// Длинный код (функция 1С) — прокрутка в обе стороны в рамке 300 pt, как max-height сайта; короткий — с переносом.
    var длинный = false
    let скопировано: () -> Void

    @State private var готово = false
    @State private var сброс: Task<Void, Never>? = nil

    private var текст: some View {
        Text(показ ?? код)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(Theme.текст)
            .textSelection(.enabled)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if длинный {
                ScrollView([.horizontal, .vertical]) {
                    текст
                        .fixedSize(horizontal: true, vertical: true)
                        .padding(12)
                }
                .frame(height: 300)
            } else {
                текст
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            Divider().overlay(Theme.линия)
            Button {
                UIPasteboard.general.string = код
                ОткликСайта.успех()
                скопировано()
                withAnimation(ДвижениеСайта.выбор) { готово = true }
                сброс?.cancel()
                сброс = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(ДвижениеСайта.уход) { готово = false }
                }
            } label: {
                Label(готово ? КабинетПлюсText.т("ig_copied_ok") : КабинетПлюсText.т("ig_copy"),
                      systemImage: готово ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.акцент)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - Примеры кода

/// Карточка «Примеры кода для 1С»: настройки узла обмена, обратный ход (intg1cBackHTML) и проверка связи (intgDocsHTML).
struct ПримерыКода1С: View {
    /// base из intg_state: «/api/v1».
    let база: String
    /// Ключ, выпущенный в этом окне (целиком), или пусто.
    let ключ: String
    let скопировано: () -> Void

    @State private var видно = false

    private func т(_ ключ: String) -> String { Интеграции1СText.т(ключ) }

    private var корень: String {
        let сайт = Config.apiBase.absoluteString
        let путь = база.hasSuffix("/v1") ? String(база.dropLast(3)) : база
        return сайт + путь
    }

    private var ключНастоящий: String { ключ.isEmpty ? т("ig_your_key") : ключ }
    private var ключНаЭкране: String { ключ.isEmpty || видно ? ключНастоящий : Подбор1С.скрыть(ключ) }

    private func настройки(_ значение: String) -> String {
        let строки: [String] = [
            "URL: " + корень + "/1c",
            т("ig_1c_lg") + ": " + т("ig_1c_lgv"),
            т("ig_1c_pw") + ": " + значение,
        ]
        return строки.joined(separator: "\n")
    }

    private func проверка(_ значение: String) -> String {
        let адрес = Config.apiBase.absoluteString + база
        return "curl -H \"Authorization: Bearer " + значение + "\" " + адрес + "/ping"
    }

    var body: some View {
        КарточкаБизнеса(т("app_code_h"), значок: "chevron.left.forwardslash.chevron.right") {
            БлокКода1С(код: настройки(ключНастоящий), показ: настройки(ключНаЭкране), скопировано: скопировано)
            ключСтрока
            Divider()
            обратныйХод
            Divider()
            Text(т("ig_ping_h"))
                .font(.system(size: 13.5, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            БлокКода1С(код: проверка(ключНастоящий), показ: проверка(ключНаЭкране), скопировано: скопировано)
            Text(т("ig_ping_s").replacingOccurrences(of: "{u}", with: Config.apiBase.absoluteString + база + "/meta"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var ключСтрока: some View {
        if ключ.isEmpty {
            Text(т("app_key_none").replacingOccurrences(of: "ВАШ_КЛЮЧ", with: т("ig_your_key")))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .top, spacing: 8) {
                Text(т("app_key_used"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    withAnimation(ДвижениеСайта.смена) { видно.toggle() }
                    ОткликСайта.выбор()
                } label: {
                    Label(видно ? т("app_key_hide") : т("app_key_show"), systemImage: видно ? "eye.slash" : "eye")
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.оттенокАкцента, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var обратныйХод: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(т("ig_back_h"))
                .font(.system(size: 13.5, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Text(т("ig_back_s"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            СтрокаКопирования(текст: корень + "/v1/orders/{id}", скопировано: скопировано)
            Text(т("ig_back_i"))
                .font(.system(size: 12.5, weight: .heavy))
            VStack(spacing: 6) {
                поле("status", "confirmed · paid · shipped · done · cancelled")
                поле("doc_no, doc_date", т("ig_back_f1"))
                поле("items", т("ig_back_f2"))
            }
            БлокКода1С(код: Подбор1С.кодОбратногоХода(хост: Config.apiBase.host ?? "kliko.kz"), длинный: true,
                       скопировано: скопировано)
            Text(т("ig_back_n"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func поле(_ имя: String, _ значение: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(имя)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 8)
            Text(значение)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI
import UIKit

/**
 «МОЁ» — ГОД И ПАРАМЕТРЫ КОЛЁС МАШИНЫ ГАРАЖА.

 Марка и модель — те же страницы, что у «Подойдут ли?» (ВыборМаркиАвтоподбора, ВыборМоделиАвтоподбора: сами только
 кладут ШагАвтоподбора в путь). Год и параметры у «Подойдут ли?» привязаны к окну сверки, поэтому здесь свои:
   · ВыборГодаМоего — годы по поколениям справочника (от новых к старым, рядом имя поколения), «Не помню год»; выбор —
     МодельРедактораМашиныМоего.выбрать: справочник нашёл посадку — назад к машине, нет — параметры вручную;
   · ПараметрыКолёсМоего — шины, PCD, DIA, ET и диаметр диска R «прям по диску» (владелец 16.10.2026): живой диск со
     стандартами, штатные машины одной кнопкой, наборы и сканер (РедакторКолеса, TryOn/WheelEditor.swift); прежние пять
     полей «Подойдут ли?» (ПолеАвтоподбора) — под «Ввести вручную», под полем сразу видно, понято ли набранное; где
     взять — наклейка в проёме двери водителя, инструкция, штатный диск.
 Справочнику уходят только марка, модель и год — без кук и без входа.
 */
struct ВыборГодаМоего: View {
    @ObservedObject var модель: МодельРедактораМашиныМоего
    let марка: String
    let имяМодели: String
    @State private var поколения: [ПоколениеАвто] = []

    init(модель: МодельРедактораМашиныМоего, марка: String, имяМодели: String) {
        self.модель = модель
        self.марка = марка
        self.имяМодели = имяМодели
    }

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    /// Годы от новых к старым: по поколениям модели, а без них — с 1980 по следующий год.
    private var годы: [Int] {
        let следующий = Calendar.current.component(.year, from: Date()) + 1
        var низ = 1980
        var верх = следующий
        let начала = поколения.map(\.с).filter { $0 > 1900 }
        if let первое = начала.min() {
            низ = первое
            let выпускается = поколения.contains { $0.по <= 0 }
            if !выпускается, let последнее = поколения.map(\.по).filter({ $0 > 1900 }).max() {
                верх = min(следующий, max(последнее, низ))
            }
        }
        guard низ <= верх else { return [] }
        return Array((низ...верх).reversed())
    }

    private func поколение(_ год: Int) -> String? {
        поколения.first { $0.с > 1900 && $0.с <= год && ($0.по <= 0 || год <= $0.по) }?.имя
    }

    var body: some View {
        List {
            Section {
                Button { выбрать(nil) } label: {
                    Label(т("af_year_skip"), systemImage: "calendar")
                }
            }
            Section(т("af_year_list")) {
                ForEach(годы, id: \.self) { год in
                    Button { выбрать(год) } label: {
                        HStack(spacing: 8) {
                            Text(String(год))
                                .foregroundStyle(Theme.текст)
                            Spacer(minLength: 8)
                            if let имя = поколение(год) {
                                Text(имя)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.текстВторой)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .disabled(модель.ищем)
        .overlay {
            if модель.ищем {
                ищем
                    .transition(.opacity)
            }
        }
        .animation(ДвижениеСайта.появление, value: модель.ищем)
        .navigationTitle(марка + " " + имяМодели)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let модели = await СправочникАвтоподбора.моделиМарки(марка)
            поколения = модели.first { $0.имя == имяМодели }?.поколения ?? []
        }
    }

    private var ищем: some View {
        VStack(spacing: 12) {
            SiteSpinner(размер: 28, толщина: 3, стоит: ДвижениеСайта.тихо)
                .accessibilityHidden(true)
            Text(т("af_car_searching"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func выбрать(_ год: Int?) {
        модель.выбрать(МашинаАвтоподбора(марка: марка, модель: имяМодели, год: год))
    }
}

// MARK: - Параметры колёс

struct ПараметрыКолёсМоего: View {
    @ObservedObject var модель: МодельРедактораМашиныМоего
    @ObservedObject private var хранилище = МоёХранилище.shared
    @State private var шины = ""
    @State private var pcd = ""
    @State private var dia = ""
    @State private var et = ""
    @State private var диаметр = ""
    @State private var заполнено = false
    @State private var спроситьСтереть = false
    @FocusState private var поле: ПолеВводаАвтоподбора?

    init(модель: МодельРедактораМашиныМоего) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { АвтоподборText.т(ключ) }

    private var машина: МашинаМоего? { хранилище.машина(модель.id) }

    /// Итог каждого поля и часть живого диска, под чьим «Ввести вручную» поле лежит.
    private var поляЧастей: [(ЧастьКолеса, ИтогВводаАвтоподбора)] {
        [(.шина, ВводАвтоподбора.шины(шины).итог), (.болты, ВводАвтоподбора.pcd(pcd).итог),
         (.центр, ВводАвтоподбора.dia(dia).итог), (.вылет, ВводАвтоподбора.et(et).итог),
         (.обод, ВводАвтоподбора.диаметр(диаметр).итог)]
    }

    private var итоги: [ИтогВводаАвтоподбора] { поляЧастей.map { $0.1 } }

    /// Сохранить можно, когда хоть одно поле понято и ни одно набранное не осталось непонятым.
    private var годится: Bool {
        !итоги.contains(.непонятно) && итоги.contains { if case .понято = $0 { return true } else { return false } }
    }

    /// Живой диск (WheelEditor.swift): шина, R диска, PCD, DIA и вылет пределами; другой R подбирает шину машины.
    private static let состав = СоставКолеса(шина: true, диаметр: true, pcd: true, dia: true, et: true, диапазонET: true,
                                             подборШины: true)

    /// Диск и чипы правят те же строки, что поля: сохранение и проверка — прежние.
    private var значения: Binding<ЗначенияКолеса> {
        Binding(get: {
            СтрокиКолеса(шины: шины, диаметр: диаметр, pcd: pcd, dia: dia, et: et).значения
        }, set: { новые in
            var строки = СтрокиКолеса(шины: шины, диаметр: диаметр, pcd: pcd, dia: dia, et: et)
            строки.принять(новые)
            if шины != строки.шины { шины = строки.шины }
            if диаметр != строки.диаметр { диаметр = строки.диаметр }
            if pcd != строки.pcd { pcd = строки.pcd }
            if dia != строки.dia { dia = строки.dia }
            if et != строки.et { et = строки.et }
        })
    }

    /// «Ввести вручную» под панелью части — прежнее поле этой части.
    @ViewBuilder
    private func ручноеПоле(_ часть: ЧастьКолеса) -> some View {
        switch часть {
        case .шина:
            ПолеАвтоподбора(заголовок: т("af_f_tire"), пример: "205/55 R16", текст: $шины,
                            итог: ВводАвтоподбора.шины(шины).итог, клавиатура: .asciiCapable, фокус: $поле, ключ: .шины)
        case .обод:
            ПолеАвтоподбора(заголовок: МоёText.т("my_f_rim"), пример: "17", текст: $диаметр,
                            итог: ВводАвтоподбора.диаметр(диаметр).итог, клавиатура: .decimalPad, фокус: $поле,
                            ключ: .диаметр)
        case .болты:
            ПолеАвтоподбора(заголовок: т("af_f_pcd"), пример: "5x114.3", текст: $pcd,
                            итог: ВводАвтоподбора.pcd(pcd).итог, клавиатура: .asciiCapable, фокус: $поле, ключ: .pcd)
        case .центр:
            ПолеАвтоподбора(заголовок: т("af_f_dia"), пример: "67.1", текст: $dia,
                            итог: ВводАвтоподбора.dia(dia).итог, клавиатура: .decimalPad, фокус: $поле, ключ: .dia)
        case .вылет:
            ПолеАвтоподбора(заголовок: т("af_f_et"), пример: "45", текст: $et,
                            итог: ВводАвтоподбора.et(et).итог, клавиатура: .numbersAndPunctuation, фокус: $поле,
                            ключ: .et)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                подсказка
                РедакторКолеса(значения: значения, состав: Self.состав, машина: машина?.авто) { часть in
                    ручноеПоле(часть)
                }
                кнопки
            }
            .padding(16)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(МоёText.т("my_car_wheels"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(т("af_done")) { поле = nil }
            }
        }
        .onAppear { заполнить() }
        .confirmationDialog(МоёText.т("my_car_wheels_clear_q"), isPresented: $спроситьСтереть,
                            titleVisibility: .visible) {
            Button(МоёText.т("my_delete"), role: .destructive) {
                хранилище.сохранитьПосадку(модель.id, nil)
                модель.путь = []
            }
            Button(МоёText.т("my_cancel"), role: .cancel) {}
        }
    }

    private var кнопки: some View {
        VStack(alignment: .leading, spacing: 12) {
            if поле == nil {
                ПлашкаНепонятогоКолеса(поляЧастей)
            }
            ЗелёнаяКнопкаФото(заголовок: МоёText.т("my_save"), значок: "checkmark") {
                сохранить()
            }
            .disabled(!годится)
            .opacity(годится ? 1 : 0.5)
            if машина?.посадка != nil {
                МалаяКнопкаАвтоподбора(заголовок: МоёText.т("my_car_wheels_clear"), значок: "trash", опасная: true) {
                    спроситьСтереть = true
                }
            }
        }
    }

    /// Машина и почему справочник промолчал; где взять параметры.
    private var подсказка: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let авто = машина?.авто {
                Text(авто.подпись)
                    .font(.headline)
                    .foregroundStyle(Theme.текст)
                if машина?.посадка == nil, let молчание = модель.молчание {
                    Text(т(молчание == .сеть ? "af_car_no_net" : "af_car_not_found"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Label {
                Text(т("af_where"))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Theme.акцент)
            }
            .font(.subheadline)
            .foregroundStyle(Theme.текст)
        }
        .карточкаАвтоподбора()
    }

    private func заполнить() {
        guard !заполнено else { return }
        заполнено = true
        guard let п = машина?.посадка else { return }
        шины = п.шины.first?.подпись ?? ""
        pcd = п.разболтовка.map { String($0.отверстий) + "x" + ЧислаАвтоподбора.ч($0.pcd, знаков: 2) } ?? ""
        dia = п.dia.map { ЧислаАвтоподбора.ч($0, знаков: 2) } ?? ""
        if let низ = п.etMin ?? п.etMax, let верх = п.etMax ?? п.etMin {
            et = низ == верх ? ЧислаАвтоподбора.ч(низ) : ЧислаАвтоподбора.ч(низ) + "-" + ЧислаАвтоподбора.ч(верх)
        }
        диаметр = п.диаметры.first.map { ЧислаАвтоподбора.ч($0) } ?? ""
    }

    private func сохранить() {
        поле = nil
        var п = машина?.посадка ?? ПосадкаАвтоподбора()
        if let размер = ВводАвтоподбора.шины(шины).размер {
            п.шины = [размер] + п.шины.filter { $0 != размер }
        } else {
            п.шины = []
        }
        п.разболтовка = ВводАвтоподбора.pcd(pcd).разболтовка
        п.dia = ВводАвтоподбора.dia(dia).dia
        let вылет = ВводАвтоподбора.et(et).вылет
        п.etMin = вылет?.lowerBound
        п.etMax = вылет?.upperBound
        if let д = ВводАвтоподбора.диаметр(диаметр).диаметр {
            п.диаметры = [д] + п.диаметры.filter { $0 != д }
        } else {
            п.диаметры = []
        }
        п.свои = true
        хранилище.сохранитьПосадку(модель.id, п.пустая ? nil : п)
        ОткликСайта.успех()
        модель.путь = []
    }
}

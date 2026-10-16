import SwiftUI

/**
 ШАБЛОНЫ НАД ЖИВЫМ ДИСКОМ (владелец 16.10.2026: «Шаблоны, чтобы были доступны» и «камерой узнать размеры»).

   · Машина известна (Моё, «Подойдут ли?») — «Штатные для Toyota Camry, 2018: 5×114.3 · DIA 60.1 · ET40 · R17 ·
     215/55 R17» и «Подставить» одной кнопкой. Берём из справочника посадки (СправочникАвтоподбора.посадка — кэш на
     телефоне, без кук и без входа); штатных шин несколько — чипы, какую подставить. У товара и подачи штатных нет: там
     описывают не свою машину.
   · «Популярные наборы» — разболтовка и отверстие по маркам (СтандартыКолёс.наборы): касание подставляет PCD и DIA.
     Пока «Штатных» нет: у известной машины хватает их, и диск остаётся ближе к верху экрана; в подаче наборов нет —
     там свои образцы каталога.
   · «Сканировать шину» / «Сканировать диск» — камера читает маркировку (СканерКолёс, WheelScan.swift); показываем,
     только когда сканер на этом телефоне есть. Что считали — WheelEditor.swift (подсветка частей и плашка «проверьте»).
 */
struct ШаблоныКолеса: View {
    /// Снимок значений на этот кадр; запись — через задать.
    let значения: ЗначенияКолеса
    let состав: СоставКолеса
    let машина: МашинаАвтоподбора?
    /// «Популярные наборы»: в подаче — нет (над диском уже образцы каталога).
    let показатьНаборы: Bool
    let задать: (ЗначенияКолеса) -> Void
    let сканировать: (ЧтоСканироватьКолеса) -> Void
    @State private var штатная: ПосадкаАвтоподбора? = nil
    @State private var выбраннаяШина: РазмерШиныАвтоподбора? = nil

    init(значения: ЗначенияКолеса, состав: СоставКолеса, машина: МашинаАвтоподбора?, наборы: Bool = true,
         задать: @escaping (ЗначенияКолеса) -> Void, сканировать: @escaping (ЧтоСканироватьКолеса) -> Void) {
        self.значения = значения
        self.состав = состав
        self.машина = машина
        self.показатьНаборы = наборы
        self.задать = задать
        self.сканировать = сканировать
    }

    private func т(_ ключ: String) -> String { КолёсаText.т(ключ) }

    /// Есть ли что показать сразу (без ответа справочника): наборы или сканер.
    @MainActor
    static func естьЧтоПоказать(_ состав: СоставКолеса, машина: МашинаАвтоподбора?, наборы: Bool = true) -> Bool {
        машина != nil || (наборы && (состав.pcd || состав.dia))
            || (СканерКолёс.доступен && (состав.шина || состав.естьДиск))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let машина, let штатная {
                штатные(машина, штатная)
                    .transition(.opacity)
            }
            /* У известной машины хватает «Штатных», в подаче — свои образцы каталога: диск не уезжает вниз. */
            if показатьНаборы && (состав.pcd || состав.dia) && штатная == nil {
                наборы
                    .transition(.opacity)
            }
            if СканерКолёс.доступен && (состав.шина || состав.естьДиск) {
                скан
            }
        }
        .animation(ДвижениеСайта.появление, value: штатная)
        .task(id: машина) { await загрузить() }
    }

    // MARK: Штатные

    private func загрузить() async {
        выбраннаяШина = nil
        guard let машина else {
            штатная = nil
            return
        }
        if case .есть(let найденная) = await СправочникАвтоподбора.посадка(машина) {
            штатная = найденная
        } else {
            штатная = nil
        }
    }

    /// Что подставит «Подставить»: известное справочнику — поверх выбранного, неизвестное не трогаем.
    private func подставленные(_ п: ПосадкаАвтоподбора, шина: РазмерШиныАвтоподбора?) -> ЗначенияКолеса {
        var н = значения
        if состав.pcd, let р = п.разболтовка { н.pcd = р }
        if состав.dia, let dia = п.dia { н.dia = dia }
        if состав.et, let а = п.etMin ?? п.etMax, let б = п.etMax ?? п.etMin {
            let низ = min(а, б)
            let верх = max(а, б)
            if состав.диапазонET {
                н.et = низ...верх
            } else {
                let середина = ((низ + верх) / 2).rounded()
                н.et = середина...середина
            }
        }
        if состав.шина, let шина { н.задатьШину(шина) }
        if состав.диаметр, let r = шина?.диаметр ?? п.штатныеДиаметры.first { н.диаметр = r }
        if состав.ширинаJ, let j = п.ширинаMin ?? п.ширинаMax { н.ширинаJ = j }
        return н
    }

    /// «5×114.3 · DIA 60.1 · ET40 · R17 · 215/55 R17».
    private func сводка(_ п: ПосадкаАвтоподбора, шина: РазмерШиныАвтоподбора?) -> String {
        var части: [String] = []
        if let р = п.разболтовка { части.append(р.подпись) }
        if let dia = п.dia { части.append("DIA " + ЧислаАвтоподбора.ч(dia, знаков: 2)) }
        if let et = СверкаАвтоподбора.штатныйВылет(п) { части.append(et) }
        if !п.штатныеДиаметры.isEmpty { части.append(СверкаАвтоподбора.списокДиаметров(п.штатныеДиаметры)) }
        if let шина { части.append(шина.подпись) }
        return части.joined(separator: " · ")
    }

    private func штатные(_ машина: МашинаАвтоподбора, _ п: ПосадкаАвтоподбора) -> some View {
        let шина = выбраннаяШина ?? п.шины.first
        let готово = подставленные(п, шина: шина)
        let совпадает = готово == значения
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        return VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(String(format: т("wh_stock_for"), машина.подпись))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.акцент)
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.текст)
            Text(сводка(п, шина: шина))
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            if п.шины.count > 1 {
                ПотокЧипов(зазор: 6) {
                    ForEach(п.шины, id: \.self) { размер in
                        ЧипЗначенияКолеса(размер.подпись, выбран: размер == шина) {
                            ОткликСайта.выбор()
                            выбраннаяШина = размер
                        }
                    }
                }
            }
            if совпадает {
                Label(т("wh_same"), systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(УровеньАвтоподбора.подходит.краска)
                    .frame(minHeight: 44, alignment: .leading)
            } else {
                ЗелёнаяКнопкаФото(заголовок: т("wh_apply"), значок: "wand.and.stars", контурная: true) {
                    ОткликСайта.успех()
                    задать(готово)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.оттенокАкцента, in: форма)
        .overlay { форма.strokeBorder(Theme.рамкаПункта, lineWidth: 1) }
    }

    // MARK: Наборы

    private var наборы: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(т("wh_sets"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(СтандартыКолёс.наборы) { набор in
                        ЧипОбразцаРазмеров(верх: набор.верх, низ: набор.низ, выбран: выбран(набор),
                                           озвучка: String(format: т("wh_set_a11y"), набор.верх + ", " + набор.низ)) {
                            взять(набор)
                        }
                        .accessibilityHint(т("wh_sets_hint"))
                    }
                }
                .padding(.vertical, 1)
                .padding(.horizontal, 1)
            }
        }
    }

    private func выбран(_ набор: НаборКолёс) -> Bool {
        let pcdДа = !состав.pcd || значения.pcd?.совпадает(набор.pcd) == true
        let diaДа = !состав.dia || значения.dia.map { abs($0 - набор.dia) < 0.06 } == true
        return pcdДа && diaДа
    }

    private func взять(_ набор: НаборКолёс) {
        var н = значения
        if состав.pcd { н.pcd = набор.pcd }
        if состав.dia { н.dia = набор.dia }
        guard н != значения else { return }
        ОткликСайта.выбор()
        задать(н)
    }

    // MARK: Сканер

    /// Кнопки сканера одним рядом; что читает камера — подсказкой VoiceOver, а не лишней строкой над диском.
    private var скан: some View {
        ПотокЧипов(зазор: 8) {
            if состав.шина {
                МалаяКнопкаАвтоподбора(заголовок: т("wh_scan_tire"), значок: "camera.viewfinder") {
                    сканировать(.шина)
                }
                .accessibilityHint(т("wh_scan_hint"))
            }
            if состав.естьДиск {
                МалаяКнопкаАвтоподбора(заголовок: т("wh_scan_rim"), значок: "text.viewfinder") {
                    сканировать(.диск)
                }
                .accessibilityHint(т("wh_scan_hint"))
            }
        }
    }
}

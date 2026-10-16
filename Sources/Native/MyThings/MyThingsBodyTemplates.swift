import SwiftUI
import UIKit

/**
 «МОЁ» — ШАБЛОНЫ МЕРОК: «МОЙ РАЗМЕР — ПОДСТАВИМ ТИПИЧНЫЕ» (владелец 16.10.2026: «стандарты ≠ удобства… шаблоны, чтобы
 были доступны»).

 Карточка над силуэтом:
   · есть размеры (одежда, обувь, джинсы, бельё, шапка) или рост — «Типичные для M (46) · EU 38 · рост 164 см:
     грудь 92 · талия 74 · бёдра 100 · стопа 24» и «Подставить · 5»: в пустые и с «≈ примерно», введённое руками
     не трогаем (ТиповыеМеркиМоего, ЗаписьМерокМоего). Размер сменился — прежние «≈» обхватов, стопы и головы уже от
     старого размера: «Обновить по размеру · N» (длины плеч, руки и шага — только в пустые: их «≈» может быть по фото);
   · нет размера одежды или обуви — быстрые чипы прямо здесь: «Мой размер одежды» — весь столбец INT своей таблицы,
     «Моя обувь, EU 36…42» (у мужской 39…46); выбор сразу ложится в «Мои размеры» с биркой всех систем — и карточка
     предлагает мерки. Пол не известен — сначала «Ваша фигура: Женская · Мужская»;
   · по фото — есть фото в полный рост и рост: «Посчитать длины по фото» (ОценкаМерокПоФото, MyThingsBodyEstimate.swift)
     → плечи, рука, шаг с пометкой «по фото, ±2–3 см» и «Подставить · N» (в пустые и поверх прежних «≈»); всё уже
     стоит — галочка вместо кнопки.
 Предложить нечего (всё к подстановке стоит, одежда и обувь есть, фото нет) — экран карточку не показывает (нужна).
 */
struct КарточкаШаблоновМоего: View {
    let тело: ТелоМоего
    @Binding var пол: ПолТелаМоего?
    @State private var поФото: [МеркаМоего: Double]? = nil

    init(тело: ТелоМоего, пол: Binding<ПолТелаМоего?>) {
        self.тело = тело
        _пол = пол
    }

    private func т(_ ключ: String) -> String { МоёТелоText.т(ключ) }

    /// Мерки, которых фото не даёт: их «≈» обновляется по новому размеру. Длины (плечи, рука, шаг) — только в пустые,
    /// чтобы не затереть «≈» по фото.
    private static let изТаблиц: Set<МеркаМоего> = [.грудь, .талия, .бёдра, .стопа, .голова]

    /// К подстановке, в порядке мерок: пустые и устаревшие «≈» мерок из таблиц (значение уже не то, что у размера).
    static func кПодстановке(_ тело: ТелоМоего, _ типовые: [МеркаМоего: (значение: Double, откуда: String)])
        -> [МеркаМоего] {
        МеркаМоего.allCases.filter { м in
            guard let типовая = типовые[м] else { return false }
            guard let есть = тело.мерка(м) else { return true }
            return изТаблиц.contains(м) && тело.примерная(м) && есть != типовая.значение
        }
    }

    /// Карточке есть что предложить: фото (длины по фото), быстрые чипы (нет одежды или обуви) или мерки к подстановке.
    static func нужна(_ тело: ТелоМоего, пол: ПолТелаМоего?) -> Bool {
        if тело.фото != nil { return true }
        let естьОдежда = тело.размеры.contains { $0.вид == .одеждаЖ || $0.вид == .одеждаМ }
        let естьОбувь = тело.размеры.contains { $0.вид.обувь }
        guard естьОдежда, естьОбувь else { return true }
        let типовые = ТиповыеМеркиМоего.поРазмерам(тело.размеры, рост: тело.рост, пол: пол)
        return !кПодстановке(тело, типовые).isEmpty
    }

    var body: some View {
        let типовые = ТиповыеМеркиМоего.поРазмерам(тело.размеры, рост: тело.рост, пол: пол)
        VStack(alignment: .leading, spacing: 14) {
            ЗаголовокМоего(т("mb_tpl_title"), значок: "wand.and.stars")
            if !типовые.isEmpty {
                блокТиповых(типовые)
                    .transition(.opacity)
            }
            быстрыеРазмеры
            блокФото
        }
        .карточкаМоего()
        .animation(ДвижениеСайта.смена, value: поФото != nil)
        .onChange(of: тело.фото?.файл) { _, _ in поФото = nil }
        .onChange(of: тело.рост) { _, _ in поФото = nil }
    }

    // MARK: Типичные по размерам

    private func блокТиповых(_ типовые: [МеркаМоего: (значение: Double, откуда: String)]) -> some View {
        let порядок = МеркаМоего.allCases.filter { типовые[$0] != nil }
        var источники: [String] = []
        for м in порядок {
            if let откуда = типовые[м]?.откуда, !источники.contains(откуда) { источники.append(откуда) }
        }
        let пустые = Self.кПодстановке(тело, типовые)
        // Среди них есть прежние «≈» от старого размера — кнопка «Обновить по размеру».
        let обновление = пустые.contains { тело.мерка($0) != nil }
        let строка = порядок.compactMap { м -> String? in
            guard let типовая = типовые[м] else { return nil }
            return т("mb_s_" + м.rawValue) + " " + ЧислоМоего.ч(типовая.значение)
        }.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 8) {
            Text(String(format: т("mb_tpl_for"), источники.joined(separator: " · ")))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            Text(строка)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.numericText())
            if пустые.isEmpty {
                Label(т("mb_tpl_full"), systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.акцент)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(т("mb_tpl_note"))
                    .font(.caption)
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                ЗелёнаяКнопкаФото(заголовок: т(обновление ? "mb_tpl_update" : "mb_suggest_apply") + " · "
                                  + String(пустые.count), значок: "wand.and.stars") {
                    let нужные = Set(пустые)
                    подставить(типовые.filter { нужные.contains($0.key) }.mapValues { $0.значение },
                               сменитьПримерные: true)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .animation(ДвижениеСайта.смена, value: строка)
        .animation(ДвижениеСайта.смена, value: пустые.count)
    }

    // MARK: Быстрые чипы размера

    @ViewBuilder
    private var быстрыеРазмеры: some View {
        let естьОдежда = тело.размеры.contains { $0.вид == .одеждаЖ || $0.вид == .одеждаМ }
        let естьОбувь = тело.размеры.contains { $0.вид.обувь }
        if !естьОдежда || !естьОбувь {
            VStack(alignment: .leading, spacing: 12) {
                if let выбранный = пол {
                    if !естьОдежда {
                        ряд(т("mb_tpl_clothes"), ТиповыеМеркиМоего.буквы(выбранный)) { буква in
                            добавить(РазмерМоего(вид: выбранный == .мужской ? .одеждаМ : .одеждаЖ, система: "INT",
                                                 значение: буква))
                        }
                    }
                    if !естьОбувь {
                        ряд(т("mb_tpl_shoes"), ТиповыеМеркиМоего.быстраяОбувь(выбранный)) { номер in
                            добавить(РазмерМоего(вид: выбранный == .мужской ? .обувьМ : .обувьЖ, система: "EU",
                                                 значение: номер))
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(т("mb_who"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.текст)
                        ПотокЧипов(зазор: 8) {
                            ЧипМоего(т("mb_women"), выбран: false) { выбратьПол(.женский) }
                            ЧипМоего(т("mb_men"), выбран: false) { выбратьПол(.мужской) }
                        }
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private func ряд(_ заголовок: String, _ значения: [String], _ выбрать: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(заголовок)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
            ПотокЧипов(зазор: 8) {
                ForEach(значения, id: \.self) { значение in
                    ЧипМоего(значение, выбран: false) { выбрать(значение) }
                }
            }
        }
    }

    private func выбратьПол(_ новый: ПолТелаМоего) {
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.смена) { пол = новый }
    }

    private func добавить(_ размер: РазмерМоего) {
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.вставкаСписка) { МоёХранилище.shared.задатьРазмер(размер) }
    }

    // MARK: По фото

    @ViewBuilder
    private var блокФото: some View {
        if let фото = тело.фото {
            VStack(alignment: .leading, spacing: 8) {
                if фото.полныйРост != true {
                    подсказка(т("mb_photo_need_full"), значок: "figure.stand")
                } else if let рост = тело.рост {
                    if let итог = поФото {
                        if итог.isEmpty {
                            подсказка(т("mb_photo_fail"), значок: "exclamationmark.triangle")
                        } else {
                            результатФото(итог)
                        }
                    } else {
                        МалаяКнопкаАвтоподбора(заголовок: т("mb_photo_calc"), значок: "camera.metering.center.weighted") {
                            посчитать(фото, рост)
                        }
                        Text(т("mb_photo_calc_sub"))
                            .font(.caption)
                            .foregroundStyle(Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    подсказка(т("mb_photo_need_h"), значок: "ruler")
                }
            }
            .transition(.opacity)
        }
    }

    private func подсказка(_ текст: String, значок: String) -> some View {
        Label {
            Text(текст)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: значок)
        }
        .font(.caption)
        .foregroundStyle(Theme.текстВторой)
    }

    private func результатФото(_ итог: [МеркаМоего: Double]) -> some View {
        let строка = МеркаМоего.allCases.compactMap { м -> String? in
            guard let x = итог[м] else { return nil }
            return т("mb_s_" + м.rawValue) + " " + ЧислоМоего.ч(x)
        }.joined(separator: " · ")
        // Что ещё можно поставить: пустые и прежние «≈» с другим значением (как в ЗаписьМерокМоего.подставить).
        let нового = итог.filter { пара in
            guard let есть = тело.мерка(пара.key) else { return true }
            return тело.примерная(пара.key) && есть != пара.value
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text(строка)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.текст)
                .fixedSize(horizontal: false, vertical: true)
            Label(т("mb_photo_est"), systemImage: "camera.viewfinder")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.текстВторой)
            if нового.isEmpty {
                Label(т("mb_tpl_full"), systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.акцент)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ЗелёнаяКнопкаФото(заголовок: т("mb_suggest_apply") + " · " + String(нового.count),
                                  значок: "wand.and.stars", контурная: true) {
                    подставить(нового, сменитьПримерные: true)
                }
            }
        }
        .animation(ДвижениеСайта.смена, value: нового.count)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    /// Длины по точкам позы и росту (договор с MyThingsBodyEstimate.swift); округлено до шага мерки, вне пределов — прочь.
    private func посчитать(_ фото: ФотоМоего, _ рост: Int) {
        ОткликСайта.выбор()
        let снимок: CGSize? = фото.ширина > 0 && фото.высота > 0 ? CGSize(width: фото.ширина, height: фото.высота) : nil
        let оценка = ОценкаМерокПоФото.оценить(точки: фото.поза, рост: рост, размерСнимка: снимок)
        var годные: [МеркаМоего: Double] = [:]
        for (м, x) in оценка where x.isFinite {
            let круглое = ТиповыеМеркиМоего.округлить(м, x)
            if м.пределы.contains(круглое) { годные[м] = круглое }
        }
        withAnimation(ДвижениеСайта.смена) { поФото = годные }
    }

    // MARK: Подстановка

    private func подставить(_ значения: [МеркаМоего: Double], сменитьПримерные: Bool) {
        let готово = ЗаписьМерокМоего.подставить(значения, сменитьПримерные: сменитьПримерные)
        guard !готово.isEmpty else {
            ОткликСайта.предупреждение()
            return
        }
        ОткликСайта.успех()
        let названия = готово.map { т("mb_s_" + $0.rawValue) }.joined(separator: ", ")
        UIAccessibility.post(notification: .announcement, argument: String(format: т("mb_tpl_done"), названия))
    }
}

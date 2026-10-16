import SwiftUI
import UIKit

/**
 «МОЙ ГАРДЕРОБ» — РАЗМЕР ВЕЩИ ЧИПОМ С БИРКОЙ ВСЕХ СИСТЕМ (владелец: «стандарты = удобство: не пустые поля, а выбор по
 стандартам»).

 Лист как у «Моих мерок» (РедакторРазмераМоего, MyThingsSizes.swift), но размер — этой вещи, а не мой: виды размера —
 только те, которыми меряют вид вещи (ВидВещиГардеробаМоего.видыРазмера), система — та, к которой человек привык, ровная
 сетка значений (СеткаРазмеровМоего), у джинсов — длина L, снизу — живая бирка всех систем (таблицы ClothingSizes — только
 вызовы). Свой размер этого вида в «Моих мерках» — одним касанием «Подставить». Хранится значение своей системы
 (РазмерМоего), а не номер ряда.
 */
struct ВыборРазмераГардероба: View {
    let виды: [ВидРазмераМоего]
    let был: РазмерМоего?
    let тело: ТелоМоего
    let готово: (РазмерМоего?) -> Void
    @Environment(\.dismiss) private var закрыть
    @Namespace private var пространство
    @State private var вид: ВидРазмераМоего
    @State private var система: String
    @State private var ряд: Int?
    @State private var ряд2: Int?
    @State private var толчок = 0

    init(виды: [ВидРазмераМоего], был: РазмерМоего?, тело: ТелоМоего, готово: @escaping (РазмерМоего?) -> Void) {
        let свои = виды.isEmpty ? [ВидРазмераМоего.одеждаЖ] : виды
        self.виды = свои
        self.был = был
        self.тело = тело
        self.готово = готово
        let начальный: РазмерМоего?
        if let был, свои.contains(был.вид) {
            начальный = был
        } else {
            начальный = свои.lazy.compactMap { тело.размер($0) }.first
        }
        let в = начальный?.вид ?? свои[0]
        _вид = State(initialValue: в)
        if let начальный, let выбор = начальный.выбор() {
            _система = State(initialValue: начальный.система)
            _ряд = State(initialValue: выбор.ряд)
            _ряд2 = State(initialValue: выбор.ряд2)
        } else {
            _система = State(initialValue: в.вкладка.системаСайта)
            _ряд = State(initialValue: nil)
            _ряд2 = State(initialValue: nil)
        }
    }

    private func т(_ ключ: String) -> String { МойГардеробText.т(ключ) }

    private var вкладка: ВкладкаРазмеровОдежды { вид.вкладка }

    private var текущая: СистемаРазмераОдежды? { вкладка.система(система) ?? вкладка.системы.first }

    private var выбор: ВыборРазмераОдежды? {
        guard let ряд else { return nil }
        return ВыборРазмераОдежды(вкладка: вкладка.ключ, ряд: ряд, ряд2: ряд2)
    }

    /// Значение своей системы у выбранного ряда (пусто — в этой системе такого размера нет).
    private var значение: String {
        guard let ряд, let с = текущая else { return "" }
        return вкладка.основная.значение(ряд, с.первый)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if виды.count > 1 { выборВида }
                    выборСистемы
                    сеткаОсновная
                    сеткаВторая
                    мойРазмер
                    бирка
                    if был != nil {
                        МалаяКнопкаАвтоподбора(заголовок: т("mw_size_none"), значок: "xmark.circle") {
                            ОткликСайта.выбор()
                            готово(nil)
                            закрыть()
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("mw_size_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(МоёText.т("my_cancel")) { закрыть() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(МоёText.т("my_save")) { сохранить() }
                        .disabled(значение.isEmpty)
                }
            }
        }
        .tint(Theme.акцент)
        .presentationDetents([.large])
    }

    // MARK: Что и в какой системе

    private var выборВида: some View {
        ПотокЧипов(зазор: 8) {
            ForEach(виды, id: \.self) { в in
                ЧипМоего(в.подпись, выбран: в == вид, значок: в.значок) { сменитьВид(в) }
            }
        }
    }

    private var выборСистемы: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(МоёТелоText.т("mb_system"))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.текст)
            ПотокЧипов(зазор: 8) {
                ForEach(вкладка.системы, id: \.код) { с in
                    ЧипМоего(РазмерыОдеждыText.система(с.код), выбран: с.код == текущая?.код) {
                        guard с.код != система else { return }
                        ОткликСайта.выбор()
                        withAnimation(ДвижениеСайта.смена) { система = с.код }
                        толчок += 1
                    }
                }
            }
        }
    }

    // MARK: Сетки

    @ViewBuilder
    private var сеткаОсновная: some View {
        if let с = текущая {
            СеткаРазмеровМоего(чипы: вкладка.основная.чипы(с.первый), выбранный: ряд, код: с.код,
                               пространство: пространство, метка: "main") { чип in
                ОткликСайта.выбор()
                withAnimation(ДвижениеСайта.мягко(.spring(response: 0.32, dampingFraction: 0.8))) { ряд = чип.id }
                толчок += 1
            }
            .id(вид.rawValue + "|" + с.код)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var сеткаВторая: some View {
        if let с = текущая, let второй = с.второй, let т2 = вкладка.вторая {
            VStack(alignment: .leading, spacing: 8) {
                Text(МоёТелоText.т(вид == .бельё ? "mb_cup" : "mb_length"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.текст)
                СеткаРазмеровМоего(чипы: т2.чипы(второй), выбранный: ряд2, код: "", пространство: пространство,
                                   метка: "second") { чип in
                    ОткликСайта.выбор()
                    withAnimation(ДвижениеСайта.мягко(.spring(response: 0.32, dampingFraction: 0.8))) {
                        ряд2 = ряд2 == чип.id ? nil : чип.id
                    }
                    толчок += 1
                }
            }
            .id(вид.rawValue + "|2|" + с.код)
            .transition(.opacity)
        }
    }

    // MARK: Мой размер

    /// Свой размер этого вида из «Моих мерок» — «Подставить», если выбрано другое.
    @ViewBuilder
    private var мойРазмер: some View {
        if let свой = тело.размер(вид), let свойВыбор = свой.выбор(),
           свойВыбор.ряд != ряд || свойВыбор.ряд2 != ряд2 || свой.система != система {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(Theme.акцент)
                    .accessibilityHidden(true)
                Text(String(format: т("mw_size_mine"), свой.коротко))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                МалаяКнопкаАвтоподбора(заголовок: МоёТелоText.т("mb_suggest_apply"), значок: "wand.and.stars") {
                    ОткликСайта.выбор()
                    withAnimation(ДвижениеСайта.мягко(.spring(response: 0.32, dampingFraction: 0.8))) {
                        система = свой.система
                        ряд = свойВыбор.ряд
                        ряд2 = свойВыбор.ряд2
                    }
                    толчок += 1
                }
            }
            .padding(12)
            .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var бирка: some View {
        if let выбор, !значение.isEmpty {
            БиркаРазмера(вкладка.бирка(выбор, система: текущая?.код ?? система), толчок: толчок, сброс: nil) {
                EmptyView()
            }
            .transition(.opacity)
        } else {
            Label(РазмерыОдеждыText.т("empty"), systemImage: "tag")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.текстВторой)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(Theme.линия, style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                }
        }
    }

    // MARK: Действия

    private func сменитьВид(_ новый: ВидРазмераМоего) {
        guard новый != вид else { return }
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.смена) {
            вид = новый
            if let свой = тело.размер(новый), let в = свой.выбор() {
                система = свой.система
                ряд = в.ряд
                ряд2 = в.ряд2
            } else {
                система = новый.вкладка.системаСайта
                ряд = nil
                ряд2 = nil
            }
        }
    }

    private func сохранить() {
        guard let ряд, let с = текущая else { return }
        let своё = вкладка.основная.значение(ряд, с.первый)
        guard !своё.isEmpty else { return }
        var второе = ""
        if let второй = с.второй, let т2 = вкладка.вторая, let ряд2 {
            второе = т2.значение(ряд2, второй)
        }
        готово(РазмерМоего(вид: вид, система: с.код, значение: своё, значение2: второе))
        ОткликСайта.успех()
        закрыть()
    }
}

/// Чип размера вещи в листе: крупно — своя система, ниже — строка всех систем; пусто — «Выбрать размер».
struct ЧипРазмераВещиГардероба: View {
    let размер: РазмерМоего?
    let действие: () -> Void

    init(размер: РазмерМоего?, действие: @escaping () -> Void) {
        self.размер = размер
        self.действие = действие
    }

    var body: some View {
        let бирка = размер?.бирка()
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        Button(action: действие) {
            HStack(spacing: 12) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 40, height: 40)
                    .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(размер?.коротко ?? МойГардеробText.т("mw_size_pick"))
                        .font(.system(size: 17, weight: .heavy).monospacedDigit())
                        .foregroundStyle(размер == nil ? Theme.акцент : Theme.текст)
                        .contentTransition(.numericText())
                    if let бирка, !бирка.части.isEmpty {
                        Text(бирка.части.map { РазмерыОдеждыText.показ($0) }.joined(separator: " · "))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    } else if размер == nil {
                        Text(МойГардеробText.т("mw_size_sub"))
                            .font(.caption)
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.текстВторой)
                    .flipsForRightToLeftLayoutDirection(true)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .background(Theme.поверхность2, in: форма)
            .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1) }
            .contentShape(форма)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.97))
        .animation(ДвижениеСайта.смена, value: размер)
        .accessibilityLabel(МойГардеробText.т("mw_size") + ". " + (размер?.коротко ?? МойГардеробText.т("mw_size_pick")))
    }
}

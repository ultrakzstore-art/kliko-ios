import SwiftUI

/**
 iPAD: ЛЕНТА И КАРТОЧКА РЯДОМ — ЭТАП 14 ПЕРЕХОДА НА SWIFTUI (владелец 25.09.2026: «давай следующие этапы»).

 На iPad в широком окне вкладка «Лента» — две колонки (NativeFeedView.раскладкаРядом): слева лента, справа выбранное
 объявление. Нажатие на карточку ленты или «Вы смотрели» не уводит с ленты, а ставит объявление в правую колонку;
 похожие и «Написать» из карточки ложатся в стек правой колонки, «Назад» ведёт к выбранному. Ссылка снаружи (этап 8)
 тоже выбирает объявление, а не кладёт его поверх ленты.

 🔴 iPHONE — КАК БЫЛО. Телефон держат только вертикально (UISupportedInterfaceOrientations в project.yml), а там
 ширина всегда compact — стек этапов 1–13 без изменений. Так же и узкое окно iPad (Split View, Slide Over): две
 колонки в трети экрана — это две полоски, в которых ничего не прочесть.
 */
enum ДвеКолонки {
    /// Лента в две колонки. Одно правило и для ленты (раскладка), и для вкладок (куда класть объявление из ссылки):
    /// разойдись они — объявление из пуша легло бы в стек, которого нет на экране. Без нативной карточки правой
    /// колонке нечего показывать — тогда стек, где карточки ведут на сайт, как раньше.
    static func включены(_ ширина: UserInterfaceSizeClass?) -> Bool {
        Config.айпадДвеКолонки && Config.нативнаяКарточка && ширина == .regular
    }
}

/// Правая колонка, пока объявление не выбрано.
struct ЗаглушкаКарточки: View {
    var body: some View {
        ContentUnavailableView {
            Label(IPadText.т("pick"), systemImage: "square.grid.2x2")
        } description: {
            Text(IPadText.т("pick_sub"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    /// Карточка ленты, открытая в правой колонке: рамка — видно, какое объявление справа, и «выбрано» для VoiceOver.
    /// Рамка не ловит нажатия: сердечко и сама карточка работают как без неё.
    func выбраннаяКарточка(_ выбрана: Bool) -> some View {
        overlay {
            if выбрана {
                /* Этап 26: карточка вида «как на сайте» скруглена на 14 (--r-md), рамка — по ней. */
                RoundedRectangle(cornerRadius: Config.дизайнКакНаСайте ? Theme.Радиус.md : 16, style: .continuous)
                    .strokeBorder(Config.дизайнКакНаСайте ? Theme.акцент : Theme.green2, lineWidth: 2.5)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityAddTraits(выбрана ? .isSelected : [])
    }
}

import SwiftUI

/**
 «МОИ ОБЪЯВЛЕНИЯ» — ЦИФРОВОЙ ТОВАР ПРОДАВЦА (ultra-site 16.10.2026, задание «Цифровые товары», Ц5).

 Свои цифровые объявления продавец видит в «Моих объявлениях» (digital: true): со значком «Цифровой товар», без правки
 сейфа и пополнения кодов — это делается на сайте; снять с публикации и удалить — можно, как обычное объявление. Вместо
 «Изменить» — строка «Правка цифровых товаров — в веб-версии кабинета», без ссылки (Apple 3.1.1). Набор кнопок —
 КнопкаОбъявления.набор, отказ правки по любому пути (карточка, окно лимита, ссылка) — МоиОбъявленияЭкран.правка и
 мастер подачи (загрузитьПравку).
 */

/// Значок «Цифровой товар» в строке даты карточки — капсула, как «ТОП» рядом с названием.
struct ЗначокЦифровогоТовара: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "key.fill")
                .font(.system(size: 9, weight: .bold))
                .accessibilityHidden(true)
            Text(ЦифровоеText.т("badge"))
                .font(.system(size: 10, weight: .heavy))
                .lineLimit(1)
        }
        .foregroundStyle(КраскаОбъявлений.индиго)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(КраскаОбъявлений.инфоФон, in: Capsule())
        .overlay {
            Capsule().strokeBorder(КраскаОбъявлений.индигоКромка, lineWidth: 1)
        }
        .fixedSize()
    }
}

/// Строка на месте «Изменить»: правки цифрового в приложении нет. Высота — как у кнопки ряда (34), карточка не выше соседних.
struct СтрокаПравкиЦифрового: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock")
                .font(.system(size: 12, weight: .semibold))
                .accessibilityHidden(true)
            Text(ЦифровоеText.т("edit_web"))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.текстВторой)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .padding(.horizontal, 10)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

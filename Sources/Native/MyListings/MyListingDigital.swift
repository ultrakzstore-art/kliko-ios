import SwiftUI

/**
 «МОИ ОБЪЯВЛЕНИЯ» — ЦИФРОВОЙ ТОВАР ПРОДАВЦА (ultra-site 16.10.2026, задание «Цифровые товары», Ц5).

 Свои цифровые объявления продавец видит в «Моих объявлениях» (digital: true): со значком «Цифровой товар», без правки
 сейфа и пополнения кодов — это делается на сайте; снять с публикации и удалить — можно, как обычное объявление. Вместо
 «Изменить» — строка «Правка цифровых товаров — в веб-версии кабинета», без ссылки (Apple 3.1.1). Набор кнопок —
 КнопкаОбъявления.набор, отказ правки по любому пути (карточка, окно лимита, ссылка) — МоиОбъявленияЭкран.правка и
 мастер подачи (загрузитьПравку).

 Владелец 16.10.2026: «Делиться можно, только актуальный товар». У опубликованного цифрового с непрошедшим сроком кода
 (digital_info.expires, СрокЦифровогоКода) — снова «Поделиться» тем же путём, что у обычных (окно кабинета, в долгом
 нажатии — и «QR-код»); в нём — только название и ссылка. «Продвинуть», «Активировать», «Восстановить», «На проверку» и
 правка по-прежнему закрыты. Срок кода прошёл — «Поделиться» нет, а в строке даты рядом со значком — «Срок истёк».
 */

extension МоёОбъявление {
    /// Срок кода прошёл (конец его дня по Алматы позади). Не цифровое, срока нет или он непонятен — false.
    func срокКодаИстёк(_ сейчас: Date = Date()) -> Bool {
        guard цифровое, let срок = срокЦифрового else { return false }
        return СрокЦифровогоКода.истёк(срок, сейчас: сейчас)
    }

    /// Опубликовано и актуально: одобрено, видно покупателям (не ждёт верификации), 30-дневный срок не вышел и срок
    /// кода не прошёл. Только тогда у цифрового есть «Поделиться».
    func цифровоеАктуально(_ сейчас: Date = Date()) -> Bool {
        цифровое && статус == "approved" && !ждётВерификации && !истёк(сейчас.timeIntervalSince1970)
            && !срокКодаИстёк(сейчас)
    }
}

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

/// «Срок истёк» рядом со значком «Цифровой товар» — у опубликованного цифрового, чей код уже не действует. Капсула в
/// тоне предупреждения, как значки статуса карточки; места мало — один значок часов с той же подписью для VoiceOver.
struct МеткаИстёкшегоКода: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            капсула(подпись: true)
            капсула(подпись: false)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ЦифровоеText.т("expired_short"))
    }

    private func капсула(подпись: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "clock")
                .font(.system(size: 9, weight: .bold))
            if подпись {
                Text(ЦифровоеText.т("expired_short"))
                    .font(.system(size: 10, weight: .heavy))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(КраскаОбъявлений.предупреждениеТекст)
        .padding(.horizontal, подпись ? 7 : 5)
        .padding(.vertical, 3)
        .background(КраскаОбъявлений.предупреждениеФон, in: Capsule())
        .overlay {
            Capsule().strokeBorder(КраскаОбъявлений.предупреждениеКромка, lineWidth: 1)
        }
        .fixedSize()
    }
}

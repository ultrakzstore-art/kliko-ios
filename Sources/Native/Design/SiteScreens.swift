import SwiftUI

/**
 ЧАТ, ИЗБРАННОЕ И КАБИНЕТ В ВИДЕ САЙТА — ЭТАП 30 (владелец 25.09.2026: «почти 100% похоже на сайт»).

 Снимков этих страниц сайта нет, поэтому вид взят из их CSS и текстов: переписка — .kc-* из css/chat.min.css (облака
 .kc-msg со скруглением 14 и «хвостом» 5 на своей стороне, своё — --kc-acc (--mk-bright: #16a34a, в тёмной — тот же
 акцент под 44 % чёрного), чужое — --kc-peer (--mk-surf2), время внутри облака, поле .kc-field — пилюля 22 на --kc-soft
 с кромкой, зелёная круглая «Отправить» 32 pt), списки — карточки .mh-c/.mk-msc (поверхность, скругление 14, тень
 сайта) на фоне страницы --mk-surf2, заголовки — жирные, как .mk-msub и ряды главной. Общие части — здесь, экраны
 берут их при Config.дизайнКакНаСайте; выключен — прежний системный вид.
 */

// MARK: - Шапка экрана

extension View {
    /// Системная панель в краске сайта: поверхность вместо стекла, заголовок жирный (как заголовки сайта), акцент —
    /// --acc-on. Название остаётся и навигационным — его читают VoiceOver и кнопка «Назад» следующего экрана.
    func шапкаЭкранаСайта(_ заголовок: String) -> some View {
        self
            .navigationTitle(заголовок)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(заголовок)
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .toolbarBackground(Theme.поверхность, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tint(Theme.акцент)
    }
}

// MARK: - Пустой экран

/// Пусто, нужен вход, не загрузилось — в краске сайта: значок в мятном круге, жирный заголовок, серый текст и зелёная
/// кнопка (.mk-btips-ok / .mh-fail). Вторая кнопка — ссылкой акцентом.
struct ПустоСайта: View {
    let значок: String
    let заголовок: String
    let подпись: String?
    let кнопка: String?
    let действие: (() -> Void)?
    let вторая: String?
    let второеДействие: (() -> Void)?

    init(значок: String, заголовок: String, подпись: String? = nil, кнопка: String? = nil,
         действие: (() -> Void)? = nil, вторая: String? = nil, второеДействие: (() -> Void)? = nil) {
        self.значок = значок
        self.заголовок = заголовок
        self.подпись = подпись
        self.кнопка = кнопка
        self.действие = действие
        self.вторая = вторая
        self.второеДействие = второеДействие
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: значок)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.акцент)
                .frame(width: 72, height: 72)
                .background(Theme.мята, in: Circle())
                .accessibilityHidden(true)
            Text(заголовок)
                .font(.system(size: 19, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if let текст = подпись {
                Text(текст)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let надпись = кнопка, let нажать = действие {
                Button(action: нажать) {
                    Text(надпись)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 26)
                        .frame(minHeight: 46)
                        .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                .padding(.top, 4)
            }
            if let надпись = вторая, let нажать = второеДействие {
                Button(надпись, action: нажать)
                    .font(.system(size: 15, weight: .bold))
                    .tint(Theme.акцент)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.фонСтраницы)
    }
}

// MARK: - Переписка

/// Облако сообщения .kc-msg: текст и время внутри, скругление 14, на своей стороне снизу — 5.
struct ОблакоСайта: View {
    let текст: String
    let время: String
    let моё: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(текст)
                .font(.system(size: 16))
                .foregroundStyle(моё ? Color.white : Theme.текст)
                .multilineTextAlignment(.leading)
                .frame(minWidth: 0, alignment: .leading)
            if !время.isEmpty {
                Text(время)
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(моё ? Color.white.opacity(0.72) : Theme.текстВторой)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(моё ? Theme.пузырьМой : Theme.пузырьЧужой, in: форма)
        /* Этап 31: чужое облако — --mk-surf2 на --mk-surf, в тёмной это #1c1c26 на #16161f, и край облака теряется.
           Тонкая кромка цвета линии возвращает его, не меняя краски сайта. */
        .overlay {
            if !моё {
                форма.stroke(Theme.линия, lineWidth: 1)
            }
        }
    }

    private var форма: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: моё ? 14 : 5,
                               bottomTrailingRadius: моё ? 5 : 14, topTrailingRadius: 14, style: .continuous)
    }
}

/// Середина панели переписки (.kc-head): зелёный кружок с первой буквой и имя.
struct ШапкаПерепискиСайта: View {
    let имя: String

    var body: some View {
        HStack(spacing: 10) {
            Text(String(имя.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 32, height: 32)
                .background(Theme.пузырьМой, in: Circle())
                .accessibilityHidden(true)
            Text(имя)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// Нижняя строка переписки (.kc-bar): поле-пилюля на --kc-soft с кромкой (в фокусе — акцентом) и круглая «Отправить».
struct ПолеПерепискиСайта: View {
    @Binding var текст: String
    let можно: Bool
    let отправить: () -> Void
    var фокус: FocusState<Bool>.Binding

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(ChatText.т("placeholder"), text: $текст, axis: .vertical)
                .font(.system(size: 16))
                .foregroundStyle(Theme.текст)
                .lineLimit(1...5)
                .focused(фокус)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 42)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: 21, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .strokeBorder(фокус.wrappedValue ? Theme.зелёныйЯркий : Theme.линия, lineWidth: 1)
                }
            Button(action: отправить) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 40, height: 40)
                    .background(Theme.пузырьМой, in: Circle())
                    .opacity(можно ? 1 : 0.5)
            }
            .disabled(!можно)
            .accessibilityLabel(ChatText.т("send"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.поверхность)
        .overlay(alignment: .top) {
            Theme.линия
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Список диалогов

/// Строка диалога карточкой сайта: обложка объявления 52 pt со скруглением 14 (или зелёная буква), имя, время,
/// объявление акцентом, последнее сообщение и красный счётчик непрочитанных (--kc-unread #ef4444).
struct СтрокаДиалогаСайта: View {
    let диалог: ЧатДиалог

    private var имя: String { диалог.собеседник.isEmpty ? ChatText.т("peer") : диалог.собеседник }

    var body: some View {
        HStack(spacing: 12) {
            обложка
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(имя)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(ЧатВремя.коротко(диалог.последнееКогда))
                        .font(.system(size: 12, weight: диалог.непрочитано > 0 ? Font.Weight.bold : Font.Weight.regular))
                        .monospacedDigit()
                        .foregroundStyle(диалог.непрочитано > 0 ? Theme.акцент : Theme.текстВторой)
                }
                if !диалог.объявление.isEmpty {
                    Text(диалог.объявление)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.акцент)
                        .lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text((диалог.последнееМоё ? ChatText.т("you") : "") + диалог.последнее)
                        .font(.system(size: 14, weight: диалог.непрочитано > 0 ? Font.Weight.semibold : Font.Weight.regular))
                        .foregroundStyle(диалог.непрочитано > 0 ? Theme.текст : Theme.текстВторой)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if диалог.непрочитано > 0 {
                        Text(диалог.непрочитано > 99 ? "99+" : String(диалог.непрочитано))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Theme.непрочитано, in: Capsule())
                            .accessibilityLabel(String(format: AccessText.т("unread"), диалог.непрочитано))
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .теньКарточкиСайта()
        .contentShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    private var обложка: some View {
        RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
            .fill(LinearGradient(colors: [Theme.зелёный2, Theme.зелёныйЯркий], startPoint: .topLeading,
                                 endPoint: .bottomTrailing))
            .overlay {
                Text(String(имя.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color.white)
            }
            .overlay {
                if let адрес = Config.url(диалог.обложка) {
                    AsyncImage(url: адрес) { картинка in
                        картинка.resizable().scaledToFill()
                    } placeholder: {
                        Theme.поверхность2
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                }
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)
    }
}

// MARK: - Кабинет

/// Верх кабинета — зелёная плашка, как шапка главной (градиент mk-gtop): значок входа, «Вы вошли» / «Вы не вошли»
/// и пояснение белым. На зелёном белый текст читается в обеих темах.
struct ШапкаКабинетаСайта<Значок: View>: View {
    let заголовок: String
    let подпись: String
    let значок: Значок

    init(заголовок: String, подпись: String, @ViewBuilder значок: () -> Значок) {
        self.заголовок = заголовок
        self.подпись = подпись
        self.значок = значок()
    }

    var body: some View {
        HStack(spacing: 14) {
            значок
                .frame(width: 52, height: 52)
                .background(Theme.шапкаКнопка, in: Circle())
                .overlay {
                    Circle().strokeBorder(Theme.шапкаКнопкаРамка, lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(заголовок)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.white)
                Text(подпись)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Theme.шапкаВерх, Theme.шапкаСередина, Theme.шапкаНиз],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
        )
        .overlay(alignment: .topLeading) {
            RadialGradient(colors: [Theme.шапкаБлик, Color.clear], center: .topLeading, startRadius: 0, endRadius: 220)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .теньКарточкиСайта(радиус: Theme.Радиус.lg)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Список в краске сайта: фон страницы --mk-surf2 вместо системного серого, строки — на поверхности, линии —
    /// --mk-line, акцент — --acc-on.
    func списокСайта() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.фонСтраницы)
            .tint(Theme.акцент)
    }

    /// Строки раздела списка — на поверхности сайта, разделители цвета линии.
    func строкиСайта() -> some View {
        self
            .listRowBackground(Theme.поверхность)
            .listRowSeparatorTint(Theme.линия)
    }
}

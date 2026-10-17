import SwiftUI

/**
 «Подойдут ли?» одной строкой в окне объявления шин и дисков (пачка 83, D2; аудит упрощений: два входа в одно окно —
 плашка «Подходит моему» и зелёная кнопка «Подойдут ли?» блока примерки — стояли друг под другом, а без машины это были
 две разные просьбы об одном и том же).

 В разделе tires-wheels при «Моём» и автоподборе вместо обоих — одна строка под ценой: итог сверки с главной машиной
 гаража («Подходят» и с какой машиной сверили) или «Подойдут ли? — выберите машину». Нажатие всегда ведёт в окно
 «Подойдут ли?» (ОкноАвтоПодбора): машину выбирают и меняют там же, там же вводят параметры колёс. Пока строка стоит,
 способа .авто в блоке примерки нет (ПодборПримерки.доступен, TryOnHub.swift) — прочие способы (диски на фото своей
 машины) остаются.

 Сверка — на телефоне, по «Моему» и самому объявлению (СовместимостьМоего.оценить); в сеть ничего не уходит. Строка вида
 «Примерить и проверить»: поверхность с рамкой-линией, значок в круге 40, заголовок, одна строка подписи и шеврон —
 без строки «Проверили по описанию» (она есть в самом окне сверки).
 */

extension Config {
    /// Одна строка «Подойдут ли?» у шин и дисков. false — как раньше: плашка «Подходит моему» и кнопка примерки.
    static let строкаПодойдутЛи = true
}

@MainActor
enum ПодойдутЛиОбъявления {
    /// Строка вообще возможна: её рубильник, «Моё» и окно «Подойдут ли?».
    static var включено: Bool { Config.строкаПодойдутЛи && Config.моё && Config.автоПодбор }

    /// У этого объявления вместо плашки «Подходит моему» и кнопки .авто — одна строка.
    static func стоит(_ товар: Listing) -> Bool {
        включено && РазделыСайта.внутри(товар.категория, СовместимостьМоего.разделыАвто)
    }
}

/// Строка «Подойдут ли?» под ценой объявления шин и дисков. Отступы — как у плашки «Подходит моему», на её месте.
struct СтрокаПодойдутЛи: View {
    let товар: Listing
    @ObservedObject private var хранилище = МоёХранилище.shared
    @State private var итог: ИтогСовместимостиМоего? = nil

    init(товар: Listing) {
        self.товар = товар
    }

    private func т(_ ключ: String) -> String { ПодойдутЛиText.т(ключ) }

    var body: some View {
        кнопка
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .animation(ДвижениеСайта.смена, value: итог)
            .onAppear {
                хранилище.подготовить()
                пересчитать()
            }
            .onChange(of: товар) { _, _ in пересчитать() }
            .onChange(of: хранилище.запись) { _, _ in пересчитать() }
    }

    private func пересчитать() {
        let новый: ИтогСовместимостиМоего? = СовместимостьМоего.оценить(товар, моё: хранилище.запись)
        guard новый != итог else { return }
        итог = новый
    }

    /// Итог сверки годится в строку: это сверка с машиной (вердикт или «нужны параметры колёс»), а не приглашение
    /// добавить машину — его заменяет своё «выберите машину».
    private var итогСМашиной: ИтогСовместимостиМоего? {
        guard let итог, итог.профиль == .машина else { return nil }
        guard итог.уровень != nil || хранилище.запись.главнаяМашина != nil else { return nil }
        return итог
    }

    private var заголовок: String {
        итогСМашиной?.заголовок ?? т("tf_title")
    }

    private var подпись: String {
        if let готово = итогСМашиной, !готово.подпись.isEmpty { return готово.подпись }
        guard let машина = хранилище.запись.главнаяМашина else { return т("tf_pick") }
        return String(format: т("tf_with"), машина.заголовок)
    }

    private var значок: String {
        итогСМашиной?.уровень?.значокИтога ?? "car.side"
    }

    private var краска: Color {
        итогСМашиной?.уровень?.краска ?? Theme.акцент
    }

    private var кнопка: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
        let есть: Bool = итогСМашиной?.уровень != nil
        let рамка: Color = есть ? краска.opacity(0.35) : Theme.линия
        return Button(action: открыть) {
            HStack(spacing: 12) {
                Image(systemName: значок)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(краска)
                    .frame(width: 40, height: 40)
                    .background(краска.opacity(0.12), in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(подпись)
                        .font(.footnote)
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(2)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.поверхность, in: форма)
            .overlay { форма.strokeBorder(рамка, lineWidth: 1) }
            .contentShape(форма)
        }
        .buttonStyle(НажатиеСайта())
        .accessibilityElement(children: .combine)
        .accessibilityHint(т("tf_hint"))
    }

    /// Всегда окно «Подойдут ли?»: есть машина — сверка с ней, нет — там же её выбрать.
    private func открыть() {
        ОткликСайта.выбор()
        ОкноАвтоПодбора.открыть(товар: товар)
    }
}

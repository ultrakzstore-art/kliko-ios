import SwiftUI
import UIKit

/**
 ОКНО «ИЛЛЮСТРАЦИЯ С ИИ» (владелец 13.10.2026: «генератор изображения как в чате»; сервер — ultra-site 14.10.2026,
 «Картинка по описанию», часть 2).

 Полноэкранный лист поверх подачи. Сверху — шапка («✕», «Иллюстрация с ИИ» и, когда запуск тратит месячный остаток,
 «Осталось картинок в этом месяце: N из M»), посередине — лента как в мессенджере (пузыри человека справа, ответы ИИ —
 карточки слева), внизу — одна строка «Что продаёте?» (заполнена названием формы) и «Отправить». Пустой чат — «Что
 продаёте?» и что будет с картинкой. Про цены и покупку в окне ничего нет. Тема — светлая и тёмная, как у подачи
 (КраскаПодачи); тексты — Dynamic Type; «Уменьшение движения» — без бегущего сияния и проявления. Состояние —
 МодельЧатаИИФото, ответы ИИ — AIImageChatParts.swift.
 */
struct ЭкранЧатаИИФото: View {
    let закрыть: () -> Void
    @StateObject private var модель: МодельЧатаИИФото

    init(подача: ПодачаМодель, вход: ВходЧатаИИФото, закрыть: @escaping () -> Void) {
        self.закрыть = закрыть
        _модель = StateObject(wrappedValue: МодельЧатаИИФото(подача: подача, вход: вход))
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    var body: some View {
        VStack(spacing: 0) {
            ШапкаЧатаИИФото(модель: модель, закрыть: закрыть)
            содержимое
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(модель.экран)
                .transition(.opacity)
        }
        .background(ФонПодачи())
        .overlay(alignment: .bottom) { весть }
        .sheet(isPresented: $модель.согласие, onDismiss: { модель.отказатьсяОтСогласия() }) {
            ЛистСогласияИИФото(модель: модель)
        }
        .onAppear {
            модель.закрытьОкно = закрыть
            модель.открыт()
        }
        .onDisappear { модель.закрыть() }
        .onChange(of: модель.экран) { _, _ in
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.экран {
        case .чат:
            ЛентаЧатаИИФото(модель: модель)
        case .вход:
            ЗаглушкаЧатаИИФото(значок: "person.crop.circle.badge.checkmark", заголовок: т("aim_login_t"),
                                текст: т("aim_login_s"), кнопка: т("aim_login"), значокКнопки: "person.fill") {
                ВходПоверх.показать(готово: { модель.послеВхода() })
            }
        case .скоро:
            ЗаглушкаЧатаИИФото(значок: "hourglass", заголовок: т("aim_soon_t"), текст: т("aim_soon_s"),
                                кнопка: т("aim_ok"), значокКнопки: "checkmark", действие: закрыть)
        }
    }

    @ViewBuilder
    private var весть: some View {
        if let текст = модель.весть {
            Text(текст)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(Color(red: 15 / 255, green: 23 / 255, blue: 18 / 255),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .padding(.horizontal, 24)
                .padding(.bottom, 120)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Шапка

/// «✕» слева, «Иллюстрация с ИИ» и месячный остаток по центру; справа — пустое место той же ширины (заголовок ровно
/// посередине).
struct ШапкаЧатаИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото
    let закрыть: () -> Void
    @ObservedObject private var готовность = ГотовностьИИФото.shared

    init(модель: МодельЧатаИИФото, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.закрыть = закрыть
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    /// «Осталось картинок в этом месяце: N из M» — только когда spends (сервер сказал, что запуск тратит остаток).
    private var подпись: String? {
        guard let остаток = готовность.сведения?.строкаОстатка else { return nil }
        return String(format: т("aim_left_month"), остаток.осталось, остаток.всего)
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: закрыть) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(КраскаПодачи.текст)
                    .frame(width: 44, height: 44)
                    .background(КраскаПодачи.поле, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
            .accessibilityLabel(т("aim_close"))
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .foregroundStyle(КраскаПодачи.хорошоТекст)
                        .accessibilityHidden(true)
                    Text(т("aim_title"))
                        .foregroundStyle(КраскаПодачи.текст)
                }
                .font(.headline.weight(.heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                if let подпись {
                    Text(подпись)
                        .font(.caption)
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(КраскаПодачи.карточка.opacity(0.92).ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(КраскаПодачи.линия)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Лента

struct ЛентаЧатаИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото

    init(модель: МодельЧатаИИФото) {
        self.модель = модель
    }

    private static let низ = "aim_bottom"

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { прокрутка in
                ScrollView {
                    /* Не Lazy: реплик немного, а проявление картинки не должно повторяться при прокрутке. */
                    VStack(alignment: .leading, spacing: 16) {
                        if модель.реплики.isEmpty {
                            ПустойЧатИИФото(модель: модель)
                        }
                        ForEach(модель.реплики) { реплика in
                            РепликаИИФотоВид(модель: модель, реплика: реплика)
                                .id(реплика.id)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(Self.низ)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: модель.сдвиг) { _, _ in
                    withAnimation(ДвижениеСайта.прокрутка) { прокрутка.scrollTo(Self.низ, anchor: .bottom) }
                }
            }
            ПолеЧатаИИФото(модель: модель)
        }
    }
}

// MARK: - Пустой чат

/// «Что продаёте?», что будет с картинкой и — если свой ИИ картинки не рисует — фраза сервера и «Нарисовать с Kliko AI».
struct ПустойЧатИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото
    @ObservedObject private var готовность = ГотовностьИИФото.shared
    @State private var появилось = false
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения

    init(модель: МодельЧатаИИФото) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    /// Свой ИИ человека картинки не рисует (own_ai:"images"): фраза сервера, иначе своя.
    private var свойНеРисует: String? {
        guard let с = готовность.сведения, с.свойНеРисует else { return nil }
        return с.свойТекст.isEmpty ? т("aim_own_images") : с.свойТекст
    }

    var body: some View {
        VStack(spacing: 14) {
            значок
            Text(т("aim_empty_t"))
                .font(.title2.weight(.heavy))
                .foregroundStyle(КраскаПодачи.текст)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(т("aim_empty_s"))
                .font(.subheadline)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            ЗаметкаПодачи(т("aim_empty_note"), тон: .серый, значок: "info.circle")
            if let свойНеРисует {
                ЗаметкаПодачи(свойНеРисует, тон: .внимание, значок: "cpu")
                if готовность.сведения?.klikoМожно == true {
                    КнопкаЧатаИИФото(т("aim_kliko_btn"), значок: "wand.and.stars", главная: true) {
                        модель.нарисоватьKliko(nil)
                    }
                    .disabled(модель.идёт)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .opacity(появилось || тихо ? 1 : 0)
        .offset(y: появилось || тихо ? 0 : 14)
        .onAppear {
            guard !появилось else { return }
            withAnimation(ДвижениеСайта.мягко(.spring(response: 0.5, dampingFraction: 0.8))) { появилось = true }
        }
    }

    private var значок: some View {
        Image(systemName: "wand.and.stars")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 76, height: 76)
            .background(LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            .shadow(color: Color(uiColor: Theme.hex(0x0F5132, 0.3)), radius: 12, y: 6)
            .symbolEffect(.bounce, value: появилось)
            .accessibilityHidden(true)
    }
}

// MARK: - Поле ввода

/// Одна строка «Что продаёте?» со счётчиком у предела и «Отправить».
struct ПолеЧатаИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото
    @FocusState private var фокус: Bool

    init(модель: МодельЧатаИИФото) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    private var можноОтправить: Bool {
        !модель.идёт && !модель.ввод.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            строка
            if модель.ввод.count > модель.пределТекста - 15 {
                Text(String(format: т("aim_counter"), модель.ввод.count, модель.пределТекста))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(модель.ввод.count >= модель.пределТекста ? Theme.скидкаТекст : Theme.текстВторой)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .background(КраскаПодачи.карточка.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(КраскаПодачи.линия)
                .frame(height: 1)
                .accessibilityHidden(true)
        }
        .onChange(of: модель.вПоле) { _, _ in фокус = true }
        .onChange(of: модель.ввод) { _, новое in
            if новое.count > модель.пределТекста { модель.ввод = String(новое.prefix(модель.пределТекста)) }
        }
    }

    private var строка: some View {
        HStack(alignment: .center, spacing: 8) {
            TextField(т("aim_ph_draft"), text: $модель.ввод)
                .lineLimit(1)
                .font(.body)
                .foregroundStyle(КраскаПодачи.текст)
                .focused($фокус)
                .submitLabel(.send)
                .onSubmit { модель.отправить() }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(фокус ? КраскаПодачи.хорошоТекст.opacity(0.6) : КраскаПодачи.линия, lineWidth: 1)
                }
                .accessibilityLabel(т("aim_field_a11y"))
            Button {
                модель.отправить()
            } label: {
                ZStack {
                    if модель.идёт {
                        SiteSpinner.белый
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 44, height: 44)
                .background(можноОтправить || модель.идёт ? Theme.зелёный2 : Theme.текстВторой.opacity(0.4), in: Circle())
                .contentShape(Circle())
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
            .disabled(!можноОтправить)
            .accessibilityLabel(т(модель.идёт ? "aim_sending" : "aim_send"))
        }
    }
}

// MARK: - Согласие

/**
 Перед первым запуском (App Review 5.1.2(i)): кто нарисует (by_text из info), что в ИИ уходит только текст формы — без
 фото и контактов, что готовая картинка ложится фото объявления и помечается «не фото товара». «Согласен» — на этого
 человека и этого исполнителя (МодельЧатаИИФото.предметСогласия); общая формулировка — только до закрытия окна.
 */
struct ЛистСогласияИИФото: View {
    @ObservedObject var модель: МодельЧатаИИФото
    @ObservedObject private var готовность = ГотовностьИИФото.shared

    init(модель: МодельЧатаИИФото) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                    .frame(width: 48, height: 48)
                    .background(КраскаПодачи.хорошоФон, in: Circle())
                    .accessibilityHidden(true)
                Text(т("aim_consent_t"))
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(КраскаПодачи.текст)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    пункт("person.badge.shield.checkmark", String(format: т("aim_consent_who"), модель.ктоОбработает))
                    пункт("text.alignleft", т("aim_consent_text"))
                    пункт("tag", т("aim_consent_mark"))
                }
            }
            VStack(spacing: 10) {
                ЗелёнаяКнопкаФото(заголовок: т("aim_consent_yes"), значок: "checkmark") { модель.согласиться() }
                Button(т("aim_consent_no")) { модель.отказатьсяОтСогласия() }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .padding(20)
        .background(КраскаПодачи.карточка.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func пункт(_ значок: String, _ текст: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: значок)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(КраскаПодачи.хорошоТекст)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(текст)
                .font(.subheadline)
                .foregroundStyle(КраскаПодачи.текст)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - «Войдите», «Сейчас недоступно»

struct ЗаглушкаЧатаИИФото: View {
    let значок: String
    let заголовок: String
    let текст: String
    let кнопка: String
    let значокКнопки: String
    let действие: () -> Void

    init(значок: String, заголовок: String, текст: String, кнопка: String, значокКнопки: String,
         действие: @escaping () -> Void) {
        self.значок = значок
        self.заголовок = заголовок
        self.текст = текст
        self.кнопка = кнопка
        self.значокКнопки = значокКнопки
        self.действие = действие
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Image(systemName: значок)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(КраскаПодачи.хорошоТекст)
                    .frame(width: 80, height: 80)
                    .background(КраскаПодачи.хорошоФон, in: Circle())
                    .accessibilityHidden(true)
                Text(заголовок)
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(КраскаПодачи.текст)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(текст)
                    .font(.subheadline)
                    .foregroundStyle(Theme.текстВторой)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
                ЗелёнаяКнопкаФото(заголовок: кнопка, значок: значокКнопки, действие: действие)
            }
            .padding(.horizontal, 32)
            .padding(.top, 70)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
    }
}

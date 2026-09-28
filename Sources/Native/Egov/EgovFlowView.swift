import SwiftUI
import UIKit

/// Поля формы, которые держат фокус.
enum ПолеФормыEgov: Hashable {
    case иин
    case номер
}

/**
 ЭКРАН ПОТОКА eGov: индикатор шагов, форма (или сверка), ожидание с отсчётом, успех или ошибка. Экран biometric.kz —
 лист поверх (ЛистБиометрииEgov), он открывается сам после запуска и закрывается сам по итогу опроса.
 */
struct ЭкранПотокаEgov: View {
    @StateObject private var модель: МодельПотокаEgov
    private let конец: (Bool) -> Void
    @FocusState private var фокус: ПолеФормыEgov?

    init(вид: ВидПотокаEgov, конец: @escaping (Bool) -> Void) {
        _модель = StateObject(wrappedValue: МодельПотокаEgov(вид: вид))
        self.конец = конец
    }

    private func т(_ ключ: String) -> String { ТекстыEgov.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ШагиEgov(текущий: модель.номерШага, сбой: модель.сбой)
                    содержимое
                        .transition(.opacity)
                }
                .padding(16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .animation(ДвижениеСайта.шаг, value: модель.этап)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(КраскаEgov.фон.ignoresSafeArea())
            .navigationTitle(модель.вид.заголовок)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { модель.закрыть() }
                }
            }
        }
        .tint(Theme.акцент)
        .environment(\.layoutDirection, ТекстыEgov.справаНалево ? .rightToLeft : .leftToRight)
        .interactiveDismissDisabled(true)
        .sheet(isPresented: $модель.листEgov, onDismiss: { модель.толкнуть() }) {
            ЛистБиометрииEgov(модель: модель)
        }
        .onAppear { модель.конец = конец }
        .task { await модель.подготовить() }
        .onDisappear { модель.остановить() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            модель.толкнуть()
        }
    }

    @ViewBuilder
    private var содержимое: some View {
        switch модель.этап {
        case .форма, .запуск:
            форма
        case .сверка:
            сверка
        case .ожидание:
            ожидание
        case .успех:
            успех
        case .ошибка(let заголовок, let текст, let повтор):
            ошибка(заголовок: заголовок, текст: текст, повтор: повтор)
        }
    }

    // MARK: - Форма (bioKycOpen, otpStepOpen, egovAuthOpen, egovLoginConfirmOpen)

    private var этоВерификация: Bool {
        if case .верификация = модель.вид { return true }
        return false
    }

    private var этоВход: Bool {
        if case .вход = модель.вид { return true }
        return false
    }

    private var этоШаг: Bool {
        if case .шаг = модель.вид { return true }
        return false
    }

    private var форма: some View {
        VStack(alignment: .leading, spacing: 14) {
            if этоВерификация {
                КакЭтоEgov()
            }
            ЗаметкаEgov(текст: модель.вид.подсказка, символ: модель.вид.сПолями ? "faceid" : "lock.shield")
            if модель.вид.сПолями {
                поля
            }
            if этоВход {
                СогласиеEgov(принято: $модель.согласие)
            }
            if let ошибка = модель.ошибкаФормы {
                Text(ошибка)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(КраскаEgov.плохо)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
            КнопкаEgov(подпись: т("continue"), вид: .главная, идёт: модель.этап == .запуск) {
                фокус = nil
                модель.продолжить()
            }
            if модель.этап == .запуск {
                Text(т("starting"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity)
            }
            ЗамокEgov()
        }
        .disabled(модель.этап == .запуск)
    }

    private var поля: some View {
        VStack(alignment: .leading, spacing: 12) {
            ПолеEgov(подпись: т("iin"), вФокусе: фокус == .иин) {
                TextField("000000000000", text: $модель.иин)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled(true)
                    .focused($фокус, equals: .иин)
                    .accessibilityLabel(т("iin"))
            }
            ПолеEgov(подпись: т("phone"), пометка: этоВход ? т("phone_opt") : nil, вФокусе: фокус == .номер) {
                TextField("+7 (7__) ___-__-__", text: $модель.телефон)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .focused($фокус, equals: .номер)
                    .accessibilityLabel(т("phone"))
            }
            if !этоШаг {
                ПредупреждениеEgov(текст: т("phone_must"))
            }
        }
        .onChange(of: модель.иин) { было, стало in модель.правкаИИН(было: было, стало: стало) }
        .onChange(of: модель.телефон) { было, стало in модель.правкаНомера(было: было, стало: стало) }
    }

    // MARK: - Сверка «Проверьте данные» (boostConfirm перед flow_create)

    private var сверка: some View {
        VStack(alignment: .leading, spacing: 14) {
            КарточкаEgov {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(КраскаEgov.хорошо)
                            .accessibilityHidden(true)
                        Text(т("cfm_t"))
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Theme.текст)
                    }
                    Text(т("cfm_m"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                    СтрокаСверкиEgov(подпись: т("iin"), значение: модель.иин)
                    СтрокаСверкиEgov(подпись: т("phone_short"), значение: модель.номерНаСверке)
                }
            }
            ПредупреждениеEgov(текст: т("phone_must"))
            КнопкаEgov(подпись: т("cfm_ok"), вид: .главная) { модель.продолжить() }
            КнопкаEgov(подпись: т("cfm_edit"), вид: .тихая) { модель.кФорме() }
        }
    }

    // MARK: - Ожидание (_bioTick: «Подтвердите код из SMS на экране eGov. м:сс»)

    private var ожидание: some View {
        VStack(alignment: .leading, spacing: 14) {
            КарточкаEgov {
                VStack(spacing: 12) {
                    КольцоОжиданияEgov(осталось: модель.осталось, всего: МодельПотокаEgov.окно)
                    Text(т("confirm_wait"))
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(Theme.текст)
                        .multilineTextAlignment(.center)
                    Text(т("wait_s"))
                        .font(.system(size: 14))
                        .lineSpacing(3)
                        .foregroundStyle(Theme.текстВторой)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        SiteSpinner(размер: 16, толщина: 2)
                        Text(т("checking"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.текстВторой)
                    }
                    .accessibilityElement(children: .combine)
                }
                .frame(maxWidth: .infinity)
            }
            if !модель.листEgov {
                КнопкаEgov(подпись: т("reopen"), вид: .главная) { модель.листEgov = true }
            }
            КнопкаEgov(подпись: т("cancel"), вид: .тихая) { модель.кФорме() }
            ЗамокEgov()
        }
    }

    // MARK: - Итог (bioSuccess / bioAlert)

    private var успех: some View {
        VStack(spacing: 12) {
            ЗначокИтогаEgov(удача: true)
                .padding(.top, 12)
            if этоВерификация {
                Text(т("succ_title"))
                    .font(.system(size: 24, weight: .heavy))
                    .foregroundStyle(Theme.текст)
            }
            Text(модель.текстУспеха)
                .font(.system(size: 16))
                .lineSpacing(3)
                .foregroundStyle(этоВерификация ? Theme.текстВторой : Theme.текст)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if этоВерификация {
                КнопкаEgov(подпись: т("done_ok"), вид: .успех) { модель.готово() }
                    .padding(.top, 10)
            } else {
                SiteSpinner(размер: 22, толщина: 2.5)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func ошибка(заголовок: String, текст: String, повтор: Bool) -> some View {
        VStack(spacing: 12) {
            ЗначокИтогаEgov(удача: false)
                .padding(.top, 12)
            Text(заголовок)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.center)
            Text(текст)
                .font(.system(size: 15))
                .lineSpacing(3)
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 10) {
                if повтор {
                    КнопкаEgov(подпись: т("retry"), вид: .ошибка) { модель.повторить() }
                }
                КнопкаEgov(подпись: т("alert_ok"), вид: .тихая) { модель.закрыть() }
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }
}

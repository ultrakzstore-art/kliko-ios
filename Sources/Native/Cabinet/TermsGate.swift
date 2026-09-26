import SwiftUI

/**
 НОВАЯ РЕДАКЦИЯ СОГЛАШЕНИЯ — ЭТАП 40 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Как termsRenewGate кабинета сайта (карта §1.6): сервер печатает window.__TERMS_RENEW = true — при входе в кабинет
 встаёт окно, которое не закрыть ни свайпом, ни «×» (у сайта его не закрыть и Esc): «Условия обновились», редакция
 (__TERMS_VER), что изменилось (__TERMS_WHAT), «Читать соглашение» (/soglashenie.php) и две кнопки — «Выйти» (тот же
 выход, что в кабинете) и «Принимаю» → POST cabinet.php?action=terms_accept {csrf, accept: 1}, только по нажатию.
 Принято — окно закрывается, внизу кабинета «Спасибо — новая редакция принята»; сессии нет — экран входа; иначе —
 «Ошибка» с кодом сервера, окно остаётся.
 */
struct ОкноСоглашения: View {
    let редакция: String
    let пункты: [String]
    let принято: () -> Void
    let выйти: () -> Void
    let нуженВход: () -> Void
    @State private var идёт = false
    @State private var ошибка: String? = nil

    /// Явный init: окно открывает кабинет из другого файла, а приватные @State сделали бы встроенный init приватным.
    init(редакция: String, пункты: [String], принято: @escaping () -> Void, выйти: @escaping () -> Void,
         нуженВход: @escaping () -> Void) {
        self.редакция = редакция
        self.пункты = пункты
        self.принято = принято
        self.выйти = выйти
        self.нуженВход = нуженВход
    }

    private func т(_ ключ: String) -> String { ВходText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.зелёный2)
                    .frame(width: 60, height: 60)
                    .background(Theme.мята, in: Circle())
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
                Text(т("terms_renew_t"))
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                if !редакция.isEmpty {
                    Text(редакция)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                        .frame(maxWidth: .infinity)
                }
                Text(т("terms_renew_gate_s"))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.текст)
                    .fixedSize(horizontal: false, vertical: true)
                список
                if let адрес = Config.url("/soglashenie.php") {
                    Link(т("terms_renew_link"), destination: адрес)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.зелёный2)
                }
                if let ошибка {
                    Text(ошибка)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.скидкаТекст)
                        .fixedSize(horizontal: false, vertical: true)
                }
                КнопкаСайта(подпись: т("terms_renew_ok"), идёт: идёт) { принять() }
                Button(т("cab_logout"), action: выйти)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .disabled(идёт)
            }
            .padding(22)
        }
        .background(Theme.поверхность.ignoresSafeArea())
        .presentationBackground(Theme.поверхность)
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private var список: some View {
        if !пункты.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(пункты.enumerated()), id: \.offset) { пара in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(Theme.зелёный2)
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                            .accessibilityHidden(true)
                        Text(пара.element)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.текст)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        }
    }

    private func принять() {
        guard !идёт else { return }
        идёт = true
        ошибка = nil
        Task { @MainActor in
            defer { идёт = false }
            do {
                let итог = try await КабинетСайта.принятьСоглашение()
                switch итог {
                case .принято: принято()
                case .нуженВход: нуженВход()
                case .ошибка(let текст): ошибка = текст
                }
            } catch {
                ошибка = ЭкранВхода.текстСбоя(error)
            }
        }
    }
}

/**
 Сигнал сеанса в кабинете (этап 40): /api/sess_alert.php сказал, что этот сеанс завершён или что в аккаунт вошли с
 другого устройства. Тексты — __klkSA.txt сайта. Завершён — «Войти» (свой экран входа); вопрос «Это были вы?» — на
 странице кабинета сайта: ответ «нет» завершает чужой вход и может закрыть вход по паролю, поэтому натив его не шлёт.
 */
struct РазделСигналаСеанса: View {
    let сигнал: КабинетСайта.СигналСеанса
    let войти: () -> Void
    let наСайт: () -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(ВходText.т(сигнал.заголовок))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.текст)
                } icon: {
                    Image(systemName: сигнал.войти ? "person.crop.circle.badge.xmark" : "exclamationmark.shield")
                        .foregroundStyle(Theme.оранжевый)
                }
                Text(ВходText.т(сигнал.текст))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            Button(ВходText.т(сигнал.войти ? "sess_login" : "sess_answer")) {
                if сигнал.войти { войти() } else { наСайт() }
            }
            .fontWeight(.semibold)
        }
    }
}

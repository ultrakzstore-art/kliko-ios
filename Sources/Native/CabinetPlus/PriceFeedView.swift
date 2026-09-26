import SwiftUI
import UIKit

/**
 «ПОДГРУЖАТЬ ПРАЙС ПО ССЫЛКЕ» — СВОИМ ЭКРАНОМ (feedCard / feedSave / feedRun модуля js/cabinet-aiimport.min.js; владелец:
 «кабинет полностью SwiftUI»). Сайт показывает эту карточку внутри «Перенести объявления»; здесь — пункт «Для бизнеса».

   · _aiPost feed_get {} → {ok, url, enabled, formats, last_run, last_ok, last_msg};
   · _aiPost feed_save {url, enabled: 0 | 1} → ok: «Будем забирать прайс раз в сутки» / «Подгрузка выключена»;
   · _aiPost feed_run {} → {msg} — «Проверить сейчас» (ответ бывает долгим: большой прайс).
 _aiPost — multipart {csrf, payload: JSON}, тот же транспорт, что у переноса объявлений (ИмпортAPI.задание). Обновляются
 только цена и остаток у существующих объявлений; Kaspi и YML — по ссылке сразу, CSV — по разметке, подтверждённой при
 импорте файлом.
 */
@MainActor
final class ПрайсПоСсылкеМодель: ObservableObject {
    enum Состояние: Equatable { case идёт, готово, нуженВход, ошибка(String) }

    @Published private(set) var состояние: Состояние = .идёт
    @Published var адрес = ""
    @Published var включено = false
    @Published private(set) var форматы = false
    @Published private(set) var последний = ""
    @Published private(set) var последнийУдачно = false
    @Published private(set) var последнийТекст = ""
    @Published private(set) var сохраняем = false
    @Published private(set) var проверяем = false
    @Published private(set) var плашка: String? = nil
    private var скрыть: Task<Void, Never>? = nil

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    func показать(_ текст: String) {
        withAnimation(.easeOut(duration: 0.2)) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        скрыть?.cancel()
        скрыть = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self?.плашка = nil }
        }
    }

    func загрузить() async {
        do {
            let j = try await ИмпортAPI.задание("feed_get", [:])
            if МоиОбъявленияAPI.нетСессии(j) {
                состояние = .нуженВход
                return
            }
            guard МоиОбъявленияAPI.да(j["ok"]) else {
                состояние = .ошибка(ЗапросыКабинета.текстОшибки(j))
                return
            }
            адрес = МоиОбъявленияAPI.строка(j["url"])
            включено = МоиОбъявленияAPI.да(j["enabled"])
            форматы = МоиОбъявленияAPI.да(j["formats"])
            последний = МоиОбъявленияAPI.строка(j["last_run"])
            последнийУдачно = МоиОбъявленияAPI.да(j["last_ok"])
            последнийТекст = МоиОбъявленияAPI.строка(j["last_msg"])
            состояние = .готово
        } catch {
            if состояние != .готово { состояние = .ошибка(т("no_conn")) }
        }
    }

    func сохранить() {
        guard !сохраняем else { return }
        сохраняем = true
        let вкл = включено
        Task { @MainActor in
            defer { self.сохраняем = false }
            do {
                let j = try await ИмпортAPI.задание("feed_save", ["url": self.адрес.trimmingCharacters(in: .whitespaces),
                                                                  "enabled": вкл ? 1 : 0])
                if МоиОбъявленияAPI.да(j["ok"]) {
                    self.показать(self.т(вкл ? "feed_on" : "feed_off"))
                    await self.загрузить()
                } else {
                    self.показать(ЗапросыКабинета.текстОшибки(j))
                }
            } catch {
                self.показать(self.т("no_conn"))
            }
        }
    }

    func проверить() {
        guard !проверяем else { return }
        проверяем = true
        Task { @MainActor in
            defer { self.проверяем = false }
            do {
                let j = try await ИмпортAPI.задание("feed_run", [:])
                let текст = МоиОбъявленияAPI.строка(j["msg"])
                self.показать(текст.isEmpty ? self.т("feed_done") : текст)
                await self.загрузить()
            } catch {
                self.показать(self.т("feed_slow"))
            }
        }
    }

    /// «26 сентября, 14:05» — toLocaleString("ru-RU", {day, month: long, hour, minute}).
    var когдаПоследний: String {
        guard let дата = СделкиФормат.дата(последний) else { return последний }
        let ф = DateFormatter()
        ф.locale = Locale(identifier: КабинетПлюсText.локаль)
        ф.setLocalizedDateFormatFromTemplate("dMMMMHHmm")
        return ф.string(from: дата)
    }
}

struct ЭкранПрайсаПоСсылке: View {
    let открыть: (URL) -> Void

    @StateObject private var модель = ПрайсПоСсылкеМодель()
    @State private var входОткрыт = false

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var body: some View {
        Group {
            switch модель.состояние {
            case .идёт:
                ЗагрузкаБизнеса()
            case .нуженВход:
                ПустоСайта(значок: "person.crop.circle", заголовок: CabinetText.т("signed_out"),
                           кнопка: CabinetText.т("login"), действие: { входОткрыт = true })
            case .ошибка(let текст):
                ПустоСайта(значок: "wifi.exclamationmark", заголовок: текст, кнопка: т("retry"),
                           действие: { Task { await модель.загрузить() } })
            case .готово:
                содержимое
            }
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(т("feed_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await модель.загрузить() }
        .overlay(alignment: .bottom) {
            if let текст = модель.плашка { ПлашкаКошелька(текст: текст) }
        }
        .sheet(isPresented: $входОткрыт) {
            ЭкранВхода(eGovВключён: true, открыть: { ПереходыКабинета.открыть($0) }, вошли: {
                Task { await модель.загрузить() }
            })
        }
    }

    private var содержимое: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                КарточкаБизнеса(т("feed_card_t"), значок: "arrow.triangle.2.circlepath") {
                    Text(т(модель.форматы ? "feed_s_formats" : "feed_s_csv"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                    ПолеРаздела(подпись: т("feed_url"), текст: $модель.адрес, подсказка: "https://вашмагазин.kz/price.xml",
                                клавиатура: .URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Toggle(т("feed_enable"), isOn: $модель.включено)
                        .tint(Theme.акцент)
                        .font(.system(size: 15))
                    HStack(spacing: 8) {
                        КнопкаРаздела(подпись: т("feed_save"), значок: "checkmark", вид: .главная,
                                      занято: модель.сохраняем) { модель.сохранить() }
                        КнопкаРаздела(подпись: модель.проверяем ? т("feed_checking") : т("feed_run"),
                                      значок: "arrow.clockwise", занято: модель.проверяем) { модель.проверить() }
                    }
                    if !модель.последний.isEmpty {
                        ЗаметкаБизнеса("\(модель.когдаПоследний) — \(модель.последнийТекст)",
                                       тон: модель.последнийУдачно ? .хорошо : .плохо,
                                       значок: модель.последнийУдачно ? "checkmark.circle" : "exclamationmark.circle")
                    }
                }
            }
            .padding(12)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}

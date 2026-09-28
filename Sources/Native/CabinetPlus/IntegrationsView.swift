import SwiftUI
import UIKit

/**
 «ИНТЕГРАЦИИ» — СВОИМ ЭКРАНОМ (showIntegrations / intgLoad / intgRender модуля js/cabinet-business.min.js; владелец:
 «кабинет полностью SwiftUI»). За PRO: без него — замок сайта «Подключите Kliko к своей системе» и текст «Эта
 возможность недоступна в приложении.» (PRO здесь не продаётся).

   · POST cabinet.php?action=intg_state {csrf} → {ok, pro, base, keys[{id, name, prefix, scopes[], last_used}],
     hooks[{id, name, url, events[], active, last_ok, last_err, kind, has_b24_token}], scopes{код: подпись},
     events{код: подпись}, b24_events[], c1_master, c1_diffs[{id, title, c1, ours, sold}], c1_last{at, updated, missed,
     disputes}, c1_groups, c1_map};
   · ключи: intg_key_new {name, scopes[]} → {key} (показывается один раз), intg_key_revoke {id}, intg_key_log {id} →
     log[{at, m, p, r}];
   · вебхуки: intg_hook_new {name, url, events[], kind: generic | bitrix24} → {hook{secret}} | {dropped[]},
     intg_hook_on {id}, intg_hook_del {id}, intg_hook_test → {note}, intg_b24_token {id, token};
   · 1С: адрес обмена <base>/1c, кто ведёт остатки — intg_1c_stock {master: 1c | site}, расхождения — intg_1c_diff {id,
     action: accept | keep}. Сопоставление групп 1С с разделами — сводка и свой лист (ЛистСопоставления1С, intg_1c_map
     {map}); примеры кода для 1С — ПримерыКода1С (Integrations1CMap.swift).
 */
struct КлючИнтеграции: Identifiable, Equatable {
    let id: String
    let имя: String
    let префикс: String
    let области: [String]
    let последний: String
}

struct ВебхукИнтеграции: Identifiable, Equatable {
    let id: String
    let имя: String
    let адрес: String
    let события: [String]
    let включён: Bool
    let работает: Bool
    let ошибка: String
    let битрикс: Bool
    let токенБитрикс: Bool
}

struct РасхождениеОстатка: Identifiable, Equatable {
    let id: String
    let название: String
    let в1С: String
    let уНас: String
    let продано: String
}

@MainActor
final class ИнтеграцииМодель: ObservableObject {
    enum Состояние: Equatable { case идёт, готово, закрыто, нуженВход, ошибка(String) }

    @Published private(set) var состояние: Состояние = .идёт
    @Published private(set) var база = ""
    @Published private(set) var ключи: [КлючИнтеграции] = []
    @Published private(set) var вебхуки: [ВебхукИнтеграции] = []
    @Published private(set) var области: [(код: String, подпись: String)] = []
    @Published private(set) var события: [(код: String, подпись: String)] = []
    @Published private(set) var событияБитрикс: [String] = []
    @Published var ведётОстатки = "1c"
    @Published private(set) var расхождения: [РасхождениеОстатка] = []
    @Published private(set) var последнийОбмен: [String: Any] = [:]
    @Published private(set) var групп = 0
    @Published private(set) var сопоставлено = 0
    /// c1Keys сайта: группы листа сопоставления (по названию) и c1_map {код группы: slug}.
    @Published private(set) var группы1С: [ГруппаОбмена1С] = []
    @Published private(set) var карта1С: [String: String] = [:]
    /// Ключ, выпущенный в этом окне, целиком — для примеров кода (скрыт, пока не нажали «Показать ключ»).
    @Published private(set) var ключСеанса = ""
    @Published private(set) var журналы: [String: [String]] = [:]
    @Published var занято = false
    @Published private(set) var плашка: String? = nil
    private var скрыть: Task<Void, Never>? = nil

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }
    private typealias A = МоиОбъявленияAPI

    func показать(_ текст: String) {
        withAnimation(.easeOut(duration: 0.2)) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        скрыть?.cancel()
        скрыть = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { self?.плашка = nil }
        }
    }

    /// Адрес от корня сайта: «https://kliko.kz» + base.
    var адресAPI: String { Config.apiBase.absoluteString + база }

    var адрес1С: String {
        let корень = база.hasSuffix("/v1") ? String(база.dropLast(3)) : база
        return Config.apiBase.absoluteString + корень + "/1c"
    }

    var адресБитрикс: String {
        let корень = база.hasSuffix("/v1") ? String(база.dropLast(3)) : база
        return Config.apiBase.absoluteString + корень + "/b24"
    }

    private static func пары(_ сырое: Any?) -> [(код: String, подпись: String)] {
        let словарь = (сырое as? [String: Any]) ?? [:]
        return словарь.keys.sorted().map { (код: $0, подпись: МоиОбъявленияAPI.строка(словарь[$0])) }
    }

    private static func строки(_ сырое: Any?) -> [String] {
        ((сырое as? [Any]) ?? []).map { МоиОбъявленияAPI.строка($0) }.filter { !$0.isEmpty }
    }

    func загрузить() async {
        if ключи.isEmpty && вебхуки.isEmpty { состояние = .идёт }
        do {
            let j = try await ЗапросыКабинета.отправить("cabinet.php?action=intg_state", [:])
            guard A.да(j["pro"]) else {
                состояние = .закрыто
                return
            }
            база = A.строка(j["base"])
            области = Self.пары(j["scopes"])
            события = Self.пары(j["events"])
            событияБитрикс = Self.строки(j["b24_events"])
            ключи = ((j["keys"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.map { к in
                КлючИнтеграции(id: A.строка(к["id"]), имя: A.строка(к["name"]), префикс: A.строка(к["prefix"]),
                               области: Self.строки(к["scopes"]), последний: A.строка(к["last_used"]))
            }
            вебхуки = ((j["hooks"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.map { х in
                ВебхукИнтеграции(id: A.строка(х["id"]), имя: A.строка(х["name"]), адрес: A.строка(х["url"]),
                                 события: Self.строки(х["events"]), включён: A.да(х["active"]),
                                 работает: A.да(х["last_ok"]), ошибка: A.строка(х["last_err"]),
                                 битрикс: A.строка(х["kind"]) == "bitrix24", токенБитрикс: A.да(х["has_b24_token"]))
            }
            let мастер = A.строка(j["c1_master"])
            ведётОстатки = мастер == "site" ? "site" : "1c"
            расхождения = ((j["c1_diffs"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.map { р in
                РасхождениеОстатка(id: A.строка(р["id"]), название: A.строка(р["title"]), в1С: A.строка(р["c1"]),
                                   уНас: A.строка(р["ours"]), продано: A.строка(р["sold"]))
            }
            последнийОбмен = (j["c1_last"] as? [String: Any]) ?? [:]
            let группы = (j["c1_groups"] as? [String: Any]) ?? [:]
            let карта = (j["c1_map"] as? [String: Any]) ?? [:]
            let использованы = Set(Self.строки(j["c1_used"]))
            var ключиГрупп = Array(группы.keys)
            if !использованы.isEmpty {
                let занятые = ключиГрупп.filter { использованы.contains($0) }
                if !занятые.isEmpty { ключиГрупп = занятые }
            }
            группы1С = ключиГрупп.map { ГруппаОбмена1С(id: $0, имя: A.строка(группы[$0])) }
                .sorted { $0.имя.localizedStandardCompare($1.имя) == .orderedAscending }
            var новаяКарта: [String: String] = [:]
            for (код, slug) in карта {
                let значение = A.строка(slug)
                if !значение.isEmpty { новаяКарта[код] = значение }
            }
            карта1С = новаяКарта
            пересчитать1С()
            состояние = .готово
        } catch let с as ЗапросыКабинета.Сбой {
            if с.нуженВход {
                состояние = .нуженВход
            } else if с.нуженПРО {
                состояние = .закрыто
            } else if ключи.isEmpty && вебхуки.isEmpty {
                состояние = .ошибка(с.текст)
            } else {
                показать(с.текст)
            }
        } catch {
            состояние = .ошибка(т("ig_noconn"))
        }
    }

    /// Общий вызов: ok — текст успеха и перечитать; иначе текст сервера.
    private func вызвать(_ действие: String, _ тело: [String: Any], успех: String?,
                         после: (([String: Any]) -> Void)? = nil) async {
        guard !занято else { return }
        занято = true
        defer { занято = false }
        do {
            let j = try await ЗапросыКабинета.отправить("cabinet.php?action=" + действие, тело)
            if let успех { показать(т(успех)) }
            после?(j)
            await загрузить()
        } catch {
            показать(ЗапросыКабинета.текст(error))
        }
    }

    func выпуститьКлюч(имя: String, области: [String], готово: @escaping (String) -> Void) {
        guard !области.isEmpty else {
            показать(т("ig_pick_sc"))
            return
        }
        Task { await вызвать("intg_key_new", ["name": имя, "scopes": области], успех: nil) { j in
            let ключ = A.строка(j["key"])
            if !ключ.isEmpty { self.ключСеанса = ключ }
            готово(ключ)
        } }
    }

    func отозвать(_ ключ: КлючИнтеграции) {
        Task { await вызвать("intg_key_revoke", ["id": ключ.id], успех: "ig_rev_ok") }
    }

    /// intgKeyLog: последние обращения ключа (строки «дата · метод путь · ответ»).
    func журнал(_ ключ: КлючИнтеграции) {
        if журналы[ключ.id] != nil {
            журналы[ключ.id] = nil
            return
        }
        журналы[ключ.id] = [т("ig_loading")]
        Task { @MainActor in
            do {
                let j = try await ЗапросыКабинета.отправить("cabinet.php?action=intg_key_log", ["id": ключ.id])
                let строки = ((j["log"] as? [Any]) ?? []).compactMap { $0 as? [String: Any] }.map { з -> String in
                    let когда = String(A.строка(з["at"]).replacingOccurrences(of: "T", with: " ").prefix(16))
                        .replacingOccurrences(of: "-", with: ".")
                    return [когда, (A.строка(з["m"]) + " " + A.строка(з["p"])).trimmingCharacters(in: .whitespaces),
                            A.строка(з["r"])].filter { !$0.isEmpty }.joined(separator: " · ")
                }
                self.журналы[ключ.id] = строки.isEmpty ? [self.т("ig_log_none")] : строки
            } catch {
                self.журналы[ключ.id] = [ЗапросыКабинета.текст(error)]
            }
        }
    }

    func добавитьВебхук(имя: String, адрес: String, события: [String], битрикс: Bool,
                        готово: @escaping (String?) -> Void) {
        guard !события.isEmpty else {
            показать(т("ig_pick_ev"))
            return
        }
        let тело: [String: Any] = ["name": имя, "url": адрес, "events": события, "kind": битрикс ? "bitrix24" : "generic"]
        Task { await вызвать("intg_hook_new", тело, успех: битрикс ? "ig_b24_ok" : nil) { j in
            if битрикс {
                готово(nil)
            } else {
                let хук = (j["hook"] as? [String: Any]) ?? [:]
                готово(A.строка(хук["secret"]))
            }
        } }
    }

    func включить(_ хук: ВебхукИнтеграции) {
        Task { await вызвать("intg_hook_on", ["id": хук.id], успех: "ig_h_on_ok") }
    }

    func удалить(_ хук: ВебхукИнтеграции) {
        Task { await вызвать("intg_hook_del", ["id": хук.id], успех: "ig_h_del_ok") }
    }

    func проверить() {
        Task { await вызвать("intg_hook_test", [:], успех: nil) { j in
            let заметка = A.строка(j["note"])
            self.показать(заметка.isEmpty ? self.т("ig_sent") : заметка)
        } }
    }

    func токенБитрикс(_ хук: ВебхукИнтеграции, _ токен: String) {
        Task { await вызвать("intg_b24_token", ["id": хук.id, "token": токен], успех: "ig_b24_ok") }
    }

    /// intg1cMaster: смена сразу, при отказе — назад.
    func сменитьВедущего(_ новый: String) {
        let прежний = ведётОстатки
        guard новый != прежний else { return }
        ведётОстатки = новый
        Task { @MainActor in
            do {
                _ = try await ЗапросыКабинета.отправить("cabinet.php?action=intg_1c_stock", ["master": новый])
            } catch {
                self.ведётОстатки = прежний
                self.показать(ЗапросыКабинета.текст(error))
            }
        }
    }

    private func пересчитать1С() {
        групп = группы1С.count
        сопоставлено = группы1С.filter { !(карта1С[$0.id] ?? "").isEmpty }.count
    }

    /// intg1cSave прошёл: c1_map — черновик листа, сводка заново, тост c1_saved.
    func картаСохранена(_ карта: [String: String]) {
        карта1С = карта
        пересчитать1С()
        показать(Интеграции1СText.т("c1_saved"))
    }

    func расхождение(_ р: РасхождениеОстатка, принять: Bool) {
        Task { await вызвать("intg_1c_diff", ["id": р.id, "action": принять ? "accept" : "keep"], успех: "c1_ddone") }
    }
}

/// Показанный один раз ключ или секрет вебхука.
private struct ОдинРаз: Identifiable {
    let id = UUID()
    let заголовок: String
    let пояснение: String
    let значение: String
}

struct ЭкранИнтеграций: View {
    let открыть: (URL) -> Void

    @StateObject private var модель = ИнтеграцииМодель()
    @State private var новыйКлюч = false
    @State private var новыйВебхук = false
    @State private var показатьОдинРаз: ОдинРаз? = nil
    @State private var отозвать: КлючИнтеграции? = nil
    @State private var удалить: ВебхукИнтеграции? = nil
    @State private var токены: [String: String] = [:]
    @State private var входОткрыт = false
    @State private var сопоставление = false

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
            case .закрыто:
                ScrollView {
                    КарточкаБизнеса(т("ig_lock_t"), значок: "lock") {
                        Text(т("ig_lock_s"))
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                        ЦифроваяПокупка()
                    }
                    .padding(12)
                }
            case .готово:
                содержимое
            }
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .navigationTitle(т("ig_title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await модель.загрузить() }
        .refreshable { await модель.загрузить() }
        .overlay(alignment: .bottom) {
            if let текст = модель.плашка { ПлашкаКошелька(текст: текст) }
        }
        .sheet(isPresented: $новыйКлюч) {
            ЛистНовогоКлюча(области: модель.области) { имя, области in
                модель.выпуститьКлюч(имя: имя, области: области) { ключ in
                    новыйКлюч = false
                    guard !ключ.isEmpty else { return }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        показатьОдинРаз = ОдинРаз(заголовок: т("ig_key_ok"), пояснение: т("ig_key_once"), значение: ключ)
                    }
                }
            }
        }
        .sheet(isPresented: $новыйВебхук) {
            ЛистНовогоВебхука(события: модель.события, событияБитрикс: модель.событияБитрикс) { имя, адрес, события, битрикс in
                модель.добавитьВебхук(имя: имя, адрес: адрес, события: события, битрикс: битрикс) { секрет in
                    новыйВебхук = false
                    guard let секрет, !секрет.isEmpty else { return }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        показатьОдинРаз = ОдинРаз(заголовок: т("ig_h_ok_t"), пояснение: т("ig_sec_once") + "\n"
                                                  + т("ig_sec_how"), значение: секрет)
                    }
                }
            }
        }
        .sheet(item: $показатьОдинРаз) { о in
            ЛистОдинРаз(данные: о) { показатьОдинРаз = nil }
        }
        .sheet(isPresented: $входОткрыт) {
            ЭкранВхода(eGovВключён: true, открыть: { ПереходыКабинета.открыть($0) }, вошли: {
                Task { await модель.загрузить() }
            })
        }
        .alert(т("ig_rev_ask").replacingOccurrences(of: "{n}", with: отозвать?.имя ?? ""), isPresented: Binding(get: { отозвать != nil }, set: { if !$0 { отозвать = nil } })) {
            Button(т("ig_rev_yes"), role: .destructive) {
                if let к = отозвать { модель.отозвать(к) }
                отозвать = nil
            }
            Button(CabinetText.т("cancel"), role: .cancel) { отозвать = nil }
        }
        .alert(т("ig_h_del_q"), isPresented: Binding(get: { удалить != nil }, set: { if !$0 { удалить = nil } })) {
            Button(т("ig_h_del_yes"), role: .destructive) {
                if let х = удалить { модель.удалить(х) }
                удалить = nil
            }
            Button(CabinetText.т("cancel"), role: .cancel) { удалить = nil }
        }
    }

    private var содержимое: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(т("ig_sub"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
                КарточкаБизнеса(т("ig_api"), значок: "network") {
                    СтрокаКопирования(текст: модель.адресAPI) { модель.показать(т("ig_copied_ok")) }
                    Text(т("ig_api_s"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ключи
                вебхуки
                обмен1С
                ПримерыКода1С(база: модель.база, ключ: модель.ключСеанса) { модель.показать(т("ig_copied_ok")) }
            }
            .padding(12)
        }
    }

    // MARK: Ключи

    private var ключи: some View {
        КарточкаБизнеса(т("ig_keys_h"), значок: "key") {
            if модель.ключи.isEmpty {
                Text(т("ig_keys_e"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
            ForEach(модель.ключи) { к in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(к.имя.isEmpty ? т("ig_key") : к.имя)
                                .font(.system(size: 14.5, weight: .bold))
                            Text(к.префикс + "…")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.текстВторой)
                        }
                        Spacer(minLength: 6)
                        Button(role: .destructive) {
                            отозвать = к
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .accessibilityLabel(т("ig_revoke"))
                    }
                    метки(к.области.map { код in модель.области.first(where: { $0.код == код })?.подпись ?? код })
                    Text(к.последний.isEmpty ? т("ig_never")
                         : т("ig_last").replacingOccurrences(of: "{d}", with: String(к.последний.prefix(10))))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                    Button(модель.журналы[к.id] == nil ? т("ig_log_show") : т("ig_log_hide")) { модель.журнал(к) }
                        .font(.system(size: 12.5, weight: .semibold))
                        .tint(Theme.акцент)
                    if let строки = модель.журналы[к.id] {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(строки.enumerated()), id: \.offset) { _, строка in
                                Text(строка)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(Theme.текстВторой)
                            }
                        }
                    }
                }
                .padding(10)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
            КнопкаБизнеса(подпись: т("ig_key_new"), занято: модель.занято) { новыйКлюч = true }
        }
    }

    // MARK: Вебхуки

    private var вебхуки: some View {
        КарточкаБизнеса(т("ig_hooks_h"), значок: "bolt.horizontal") {
            Text(т("ig_hooks_s"))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            if модель.вебхуки.isEmpty {
                Text(т("ig_hooks_e"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
            ForEach(модель.вебхуки) { х in
                вебхук(х)
            }
            if !модель.вебхуки.isEmpty {
                КнопкаРаздела(подпись: т("ig_h_test"), значок: "paperplane", занято: модель.занято) { модель.проверить() }
            }
            КнопкаБизнеса(подпись: т("ig_h_add"), занято: модель.занято) { новыйВебхук = true }
        }
    }

    private func вебхук(_ х: ВебхукИнтеграции) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text((х.имя.isEmpty ? т("ig_hook") : х.имя) + (х.битрикс ? " · Bitrix24" : ""))
                        .font(.system(size: 14.5, weight: .bold))
                    Text(х.адрес)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.текстВторой)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                if !х.включён {
                    Button {
                        модель.включить(х)
                    } label: {
                        Image(systemName: "power")
                    }
                    .accessibilityLabel(т("ig_h_on"))
                }
                Button(role: .destructive) {
                    удалить = х
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(т("ig_del"))
            }
            метки(х.события.map { код in модель.события.first(where: { $0.код == код })?.подпись ?? код })
            Text(состояние(х))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(х.включён && х.ошибка.isEmpty ? КраскаОбъявлений.хорошоТекст
                                 : (х.включён && х.работает == false && х.ошибка.isEmpty ? Theme.текстВторой
                                    : КраскаОбъявлений.плохоТекст))
            if х.битрикс {
                VStack(alignment: .leading, spacing: 6) {
                    Text(т("ig_b24_back_h") + (х.токенБитрикс ? " · " + т("ig_b24_set") : ""))
                        .font(.system(size: 13, weight: .bold))
                    Text(т("ig_b24_back_s"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                    СтрокаКопирования(текст: модель.адресБитрикс) { модель.показать(т("ig_copied_ok")) }
                    ПолеРаздела(подпись: т("ig_b24_tok"), текст: Binding(get: { токены[х.id] ?? "" },
                                                                         set: { токены[х.id] = $0 }),
                                подсказка: х.токенБитрикс ? "••••••••" : "application_token")
                    КнопкаРаздела(подпись: т("ig_b24_save"), занято: модель.занято) {
                        модель.токенБитрикс(х, токены[х.id] ?? "")
                        токены[х.id] = ""
                    }
                    Text(т("ig_b24_what"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
    }

    private func состояние(_ х: ВебхукИнтеграции) -> String {
        if !х.включён {
            return т("ig_h_off") + (х.ошибка.isEmpty ? "" : " · " + х.ошибка)
        }
        if !х.ошибка.isEmpty { return т("ig_h_err").replacingOccurrences(of: "{e}", with: х.ошибка) }
        return х.работает ? т("ig_h_ok") : т("ig_h_new")
    }

    // MARK: 1С

    private var обмен1С: some View {
        КарточкаБизнеса(т("ig_1c_h"), значок: "arrow.left.arrow.right.square") {
            содержимое1С
        }
        .sheet(isPresented: $сопоставление) {
            ЛистСопоставления1С(группы: модель.группы1С, карта: модель.карта1С) { карта in
                модель.картаСохранена(карта)
            }
        }
    }

    @ViewBuilder
    private var содержимое1С: some View {
        Group {
            Text(т("ig_1c_s").replacingOccurrences(of: "{b}", with: т("ig_1c_node")))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            СтрокаКопирования(текст: модель.адрес1С) { модель.показать(т("ig_copied_ok")) }
            VStack(spacing: 6) {
                пара(т("ig_1c_lg"), т("ig_1c_lgv"))
                пара(т("ig_1c_pw"), т("ig_1c_pwv"))
                пара(т("ig_1c_out"), т("ig_1c_outv"))
                пара(т("ig_1c_in"), т("ig_1c_inv"))
            }
            Text(т("ig_1c_hint"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            последний
            сопоставлениеИОстатки
            if !модель.расхождения.isEmpty {
                расхождения
            }
        }
    }

    @ViewBuilder
    private var сопоставлениеИОстатки: some View {
        Group {
            Divider()
            Text(т("c1_h"))
                .font(.system(size: 13.5, weight: .bold))
            Text(модель.групп == 0 ? т("c1_first")
                 : т("c1_done").replacingOccurrences(of: "{a}", with: String(модель.сопоставлено))
                    .replacingOccurrences(of: "{b}", with: String(модель.групп)))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            if модель.групп > 0 {
                let ждут = модель.групп - модель.сопоставлено
                if ждут > 0 {
                    Text(Интеграции1СText.т("c1_wait").replacingOccurrences(of: "{n}", with: String(ждут)))
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(КраскаОбъявлений.предупреждениеТекст)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(КраскаОбъявлений.предупреждениеФон, in: Capsule())
                    Text(Интеграции1СText.т("c1_gap"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
                КнопкаБизнеса(подпись: Интеграции1СText.т(ждут > 0 ? "c1_set" : "c1_edit"), второстепенная: ждут == 0) {
                    сопоставление = true
                }
            }
            Divider()
            Text(т("c1_mh"))
                .font(.system(size: 13.5, weight: .bold))
            ВкладкиРаздела(варианты: [("1c", т("c1_m1c")), ("site", т("c1_msite"))],
                           выбрано: Binding(get: { модель.ведётОстатки }, set: { модель.сменитьВедущего($0) }))
            Text(модель.ведётОстатки == "site" ? т("c1_mh_st") : т("c1_mh_1c"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var расхождения: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("\(т("c1_dh")) · \(модель.расхождения.count)")
                .font(.system(size: 13.5, weight: .bold))
            Text(т("c1_ds"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(модель.расхождения) { р in
                VStack(alignment: .leading, spacing: 6) {
                    Text(р.название.isEmpty ? р.id : р.название)
                        .font(.system(size: 13.5, weight: .bold))
                    Text(т("c1_drow").replacingOccurrences(of: "{a}", with: р.в1С)
                        .replacingOccurrences(of: "{b}", with: р.уНас).replacingOccurrences(of: "{c}", with: р.продано))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                    HStack(spacing: 8) {
                        КнопкаРаздела(подпись: т("c1_dtake"), вид: .главная, занято: модель.занято) {
                            модель.расхождение(р, принять: true)
                        }
                        КнопкаРаздела(подпись: т("c1_dkeep"), занято: модель.занято) {
                            модель.расхождение(р, принять: false)
                        }
                    }
                }
                .padding(10)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var последний: some View {
        let з = модель.последнийОбмен
        let когда = МоиОбъявленияAPI.строка(з["at"])
        if !когда.isEmpty {
            let пропущено = МоиОбъявленияAPI.целое(з["missed"])
            let споров = МоиОбъявленияAPI.целое(з["disputes"])
            VStack(spacing: 6) {
                пара(т("ig_1c_last_when"), String(когда.replacingOccurrences(of: "T", with: " ").prefix(16))
                    .replacingOccurrences(of: "-", with: "."))
                пара(т("ig_1c_last_upd"), String(МоиОбъявленияAPI.целое(з["updated"])))
                if пропущено > 0 {
                    пара(т("ig_1c_last_miss"), String(пропущено))
                    Text(т("ig_1c_last_miss_s"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(КраскаОбъявлений.плохоТекст)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if споров > 0 {
                    пара(т("ig_1c_last_disp"), String(споров))
                }
            }
            .padding(10)
            .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
    }

    private func пара(_ подпись: String, _ значение: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(подпись)
                .foregroundStyle(Theme.текстВторой)
            Spacer(minLength: 8)
            Text(значение)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.текст)
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 12.5))
        .accessibilityElement(children: .combine)
    }

    private func метки(_ подписи: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(Array(подписи.enumerated()), id: \.offset) { _, подпись in
                    Text(подпись)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.акцент)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.оттенокАкцента, in: Capsule())
                }
            }
        }
    }
}

// MARK: - Листы

/// intgKeyForm: название и области доступа.
private struct ЛистНовогоКлюча: View {
    let области: [(код: String, подпись: String)]
    let выпустить: (String, [String]) -> Void

    @Environment(\.dismiss) private var закрыть
    @State private var имя = ""
    @State private var выбраны: Set<String> = []

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var body: some View {
        NavigationStack {
            Form {
                Section(т("ig_key_nm")) {
                    TextField(т("ig_key_nm_p"), text: $имя)
                }
                Section {
                    ForEach(области, id: \.код) { о in
                        Toggle(isOn: Binding(get: { выбраны.contains(о.код) }, set: { да in
                            if да { выбраны.insert(о.код) } else { выбраны.remove(о.код) }
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(о.подпись)
                                Text(о.код)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(Theme.текстВторой)
                            }
                        }
                        .tint(Theme.акцент)
                    }
                } header: {
                    Text(т("ig_allow"))
                } footer: {
                    Text(т("ig_allow_h"))
                }
            }
            .navigationTitle(т("ig_key_new_t"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CabinetText.т("cancel")) { закрыть() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(т("ig_issue")) {
                        выпустить(String(имя.prefix(60)), области.map { $0.код }.filter { выбраны.contains($0) })
                    }
                }
            }
        }
        .tint(Theme.акцент)
    }
}

/// intgHookForm: своя система или Bitrix24, название, адрес, события.
private struct ЛистНовогоВебхука: View {
    let события: [(код: String, подпись: String)]
    let событияБитрикс: [String]
    let добавить: (String, String, [String], Bool) -> Void

    @Environment(\.dismiss) private var закрыть
    @State private var битрикс = false
    @State private var имя = ""
    @State private var адрес = ""
    @State private var выбраны: Set<String> = []

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    private var доступные: [(код: String, подпись: String)] {
        битрикс ? события.filter { событияБитрикс.contains($0.код) } : события
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(т("ig_where")) {
                    Picker(т("ig_where"), selection: $битрикс) {
                        Text(т("ig_own")).tag(false)
                        Text("Bitrix24").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                Section(т("ig_name")) {
                    TextField(т("ig_h_nm_p"), text: $имя)
                }
                Section {
                    TextField(битрикс ? т("ig_b24_ph") : "https://…", text: $адрес)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(т("ig_url_l"))
                } footer: {
                    Text(битрикс ? т("ig_b24_h").replacingOccurrences(of: "{b}", with: т("ig_b24_dev"))
                            .replacingOccurrences(of: "{c}", with: "crm")
                            .replacingOccurrences(of: "{p}", with: "/rest/1/" + т("ig_b24_tok") + "/")
                         : т("ig_url_h"))
                }
                Section(т("ig_ev_l")) {
                    ForEach(доступные, id: \.код) { с in
                        Toggle(isOn: Binding(get: { выбраны.contains(с.код) }, set: { да in
                            if да { выбраны.insert(с.код) } else { выбраны.remove(с.код) }
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(с.подпись)
                                Text(с.код)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(Theme.текстВторой)
                            }
                        }
                        .tint(Theme.акцент)
                    }
                }
            }
            .navigationTitle(т("ig_h_new_t"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(CabinetText.т("cancel")) { закрыть() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(т("ig_add")) {
                        let коды = доступные.map { $0.код }.filter { выбраны.contains($0) }
                        добавить(String(имя.prefix(60)), адрес.trimmingCharacters(in: .whitespacesAndNewlines), коды, битрикс)
                    }
                }
            }
        }
        .tint(Theme.акцент)
    }
}

/// intgKeyShow / секрет вебхука: значение один раз, «Копировать» и «Я скопировал».
private struct ЛистОдинРаз: View {
    let данные: ОдинРаз
    let готово: () -> Void

    @State private var скопировано = false

    private func т(_ ключ: String) -> String { КабинетПлюсText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ЗаметкаБизнеса(данные.пояснение
                        .replacingOccurrences(of: "{a}", with: "HMAC-SHA256")
                        .replacingOccurrences(of: "{b}", with: "X-Kliko-Signature"),
                                   тон: .предупреждение, значок: "exclamationmark.triangle")
                    СтрокаКопирования(текст: данные.значение) { скопировано = true }
                    if скопировано {
                        Text(т("ig_copied_ok"))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(КраскаОбъявлений.хорошоТекст)
                    }
                    КнопкаБизнеса(подпись: т("ig_copied")) { готово() }
                }
                .padding(16)
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(данные.заголовок)
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}

import SwiftUI
import UIKit

/**
 «СВОЙ ИИ» В НОВЫХ МЕСТАХ — ПРЕДЛОЖЕНИЕ ДОГОВОРА (docs/OWN_AI_COVERAGE.md, раздел «Б»), ЗА РУБИЛЬНИКОМ
 Config.свойИИНовыеМеста (выключен, пока ultra-site не ответит).

 Сейчас всегда на Kliko AI: ассистент в чате по объявлению, проверка объявлений; объяснений о товаре и ИИ-поддержки у
 сервера нет; примерочная (docs/SERVER_TRYON.md §6) берёт свой ИИ сама, если поставщик рисует картинки; студия фото
 техники — на телефоне, без сервера. Предложено: по желанию человека свой ИИ и там — переключатели на экране «Свой ИИ».
 Сервер присылает список мест сам, добавлением к объекту own_ai:
   own_ai.places: [{id, label, on, avail, why}] — id: assist · explain · support · tryon · studio · precheck;
     label — подпись на языке человека; on — человек включил здесь свой ИИ; avail — поставщик и модель это умеют
     (примерочная и фоторедактор — только поставщики с генерацией картинок); why — готовый текст, почему нельзя.
   own_ai_place {csrf, place, on} → {ok:true, own_ai} | {ok:false, code, error, own_ai} — тем же транспортом, что
     остальные own_ai_* (СвойИИAPI: сессия кабинета, csrf, один повтор на «csrf»).
 Модерация (решение «пропустить или отклонить») своим ИИ не делается никогда: ключом и моделью управляет сам продавец,
 и через «мягкую» модель на OpenRouter он мог бы пропустить запрещённое. precheck — только подсказка до отправки, решение
 остаётся за Kliko AI.

 🔴 ЧЕСТНЫЙ ОТКАТ. Рубильник выключен или старый сервер поля places не шлёт — блока нет вовсе, экран как раньше.
 Отказы своего ИИ в новых местах — тем же форматом, что ai_style / photo_search (own_ai:"<код>", текст в error), их
 разбирает ОтказСвоегоИИ.из, окно — ОкноСвоегоИИ.показатьЕслиОтказ.
 */
extension Config {
    /// Переключатели «Свой ИИ в других местах» на экране «Свой ИИ» (own_ai.places / own_ai_place). Включать — когда
    /// ultra-site подтвердит раздел «Б» docs/OWN_AI_COVERAGE.md.
    static let свойИИНовыеМеста = false
}

/// Место из own_ai.places, где человек может включить свой ИИ по желанию.
struct МестоСвоегоИИ: Identifiable, Equatable {
    let id: String
    let подпись: String
    /// on — здесь отвечает свой ИИ.
    let вкл: Bool
    /// avail — поставщик и модель это умеют; нет поля — умеют.
    let можно: Bool
    /// why — готовый текст сервера, почему нельзя.
    let почему: String

    /// own_ai.places. Повторы id пропускаются; незнакомое место без label сервера не показываем.
    static func список(_ значение: Any?) -> [МестоСвоегоИИ] {
        typealias A = МоиОбъявленияAPI
        var итог: [МестоСвоегоИИ] = []
        for элемент in (значение as? [Any]) ?? [] {
            guard let м = элемент as? [String: Any] else { continue }
            let id = A.строка(м["id"]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !итог.contains(where: { $0.id == id }) else { continue }
            var подпись = A.строка(м["label"]).trimmingCharacters(in: .whitespacesAndNewlines)
            if подпись.isEmpty { подпись = СвойИИМестаText.подписьМеста(id) ?? "" }
            guard !подпись.isEmpty else { continue }
            let безПоля = м["avail"] == nil || м["avail"] is NSNull
            let можно = безПоля ? true : A.да(м["avail"])
            let почему = A.строка(м["why"]).trimmingCharacters(in: .whitespacesAndNewlines)
            итог.append(МестоСвоегоИИ(id: id, подпись: подпись, вкл: A.да(м["on"]), можно: можно, почему: почему))
        }
        return итог
    }
}

// MARK: - Блок на экране «Свой ИИ»

/// «Свой ИИ в других местах»: переключатель на каждое место own_ai.places. Только по нажатию — own_ai_place.
struct БлокМестСвоегоИИ: View {
    let места: [МестоСвоегоИИ]
    /// id места, которое сейчас переключается.
    @State private var занято: String? = nil
    @State private var итог: String? = nil
    @State private var итогТон: ЗаметкаБизнеса.Тон = .инфо

    init(места: [МестоСвоегоИИ]) {
        self.места = места
    }

    private func т(_ ключ: String) -> String { СвойИИМестаText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(т("oaip_t"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.текст)
                .accessibilityAddTraits(.isHeader)
            Text(т("oaip_s"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(места) { место in
                строка(место)
            }
            if let итог {
                ЗаметкаБизнеса(итог, тон: итогТон,
                               значок: итогТон == .плохо ? "exclamationmark.triangle" : "info.circle")
            }
        }
        .padding(.top, 4)
    }

    private func строка(_ место: МестоСвоегоИИ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(isOn: Binding(get: { место.вкл }, set: { новое in переключить(место, новое) })) {
                HStack(spacing: 6) {
                    Text(место.подпись)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(место.можно ? Theme.текст : Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                    if занято == место.id {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.акцент)
                    }
                }
            }
            .tint(Theme.акцент)
            .disabled(занято != nil || !место.можно)
            if !место.можно {
                Text(место.почему.isEmpty ? т("oaip_na") : место.почему)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// own_ai_place {place, on}. Новое состояние приходит объектом own_ai ответа (СвойИИAPI кладёт его в модель).
    private func переключить(_ место: МестоСвоегоИИ, _ вкл: Bool) {
        guard занято == nil, место.можно else { return }
        занято = место.id
        итог = nil
        Task { @MainActor in
            let ответ = await СвойИИAPI.выполнить("own_ai_place", ["place": место.id, "on": вкл])
            занято = nil
            switch ответ {
            case .готово:
                показать(т(вкл ? "oaip_on" : "oaip_off"), .инфо)
            case .отказ(let текст, _, _):
                показать(текст, .плохо)
            case .нуженВход:
                показать(СвойИИText.т("oai_need_login"), .плохо)
            case .сеть:
                показать(СвойИИText.т("oai_no_conn"), .плохо)
            }
        }
    }

    private func показать(_ текст: String, _ тон: ЗаметкаБизнеса.Тон) {
        итог = текст
        итогТон = тон
        UIAccessibility.post(notification: .announcement, argument: текст)
    }

    /// Заметка экрана о том, что всегда на Kliko AI: сервер дал включить ассистента — всегда только модерация.
    static func заметка(_ с: СостояниеСвоегоИИ?) -> String {
        guard Config.свойИИНовыеМеста, let с, с.места.contains(where: { $0.id == "assist" }) else {
            return СвойИИText.т("oai_keep")
        }
        return СвойИИМестаText.т("oaip_keep")
    }
}

// MARK: - Отказ своего ИИ в новых местах

extension ОкноСвоегоИИ {
    /**
     Для экранов новых мест (примерочная, фоторедактор, объяснения, поддержка) и любых будущих ИИ-функций: в ответе
     отказ своего ИИ (own_ai:"<код>" или own_ai_gone и готовый текст, §5) — окно с действиями. ok не смотрим: у
     примерочной отказ приходит и в {ok:true, state:"failed", code:"own_ai"} (docs/SERVER_TRYON.md). одинРаз — живые и
     фоновые запросы: окно раз за запуск на код. Итог — отказ (его текст — под полем экрана) или nil.
     */
    @discardableResult
    static func показатьЕслиОтказ(_ j: [String: Any], одинРаз: Bool = false) -> ОтказСвоегоИИ? {
        guard let отказ = ОтказСвоегоИИ.из(j) else { return nil }
        if одинРаз {
            СвойИИМодель.shared.сказатьОдинРаз(отказ)
        } else {
            показатьОтказ(отказ)
        }
        return отказ
    }
}

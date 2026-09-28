import SwiftUI
import UIKit

/**
 МАСТЕР УСЛУГИ (TestFlight, владелец: «Услуга так же не верно настроена»). Как у сайта (#svc-wizard-panel,
 addEnterServiceMode): у услуги первый шаг — не «Фото» (у сайта фото услуги свёрнуто, «Фото для услуги
 необязательно»), а мастер: 1) «Чем хотите заняться?» — направления из раздела «Услуги» (первые три подраздела —
 подписью), 2) «Что чините?» (вопрос и пример — _SVC_DIR_Q по направлению), подразделы чипами, «Что входит, ваши
 плюсы?», «Цена от, ₸», «Город» и «Собрать объявление» — POST cabinet.php?action=ai_service {do, includes, price, city,
 dir}: Kliko AI подбирает раздел, пишет заголовок и описание (svcWizardRun модуля compose). Дальше — те же шаги:
 «Данные», «Цена» (необязательна, «Договорная»), «Адрес» (режим работы обязателен), «Дополнительно», «Проверка».
 Своё фото — по кнопке «Добавить своё фото». Постер-обложку (canvas сайта) приложение не рисует.
 */

/// Ответы мастера услуги — живут в модели, пока идёт подача (шаги туда-обратно их не теряют).
struct ЗаготовкаУслуги: Equatable {
    var направление: String = ""
    var что: String = ""
    var плюсы: String = ""
    var цена: String = ""
    var город: String = ""
    /// «Собрать объявление» уже сработал — название и описание в форме.
    var собрано = false
}

extension ПодачаМодель {
    /// Направление услуги по разделу формы: подраздел «Услуг» в цепочке (restore черновика, «Изменить»).
    var направлениеИзРаздела: String {
        let цепочка = справочники.цепочка(форма.раздел)
        guard цепочка.count >= 2, цепочка[0] == "services" else { return "" }
        return цепочка[1]
    }

    /// svcWizardRun: «Опишите, что вы делаете» без текста; дальше ai_service и разбор ответа.
    func собратьУслугу() {
        let у = услуга
        let что = у.что.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !что.isEmpty else {
            пометить("svc_do", МастерПодачиText.т("svc_need"))
            return
        }
        guard !собираемУслугу else { return }
        собираемУслугу = true
        let цена = Self.цифры(у.цена)
        let город = у.город.trimmingCharacters(in: .whitespacesAndNewlines)
        let тело: [String: Any] = ["do": что, "includes": у.плюсы.trimmingCharacters(in: .whitespacesAndNewlines),
                                   "price": цена, "city": город, "dir": у.направление]
        Task { @MainActor in
            let итог = await self.сПределом(55) {
                try await МоиОбъявленияAPI.отправить("cabinet.php?action=ai_service", тело: тело)
            }
            self.собираемУслугу = false
            switch итог {
            case .ответ(let j):
                self.разобратьУслугу(j, цена: цена, город: город)
            case .долго, .сбой:
                self.показать(ПодачаText.т("no_conn"))
            }
        }
    }

    private func разобратьУслугу(_ j: [String: Any], цена: String, город: String) {
        typealias A = МоиОбъявленияAPI
        let тм = МастерПодачиText.т
        guard A.да(j["ok"]) else {
            if A.нетСессии(j) {
                войти = true
                return
            }
            let текст = A.строка(j["msg"]).trimmingCharacters(in: .whitespacesAndNewlines)
            if A.да(j["slots_full"]) {
                let пояснение = текст.isEmpty ? т("limit_d") : текст
                if A.да(j["verify_required"]) {
                    вопрос = ВопросПодачи(заголовок: тм("svc_limit_t"), текст: пояснение, да: т("verify_plus5"),
                                          нет: тм("svc_manual"),
                                          действие: { [weak self] in self?.открытьСтраницу = "cabinet.php?go=verify" })
                } else if Config.цифровыеПокупки {
                    вопрос = ВопросПодачи(заголовок: тм("svc_limit_t"), текст: пояснение, да: т("slots_more"),
                                          нет: тм("svc_manual"), действие: { ЛистУслугиApple.показать(.слоты) })
                } else {
                    сообщение = СообщениеПодачи(заголовок: тм("svc_limit_t"), текст: пояснение)
                }
                return
            }
            /* need_paid: платный Kliko AI в приложении не продаётся — только текст сервера. */
            показать(текст.isEmpty || КабинетСайта.машинныйКод(текст) ? тм("svc_fail") : текст)
            return
        }
        let ответРаздел = A.строка(j["category"])
        let раздел = ответРаздел.isEmpty ? услуга.направление : ответРаздел
        if !раздел.isEmpty && справочники.разделы[раздел] != nil && справочники.внутри(раздел, ["services"]) {
            выбратьРаздел(раздел)
        }
        var ф = форма
        let название = A.строка(j["title"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !название.isEmpty { ф.название = название }
        let описание = A.строка(j["description"]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !описание.isEmpty { ф.описание = описание }
        if !цена.isEmpty { ф.цена = цена }
        if !город.isEmpty { ф.город = город }
        форма = ф
        услуга.собрано = true
        ОткликСайта.успех()
        показать(тм("svc_done"))
        if шаг == .фото { перейти(к: .данные) }
    }
}

/// #svc-wizard-panel: шаг 1 — направления карточками, шаг 2 — вопросы и «Собрать объявление».
struct МастерУслугиВид: View {
    @ObservedObject var модель: ПодачаМодель
    let фокус: FocusState<String?>.Binding

    init(модель: ПодачаМодель, фокус: FocusState<String?>.Binding) {
        self.модель = модель
        self.фокус = фокус
    }

    private func т(_ ключ: String) -> String { МастерПодачиText.т(ключ) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if модель.услуга.направление.isEmpty {
                направления
            } else {
                вопросы
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(КраскаПодачи.карточка, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(КраскаПодачи.линия, lineWidth: 1)
        }
        .shadow(color: КраскаПодачи.тень, radius: 6, y: 2)
        .onAppear { подхватить() }
        .onChange(of: модель.услуга.что) { _, _ in
            if модель.ошибка("svc_do") != nil { модель.ошибкиПолей.removeValue(forKey: "svc_do") }
        }
    }

    /// Раздел формы уже внутри «Услуг» (черновик, возврат на шаг) — сразу вопросы этого направления; город — из формы.
    @MainActor
    private func подхватить() {
        if модель.услуга.направление.isEmpty && !модель.услуга.собрано {
            let н = модель.направлениеИзРаздела
            if !н.isEmpty { модель.услуга.направление = н }
        }
        if модель.услуга.город.isEmpty && !модель.форма.город.isEmpty {
            модель.услуга.город = модель.форма.город
        }
    }

    // MARK: Шаг 1 — направления (svcWizBuildCards)

    private var направления: some View {
        let дети = модель.справочники.разделы["services"]?.дети ?? []
        return VStack(alignment: .leading, spacing: 12) {
            ВопросМастераПодачи(т("svc_pick"), пояснение: т("svc_pick_s"))
            VStack(spacing: 8) {
                ForEach(дети, id: \.self) { к in
                    ПлиткаМастераПодачи(имя(к), пояснение: подпись(к), значок: Self.значок(к), выбрана: false) {
                        выбрать(к)
                    }
                }
            }
        }
    }

    private func имя(_ ключ: String) -> String {
        let и = модель.справочники.имя(ключ)
        return и.isEmpty ? ключ : и
    }

    /// Первые три подраздела через запятую — подпись карточки направления.
    private func подпись(_ ключ: String) -> String {
        let дети = модель.справочники.разделы[ключ]?.дети ?? []
        return дети.prefix(3).map { модель.справочники.имя($0) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    static func значок(_ направление: String) -> String {
        switch направление {
        case "tech-repair": return "wrench.adjustable"
        case "repair-construction": return "hammer"
        case "auto-services": return "car"
        case "beauty-health": return "sparkles"
        case "tutors-education": return "graduationcap"
        case "it-development": return "chevron.left.forwardslash.chevron.right"
        case "delivery-courier": return "shippingbox"
        case "photo-video-svc": return "camera"
        case "events": return "party.popper"
        case "legal-financial": return "building.columns"
        case "translation": return "globe"
        default: return "ellipsis.circle"
        }
    }

    /// svcWizPickDir: направление — раздел формы сразу (catCascadeSetPath), ответ «Что делаете» — заново.
    @MainActor
    private func выбрать(_ ключ: String) {
        ОткликСайта.выбор()
        if модель.услуга.направление != ключ { модель.услуга.что = "" }
        модель.услуга.направление = ключ
        модель.выбратьРаздел(ключ)
        if модель.услуга.город.isEmpty { модель.услуга.город = модель.форма.город }
    }

    // MARK: Шаг 2 — вопросы (svc-wiz-step2)

    private var вопросы: some View {
        let н = модель.услуга.направление
        let ошибка = модель.ошибка("svc_do")
        return VStack(alignment: .leading, spacing: 14) {
            Button {
                модель.услуга.направление = ""
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                    Text(имя(н) + " · " + т("svc_change"))
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.текстВторой)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 8) {
                ПодписьПоля(вопрос(н))
                TextField(пример(н), text: $модель.услуга.что, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(2...5)
                    .foregroundStyle(КраскаПодачи.текст)
                    .modifier(ФокусПоля(фокус: фокус, ключ: "svc_do"))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(КраскаПодачи.поле, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                            .strokeBorder(ошибка != nil ? Theme.ценаСкидка : КраскаПодачи.линия, lineWidth: ошибка != nil ? 2 : 1)
                    }
                СтрокаОшибки(ошибка)
                чипы(н)
            }
            .id("svc_do")
            VStack(alignment: .leading, spacing: 8) {
                ПодписьПоля(т("svc_q2") + " · " + т("svc_opt"))
                ПолеПодачи(т("svc_q2_ph"), текст: $модель.услуга.плюсы, фокус: фокус, ключ: "svc_inc")
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    ПодписьПоля(т("svc_price"), мелкая: true)
                    ПолеПодачи("5000", текст: ценаСвязь, клавиатура: .numberPad, фокус: фокус, ключ: "svc_price")
                }
                VStack(alignment: .leading, spacing: 8) {
                    ПодписьПоля(т("svc_city"), мелкая: true)
                    ПолеПодачи(т("svc_city_ph"), текст: $модель.услуга.город, заглавные: .words, фокус: фокус,
                               ключ: "svc_city")
                }
            }
            кнопкаСобрать
            Text(т("svc_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func вопрос(_ н: String) -> String {
        let свой = т("sq_" + н)
        return свой == "sq_" + н ? т("svc_q1") : свой
    }

    private func пример(_ н: String) -> String {
        let свой = т("sp_" + н)
        return свой == "sp_" + н ? т("svc_q1_ph") : свой
    }

    /// svcWizBuildChips: до 12 подразделов направления — нажатие пишет подраздел в «Что делаете».
    private func чипы(_ н: String) -> some View {
        let дети = Array((модель.справочники.разделы[н]?.дети ?? []).prefix(12))
        return ПотокЧипов(зазор: 6) {
            ForEach(дети, id: \.self) { к in
                let подпись = имя(к)
                ЧипПодачи(подпись, выбран: модель.услуга.что == подпись) {
                    модель.услуга.что = подпись
                }
            }
        }
    }

    private var ценаСвязь: Binding<String> {
        let м = модель
        return Binding(get: { м.услуга.цена }, set: { новое in
            м.услуга.цена = ПодачаМодель.цифры(новое, предел: 9)
        })
    }

    /// .svc-wiz-go: градиент --g → --g2, «✦ Собрать объявление»; пока собирается — шаги svc_prog_1…3.
    @ViewBuilder
    private var кнопкаСобрать: some View {
        if модель.собираемУслугу {
            TimelineView(.periodic(from: .now, by: 1.5)) { время in
                let номер = Int(время.date.timeIntervalSinceReferenceDate / 1.5) % 3 + 1
                HStack(spacing: 10) {
                    SiteSpinner()
                    Text(т("svc_prog_" + String(номер)))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(КраскаПодачи.хорошоТекст)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            }
        } else {
            Button {
                фокус.wrappedValue = nil
                модель.собратьУслугу()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .bold))
                        .accessibilityHidden(true)
                    Text(т("svc_go"))
                        .font(.system(size: 16, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(LinearGradient(colors: [Theme.зелёный, Theme.зелёный2], startPoint: .topLeading,
                                           endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                .shadow(color: Color(uiColor: Theme.hex(0x0F5132, 0.35)), radius: 8, y: 6)
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        }
    }
}

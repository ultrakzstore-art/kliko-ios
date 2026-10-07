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
 Своё фото — по кнопке «Добавить своё фото». Постер-обложка (#svc-poster-panel, svcPosterGenerateCover) — ниже:
 рисует ПостерУслугиСайта (Design/SiteServicePoster.swift), при публикации без своих фото он становится первым фото.
 Ответы мастера и обложка пишутся в черновик.
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
    /// _svcPosterOptIn: постер станет обложкой при публикации (выключается «Убрать обложку» или удалением плитки).
    var постер = true
    /// _svcPosterCoverUrl: урл загруженной обложки — по нему старая заменяется новой.
    var обложка: String = ""
    /// Из чего нарисована обложка (название, цена, город, продавец) — не изменилось, заново не грузим.
    var обложкаКлюч: String = ""
}

/// Черновик: ответы мастера услуги. Ключи читаются мягко — старый черновик без них не ломается.
extension ЗаготовкаУслуги: Codable {
    private enum Ключ: String, CodingKey {
        case направление, что, плюсы, цена, город, собрано, постер, обложка, обложкаКлюч
    }

    init(from decoder: Decoder) throws {
        self.init()
        let к = try decoder.container(keyedBy: Ключ.self)
        направление = (try? к.decodeIfPresent(String.self, forKey: .направление)) ?? ""
        что = (try? к.decodeIfPresent(String.self, forKey: .что)) ?? ""
        плюсы = (try? к.decodeIfPresent(String.self, forKey: .плюсы)) ?? ""
        цена = (try? к.decodeIfPresent(String.self, forKey: .цена)) ?? ""
        город = (try? к.decodeIfPresent(String.self, forKey: .город)) ?? ""
        собрано = (try? к.decodeIfPresent(Bool.self, forKey: .собрано)) ?? false
        постер = (try? к.decodeIfPresent(Bool.self, forKey: .постер)) ?? true
        обложка = (try? к.decodeIfPresent(String.self, forKey: .обложка)) ?? ""
        обложкаКлюч = (try? к.decodeIfPresent(String.self, forKey: .обложкаКлюч)) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var к = encoder.container(keyedBy: Ключ.self)
        try к.encode(направление, forKey: .направление)
        try к.encode(что, forKey: .что)
        try к.encode(плюсы, forKey: .плюсы)
        try к.encode(цена, forKey: .цена)
        try к.encode(город, forKey: .город)
        try к.encode(собрано, forKey: .собрано)
        try к.encode(постер, forKey: .постер)
        try к.encode(обложка, forKey: .обложка)
        try к.encode(обложкаКлюч, forKey: .обложкаКлюч)
    }

    /// Есть что сохранить в черновик: хоть один ответ мастера.
    var естьОтветы: Bool {
        !что.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !плюсы.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !цена.isEmpty
    }
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
                } else if ПокупкиApple.shared.можноКупить(.слоты) {
                    /* Слоты — окно App Store, только при загруженном товаре слотов (ДоступПокупкиApple). */
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

// MARK: - Постер-обложка услуги (svcPosterGenerateCover сайта)

extension ПодачаМодель {
    /// _svcPosterOpts сайта: название, цена, город формы и имя продавца (CAB_USER.name); тема — по названию.
    var данныеПостера: ДанныеОтправкиСайта {
        let ф = форма
        let у = ДанныеУслугиПостера(продавец: страница.состояние?.имя ?? "", рейтинг: 0, проверен: false,
                                    город: ф.город.trimmingCharacters(in: .whitespacesAndNewlines), раздел: "")
        return ДанныеОтправкиСайта(id: "", название: ф.название.trimmingCharacters(in: .whitespacesAndNewlines),
                                   цена: Double(ценаЧислом), состояние: nil, фото: nil, услуга: у)
    }

    /// Из чего рисуется постер — сменилось, значит старую обложку надо заменить.
    var ключПостера: String {
        let д = данныеПостера
        let части: [String] = [д.название, String(ценаЧислом), д.услуга?.город ?? "", д.услуга?.продавец ?? ""]
        return части.joined(separator: "|")
    }

    /// Портрет 4:5 (1080 × 1350), как aspect «portrait» сайта; лица нет — первая буква продавца.
    func нарисоватьПостер() -> UIImage {
        let д = данныеПостера
        return ПостерУслугиСайта.нарисовать(д, услуга: д.услуга ?? ДанныеУслугиПостера(), фото: nil, qr: nil,
                                           высота: 1350)
    }

    func этоОбложка(_ плитка: ПлиткаФото) -> Bool {
        if let id = обложкаПлитка, плитка.id == id { return true }
        return !услуга.обложка.isEmpty && плитка.url == услуга.обложка
    }

    /// Фото, которые человек добавил сам (без постера).
    var своиФото: [ПлиткаФото] { плитки.filter { !этоОбложка($0) } }

    var естьОбложка: Bool { плитки.contains { этоОбложка($0) } }

    /// Перед окном проверки: услуга, постер не выключен, своих фото нет, название есть.
    var нужнаОбложкаУслуги: Bool {
        режим == .услуга && !правка && услуга.постер && своиФото.isEmpty
            && !форма.название.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Урл и плитку обложки больше не помним; `выключить` — и при публикации не рисовать.
    func забытьОбложку(выключить: Bool) {
        обложкаПлитка = nil
        var у = услуга
        у.обложка = ""
        у.обложкаКлюч = ""
        if выключить { у.постер = false }
        услуга = у
    }

    /// «Убрать обложку»: плитка постера уходит, при публикации он не рисуется.
    func убратьОбложку() {
        плитки.removeAll { этоОбложка($0) }
        забытьОбложку(выключить: true)
    }

    /**
     svcPosterGenerateCover: рисуем постер, старую обложку (по урлу) убираем, новую ставим первым фото и грузим
     тем же upload_photo. Сам (перед публикацией) — только без своих фото; «Сделать обложкой» — всегда первым.
     */
    @discardableResult
    func сделатьОбложкуУслуги(вручную: Bool = false) async -> Bool {
        guard режим == .услуга, !правка else { return false }
        guard !форма.название.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if вручную { показать(МастерПодачиText.т("svc_poster_need")) }
            return false
        }
        guard вручную || (услуга.постер && своиФото.isEmpty) else { return false }
        if плитки.contains(where: { этоОбложка($0) && $0.грузится }) { return false }
        let ключ = ключПостера
        if let старая = плитки.first(where: { этоОбложка($0) }), старая.готова, услуга.обложкаКлюч == ключ,
           плитки.first?.id == старая.id {
            return true
        }
        плитки.removeAll { этоОбложка($0) }
        guard местоФото > 0 else {
            забытьОбложку(выключить: false)
            показать(String(format: т("photo_cap_full"), лимитФото))
            return false
        }
        guard let png = нарисоватьПостер().pngData() else { return false }
        let id = UUID()
        обложкаПлитка = id
        var у = услуга
        у.постер = true
        у.обложка = ""
        у.обложкаКлюч = ключ
        услуга = у
        плитки.insert(ПлиткаФото(id: id, url: "", превью: nil, картинка: nil, миниатюра: nil, грузится: true,
                                 ошибка: nil), at: 0)
        let готово: ГотовоеФото? = await Task.detached(priority: .userInitiated) { () -> ГотовоеФото? in
            ОбработкаФото.подготовить(png)
        }.value
        guard let место = плитки.firstIndex(where: { $0.id == id }) else { return false }
        guard let готово else {
            плитки.remove(at: место)
            забытьОбложку(выключить: false)
            return false
        }
        плитки[место].картинка = готово.картинка
        плитки[место].миниатюра = готово.миниатюра
        плитки[место].превью = UIImage(data: готово.миниатюра) ?? UIImage(data: готово.картинка)
        await загрузить(id)
        guard let итог = плитки.first(where: { $0.id == id }), итог.готова else { return false }
        услуга.обложка = итог.url
        return true
    }
}

/// #svc-poster-panel: превью постера, «Сделать обложкой» / «Обновить», «Убрать обложку» и переключатель.
@MainActor
struct ПостерУслугиПодачиВид: View {
    @ObservedObject var модель: ПодачаМодель
    @State private var превью: UIImage? = nil
    @State private var делаем = false

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { МастерПодачиText.т(ключ) }

    var body: some View {
        КарточкаПодачи(т("svc_poster_title"), подпись: т("svc_poster_sub"), значок: "photo.artframe") {
            HStack(alignment: .top, spacing: 14) {
                картинка
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: включено) {
                        Text(т("svc_poster_opt"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(КраскаПодачи.текст)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tint(Theme.зелёный)
                    кнопкаСделать
                    if модель.естьОбложка {
                        Button {
                            ОткликСайта.выбор()
                            модель.убратьОбложку()
                        } label: {
                            Label(т("svc_poster_remove"), systemImage: "trash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.ценаСкидка)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(т("svc_poster_note"))
                .font(.system(size: 12))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: модель.ключПостера) {
            /* svcPosterRenderSoon: перерисовка через 350 мс после правки полей. */
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            превью = модель.нарисоватьПостер()
        }
    }

    private var картинка: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .fill(КраскаПодачи.поле)
            if let превью {
                Image(uiImage: превью)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            } else {
                SiteSpinner()
            }
        }
        .frame(width: 120, height: 150)
        .accessibilityHidden(true)
    }

    private var включено: Binding<Bool> {
        let м = модель
        return Binding(get: { м.услуга.постер }, set: { новое in
            if новое {
                м.услуга.постер = true
            } else {
                м.убратьОбложку()
            }
        })
    }

    private var кнопкаСделать: some View {
        Button {
            guard !делаем else { return }
            делаем = true
            ОткликСайта.выбор()
            let м = модель
            Task { @MainActor in
                let вышло = await м.сделатьОбложкуУслуги(вручную: true)
                делаем = false
                if вышло { м.показать(МастерПодачиText.т("svc_poster_added")) }
            }
        } label: {
            HStack(spacing: 6) {
                if делаем {
                    SiteSpinner()
                } else {
                    Image(systemName: модель.естьОбложка ? "arrow.triangle.2.circlepath" : "photo.badge.plus")
                        .font(.system(size: 14, weight: .bold))
                }
                Text(т(модель.естьОбложка ? "svc_poster_redo" : "svc_poster_make"))
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(КраскаПодачи.хорошоТекст)
            .padding(.horizontal, 12)
            .frame(minHeight: 38)
            .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(делаем)
    }
}

import SwiftUI
import MapKit

/**
 «РЕГИОН И АДРЕС» И «РАССРОЧКА И КРЕДИТ» — ЭТАП 46 (владелец 26.09.2026: «всё одно и то же, просто код разный»).

 Регион и адрес (cabPrefGeo, §6.2.7): регион и район — ключи из GEO_KZ (js/cab-refs.js, тот же файл, что у мастера
 подачи), город — текстом, улица, «Это и адрес получения» и блок «Куда отправляю» (delWhereHTML). «Сохранить» шлёт два
 запроса разом, как сайт: save_pref_geo и save_pref_ship; успех решает первый, ошибку второго сайт не показывает.
 Точку на карте сайт ставит своим окном (mapPickOpen) — здесь своим листом карты (ТочкаНаКартеНастроек): нажали на
 карту — точка, «Сохранить» кладёт её в форму, «Убрать точку» — стирает; lat/lon уходят с «Сохранить» формы.

 Рассрочка и кредит (cabPrefPay, §6.2.11): переключатели, «С банком / Без банка · нотариус», наценка и ставка в пределах
 PAY_CFG, банки из PAY_CFG.banks в их порядке, ссылка на оплату на каждый отмеченный банк с проверкой _cabPayLinkOk
 (только https и домен банка из PAY_CFG.domains или его поддомен). В links уходят только непустые.
 */

// MARK: - Регион и адрес

struct ФормаРегиона: View {
    let профиль: ПрофильКабинета
    let кнопка: String
    let готово: (ПолеПрименения?) -> Void
    @State private var регионы: [РегионКЗ] = []
    @State private var грузится = true
    @State private var регион: String
    @State private var район: String
    @State private var город: String
    @State private var адрес: String
    @State private var получение: Bool
    @State private var отправка: String
    @State private var куда: Set<String>
    @State private var широта: Double?
    @State private var долгота: Double?
    @State private var карта = false
    /// Квартира, подъезд, этаж, домофон адреса получения — их подставляет лист «Куда доставить».
    @State private var квартира: String
    @State private var подъезд: String
    @State private var этаж: String
    @State private var домофон: String
    /// «Встречу у подъезда» и комментарий курьеру из листа — форма их не показывает, но и не теряет.
    private let прочееДвери: ДверьСделки
    @State private var ошибка: String? = nil
    @State private var идёт = false

    init(профиль: ПрофильКабинета, кнопка: String, готово: @escaping (ПолеПрименения?) -> Void) {
        self.профиль = профиль
        self.кнопка = кнопка
        self.готово = готово
        _регион = State(initialValue: профиль.регион)
        _район = State(initialValue: профиль.район)
        _город = State(initialValue: профиль.город)
        _адрес = State(initialValue: профиль.адрес)
        _получение = State(initialValue: профиль.адресПолучения)
        _отправка = State(initialValue: профиль.отправка)
        _куда = State(initialValue: Set(профиль.регионыОтправки))
        _широта = State(initialValue: профиль.широта)
        _долгота = State(initialValue: профиль.долгота)
        let дверь = профиль.дверьАдреса ?? ДверьПрофиляТелефона.загрузить() ?? ДверьСделки()
        прочееДвери = дверь
        _квартира = State(initialValue: дверь.квартира)
        _подъезд = State(initialValue: дверь.подъезд)
        _этаж = State(initialValue: дверь.этаж)
        _домофон = State(initialValue: дверь.домофон)
    }

    /// Дверь для сохранения: поля формы плюс «у подъезда» и комментарий, как были.
    private var дверьФормы: ДверьСделки {
        var д = прочееДвери
        д.квартира = String(квартира.trimmingCharacters(in: .whitespaces).prefix(16))
        д.подъезд = String(подъезд.trimmingCharacters(in: .whitespaces).prefix(8))
        д.этаж = String(этаж.trimmingCharacters(in: .whitespaces).prefix(8))
        д.домофон = String(домофон.trimmingCharacters(in: .whitespaces).prefix(24))
        return д
    }

    /// Квартира, подъезд, этаж, домофон — двумя строками по два поля.
    private var поляДвери: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ТочкаText.т("prof_door_l"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
            HStack(spacing: 12) {
                TextField(ТочкаText.т("flat"), text: $квартира)
                TextField(ТочкаText.т("porch"), text: $подъезд)
                    .keyboardType(.numberPad)
            }
            HStack(spacing: 12) {
                TextField(ТочкаText.т("floor"), text: $этаж)
                    .keyboardType(.numberPad)
                TextField(ТочкаText.т("code"), text: $домофон)
            }
        }
    }

    private var районы: [РайонКЗ] {
        регионы.first(where: { $0.id == регион })?.районы ?? []
    }

    /// Точка на карте отмечена: оба числа есть и не (0; 0) — _pgSt сайта.
    private var точкаЕсть: Bool { точка != nil }

    private var точка: CLLocationCoordinate2D? {
        guard let ш = широта, let д = долгота, ш != 0 || д != 0 else { return nil }
        return CLLocationCoordinate2D(latitude: ш, longitude: д)
    }

    var body: some View {
        Form {
            РазделШагаМастера(подсказка: тН("cabset_geo_hint"))
            Section {
                if грузится {
                    HStack(spacing: 10) {
                        SiteSpinner()
                        Text(тН("loading")).foregroundStyle(Theme.текстВторой)
                    }
                }
                Picker(тН("pg_region_l"), selection: регионВыбор) {
                    Text(тН("form_region_ph")).tag("")
                    ForEach(регионы) { р in
                        Text(р.имя).tag(р.id)
                    }
                }
                Picker(тН("pg_district_l"), selection: $район) {
                    Text(тН("pg_district_none")).tag("")
                    ForEach(районы) { д in
                        Text(д.имя).tag(д.id)
                    }
                }
                .disabled(районы.isEmpty)
                VStack(alignment: .leading, spacing: 4) {
                    Text(тН("pg_city_l"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                    TextField(тН("pg_city_ph"), text: $город)
                        .textContentType(.addressCity)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(тН("pg_addr_l"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                    TextField(тН("pg_addr_ph"), text: $адрес)
                        .textContentType(.streetAddressLine1)
                }
                поляДвери
                Button {
                    карта = true
                } label: {
                    HStack {
                        Text(тН("pg_map_l")).foregroundStyle(Theme.текст)
                        Spacer(minLength: 8)
                        Text(тН(точкаЕсть ? "pg_map_on" : "pg_map_off"))
                            .foregroundStyle(точкаЕсть ? Theme.акцент : Theme.текстВторой)
                        Image(systemName: "chevron.right")
                            .flipsForRightToLeftLayoutDirection(true)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.текстВторой.opacity(0.5))
                            .accessibilityHidden(true)
                    }
                }
            } header: {
                ПодсказкаФормыНастройки(тН("cabset_geo_hint"))
            } footer: {
                Text(тН("pg_map_note"))
            }
            Section {
                Toggle(isOn: $получение) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(тН("pg_recv")).font(.system(size: 16, weight: .semibold))
                        Text(тН("pg_recv_s")).font(.system(size: 13)).foregroundStyle(Theme.текстВторой)
                    }
                }
                .tint(Theme.зелёныйЯркий)
            }
            разделОтправки
            if let ошибка {
                Section { ОшибкаНастройки(текст: ошибка) }
            }
            КнопкаНастройки(подпись: кнопка, идёт: идёт) { сохранить() }
        }
        .кнопкаШагаМастера(подпись: кнопка, идёт: идёт) { сохранить() }
        .task { await загрузить() }
        .sheet(isPresented: $карта) {
            ТочкаНаКартеНастроек(начало: точка) { новая in
                широта = новая?.latitude
                долгота = новая?.longitude
            }
        }
    }

    /// geoFillDistricts: сменился регион — район сбрасывается.
    private var регионВыбор: Binding<String> {
        Binding(get: { регион }, set: { новый in
            guard новый != регион else { return }
            регион = новый
            район = ""
        })
    }

    /// delWhereHTML: три варианта; при «Своя область и выбранные» — галочки областей, своя отмечена и заблокирована.
    private var разделОтправки: some View {
        Section {
            вариантОтправки("all", заголовок: тН("del_where_all"), подпись: тН("del_where_all_s"), значок: "globe")
            вариантОтправки("regions", заголовок: тН("del_where_regions"), подпись: тН("del_where_regions_s"),
                            значок: "map")
            if отправка == "regions" {
                ForEach(регионы) { р in
                    строкаОбласти(р)
                }
            }
            вариантОтправки("city", заголовок: тН("del_where_city"), подпись: тН("del_where_city_s"),
                            значок: "mappin.and.ellipse")
        } header: {
            Text(тН("del_where_t"))
        } footer: {
            Text(тН("del_where_note"))
        }
    }

    private func вариантОтправки(_ ключ: String, заголовок: String, подпись: String, значок: String) -> some View {
        Button {
            отправка = ключ
        } label: {
            HStack(spacing: 12) {
                Image(systemName: значок)
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(заголовок)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                    Text(подпись)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 8)
                Image(systemName: отправка == ключ ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(отправка == ключ ? Theme.зелёныйЯркий : Theme.текстВторой)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityAddTraits(отправка == ключ ? [.isSelected] : [])
    }

    private func строкаОбласти(_ р: РегионКЗ) -> some View {
        let своя = р.id == регион
        let отмечена = своя || куда.contains(р.id)
        return Button {
            guard !своя else { return }
            if куда.contains(р.id) {
                куда.remove(р.id)
            } else {
                куда.insert(р.id)
            }
        } label: {
            HStack {
                Text(р.имя).foregroundStyle(Theme.текст)
                if своя {
                    Text(тН("del_where_own"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.текстВторой)
                }
                Spacer(minLength: 8)
                Image(systemName: отмечена ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(отмечена ? Theme.зелёныйЯркий : Theme.текстВторой)
                    .opacity(своя ? 0.5 : 1)
                    .accessibilityHidden(true)
            }
            .padding(.leading, 36)
        }
        .disabled(своя)
        .accessibilityAddTraits(отмечена ? [.isSelected] : [])
    }

    private func загрузить() async {
        guard регионы.isEmpty else { return }
        var страница = СтраницаПодачи()
        страница.путьРазделов = профиль.путьРазделов
        страница.путьСправочников = профиль.путьСправочников
        do {
            let справочники = try await ЗагрузкаСправочников.загрузить(страница)
            регионы = справочники.регионы
        } catch {
            ошибка = НастройкиAPI.сбой(error)
        }
        грузится = false
    }

    /**
     cabPrefGeoSave: оба запроса разом. geo: {region, district, city (trim), address (trim), lat, lon (число или null),
     recv}; ship: {ship_scope, ship_regions} — области только при «regions» и без своей (заблокированная галочка у сайта
     не уходит). Успех — по первому: плашка «Регион и адрес сохранены» и вопрос «Применить адрес к объявлениям?».
     */
    private func сохранить() {
        guard !идёт else { return }
        ошибка = nil
        идёт = true
        let чистыйГород = город.trimmingCharacters(in: .whitespacesAndNewlines)
        let чистыйАдрес = адрес.trimmingCharacters(in: .whitespacesAndNewlines)
        var поляГео: [String: Any] = ["region": регион, "district": район, "city": чистыйГород, "address": чистыйАдрес,
                                      "recv": получение]
        let сохранённаяТочка = точка
        if let т = сохранённаяТочка {
            поляГео["lat"] = NSNumber(value: т.latitude)
            поляГео["lon"] = NSNumber(value: т.longitude)
        } else {
            поляГео["lat"] = NSNull()
            поляГео["lon"] = NSNull()
        }
        let сохранённаяДверь = дверьФормы
        поляГео["door"] = сохранённаяДверь.значениеПрофиля
        let гео = поляГео
        /* Справочник регионов не загрузился («Нет соединения») — галочек на экране нет, и выбор фильтровать не по чему:
           уходят прежние области профиля, а не пустой список (иначе выбранные области доставки стёрлись бы). */
        let области: [String] = отправка != "regions" ? []
            : регионы.isEmpty ? профиль.регионыОтправки.filter { куда.contains($0) && $0 != регион }
            : регионы.map { $0.id }.filter { куда.contains($0) && $0 != регион }
        let доставка: [String: Any] = ["ship_scope": отправка, "ship_regions": области]
        let сохранённыйРегион = регион
        let сохранённыйРайон = район
        let сохранённаяОтправка = отправка
        let сохранённоеПолучение = получение
        Task { @MainActor in
            defer { идёт = false }
            async let ответДоставки: [String: Any]? = try? НастройкиAPI.отправить("cabinet.php?action=save_pref_ship",
                                                                                    доставка)
            do {
                let j = try await НастройкиAPI.отправить("cabinet.php?action=save_pref_geo", гео)
                let d = await ответДоставки
                if МоиОбъявленияAPI.да(j["ok"]) {
                    let доставкаПринята = d.map { МоиОбъявленияAPI.да($0["ok"]) } ?? false
                    ДверьПрофиляТелефона.запомнить(сохранённаяДверь)
                    НастройкиМодель.shared.изменить { п in
                        п.регион = сохранённыйРегион
                        п.район = сохранённыйРайон
                        п.город = чистыйГород
                        п.адрес = чистыйАдрес
                        п.адресПолучения = сохранённоеПолучение
                        п.широта = сохранённаяТочка?.latitude
                        п.долгота = сохранённаяТочка?.longitude
                        п.дверьАдреса = сохранённаяДверь.естьДетали || !сохранённаяДверь.комментарий.isEmpty
                            ? сохранённаяДверь : nil
                        if доставкаПринята {
                            п.отправка = сохранённаяОтправка
                            п.регионыОтправки = области
                        }
                    }
                    НастройкиМодель.shared.показать(тН("cabset_geo_saved"))
                    готово(.гео)
                } else {
                    ошибка = НастройкиAPI.ошибка(j)
                }
            } catch {
                _ = await ответДоставки
                ошибка = НастройкиAPI.сбой(error)
            }
        }
    }
}

/// Лист «Точка на карте» (mapPickOpen сайта): нажатие на карту ставит точку, «Сохранить» отдаёт её форме,
/// «Убрать точку» — стирает. Сама запись — кнопкой формы «Регион и адрес».
struct ТочкаНаКартеНастроек: View {
    let начало: CLLocationCoordinate2D?
    let готово: (CLLocationCoordinate2D?) -> Void
    @Environment(\.dismiss) private var закрыть
    @State private var точка: CLLocationCoordinate2D?
    @State private var камера: MapCameraPosition

    init(начало: CLLocationCoordinate2D?, готово: @escaping (CLLocationCoordinate2D?) -> Void) {
        self.начало = начало
        self.готово = готово
        _точка = State(initialValue: начало)
        /* Нет точки — весь Казахстан. */
        let центр = начало ?? CLLocationCoordinate2D(latitude: 48.0, longitude: 67.0)
        let размах = начало == nil ? 18.0 : 0.02
        _камера = State(initialValue: .region(MKCoordinateRegion(center: центр,
                                                                 span: MKCoordinateSpan(latitudeDelta: размах,
                                                                                        longitudeDelta: размах))))
    }

    var body: some View {
        ЛистНастройки(заголовок: тН("pg_map_l")) {
            VStack(spacing: 12) {
                Text(тН("pg_map_note"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity, alignment: .leading)
                карта
                КнопкаСайта(подпись: тН("save"), идёт: false) {
                    готово(точка)
                    закрыть()
                }
                .disabled(точка == nil)
                .opacity(точка == nil ? 0.5 : 1)
                if начало != nil || точка != nil {
                    Button(тН("pg_map_clear")) {
                        готово(nil)
                        закрыть()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(КраскаОбъявлений.плохоТекст)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(16)
        }
    }

    private var карта: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return MapReader { прокси in
            Map(position: $камера, interactionModes: .all) {
                if let точка {
                    Marker("", coordinate: точка)
                        .tint(Theme.зелёный)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onTapGesture { место in
                guard let к = прокси.convert(место, from: .local) else { return }
                точка = к
            }
        }
        .frame(maxHeight: .infinity)
        .frame(minHeight: 260)
        .clipShape(форма)
        .overlay { форма.strokeBorder(Theme.линия, lineWidth: 1) }
        .accessibilityLabel(тН("pg_map_l"))
    }
}

// MARK: - Рассрочка и кредит

struct ФормаОплаты: View {
    let профиль: ПрофильКабинета
    let готово: () -> Void
    @State private var о: НастройкиОплаты
    @State private var ошибка: String? = nil
    @State private var идёт = false

    init(профиль: ПрофильКабинета, готово: @escaping () -> Void) {
        self.профиль = профиль
        self.готово = готово
        var начальная = профиль.оплата
        let с = профиль.справочникОплаты
        начальная.наценка = min(max(начальная.наценка, с.наценкаОт), с.наценкаДо)
        начальная.ставка = min(max(начальная.ставка, с.ставкаОт), с.ставкаДо)
        _о = State(initialValue: начальная)
    }

    private var справочник: СправочникОплаты { профиль.справочникОплаты }

    var body: some View {
        Form {
            Section {
                Text(тН("pp_hint"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
            }
            разделРассрочки
            разделКредита
            if let ошибка {
                Section { ОшибкаНастройки(текст: ошибка) }
            }
            КнопкаНастройки(подпись: тН("save"), идёт: идёт) { сохранить() }
        }
    }

    private var разделРассрочки: some View {
        Section {
            Toggle(тН("pay_installment"), isOn: $о.рассрочка)
                .tint(Theme.зелёныйЯркий)
                .font(.system(size: 16, weight: .bold))
            if о.рассрочка {
                Picker(тН("pay_installment"), selection: $о.режим) {
                    Text(тН("pay_with_bank")).tag("bank")
                    Text(тН("pay_notary")).tag("notary")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                ползунок(тН("pay_markup"), значение: $о.наценка, от: справочник.наценкаОт, до: справочник.наценкаДо)
                if о.режим == "bank" {
                    банки(выбранные: $о.банкиРассрочки)
                    ссылки
                    Text(тН("pp_inst_note"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
        }
    }

    private var разделКредита: some View {
        Section {
            Toggle(тН("pay_credit"), isOn: $о.кредит)
                .tint(Theme.зелёныйЯркий)
                .font(.system(size: 16, weight: .bold))
            if о.кредит {
                ползунок(тН("pay_annual_rate"), значение: $о.ставка, от: справочник.ставкаОт, до: справочник.ставкаДо)
                банки(выбранные: $о.банкиКредита)
                Text(тН("pp_cred_note"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            }
        }
    }

    /// Ползунок сайта (type=range, шаг 1) и значение «N%» справа.
    private func ползунок(_ подпись: String, значение: Binding<Int>, от: Int, до: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(подпись).font(.system(size: 15))
                Spacer(minLength: 8)
                Text(String(значение.wrappedValue) + "%")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
            }
            Slider(value: Binding<Double>(get: { Double(значение.wrappedValue) },
                                          set: { значение.wrappedValue = Int($0.rounded()) }),
                   in: Double(от)...Double(max(до, от + 1)), step: 1)
                .tint(Theme.зелёныйЯркий)
                .accessibilityLabel(подпись)
                .accessibilityValue(String(значение.wrappedValue) + "%")
        }
    }

    /// Кнопки банков (.pay-bank): нажатие добавляет или убирает банк, порядок — как нажимали (push/splice сайта).
    private func банки(выбранные: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(тН("pp_banks"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
            ПереносСтрок(промежуток: 8, междуСтрок: 8) {
                ForEach(справочник.банки) { банк in
                    let выбран = выбранные.wrappedValue.contains(банк.ключ)
                    Button {
                        if let место = выбранные.wrappedValue.firstIndex(of: банк.ключ) {
                            выбранные.wrappedValue.remove(at: место)
                        } else {
                            выбранные.wrappedValue.append(банк.ключ)
                        }
                    } label: {
                        Text(банк.подпись)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(выбран ? Color.white : Theme.текст)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(выбран ? Theme.зелёный2 : Theme.поверхность2,
                                        in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(выбран ? [.isSelected] : [])
                }
            }
        }
    }

    /// _cabPayLinksHTML: поле ссылки на каждый отмеченный банк рассрочки; пусто — подсказка.
    @ViewBuilder
    private var ссылки: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(тН("pp_links"))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
            if о.банкиРассрочки.isEmpty {
                Text(тН("pp_empty"))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.текстВторой)
            } else {
                ForEach(о.банкиРассрочки, id: \.self) { банк in
                    полеСсылки(банк)
                }
            }
        }
    }

    private func полеСсылки(_ банк: String) -> some View {
        let домен = справочник.домены[банк]?.first ?? ""
        let ссылка = о.ссылки[банк] ?? ""
        let годна = НастройкиAPI.ссылкаГодна(банк, ссылка, домены: справочник.домены)
        let имя = справочник.банки.first(where: { $0.ключ == банк })?.подпись ?? банк
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(имя).font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 6)
                if годна == true {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.зелёныйЯркий)
                        .accessibilityHidden(true)
                }
            }
            TextField("https://" + домен + "/…", text: Binding(get: { о.ссылки[банк] ?? "" },
                                                              set: { о.ссылки[банк] = $0 }))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .padding(10)
                .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
                .accessibilityLabel(тН("pp_links") + ", " + имя)
            if годна == false {
                Text(тН("pp_link_bad").replacingOccurrences(of: "{d}", with: домен))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.скидкаТекст)
            }
        }
    }

    /// cabPrefPaySave: неверная ссылка — «Ссылка должна вести на сайт выбранного банка», запрос не уходит.
    private func сохранить() {
        guard !идёт else { return }
        ошибка = nil
        let домены = справочник.домены
        let плохие = о.банкиРассрочки.filter { НастройкиAPI.ссылкаГодна($0, о.ссылки[$0] ?? "", домены: домены) == false }
        guard плохие.isEmpty else {
            ошибка = тН("pp_err_link")
            return
        }
        var ссылкиТела: [String: String] = [:]
        for банк in о.банкиРассрочки {
            let t = (о.ссылки[банк] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { ссылкиТела[банк] = t }
        }
        let тело: [String: Any] = [
            "installment": о.рассрочка, "installment_mode": о.режим, "installment_commission": о.наценка,
            "installment_banks": о.банкиРассрочки, "credit": о.кредит, "credit_rate": о.ставка,
            "credit_banks": о.банкиКредита, "links": ссылкиТела
        ]
        var новая = о
        новая.ссылки = ссылкиТела
        let сохранённая = новая
        идёт = true
        Task { @MainActor in
            defer { идёт = false }
            do {
                let j = try await НастройкиAPI.отправить("cabinet.php?action=save_pref_pay", тело)
                if МоиОбъявленияAPI.да(j["ok"]) {
                    НастройкиМодель.shared.изменить { $0.оплата = сохранённая }
                    НастройкиМодель.shared.показать(тН("pp_saved"))
                    готово()
                } else if МоиОбъявленияAPI.строка(j["error"]) == "link" {
                    ошибка = тН("pp_err_link")
                } else {
                    ошибка = НастройкиAPI.ошибка(j)
                }
            } catch {
                ошибка = НастройкиAPI.сбой(error)
            }
        }
    }
}

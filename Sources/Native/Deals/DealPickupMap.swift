import SwiftUI
import MapKit
import CoreLocation

/**
 ТОЧКА ЗАБОРА / ДОСТАВКИ НА КАРТЕ — СВОЁ ОКНО ВМЕСТО СТРАНИЦЫ СДЕЛКИ (hovAddrOpen сайта, карта §4.9.2).

 У сайта окно .apk: «Откуда забрать» / «Куда доставить», подсказка «Поставьте точку на карте или нажмите
 «Определить»…», карта Leaflet (точка — нажатием или перетаскиванием маркера), адрес по точке — nominatim reverse,
 «Определить моё место», поле «Город, улица, дом» (≥ 5 символов, иначе «Напишите адрес: город, улица, дом»), флажок
 «Вынесу к подъезду» / «Встречу у подъезда», «Кв./офис» (16), «Подъезд» (8), «Этаж» (8), «Домофон» (24), комментарий
 курьеру (300), строка «Точка задана: 43.23810, 76.94560» / «Точка не задана — маршрут будет по адресу», «Сохранить».
 Сохранение — hovPickupSave: POST escrow.php?action=set_pickup {csrf, deal_id, addr, lat, lon, door}; door —
 {out:true, note?} или {flat, porch, floor, code, note?} (_apkDoorVal). Ответ ok → «Адрес сохранён» (claim_live —
 «Курьер уже вызван — правка до него не дойдёт…»), иначе message или hovErr(error). Сторону (from / to) сервер
 определяет сам.

 Здесь то же на MapKit: булавка в центре карты (двигаете карту — двигается точка), нажатие на карту ставит точку туда,
 поиск адреса (MKLocalSearch по Казахстану), адрес по точке — геокодер системы, «Определить моё место» — геопозиция
 телефона, «Готово» в панели — сохранить, как «Сохранить» сайта.

 Посылка с кодом (hovFromEdit / hovAddrEdit при _hovParcel сайта): то же окно без подъезда и этажа, сохранение —
 chat.php?action=parcel_from | parcel_addr {deal_id, addr, lat, lon} (ПередачаСделкиМодель.адресПосылки); не вышло —
 окно остаётся открытым с текстом ошибки, как у сайта.
 */
struct ТочкаНаКартеСделки: Identifiable, Equatable {
    /// "from" — откуда забрать (продавец), "to" — куда доставить.
    let сторона: String
    let адрес: String
    let точка: ТочкаСделки?
    let дверь: ДверьСделки?
    /// Адрес посылки с кодом: parcel_from / parcel_addr вместо set_pickup, без подъезда и этажа.
    var посылка: Bool = false

    var id: String { посылка ? "parcel-" + сторона : сторона }
    var откуда: Bool { сторона == "from" }

    /// hovFromEdit / hovAddrEdit посылки: адрес и точка посылки, нет своих — сделки.
    static func посылки(_ с: Сделка, откуда: Bool) -> ТочкаНаКартеСделки {
        let п = с.посылка
        if откуда {
            let адрес = (п?.адресОткуда ?? "").isEmpty ? с.адресОткуда : (п?.адресОткуда ?? "")
            return ТочкаНаКартеСделки(сторона: "from", адрес: адрес, точка: п?.точкаОткуда ?? с.точкаОткуда, дверь: nil,
                                      посылка: true)
        }
        let адрес = (п?.адресКуда ?? "").isEmpty ? с.адресКуда : (п?.адресКуда ?? "")
        return ТочкаНаКартеСделки(сторона: "to", адрес: адрес, точка: п?.точкаКуда ?? с.точкаКуда, дверь: nil, посылка: true)
    }

    static func откуда(_ с: Сделка) -> ТочкаНаКартеСделки {
        ТочкаНаКартеСделки(сторона: "from", адрес: с.адресОткуда, точка: с.точкаОткуда, дверь: с.дверьОткуда)
    }

    static func куда(_ с: Сделка) -> ТочкаНаКартеСделки {
        ТочкаНаКартеСделки(сторона: "to", адрес: с.адресКуда, точка: с.точкаКуда, дверь: с.дверьКуда)
    }
}

/// Адрес, выбранный в окне карты без сделки (оформление новой сделки): адрес, точка, дверь в виде _apkDoorVal.
struct АдресИзКарты {
    let адрес: String
    let точка: CLLocationCoordinate2D?
    let дверь: [String: Any]
    let уПодъезда: Bool
}

struct ЛистТочкиСделки: View {
    let цель: ТочкаНаКартеСделки
    /// Сделка, куда сохранить (set_pickup); nil — окно только выбирает адрес и отдаёт его в выбрано.
    let модель: КарточкаСделкиМодель?
    let выбрано: ((АдресИзКарты) -> Void)?

    @Environment(\.dismiss) private var закрыть
    @StateObject private var место = МестоТелефона()
    @State private var камера: MapCameraPosition
    @State private var координата: CLLocationCoordinate2D?
    @State private var адрес: String
    @State private var уПодъезда: Bool
    @State private var квартира: String
    @State private var подъезд: String
    @State private var этаж: String
    @State private var домофон: String
    @State private var комментарий: String
    @State private var ищемАдрес = false
    @State private var найдено: [MKMapItem] = []
    @State private var ищем = false
    @State private var сохраняем = false
    @State private var ошибка: String? = nil
    /// Человек сам двигал карту — только тогда центр карты становится точкой.
    @State private var двигали = false
    @State private var геокодЗадача: Task<Void, Never>? = nil

    /// Центр Казахстана и масштаб страны — [48.02, 66.92], zoom 5 у сайта.
    private static let центрСтраны = CLLocationCoordinate2D(latitude: 48.02, longitude: 66.92)

    init(цель: ТочкаНаКартеСделки, модель: КарточкаСделкиМодель?, выбрано: ((АдресИзКарты) -> Void)? = nil) {
        self.цель = цель
        self.модель = модель
        self.выбрано = выбрано
        let д = цель.дверь ?? ДверьСделки()
        _адрес = State(initialValue: цель.адрес)
        _уПодъезда = State(initialValue: д.уПодъезда)
        _квартира = State(initialValue: д.квартира)
        _подъезд = State(initialValue: д.подъезд)
        _этаж = State(initialValue: д.этаж)
        _домофон = State(initialValue: д.домофон)
        _комментарий = State(initialValue: д.комментарий)
        if let т = цель.точка {
            let к = CLLocationCoordinate2D(latitude: т.широта, longitude: т.долгота)
            _координата = State(initialValue: к)
            _камера = State(initialValue: .region(MKCoordinateRegion(center: к, latitudinalMeters: 600,
                                                                     longitudinalMeters: 600)))
        } else {
            _координата = State(initialValue: nil)
            _камера = State(initialValue: .region(MKCoordinateRegion(center: Self.центрСтраны,
                                                                     span: MKCoordinateSpan(latitudeDelta: 18,
                                                                                            longitudeDelta: 30))))
        }
    }

    private func т(_ ключ: String) -> String { ТочкаText.т(ключ) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(т("sub"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                    карта
                    кнопкиКарты
                    полеАдреса
                    if !найдено.isEmpty { результаты }
                    заметкаТочки
                    if !цель.посылка { дверь }
                    if let ошибка {
                        Text(ошибка)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.скидкаТекст)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        сохранить()
                    } label: {
                        HStack(spacing: 8) {
                            if сохраняем { SiteSpinner.белый }
                            Text(сохраняем ? т("saving") : т("save"))
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Theme.зелёный, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    }
                    .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                    .disabled(сохраняем)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .modifier(ШапкаСделок(заголовок: т(цель.откуда ? "t_from" : "t_to")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("cancel")) { закрыть() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(т("done")) { сохранить() }
                        .disabled(сохраняем)
                }
            }
        }
        .tint(Theme.акцент)
        .onChange(of: место.координата?.latitude) { _, _ in
            guard let к = место.координата else { return }
            двигали = false
            поставить(к, сдвинуть: true, подобрать: true)
        }
        .onDisappear { геокодЗадача?.cancel() }
    }

    // MARK: - Карта

    private var карта: some View {
        /* .clc-map: высота 220, радиус 12, рамка 1px --line. */
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return MapReader { прокси in
            Map(position: $камера, interactionModes: .all) {
                if let координата, !двигали {
                    Marker(т("pin"), coordinate: координата)
                        .tint(Theme.зелёный)
                }
                UserAnnotation()
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { контекст in
                guard двигали else { return }
                поставить(контекст.region.center, сдвинуть: false, подобрать: true)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 6).onChanged { _ in
                    if !двигали { двигали = true }
                }
            )
            .onTapGesture { точка in
                guard let к = прокси.convert(точка, from: .local) else { return }
                двигали = false
                поставить(к, сдвинуть: true, подобрать: true)
            }
            .overlay {
                /* Двигаете карту — точка в её центре, булавкой поверх. */
                if двигали {
                    Image(systemName: "mappin")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Theme.зелёный)
                        .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
                        .offset(y: -17)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(height: 220)
        .clipShape(форма)
        .overlay {
            форма.strokeBorder(Theme.линия, lineWidth: 1)
        }
        .accessibilityLabel(т("map_a11y"))
    }

    private var кнопкиКарты: some View {
        HStack(spacing: 8) {
            Button {
                место.запросить()
            } label: {
                ярлыкКнопки(т("locate"), символ: "location")
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            .disabled(место.ищет)
            .opacity(место.ищет ? 0.55 : 1)
            let пустойАдрес = адрес.trimmingCharacters(in: .whitespacesAndNewlines).count < 3
            Button {
                найти()
            } label: {
                ярлыкКнопки(т("find"), символ: "magnifyingglass")
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            .disabled(ищем || пустойАдрес)
            .opacity(ищем || пустойАдрес ? 0.55 : 1)
        }
    }

    /// .clc-geo: --acc-tint, текст --acc-on, рамка 1.5 --line, радиус 12, 13/800, значок 16.
    private func ярлыкКнопки(_ текст: String, символ: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: символ)
                .font(.system(size: 15, weight: .semibold))
                .accessibilityHidden(true)
            Text(текст)
                .font(.system(size: 13, weight: .heavy))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(КраскаСделокКабинета.акцент)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }

    private var полеАдреса: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(т("addr_l"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.текст)
            TextField(ищемАдрес ? т("looking") : т("addr_ph"), text: $адрес, axis: .vertical)
                .lineLimit(1...3)
                .textContentType(.fullStreetAddress)
                .submitLabel(.search)
                .onSubmit { найти() }
                .onChange(of: адрес) { _, новое in
                    if новое.count > 300 { адрес = String(новое.prefix(300)) }
                }
                .modifier(ПолеТочки())
        }
    }

    private var результаты: some View {
        VStack(spacing: 0) {
            ForEach(Array(найдено.enumerated()), id: \.offset) { пара in
                Button {
                    выбрать(пара.element)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(Theme.акцент)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(пара.element.name ?? "")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.текст)
                                .lineLimit(1)
                            Text(ЛистТочкиСделки.строка(пара.element.placemark))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.текстВторой)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if пара.offset < найдено.count - 1 {
                    Divider().padding(.leading, 40)
                }
            }
        }
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private var заметкаТочки: some View {
        let текст: String
        if let к = координата {
            текст = т("has") + ": " + String(format: "%.5f, %.5f", к.latitude, к.longitude)
        } else {
            текст = т("none")
        }
        return Label(текст, systemImage: координата == nil ? "mappin.slash" : "mappin.and.ellipse")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(координата == nil ? Theme.текстВторой : Theme.зелёный2)
    }

    // MARK: - Подъезд

    private var дверь: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $уПодъезда) {
                Text(т(цель.откуда ? "out_s" : "out_b"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.текст)
            }
            .tint(Theme.зелёный)
            if !уПодъезда {
                HStack(spacing: 8) {
                    поле(т("flat"), $квартира, предел: 16, цифры: false)
                    поле(т("porch"), $подъезд, предел: 8, цифры: true)
                }
                HStack(spacing: 8) {
                    поле(т("floor"), $этаж, предел: 8, цифры: true)
                    поле(т("code"), $домофон, предел: 24, цифры: false)
                }
                Text(т("door_h"))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.текстВторой)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TextField(т("note_ph"), text: $комментарий, axis: .vertical)
                .lineLimit(2...4)
                .onChange(of: комментарий) { _, новое in
                    if новое.count > 300 { комментарий = String(новое.prefix(300)) }
                }
                .modifier(ПолеТочки())
                .accessibilityLabel(т("note_l"))
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private func поле(_ подпись: String, _ текст: Binding<String>, предел: Int, цифры: Bool) -> some View {
        TextField(подпись, text: Binding(get: { текст.wrappedValue }, set: { новое in
            var чистое = цифры ? новое.filter { $0.isNumber } : новое
            if чистое.count > предел { чистое = String(чистое.prefix(предел)) }
            текст.wrappedValue = чистое
        }))
        .keyboardType(цифры ? .numberPad : .default)
        .modifier(ПолеТочки())
        .accessibilityLabel(подпись)
    }

    // MARK: - Действия

    /// Поставить точку: запомнить, при нужде показать на карте и подобрать адрес (как _apkReverse — через 0,7 с).
    private func поставить(_ к: CLLocationCoordinate2D, сдвинуть: Bool, подобрать: Bool) {
        guard CLLocationCoordinate2DIsValid(к) else { return }
        координата = к
        найдено = []
        if сдвинуть {
            withAnimation(ДвижениеСайта.камера) {
                камера = .region(MKCoordinateRegion(center: к, latitudinalMeters: 500, longitudinalMeters: 500))
            }
        }
        guard подобрать else { return }
        геокодЗадача?.cancel()
        ищемАдрес = true
        геокодЗадача = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            let найденный = await ЛистТочкиСделки.адресПоТочке(к)
            guard !Task.isCancelled else { return }
            ищемАдрес = false
            if let найденный, !найденный.isEmpty { адрес = найденный }
        }
    }

    /// Поиск по тексту поля: MKLocalSearch в пределах Казахстана, до шести мест.
    private func найти() {
        let запрос = адрес.trimmingCharacters(in: .whitespacesAndNewlines)
        guard запрос.count >= 3, !ищем else { return }
        ищем = true
        ошибка = nil
        Task { @MainActor in
            defer { ищем = false }
            let поиск = MKLocalSearch.Request()
            поиск.naturalLanguageQuery = запрос
            поиск.region = MKCoordinateRegion(center: Self.центрСтраны,
                                              span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 40))
            поиск.resultTypes = [.address, .pointOfInterest]
            let ответ = try? await MKLocalSearch(request: поиск).start()
            let места = Array((ответ?.mapItems ?? []).prefix(6))
            if места.isEmpty {
                ошибка = т("not_found")
            } else if места.count == 1, let одно = места.first {
                выбрать(одно)
            } else {
                найдено = места
            }
        }
    }

    private func выбрать(_ место: MKMapItem) {
        let к = место.placemark.coordinate
        let строка = ЛистТочкиСделки.строка(место.placemark)
        найдено = []
        двигали = false
        поставить(к, сдвинуть: true, подобрать: false)
        if !строка.isEmpty { адрес = строка }
    }

    /// hovAddrSave + hovPickupSave сайта.
    private func сохранить() {
        guard !сохраняем else { return }
        let текст = адрес.trimmingCharacters(in: .whitespacesAndNewlines)
        guard текст.count >= 5 else {
            ошибка = т("short")
            return
        }
        ошибка = nil
        if let выбрано {
            /* Новая сделка: адрес уходит в окно оформления, сервер получит его вместе с create. */
            выбрано(АдресИзКарты(адрес: String(текст.prefix(300)), точка: координата, дверь: значениеДвери(),
                                 уПодъезда: уПодъезда))
            закрыть()
            return
        }
        guard let м = модель else { return }
        if цель.посылка {
            /* hovAddrSave при посылке: parcel_from / parcel_addr; ok — окно закрывается, иначе остаётся с ошибкой. */
            сохраняем = true
            let точка = координата.flatMap { ТочкаСделки($0.latitude, $0.longitude) }
            м.передача.адресПосылки(откуда: цель.откуда, адрес: String(текст.prefix(300)), точка: точка) { итог in
                сохраняем = false
                if let итог {
                    if !итог.isEmpty { ошибка = итог }
                } else {
                    закрыть()
                }
            }
            return
        }
        сохраняем = true
        var тело: [String: Any] = ["deal_id": м.id, "addr": String(текст.prefix(300))]
        if let к = координата {
            тело["lat"] = к.latitude
            тело["lon"] = к.longitude
        } else {
            тело["lat"] = NSNull()
            тело["lon"] = NSNull()
        }
        тело["door"] = значениеДвери()
        Task { @MainActor in
            defer { сохраняем = false }
            do {
                let j = try await СделкиAPI.отправить("escrow.php?action=set_pickup", тело: тело)
                if СделкиAPI.да(j["ok"]) {
                    закрыть()
                    м.показать(т(СделкиAPI.да(j["claim_live"]) ? "door_live" : "saved"))
                    await м.загрузить()
                    return
                }
                if МоиОбъявленияAPI.нетСессии(j) {
                    ошибка = т("login")
                    return
                }
                let сообщение = СделкиAPI.строка(j["message"]).trimmingCharacters(in: .whitespacesAndNewlines)
                ошибка = сообщение.isEmpty ? ТекстыОшибокСделки.текст(СделкиAPI.строка(j["error"])) : сообщение
            } catch {
                ошибка = СделкиText.т("err_no_conn")
            }
        }
    }

    /// _apkDoorVal: у подъезда — {out:true, note?}; иначе {flat, porch, floor, code, note?}.
    private func значениеДвери() -> [String: Any] {
        let заметка = String(комментарий.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        if уПодъезда {
            var д: [String: Any] = ["out": true]
            if !заметка.isEmpty { д["note"] = заметка }
            return д
        }
        var д: [String: Any] = [
            "flat": квартира.trimmingCharacters(in: .whitespaces),
            "porch": подъезд.trimmingCharacters(in: .whitespaces),
            "floor": этаж.trimmingCharacters(in: .whitespaces),
            "code": домофон.trimmingCharacters(in: .whitespaces)
        ]
        if !заметка.isEmpty { д["note"] = заметка }
        return д
    }

    // MARK: - Адрес по точке

    /// «Алматы, улица Абая, 10» — город, улица, дом; пусто — nil.
    static func адресПоТочке(_ к: CLLocationCoordinate2D) async -> String? {
        let геокодер = CLGeocoder()
        let место = CLLocation(latitude: к.latitude, longitude: к.longitude)
        let язык = Locale(identifier: SellerText.язык == "kk" ? "kk_KZ" : "ru_KZ")
        guard let метки = try? await геокодер.reverseGeocodeLocation(место, preferredLocale: язык),
              let метка = метки.first else { return nil }
        let строка = Self.строка(метка)
        return строка.isEmpty ? nil : строка
    }

    static func строка(_ метка: CLPlacemark) -> String {
        var части: [String] = []
        if let город = метка.locality, !город.isEmpty { части.append(город) }
        var улица = метка.thoroughfare ?? ""
        if let дом = метка.subThoroughfare, !дом.isEmpty {
            улица = улица.isEmpty ? дом : улица + ", " + дом
        }
        if !улица.isEmpty { части.append(улица) }
        if части.isEmpty, let имя = метка.name, !имя.isEmpty { части.append(имя) }
        return части.joined(separator: ", ")
    }
}

/// Поле окна точки: --mk-surf, рамка 1.5 --line, скругление --r-sm, как .apk-in сайта.
private struct ПолеТочки: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15))
            .foregroundStyle(Theme.текст)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous)
                    .strokeBorder(Theme.линия, lineWidth: 1.5)
            }
    }
}

/// «Определить моё место»: одна геопозиция телефона по нажатию (ulxGetPosition сайта).
@MainActor
final class МестоТелефона: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var координата: CLLocationCoordinate2D? = nil
    @Published private(set) var ищет = false
    private let менеджер = CLLocationManager()

    override init() {
        super.init()
        менеджер.delegate = self
        менеджер.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func запросить() {
        ищет = true
        switch менеджер.authorizationStatus {
        case .notDetermined:
            менеджер.requestWhenInUseAuthorization()
        case .denied, .restricted:
            ищет = false
        default:
            менеджер.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let статус = manager.authorizationStatus
        Task { @MainActor in
            guard self.ищет else { return }
            if статус == .authorizedWhenInUse || статус == .authorizedAlways {
                self.менеджер.requestLocation()
            } else if статус != .notDetermined {
                self.ищет = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let последняя = locations.last else { return }
        let к = последняя.coordinate
        Task { @MainActor in
            self.ищет = false
            self.координата = к
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.ищет = false }
    }
}

/// Тексты окна точки. Русские — сайта (apk_*, co_door_*, co_dm_out*, co_note_*, door_live).
enum ТочкаText {
    static func т(_ ключ: String) -> String {
        let язык = SellerText.язык
        let словарь = тексты[язык] ?? тексты["ru"]!
        return словарь[ключ] ?? тексты["ru"]![ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "t_from": "Откуда забрать", "t_to": "Куда доставить",
            "sub": "Поставьте точку на карте или нажмите «Определить» — курьер приедет к подъезду, а не к улице. Текст адреса всё равно нужен: его вписывают в заявку.",
            "locate": "Определить моё место", "find": "Найти на карте", "addr_l": "Адрес",
            "addr_ph": "Город, улица, дом", "looking": "Определяем адрес…",
            "has": "Точка задана", "none": "Точка не задана — маршрут будет по адресу",
            "out_s": "Вынесу к подъезду", "out_b": "Встречу у подъезда",
            "flat": "Кв./офис", "porch": "Подъезд", "floor": "Этаж", "code": "Домофон",
            "door_h": "Квартира, подъезд, этаж и домофон уйдут курьеру отдельными строками.",
            "note_ph": "Комментарий курьеру — например, позвоните за 10 минут", "note_l": "Комментарий курьеру",
            "save": "Сохранить", "saving": "Сохранение…", "cancel": "Отмена", "done": "Готово",
            "short": "Напишите адрес: город, улица, дом", "saved": "Адрес сохранён",
            "door_live": "Курьер уже вызван — правка до него не дойдёт. Квартиру и подъезд скажите ему по телефону.",
            "not_found": "Ничего не нашлось — уточните адрес или поставьте точку на карте",
            "login": "Войдите в кабинет", "pin": "Точка", "map_a11y": "Карта: нажмите, чтобы поставить точку"
        ],
        "kk": [
            "t_from": "Қайдан алып кету", "t_to": "Қайда жеткізу",
            "sub": "Картада нүкте қойыңыз немесе «Анықтау» басыңыз — курьер көшеге емес, кіреберіске келеді. Мекенжай мәтіні бәрібір керек: ол өтінімге жазылады.",
            "locate": "Орнымды анықтау", "find": "Картадан табу", "addr_l": "Мекенжай",
            "addr_ph": "Қала, көше, үй", "looking": "Мекенжай анықталуда…",
            "has": "Нүкте қойылды", "none": "Нүкте қойылмаған — бағыт мекенжай бойынша болады",
            "out_s": "Кіреберіске шығарамын", "out_b": "Кіреберісте қарсы аламын",
            "flat": "Пәтер/кеңсе", "porch": "Кіреберіс", "floor": "Қабат", "code": "Домофон",
            "door_h": "Пәтер, кіреберіс, қабат және домофон курьерге бөлек жолмен жіберіледі.",
            "note_ph": "Курьерге түсініктеме — мысалы, 10 минут бұрын қоңырау шалыңыз", "note_l": "Курьерге түсініктеме",
            "save": "Сақтау", "saving": "Сақталуда…", "cancel": "Бас тарту", "done": "Дайын",
            "short": "Мекенжайды жазыңыз: қала, көше, үй", "saved": "Мекенжай сақталды",
            "door_live": "Курьер шақырылып қойған — түзету оған жетпейді. Пәтер мен кіреберісті телефонмен айтыңыз.",
            "not_found": "Ештеңе табылмады — мекенжайды нақтылаңыз немесе картада нүкте қойыңыз",
            "login": "Кабинетке кіріңіз", "pin": "Нүкте", "map_a11y": "Карта: нүкте қою үшін басыңыз"
        ],
        "en": [
            "t_from": "Pickup point", "t_to": "Delivery point",
            "sub": "Drop a pin on the map or tap “Locate” — the courier will come to the entrance, not just the street. The address text is still needed: it goes into the order.",
            "locate": "Use my location", "find": "Find on map", "addr_l": "Address",
            "addr_ph": "City, street, building", "looking": "Looking up the address…",
            "has": "Pin set", "none": "No pin — the route will follow the address",
            "out_s": "I'll bring it out to the entrance", "out_b": "I'll meet at the entrance",
            "flat": "Apt/office", "porch": "Entrance", "floor": "Floor", "code": "Intercom",
            "door_h": "Apartment, entrance, floor and intercom go to the courier as separate lines.",
            "note_ph": "Note for the courier — e.g. call 10 minutes ahead", "note_l": "Note for the courier",
            "save": "Save", "saving": "Saving…", "cancel": "Cancel", "done": "Done",
            "short": "Enter the address: city, street, building", "saved": "Address saved",
            "door_live": "The courier is already on the way — this edit won't reach them. Tell them the apartment and entrance by phone.",
            "not_found": "Nothing found — refine the address or drop a pin on the map",
            "login": "Sign in to your account", "pin": "Pin", "map_a11y": "Map: tap to drop a pin"
        ],
        "ar": [
            "t_from": "مكان الاستلام", "t_to": "مكان التوصيل",
            "sub": "ضع نقطة على الخريطة أو اضغط «تحديد» — سيأتي المندوب إلى المدخل لا إلى الشارع فقط. نص العنوان مطلوب أيضًا لأنه يُكتب في الطلب.",
            "locate": "تحديد موقعي", "find": "البحث على الخريطة", "addr_l": "العنوان",
            "addr_ph": "المدينة، الشارع، المبنى", "looking": "جارٍ تحديد العنوان…",
            "has": "تم تحديد النقطة", "none": "لم تُحدَّد نقطة — سيكون المسار حسب العنوان",
            "out_s": "سأُخرجه إلى المدخل", "out_b": "سألتقي عند المدخل",
            "flat": "شقة/مكتب", "porch": "المدخل", "floor": "الطابق", "code": "الإنتركم",
            "door_h": "ستُرسل الشقة والمدخل والطابق والإنتركم إلى المندوب في أسطر منفصلة.",
            "note_ph": "ملاحظة للمندوب — مثلًا اتصل قبل 10 دقائق", "note_l": "ملاحظة للمندوب",
            "save": "حفظ", "saving": "جارٍ الحفظ…", "cancel": "إلغاء", "done": "تم",
            "short": "اكتب العنوان: المدينة، الشارع، المبنى", "saved": "تم حفظ العنوان",
            "door_live": "المندوب في الطريق بالفعل — لن يصله هذا التعديل. أخبره بالشقة والمدخل هاتفيًا.",
            "not_found": "لم يُعثر على شيء — دقّق العنوان أو ضع نقطة على الخريطة",
            "login": "سجّل الدخول إلى حسابك", "pin": "نقطة", "map_a11y": "الخريطة: اضغط لوضع نقطة"
        ]
    ]
}

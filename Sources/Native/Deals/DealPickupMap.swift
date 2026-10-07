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
 телефона (круглая кнопка на карте), «Сохранить» — закреплена внизу листа.

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

/**
 Вид окна (владелец, 06.10.2026: «Сохранить чтобы виднее было, причесать дизайн, кнопки объединить»): шапка как у листа
 фильтров и мастера — «×» слева, заголовок посередине, без системной панели; сверху поле поиска адреса с лупой, под ним
 карта с круглой кнопкой «моё место» в правом нижнем углу (как в Картах); под картой одна строка — подсказка или
 «Точка на карте выбрана»; карточка адреса — поле «Адрес», «Встречу у подъезда» (включено — квартира не нужна, поля
 скрыты; выключено — курьер идёт к двери, поля квартиры видны), комментарий. «Сохранить» — одна, закреплена внизу листа
 и не нажимается, пока адрес не задан.

 «Куда доставить» берёт адрес и детали двери из профиля (настройки «Регион и адрес»): если они есть — свёрнутая сводка
 «кв. 12 · подъезд 3 · этаж 5 · домофон 12К» с кнопками «Изменить» и «Другой адрес»; «Другой адрес» — разовый, с
 галочкой «Сохранить в профиле» (выключена). Детали двери хранятся на телефоне и уходят серверу в save_pref_geo (door).
 */
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
    @State private var геокодЗадача: Task<Void, Never>? = nil
    /// Поиск адреса: текст, найденные места, идёт ли запрос, «Ничего не найдено» / «Нет связи».
    @State private var запрос = ""
    @State private var найдено: [MKMapItem] = []
    @State private var ищем = false
    @State private var итогПоиска: String? = nil
    @State private var поискЗадача: Task<Void, Never>? = nil
    /// Видимая часть карты — поиск сперва в ней (если это город, а не вся страна).
    @State private var видимаяОбласть: MKCoordinateRegion? = nil
    @State private var сохраняем = false
    /// Адрес уже отдан вызывающему — второе нажатие «Сохранить» ничего не делает.
    @State private var отдано = false
    @State private var ошибка: String? = nil
    /// «Не удалось определить место» под картой.
    @State private var сообщениеМеста: String? = nil
    /// Геопозиция запрещена — вопрос «Открыть настройки».
    @State private var отказМеста = false
    /// Человек сам двигал карту — только тогда центр карты становится точкой.
    @State private var двигали = false
    /// Детали двери показаны сводкой (есть сохранённые); «Изменить» раскрывает поля.
    @State private var свёрнуто: Bool
    /// Галочка «Сохранить в профиле».
    @State private var вПрофиль = false
    @State private var подставлено = false
    @FocusState private var поискВФокусе: Bool

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
        let естьАдрес = !цель.адрес.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        _свёрнуто = State(initialValue: !цель.посылка && естьАдрес && д.естьДетали)
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

    /// Адрес получения из профиля и «Сохранить в профиле» — только для «Куда доставить» сделки (не посылки).
    private var свойАдрес: Bool { !цель.откуда && !цель.посылка }

    private var текстАдреса: String { адрес.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var можноСохранить: Bool { текстАдреса.count >= 5 && !сохраняем && !отдано }

    private var дверьСейчас: ДверьСделки {
        var д = ДверьСделки()
        д.уПодъезда = уПодъезда
        д.квартира = квартира.trimmingCharacters(in: .whitespaces)
        д.подъезд = подъезд.trimmingCharacters(in: .whitespaces)
        д.этаж = этаж.trimmingCharacters(in: .whitespaces)
        д.домофон = домофон.trimmingCharacters(in: .whitespaces)
        д.комментарий = String(комментарий.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        return д
    }

    var body: some View {
        VStack(spacing: 0) {
            шапка
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    поиск
                    if !найдено.isEmpty { результаты }
                    if let итогПоиска { строкаПоиска(итогПоиска) }
                    карта
                    строкаТочки
                    карточкаАдреса
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) { низ }
        }
        .background(Theme.фонСтраницы.ignoresSafeArea())
        .tint(Theme.акцент)
        .interactiveDismissDisabled(сохраняем)
        .alert(т("geo_denied_t"), isPresented: $отказМеста) {
            Button(т("geo_settings")) {
                if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
            }
            Button(т("cancel"), role: .cancel) {}
        } message: {
            Text(т("geo_denied"))
        }
        .onChange(of: место.номер) { _, _ in
            guard let к = место.координата else { return }
            двигали = false
            поставить(к, сдвинуть: true, подобрать: true)
        }
        .onChange(of: место.номерСбоя) { _, _ in
            guard let сбой = место.сбой else { return }
            switch сбой {
            case .отказано:
                отказМеста = true
            case .нетОтвета:
                сообщениеМеста = т("geo_timeout")
            }
        }
        .task { await подставитьИзПрофиля() }
        .onDisappear {
            геокодЗадача?.cancel()
            поискЗадача?.cancel()
        }
    }

    // MARK: - Шапка и низ

    private var шапка: some View {
        ШапкаЛистаМастера(заголовок: т(цель.откуда ? "t_from" : "t_to"), подписьЗакрыть: т("cancel")) { закрыть() }
            .background(Theme.фонСтраницы)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.линия).frame(height: 1)
            }
    }

    /// Закреплённая «Сохранить» (как «Показать N предложений» листа фильтров) и ошибка над ней.
    private var низ: some View {
        ПанельКнопкиМастера {
            if let ошибка {
                Text(ошибка)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.скидкаТекст)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 6)
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
                .background(Theme.зелёный.opacity(можноСохранить || сохраняем ? 1 : 0.45),
                            in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
            .disabled(!можноСохранить)
        }
    }

    // MARK: - Поиск адреса

    private var поиск: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.текстВторой)
                .accessibilityHidden(true)
            TextField(т("search_ph"), text: $запрос)
                .focused($поискВФокусе)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { искать(сразу: true) }
                .onChange(of: запрос) { _, _ in искать(сразу: false) }
            if ищем {
                SiteSpinner(размер: 16, толщина: 2)
            } else if !запрос.isEmpty {
                Button {
                    запрос = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.текстВторой)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(т("clear"))
            }
        }
        .modifier(ПолеТочки())
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

    private func строкаПоиска(_ текст: String) -> some View {
        Label(текст, systemImage: "magnifyingglass")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.текстВторой)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Карта

    private var карта: some View {
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
                видимаяОбласть = контекст.region
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
                // Двигаете карту — точка в её центре, булавкой поверх.
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
        .frame(height: 240)
        .clipShape(форма)
        .overlay {
            форма.strokeBorder(Theme.линия, lineWidth: 1)
        }
        .accessibilityLabel(т("map_a11y"))
        .overlay(alignment: .bottomTrailing) {
            кнопкаМоегоМеста.padding(10)
        }
    }

    /// «Моё место» поверх карты, как в Картах: круг, значок геопозиции; пока ищем — колесо и не нажимается.
    private var кнопкаМоегоМеста: some View {
        Button {
            сообщениеМеста = nil
            место.запросить()
        } label: {
            ZStack {
                Circle().fill(Theme.поверхность)
                if место.ищет {
                    SiteSpinner(размер: 18, толщина: 2.2)
                } else {
                    Image(systemName: "location.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.акцент)
                }
            }
            .frame(width: 44, height: 44)
            .overlay { Circle().strokeBorder(Theme.линия, lineWidth: 1) }
            .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.94))
        .disabled(место.ищет)
        .accessibilityLabel(т("locate"))
    }

    /// Одна строка под картой: «не удалось определить место», «Точка на карте выбрана» или короткая подсказка.
    @ViewBuilder
    private var строкаТочки: some View {
        if let сообщениеМеста {
            Label(сообщениеМеста, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.скидкаТекст)
                .fixedSize(horizontal: false, vertical: true)
        } else if координата != nil {
            Label(т("point_ok"), systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.зелёный2)
        } else {
            Text(т("sub"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Адрес и дверь

    private var карточкаАдреса: some View {
        VStack(alignment: .leading, spacing: 12) {
            полеАдреса
            if !цель.посылка {
                Rectangle().fill(Theme.линия).frame(height: 1)
                if свёрнуто {
                    сводкаДвери
                } else {
                    поляДвери
                }
            }
        }
        .padding(16)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.lg, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1)
        }
    }

    private var полеАдреса: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(т("addr_l"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.текст)
                Spacer(minLength: 0)
                if ищемАдрес {
                    SiteSpinner(размер: 14, толщина: 2)
                    Text(т("looking"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                }
            }
            TextField(т("addr_ph"), text: $адрес, axis: .vertical)
                .lineLimit(1...3)
                .textContentType(.fullStreetAddress)
                .onChange(of: адрес) { _, новое in
                    if новое.count > 300 { адрес = String(новое.prefix(300)) }
                }
                .modifier(ПолеТочки())
        }
    }

    /// Сохранённые детали двери одной строкой и две кнопки: «Изменить», «Другой адрес».
    private var сводкаДвери: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: уПодъезда ? "figure.walk" : "building.2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(уПодъезда ? т(цель.откуда ? "out_s" : "out_b") : дверьСейчас.сводка)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                        .fixedSize(horizontal: false, vertical: true)
                    if !комментарий.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(комментарий)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.текстВторой)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                кнопкаСводки(т("edit"), символ: "pencil") {
                    withAnimation(ДвижениеСайта.появление) { свёрнуто = false }
                }
                кнопкаСводки(т("other"), символ: "plus") { другойАдрес() }
            }
        }
    }

    private func кнопкаСводки(_ текст: String, символ: String, действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            HStack(spacing: 6) {
                Image(systemName: символ)
                    .font(.system(size: 13, weight: .bold))
                    .accessibilityHidden(true)
                Text(текст)
                    .font(.system(size: 14, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(КраскаСделокКабинета.акцент)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Theme.оттенокАкцента, in: RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
    }

    /// «Встречу у подъезда» включено — курьер звонит и вы выходите (квартира не нужна); выключено — курьер идёт к двери.
    private var поляДвери: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $уПодъезда) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(т(цель.откуда ? "out_s" : "out_b"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                    Text(т(уПодъезда ? (цель.откуда ? "door_out_s" : "door_out_b") : "door_up"))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
            }
            TextField(т("note_ph"), text: $комментарий, axis: .vertical)
                .lineLimit(2...4)
                .onChange(of: комментарий) { _, новое in
                    if новое.count > 300 { комментарий = String(новое.prefix(300)) }
                }
                .modifier(ПолеТочки())
                .accessibilityLabel(т("note_l"))
            if свойАдрес {
                Toggle(isOn: $вПрофиль) {
                    Text(т("to_profile"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.текст)
                }
                .tint(Theme.зелёный)
            }
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

    /// Адрес и дверь из профиля, если окно открыто без своих (новая сделка, сделка без адреса).
    @MainActor
    private func подставитьИзПрофиля() async {
        guard !подставлено, свойАдрес else { return }
        подставлено = true
        let пустаяДверь = !(цель.дверь?.естьДетали ?? false) && (цель.дверь?.комментарий ?? "").isEmpty
        if НастройкиМодель.shared.профиль == nil && текстАдреса.isEmpty {
            await НастройкиМодель.shared.загрузить()
        }
        let профиль = НастройкиМодель.shared.профиль
        let сохранённая = АдресПолученияПрофиля.дверь(профиль)
        // Сохранённого нет — новый адрес сразу запомнится (галочку можно снять).
        if сохранённая == nil && АдресПолученияПрофиля.текст(профиль) == nil { вПрофиль = true }
        if текстАдреса.isEmpty, let текст = АдресПолученияПрофиля.текст(профиль) {
            адрес = текст
            if координата == nil, let к = АдресПолученияПрофиля.точка(профиль) {
                координата = к
                камера = .region(MKCoordinateRegion(center: к, latitudinalMeters: 600, longitudinalMeters: 600))
            }
        }
        /* Поля двери подставляем, только если человек их ещё не трогал и адрес на экране — тот, что в профиле (или
           адреса ещё нет): у сделки с другим адресом и у разового «Другого адреса» квартира из дома была бы чужой —
           свернулась бы в сводку и ушла курьеру (to_door, set_pickup door). */
        let тронуто = дверьСейчас.естьДетали || !комментарий.isEmpty
        let тотЖеАдрес = текстАдреса.isEmpty || АдресПолученияПрофиля.тотЖе(текстАдреса, профиль)
        if пустаяДверь, !тронуто, тотЖеАдрес, let д = сохранённая {
            уПодъезда = д.уПодъезда
            квартира = д.квартира
            подъезд = д.подъезд
            этаж = д.этаж
            домофон = д.домофон
            комментарий = д.комментарий
        }
        if !текстАдреса.isEmpty && дверьСейчас.естьДетали { свёрнуто = true }
    }

    /// «Другой адрес»: разовый адрес этой сделки — всё с чистого листа, «Сохранить в профиле» выключена.
    private func другойАдрес() {
        геокодЗадача?.cancel()
        ищемАдрес = false
        адрес = ""
        координата = nil
        двигали = false
        уПодъезда = false
        квартира = ""
        подъезд = ""
        этаж = ""
        домофон = ""
        комментарий = ""
        вПрофиль = false
        сообщениеМеста = nil
        withAnimation(ДвижениеСайта.появление) { свёрнуто = false }
        поискВФокусе = true
    }

    /// Поставить точку: запомнить, при нужде показать на карте и подобрать адрес (как _apkReverse — через 0,7 с).
    /// Геокодер не ответил — точка остаётся, поле адреса не трогаем.
    private func поставить(_ к: CLLocationCoordinate2D, сдвинуть: Bool, подобрать: Bool) {
        guard CLLocationCoordinate2DIsValid(к) else { return }
        координата = к
        найдено = []
        сообщениеМеста = nil
        if сдвинуть {
            withAnimation(ДвижениеСайта.камера) {
                камера = .region(MKCoordinateRegion(center: к, latitudinalMeters: 500, longitudinalMeters: 500))
            }
        }
        геокодЗадача?.cancel()
        guard подобрать else {
            ищемАдрес = false
            return
        }
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

    /// Поиск по полю: 0,45 с после последней буквы (или сразу по «Найти»), прошлый запрос отменяется.
    private func искать(сразу: Bool) {
        поискЗадача?.cancel()
        итогПоиска = nil
        let текст = запрос.trimmingCharacters(in: .whitespacesAndNewlines)
        guard текст.count >= 3 else {
            найдено = []
            ищем = false
            return
        }
        let область = областьПоиска
        поискЗадача = Task { @MainActor in
            if !сразу {
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
            guard !Task.isCancelled else { return }
            ищем = true
            let итог = await ПоискАдресаКарты.найти(текст, область: область)
            guard !Task.isCancelled else { return }
            ищем = false
            switch итог {
            case .места(let места):
                if сразу && места.count == 1, let одно = места.first {
                    выбрать(одно)
                } else {
                    найдено = места
                }
            case .пусто:
                найдено = []
                итогПоиска = т("not_found")
            case .сбой:
                найдено = []
                итогПоиска = т("search_err")
            }
        }
    }

    /// Карта приближена к городу — ищем в видимой части, иначе по всему Казахстану.
    private var областьПоиска: MKCoordinateRegion? {
        guard let в = видимаяОбласть, в.span.latitudeDelta < 3 else { return nil }
        return в
    }

    private func выбрать(_ место: MKMapItem) {
        let к = место.placemark.coordinate
        let строка = ЛистТочкиСделки.строка(место.placemark)
        поискЗадача?.cancel()
        найдено = []
        итогПоиска = nil
        ищем = false
        запрос = ""
        поискВФокусе = false
        двигали = false
        поставить(к, сдвинуть: true, подобрать: строка.isEmpty)
        if !строка.isEmpty { адрес = строка }
    }

    /// Адрес ушёл — запомнить в профиле, если отмечено «Сохранить в профиле».
    private func запомнитьВПрофиле(_ текст: String) {
        guard свойАдрес, вПрофиль else { return }
        АдресПолученияПрофиля.сохранить(адрес: текст, точка: координата, дверь: дверьСейчас)
    }

    /// hovAddrSave + hovPickupSave сайта.
    private func сохранить() {
        guard !сохраняем, !отдано else { return }
        let текст = String(текстАдреса.prefix(300))
        guard текст.count >= 5 else {
            ошибка = т("short")
            return
        }
        ошибка = nil
        if let выбрано {
            // Новая сделка: адрес уходит в окно оформления, сервер получит его вместе с create.
            отдано = true
            запомнитьВПрофиле(текст)
            выбрано(АдресИзКарты(адрес: текст, точка: координата, дверь: значениеДвери(), уПодъезда: уПодъезда))
            закрыть()
            return
        }
        guard let м = модель else { return }
        if цель.посылка {
            // hovAddrSave при посылке: parcel_from / parcel_addr; ok — окно закрывается, иначе остаётся с ошибкой.
            сохраняем = true
            let точка = координата.flatMap { ТочкаСделки($0.latitude, $0.longitude) }
            м.передача.адресПосылки(откуда: цель.откуда, адрес: текст, точка: точка) { итог in
                сохраняем = false
                if let итог {
                    if !итог.isEmpty { ошибка = итог }
                } else {
                    отдано = true
                    закрыть()
                }
            }
            return
        }
        сохраняем = true
        var тело: [String: Any] = ["deal_id": м.id, "addr": текст]
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
                    отдано = true
                    запомнитьВПрофиле(текст)
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
        let д = дверьСейчас
        if д.уПодъезда {
            var з: [String: Any] = ["out": true]
            if !д.комментарий.isEmpty { з["note"] = д.комментарий }
            return з
        }
        var з: [String: Any] = ["flat": д.квартира, "porch": д.подъезд, "floor": д.этаж, "code": д.домофон]
        if !д.комментарий.isEmpty { з["note"] = д.комментарий }
        return з
    }

    // MARK: - Адрес по точке

    /// «Алматы, улица Абая, 10» — город (по справочнику, без «… городская администрация»), улица, дом; пусто — nil.
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
        if let город = метка.locality, !город.isEmpty { части.append(ГеоДанные.городБезАдминистрации(город)) }
        var улица = метка.thoroughfare ?? ""
        if let дом = метка.subThoroughfare, !дом.isEmpty {
            улица = улица.isEmpty ? дом : улица + ", " + дом
        }
        if !улица.isEmpty { части.append(улица) }
        if части.isEmpty, let имя = метка.name, !имя.isEmpty {
            части.append(ГеоДанные.городБезАдминистрации(имя))
        }
        return части.joined(separator: ", ")
    }
}

/// Итог поиска адреса: места, «ничего не найдено» или сбой сети.
enum ИтогПоискаАдреса {
    case места([MKMapItem])
    case пусто
    case сбой
}

/// Поиск адреса на карте (MKLocalSearch): в видимой части карты или по Казахстану, только места Казахстана, до шести.
@MainActor
enum ПоискАдресаКарты {
    private static let страна = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 48.02, longitude: 66.92),
                                                   span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 40))

    static func найти(_ текст: String, область: MKCoordinateRegion?) async -> ИтогПоискаАдреса {
        let поиск = MKLocalSearch.Request()
        поиск.naturalLanguageQuery = текст
        поиск.region = область ?? страна
        поиск.resultTypes = [.address, .pointOfInterest]
        do {
            let ответ = try await MKLocalSearch(request: поиск).start()
            let свои = ответ.mapItems.filter { м in
                let код = м.placemark.isoCountryCode ?? ""
                return код.isEmpty || код == "KZ"
            }
            let места = Array(свои.prefix(6))
            return места.isEmpty ? .пусто : .места(места)
        } catch {
            let н = error as NSError
            if н.domain == MKErrorDomain && н.code == Int(MKError.Code.placemarkNotFound.rawValue) { return .пусто }
            return .сбой
        }
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

/// Почему геопозиция не пришла.
enum СбойМестаТелефона: Equatable {
    /// Доступ запрещён (или ограничен) — нужна кнопка «Открыть настройки».
    case отказано
    /// Телефон не ответил за 10 секунд или вернул ошибку.
    case нетОтвета
}

/**
 «Определить моё место»: одна геопозиция телефона по нажатию (ulxGetPosition сайта). Разрешения нет — спрашиваем;
 запрещено — сбой .отказано; ответа нет 10 секунд — .нетОтвета, кнопка снова доступна. Пока ищем, второе нажатие
 ничего не делает. Каждая новая точка — номер + 1, каждый сбой — номерСбоя + 1 (повторное одинаковое событие тоже видно).
 */
@MainActor
final class МестоТелефона: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var координата: CLLocationCoordinate2D? = nil
    @Published private(set) var ищет = false
    @Published private(set) var номер = 0
    @Published private(set) var сбой: СбойМестаТелефона? = nil
    @Published private(set) var номерСбоя = 0
    private let менеджер = CLLocationManager()
    private var таймер: Task<Void, Never>? = nil

    override init() {
        super.init()
        менеджер.delegate = self
        менеджер.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func запросить() {
        guard !ищет else { return }
        сбой = nil
        координата = nil
        switch менеджер.authorizationStatus {
        case .notDetermined:
            ищет = true
            менеджер.requestWhenInUseAuthorization()
        case .denied, .restricted:
            ищет = true
            закончить(.отказано)
        default:
            ищет = true
            спросить()
        }
    }

    private func спросить() {
        менеджер.requestLocation()
        таймер?.cancel()
        таймер = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            self?.закончить(.нетОтвета)
        }
    }

    private func закончить(_ причина: СбойМестаТелефона) {
        таймер?.cancel()
        таймер = nil
        guard ищет else { return }
        менеджер.stopUpdatingLocation()
        сбой = причина
        номерСбоя += 1
        ищет = false
    }

    private func пришло(_ к: CLLocationCoordinate2D) {
        guard ищет else { return }
        таймер?.cancel()
        таймер = nil
        координата = к
        номер += 1
        ищет = false
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let статус = manager.authorizationStatus
        Task { @MainActor in
            guard self.ищет, self.таймер == nil else { return }
            switch статус {
            case .authorizedWhenInUse, .authorizedAlways:
                self.спросить()
            case .denied, .restricted:
                self.закончить(.отказано)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let последняя = locations.last else { return }
        let к = последняя.coordinate
        Task { @MainActor in self.пришло(к) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let запрещено = (error as NSError).domain == kCLErrorDomain && (error as NSError).code == CLError.Code.denied.rawValue
        Task { @MainActor in self.закончить(запрещено ? .отказано : .нетОтвета) }
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
            "sub": "Поставьте точку — курьер приедет к подъезду",
            "search_ph": "Найти адрес или место", "clear": "Очистить", "point_ok": "Точка на карте выбрана",
            "search_err": "Нет связи — поиск не сработал, попробуйте ещё раз",
            "geo_denied_t": "Нет доступа к геопозиции",
            "geo_denied": "Разрешите Kliko доступ к геопозиции в настройках — или найдите адрес поиском.",
            "geo_settings": "Открыть настройки",
            "geo_timeout": "Не удалось определить место — попробуйте ещё раз или найдите адрес поиском",
            "door_up": "Курьер поднимется к двери — укажите квартиру",
            "door_out_b": "Курьер позвонит, и вы выйдете к подъезду",
            "door_out_s": "Курьер позвонит, и вы вынесете посылку к подъезду",
            "edit": "Изменить", "other": "Другой адрес", "to_profile": "Сохранить в профиле",
            "s_flat": "кв.", "s_porch": "подъезд", "s_floor": "этаж", "s_code": "домофон",
            "prof_door_l": "Квартира, подъезд, этаж, домофон — для курьера",
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
            "not_found": "Ничего не найдено — уточните запрос или поставьте точку на карте",
            "login": "Войдите в кабинет", "pin": "Точка", "map_a11y": "Карта: нажмите, чтобы поставить точку"
        ],
        "kk": [
            "t_from": "Қайдан алып кету", "t_to": "Қайда жеткізу",
            "sub": "Нүкте қойыңыз — курьер кіреберіске келеді",
            "search_ph": "Мекенжай немесе орын іздеу", "clear": "Тазалау", "point_ok": "Картада нүкте таңдалды",
            "search_err": "Байланыс жоқ — іздеу орындалмады, қайталап көріңіз",
            "geo_denied_t": "Геолокацияға рұқсат жоқ",
            "geo_denied": "Баптауларда Kliko-ға геолокацияға рұқсат беріңіз — немесе мекенжайды іздеп табыңыз.",
            "geo_settings": "Баптауларды ашу",
            "geo_timeout": "Орынды анықтау мүмкін болмады — қайталаңыз немесе мекенжайды іздеп табыңыз",
            "door_up": "Курьер есікке дейін көтеріледі — пәтерді көрсетіңіз",
            "door_out_b": "Курьер қоңырау шалады, сіз кіреберіске шығасыз",
            "door_out_s": "Курьер қоңырау шалады, сіз сәлемдемені кіреберіске шығарасыз",
            "edit": "Өзгерту", "other": "Басқа мекенжай", "to_profile": "Профильде сақтау",
            "s_flat": "пәтер", "s_porch": "кіреберіс", "s_floor": "қабат", "s_code": "домофон",
            "prof_door_l": "Пәтер, кіреберіс, қабат, домофон — курьер үшін",
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
            "sub": "Drop a pin — the courier will come to the entrance",
            "search_ph": "Search for an address or place", "clear": "Clear", "point_ok": "Pin set on the map",
            "search_err": "No connection — search failed, please try again",
            "geo_denied_t": "No access to location",
            "geo_denied": "Allow Kliko to use your location in Settings — or find the address with search.",
            "geo_settings": "Open Settings",
            "geo_timeout": "Couldn't get your location — try again or find the address with search",
            "door_up": "The courier will come up to your door — add the apartment",
            "door_out_b": "The courier will call and you'll come out to the entrance",
            "door_out_s": "The courier will call and you'll bring the parcel out to the entrance",
            "edit": "Edit", "other": "Another address", "to_profile": "Save to profile",
            "s_flat": "apt", "s_porch": "entrance", "s_floor": "floor", "s_code": "intercom",
            "prof_door_l": "Apartment, entrance, floor, intercom — for the courier",
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
            "sub": "ضع نقطة — سيأتي المندوب إلى المدخل",
            "search_ph": "ابحث عن عنوان أو مكان", "clear": "مسح", "point_ok": "تم اختيار النقطة على الخريطة",
            "search_err": "لا يوجد اتصال — تعذّر البحث، حاول مرة أخرى",
            "geo_denied_t": "لا يوجد وصول إلى الموقع",
            "geo_denied": "اسمح لـ Kliko باستخدام موقعك من الإعدادات — أو ابحث عن العنوان.",
            "geo_settings": "فتح الإعدادات",
            "geo_timeout": "تعذّر تحديد موقعك — حاول مرة أخرى أو ابحث عن العنوان",
            "door_up": "سيصعد المندوب إلى الباب — أدخل رقم الشقة",
            "door_out_b": "سيتصل المندوب وتخرج إليه عند المدخل",
            "door_out_s": "سيتصل المندوب وتُخرج الطرد إلى المدخل",
            "edit": "تعديل", "other": "عنوان آخر", "to_profile": "حفظ في الملف الشخصي",
            "s_flat": "شقة", "s_porch": "مدخل", "s_floor": "طابق", "s_code": "إنتركم",
            "prof_door_l": "الشقة والمدخل والطابق والإنتركم — للمندوب",
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

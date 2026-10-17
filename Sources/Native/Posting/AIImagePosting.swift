import SwiftUI
import UIKit

/**
 КАРТИНКА ПО ОПИСАНИЮ В ПОДАЧЕ — ПОМЕТКИ ФОТО, ВХОД И ЗАМЕТКА ПЕРЕД ПУБЛИКАЦИЕЙ (ultra-site 14.10.2026, часть 2).

 Запись на цель подачи («new» или «edit:<id>»), на телефоне, вместе с черновиком подачи: пометки взятых картинок
 (адрес → illustration | cover) для плашки на плитке и запуск, ответа которого окно не дождалось (закрыли окно,
 оборвалась связь): при новом открытии окно ждёт его в last ответа info. Чужому человеку (другой id сессии) запись не
 достаётся. Пометку «создано ИИ» в объявление ставит сервер по своей записи о файле — приложение её не шлёт; настоящие
 фото сервер ставит первыми, а иллюстрацию главным кадром не делает, пока есть хоть одно настоящее.

 Правка опубликованного: пометки — с сервера, photo_marks[n].gen записи my_items (та же длина и порядок, что images);
 старое поле images_meta — тоже. Вход «Нет фото? Создать иллюстрацию» — на шаге «Фото», только когда сервер сказал
 «можно» для раздела формы (ГотовностьИИФото.доступно).
 */

// MARK: - Запись подачи

struct ЗаписьИИФотоПодачи: Codable, Equatable {
    /// Адрес взятой картинки → illustration | cover.
    var метки: [String: String] = [:]
    /// Запуск ушёл, а окно ответа не дождалось: при новом открытии — ждать его в last.
    var ждём = false
    /// Ключ last до этого запуска (номер или адрес): новая картинка — та, что отличается.
    var прежний = ""
    var время: Double = 0
}

/// Что лежит на телефоне: чьи записи и сами записи по целям подачи.
private struct ХранилищеИИФотоПодачи: Codable {
    var кто: String
    var записи: [String: ЗаписьИИФотоПодачи]
}

/// Слабая ссылка на подачу: подача, где выбор способа уже начинал всё заново, не держится в памяти.
final class СлабаяПодачаИИФото {
    weak var подача: ПодачаМодель?

    init(_ подача: ПодачаМодель) {
        self.подача = подача
    }
}

@MainActor
final class ИИФотоПодачи: ObservableObject {
    static let shared = ИИФотоПодачи()

    /// Растёт при каждой записи: экраны (плашки плиток) перечитывают себя. Чтение записей его не трогает — их можно
    /// читать прямо из body.
    @Published private(set) var версия = 0

    private var записи: [String: ЗаписьИИФотоПодачи] = [:]
    private var кто = ""
    private var прочитано = false
    private var начатыеЗаново: [СлабаяПодачаИИФото] = []

    /// v1 — прежний договор (диалог, черновик ИИ); его записи не читаются.
    private static let ключ = "kliko.aiimage.posting.v2"
    private static let ключПрежний = "kliko.aiimage.posting.v1"
    /// Как у черновика подачи — 7 дней.
    private static let срок: TimeInterval = 7 * 24 * 3600
    /// Сколько ждать незаконченный запуск после закрытия окна: дольше — его уже не ищем.
    private static let срокОжидания: TimeInterval = 15 * 60

    private init() {}

    private func ключЦели(_ подача: ПодачаМодель) -> String { подача.цель.id }

    /// Кто подаёт: uid страницы кабинета подачи, иначе id сессии приложения; пусто — ещё не знаем.
    private func ктоПодаёт(_ подача: ПодачаМодель) -> String {
        let uid = подача.страница.состояние?.uid ?? ""
        return uid.isEmpty ? СессияПриложения.shared.id : uid
    }

    /**
     Записи с телефона — один раз на человека; сменился человек — чужие записи не показываем и стираем. Пока не знаем,
     кто это (пустой id), — записи только в памяти: чужое не показываем, своё не стираем.
     */
    private func прочитать(_ подача: ПодачаМодель) {
        let сейчас = ктоПодаёт(подача)
        if прочитано && кто == сейчас { return }
        записи = [:]
        кто = сейчас
        guard !сейчас.isEmpty else {
            прочитано = false
            return
        }
        прочитано = true
        UserDefaults.standard.removeObject(forKey: Self.ключПрежний)
        guard let данные = UserDefaults.standard.data(forKey: Self.ключ),
              let хранилище = try? JSONDecoder().decode(ХранилищеИИФотоПодачи.self, from: данные) else { return }
        guard хранилище.кто == сейчас else {
            UserDefaults.standard.removeObject(forKey: Self.ключ)
            return
        }
        let граница = Date().timeIntervalSince1970 - Self.срок
        записи = хранилище.записи.filter { $0.value.время > граница }
    }

    private func записать() {
        guard !кто.isEmpty else { return }
        let пустые = записи.filter { $0.value.метки.isEmpty && !$0.value.ждём }
        for (ключ, _) in пустые { записи[ключ] = nil }
        guard !записи.isEmpty else {
            UserDefaults.standard.removeObject(forKey: Self.ключ)
            return
        }
        if let данные = try? JSONEncoder().encode(ХранилищеИИФотоПодачи(кто: кто, записи: записи)) {
            UserDefaults.standard.set(данные, forKey: Self.ключ)
        }
    }

    func запись(_ подача: ПодачаМодель) -> ЗаписьИИФотоПодачи {
        прочитать(подача)
        return записи[ключЦели(подача)] ?? ЗаписьИИФотоПодачи()
    }

    private func изменить(_ подача: ПодачаМодель, _ правка: (inout ЗаписьИИФотоПодачи) -> Void) {
        прочитать(подача)
        var з = записи[ключЦели(подача)] ?? ЗаписьИИФотоПодачи()
        правка(&з)
        з.время = Date().timeIntervalSince1970
        записи[ключЦели(подача)] = з
        записать()
        версия += 1
    }

    /// Запись цели — прочь: на телефоне не остаётся ничего.
    private func стереть(_ подача: ПодачаМодель) {
        прочитать(подача)
        guard записи[ключЦели(подача)] != nil else { return }
        записи[ключЦели(подача)] = nil
        записать()
        версия += 1
    }

    // MARK: Запуск без ответа

    /// Запуск ушёл: до ответа запись помнит его (окно могут закрыть).
    func ждём(_ подача: ПодачаМодель, прежний: String) {
        изменить(подача) { з in
            з.ждём = true
            з.прежний = прежний
        }
    }

    /// Ответ получен (или ждать больше нечего).
    func дождались(_ подача: ПодачаМодель) {
        guard запись(подача).ждём else { return }
        изменить(подача) { з in
            з.ждём = false
            з.прежний = ""
        }
    }

    /// Незаконченный запуск этой подачи: ключ last до него; nil — ждать нечего (или давно).
    func ожидание(_ подача: ПодачаМодель) -> String? {
        let з = запись(подача)
        guard з.ждём else { return nil }
        guard Date().timeIntervalSince1970 - з.время < Self.срокОжидания else {
            дождались(подача)
            return nil
        }
        return з.прежний
    }

    // MARK: Пометки фото

    func пометка(_ подача: ПодачаМодель, адрес: String) -> String? {
        guard !адрес.isEmpty else { return nil }
        return запись(подача).метки[адрес]
    }

    func отметитьФото(_ подача: ПодачаМодель, адрес: String, вид: String) {
        guard !адрес.isEmpty, ["illustration", "cover"].contains(вид) else { return }
        изменить(подача) { $0.метки[адрес] = вид }
    }

    // MARK: Публикация

    /// Галочки «Проверил характеристики» больше нет: сервер собирает только картинку, поля пишет человек. Всегда nil.
    func нужнаГалочка(_ подача: ПодачаМодель) -> String? { nil }

    /// В submit ничего не добавляется: пометку «создано ИИ» сервер ставит сам по записи о файле.
    func поляПодачи(_ подача: ПодачаМодель) -> [String: Any] { [:] }

    /// Объявление сохранено: запись этой цели больше не нужна.
    func послеПубликации(_ подача: ПодачаМодель) {
        стереть(подача)
    }

    /**
     Первый экран новой подачи с чистой формой (открытьПервыйЭкран, PostingQuick.swift; заготовка «Моего»): запись новой
     подачи — стереть. Один раз на открытую подачу: «Подать ещё» и повторный вызов запись не трогают.
     */
    func начатьЗаново(_ подача: ПодачаМодель) {
        guard !подача.правка else { return }
        начатыеЗаново.removeAll { $0.подача == nil }
        guard !начатыеЗаново.contains(where: { $0.подача === подача }) else { return }
        начатыеЗаново.append(СлабаяПодачаИИФото(подача))
        guard подача.плитки.isEmpty, подача.форма.название.isEmpty else { return }
        стереть(подача)
    }

    /**
     Отказ submit / edit_item «нужно своё фото» (need_real_photo — если сервер когда-нибудь так ответит): вопрос
     «Добавьте хотя бы одно своё фото» и шаг «Фото». true — отказ разобран.
     */
    func разобратьОтказПодачи(_ j: [String: Any], подача: ПодачаМодель) -> Bool {
        typealias A = МоиОбъявленияAPI
        guard A.строка(j["code"]) == "need_real_photo" || A.да(j["need_real_photo"]) else { return false }
        let т = ИИФотоText.т
        let ошибка = A.строка(j["error"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let текст = ИИФотоAPI.текстСервера(ошибка, предел: 400)
        подача.вопрос = ВопросПодачи(заголовок: т("aim_real_t"), текст: текст.isEmpty ? т("aim_real_need") : текст,
                                    да: т("aim_real_add"), нет: т("aim_later"),
                                    действие: { [weak подача] in подача?.кФотоИИ() })
        return true
    }
}

// MARK: - Подача

extension ПодачаМодель {
    /// Плашка у плитки: illustration | cover | edited | nil. Свои пометки (картинки, взятые в этой подаче) и — в правке
    /// опубликованного — пометки сервера из my_items.
    func пометкаИИ(_ плитка: ПлиткаФото) -> String? {
        guard плитка.готова else { return nil }
        if let своя = ИИФотоПодачи.shared.пометка(self, адрес: плитка.url) { return своя }
        return меткиСервераИИ[плитка.url]
    }

    /**
     Правка: адрес фото → вид по записи my_items. photo_marks[n].gen — создано ИИ (gen.cover — обложка без рисунка);
     старое images_meta[n].ai — illustration | edited. Та же длина и порядок, что images; неизвестное пропускается.
     */
    var меткиСервераИИ: [String: String] {
        typealias A = МоиОбъявленияAPI
        guard правка else { return [:] }
        let адреса = ((исходник["images"] as? [Any]) ?? []).map { A.строка($0) }
        var итог: [String: String] = [:]
        if let меты = исходник["images_meta"] as? [Any] {
            for (номер, элемент) in меты.enumerated() where номер < адреса.count {
                guard let мета = элемент as? [String: Any] else { continue }
                let вид = A.строка(мета["ai"])
                if !адреса[номер].isEmpty && ["illustration", "edited"].contains(вид) { итог[адреса[номер]] = вид }
            }
        }
        if let метки = исходник["photo_marks"] as? [Any] {
            for (номер, элемент) in метки.enumerated() where номер < адреса.count {
                guard let метка = элемент as? [String: Any], let создано = метка["gen"] as? [String: Any],
                      !адреса[номер].isEmpty else { continue }
                итог[адреса[номер]] = A.да(создано["cover"]) ? "cover" : "illustration"
            }
        }
        return итог
    }

    /**
     Студия (PhotoStudio*) на плитке — со стороны ИИ: не картинка ИИ. Иначе обработанный кадр картинки ИИ выглядел бы
     в подаче как своё фото.
     */
    func студияБезИИ(_ плитка: ПлиткаФото) -> Bool {
        пометкаИИ(плитка) == nil
    }

    /// Плитка для плашки «Сделать как в каталоге»: первая, которую можно открыть в студии, и не картинка ИИ.
    var плиткаПлашкиСтудииБезИИ: ПлиткаФото? {
        guard плиткаДляПлашкиСтудии != nil else { return nil }
        return плитки.first { студияДоступна($0) && студияБезИИ($0) }
    }

    /// Картинок ИИ среди фото подачи.
    func иллюстрацийИИ() -> Int {
        плитки.filter { пометкаИИ($0) != nil }.count
    }

    /// Настоящих фото (не картинок ИИ) среди фото подачи — загруженных или ещё грузящихся.
    var настоящихФотоИИ: Int {
        плитки.filter { $0.ошибка == nil && (!$0.готова || пометкаИИ($0) == nil) }.count
    }

    /// Правки фото ИИ больше нет: сервер рисует только по тексту (only_text). Пункта «Править с ИИ» у плиток нет.
    func правкаИИДоступна(_ плитка: ПлиткаФото) -> Bool { false }

    /// Подсказка перед публикацией: фото есть, но все — картинки ИИ. nil — всё в порядке.
    var подсказкаНастоящегоФотоИИ: String? {
        guard иллюстрацийИИ() > 0, настоящихФотоИИ == 0 else { return nil }
        return ИИФотоText.т("aim_real_need")
    }

    /// «Добавить фото»: к фото подачи — на короткой подаче камера, иначе шаг «Фото».
    func кФотоИИ() {
        подтверждение = false
        if быстрый && !правка {
            кКамере()
        } else {
            шаг = .фото
            if экран != .шаги { экран = .шаги }
        }
    }
}

// MARK: - Окно чата поверх подачи

/// Как открыть окно: иллюстрация по описанию; правка фото плитки — прежний вход (сервер её не умеет, пункта нет).
enum ВходЧатаИИФото: Identifiable, Equatable {
    case черновик
    case правка(UUID)

    var id: String {
        switch self {
        case .черновик: return "draft"
        case .правка(let плитка): return "edit:" + плитка.uuidString
        }
    }
}

/// Полноэкранный чат поверх шага: вход не nil — окно открыто.
struct ПоказЧатаИИФото: ViewModifier {
    let подача: ПодачаМодель
    @Binding var вход: ВходЧатаИИФото?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $вход) { выбранный in
                ЭкранЧатаИИФото(подача: подача, вход: выбранный, закрыть: { вход = nil })
            }
    }
}

extension View {
    /// Окно «Иллюстрация с ИИ» для подачи; `вход` — как открыть или nil.
    func чатИИФото(подача: ПодачаМодель, вход: Binding<ВходЧатаИИФото?>) -> some View {
        modifier(ПоказЧатаИИФото(подача: подача, вход: вход))
    }
}

// MARK: - Входы

/* Прежней карточки на экране выбора способа подачи («Объявление по названию») нет: сервер рисует картинку только для
   известного раздела, а экрана выбора с пачки 83 нет вовсе — новая подача начинается с камеры. Вход — на шаге «Фото». */

/**
 Шаг «Фото»: «Нет фото? Создать иллюстрацию» — окно-чат. Только когда сервер для раздела формы сказал on и can (и
 cat_ok не false), настоящих фото ещё нет и место для фото есть. Раздел формы сменился — сведения спрашиваются заново
 (из body — отдельной задачей: сам вход без сведений не виден и своего .task не получил бы).
 */
struct ВходИИФотоВШаге: View {
    @ObservedObject var модель: ПодачаМодель
    let открыть: () -> Void
    @ObservedObject private var готовность = ГотовностьИИФото.shared
    @ObservedObject private var хранилище = ИИФотоПодачи.shared

    init(модель: ПодачаМодель, открыть: @escaping () -> Void) {
        self.модель = модель
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    private var виден: Bool {
        Config.ииРедакторФото && готовность.доступно(раздел: модель.форма.раздел) && модель.настоящихФотоИИ == 0
            && модель.местоФото > 0
    }

    var body: some View {
        let _ = готовность.спроситьДля(модель.форма.раздел)
        if виден {
            Button {
                ОткликСайта.выбор()
                открыть()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 40, height: 40)
                        .background(LinearGradient(colors: [Theme.кнопкаКамерыНачало, Theme.кнопкаКамерыКонец],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(т("aim_step_t"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(КраскаПодачи.текст)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(т("aim_step_s"))
                            .font(.caption)
                            .foregroundStyle(Theme.текстВторой)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(КраскаПодачи.хорошоТекст)
                        .accessibilityHidden(true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(КраскаПодачи.хорошоФон, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                        .strokeBorder(КраскаПодачи.хорошоТекст.opacity(0.28), lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .transition(.opacity)
        }
    }
}

/// Пункт меню плитки фото — прежняя правка ИИ (правкаИИДоступна сейчас всегда false, пункт не показывается).
struct ПунктИИФотоПлитки: View {
    let действие: () -> Void

    init(действие: @escaping () -> Void) {
        self.действие = действие
    }

    var body: some View {
        Button(ИИФотоText.т("aim_menu_edit"), systemImage: "wand.and.stars", action: действие)
    }
}

/// Плашка на плитке и на картинке окна: «Иллюстрация ИИ», «Обложка ИИ» или «Изменено ИИ».
struct ПометкаИИФото: View {
    let вид: String
    var мелкая = true

    init(вид: String, мелкая: Bool = true) {
        self.вид = вид
        self.мелкая = мелкая
    }

    static func текст(_ вид: String) -> String {
        switch вид {
        case "illustration": return ИИФотоText.т("aim_mark_ill")
        case "cover": return ИИФотоText.т("aim_mark_cover")
        default: return ИИФотоText.т("aim_mark_edit")
        }
    }

    private var значок: String {
        switch вид {
        case "illustration": return "paintbrush.pointed.fill"
        case "cover": return "rectangle.on.rectangle"
        default: return "wand.and.rays"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: значок)
                .font(.system(size: мелкая ? 8 : 11, weight: .bold))
                .accessibilityHidden(true)
            Text(Self.текст(вид))
                .font(мелкая ? .system(size: 9, weight: .bold) : .caption.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, мелкая ? 5 : 8)
        .padding(.vertical, мелкая ? 2 : 4)
        .background(Color.black.opacity(0.62), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.текст(вид))
    }
}

// MARK: - Перед публикацией

/**
 Окно «Проверьте перед публикацией»: все фото — картинки ИИ — подсказка «Добавьте настоящие фото» и «Добавить фото»;
 картинки ИИ в объявлении — тихая заметка, что покупатель увидит их с подписью «не фото товара».
 */
struct ПроверкаИИПодачи: View {
    @ObservedObject var модель: ПодачаМодель
    @ObservedObject private var хранилище = ИИФотоПодачи.shared

    init(модель: ПодачаМодель) {
        self.модель = модель
    }

    private func т(_ ключ: String) -> String { ИИФотоText.т(ключ) }

    var body: some View {
        if модель.иллюстрацийИИ() > 0 {
            VStack(alignment: .leading, spacing: 10) {
                if let подсказка = модель.подсказкаНастоящегоФотоИИ {
                    VStack(alignment: .leading, spacing: 8) {
                        ЗаметкаПодачи(подсказка, тон: .внимание, значок: "camera.badge.ellipsis")
                        КнопкаПодачиВторая(т("aim_real_add")) { модель.кФотоИИ() }
                    }
                }
                ЗаметкаПодачи(т("aim_marked_note"), тон: .серый, значок: "wand.and.stars")
            }
        }
    }
}

import SwiftUI
import AVFoundation
import PhotosUI
import UIKit

/**
 СЪЁМКА ПО ПЛАНУ В СВОЕЙ КАМЕРЕ (#rshcam сайта: rshCamOpen … rshCamClose в js/cabinet.js; владелец 29.09.2026: «вот тут
 вспомогательная камера была — тоже добей его. Подсказки»).

 Как у сайта:
   · вход — «Камера» и «Снять по шагам» при плане съёмки (rshStepStart) и тап по неснятому кадру плана — камера сразу на
     нём (realtyShotPick → rshCamOpen(k));
   · сверху ✕, полоски шагов с «N / M», «Начать сначала» (только когда есть что сбрасывать) и «Другая камера»;
   · видоискатель во весь экран между панелями, рамка из четырёх уголков в пропорции плана (SHOT_AR: одежда и телефон
     4:5, ноутбук и запчасть 4:3, машина, мебель и жильё 16:9) чуть выше середины, виньетка; снизу подсказка кадра —
     значок и «ШАГ N ИЗ M», крупно название кадра, под ним совет плана; план закрыт — «План закрыт · Всё снято»;
   · снизу плитка галереи (последний кадр), лента снятых и счёт «2 / 5 · осталось 3»; «Пропустить» · затвор · «Готово»;
   · снимок режется ровно по рамке в пропорции плана, до 2200 px по большей стороне (rshCamShoot), и уходит ТЕМ ЖЕ путём,
     что фото из галереи (сжатие, водяной знак, upload_photo) — со своим местом плана (slot), кадры встают в порядке
     плана (_rshSortInPlace); закреплённый чипом кадр — первым, дальше первый неснятый и непропущенный (_rcNext);
   · кадр с текстом, который решает сделку (экран «О системе», приборка с пробегом, маркировка, бирка, ветпаспорт…,
     _rcRead), — проверка «Прочиталось … Верно, дальше / Переснять» через cabinet.php?action=shot_read, только если у
     сайта есть Kliko AI; ответа нет — съёмка идёт дальше молча;
   · «Начать сначала» спрашивает и удаляет кадры плана; «Пропустить» живёт только в этой съёмке.
 Своё приложения: фонарик (у сайта в браузере его нет), «Переснять» тапом по кадру ленты (с вопросом), озвучка
 следующего кадра для VoiceOver. Нет доступа к камере — объяснение и «Открыть Настройки», галерея снизу работает и кладёт
 кадр на его место плана. Лимит фото — как у всей формы: места нет — «Можно до N фото».
 */

// MARK: - Какую камеру открыть с шага «Фото»

/// Камера шага «Фото»: системная (плана съёмки нет) или своя по плану (закреплён — кадр, с которого начать).
enum КамераШагаФото: Identifiable, Equatable {
    case система
    case план(String)

    var id: String {
        switch self {
        case .система: return "system"
        case .план(let ключ): return "plan:" + ключ
        }
    }
}

// MARK: - Места кадров в плане (slot сайта)

extension ПодачаМодель {
    /// Места плана, у которых уже есть кадр (готовый или летящий на сервер).
    var снятыеМеста: Set<String> {
        Set(плитки.map { $0.слот }.filter { !$0.isEmpty })
    }

    /// Плитка, занявшая место плана.
    func плиткаМеста(_ ключ: String) -> ПлиткаФото? {
        guard !ключ.isEmpty else { return nil }
        return плитки.first { $0.слот == ключ }
    }

    /// _rshSlotMap: адрес готового кадра → место плана (shot_slots в submit, edit_item и черновике).
    var картаМест: [String: String] {
        var карта: [String: String] = [:]
        for плитка in плитки where плитка.готова && !плитка.слот.isEmpty {
            карта[плитка.url] = плитка.слот
        }
        return карта
    }

    /// _rshSlotApply: вернуть кадры на места плана; адрес мог приехать с базой сайта — сверяем и по хвосту.
    func вернутьМеста(_ карта: [String: String]) {
        guard !карта.isEmpty else { return }
        var новые = плитки
        var было = false
        for i in новые.indices where новые[i].готова && новые[i].слот.isEmpty {
            let адрес = новые[i].url
            var место = карта[адрес] ?? ""
            if место.isEmpty {
                for (ключ, значение) in карта where !ключ.isEmpty && (ключ.hasSuffix(адрес) || адрес.hasSuffix(ключ)) {
                    место = значение
                    break
                }
            }
            if !место.isEmpty {
                новые[i].слот = место
                было = true
            }
        }
        if было { плитки = новые }
    }

    /// _rshSortInPlace: порядок фото = порядок плана; главное, выбранное вручную, — первым; вне плана — следом, как были.
    func расставитьПоПлану() {
        guard let план = планСъёмки, плитки.count > 1 else { return }
        var порядок: [String: Int] = [:]
        for (номер, ключ) in план.ключи.enumerated() where порядок[ключ] == nil {
            порядок[ключ] = номер
        }
        let главная = главнаяВручную
        let ранги: [Int] = плитки.map { плитка in
            if let главная, плитка.id == главная { return -1 }
            return порядок[плитка.слот] ?? 900
        }
        let порядокНовый = плитки.indices.sorted { a, b in
            ранги[a] != ранги[b] ? ранги[a] < ранги[b] : a < b
        }
        guard порядокНовый != Array(плитки.indices) else { return }
        плитки = порядокНовый.map { плитки[$0] }
    }

    /// _rshClaim: единственное фото, добавленное общей кнопкой, пока план пуст, — первый пункт плана (общий вид).
    func занятьПервоеМесто(_ id: UUID) {
        guard плитки.count == 1, плитки[0].id == id, плитки[0].слот.isEmpty,
              let первый = планСъёмки?.ключи.first, !первый.isEmpty else { return }
        плитки[0].слот = первый
    }

    /// «Начать сначала»: кадры плана удаляются (вне плана — остаются). Сколько удалили.
    @discardableResult
    func удалитьКадрыПлана() -> Int {
        let ушли = плитки.filter { !$0.слот.isEmpty }.map { $0.id }
        for id in ушли { удалитьФото(id) }
        return ушли.count
    }

    /// «Переснять»: кадр этого места удаляется, место снова пустое.
    func освободитьМестоПлана(_ ключ: String) {
        guard let плитка = плиткаМеста(ключ) else { return }
        удалитьФото(плитка.id)
    }

    /// Проверка текста на кадре (HAS_AI_KEY сайта) — только когда Kliko AI у сайта есть и не выключен для подачи.
    var проверкаКадровДоступна: Bool {
        Config.распознаваниеВПодаче && страница.ключИИ && !страница.иИЗаблокирован
    }
}

// MARK: - Кадры плана: пропорция, значок, проверка текста

extension ПланСъёмки {
    /// SHOT_AR сайта (ширина / высота): высокое — 4:5, вещь на столе — 4:3, длинное и неизвестное — 16:9.
    static func пропорция(_ группа: String) -> CGFloat {
        switch группа {
        case "clothes", "shoes", "phone", "animals", "birds", "reptiles", "livestock":
            return 4.0 / 5.0
        case "laptop", "building", "auto-parts", "petgoods", "fish":
            return 4.0 / 3.0
        default:
            return 16.0 / 9.0
        }
    }

    /// _rcRead сайта: ОДИН кадр на план, где текст решает сделку, — его проверяем на читаемость.
    static let читаемые: Set<String> = [
        "g_sysinfo", "dash", "marking", "g_tag", "b_mark", "pg_date", "r_serial", "a_docs", "rp_docs", "l_docs", "bd_ring"
    ]

    /// Значок кадра рядом с «ШАГ N ИЗ M» (у сайта — контур Tabler рядом с номером шага, не поверх кадра).
    static func значок(_ ключ: String) -> String {
        значки[ключ] ?? "camera.viewfinder"
    }

    private static let значки: [String: String] = [
        "front34": "car.fill", "rear34": "car.rear.fill", "side": "car.side.fill", "cabin": "steeringwheel",
        "back": "sofa.fill", "dash": "speedometer", "engine": "engine.combustion.fill", "trunk": "suitcase.fill",
        "tires": "circle.circle", "body": "truck.box.fill", "part": "gearshape.2.fill", "marking": "barcode",
        "wear": "exclamationmark.triangle.fill", "set": "shippingbox.fill", "fit": "wrench.and.screwdriver.fill",
        "hull": "sailboat.fill", "trailer": "truck.box.fill", "frame": "bicycle", "drive": "gearshape.fill",
        "brakes": "circle.circle",
        "living": "sofa.fill", "kitchen": "fork.knife", "bedroom": "bed.double.fill", "bath": "bathtub.fill",
        "window": "square.split.2x2", "entrance": "door.left.hand.open", "facade": "house.fill", "yard": "leaf.fill",
        "street": "road.lanes", "hall": "building.2.fill", "rooms": "square.grid.2x2.fill",
        "parking": "parkingsign.circle.fill", "utils": "bolt.fill", "plot": "map.fill", "bounds": "square.dashed",
        "road": "road.lanes", "around": "globe",
        "g_front": "viewfinder", "g_back": "arrow.triangle.2.circlepath", "g_sysinfo": "info.circle.fill",
        "g_keys": "keyboard", "g_ports": "powerplug.fill", "g_box": "shippingbox.fill",
        "g_defect": "exclamationmark.triangle.fill", "g_tag": "tag.fill", "g_material": "square.grid.3x3.fill",
        "g_detail": "magnifyingglass", "g_angle": "rotate.3d", "g_sole": "shoeprints.fill", "g_size": "ruler.fill",
        "g_on": "power",
        "a_full": "pawprint.fill", "a_face": "face.smiling", "a_docs": "doc.text.fill", "a_where": "house.fill",
        "bd_full": "bird.fill", "bd_head": "bird", "bd_ring": "circle.dotted", "bd_cage": "archivebox.fill",
        "fs_fish": "fish.fill", "fs_tank": "drop.fill", "fs_gear": "gearshape.fill", "fs_size": "ruler.fill",
        "rp_full": "lizard.fill", "rp_head": "lizard", "rp_terr": "square.stack.fill", "rp_docs": "doc.text.fill",
        "pg_pack": "bag.fill", "pg_label": "list.bullet.rectangle.fill", "pg_date": "calendar", "pg_set": "shippingbox.fill",
        "l_side": "hare.fill", "l_head": "tag.fill", "l_docs": "doc.text.fill", "l_keep": "house.fill",
        "r_full": "shippingbox.fill", "r_kit": "square.stack.3d.up.fill", "r_wear": "magnifyingglass",
        "r_work": "play.circle.fill", "r_serial": "barcode",
        "b_stack": "square.stack.3d.up.fill", "b_close": "magnifyingglass", "b_mark": "tag.fill",
        "b_defect": "exclamationmark.triangle.fill"
    ]
}

// MARK: - Рамка и вырезка кадра (без главной нити: вызывается из Task.detached)

enum ВырезкаКадраПлана {
    /// .rc-frame: по центру, центр на 41 % высоты, почти во весь видоискатель, в пропорции плана.
    static func рамка(в место: CGSize, пропорция: CGFloat) -> CGRect {
        guard место.width > 0, место.height > 0, пропорция > 0 else { return .zero }
        var ширина = min(место.width * 0.88, место.height * 0.78)
        var высота = ширина / пропорция
        let предел = место.height * 0.74
        if высота > предел {
            высота = предел
            ширина = высота * пропорция
        }
        let верх = max(8, место.height * 0.41 - высота / 2)
        return CGRect(x: (место.width - ширина) / 2, y: верх, width: ширина, height: высота)
    }

    /**
     rshCamShoot: экранную рамку — в пиксели снимка. Превью заполняет вид (как object-fit: cover), поэтому считаем через
     масштаб по большей стороне и срезанные края; рамка вышла за снимок — зажимаем и добираем пропорцию по тому, что есть.
     Итог — не больше 2200 px по большей стороне.
     */
    static func часть(снимок: CGSize, вид: CGSize, рамка: CGRect,
                      пропорция: CGFloat) -> (часть: CGRect, размер: CGSize)? {
        let vw = снимок.width
        let vh = снимок.height
        guard vw > 1, vh > 1, пропорция > 0 else { return nil }
        var cx: CGFloat = 0
        var cy: CGFloat = 0
        var cw = vw
        var ch = vh
        let поРамке = вид.width > 0 && вид.height > 0 && рамка.width > 0 && рамка.height > 0
        if поРамке {
            let м = max(вид.width / vw, вид.height / vh)
            let сдвигX = (вид.width - vw * м) / 2
            let сдвигY = (вид.height - vh * м) / 2
            cx = (рамка.minX - сдвигX) / м
            cy = (рамка.minY - сдвигY) / м
            cw = рамка.width / м
            ch = рамка.height / м
        }
        cw = min(cw, vw)
        ch = min(ch, vh)
        if cw / ch > пропорция {
            cw = ch * пропорция
        } else {
            ch = cw / пропорция
        }
        if !поРамке {
            /* Размер видоискателя ещё не известен — берём середину снимка в пропорции плана. */
            cx = (vw - cw) / 2
            cy = (vh - ch) / 2
        }
        cx = max(0, min(vw - cw, cx))
        cy = max(0, min(vh - ch, cy))
        let сторона = min(2200, max(cw, ch)).rounded()
        let размер: CGSize
        if cw >= ch {
            размер = CGSize(width: сторона, height: (сторона / пропорция).rounded())
        } else {
            размер = CGSize(width: (сторона * пропорция).rounded(), height: сторона)
        }
        guard размер.width >= 1, размер.height >= 1, cw >= 1, ch >= 1 else { return nil }
        return (CGRect(x: cx, y: cy, width: cw, height: ch), размер)
    }

    /// Часть снимка в итоговый размер (поворот снимка учтён: UIImage.draw рисует его как видно) — JPEG 0.92, как у сайта.
    static func jpeg(_ снимок: UIImage, часть: CGRect, размер: CGSize) -> Data? {
        let формат = UIGraphicsImageRendererFormat()
        формат.scale = 1
        формат.opaque = true
        let k = размер.width / часть.width
        let полная = CGSize(width: снимок.size.width * снимок.scale * k, height: снимок.size.height * снимок.scale * k)
        let картинка = UIGraphicsImageRenderer(size: размер, format: формат).image { _ in
            снимок.draw(in: CGRect(x: -часть.minX * k, y: -часть.minY * k, width: полная.width, height: полная.height))
        }
        return картинка.jpegData(compressionQuality: 0.92)
    }
}

// MARK: - Состояния экрана

/// Вопрос внутри камеры (.rc-confirm сайта): обычное окно легло бы под неё.
enum ВопросСъёмкиПоПлану: Equatable {
    /// «Удалить снятые кадры плана и начать сначала?» — сколько кадров уйдёт.
    case сначала(Int)
    /// «Переснять «…»?» — место и подпись кадра.
    case переснять(String, String)
}

/// Проверка текста на кадре (_rcCheck): ждём ответ — ответа ещё нет.
struct ПроверкаСъёмкиПоПлану: Equatable {
    let ключ: String
    let подпись: String
    var хорошо = false
    var текст = ""
    var почему = ""
    var пришла = false

    init(ключ: String, подпись: String) {
        self.ключ = ключ
        self.подпись = подпись
    }
}

// MARK: - Экран

struct СъёмкаПоПлану: View {
    @ObservedObject var модель: ПодачаМодель
    let закрыть: () -> Void
    @StateObject private var камера = КамераПоиска()
    @Environment(\.accessibilityReduceMotion) private var меньшеДвижения
    /// Кадр, с которого начать (тап по чипу плана или «Переснять»); место закрыто — дальше обычным порядком.
    @State private var закреплён: String
    /// «Пропустить»: пометка живёт только внутри этой съёмки (_rcSkip).
    @State private var пропущенные: [String] = []
    @State private var вопрос: ВопросСъёмкиПоПлану? = nil
    @State private var проверка: ПроверкаСъёмкиПоПлану? = nil
    @State private var вспышка = false
    /// Размер видоискателя — по нему рамка на экране и вырезка снимка.
    @State private var видоискатель: CGSize = .zero
    @State private var выбор: [PhotosPickerItem] = []
    @State private var плашка: String? = nil
    /// Последний кадр этой съёмки — на плитке галереи, как в камере телефона.
    @State private var последний: UUID? = nil
    /// Последний снимок плёнки — пока своих кадров нет (доступ к фото уже дан; сами не спрашиваем).
    @State private var плёнка: UIImage? = nil

    init(модель: ПодачаМодель, закреплён: String, закрыть: @escaping () -> Void) {
        self.модель = модель
        self.закрыть = закрыть
        _закреплён = State(initialValue: закреплён)
    }

    private func т(_ ключ: String) -> String { СъёмкаПоПлануText.т(ключ) }

    private var тихо: Bool { меньшеДвижения || ДвижениеСайта.тихо }

    private var живая: Bool { камера.доступ == .есть || камера.доступ == .неизвестно }

    private var лимитТекст: String { String(format: ПодачаText.т("photo_cap_full"), модель.лимитФото) }

    // MARK: Шаги плана

    /// _rcNext: закреплённый — первым, если его место свободно; дальше первый неснятый и непропущенный.
    private func текущий(_ план: ПланСъёмки.План?, _ снятые: Set<String>) -> Int? {
        guard let план else { return nil }
        if !закреплён.isEmpty, !снятые.contains(закреплён), let номер = план.ключи.firstIndex(of: закреплён) {
            return номер
        }
        for (номер, ключ) in план.ключи.enumerated() where !снятые.contains(ключ) && !пропущенные.contains(ключ) {
            return номер
        }
        return nil
    }

    private func снято(_ план: ПланСъёмки.План?, _ снятые: Set<String>) -> Int {
        guard let план else { return 0 }
        return план.ключи.filter { снятые.contains($0) }.count
    }

    private func осталось(_ план: ПланСъёмки.План?, _ снятые: Set<String>) -> Int {
        guard let план else { return 0 }
        return план.ключи.filter { !снятые.contains($0) && !пропущенные.contains($0) }.count
    }

    private func подпись(_ план: ПланСъёмки.План?, _ номер: Int?) -> String {
        guard let план, let номер, номер >= 0, номер < план.кадры.count else { return "" }
        return план.кадры[номер]
    }

    private func ключ(_ план: ПланСъёмки.План?, _ номер: Int?) -> String {
        guard let план, let номер, номер >= 0, номер < план.ключи.count else { return "" }
        return план.ключи[номер]
    }

    /// Русская подпись кадра — для shot_read (сервер спрашивает Kliko AI по-русски).
    private func подписьПоРусски(_ план: ПланСъёмки.План?, _ номер: Int?) -> String {
        guard let план, let номер, номер >= 0, номер < план.кадрыRu.count else { return "" }
        return план.кадрыRu[номер]
    }

    /// Подпись места для ленты и вопроса «Переснять»: кадр плана или «Доп. фото».
    private func подписьМеста(_ план: ПланСъёмки.План?, _ место: String) -> String {
        guard let план, !место.isEmpty, let номер = план.ключи.firstIndex(of: место) else { return т("cam_extra") }
        return подпись(план, номер)
    }

    // MARK: Экран

    var body: some View {
        let план = модель.планСъёмки
        let снятые = модель.снятыеМеста
        let номер = текущий(план, снятые)
        let готово = снято(план, снятые)
        return VStack(spacing: 0) {
            верх(план, готово)
            видоискательВид(план, номер, готово)
            низ(план, номер, готово, осталось(план, снятые))
        }
        .background(Color.black.ignoresSafeArea())
        .statusBarHidden(true)
        .onAppear {
            камера.запустить()
            ПоследнееФотоГалереи.загрузить { кадр in плёнка = кадр }
        }
        .onDisappear { камера.остановить() }
        .onChange(of: выбор) { _, новые in
            guard let элемент = новые.first else { return }
            выбор = []
            взятьИзГалереи(элемент)
        }
    }

    /// .rc-top: ✕, полоски шагов с «N / M», «Начать сначала» и «Другая камера».
    private func верх(_ план: ПланСъёмки.План?, _ готово: Int) -> some View {
        let всего = план?.ключи.count ?? 0
        let естьКадрыПлана = модель.плитки.contains { !$0.слот.isEmpty }
        return HStack(spacing: 8) {
            кнопкаВерха("xmark", подпись: т("cam_close")) { закрыть() }
            Spacer(minLength: 4)
            if всего > 0 {
                шаги(всего, готово)
            }
            Spacer(minLength: 4)
            if естьКадрыПлана {
                кнопкаВерха("arrow.counterclockwise", подпись: т("cam_reset")) { спроситьСначала() }
            }
            if камера.естьПередняя && камера.доступ == .есть {
                кнопкаВерха("arrow.triangle.2.circlepath.camera", подпись: т("cam_flip")) { камера.переключитьКамеру() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private func кнопкаВерха(_ значок: String, подпись: String, _ действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Image(systemName: значок)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(Color.white.opacity(0.13), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .accessibilityLabel(подпись)
    }

    /// .rc-step: полоски (снятые — белые) и «N / M».
    private func шаги(_ всего: Int, _ готово: Int) -> some View {
        let ширина: CGFloat = всего > 6 ? 9 : 14
        let сейчас = min(готово + 1, всего)
        return HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<всего, id: \.self) { i in
                    Capsule()
                        .fill(i < готово ? Color.white : Color.white.opacity(0.3))
                        .frame(width: ширина, height: 3)
                }
            }
            Text(String(сейчас) + " / " + String(всего))
                .font(.subheadline.weight(.heavy).monospacedDigit())
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Color.white.opacity(0.13), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: т("step_of"), сейчас, всего))
    }

    /// .rc-view: превью, виньетка, уголки рамки, подсказка кадра, фонарик, плашка, вспышка затвора.
    private func видоискательВид(_ план: ПланСъёмки.План?, _ номер: Int?, _ готово: Int) -> some View {
        let пропорция = ПланСъёмки.пропорция(план?.группа ?? "")
        return GeometryReader { гео in
            let рамка = ВырезкаКадраПлана.рамка(в: гео.size, пропорция: пропорция)
            ZStack {
                фонВидоискателя
                if живая {
                    виньетка(гео.size)
                    УголкиПоискаФото(длина: 28, цвет: Color.white.opacity(0.5), толщина: 2.5)
                        .frame(width: рамка.width, height: рамка.height)
                        .position(x: рамка.midX, y: рамка.midY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                подсказка(план, номер, готово)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                верхВидоискателя
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                Color.white
                    .opacity(вспышка ? 0.9 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(width: гео.size.width, height: гео.size.height)
            .onAppear { видоискатель = гео.size }
            .onChange(of: гео.size) { _, новый in видоискатель = новый }
        }
        .clipped()
    }

    @ViewBuilder
    private var фонВидоискателя: some View {
        switch камера.доступ {
        case .есть, .неизвестно:
            ПревьюКамерыПоиска(камера: камера)
                .opacity(камера.готова ? 1 : 0)
                .animation(ДвижениеСайта.появление, value: камера.готова)
                .accessibilityHidden(true)
        case .запрещён:
            заглушка(заголовок: т("cam_denied"), текст: т("cam_denied_s"), настройки: true)
        case .нетКамеры:
            заглушка(заголовок: т("cam_no_cam"), текст: т("cam_no_cam_s"), настройки: false)
        }
    }

    /// .rc-view::after — затемнение к краям, чтобы рамка и подсказка читались на любом кадре.
    private func виньетка(_ размер: CGSize) -> some View {
        RadialGradient(gradient: Gradient(stops: [.init(color: .clear, location: 0.54),
                                                  .init(color: Color.black.opacity(0.5), location: 1)]),
                       center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0,
                       endRadius: max(размер.width, размер.height) * 0.72)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Плашка (toast внутри камеры) по центру и фонарик справа — поверх превью сверху; плашка фонарик не закрывает.
    private var верхВидоискателя: some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                if let текст = плашка {
                    Text(текст)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 52)
            if камера.фонарикЕсть && камера.доступ == .есть {
                КруглаяКнопкаФото(значок: камера.фонарик ? "flashlight.on.fill" : "flashlight.off.fill",
                                  подпись: камера.фонарик ? т("cam_torch_off") : т("cam_torch_on"),
                                  активна: камера.фонарик) { камера.переключитьФонарик() }
            }
        }
        .padding(12)
    }

    /// .rc-hint: значок и «ШАГ N ИЗ M», крупно — что снять, под ним — совет плана; план закрыт — «Всё снято».
    private func подсказка(_ план: ПланСъёмки.План?, _ номер: Int?, _ готово: Int) -> some View {
        let всего = план?.ключи.count ?? 0
        let идёт = номер != nil
        let надпись = идёт ? String(format: т("step_of"), min(готово + 1, всего), всего) : т("cam_plan_ok")
        let заголовок = идёт ? подпись(план, номер) : т("cam_plan_done")
        let совет = идёт ? (план?.совет ?? "") : т("cam_plan_done_s")
        let значок = идёт ? ПланСъёмки.значок(ключ(план, номер)) : "checkmark.circle.fill"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: значок)
                    .font(.system(size: 12, weight: .bold))
                    .accessibilityHidden(true)
                Text(надпись.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(0.6)
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .padding(.leading, 9)
            .padding(.trailing, 12)
            .frame(height: 26)
            .background(Color.black.opacity(0.55), in: Capsule())
            Text(заголовок)
                .font(.title2.weight(.heavy))
                .foregroundStyle(Color.white)
                .shadow(color: Color.black.opacity(0.55), radius: 5, y: 2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !совет.isEmpty {
                Text(совет)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.8))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .padding(.bottom, 16)
        .background {
            LinearGradient(stops: [.init(color: Color.black.opacity(0), location: 0),
                                   .init(color: Color.black.opacity(0.82), location: 0.7)],
                           startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
        .animation(ДвижениеСайта.смена, value: заголовок)
        .accessibilityElement(children: .combine)
    }

    /// Нет доступа или камеры: объяснение и «Открыть Настройки»; галерея — плиткой внизу.
    private func заглушка(заголовок: String, текст: String, настройки: Bool) -> some View {
        VStack(spacing: 0) {
            Image(systemName: "camera.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.зелёныйЯркий)
                .frame(width: 64, height: 64)
                .background(Color.white.opacity(0.1), in: Circle())
                .padding(.bottom, 14)
                .accessibilityHidden(true)
            Text(заголовок)
                .font(.title3.weight(.heavy))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
            Text(текст)
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 16)
            if настройки {
                ЗелёнаяКнопкаФото(заголовок: т("cam_settings"), значок: "gearshape", контурная: true, наТёмном: true) {
                    if let адрес = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(адрес)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .frame(maxWidth: 460)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Низ

    /// .rc-bot: галерея, лента, счёт; под ними — действия, вопрос или проверка кадра.
    private func низ(_ план: ПланСъёмки.План?, _ номер: Int?, _ готово: Int, _ осталось: Int) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                галерея
                лента(план)
                счёт(план, готово, осталось)
            }
            .frame(minHeight: 58)
            if let в = вопрос {
                панельВопроса(в)
            } else if let п = проверка {
                панельПроверки(п)
            } else {
                действия(план, номер)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(Color.black)
        .animation(ДвижениеСайта.смена, value: вопрос)
        .animation(ДвижениеСайта.смена, value: проверка)
    }

    /// .rc-gal: последний кадр (свой или плёнки), значок галереи в углу; места нет — «Можно до N фото».
    @ViewBuilder
    private var галерея: some View {
        if модель.местоФото > 0 {
            PhotosPicker(selection: $выбор, maxSelectionCount: 1, matching: .images) {
                плиткаГалереи
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
            .accessibilityLabel(т("cam_gallery"))
        } else {
            Button { сказать(лимитТекст) } label: {
                плиткаГалереи
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
            .accessibilityLabel(т("cam_gallery"))
        }
    }

    private var картинкаГалереи: UIImage? {
        if let id = последний, let превью = модель.плитки.first(where: { $0.id == id })?.превью { return превью }
        return плёнка
    }

    private var плиткаГалереи: some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        return ZStack(alignment: .bottomTrailing) {
            if let кадр = картинкаГалереи {
                Color.clear
                    .overlay {
                        Image(uiImage: кадр)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.8), radius: 2)
                    .padding(4)
            } else {
                Color.white.opacity(0.13)
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(форма)
        .overlay { форма.strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5) }
        .contentShape(форма)
    }

    /// .rc-strip: все фото формы, последний снятый — на виду; тап по кадру плана — «Переснять?».
    private func лента(_ план: ПланСъёмки.План?) -> some View {
        ScrollViewReader { прокрутка in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if модель.плитки.isEmpty {
                        Text(т("cam_none"))
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.42))
                            .lineLimit(2)
                    }
                    ForEach(модель.плитки) { плитка in
                        миниатюра(плитка, план)
                            .id(плитка.id)
                    }
                }
                .padding(.vertical, 2)
            }
            .onChange(of: модель.плитки.count) { _, _ in
                guard let цель = последний ?? модель.плитки.last?.id else { return }
                withAnimation(ДвижениеСайта.прокрутка) { прокрутка.scrollTo(цель, anchor: .trailing) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func миниатюра(_ плитка: ПлиткаФото, _ план: ПланСъёмки.План?) -> some View {
        let форма = RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
        let подписьКадра = подписьМеста(план, плитка.слот)
        let можноПереснять = !плитка.слот.isEmpty
        return Button {
            guard можноПереснять else { return }
            вопрос = .переснять(плитка.слот, подписьКадра)
        } label: {
            ZStack {
                картинкаМиниатюры(плитка)
                if плитка.грузится && плитка.превью == nil {
                    ProgressView()
                        .tint(Color.white)
                        .controlSize(.small)
                } else if плитка.ошибка != nil {
                    Color.black.opacity(0.45)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.yellow)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(форма)
            .overlay { форма.strokeBorder(Color.white.opacity(0.24), lineWidth: 1.5) }
            .contentShape(форма)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.92))
        .accessibilityLabel(подписьКадра)
        .accessibilityHint(можноПереснять ? т("cam_retake_hint") : "")
    }

    @ViewBuilder
    private func картинкаМиниатюры(_ плитка: ПлиткаФото) -> some View {
        if let превью = плитка.превью {
            Color.clear
                .overlay {
                    Image(uiImage: превью)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else if let адрес = Config.url(плитка.url) {
            Color.clear
                .overlay {
                    AsyncImage(url: адрес) { фаза in
                        if let изображение = фаза.image {
                            изображение.resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.1)
                        }
                    }
                }
                .clipped()
        } else {
            Color.white.opacity(0.1)
        }
    }

    /// #rc-count: «2 / 5» крупно и «осталось 3» (или «план закрыт»).
    private func счёт(_ план: ПланСъёмки.План?, _ готово: Int, _ осталось: Int) -> some View {
        let всего = план?.ключи.count ?? 0
        let ниже = осталось > 0 ? String(format: т("cam_left"), осталось) : т("cam_plan_ok").lowercased()
        return VStack(alignment: .trailing, spacing: 1) {
            Text(String(готово) + " / " + String(всего))
                .font(.headline.weight(.heavy).monospacedDigit())
                .foregroundStyle(Color.white)
            Text(ниже)
                .font(.caption.weight(.heavy))
                .foregroundStyle(Color.white.opacity(0.82))
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    /// .rc-actions: «Пропустить» · затвор · «Готово»; план закрыт — «Пропустить» нет, «Готово» — белая кнопка.
    private func действия(_ план: ПланСъёмки.План?, _ номер: Int?) -> some View {
        let закрыт = номер == nil
        return HStack(spacing: 12) {
            Button {
                пропустить(план, номер)
            } label: {
                Text(т("cam_skip"))
                    .font(.body.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.96))
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(закрыт ? 0 : 1)
            .disabled(закрыт)
            .accessibilityHidden(закрыт)
            затвор(закрыт)
            Button { закрыть() } label: {
                Text(т("cam_done"))
                    .font(.body.weight(.bold))
                    .foregroundStyle(закрыт ? Color(uiColor: Theme.hex(0x0F5132)) : Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.vertical, 12)
                    .padding(.horizontal, закрыт ? 20 : 6)
                    .background(закрыт ? Color.white : Color.clear, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(НажатиеКнопкиФото(сжатие: 0.96))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// .rc-shoot: белое кольцо и круг; план закрыт — приглушён (снимать сверх плана можно); во время снимка — зелёный.
    private func затвор(_ закрыт: Bool) -> some View {
        let можно = камера.готова && !камера.снимаем && камера.доступ == .есть
        return Button { снять() } label: {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(закрыт ? 0.4 : 1), lineWidth: 3)
                    .frame(width: 74, height: 74)
                Circle()
                    .fill(камера.снимаем ? Theme.зелёныйЯркий : Color.white.opacity(закрыт ? 0.5 : 1))
                    .frame(width: 58, height: 58)
            }
            .contentShape(Circle())
            .opacity(можно || камера.снимаем ? 1 : 0.4)
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.9))
        .disabled(!можно)
        .accessibilityLabel(т("cam_shoot"))
    }

    /// .rc-confirm: вопрос и две кнопки прямо в камере.
    private func панельВопроса(_ в: ВопросСъёмкиПоПлану) -> some View {
        let текст: String
        let да: String
        switch в {
        case .сначала(let сколько):
            текст = String(format: т("cam_reset_ask"), сколько)
            да = т("cam_reset_go")
        case .переснять(_, let подписьКадра):
            текст = String(format: т("cam_retake_ask"), подписьКадра)
            да = т("cam_retake_go")
        }
        return VStack(spacing: 12) {
            Text(текст)
                .font(.body.weight(.bold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                кнопкаПанели(т("cancel"), фон: Color.white.opacity(0.15), цвет: Color.white) { вопрос = nil }
                кнопкаПанели(да, фон: Color(uiColor: Theme.hex(0xE5484D)), цвет: Color.white) { ответить(в) }
            }
        }
        .transition(.opacity)
    }

    /// .rc-check: «Смотрю, читается ли текст · Секунду», потом «Прочиталось … Верно, дальше / Переснять».
    private func панельПроверки(_ п: ПроверкаСъёмкиПоПлану) -> some View {
        let надпись: String
        let строка: String
        if !п.пришла {
            надпись = п.подпись
            строка = т("cam_ck_wait")
        } else if п.хорошо {
            надпись = т("cam_ck_read")
            строка = п.текст.isEmpty ? т("cam_ck_none") : п.текст
        } else {
            надпись = т("cam_ck_bad")
            строка = п.почему.isEmpty ? т("cam_ck_none") : п.почему
        }
        return VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text(надпись.uppercased())
                    .font(.caption.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
                Text(строка)
                    .font(п.пришла ? Font.body.weight(.bold) : Font.subheadline)
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .accessibilityElement(children: .combine)
            if п.пришла {
                HStack(spacing: 10) {
                    кнопкаПанели(т("cam_ck_retake"), фон: Color.white.opacity(0.15), цвет: Color.white) {
                        переснятьПроверенный(п.ключ)
                    }
                    кнопкаПанели(п.хорошо ? т("cam_ck_ok") : т("cam_ck_keep"), фон: Color.white,
                                 цвет: Color(uiColor: Theme.hex(0x0F5132))) {
                        проверка = nil
                        объявитьСледующий()
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color.white)
                    Text(т("cam_ck_sec"))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
        }
        .transition(.opacity)
    }

    private func кнопкаПанели(_ подпись: String, фон: Color, цвет: Color,
                              _ действие: @escaping () -> Void) -> some View {
        Button(action: действие) {
            Text(подпись)
                .font(.body.weight(.heavy))
                .foregroundStyle(цвет)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(фон, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеКнопкиФото(сжатие: 0.97))
    }

    // MARK: Действия

    /// Плашка внутри камеры (toast сайта) — сама гаснет; VoiceOver читает сразу.
    private func сказать(_ текст: String) {
        withAnimation(ДвижениеСайта.появление) { плашка = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard плашка == текст else { return }
            withAnimation(ДвижениеСайта.уход) { плашка = nil }
        }
    }

    /// Следующий кадр — голосом (у сайта подпись видна на экране; незрячему её нужно услышать).
    private func объявитьСледующий() {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let план = модель.планСъёмки
        if let номер = текущий(план, модель.снятыеМеста) {
            UIAccessibility.post(notification: .announcement,
                                 argument: String(format: т("cam_next"), подпись(план, номер)))
        } else if план != nil {
            UIAccessibility.post(notification: .announcement, argument: т("cam_plan_full"))
        }
    }

    /// rshCamShoot: затвор — снимок — вырезка по рамке — та же загрузка, что у галереи, с местом плана.
    private func снять() {
        guard модель.местоФото > 0 else {
            сказать(лимитТекст)
            return
        }
        let план = модель.планСъёмки
        let номер = текущий(план, модель.снятыеМеста)
        let место = ключ(план, номер)
        let подписьRu = подписьПоРусски(план, номер)
        let подписьКадра = подпись(план, номер)
        let пропорция = ПланСъёмки.пропорция(план?.группа ?? "")
        let вид = видоискатель
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if !тихо {
            вспышка = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)
                withAnimation(.easeOut(duration: 0.3)) { вспышка = false }
            }
        }
        камера.снять { снимок in
            принять(снимок, место: место, подписьRu: подписьRu, подпись: подписьКадра, пропорция: пропорция, вид: вид)
        }
    }

    private func принять(_ снимок: UIImage, место: String, подписьRu: String, подпись подписьКадра: String,
                         пропорция: CGFloat, вид: CGSize) {
        guard модель.местоФото > 0 else {
            сказать(лимитТекст)
            return
        }
        /* Место могли занять, пока шёл снимок (галерея) — тогда кадр ложится вне плана, а не вторым в то же место. */
        let слот = (место.isEmpty || модель.плиткаМеста(место) != nil) ? "" : место
        guard let id = модель.поставитьПлитки(1, слот: слот).first else { return }
        последний = id
        if !слот.isEmpty && закреплён == слот { закреплён = "" }
        let рамка = ВырезкаКадраПлана.рамка(в: вид, пропорция: пропорция)
        let пиксели = CGSize(width: снимок.size.width * снимок.scale, height: снимок.size.height * снимок.scale)
        let вырезка = ВырезкаКадраПлана.часть(снимок: пиксели, вид: вид, рамка: рамка, пропорция: пропорция)
        Task { @MainActor in
            let данные: Data? = await Task.detached(priority: .userInitiated) { () -> Data? in
                if let вырезка {
                    return ВырезкаКадраПлана.jpeg(снимок, часть: вырезка.часть, размер: вырезка.размер)
                }
                return снимок.jpegData(compressionQuality: 0.92)
            }.value
            guard let данные else {
                модель.удалитьФото(id)
                сказать(т("cam_fail"))
                return
            }
            await модель.обработатьИЗагрузить([данные], [id])
        }
        послеКадра(слот, подписьRu: подписьRu, подпись: подписьКадра)
    }

    /// Кадр лёг на место: текст решает — проверка (_rcCheckStart), иначе — следующий кадр голосом.
    private func послеКадра(_ слот: String, подписьRu: String, подпись подписьКадра: String) {
        if !слот.isEmpty, ПланСъёмки.читаемые.contains(слот), модель.проверкаКадровДоступна {
            начатьПроверку(слот, подписьRu: подписьRu, подпись: подписьКадра)
        } else {
            объявитьСледующий()
        }
    }

    /// rshCamGallery: кадр из галереи — на ТЕКУЩЕЕ место плана, тем же путём загрузки (без вырезки — как у сайта).
    private func взятьИзГалереи(_ элемент: PhotosPickerItem) {
        let план = модель.планСъёмки
        let номер = текущий(план, модель.снятыеМеста)
        let место = ключ(план, номер)
        let подписьRu = подписьПоРусски(план, номер)
        let подписьКадра = подпись(план, номер)
        Task { @MainActor in
            guard модель.местоФото > 0 else {
                сказать(лимитТекст)
                return
            }
            guard let файл = try? await элемент.loadTransferable(type: Data.self) else {
                сказать(т("cam_fail"))
                return
            }
            guard файл.count <= ОбработкаФото.предел else {
                сказать(ПодачаText.т("ph_big"))
                return
            }
            guard модель.местоФото > 0 else {
                сказать(лимитТекст)
                return
            }
            let слот = (место.isEmpty || модель.плиткаМеста(место) != nil) ? "" : место
            guard let id = модель.поставитьПлитки(1, слот: слот).first else { return }
            последний = id
            if !слот.isEmpty && закреплён == слот { закреплён = "" }
            послеКадра(слот, подписьRu: подписьRu, подпись: подписьКадра)
            await модель.обработатьИЗагрузить([файл], [id])
        }
    }

    /// rshCamSkip: место пропущено до конца этой съёмки.
    private func пропустить(_ план: ПланСъёмки.План?, _ номер: Int?) {
        let место = ключ(план, номер)
        guard !место.isEmpty else { return }
        if закреплён == место { закреплён = "" }
        if !пропущенные.contains(место) { пропущенные.append(место) }
        объявитьСледующий()
    }

    /// rshCamReset: кадров плана нет — просто снимаем пропуски; есть — спрашиваем (удаление не отменить).
    private func спроситьСначала() {
        let сколько = модель.плитки.filter { !$0.слот.isEmpty }.count
        guard сколько > 0 else {
            пропущенные = []
            закреплён = ""
            return
        }
        проверка = nil
        вопрос = .сначала(сколько)
    }

    private func ответить(_ в: ВопросСъёмкиПоПлану) {
        вопрос = nil
        switch в {
        case .сначала:
            модель.удалитьКадрыПлана()
            пропущенные = []
            закреплён = ""
            проверка = nil
            сказать(т("cam_reset_done"))
        case .переснять(let место, _):
            if проверка?.ключ == место { проверка = nil }
            модель.освободитьМестоПлана(место)
            пропущенные.removeAll { $0 == место }
            закреплён = место
            объявитьСледующий()
        }
    }

    /// rshCamRetake: забракованный кадр убираем — место снова пустое и следующее.
    private func переснятьПроверенный(_ место: String) {
        проверка = nil
        модель.освободитьМестоПлана(место)
        пропущенные.removeAll { $0 == место }
        закреплён = место
        объявитьСледующий()
    }

    /**
     _rcCheckStart / _rcCheckPoll / _rcCheckSend: ждём, пока кадр долетит до сервера (до 30 с), и спрашиваем shot_read по
     адресу файла (картинку в теле не шлём — большой POST режет WAF). Выключено, лимит, сеть — молча дальше.
     */
    private func начатьПроверку(_ место: String, подписьRu: String, подпись подписьКадра: String) {
        проверка = ПроверкаСъёмкиПоПлану(ключ: место, подпись: подписьКадра)
        Task { @MainActor in
            var адрес = ""
            for _ in 0..<60 {
                guard проверка?.ключ == место else { return }
                guard let плитка = модель.плиткаМеста(место), плитка.ошибка == nil else { break }
                if плитка.готова {
                    адрес = плитка.url
                    break
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard проверка?.ключ == место else { return }
            guard !адрес.isEmpty else {
                проверка = nil
                объявитьСледующий()
                return
            }
            let тело: [String: Any] = ["img_url": адрес, "label": подписьRu.isEmpty ? подписьКадра : подписьRu]
            let ответ = try? await МоиОбъявленияAPI.отправить("cabinet.php?action=shot_read", тело: тело)
            guard проверка?.ключ == место, проверка?.пришла == false else { return }
            guard let j = ответ, МоиОбъявленияAPI.да(j["ok"]) else {
                проверка = nil
                объявитьСледующий()
                return
            }
            var итог = ПроверкаСъёмкиПоПлану(ключ: место, подпись: подписьКадра)
            итог.хорошо = МоиОбъявленияAPI.да(j["good"])
            итог.текст = МоиОбъявленияAPI.строка(j["text"]).trimmingCharacters(in: .whitespacesAndNewlines)
            итог.почему = МоиОбъявленияAPI.строка(j["why"]).trimmingCharacters(in: .whitespacesAndNewlines)
            итог.пришла = true
            проверка = итог
            let что: String
            if итог.хорошо {
                что = итог.текст.isEmpty ? т("cam_ck_none") : итог.текст
            } else {
                что = итог.почему.isEmpty ? т("cam_ck_none") : итог.почему
            }
            let голос = (итог.хорошо ? т("cam_ck_read") : т("cam_ck_bad")) + ": " + что
            UIAccessibility.post(notification: .announcement, argument: голос)
        }
    }
}

// MARK: - Тексты (ru / kk / en / ar): подписи — как lang/*.php сайта (cam_*), своё — переведено здесь

enum СъёмкаПоПлануText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь: [String: String]
        switch язык {
        case "kk": словарь = kk
        case "en": словарь = en
        case "ar": словарь = ar
        default: словарь = ru
        }
        return словарь[ключ] ?? ru[ключ] ?? ключ
    }

    private static let ru: [String: String] = [
        "cam_close": "Закрыть", "cam_reset": "Начать сначала", "cam_flip": "Другая камера",
        "cam_gallery": "Выбрать из галереи", "cam_skip": "Пропустить", "cam_shoot": "Снять", "cam_done": "Готово",
        "cancel": "Отмена", "cam_reset_go": "Начать сначала", "step_of": "Шаг %d из %d",
        "cam_plan_ok": "План закрыт", "cam_plan_done": "Всё снято",
        "cam_plan_done_s": "Можно добавить кадры сверх плана или закончить", "cam_none": "Кадров пока нет",
        "cam_left": "осталось %d", "cam_reset_ask": "Удалить снятые кадры плана и начать сначала? (%d)",
        "cam_reset_done": "Начинаем сначала", "cam_fail": "Кадр не получился, попробуйте ещё раз",
        "cam_ck_wait": "Смотрю, читается ли текст", "cam_ck_sec": "Секунду", "cam_ck_read": "Прочиталось",
        "cam_ck_none": "Текста не видно", "cam_ck_bad": "Читается плохо", "cam_ck_retake": "Переснять",
        "cam_ck_ok": "Верно, дальше", "cam_ck_keep": "Оставить",
        "cam_retake_ask": "Переснять «%@»? Этот кадр удалится", "cam_retake_go": "Переснять",
        "cam_retake_hint": "Переснять этот кадр",
        "cam_torch_on": "Включить фонарик", "cam_torch_off": "Выключить фонарик",
        "cam_denied": "Нет доступа к камере",
        "cam_denied_s": "Разрешите доступ к камере в Настройках — или выберите кадр из галереи кнопкой внизу",
        "cam_no_cam": "Камера недоступна",
        "cam_no_cam_s": "Выберите кадр из галереи кнопкой внизу — он ляжет на своё место в плане",
        "cam_settings": "Открыть Настройки", "cam_next": "Следующий кадр: %@", "cam_plan_full": "План снят полностью",
        "cam_extra": "Доп. фото", "step_btn": "Снять по шагам",
        "step_btn_s": "Камера подскажет каждый кадр — снимаете подряд",
        "chip_hint": "Откроет камеру на этом кадре"
    ]

    private static let kk: [String: String] = [
        "cam_close": "Жабу", "cam_reset": "Қайтадан бастау", "cam_flip": "Басқа камера",
        "cam_gallery": "Галереядан таңдау", "cam_skip": "Өткізіп жіберу", "cam_shoot": "Түсіру", "cam_done": "Дайын",
        "cancel": "Бас тарту", "cam_reset_go": "Қайтадан бастау", "step_of": "Қадам %d / %d",
        "cam_plan_ok": "Жоспар жабылды", "cam_plan_done": "Барлығы түсірілді",
        "cam_plan_done_s": "Жоспардан тыс кадр қосуға немесе аяқтауға болады", "cam_none": "Әзірге кадр жоқ",
        "cam_left": "%d қалды", "cam_reset_ask": "Түсірілген кадрларды жойып, қайтадан бастау керек пе? (%d)",
        "cam_reset_done": "Қайтадан бастаймыз", "cam_fail": "Кадр шықпады, қайталап көріңіз",
        "cam_ck_wait": "Мәтіннің оқылатынын тексеріп жатырмын", "cam_ck_sec": "Бір сәт", "cam_ck_read": "Оқылды",
        "cam_ck_none": "Мәтін көрінбейді", "cam_ck_bad": "Нашар оқылады", "cam_ck_retake": "Қайта түсіру",
        "cam_ck_ok": "Дұрыс, әрі қарай", "cam_ck_keep": "Қалдыру",
        "cam_retake_ask": "«%@» қайта түсіру керек пе? Бұл кадр жойылады", "cam_retake_go": "Қайта түсіру",
        "cam_retake_hint": "Бұл кадрды қайта түсіру",
        "cam_torch_on": "Шамды қосу", "cam_torch_off": "Шамды өшіру",
        "cam_denied": "Камераға рұқсат жоқ",
        "cam_denied_s": "Баптауларда камераға рұқсат беріңіз — немесе төмендегі батырмамен галереядан кадр таңдаңыз",
        "cam_no_cam": "Камера қолжетімсіз",
        "cam_no_cam_s": "Төмендегі батырмамен галереядан кадр таңдаңыз — ол жоспардағы өз орнына түседі",
        "cam_settings": "Баптауларды ашу", "cam_next": "Келесі кадр: %@", "cam_plan_full": "Жоспар толық түсірілді",
        "cam_extra": "Қосымша фото", "step_btn": "Қадаммен түсіру",
        "step_btn_s": "Камера әр кадрды айтып отырады — қатарынан түсіресіз",
        "chip_hint": "Камераны осы кадрда ашады"
    ]

    private static let en: [String: String] = [
        "cam_close": "Close", "cam_reset": "Start over", "cam_flip": "Switch camera",
        "cam_gallery": "Choose from gallery", "cam_skip": "Skip", "cam_shoot": "Take a photo", "cam_done": "Done",
        "cancel": "Cancel", "cam_reset_go": "Start over", "step_of": "Step %d of %d",
        "cam_plan_ok": "Shot list complete", "cam_plan_done": "All shots taken",
        "cam_plan_done_s": "You can add extra shots or finish", "cam_none": "No shots yet",
        "cam_left": "%d left", "cam_reset_ask": "Delete the shots taken and start over? (%d)",
        "cam_reset_done": "Starting over", "cam_fail": "The shot did not work, try again",
        "cam_ck_wait": "Checking whether the text is readable", "cam_ck_sec": "One moment", "cam_ck_read": "Recognised",
        "cam_ck_none": "No text visible", "cam_ck_bad": "Hard to read", "cam_ck_retake": "Retake",
        "cam_ck_ok": "Correct, continue", "cam_ck_keep": "Keep",
        "cam_retake_ask": "Retake “%@”? This shot will be deleted", "cam_retake_go": "Retake",
        "cam_retake_hint": "Retake this shot",
        "cam_torch_on": "Turn on flashlight", "cam_torch_off": "Turn off flashlight",
        "cam_denied": "No camera access",
        "cam_denied_s": "Allow camera access in Settings — or pick a shot from your gallery with the button below",
        "cam_no_cam": "Camera unavailable",
        "cam_no_cam_s": "Pick a shot from your gallery with the button below — it goes to its place in the plan",
        "cam_settings": "Open Settings", "cam_next": "Next shot: %@", "cam_plan_full": "The plan is fully shot",
        "cam_extra": "Extra photo", "step_btn": "Shoot step by step",
        "step_btn_s": "The camera prompts every shot — just shoot one after another",
        "chip_hint": "Opens the camera on this shot"
    ]

    private static let ar: [String: String] = [
        "cam_close": "إغلاق", "cam_reset": "البدء من جديد", "cam_flip": "كاميرا أخرى",
        "cam_gallery": "اختيار من المعرض", "cam_skip": "تخطٍ", "cam_shoot": "التقاط صورة", "cam_done": "تم",
        "cancel": "إلغاء", "cam_reset_go": "البدء من جديد", "step_of": "خطوة %d من %d",
        "cam_plan_ok": "اكتملت قائمة اللقطات", "cam_plan_done": "تم تصوير كل اللقطات",
        "cam_plan_done_s": "يمكنك إضافة لقطات إضافية أو الإنهاء", "cam_none": "لا توجد لقطات بعد",
        "cam_left": "متبقٍ %d", "cam_reset_ask": "حذف اللقطات والبدء من جديد؟ (%d)",
        "cam_reset_done": "نبدأ من جديد", "cam_fail": "لم تنجح اللقطة، حاول مرة أخرى",
        "cam_ck_wait": "أتحقق مما إذا كان النص مقروءًا", "cam_ck_sec": "لحظة", "cam_ck_read": "تمت القراءة",
        "cam_ck_none": "لا يظهر نص", "cam_ck_bad": "صعب القراءة", "cam_ck_retake": "إعادة التصوير",
        "cam_ck_ok": "صحيح، تابع", "cam_ck_keep": "إبقاء",
        "cam_retake_ask": "إعادة تصوير «%@»؟ ستُحذف هذه اللقطة", "cam_retake_go": "إعادة التصوير",
        "cam_retake_hint": "إعادة تصوير هذه اللقطة",
        "cam_torch_on": "تشغيل المصباح", "cam_torch_off": "إطفاء المصباح",
        "cam_denied": "لا يوجد وصول إلى الكاميرا",
        "cam_denied_s": "اسمح بالوصول إلى الكاميرا من الإعدادات — أو اختر لقطة من المعرض بالزر في الأسفل",
        "cam_no_cam": "الكاميرا غير متاحة",
        "cam_no_cam_s": "اختر لقطة من المعرض بالزر في الأسفل — ستوضع في مكانها في الخطة",
        "cam_settings": "فتح الإعدادات", "cam_next": "اللقطة التالية: %@", "cam_plan_full": "اكتملت خطة التصوير",
        "cam_extra": "صورة إضافية", "step_btn": "التصوير خطوة بخطوة",
        "step_btn_s": "ستخبرك الكاميرا بكل لقطة — صوّر واحدة تلو الأخرى",
        "chip_hint": "يفتح الكاميرا على هذه اللقطة"
    ]
}

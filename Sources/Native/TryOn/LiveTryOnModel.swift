import SwiftUI
import UIKit

/**
 ЖИВАЯ ПРИМЕРКА — СОСТОЯНИЕ ЭКРАНА (одно на открытый экран, не синглтон; держит его ЭкранЖивойПримерки).

 Два этапа (владелец 14.10.2026: «через студию для примерочной должен обрезаться»): сначала «Вещь» — фото вещи (тот же
 кэш, что у ленты) прямо и вырезка студии один раз в фоне (ВырезкаЖивойПримерки → ВырезкаПредмета), выбор фото
 объявления и «Обрезать вручную» (рамка по фото — вырезка внутри неё); камера в это время не работает. «Примерить» —
 камера, анализ кадров и слежение, как было; «Фото вещи» у камеры — обратно к «Вещи» (камера стоит). Вырезки помнятся до
 закрытия экрана, по номеру фото: автоматические и ручные отдельно («Автоматически» возвращает студийную).

 Ручная подгонка (щипок, поворот, сдвиг) — на сеанс, и для другого фото вещи тоже. Снимок — следующий кадр камеры с
 вещью поверх (собирается не на главной нити), дальше — «Сохранить в Фото» и «Поделиться». Пока на экране снимок, камера
 и анализ стоят (на снимке можно сидеть долго — сохранить, поделиться); закрыли снимок — камера снова идёт. Камеру
 прервали (звонок, другое приложение, Split View на iPad) — вещь гаснет, подсказка «Камера на паузе».
 */
@MainActor
final class МодельЖивойПримерки: ObservableObject {
    enum СостояниеВещи: Equatable {
        case грузим
        case готово
        /// Не вышло: текст и можно ли повторить то же фото (сеть).
        case неВышло(String, повторить: Bool)
    }

    /// Этап экрана: «Вещь» (вырезка, фото, ручная рамка; камера стоит) или сама примерка в камере.
    enum Этап: Equatable {
        case вещь
        case примерка
    }

    /// Готовая вырезка фото: вещи и где вещь на фото (доли, начало сверху слева).
    private struct Готовое {
        let вещи: [UIImage]
        let рамка: CGRect?
    }

    let товар: Listing
    let вид: ВидЖивойПримерки
    let камера = КамераЖивойПримерки()
    let слежение: СлежениеЖивойПримерки
    let анализ: АнализЖивойПримерки

    @Published private(set) var этап: Этап = .вещь
    @Published private(set) var номерФото: Int
    @Published private(set) var вещь: СостояниеВещи = .грузим
    /// Вырезки текущего фото: одна, у серёг — две (левая и правая).
    @Published private(set) var вырезки: [UIImage] = []
    /// Текущее фото вещи прямо, не больше 1024 px: под линией сканирования и в рамке «Обрезать вручную».
    @Published private(set) var исходник: UIImage? = nil
    /// Вырезка текущего фото — по ручной рамке.
    @Published private(set) var ручная = false
    /// Где вещь на текущем фото (доли, начало сверху слева): с неё начинается ручная рамка; nil — не знаем.
    @Published private(set) var рамкаВещи: CGRect? = nil
    /// Фото, с которых вещь не вырезалась, — помечены в полосе миниатюр.
    @Published private(set) var неПодошли: Set<Int> = []
    @Published private(set) var состояние: СостояниеСлеженияЖивой = .ищем
    @Published private(set) var подгонка = ПодгонкаЖивойПримерки()
    @Published private(set) var советЖестов = false
    @Published private(set) var снимок: UIImage? = nil
    @Published private(set) var снимаем = false
    @Published private(set) var сохраняем = false
    /// Короткая весть внизу экрана («Сохранено в Фото»).
    @Published private(set) var весть: String? = nil
    /// Камеру прервала система: кадры не идут.
    @Published private(set) var пауза = false

    private var кэш: [Int: Готовое] = [:]
    private var ручные: [Int: Готовое] = [:]
    /// Прямой кадр текущего фото (тот же, что исходник) — для вырезки; его номер фото.
    private var кадр: КадрСтудииФото? = nil
    private var номерКадра = -1
    private var загрузка: Task<Void, Never>? = nil
    private var закрыто = false
    private var вФоне = false
    private var номерВести = 0
    private var номерСнимка = 0
    private var снимокДанные: Data? = nil
    private var советПоказан = false
    private var последнееОбъявление = Date.distantPast
    private var приветствие = false

    init(товар: Listing, вид: ВидЖивойПримерки, фото: Int) {
        self.товар = товар
        self.вид = вид
        let всего = товар.фотоАдреса.count
        self.номерФото = всего > 0 ? min(max(0, фото), всего - 1) : 0
        let слежение = СлежениеЖивойПримерки(вид: вид, мм: ВидЖивойПримерки.размерМм(товар, вид: вид))
        self.слежение = слежение
        self.анализ = АнализЖивойПримерки(наГлавную: { [weak слежение] наблюдение in
            слежение?.принять(наблюдение)
        })
        слежение.приСмене = { [weak self] новое in self?.сменилосьСлежение(новое) }
        камера.приПрерывании = { [weak self] прервана in self?.прерваласьКамера(прервана) }
        камера.подключить(анализ)
    }

    private func т(_ ключ: String) -> String { ЖиваяПримеркаText.т(ключ) }

    // MARK: - Открыли, закрыли, фон

    func открыт() {
        guard !закрыто else { return }
        запуститьКамеру()
        if вырезки.isEmpty && исходник == nil { загрузитьВещь() }
    }

    /// «Примерить»: вещь готова — камера, анализ и слежение. Первый раз — весть, что видео никуда не уходит.
    func кПримерке() {
        guard !закрыто, этап == .вещь, вещь == .готово, !вырезки.isEmpty else { return }
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.шаг) { этап = .примерка }
        запуститьКамеру()
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        guard !приветствие else { return }
        приветствие = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, !self.закрыто, self.этап == .примерка else { return }
            self.показатьВесть(self.т("lt_privacy"))
        }
    }

    /// «Фото вещи» у камеры: обратно к «Вещи» — камера и анализ стоят, подгонка сеанса остаётся.
    func кВещи() {
        guard !закрыто, этап == .примерка, снимок == nil, !снимаем else { return }
        ОткликСайта.выбор()
        анализ.выключить()
        камера.остановить()
        слежение.сброс()
        if советЖестов { советЖестов = false }
        withAnimation(ДвижениеСайта.шаг) { этап = .вещь }
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    func закрыть() {
        guard !закрыто else { return }
        закрыто = true
        загрузка?.cancel()
        анализ.выключить()
        камера.остановить()
        слежение.сброс()
    }

    func вФон() {
        guard !закрыто else { return }
        вФоне = true
        анализ.выключить()
        камера.остановить()
        слежение.сброс()
    }

    func изФона() {
        guard !закрыто, вФоне else { return }
        вФоне = false
        запуститьКамеру()
    }

    /// Камера — только на этапе примерки; под снимком она стоит — её запускает закрытьСнимок().
    private func запуститьКамеру() {
        guard этап == .примерка, снимок == nil else { return }
        камера.запустить(передней: вид.передняя)
        анализ.включить(рука: !вид.лицо)
    }

    /// Система прервала камеру (звонок, другое приложение, Split View) или прерывание кончилось.
    private func прерваласьКамера(_ прервана: Bool) {
        guard !закрыто, пауза != прервана else { return }
        withAnimation(ДвижениеСайта.смена) { пауза = прервана }
        guard прервана else { return }
        слежение.сброс()
        UIAccessibility.post(notification: .announcement, argument: т("lt_paused"))
    }

    func переключитьКамеру() {
        ОткликСайта.выбор()
        слежение.сброс()
        камера.переключить()
    }

    // MARK: - Вещь

    /// Миниатюра фото объявления на шаге «Вещь». То же фото: не вышло по сети — ещё раз, иначе ничего.
    func выбратьФото(_ номер: Int) {
        guard товар.фотоАдреса.indices.contains(номер), этап == .вещь else { return }
        if номер == номерФото {
            if case .неВышло(_, повторить: true) = вещь { загрузитьВещь() }
            return
        }
        ОткликСайта.выбор()
        номерФото = номер
        загрузитьВещь()
    }

    /// То же фото ещё раз (не загрузилось по сети).
    func повторить() {
        загрузитьВещь()
    }

    /// «Обрезать» в ручной рамке (доли фото, начало сверху слева): вырезка внутри неё; вещь будет в любом случае.
    func обрезатьВручную(_ рамка: CGRect) {
        guard !закрыто, этап == .вещь, кадр != nil, номерКадра == номерФото else { return }
        let единица = рамка.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !единица.isNull, единица.width >= 0.02, единица.height >= 0.02 else { return }
        let номер = номерФото
        загрузка?.cancel()
        вырезки = []
        withAnimation(ДвижениеСайта.смена) { вещь = .грузим }
        UIAccessibility.post(notification: .announcement, argument: т("lt_preparing"))
        загрузка = Task { @MainActor [weak self] in
            await self?.вырезать(номер: номер, рамка: единица)
        }
    }

    /// «Автоматически»: ручная рамка этого фото забыта — снова вырезка студии по всему фото.
    func автоВырезка() {
        guard !закрыто, этап == .вещь, ручные[номерФото] != nil else { return }
        ОткликСайта.выбор()
        ручные[номерФото] = nil
        загрузитьВещь()
    }

    /**
     Фото номерФото: готовая вырезка (ручная, иначе автоматическая) — сразу; прямой кадр — из кэша ленты и Task.detached
     (нужен линии сканирования и ручной рамке); вырезки нет — вырезка студии по всему фото.
     */
    private func загрузитьВещь() {
        let номер = номерФото
        let адреса = товар.фотоАдреса
        guard адреса.indices.contains(номер) else { return }
        let адрес = адреса[номер]
        let готовое = ручные[номер] ?? кэш[номер]
        загрузка?.cancel()
        ручная = ручные[номер] != nil
        рамкаВещи = готовое?.рамка
        if номерКадра != номер {
            кадр = nil
            номерКадра = -1
            исходник = nil
        }
        if let готовое {
            вырезки = готовое.вещи
            withAnimation(ДвижениеСайта.смена) { вещь = .готово }
        } else {
            вырезки = []
            withAnimation(ДвижениеСайта.смена) { вещь = .грузим }
        }
        let нуженКадр = номерКадра != номер || кадр == nil
        let нужнаВырезка = готовое == nil
        guard нуженКадр || нужнаВырезка else { return }
        загрузка = Task { @MainActor [weak self] in
            if нуженКадр {
                let картинка = await КартинкиЛенты.shared.загрузить(адрес, пикселей: 1024, заполнить: false)
                guard let self, !Task.isCancelled, !self.закрыто, self.номерФото == номер else { return }
                guard let картинка else {
                    if нужнаВырезка { self.неВышло(номер, текст: self.т("lt_cut_load"), повторить: true) }
                    return
                }
                let ящик = await Task.detached(priority: .userInitiated) { () -> КадрСтудииФото in
                    КадрСтудииФото(картинка: ВырезкаЖивойПримерки.кадр(картинка))
                }.value
                guard !Task.isCancelled, !self.закрыто, self.номерФото == номер else { return }
                guard let прямой = ящик.картинка else {
                    if нужнаВырезка { self.неВышло(номер, текст: self.т("lt_cut_fail"), повторить: false) }
                    return
                }
                self.кадр = ящик
                self.номерКадра = номер
                withAnimation(ДвижениеСайта.появление) { self.исходник = UIImage(cgImage: прямой) }
            }
            guard нужнаВырезка else { return }
            await self?.вырезать(номер: номер, рамка: nil)
        }
    }

    /**
     Вырезка текущего кадра — по всему фото (рамка nil) или внутри ручной рамки — в Task.detached. Без «Уменьшения
     движения» сканирование на экране длится не меньше 1,1 с: бегущая линия успевает пройти фото, как в студии.
     */
    private func вырезать(номер: Int, рамка: CGRect?) async {
        guard let ящик = кадр, номерКадра == номер else { return }
        let пара = вид.пара
        let стоя = вид == .часы || вид == .браслет
        let тихо = ДвижениеСайта.тихо
        let начало = Date()
        /* Отмена загрузки (другое фото, закрыли экран) доходит и до вырезки: сама в detached она не передаётся. */
        let работа = Task.detached(priority: .userInitiated) { () -> ВырезкаЖивойПримерки.Итог in
            guard let картинка = ящик.картинка else { return .фон }
            return ВырезкаЖивойПримерки.вырезать(кадр: картинка, пара: пара, стоя: стоя, рамка: рамка)
        }
        let итог = await withTaskCancellationHandler {
            await работа.value
        } onCancel: {
            работа.cancel()
        }
        if !тихо {
            let прошло = Date().timeIntervalSince(начало)
            if прошло < 1.1 { try? await Task.sleep(nanoseconds: UInt64((1.1 - прошло) * 1_000_000_000)) }
        }
        guard !Task.isCancelled, !закрыто, номерФото == номер else { return }
        switch итог {
        case .готово(let вещи, let где):
            let готовое = Готовое(вещи: вещи, рамка: где)
            if рамка != nil {
                ручные[номер] = готовое
            } else {
                кэш[номер] = готовое
            }
            неПодошли.remove(номер)
            вырезки = вещи
            ручная = рамка != nil
            рамкаВещи = где
            ОткликСайта.успех()
            withAnimation(ДвижениеСайта.появление) { вещь = .готово }
            UIAccessibility.post(notification: .announcement,
                                 argument: ВещьЖивойПримеркиText.т(рамка != nil ? "lw_ready_manual" : "lw_ready"))
        case .человек:
            неВышло(номер, текст: т("lt_cut_person"), повторить: false)
        case .фон:
            неВышло(номер, текст: т("lt_cut_fail"), повторить: false)
        }
    }

    private func неВышло(_ номер: Int, текст: String, повторить: Bool) {
        if !повторить { неПодошли.insert(номер) }
        вырезки = []
        ручная = false
        ОткликСайта.предупреждение()
        withAnimation(ДвижениеСайта.появление) { вещь = .неВышло(текст, повторить: повторить) }
        UIAccessibility.post(notification: .announcement, argument: текст)
    }

    // MARK: - Слежение и подсказки

    /// Подсказка над камерой; nil — подсказки нет.
    var подсказка: String? {
        if пауза { return т("lt_paused") }
        switch вещь {
        case .грузим: return т("lt_preparing")
        case .неВышло: return nil
        case .готово: break
        }
        switch состояние {
        case .ищем: return nil
        case .нетЛица: return т("lt_look")
        case .лицоДалеко: return т("lt_face_closer")
        case .нетРуки: return т("lt_hand")
        case .есть: return советЖестов ? т("lt_tip_gestures") : nil
        }
    }

    private func сменилосьСлежение(_ новое: СостояниеСлеженияЖивой) {
        withAnimation(ДвижениеСайта.смена) { состояние = новое }
        показатьСоветЖестов()
        /* VoiceOver: о смене — не чаще раза в 2,5 с, чтобы не тараторить на каждом моргании. */
        guard UIAccessibility.isVoiceOverRunning, вещь == .готово, снимок == nil else { return }
        let сейчас = Date()
        guard сейчас.timeIntervalSince(последнееОбъявление) > 2.5 else { return }
        let текст: String?
        switch новое {
        case .есть: текст = т("lt_on_place")
        case .нетЛица: текст = т("lt_look")
        case .лицоДалеко: текст = т("lt_face_closer")
        case .нетРуки: текст = т("lt_hand")
        case .ищем: текст = nil
        }
        guard let текст else { return }
        последнееОбъявление = сейчас
        UIAccessibility.post(notification: .announcement, argument: текст)
    }

    /// Один раз за экран, когда вещь впервые встала на место: как подгонять жестами (4 с).
    private func показатьСоветЖестов() {
        guard состояние == .есть, вещь == .готово, !советПоказан else { return }
        советПоказан = true
        withAnimation(ДвижениеСайта.появление) { советЖестов = true }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self else { return }
            withAnimation(ДвижениеСайта.уход) { self.советЖестов = false }
        }
    }

    // MARK: - Ручная подгонка

    /// Жест закончился: щипок, поворот двумя пальцами и сдвиг (точки экрана) — в подгонку сеанса.
    func принятьЖест(масштаб: CGFloat, поворот: Double, сдвиг: CGSize) {
        var п = подгонка
        if сдвиг != .zero, let первое = слежение.положения.first {
            let сейчас = первое.сПодгонкой(подгонка, зеркально: false)
            let ш = max(1, сейчас.ширина)
            let a = -первое.угол
            let x = (сдвиг.width * CGFloat(cos(a)) - сдвиг.height * CGFloat(sin(a))) / ш
            let y = (сдвиг.width * CGFloat(sin(a)) + сдвиг.height * CGFloat(cos(a))) / ш
            п.сдвиг = CGSize(width: min(2.5, max(-2.5, п.сдвиг.width + x)),
                             height: min(2.5, max(-2.5, п.сдвиг.height + y)))
        }
        п.масштаб = min(3, max(0.3, п.масштаб * масштаб))
        п.поворот += поворот
        подгонка = п
        if советЖестов { withAnimation(ДвижениеСайта.уход) { советЖестов = false } }
    }

    /// VoiceOver и кнопки: крупнее/мельче на 10 %, поворот на 6°.
    func крупнее(_ да: Bool) {
        подгонка.масштаб = min(3, max(0.3, подгонка.масштаб * (да ? 1.1 : 1 / 1.1)))
    }

    func повернуть(вправо: Bool) {
        подгонка.поворот += (вправо ? 1 : -1) * Double.pi / 30
    }

    func сброситьПодгонку() {
        guard !подгонка.исходная else { return }
        ОткликСайта.выбор()
        withAnimation(ДвижениеСайта.смена) { подгонка = ПодгонкаЖивойПримерки() }
        показатьВесть(т("lt_reset_done"))
    }

    // MARK: - Снимок

    /// Следующий кадр камеры и вещь поверх — как на экране. Кадр не пришёл за 2 с — «Не получилось».
    func снять() {
        guard !снимаем, снимок == nil, вещь == .готово, камера.готова else { return }
        снимаем = true
        номерСнимка += 1
        let номер = номерСнимка
        let положения: [РасположениеВещиЖивой] = слежение.видно
            ? слежение.положения.enumerated().map { $0.element.сПодгонкой(подгонка, зеркально: вид.пара && $0.offset == 1) }
            : []
        let вещи = вырезки
        let экран = слежение.размерЭкрана
        let масштаб = min(3, 2160 / max(1, max(экран.width, экран.height)))
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        анализ.кадр { [weak self] кадр in
            guard let self, self.номерСнимка == номер, self.снимаем else { return }
            guard let кадр else {
                self.снимокНеВышел()
                return
            }
            Task { @MainActor [weak self] in
                let готовый = await Task.detached(priority: .userInitiated) { () -> СнимокЖивойПримерки.Готовый? in
                    СнимокЖивойПримерки.собрать(кадр: кадр, экран: экран, масштаб: масштаб, вещи: вещи,
                                                положения: положения)
                }.value
                guard let self, self.номерСнимка == номер, !self.закрыто else { return }
                guard let готовый else {
                    self.снимокНеВышел()
                    return
                }
                self.снимаем = false
                self.снимокДанные = готовый.jpeg
                self.анализ.выключить()
                self.камера.остановить()
                withAnimation(ДвижениеСайта.появление) { self.снимок = готовый.картинка }
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, self.номерСнимка == номер, self.снимаем, self.снимок == nil else { return }
            self.снимокНеВышел()
        }
    }

    private func снимокНеВышел() {
        номерСнимка += 1
        снимаем = false
        ОткликСайта.предупреждение()
        показатьВесть(т("lt_shot_fail"))
    }

    /// «Ещё снимок» или ✕ у снимка: обратно к живой примерке.
    func закрытьСнимок() {
        withAnimation(ДвижениеСайта.уход) { снимок = nil }
        снимокДанные = nil
        слежение.сброс()
        if !закрыто && !вФоне { запуститьКамеру() }
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    func сохранить() {
        guard let данные = снимокДанные, !сохраняем else { return }
        сохраняем = true
        Task { @MainActor [weak self] in
            let итог = await СнимокЖивойПримерки.вФото(данные)
            guard let self else { return }
            self.сохраняем = false
            switch итог {
            case .готово:
                ОткликСайта.успех()
                self.показатьВесть(self.т("lt_saved"))
            case .нетДоступа:
                ОткликСайта.предупреждение()
                self.показатьВесть(self.т("lt_save_denied"))
            case .сбой:
                ОткликСайта.предупреждение()
                self.показатьВесть(self.т("lt_save_fail"))
            }
        }
    }

    /// Системный лист: снимок и ссылка на объявление.
    func поделиться() {
        guard let снимок else { return }
        var предметы: [Any] = [снимок]
        if let адрес = товар.адрес { предметы.append(адрес) }
        ПоделитьсяСайта.системныйЛист(предметы)
    }

    func показатьВесть(_ текст: String) {
        номерВести += 1
        let номер = номерВести
        withAnimation(ДвижениеСайта.появление) { весть = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard let self, номер == self.номерВести else { return }
            withAnimation(ДвижениеСайта.уход) { self.весть = nil }
        }
    }
}

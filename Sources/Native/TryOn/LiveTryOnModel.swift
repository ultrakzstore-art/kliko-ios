import SwiftUI
import UIKit

/**
 ЖИВАЯ ПРИМЕРКА — СОСТОЯНИЕ ЭКРАНА (одно на открытый экран, не синглтон; держит его ЭкранЖивойПримерки).

 Держит камеру, анализ кадров и слежение; грузит фото вещи (тот же кэш, что у ленты) и вырезает его один раз в фоне —
 вырезки помнятся до закрытия экрана, по номеру фото. Ручная подгонка (щипок, поворот, сдвиг) — на сеанс, и для другого
 фото вещи тоже. Снимок — следующий кадр камеры с вещью поверх (собирается не на главной нити), дальше — «Сохранить в
 Фото» и «Поделиться». Пока на экране снимок, камера и анализ стоят (на снимке можно сидеть долго — сохранить,
 поделиться); закрыли снимок — камера снова идёт. Камеру прервали (звонок, другое приложение, Split View на iPad) —
 вещь гаснет, подсказка «Камера на паузе».
 */
@MainActor
final class МодельЖивойПримерки: ObservableObject {
    enum СостояниеВещи: Equatable {
        case грузим
        case готово
        /// Не вышло: текст и можно ли повторить то же фото (сеть).
        case неВышло(String, повторить: Bool)
    }

    let товар: Listing
    let вид: ВидЖивойПримерки
    let камера = КамераЖивойПримерки()
    let слежение: СлежениеЖивойПримерки
    let анализ: АнализЖивойПримерки

    @Published private(set) var номерФото: Int
    @Published private(set) var вещь: СостояниеВещи = .грузим
    /// Вырезки текущего фото: одна, у серёг — две (левая и правая).
    @Published private(set) var вырезки: [UIImage] = []
    /// Фото, с которых вещь не вырезалась, — помечены в полосе миниатюр.
    @Published private(set) var неПодошли: Set<Int> = []
    @Published private(set) var состояние: СостояниеСлеженияЖивой = .ищем
    @Published var полосаФото = false
    @Published private(set) var подгонка = ПодгонкаЖивойПримерки()
    @Published private(set) var советЖестов = false
    @Published private(set) var снимок: UIImage? = nil
    @Published private(set) var снимаем = false
    @Published private(set) var сохраняем = false
    /// Короткая весть внизу экрана («Сохранено в Фото»).
    @Published private(set) var весть: String? = nil
    /// Камеру прервала система: кадры не идут.
    @Published private(set) var пауза = false

    private var кэш: [Int: [UIImage]] = [:]
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
        if вырезки.isEmpty { загрузитьВещь() }
        guard !приветствие else { return }
        приветствие = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, !self.закрыто else { return }
            self.показатьВесть(self.т("lt_privacy"))
        }
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

    /// Под снимком камера стоит — её запускает закрытьСнимок().
    private func запуститьКамеру() {
        guard снимок == nil else { return }
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

    func выбратьФото(_ номер: Int) {
        guard товар.фотоАдреса.indices.contains(номер) else { return }
        ОткликСайта.выбор()
        if номер == номерФото, вещь == .готово {
            полосаФото = false
            return
        }
        номерФото = номер
        загрузитьВещь()
    }

    /// То же фото ещё раз (не загрузилось по сети).
    func повторить() {
        загрузитьВещь()
    }

    private func загрузитьВещь() {
        let номер = номерФото
        if let готовые = кэш[номер] {
            вырезки = готовые
            вещь = .готово
            полосаФото = false
            return
        }
        let адреса = товар.фотоАдреса
        guard адреса.indices.contains(номер) else { return }
        let адрес = адреса[номер]
        let пара = вид.пара
        let стоя = вид == .часы || вид == .браслет
        вещь = .грузим
        загрузка?.cancel()
        загрузка = Task { @MainActor [weak self] in
            let картинка = await КартинкиЛенты.shared.загрузить(адрес, пикселей: 1024, заполнить: false)
            guard let self, !Task.isCancelled, !self.закрыто, self.номерФото == номер else { return }
            guard let картинка else {
                self.неВышло(номер, текст: self.т("lt_cut_load"), повторить: true)
                return
            }
            /* Отмена загрузки (другое фото, закрыли экран) доходит и до вырезки: сама в detached она не передаётся. */
            let вырезка = Task.detached(priority: .userInitiated) { () -> ВырезкаЖивойПримерки.Итог in
                ВырезкаЖивойПримерки.вырезать(картинка, пара: пара, стоя: стоя)
            }
            let итог = await withTaskCancellationHandler {
                await вырезка.value
            } onCancel: {
                вырезка.cancel()
            }
            guard !Task.isCancelled, !self.закрыто, self.номерФото == номер else { return }
            switch итог {
            case .готово(let вещи):
                self.кэш[номер] = вещи
                self.неПодошли.remove(номер)
                self.вырезки = вещи
                withAnimation(ДвижениеСайта.появление) {
                    self.вещь = .готово
                    self.полосаФото = false
                }
                self.показатьСоветЖестов()
            case .человек:
                self.неВышло(номер, текст: self.т("lt_cut_person"), повторить: false)
            case .фон:
                self.неВышло(номер, текст: self.т("lt_cut_fail"), повторить: false)
            }
        }
    }

    private func неВышло(_ номер: Int, текст: String, повторить: Bool) {
        if !повторить { неПодошли.insert(номер) }
        вырезки = []
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

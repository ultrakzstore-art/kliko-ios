import Foundation

/**
 СОСТОЯНИЕ НАТИВНОЙ ЛЕНТЫ: страницы, поиск, раздел, ошибки.

 Порядок запуска: сначала лента с диска (ListingsCache) — мгновенно и без сети; следом запрос свежей; пришла —
 подменяем. Не пришла, а на экране уже есть что листать, — ошибку не показываем крупно: человек листает
 вчерашнее, а внизу строка «нет связи».
 */
@MainActor
final class FeedModel: ObservableObject {
    @Published private(set) var items: [Listing] = []
    @Published private(set) var грузим = false
    @Published private(set) var ошибка: ListingsAPI.Ошибка?
    /// На экране лента с диска, а не свежая.
    @Published private(set) var сДиска = false
    /// Ответ на запрос уже был — удачный или с ошибкой. Без него пустой ответ («ничего не нашлось») не отличить
    /// от «ещё грузим», и пустой поиск навсегда оставался бы серыми карточками.
    @Published private(set) var ответПришёл = false
    @Published var поиск = ""
    @Published private(set) var раздел = ""

    private var запрос = ListingsAPI.Запрос()
    private var естьЕщё = true
    private var задача: Task<Void, Never>?
    /// Номер последнего запроса: ответ на прежний (сменили раздел, искомое, потянули вниз) уже не про то, что на экране.
    private var поколение = 0

    init() {
        if let сохранённые = ListingsCache.прочитать() {
            items = сохранённые
            сДиска = true
        }
    }

    /// Первый показ: свежая лента, если на экране пусто или лента с диска.
    func начать() async {
        guard items.isEmpty || сДиска else { return }
        await обновить()
    }

    /// Потянули вниз, сменили раздел или искомое — с первой страницы.
    func обновить() async {
        запрос.page = 1
        запрос.q = поиск.trimmingCharacters(in: .whitespacesAndNewlines)
        запрос.cat = раздел
        естьЕщё = true
        await загрузить(сброс: true)
    }

    func выбратьРаздел(_ ключ: String) {
        guard ключ != раздел else { return }
        раздел = ключ
        перезапустить()
    }

    func искать() { перезапустить() }

    /// Поле поиска очистили — вернуть ленту, но только если по ней уже искали: иначе лишний запрос на каждое открытие поля.
    func поискОчищен() {
        guard !запрос.q.isEmpty else { return }
        перезапустить()
    }

    /// Дошли до последней карточки — следующая страница.
    func дальше(после товар: Listing) {
        guard естьЕщё, !грузим, ошибка == nil, товар.id == items.last?.id else { return }
        запрос.page += 1
        задача = Task { await загрузить(сброс: false) }
    }

    private func перезапустить() {
        задача?.cancel()
        задача = Task { await обновить() }
    }

    private func загрузить(сброс: Bool) async {
        let з = запрос
        поколение += 1
        let номер = поколение
        грузим = true
        defer { if номер == поколение { грузим = false } }
        do {
            let (страница, сырое) = try await ListingsAPI.загрузить(з)
            /* Пока ехал ответ, человек сменил раздел или искомое — этот ответ уже не про то, что на экране. */
            guard номер == поколение, !Task.isCancelled else { return }
            ошибка = nil
            if сброс {
                items = страница.items
                сДиска = false
                ответПришёл = true
                if з.поУмолчанию { ListingsCache.сохранить(сырое) }
            } else {
                /* Лента «рекомендаций» между запросами может сдвинуться, и объявление приедет второй раз. Два
                   одинаковых id в ForEach — это сломанная прокрутка, поэтому повторы отсекаем. */
                let были = Set(items.map(\.id))
                items.append(contentsOf: страница.items.filter { !были.contains($0.id) })
            }
            if страница.items.count < з.per { естьЕщё = false }
        } catch let e as ListingsAPI.Ошибка {
            guard номер == поколение, !Task.isCancelled else { return }
            ответПришёл = true
            ошибка = e
            if !сброс { запрос.page -= 1 }       // следующая попытка — за той же страницей
        } catch {
            guard номер == поколение, !Task.isCancelled else { return }
            ответПришёл = true
            ошибка = .сеть
            if !сброс { запрос.page -= 1 }
        }
    }

    /// Повтор после ошибки внизу ленты.
    func повторить() {
        ошибка = nil
        /* Ошибку сняли сразу, а задача стартует чуть позже: без сброса на пустом экране мелькнуло бы «ничего не нашлось». */
        if items.isEmpty { ответПришёл = false }
        if items.isEmpty || запрос.page == 1 { перезапустить() }
        else {
            запрос.page += 1
            задача = Task { await загрузить(сброс: false) }
        }
    }
}

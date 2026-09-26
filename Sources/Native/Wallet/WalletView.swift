import SwiftUI

/**
 КОШЕЛЁК — ЭКРАН И РАЗДЕЛ ВКЛАДКИ «КАБИНЕТ», ЭТАП 47 (владелец 26.09.2026: «всё одно и то же, просто код разный»,
 Config.нативныйКошелёк).

 У сайта кошелёк — в шапке кабинета (баланс, строка под ним, «Пополнить | Вывести»), а история и «Заморожено сейчас»
 живут под формой пополнения (#topup-screen). Приложение делает так же, но форму пополнения держит за рубильником денег:
   · во вкладке «Кабинет» — карточка «Кошелёк» сразу под шапкой профиля (РазделКошелька) и строки «История операций»,
     «Баллы»;
   · экран кошелька (ЭкранКошелька) — та же карточка, «Выплата … готова», «На удержании» и «Пополнение с карты» (у сайта
     они на экране вывода — здесь это сведения, пока сам вывод страницей сайта), «Заморожено сейчас», «История операций»
     со ссылками «сделка» и «чек».
 🔴 Пока Config.деньгиКошелька выключен, «Пополнить», «Вывести» и «Указать карту» открывают кабинет сайта (стрелка
 «наружу»): экран пополнения сайта по адресу не открыть (showTopup без URL, карта §5.0.6), а в шапке кабинета сайта эти
 кнопки есть. «Вернуть деньги» из «Заморожено» — за Config.деньгиСделок: сделка — её страница на сайте (или своя карточка
 при включённом), предложение — кабинет сайта. «Сделка», «Спор» — своя карточка сделки (этап 43; спор — там).
 Ссылки ?go=wallet (у сайта ветки нет — главный экран, где кошелёк в шапке), ?payout=back (итог выплаты — только чтение)
 и, при включённых деньгах, ?topup=ok|fail без сделки ведут сюда.
 */
struct ЭкранКошелька: View {
    @ObservedObject private var кошелёк = КошелёкМодель.shared
    @StateObject private var пополнение = ПополнениеМодель()
    @StateObject private var вывод = ВыводМодель()
    let сразу: ДействиеКошелька
    let открыть: (URL) -> Void

    @State private var листПополнения = false
    @State private var листВывода = false
    @State private var вопросВерификации = false
    @State private var входОткрыт = false
    @State private var сделкаОткрыть: String? = nil
    @State private var первыйПоказ = true

    init(сразу: ДействиеКошелька = .показать, открыть: @escaping (URL) -> Void) {
        self.сразу = сразу
        self.открыть = открыть
    }

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    var body: some View {
        содержимое
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(т("title"))
            .navigationBarTitleDisplayMode(.inline)
            .task { await показан() }
            .onReceive(NotificationCenter.default.publisher(for: ЗаданияКошелька.пришло)) { _ in
                Task { await выполнитьЗадание() }
            }
            .navigationDestination(item: $сделкаОткрыть) { номер in
                ЭкранСделки(id: номер, открыть: открыть)
            }
            .modifier(ОкнаЭкранаКошелька(кошелёк: кошелёк, пополнение: пополнение, вывод: вывод,
                                         листПополнения: $листПополнения, листВывода: $листВывода,
                                         вопросВерификации: $вопросВерификации, входОткрыт: $входОткрыт,
                                         открыть: открыть))
            .overlay(alignment: .bottom) {
                if let текст = кошелёк.плашка { ПлашкаКошелька(текст: текст) }
            }
    }

    // MARK: - Состояния

    @ViewBuilder
    private var содержимое: some View {
        switch кошелёк.загрузка {
        case .нуженВход:
            ПустоСайта(значок: "person.crop.circle", заголовок: CabinetText.т("signed_out"),
                       подпись: CabinetText.т("signed_out_sub"), кнопка: CabinetText.т("login"),
                       действие: { войти() })
        case .ошибка(let текст):
            if кошелёк.сведения == nil {
                ПустоСайта(значок: "wifi.exclamationmark", заголовок: текст, кнопка: т("retry"),
                           действие: { Task { await кошелёк.загрузить() } })
            } else {
                список
            }
        case .нет, .идёт:
            if кошелёк.сведения == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(т("loading"))
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.текстВторой)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                список
            }
        case .готово:
            список
        }
    }

    private var список: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                КарточкаКошелька(кошелёк: кошелёк, пополнить: { пополнить() }, вывести: { вывести() })
                if !Config.деньгиКошелька {
                    Label(т("site_note"), systemImage: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.текстВторой)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
                if let с = кошелёк.сведения {
                    ForEach(с.выплаты) { в in
                        БаннерВыплаты(выплата: в, открываем: кошелёк.занято.contains(в.wid), указать: { указатьКарту(в) })
                    }
                    if с.удержано > 0 {
                        КарточкаУдержания(сумма: с.удержано, удержания: с.удержания)
                    }
                    if с.пополнениеКартой > 0 {
                        КарточкаПополненияКартой(сумма: с.пополнениеКартой, поддержка: {
                            if let u = Config.url("/support.php?topic=payment") { открыть(u) }
                        })
                    }
                }
                if let з = кошелёк.заморожено {
                    БлокЗаморожено(заморожено: з, занято: кошелёк.занято,
                                   сделка: { номер in открытьСделку(номер) },
                                   вернутьСделку: { номер in вернутьСделку(номер) },
                                   вернутьПредложение: { номер in вернутьПредложение(номер) },
                                   спор: { номер in открытьСделку(номер) })
                }
                история
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .refreshable { await кошелёк.загрузить() }
    }

    /// .wal-card «История операций»: весь transactions[] одного ответа — пагинации у сайта нет.
    private var история: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(т("history"), systemImage: "clock.arrow.circlepath")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Theme.текст)
                .padding(.bottom, 4)
                .accessibilityAddTraits(.isHeader)
            let операции = кошелёк.сведения?.операции ?? []
            if операции.isEmpty {
                Text(т(кошелёк.сведения == nil ? "loading" : "tx_none"))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ForEach(операции) { о in
                    СтрокаОперации(операция: о, чекГрузится: кошелёк.чекГрузится == о.сделка && !о.сделка.isEmpty,
                                   сделка: { номер in открытьСделку(номер) },
                                   чек: { номер in кошелёк.открытьЧек(номер) })
                    if о.id != операции.last?.id { Divider() }
                }
            }
        }
        .padding(14)
        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous)
                .strokeBorder(Theme.линия, lineWidth: 1.5)
        }
    }

    // MARK: - Действия

    private func показан() async {
        await кошелёк.загрузить()
        if первыйПоказ {
            первыйПоказ = false
            switch сразу {
            case .показать: break
            case .пополнить: пополнить()
            case .вывести: вывести()
            }
        }
        await выполнитьЗадание()
    }

    /// Задание из ссылки: ?payout=back — payout_outcome (только чтение); ?topup= — только при включённых деньгах.
    private func выполнитьЗадание() async {
        guard let задание = кошелёк.забратьЗадание() else { return }
        switch задание {
        case .выплата:
            await кошелёк.проверитьВыплату()
        case .пополнение(let оплачено):
            guard Config.деньгиКошелька else { return }
            листПополнения = true
            try? await Task.sleep(nanoseconds: 500_000_000)
            пополнение.вернулисьСБанка(оплачено: оплачено)
        }
    }

    private func сайт(_ хвост: String) {
        if let u = Config.страницаСайта(хвост) { открыть(u) }
    }

    private func пополнить() {
        guard Config.деньгиКошелька else {
            сайт("cabinet.php")
            return
        }
        листПополнения = true
    }

    /// showWithdraw: не верифицирован — «Нужна верификация» (и только тогда).
    private func вывести() {
        guard Config.деньгиКошелька else {
            сайт("cabinet.php")
            return
        }
        if кошелёк.верифицирован == false {
            вопросВерификации = true
            return
        }
        вывод.шаг = 1
        листВывода = true
    }

    private func указатьКарту(_ в: ГотоваяВыплата) {
        guard Config.деньгиКошелька else {
            сайт("cabinet.php")
            return
        }
        кошелёк.ссылкаВыплаты(в.wid)
    }

    /// Карточка сделки (этап 43) или, без неё, страница сделки на сайте.
    private func открытьСделку(_ номер: String) {
        guard СделкиAPI.годныйНомер(номер) else { return }
        if Config.нативныеСделки {
            сделкаОткрыть = номер
        } else {
            сайт("cabinet.php?deal=" + СделкиAPI.вАдрес(номер))
        }
    }

    /// frozenCancel = dealCancel (escrow.php?action=cancel) — деньги сделки: выключено — страница сделки на сайте;
    /// включено — своя карточка, где отмена этапа 44 со своим вопросом и сбором после отправки.
    private func вернутьСделку(_ номер: String) {
        guard СделкиAPI.годныйНомер(номер) else { return }
        if Config.деньгиСделок && Config.нативныеСделки {
            сделкаОткрыть = номер
        } else {
            сайт("cabinet.php?deal=" + СделкиAPI.вАдрес(номер))
        }
    }

    /// frozenUnfund: выключено — кабинет сайта (там «Заморожено сейчас» под пополнением); включено — вопрос сайта.
    private func вернутьПредложение(_ номер: String) {
        guard Config.деньгиСделок else {
            сайт("cabinet.php")
            return
        }
        кошелёк.спроситьСнять(номер)
    }

    private func войти() {
        if Config.нативныйВход {
            входОткрыт = true
        } else {
            сайт("cabinet.php")
        }
    }
}

// MARK: - Окна экрана (вынесены: иначе body — одно длинное выражение для компилятора)

private struct ОкнаЭкранаКошелька: ViewModifier {
    @ObservedObject var кошелёк: КошелёкМодель
    @ObservedObject var пополнение: ПополнениеМодель
    @ObservedObject var вывод: ВыводМодель
    @Binding var листПополнения: Bool
    @Binding var листВывода: Bool
    @Binding var вопросВерификации: Bool
    @Binding var входОткрыт: Bool
    let открыть: (URL) -> Void

    private func т(_ ключ: String) -> String { КошелёкText.т(ключ) }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $листПополнения) {
                ЭкранПополнения(модель: пополнение, открыть: открыть, закрыть: { листПополнения = false })
            }
            .sheet(isPresented: $листВывода) {
                ЭкранВывода(модель: вывод, открыть: открыть, закрыть: { листВывода = false })
            }
            .sheet(item: $кошелёк.чек) { сделка in
                ЧекСделки(сделка: сделка, закрыть: { кошелёк.чек = nil })
            }
            .sheet(item: $кошелёк.банкВыплаты) { б in
                ОкноБанкаКошелька(адрес: б.адрес, вернулись: { итог in
                    if итог == .выплата { кошелёк.вернулисьСБанка() } else { кошелёк.банкВыплаты = nil }
                }, закрыть: {
                    /* Закрыли сами — итог всё равно спросим: карту могли успеть ввести. */
                    кошелёк.вернулисьСБанка()
                })
            }
            .sheet(isPresented: $входОткрыт) {
                ЭкранВхода(eGovВключён: true, открыть: открыть, вошли: {
                    Task { await кошелёк.загрузить() }
                })
            }
            .alert(т("verify_t"), isPresented: $вопросВерификации) {
                Button(т("verify_go")) {
                    if let u = Config.страницаСайта("cabinet.php?go=verify") { открыть(u) }
                }
                Button(т("later"), role: .cancel) {}
            } message: {
                Text(т("verify_s"))
            }
            .alert(т("frz_unfund_t"), isPresented: вопросСнять, presenting: кошелёк.снять) { с in
                Button(т("frz_unfund_ok"), role: .destructive) { кошелёк.снятьПредложение(с.id) }
                Button(т("cancel"), role: .cancel) {}
            } message: { _ in
                Text(т("frz_unfund_s"))
            }
            .overlay {
                if let итог = кошелёк.итогВыплаты { окноВыплаты(итог) }
            }
    }

    private var вопросСнять: Binding<Bool> {
        Binding(get: { кошелёк.снять != nil }, set: { показан in
            if !показан { кошелёк.снять = nil }
        })
    }

    /// wdOutcomeModal: «Деньги отправлены» / «Не удалось вывести», сумма, «Баланс», «Понятно».
    private func окноВыплаты(_ итог: КошелёкМодель.ИтогВыплаты) -> some View {
        var строки: [(String, String)] = []
        if let б = итог.баланс { строки.append((т("balance"), КошелёкФормат.тенге(б))) }
        return ОкноИтогаКошелька(вид: итог.отправлено ? .хорошо : .плохо,
                                 заголовок: т(итог.отправлено ? "out_paid_t" : "out_fail_t"),
                                 сумма: КошелёкФормат.тенге(итог.сумма), строки: строки,
                                 текст: т(итог.отправлено ? "out_paid_s" : "out_fail_s"),
                                 кнопки: [ОкноИтогаКошелька.Кнопка(подпись: т("ok"), главная: true, действие: {
                                     кошелёк.итогВыплаты = nil
                                 })])
    }
}

// MARK: - Раздел вкладки «Кабинет»

/**
 Карточка «Кошелёк» (как .hero-wallet под шапкой кабинета сайта) и строки «История операций» и «Баллы». Кнопки
 карточки: деньги выключены — кабинет сайта; включены — экран кошелька со своей формой (сразу).
 */
struct РазделКошелька: View {
    @ObservedObject private var кошелёк = КошелёкМодель.shared
    let открыть: (URL) -> Void
    let сразу: (ДействиеКошелька) -> Void

    init(открыть: @escaping (URL) -> Void, сразу: @escaping (ДействиеКошелька) -> Void) {
        self.открыть = открыть
        self.сразу = сразу
    }

    var body: some View {
        Section {
            КарточкаКошелька(кошелёк: кошелёк, пополнить: { нажато(.пополнить) }, вывести: { нажато(.вывести) })
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
            if let выплата = кошелёк.сведения?.выплаты.first {
                /* Баннер под шапкой (#payout-ready-hero): «Указать карту» — на экране кошелька или сайте. */
                БаннерВыплаты(выплата: выплата, открываем: false, указать: { нажато(.показать) })
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
            }
            строка(КошелёкText.т("history"), значок: "clock.arrow.circlepath", цель: .кошелёк)
            строка(КошелёкText.т("points"), значок: "star.circle", цель: .баллы)
        }
    }

    /// Строка экрана приложения; в виде сайта — на его поверхности (строкиСайта), как остальные разделы кабинета.
    @ViewBuilder
    private func строка(_ название: String, значок: String, цель: КабинетЦель) -> some View {
        let ссылка = NavigationLink(value: цель) {
            Label {
                Text(название).foregroundStyle(.primary)
            } icon: {
                Image(systemName: значок).foregroundStyle(Theme.green2)
            }
        }
        if Config.дизайнКакНаСайте {
            ссылка.строкиСайта()
        } else {
            ссылка
        }
    }

    private func нажато(_ д: ДействиеКошелька) {
        if д == .показать || Config.деньгиКошелька {
            сразу(д)
        } else if let u = Config.страницаСайта("cabinet.php") {
            открыть(u)
        }
    }
}

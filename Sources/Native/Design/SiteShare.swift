import SwiftUI
import UIKit
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins

/**
 «ПОДЕЛИТЬСЯ» КАК НА САЙТЕ (владелец 26.09.2026: «поделиться такой же мощный, как в PWA, только SwiftUI»).

 Сайт (js/marketplace.min.js): mkShare(id) рисует нижний лист #mk-share-ov: полоска, «Поделиться объявлением»,
 превью (фото 48, название, цена или «Договорная»), строка ссылки с «Копировать» (в буфер — одна ссылка, галочка и
 «Скопировано!» на 1,7 с), сетка .mksh-grid: WhatsApp (wa.me/?text=«текст»\nссылка), Telegram
 (t.me/share/url?url=&text=), Instagram (ссылка в буфер, подсказка sh_insta_hint и фото-карточка), «Фото-карточка»
 (mkShareCard: холст 1080 × 1350 — зелёный градиент, белая карточка, «Kliko.kz», плашка «Гарант-сделка», фото, метка
 состояния, название, цена, три галочки, «Наведи камеру на QR →» и QR справа внизу), «Ссылка», «Ещё» (navigator.share);
 внизу «Позже». Открытие листа считает mkTrackEv("share", id).

 Текст — «Название» — цена ₸ (без цены — «Договорная»), ссылка — mkItemUrl: /kz/<язык>/<чпу>-<id>/ для буквенных номеров,
 /kz/<язык>/marketplace?item=<id> для числовых, плюс p=<номер фото>, если в галерее открыто не первое. Ни ref, ни utm
 сайт к ссылке не добавляет — не добавляем и здесь. QR у сайта — qrcode(0, "M"), тёмный #0b1f14 на белом, без знака в
 середине — так же и здесь (CIQRCodeGenerator, уровень M, увеличение целым числом без сглаживания).

 Сверх сайта (владелец): сразу в приложение WhatsApp и Telegram по их схемам с запасом на веб, SMS, Почта, QR с
 «Сохранить» в Фото и «Поделиться», «Для сторис» — та же карточка 1080 × 1920, Instagram Stories напрямую, если в
 Info.plist есть FacebookAppID (без него Instagram с 2023 года сторис от чужого приложения не принимает) — иначе как сайт.

 Показ: ЛистПоделитьсяСайта.показать(товар) — одной строкой из любого места: лист UIKit поверх верхнего экрана,
 высотой по содержимому (свой detent), тема — от окна. Внутри .sheet — сам вид с .листПоВысоте().
 */
struct ДанныеОтправкиСайта: Hashable {
    let id: String
    let название: String
    let цена: Double
    let состояние: String?
    let фото: URL?
    /// Номер открытого в галерее фото — p= в ссылке, как mkShareImgIdx сайта; 0 — не добавляется.
    let номерФото: Int

    init(id: String, название: String, цена: Double, состояние: String?, фото: URL?, номерФото: Int = 0) {
        self.id = id
        self.название = название
        self.цена = цена
        self.состояние = состояние
        self.фото = фото
        self.номерФото = max(0, номерФото)
    }

    /// Из объявления ленты. `номер` — вместо товар.id (после подачи номер приходит отдельно), `фото` — открытое в галерее.
    init(_ товар: Listing, номер: String? = nil, фото номерФото: Int = 0) {
        let адреса = товар.фотоАдреса
        let n = адреса.indices.contains(номерФото) ? номерФото : 0
        let свой = номер ?? ""
        self.init(id: свой.isEmpty ? товар.id : свой, название: товар.title, цена: товар.price ?? 0,
                  состояние: товар.состояние, фото: адреса.indices.contains(n) ? Optional(адреса[n]) : товар.обложка,
                  номерФото: n)
    }

    /// Из «Моих объявлений».
    init(моё товар: МоёОбъявление) {
        self.init(id: товар.id, название: товар.название, цена: товар.цена, состояние: nil,
                  фото: Config.url(товар.фото))
    }

    /// «14 500 000 ₸» или «Договорная».
    var строкаЦены: String {
        цена > 0 ? ЦенаКарточкиСайта.полная(цена) : ListingPageText.т("negotiable")
    }

    /// ««Название» — 14 500 000 ₸» — r у mkShare сайта.
    var сообщение: String {
        "«\(название)» — \(строкаЦены)"
    }

    /// Сообщение и ссылка строкой ниже — text у wa.me и navigator.share сайта.
    var сообщениеСоСсылкой: String {
        "\(сообщение)\n\(адрес.absoluteString)"
    }

    /// mkItemUrl сайта.
    var адрес: URL {
        let фотоЧасть = номерФото > 0 ? "p=\(номерФото)" : ""
        let хвост: String
        if ПоделитьсяСайта.буквенныйНомер(id) {
            let запрос = фотоЧасть.isEmpty ? "" : "?\(фотоЧасть)"
            хвост = "\(ПоделитьсяСайта.чпу(название))-\(id)/\(запрос)"
        } else {
            let запрос = фотоЧасть.isEmpty ? "" : "&\(фотоЧасть)"
            хвост = "marketplace?item=\(ПоделитьсяСайта.код(id))\(запрос)"
        }
        return Config.страницаСайта(хвост) ?? Config.apiBase
    }
}

// MARK: - Лист

struct ЛистПоделитьсяСайта: View {
    let данные: ДанныеОтправкиСайта
    private let закрытьЛист: (() -> Void)?
    private let высотаСодержимого: ((CGFloat) -> Void)?

    @Environment(\.dismiss) private var закрытьСреда
    @State private var фото: UIImage? = nil
    @State private var измерено: CGFloat = 0
    @State private var тост: String? = nil
    @State private var задачаТоста: Task<Void, Never>? = nil
    @State private var скопировано = false
    @State private var показQR = false
    @State private var qr: UIImage? = nil
    @State private var занято = false

    init(данные: ДанныеОтправкиСайта, закрыть: (() -> Void)? = nil, высота: ((CGFloat) -> Void)? = nil) {
        self.данные = данные
        self.закрытьЛист = закрыть
        self.высотаСодержимого = высота
    }

    private func т(_ ключ: String) -> String { SiteShareText.т(ключ) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Text(т("title"))
                    .font(.system(size: 19, weight: .heavy))
                    .foregroundStyle(Theme.текст)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 12)
                превью
                    .padding(.bottom, 14)
                строкаСсылки
                    .padding(.bottom, 14)
                сетка
                if показQR {
                    панельQR
                        .padding(.top, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                Button(т("later")) { закрыть() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.текстВторой)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 10)
            .frame(maxWidth: 460)
            .frame(maxWidth: .infinity)
            .мерилоЛиста()
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.поверхность.ignoresSafeArea())
        .overlay(alignment: .bottom) { плашкаТоста }
        .onPreferenceChange(ВысотаЛистаКлюч.self) { новое in
            if abs(новое - измерено) > 0.5 { измерено = новое }
        }
        .onChange(of: измерено) { _, новое in высотаСодержимого?(новое) }
        .task {
            if фото == nil { фото = await ПоделитьсяСайта.загрузить(данные.фото) }
        }
        .onAppear {
            if !данные.id.isEmpty { КонтактыПродавца.отметить("share", объявление: данные.id) }
        }
    }

    // MARK: Части

    /// .mksh-prev: фото 48, название в строку, цена зелёным.
    private var превью: some View {
        HStack(spacing: 12) {
            Group {
                if let фото {
                    Image(uiImage: фото).resizable().scaledToFill()
                } else {
                    ZStack {
                        Theme.линия
                        Image(systemName: "photo")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.текстВторой)
                    }
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Радиус.sm, style: .continuous))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(данные.название)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                Text(данные.строкаЦены)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.акцент)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// .mksh-linkrow: значок цепи, ссылка серым в строку, «Копировать» — после нажатия галочка и «Скопировано!».
    private var строкаСсылки: some View {
        Button { скопировать() } label: {
            HStack(spacing: 10) {
                Image(systemName: скопировано ? "checkmark" : "link")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.акцент)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text(данные.адрес.absoluteString)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.текстВторой)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(скопировано ? т("copied") : т("copy"))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.акцент)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(скопировано ? Theme.мята : Theme.поверхность2,
                        in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                    .strokeBorder(скопировано ? Theme.акцент : Theme.линия, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.98))
        .accessibilityLabel(т("copy_link"))
        .accessibilityValue(данные.адрес.absoluteString)
    }

    /// .mksh-grid — круглые кнопки приложений, по четыре в ряд.
    private var сетка: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 14) {
            кнопка("WhatsApp", фон: Color(uiColor: Theme.hex(0x25D366)), действие: { whatsApp() }) {
                ЗнакWhatsApp().scaleEffect(1.25)
            }
            кнопка("Telegram", фон: Color(uiColor: Theme.hex(0x229ED9)), действие: { telegram() }) {
                символ("paperplane.fill")
            }
            кнопка("Instagram", фон: ПоделитьсяСайта.цветаInstagram, действие: { instagram() }) {
                символ("camera")
            }
            кнопка("SMS", фон: Color(uiColor: Theme.hex(0x34C759)), действие: { смс() }) {
                символ("message.fill")
            }
            кнопка(т("email"), фон: Color(uiColor: Theme.hex(0x1D9BF0)), действие: { почта() }) {
                символ("envelope.fill")
            }
            кнопка(т("photo"), фон: Theme.поверхность2, рамка: true, действие: { картинка(1350) }) {
                символ("photo.on.rectangle", цвет: Theme.акцент)
            }
            кнопка(т("story"), фон: Theme.поверхность2, рамка: true, действие: { картинка(1920) }) {
                символ("rectangle.portrait", цвет: Theme.акцент)
            }
            кнопка("QR", фон: показQR ? Theme.мята : Theme.поверхность2, рамка: true, действие: { переключитьQR() }) {
                символ("qrcode", цвет: Theme.акцент)
            }
            кнопка(скопировано ? т("copied") : т("link"), фон: скопировано ? Theme.мята : Theme.поверхность2, рамка: true,
                   действие: { скопировать() }) {
                символ(скопировано ? "checkmark" : "link", цвет: Theme.акцент)
            }
            кнопка(т("more"), фон: Theme.поверхность2, рамка: true, действие: { ещё() }) {
                символ("ellipsis", цвет: Theme.текст)
            }
        }
        .disabled(занято)
    }

    private func кнопка<Знак: View, Фон: ShapeStyle>(_ подпись: String, фон: Фон, рамка: Bool = false,
                                                     действие: @escaping () -> Void,
                                                     @ViewBuilder знак: () -> Знак) -> some View {
        Button(action: действие) {
            VStack(spacing: 7) {
                знак()
                    .frame(width: 56, height: 56)
                    .background(фон, in: Circle())
                    .overlay {
                        if рамка { Circle().strokeBorder(Theme.линия, lineWidth: 1.5) }
                    }
                    .accessibilityHidden(true)
                Text(подпись)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.текст)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(НажатиеПанелиСайта(сжатие: 0.95))
        .accessibilityLabel(подпись)
    }

    private func символ(_ имя: String, цвет: Color = .white) -> some View {
        Image(systemName: имя)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(цвет)
    }

    /// QR ссылки: крупно, чёткими квадратами; «Сохранить» в Фото и «Поделиться».
    private var панельQR: some View {
        VStack(spacing: 12) {
            if let qr {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 196, height: 196)
                    .padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
                    .accessibilityLabel(т("qr_label"))
            }
            Text(т("qr_hint"))
                .font(.system(size: 13))
                .foregroundStyle(Theme.текстВторой)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button { Task { await сохранитьQR() } } label: {
                    Label(т("save"), systemImage: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.акцент, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
                Button { поделитьсяQR() } label: {
                    Label(т("share"), systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.акцент)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.поверхность, in: RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Радиус.ms, style: .continuous)
                                .strokeBorder(Theme.акцент, lineWidth: 1.5)
                        }
                }
                .buttonStyle(НажатиеПанелиСайта(сжатие: 0.97))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.поверхность2, in: RoundedRectangle(cornerRadius: Theme.Радиус.md, style: .continuous))
    }

    @ViewBuilder
    private var плашкаТоста: some View {
        if let тост {
            Text(тост)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(uiColor: Theme.hex(0x12271C, 0.94)), in: Capsule())
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    // MARK: Действия

    private func закрыть() {
        if let закрытьЛист { закрытьЛист() } else { закрытьСреда() }
    }

    private func показатьТост(_ текст: String, секунд: Double = 1.8) {
        задачаТоста?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { тост = текст }
        UIAccessibility.post(notification: .announcement, argument: текст)
        задачаТоста = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(секунд * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { тост = nil }
        }
    }

    /// Ссылка в буфер (mkShareCopyRow), отклик и «Ссылка скопирована».
    private func скопировать() {
        UIPasteboard.general.string = данные.адрес.absoluteString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeOut(duration: 0.15)) { скопировано = true }
        показатьТост(т("link_copied"))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_700_000_000)
            withAnimation(.easeIn(duration: 0.15)) { скопировано = false }
        }
    }

    private func whatsApp() {
        ПоделитьсяСайта.whatsApp(данные)
        закрыть()
    }

    private func telegram() {
        ПоделитьсяСайта.telegram(данные)
        закрыть()
    }

    private func смс() {
        let текст = ПоделитьсяСайта.код(данные.сообщениеСоСсылкой)
        if let u = URL(string: "sms:&body=\(текст)") { UIApplication.shared.open(u) }
    }

    private func почта() {
        let тема = ПоделитьсяСайта.код(данные.название)
        let текст = ПоделитьсяСайта.код(данные.сообщениеСоСсылкой)
        if let u = URL(string: "mailto:?subject=\(тема)&body=\(текст)") { UIApplication.shared.open(u) }
    }

    /// «Ещё» — navigator.share({title, text, url}) сайта: системный лист с текстом и ссылкой (тема письма — название).
    private func ещё() {
        let адрес = АдресДляОтправкиСайта(адрес: данные.адрес, тема: данные.название)
        ПоделитьсяСайта.системныйЛист([данные.сообщение, адрес])
    }

    private func переключитьQR() {
        if qr == nil { qr = ПоделитьсяСайта.qr(данные.адрес.absoluteString, модуль: 8) }
        withAnimation(.easeOut(duration: 0.22)) { показQR.toggle() }
    }

    /// Фото, если ещё не пришло, — дождаться; затем нарисовать карточку.
    private func готовоеФото() async -> UIImage? {
        if let фото { return фото }
        let пришло = await ПоделитьсяСайта.загрузить(данные.фото)
        фото = пришло
        return пришло
    }

    /// «Фото-карточка» (1350) и «Для сторис» (1920): картинка — в системный лист (там и «Сохранить изображение»).
    private func картинка(_ высота: CGFloat) {
        guard !занято else { return }
        занято = true
        показатьТост(т("making"), секунд: 1.4)
        Task { @MainActor in
            let снимок = await готовоеФото()
            let готово = ПоделитьсяСайта.постер(данные, фото: снимок, высота: высота)
            занято = false
            guard let готово else { показатьТост(т("failed")); return }
            ПоделитьсяСайта.системныйЛист([готово])
        }
    }

    /// Instagram: сторис напрямую, если можно; иначе как mkShareInsta сайта — ссылка в буфер, подсказка и фото-карточка.
    private func instagram() {
        guard !занято else { return }
        занято = true
        Task { @MainActor in
            let снимок = await готовоеФото()
            занято = false
            if let сторис = ПоделитьсяСайта.постер(данные, фото: снимок, высота: 1920),
               ПоделитьсяСайта.вСторисInstagram(сторис, адрес: данные.адрес) {
                закрыть()
                return
            }
            UIPasteboard.general.string = данные.адрес.absoluteString
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            показатьТост(т("insta_hint"), секунд: 3.5)
            guard let карточка = ПоделитьсяСайта.постер(данные, фото: снимок, высота: 1350) else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            ПоделитьсяСайта.системныйЛист([карточка])
        }
    }

    private func сохранитьQR() async {
        guard let картинка = ПоделитьсяСайта.картинкаQR(данные) else { показатьТост(т("failed")); return }
        let сохранено = await ПоделитьсяСайта.вФото(картинка)
        if сохранено { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        показатьТост(сохранено ? т("saved") : т("save_denied"), секунд: сохранено ? 1.8 : 3)
    }

    private func поделитьсяQR() {
        guard let картинка = ПоделитьсяСайта.картинкаQR(данные) else { показатьТост(т("failed")); return }
        ПоделитьсяСайта.системныйЛист([картинка, данные.адрес])
    }
}

// MARK: - Показ одной строкой

extension ЛистПоделитьсяСайта {
    /// Лист «Поделиться» для объявления поверх верхнего экрана. `номер` — если id ещё не в товаре, `фото` — открытое.
    @MainActor
    static func показать(_ товар: Listing, номер: String? = nil, фото: Int = 0) {
        показать(ДанныеОтправкиСайта(товар, номер: номер, фото: фото))
    }

    @MainActor
    static func показать(_ данные: ДанныеОтправкиСайта) {
        guard let верх = ПоделитьсяСайта.верхнийЭкран() else { return }
        let мерка = МеркаЛистаПоделиться()
        let хост = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
        let вид = ЛистПоделитьсяСайта(данные: данные,
                                      закрыть: { [weak хост] in хост?.dismiss(animated: true) },
                                      высота: { [weak хост] новая in мерка.обновить(новая, хост: хост) })
        хост.rootView = AnyView(вид)
        хост.view.backgroundColor = UIColor(Theme.поверхность)
        /* formSheet: на iPhone — тот же нижний лист, на iPad — окно по центру размером preferredContentSize. */
        хост.modalPresentationStyle = .formSheet
        хост.preferredContentSize = CGSize(width: 460, height: 620)
        if let лист = хост.sheetPresentationController {
            лист.detents = [
                .custom(identifier: МеркаЛистаПоделиться.метка) { контекст in
                    мерка.высотаЛиста(контекст.maximumDetentValue)
                }
            ]
            лист.prefersGrabberVisible = true
            лист.preferredCornerRadius = 22
            лист.prefersScrollingExpandsWhenScrolledToEdge = false
        }
        верх.present(хост, animated: true)
    }
}

/// Высота содержимого листа для своего detent: вид сообщает, лист пересчитывает.
final class МеркаЛистаПоделиться {
    static let метка = UISheetPresentationController.Detent.Identifier("kz.kliko.share")
    var высота: CGFloat = 0

    /// Пока не измерено — 60 % экрана; дальше — по содержимому, но не выше экрана (ScrollView долистает).
    func высотаЛиста(_ предел: CGFloat) -> CGFloat {
        высота > 1 ? min(высота.rounded(.up), предел) : предел * 0.6
    }

    @MainActor
    func обновить(_ новая: CGFloat, хост: UIViewController?) {
        guard abs(новая - высота) > 0.5 else { return }
        высота = новая
        guard let хост else { return }
        хост.preferredContentSize = CGSize(width: 460, height: новая.rounded(.up))
        if let лист = хост.sheetPresentationController {
            лист.animateChanges { лист.invalidateDetents() }
        }
    }
}

/// Ссылка для системного листа: тема письма — название объявления.
final class АдресДляОтправкиСайта: NSObject, UIActivityItemSource {
    let адрес: URL
    let тема: String

    init(адрес: URL, тема: String) {
        self.адрес = адрес
        self.тема = тема
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        адрес
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        адрес
    }

    func activityViewController(_ activityViewController: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        тема
    }
}

// MARK: - Общее: ссылки, приложения, картинки

enum ПоделитьсяСайта {
    static let цветаInstagram = LinearGradient(
        colors: [Color(uiColor: Theme.hex(0xF58529)), Color(uiColor: Theme.hex(0xDD2A7B)), Color(uiColor: Theme.hex(0x8134AF))],
        startPoint: .bottomLeading, endPoint: .topTrailing)

    /// encodeURIComponent: всё, кроме A–Z a–z 0–9 - _ . ! ~ * ' ( ).
    static func код(_ текст: String) -> String {
        let можно = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.!~*'()")
        return текст.addingPercentEncoding(withAllowedCharacters: можно) ?? текст
    }

    /// /^[A-Za-z][A-Za-z0-9_]{5,}$/ сайта — у таких номеров ЧПУ-ссылка.
    static func буквенныйНомер(_ номер: String) -> Bool {
        номер.range(of: "^[A-Za-z][A-Za-z0-9_]{5,}$", options: .regularExpression) != nil
    }

    private static let транслит: [Unicode.Scalar: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "e", "ж": "zh", "з": "z", "и": "i", "й": "y",
        "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u", "ф": "f",
        "х": "h", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya",
        "қ": "q", "ғ": "g", "ң": "ng", "ү": "u", "ұ": "u", "һ": "h", "ө": "o", "і": "i", "ә": "a"
    ]

    /// mkSlug сайта: строчные, кириллица латиницей, прочее — дефисами, не длиннее 60; пусто — «obyavlenie».
    static func чпу(_ название: String) -> String {
        var латиницей = ""
        for скаляр in название.lowercased().unicodeScalars {
            if let замена = транслит[скаляр] {
                латиницей.append(замена)
            } else {
                латиницей.unicodeScalars.append(скаляр)
            }
        }
        var итог = ""
        var былДефис = false
        for скаляр in латиницей.unicodeScalars {
            let v = скаляр.value
            if (97...122).contains(v) || (48...57).contains(v) {
                итог.unicodeScalars.append(скаляр)
                былДефис = false
            } else if !былДефис {
                итог.append("-")
                былДефис = true
            }
        }
        итог = обрезатьДефисы(итог)
        if итог.isEmpty { return "obyavlenie" }
        if итог.count > 60 {
            итог = String(итог.prefix(60))
            while итог.hasSuffix("-") { итог.removeLast() }
        }
        return итог
    }

    private static func обрезатьДефисы(_ s: String) -> String {
        var t = Substring(s)
        while t.hasPrefix("-") { t = t.dropFirst() }
        while t.hasSuffix("-") { t = t.dropLast() }
        return String(t)
    }

    /// Открыть приложение по схеме, нет его — веб-адрес.
    @MainActor
    static func открыть(_ приложение: String, запасной: String) {
        if let u = URL(string: приложение), UIApplication.shared.canOpenURL(u) {
            UIApplication.shared.open(u)
        } else if let w = URL(string: запасной) {
            UIApplication.shared.open(w)
        }
    }

    /// WhatsApp: whatsapp://send?text=, запасной — wa.me/?text= (текст сайта: сообщение и ссылка строкой ниже).
    @MainActor
    static func whatsApp(_ данные: ДанныеОтправкиСайта) {
        let текст = код(данные.сообщениеСоСсылкой)
        открыть("whatsapp://send?text=\(текст)", запасной: "https://wa.me/?text=\(текст)")
    }

    /// Telegram: tg://msg_url?url=&text=, запасной — t.me/share/url?url=&text=.
    @MainActor
    static func telegram(_ данные: ДанныеОтправкиСайта) {
        let ссылка = код(данные.адрес.absoluteString)
        let текст = код(данные.сообщение)
        открыть("tg://msg_url?url=\(ссылка)&text=\(текст)", запасной: "https://t.me/share/url?url=\(ссылка)&text=\(текст)")
    }

    /// Instagram Stories с картинкой фоном. Нужен FacebookAppID в Info.plist и установленный Instagram; иначе false.
    @MainActor
    static func вСторисInstagram(_ картинка: UIImage, адрес: URL) -> Bool {
        guard let приложение = Bundle.main.object(forInfoDictionaryKey: "FacebookAppID") as? String, !приложение.isEmpty,
              let схема = URL(string: "instagram-stories://share?source_application=\(код(приложение))"),
              UIApplication.shared.canOpenURL(схема),
              let png = картинка.pngData() else { return false }
        let предмет: [String: Any] = [
            "com.instagram.sharedSticker.backgroundImage": png,
            "com.instagram.sharedSticker.contentURL": адрес.absoluteString
        ]
        UIPasteboard.general.setItems([предмет], options: [.expirationDate: Date().addingTimeInterval(300)])
        UIApplication.shared.open(схема)
        return true
    }

    /// Фото объявления: из общего кэша сразу, иначе запросом. Не вышло — nil (карточка нарисуется с подложкой).
    static func загрузить(_ адрес: URL?) async -> UIImage? {
        guard let адрес else { return nil }
        let запрос = URLRequest(url: адрес)
        if let ответ = URLCache.shared.cachedResponse(for: запрос), let картинка = UIImage(data: ответ.data) {
            return картинка
        }
        guard let результат = try? await URLSession.shared.data(for: запрос) else { return nil }
        return UIImage(data: результат.0)
    }

    /// QR ссылки: уровень M, тёмный #0b1f14 на белом, каждый модуль — `модуль` пикселей без сглаживания.
    static func qr(_ текст: String, модуль: CGFloat) -> UIImage? {
        let генератор = CIFilter.qrCodeGenerator()
        генератор.message = Data(текст.utf8)
        генератор.correctionLevel = "M"
        guard let код = генератор.outputImage else { return nil }
        let краска = CIFilter.falseColor()
        краска.inputImage = код
        краска.color0 = CIColor(red: 11.0 / 255, green: 31.0 / 255, blue: 20.0 / 255)
        краска.color1 = CIColor(red: 1, green: 1, blue: 1)
        guard let цветной = краска.outputImage else { return nil }
        let крупно = цветной.transformed(by: CGAffineTransform(scaleX: max(1, модуль.rounded()), y: max(1, модуль.rounded())))
        guard let готово = CIContext().createCGImage(крупно, from: крупно.extent.integral) else { return nil }
        return UIImage(cgImage: готово)
    }

    /// Карточка сайта (mkShareCard) шириной 1080 пикселей: 1350 — «Фото-карточка», 1920 — для сторис.
    @MainActor
    static func постер(_ данные: ДанныеОтправкиСайта, фото: UIImage?, высота: CGFloat) -> UIImage? {
        let вид = ПостерОбъявленияСайта(данные: данные, фото: фото, qr: qr(данные.адрес.absoluteString, модуль: 12),
                                         высота: высота)
        let рисовальщик = ImageRenderer(content: вид)
        рисовальщик.scale = 1
        рисовальщик.isOpaque = true
        return рисовальщик.uiImage
    }

    /// QR для сохранения: белая карточка 1080 × 1280 — код, название, цена и «Kliko.kz».
    @MainActor
    static func картинкаQR(_ данные: ДанныеОтправкиСайта) -> UIImage? {
        guard let код = qr(данные.адрес.absoluteString, модуль: 16) else { return nil }
        let рисовальщик = ImageRenderer(content: КартинкаQRСайта(данные: данные, qr: код))
        рисовальщик.scale = 1
        рисовальщик.isOpaque = true
        return рисовальщик.uiImage
    }

    /// В Фото — только добавление (NSPhotoLibraryAddUsageDescription). false — доступа нет или не сохранилось.
    static func вФото(_ картинка: UIImage) async -> Bool {
        let доступ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard доступ == .authorized || доступ == .limited else { return false }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetChangeRequest.creationRequestForAsset(from: картинка)
            }
            return true
        } catch {
            return false
        }
    }

    /// Системный лист поверх верхнего экрана; на iPad — всплывающий у низа экрана (без привязки UIKit роняет приложение).
    @MainActor
    static func системныйЛист(_ предметы: [Any]) {
        guard let верх = верхнийЭкран() else { return }
        let лист = UIActivityViewController(activityItems: предметы, applicationActivities: nil)
        if let всплывающее = лист.popoverPresentationController {
            let вид: UIView = верх.view
            всплывающее.sourceView = вид
            всплывающее.sourceRect = CGRect(x: вид.bounds.midX, y: вид.bounds.maxY - 60, width: 1, height: 1)
            всплывающее.permittedArrowDirections = [.down]
        }
        верх.present(лист, animated: true)
    }

    /// Самый верхний показанный экран ключевого окна.
    @MainActor
    static func верхнийЭкран() -> UIViewController? {
        let окна = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        var верх = (окна.first { $0.isKeyWindow } ?? окна.first)?.rootViewController
        while let дальше = верх?.presentedViewController, !дальше.isBeingDismissed { верх = дальше }
        return верх
    }
}

// MARK: - Картинки

/**
 mkShareCard сайта в пикселях (масштаб 1): градиент #0e5a34 → #0a3a22, белая карточка с отступом 54 и скруглением 44,
 «Kliko.kz» 48 900 зелёным #0b6b3c и плашка «Гарант-сделка» справа, фото со скруглением 28 и меткой состояния, название
 46 800 (две строки), цена 72 900, три галочки, черта, «Наведи камеру на QR →» и QR 176 в светлой рамке 208. Всегда
 светлая: её увидят в чужой ленте.
 */
struct ПостерОбъявленияСайта: View {
    let данные: ДанныеОтправкиСайта
    let фото: UIImage?
    let qr: UIImage?
    let высота: CGFloat

    private var зелёный: Color { Color(uiColor: Theme.hex(0x0B6B3C)) }
    private var фотоВысота: CGFloat { max(420, высота - 790) }
    private func т(_ ключ: String) -> String { SiteShareText.т(ключ) }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(uiColor: Theme.hex(0x0E5A34)), Color(uiColor: Theme.hex(0x0A3A22))],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 0) {
                шапка
                обложка
                    .padding(.top, 30)
                Text(данные.название.isEmpty ? т("poster_item") : данные.название)
                    .font(.system(size: 46, weight: .heavy))
                    .foregroundStyle(Color(uiColor: Theme.hex(0x14312A)))
                    .lineLimit(2)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 34)
                Text(данные.строкаЦены)
                    .font(.system(size: 72, weight: .black))
                    .foregroundStyle(зелёный)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.top, 10)
                Spacer(minLength: 16)
                низ
            }
            .padding(52)
            .frame(width: 972, height: высота - 108, alignment: .topLeading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
        }
        .frame(width: 1080, height: высота)
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
    }

    private var шапка: some View {
        HStack(alignment: .center) {
            Text("Kliko.kz")
                .font(.system(size: 48, weight: .black))
                .foregroundStyle(зелёный)
            Spacer(minLength: 16)
            Text(т("poster_guarantee"))
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(зелёный)
                .padding(.horizontal, 22)
                .frame(height: 48)
                .background(Color(uiColor: Theme.hex(0xE9F5EE)), in: Capsule())
        }
    }

    private var обложка: some View {
        ZStack(alignment: .topLeading) {
            if let фото {
                Image(uiImage: фото)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 868, height: фотоВысота)
                    .clipped()
            } else {
                ZStack {
                    Color(uiColor: Theme.hex(0xEEF4F0))
                    Text("Kliko.kz")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Color(uiColor: Theme.hex(0x9AA8A0)))
                }
                .frame(width: 868, height: фотоВысота)
            }
            if let состояние = данные.состояние, !состояние.isEmpty {
                let новое = состояние == "new"
                Text(ListingPageText.т(новое ? "cond_new" : "cond_used"))
                    .font(.system(size: 27, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 20)
                    .frame(height: 46)
                    .background(новое ? зелёный : Theme.меткаБУ, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .padding(22)
            }
        }
        .frame(width: 868, height: фотоВысота)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var низ: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(["poster_b1", "poster_b2", "poster_b3"], id: \.self) { ключ in
                    HStack(spacing: 14) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(Color.white)
                            .frame(width: 32, height: 32)
                            .background(зелёный, in: Circle())
                        Text(т(ключ))
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(Color(uiColor: Theme.hex(0x3F5A4E)))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(height: 52, alignment: .leading)
                }
                Rectangle()
                    .fill(Color(uiColor: Theme.hex(0xE6ECE8)))
                    .frame(height: 2)
                    .padding(.vertical, 20)
                Text(qr != nil ? т("poster_qr") : т("poster_open"))
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(зелёный)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let qr {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 176, height: 176)
                    .padding(16)
                    .background(Color(uiColor: Theme.hex(0xF4F8F6)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

/// QR для Фото: белая карточка 1080 × 1280, код 760, название, цена и «Kliko.kz».
struct КартинкаQRСайта: View {
    let данные: ДанныеОтправкиСайта
    let qr: UIImage

    var body: some View {
        VStack(spacing: 0) {
            Text("Kliko.kz")
                .font(.system(size: 56, weight: .black))
                .foregroundStyle(Color(uiColor: Theme.hex(0x0B6B3C)))
                .padding(.bottom, 40)
            Image(uiImage: qr)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: 760, height: 760)
            Text(данные.название)
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(Color(uiColor: Theme.hex(0x14312A)))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.top, 40)
            Text(данные.строкаЦены)
                .font(.system(size: 52, weight: .black))
                .foregroundStyle(Color(uiColor: Theme.hex(0x0B6B3C)))
                .lineLimit(1)
                .padding(.top, 12)
        }
        .padding(.horizontal, 80)
        .frame(width: 1080, height: 1280)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .dynamicTypeSize(.large)
    }
}

// MARK: - Тексты

/// Тексты листа (i18n сайта: sh_title, copy_word, copied_excl, sh_link, sh_photo, sh_more, sh_making, sh_insta_hint,
/// img_saved, later) на языке телефона — kk/ru/en/ar.
enum SiteShareText {
    static func т(_ ключ: String) -> String {
        let язык = String((Locale.preferredLanguages.first ?? "ru").prefix(2))
        let словарь = тексты[язык] ?? тексты["ru"] ?? [:]
        return словарь[ключ] ?? тексты["ru"]?[ключ] ?? ключ
    }

    private static let тексты: [String: [String: String]] = [
        "ru": [
            "title": "Поделиться объявлением", "copy": "Копировать", "copied": "Скопировано!",
            "copy_link": "Скопировать ссылку", "link_copied": "Ссылка скопирована", "link": "Ссылка",
            "email": "Почта", "photo": "Фото-карточка", "story": "Для сторис", "more": "Ещё", "later": "Позже",
            "making": "Готовлю фото…", "failed": "Не получилось, попробуйте ещё раз",
            "insta_hint": "Ссылка скопирована — вставьте в Instagram. Сохраняю фото для поста…",
            "save": "Сохранить", "share": "Поделиться", "saved": "Картинка сохранена",
            "save_denied": "Нет доступа к Фото — разрешите в Настройках",
            "qr_label": "QR-код ссылки на объявление", "qr_hint": "Наведите камеру телефона — откроется объявление",
            "poster_item": "Объявление", "poster_guarantee": "Гарант-сделка",
            "poster_b1": "Оплата защищена (гарант-сделка)", "poster_b2": "Проверенные продавцы",
            "poster_b3": "Доставка по Казахстану", "poster_qr": "Наведи камеру на QR →",
            "poster_open": "Открыть на Kliko.kz  →"
        ],
        "kk": [
            "title": "Хабарландырумен бөлісу", "copy": "Көшіру", "copied": "Көшірілді!",
            "copy_link": "Сілтемені көшіру", "link_copied": "Сілтеме көшірілді", "link": "Сілтеме",
            "email": "Пошта", "photo": "Фото-карточка", "story": "Сторис үшін", "more": "Тағы", "later": "Кейін",
            "making": "Фото дайындалуда…", "failed": "Болмады, қайта көріңіз",
            "insta_hint": "Сілтеме көшірілді — Instagram-ға қойыңыз. Жазбаға фото сақталуда…",
            "save": "Сақтау", "share": "Бөлісу", "saved": "Сурет сақталды",
            "save_denied": "Фотоға рұқсат жоқ — Баптауларда рұқсат етіңіз",
            "qr_label": "Хабарландыру сілтемесінің QR-коды", "qr_hint": "Телефон камерасын бағыттаңыз — хабарландыру ашылады",
            "poster_item": "Хабарландыру", "poster_guarantee": "Кепіл-мәміле",
            "poster_b1": "Төлем қорғалған (кепіл-мәміле)", "poster_b2": "Тексерілген сатушылар",
            "poster_b3": "Қазақстан бойынша жеткізу", "poster_qr": "Камераны QR-ға бағытта →",
            "poster_open": "Kliko.kz-те ашу  →"
        ],
        "en": [
            "title": "Share listing", "copy": "Copy", "copied": "Copied!",
            "copy_link": "Copy link", "link_copied": "Link copied", "link": "Link",
            "email": "Mail", "photo": "Photo card", "story": "For stories", "more": "More", "later": "Later",
            "making": "Preparing the photo…", "failed": "Something went wrong, try again",
            "insta_hint": "Link copied — paste it in Instagram. Saving a photo for the post…",
            "save": "Save", "share": "Share", "saved": "Image saved",
            "save_denied": "No access to Photos — allow it in Settings",
            "qr_label": "QR code of the listing link", "qr_hint": "Point a phone camera at it to open the listing",
            "poster_item": "Listing", "poster_guarantee": "Escrow deal",
            "poster_b1": "Payment protected (escrow deal)", "poster_b2": "Verified sellers",
            "poster_b3": "Delivery across Kazakhstan", "poster_qr": "Point your camera at the QR →",
            "poster_open": "Open on Kliko.kz  →"
        ],
        "ar": [
            "title": "مشاركة الإعلان", "copy": "نسخ", "copied": "تم النسخ!",
            "copy_link": "نسخ الرابط", "link_copied": "تم نسخ الرابط", "link": "الرابط",
            "email": "البريد", "photo": "بطاقة صورة", "story": "للقصص", "more": "المزيد", "later": "لاحقًا",
            "making": "جارٍ تجهيز الصورة…", "failed": "تعذّر ذلك، حاول مرة أخرى",
            "insta_hint": "تم نسخ الرابط — الصقه في Instagram. جارٍ حفظ صورة للمنشور…",
            "save": "حفظ", "share": "مشاركة", "saved": "تم حفظ الصورة",
            "save_denied": "لا يوجد وصول إلى الصور — اسمح به في الإعدادات",
            "qr_label": "رمز QR لرابط الإعلان", "qr_hint": "وجّه كاميرا الهاتف لفتح الإعلان",
            "poster_item": "إعلان", "poster_guarantee": "صفقة مضمونة",
            "poster_b1": "الدفع محمي (صفقة مضمونة)", "poster_b2": "بائعون موثّقون",
            "poster_b3": "التوصيل في جميع أنحاء كازاخستان", "poster_qr": "وجّه الكاميرا إلى رمز QR ←",
            "poster_open": "افتح على Kliko.kz  ←"
        ]
    ]
}

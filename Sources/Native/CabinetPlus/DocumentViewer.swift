import SwiftUI
import UIKit
import PDFKit
import WebKit

/**
 ДОКУМЕНТЫ КАБИНЕТА СВОИМ ОКНОМ: ПРОСМОТР PDF, «ПОДЕЛИТЬСЯ» И ПЕЧАТЬ (владелец: «и кабинет полностью SwiftUI сделай»).

 У сайта документы — это HTML: счёт, акт, накладная, КП и прайс-лист модуль business собирает сам и печатает окном
 браузера (window.open + print), договор и акт аренды, акт работ и гарантийный талон отдаёт сервер (escrow.php?action=
 rental_contract | rental_act | service_act | warranty_card, cabinet.php?action=rent_contract). Здесь оба вида
 превращаются в PDF на телефоне (UIMarkupTextPrintFormatter и UIPrintPageRenderer, лист A4) и показываются PDFKit:
 «Поделиться» — системный лист с файлом .pdf, «Печать» — UIPrintInteractionController. Сайт не открывается.

 Серверный документ читается тем же транспортом, что остальной кабинет (fetch изнутри страницы сайта под слоем — её куки),
 в разметку добавляется <base href> сайта, чтобы относительные ссылки и картинки указывали на kliko.kz.
 */

/// Что показать: готовая разметка (собрана приложением) или путь серверного документа от корня сайта.
enum ИсточникДокумента: Equatable {
    case разметка(String)
    case путь(String)
}

/// Документ для окна: заголовок и источник.
struct ДокументКабинета: Identifiable, Equatable {
    let id = UUID()
    let заголовок: String
    let источник: ИсточникДокумента

    static func == (a: ДокументКабинета, b: ДокументКабинета) -> Bool { a.id == b.id }
}

// MARK: - HTML → PDF

@MainActor
enum PDFизHTML {
    /// Лист A4 в пунктах и поля 12 мм, как @page сайта.
    private static let лист = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
    private static let поле: CGFloat = 34

    private final class РендерЛиста: UIPrintPageRenderer {
        let бумага: CGRect
        let печать: CGRect

        init(бумага: CGRect, печать: CGRect) {
            self.бумага = бумага
            self.печать = печать
            super.init()
        }

        override var paperRect: CGRect { бумага }
        override var printableRect: CGRect { печать }
    }

    /// PDF из разметки. Пусто (форматтер не разметил ни одной страницы) — запасной путь: текст разметки как есть.
    static func собрать(_ разметка: String) -> Data {
        let готово = отрисовать(UIMarkupTextPrintFormatter(markupText: разметка))
        if !готово.isEmpty { return готово }
        let текст = простойТекст(разметка)
        return отрисовать(UISimpleTextPrintFormatter(text: текст))
    }

    private static func отрисовать(_ форматтер: UIPrintFormatter) -> Data {
        let рендер = РендерЛиста(бумага: лист, печать: лист.insetBy(dx: поле, dy: поле))
        рендер.addPrintFormatter(форматтер, startingAtPageAt: 0)
        let страниц = рендер.numberOfPages
        guard страниц > 0 else { return Data() }
        let данные = NSMutableData()
        UIGraphicsBeginPDFContextToData(данные, лист, nil)
        рендер.prepare(forDrawingPages: NSRange(location: 0, length: страниц))
        let рамка = UIGraphicsGetPDFContextBounds()
        for номер in 0..<страниц {
            UIGraphicsBeginPDFPage()
            рендер.drawPage(at: номер, in: рамка)
        }
        UIGraphicsEndPDFContext()
        return данные as Data
    }

    /// Разметка без тегов — для запасного пути.
    static func простойТекст(_ разметка: String) -> String {
        var s = разметка
        for шаблон in ["<style[\\s\\S]*?</style>", "<script[\\s\\S]*?</script>"] {
            s = s.replacingOccurrences(of: шаблон, with: "", options: [.regularExpression, .caseInsensitive])
        }
        for шаблон in ["<br\\s*/?>", "</p>", "</div>", "</tr>", "</h[1-6]>", "</li>"] {
            s = s.replacingOccurrences(of: шаблон, with: "\n", options: [.regularExpression, .caseInsensitive])
        }
        s = s.replacingOccurrences(of: "</td>", with: "\t", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let сущности: [(String, String)] = [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                             ("&quot;", "\""), ("&#39;", "'"), ("&laquo;", "«"), ("&raquo;", "»")]
        for (было, стало) in сущности { s = s.replacingOccurrences(of: было, with: стало) }
        s = s.replacingOccurrences(of: "\n[ \t]+", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// <base href> сайта в <head> — относительные ссылки и картинки документа указывают на kliko.kz.
    static func сБазой(_ разметка: String) -> String {
        let база = "<base href=\"" + Config.apiBase.absoluteString + "/\">"
        if let голова = разметка.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
            var итог = разметка
            итог.insert(contentsOf: база, at: голова.upperBound)
            return итог
        }
        return "<!DOCTYPE html><html><head><meta charset=\"utf-8\">" + база + "</head><body>" + разметка + "</body></html>"
    }

    /// Имя файла для «Поделиться»: заголовок без знаков, которых не любят файловые системы.
    static func имяФайла(_ заголовок: String) -> String {
        let запрещённые = CharacterSet(charactersIn: "/\\?%*|\"<>:#")
        let чистое = заголовок.components(separatedBy: запрещённые).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (чистое.isEmpty ? "Kliko" : String(чистое.prefix(80))) + ".pdf"
    }
}

// MARK: - Серверный документ

@MainActor
enum ДокументыСайта {
    enum Сбой: Error {
        case вход
        case нет
        case сеть
    }

    /// HTML документа по пути от корня (/escrow.php?action=…&id=, /cabinet.php?action=rent_contract&id=).
    static func разметка(_ путь: String) async throws -> String {
        let ответ: КабинетСайта.Ответ
        do {
            ответ = try await КабинетСайта.вызвать(путь, отКорня: true)
        } catch {
            throw Сбой.сеть
        }
        let текст = ответ.текст
        if let j = ответ.json {
            if МоиОбъявленияAPI.нетСессии(j) { throw Сбой.вход }
            throw Сбой.нет
        }
        guard ответ.код < 400, текст.range(of: "<", options: .literal) != nil else { throw Сбой.нет }
        /* Сервер вместо документа отдал страницу входа — сессии нет. */
        if текст.contains("action=login") && текст.contains("register_quick") { throw Сбой.вход }
        return текст
    }
}

// MARK: - Окно

/// Документ: колесо, пока собирается PDF, затем страницы PDFKit; «Поделиться» и «Печать» сверху.
struct ОкноДокумента: View {
    let документ: ДокументКабинета
    let закрыть: () -> Void

    @State private var pdf: Data? = nil
    @State private var файл: URL? = nil
    @State private var ошибка: String? = nil
    @State private var нуженВход = false
    @State private var входОткрыт = false

    private func т(_ ключ: String) -> String { ДокументыText.т(ключ) }

    var body: some View {
        NavigationStack {
            Group {
                if let pdf {
                    ПросмотрPDF(данные: pdf)
                        .ignoresSafeArea(edges: .bottom)
                } else if let ошибка {
                    ПустоСайта(значок: нуженВход ? "person.crop.circle" : "doc.questionmark", заголовок: ошибка,
                               кнопка: нуженВход ? CabinetText.т("login") : т("retry"),
                               действие: {
                        if нуженВход {
                            входОткрыт = true
                        } else {
                            Task { await собрать() }
                        }
                    })
                } else {
                    VStack(spacing: 12) {
                        SiteSpinner()
                        Text(т("making"))
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.текстВторой)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.фонСтраницы.ignoresSafeArea())
            .navigationTitle(документ.заголовок)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(т("close")) { закрыть() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let файл {
                        ShareLink(item: файл) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(т("share"))
                    }
                    if pdf != nil {
                        Button {
                            печать()
                        } label: {
                            Image(systemName: "printer")
                        }
                        .accessibilityLabel(т("print"))
                    }
                }
            }
        }
        .tint(Theme.акцент)
        .task { await собрать() }
        .sheet(isPresented: $входОткрыт) {
            ЭкранВхода(eGovВключён: true, открыть: { адрес in ПереходыКабинета.открыть(адрес) }, вошли: {
                Task { await собрать() }
            })
        }
    }

    private func собрать() async {
        ошибка = nil
        нуженВход = false
        pdf = nil
        let разметка: String
        switch документ.источник {
        case .разметка(let готовая):
            разметка = готовая
        case .путь(let путь):
            do {
                разметка = PDFизHTML.сБазой(try await ДокументыСайта.разметка(путь))
            } catch ДокументыСайта.Сбой.вход {
                нуженВход = true
                ошибка = CabinetText.т("signed_out")
                return
            } catch ДокументыСайта.Сбой.сеть {
                ошибка = т("no_conn")
                return
            } catch {
                ошибка = т("not_found")
                return
            }
        }
        /* Дать SwiftUI показать колесо до тяжёлой вёрстки на главной нити. */
        try? await Task.sleep(nanoseconds: 60_000_000)
        let данные = PDFизHTML.собрать(разметка)
        guard !данные.isEmpty else {
            ошибка = т("not_found")
            return
        }
        let адрес = FileManager.default.temporaryDirectory.appendingPathComponent(PDFизHTML.имяФайла(документ.заголовок))
        try? данные.write(to: адрес, options: .atomic)
        файл = FileManager.default.fileExists(atPath: адрес.path) ? адрес : nil
        pdf = данные
    }

    private func печать() {
        guard let pdf else { return }
        let окно = UIPrintInteractionController.shared
        let сведения = UIPrintInfo(dictionary: nil)
        сведения.outputType = .general
        сведения.jobName = документ.заголовок
        окно.printInfo = сведения
        окно.printingItem = pdf
        окно.present(animated: true, completionHandler: nil)
    }
}

/// PDFKit в SwiftUI: страницы по ширине экрана, прокрутка вниз.
struct ПросмотрPDF: UIViewRepresentable {
    let данные: Data

    final class Coordinator {
        var показаны: Data? = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let вид = PDFView()
        вид.autoScales = true
        вид.displayMode = .singlePageContinuous
        вид.displayDirection = .vertical
        вид.backgroundColor = UIColor.secondarySystemBackground
        вид.document = PDFDocument(data: данные)
        context.coordinator.показаны = данные
        return вид
    }

    func updateUIView(_ вид: PDFView, context: Context) {
        guard context.coordinator.показаны != данные else { return }
        context.coordinator.показаны = данные
        вид.document = PDFDocument(data: данные)
    }
}

// MARK: - Показ поверх любого экрана

@MainActor
enum ОкнаДокументов {
    /// Документ листом над верхним контроллером (встаёт и поверх другого листа).
    static func показать(_ документ: ДокументКабинета) {
        Task { @MainActor in
            for _ in 0..<12 {
                if let верх = ПереходыКабинета.верхнийКонтроллер() {
                    let хост = UIHostingController<AnyView>(rootView: AnyView(EmptyView()))
                    let закрыть: () -> Void = { [weak хост] in хост?.dismiss(animated: true) }
                    хост.rootView = AnyView(ОкноДокумента(документ: документ, закрыть: закрыть))
                    хост.modalPresentationStyle = .pageSheet
                    if let лист = хост.sheetPresentationController {
                        лист.detents = [.large()]
                        лист.prefersGrabberVisible = true
                    }
                    верх.present(хост, animated: true)
                    return
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }
}

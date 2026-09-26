import SwiftUI

/**
 «PDF» У КОММЕРЧЕСКОГО ПРЕДЛОЖЕНИЯ (kpPrintBranded сайта печатает КП окном браузера; владелец: «кабинет полностью
 SwiftUI»). Отправленное и полученное КП — свой документ PDF с «Поделиться» и «Печать» (ОкноДокумента): шапка, кому,
 позиции запроса и текст предложения (ДокументыБизнеса.кп).
 */
struct КнопкаPDFКП: View {
    let текст: String
    var кому: String = ""
    var от: String = ""
    var позиции: [(String, Int, Int)] = []

    var body: some View {
        Button {
            ОкнаДокументов.показать(ДокументКабинета(
                заголовок: БизнесРазделыText.т("kp_gen_title"),
                источник: .разметка(ДокументыБизнеса.кп(текст: текст, кому: кому, от: от, позиции: позиции))))
        } label: {
            Label("PDF", systemImage: "doc.richtext")
                .font(.system(size: 13, weight: .semibold))
        }
        .tint(Theme.акцент)
        .accessibilityHint(КабинетПлюсText.т("doc_open_hint"))
    }
}

import SwiftUI
import WidgetKit

/// Точка входа виджет-расширения: Live Activity сделки и виджет «Kliko» домашнего экрана (KlikoHomeWidget.swift).
@main
struct KlikoWidgetBundle: WidgetBundle {
    var body: some Widget {
        DealLiveActivity()
        KlikoHomeWidget()
    }
}

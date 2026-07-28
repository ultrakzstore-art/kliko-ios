import SwiftUI
import WidgetKit

/// Точка входа виджет-расширения. Пока один виджет — Live Activity сделки.
@main
struct KlikoWidgetBundle: WidgetBundle {
    var body: some Widget {
        DealLiveActivity()
    }
}

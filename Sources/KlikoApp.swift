import SwiftUI

@main
struct KlikoApp: App {
    var body: some Scene {
        WindowGroup {
            FeedView()
                .tint(Theme.green)
        }
    }
}

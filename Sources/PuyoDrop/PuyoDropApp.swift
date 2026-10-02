import SwiftUI

@main
struct PuyoDropApp: App {
    var body: some Scene {
        WindowGroup("PuyoDrop") {
            PuyoDropView()
        }
        .windowResizability(.contentSize)
    }
}

import SwiftUI

@main
struct DaysEngineApp: App {
    /// Held by the App so both the toolbar and the web view can reach it.
    @StateObject private var bridge = WebBridge()

    init() {
        AudioSessionController.configure()
    }

    var body: some Scene {
        WindowGroup {
            // A NavigationView wrapper is what makes the toolbar's reload/share items appear.
            NavigationView {
                ContentView()
                    .environmentObject(bridge)
                    .preferredColorScheme(.dark)
            }
            .navigationViewStyle(.stack)
        }
    }
}

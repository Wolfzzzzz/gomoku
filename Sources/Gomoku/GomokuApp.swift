import SwiftUI

@main
struct GomokuApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .frame(minWidth: 880, minHeight: 640)
        }
        .windowResizability(.contentSize)
    }
}

import SwiftUI

@main
struct MeetingTranscriptApplication: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container)
        }
        .windowStyle(.titleBar)
    }
}

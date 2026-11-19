import SwiftUI

@main
struct FabloApp: App {
    @State private var studio = StoryStudio()
    @State private var player = SpeechPlayer()

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            // A single reading column: the width is fixed, only the height follows the window.
            library.frame(width: 480).frame(minHeight: 600)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 480, height: 900)

        // Fablo ▸ Settings… (⌘,) opens the backend connection.
        Settings {
            BackendSettingsView()
                .environment(studio)
                .environment(player)
                .tint(Theme.accent)
        }
        #else
        WindowGroup { library }
        #endif
    }

    private var library: some View {
        LibraryView()
            .environment(studio)
            .environment(player)
            .tint(Theme.accent)
    }
}

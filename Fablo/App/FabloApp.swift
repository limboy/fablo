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
                .background(HiddenWindowButtons())
                // The hidden title bar still reserves its height; the in-content bars start at the top.
                .ignoresSafeArea(.container, edges: .top)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        // With the toolbar hidden, empty areas of the window are what you drag it by.
        .windowBackgroundDragBehavior(.enabled)
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

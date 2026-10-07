import SwiftData
import SwiftUI

@main
struct FabloApp: App {
    @State private var studio = StoryStudio()
    @State private var player = SpeechPlayer()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(studio)
                .environment(player)
                .tint(Theme.accent)
        }
        .modelContainer(for: Story.self)
    }
}

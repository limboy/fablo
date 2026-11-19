import SwiftUI

struct ReadingStatusMenu: View {
    let story: Story
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        Menu {
            ReadingStatusPicker(story: story) { message in
                errorMessage = message
                showingError = true
            }
        } label: {
            HStack(spacing: 6) {
                Label(story.readingStatus.title, systemImage: story.readingStatus.systemImage)
                if story.isUpdatingReadingStatus { ProgressView().controlSize(.mini) }
                else { Image(systemName: "chevron.down").font(.caption2.weight(.semibold)) }
            }
            .font(.subheadline.weight(.medium))
            #if os(iOS)
            .frame(minHeight: 44)
            #endif
            .contentShape(.rect)
        }
        // The label draws its own chevron; the Mac would add a second one.
        .menuIndicator(.hidden)
        .accessibilityLabel("阅读状态，\(story.readingStatus.title)")
        .accessibilityHint("切换待读、在读或已读")
        .disabled(story.isUpdatingReadingStatus)
        .alert("无法更新阅读状态", isPresented: $showingError) {
            Button("好", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }
}

/// The 待读 / 在读 / 已读 choices, for use inside a menu. Saves the choice on the server;
/// failures other than a rejected connection are passed to `onError`.
struct ReadingStatusPicker: View {
    let story: Story
    var onError: (String) -> Void
    @Environment(StoryStudio.self) private var studio

    var body: some View {
        Picker("阅读状态", selection: Binding(get: { story.readingStatus }, set: updateStatus)) {
            ForEach(ReadingStatus.allCases) { status in
                Label(status.title, systemImage: status.systemImage).tag(status)
            }
        }
        // List the options in the menu itself; the Mac would otherwise nest them in a submenu.
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private func updateStatus(_ status: ReadingStatus) {
        Task {
            do { try await story.setReadingStatus(status) }
            catch {
                if (error as? BackendError)?.invalidatesConnection == true { studio.rejectConnection(error) }
                else { onError(error.localizedDescription) }
            }
        }
    }
}

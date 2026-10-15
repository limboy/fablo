import SwiftUI

struct ReadingStatusMenu: View {
    let story: Story
    @Environment(StoryStudio.self) private var studio
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        Menu {
            Picker("阅读状态", selection: Binding(get: { story.readingStatus }, set: updateStatus)) {
                ForEach(ReadingStatus.allCases) { status in
                    Label(status.title, systemImage: status.systemImage).tag(status)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Label(story.readingStatus.title, systemImage: story.readingStatus.systemImage)
                if story.isUpdatingReadingStatus { ProgressView().controlSize(.mini) }
                else { Image(systemName: "chevron.down").font(.caption2.weight(.semibold)) }
            }
            .font(.subheadline.weight(.medium))
        }
        .accessibilityLabel("阅读状态，\(story.readingStatus.title)")
        .accessibilityHint("切换待读、在读或已读")
        .disabled(story.isUpdatingReadingStatus)
        .alert("无法更新阅读状态", isPresented: $showingError) {
            Button("好", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }

    private func updateStatus(_ status: ReadingStatus) {
        Task {
            do { try await story.setReadingStatus(status) }
            catch {
                if (error as? BackendError)?.invalidatesConnection == true { studio.rejectConnection(error) }
                else {
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

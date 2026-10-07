import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(StoryStudio.self) private var studio
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Story.createdAt, order: .reverse) private var stories: [Story]

    @State private var filter: StoryLanguage?
    @State private var showingNewStory = false

    private var visibleStories: [Story] {
        guard let filter else { return stories }
        return stories.filter { $0.language == filter }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    Picker("语言", selection: $filter) {
                        Text("全部").tag(StoryLanguage?.none)
                        ForEach(StoryLanguage.allCases) { language in
                            Text(language.nativeName).tag(Optional(language))
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 4)

                    ForEach(studio.jobs) { job in
                        JobCard(job: job)
                    }

                    ForEach(visibleStories) { story in
                        NavigationLink(value: story) {
                            StoryCard(story: story)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("重新生成封面", systemImage: "photo") {
                                studio.generateCover(for: story, in: modelContext)
                            }
                            Button("删除", systemImage: "trash", role: .destructive) {
                                modelContext.delete(story)
                                try? modelContext.save()
                            }
                        }
                    }

                    if stories.isEmpty && studio.jobs.isEmpty {
                        emptyState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Fablo")
            .toolbarTitleDisplayMode(.inlineLarge)
            .navigationDestination(for: Story.self) { story in
                ReaderView(story: story)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新短文", systemImage: "plus") { showingNewStory = true }
                        .buttonStyle(.glassProminent)
                }
            }
            .sheet(isPresented: $showingNewStory) {
                NewStoryView()
                    .presentationBackground(Theme.paper)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical.fill").font(.system(size: 50)).foregroundStyle(Theme.accent)
            Text("还没有短文").font(.title3.weight(.semibold))
            Text("选一个语言、难度和类型，\nAI 会为你写一篇专属读物。")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            Button("创作第一篇", systemImage: "sparkles") { showingNewStory = true }
                .buttonStyle(.glassProminent)
                .padding(.top, 6)
        }
        .padding(.top, 80)
    }
}

struct StoryCard: View {
    let story: Story

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoverView(story: story)
                .frame(height: 180)
                .clipped()
            VStack(alignment: .leading, spacing: 6) {
                Text(story.title)
                    .font(story.language == .ja ? .title3.weight(.bold) : .system(.title3, design: .serif, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(story.titleZh)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 6) {
                    TagLabel(text: "\(story.language.code) · \(story.level)")
                    TagLabel(text: story.genre, systemImage: story.genreSymbol)
                    Spacer()
                    Text(story.createdAt, format: .dateTime.month().day())
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
    }
}

private struct JobCard: View {
    let job: StoryStudio.Job
    @Environment(StoryStudio.self) private var studio
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: job.request.genre.symbol)
                .font(.system(size: 24))
                .foregroundStyle(Theme.accent)
                .frame(width: 56, height: 56)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 6) {
                Text("\(job.request.language.nativeName) \(job.request.level.name) · \(job.request.genre.rawValue) · \(job.request.length.label)")
                    .font(.subheadline.weight(.semibold))
                if let error = job.error {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
                    HStack {
                        Button("重试") { studio.retry(job.id, in: modelContext) }
                        Button("移除", role: .destructive) { studio.dismiss(job.id) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    TimelineView(.periodic(from: job.startedAt, by: 1)) { context in
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("正在创作并逐词标注… \(Int(context.date.timeIntervalSince(job.startedAt)))s")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

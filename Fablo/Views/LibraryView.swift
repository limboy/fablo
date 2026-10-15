import SwiftUI

struct LibraryView: View {
    @Environment(StoryStudio.self) private var studio
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SpeechPlayer.self) private var player

    @State private var filter: StoryLanguage = .en
    @State private var board: ReadingStatus = .unread
    @State private var showingNewStory = false
    @State private var showingBackendSettings = false
    @State private var path: [Story] = []

    private var stories: [Story] { studio.stories }

    private var languageEntries: [LibraryEntry] { LibraryEntry.make(stories: stories, jobs: studio.jobs, language: filter) }
    private var entries: [LibraryEntry] { languageEntries.filter { $0.readingStatus == board } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 18) {
                    if let error = studio.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(error).font(.callout).foregroundStyle(studio.isShowingCachedLibrary ? Theme.muted : .red)
                            Button("重试") { Task { await studio.refresh() } }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(entries) { entry in
                        LibraryEntryCard(entry: entry)
                    }

                    if entries.isEmpty {
                        if !studio.hasLoadedConnection || (stories.isEmpty && studio.jobs.isEmpty && studio.isRefreshing) {
                            ProgressView("正在读取书库…").padding(.top, 80)
                        } else if !stories.isEmpty || !studio.jobs.isEmpty {
                            ContentUnavailableView("没有\(board.title)的\(filter.chineseName)短文", systemImage: board.systemImage,
                                                   description: Text(board == .unread ? "切换看板，或创作一篇新短文。" : "在短文卡片的状态菜单中，将短文移到这里。"))
                        } else {
                            emptyState
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(Theme.paper.ignoresSafeArea())
            .refreshable { await studio.refresh() }
            .safeAreaInset(edge: .bottom, spacing: 0) { readingBoards }
            .toolbarTitleDisplayMode(.inline)
            .navigationDestination(for: Story.self) { story in
                ReaderView(story: story)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("连接服务", systemImage: "gearshape") { showingBackendSettings = true }
                }
                ToolbarItem(placement: .principal) {
                    Picker("语言", selection: $filter) {
                        ForEach(StoryLanguage.allCases) { language in
                            Text(language.chineseName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("新短文", systemImage: "plus") { showingNewStory = true }
                        .buttonStyle(.glassProminent)
                        .disabled(!studio.isConfigured)
                }
            }
            .sheet(isPresented: $showingNewStory) {
                NewStoryView()
                    .presentationBackground(Theme.paper)
            }
            .sheet(isPresented: $showingBackendSettings) { BackendSettingsView() }
            .task(id: scenePhase) {
                if scenePhase == .active { await studio.observe() }
            }
            .onChange(of: studio.connectionID) { _, _ in
                player.stop()
                path = []
            }
            .onChange(of: stories.map(\.id)) { _, ids in
                if let current = path.last, !ids.contains(current.id) {
                    player.stop()
                    path = []
                }
            }
        }
    }

    private var readingBoards: some View {
        HStack(spacing: 6) {
            ForEach(ReadingStatus.allCases) { status in
                let count = languageEntries.filter { $0.readingStatus == status }.count
                Button {
                    board = status
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: status.systemImage).font(.system(size: 19, weight: .semibold))
                        HStack(spacing: 4) {
                            Text(status.title)
                            Text(count, format: .number).monospacedDigit()
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(board == status ? .white : Theme.muted)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 58)
                    .background(board == status ? Theme.accent : .clear, in: Capsule())
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(status.title)，\(count)篇短文")
                .accessibilityAddTraits(board == status ? .isSelected : [])
            }
        }
        // Keep selection animation in the controls so lazy cards appear at their final positions.
        .animation(.snappy(duration: 0.25), value: board)
        .padding(6)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical.fill").font(.system(size: 50)).foregroundStyle(Theme.accent)
            Text(studio.isConfigured ? "还没有短文" : "连接你的书库").font(.title3.weight(.semibold))
            Text(studio.isConfigured ? "选一个语言、难度和类型，\nAI 会为你写一篇专属读物。" : "连接服务后，即可阅读和创作短文。")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.muted)
            Button(studio.isConfigured ? "创作第一篇" : "连接服务", systemImage: studio.isConfigured ? "sparkles" : "network") {
                if studio.isConfigured { showingNewStory = true } else { showingBackendSettings = true }
            }
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
                if let request = story.generationRequest, !request.topic.isEmpty {
                    Text(request.topic)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .padding(.top, 4)
                }
                HStack(spacing: 6) {
                    TagLabel(text: "\(story.language.code) · \(story.level)")
                    TagLabel(text: story.genre, systemImage: story.genreSymbol)
                    if let request = story.generationRequest {
                        TagLabel(text: request.length.label)
                    }
                    Spacer()
                    Text(story.createdAt, format: .dateTime.month().day())
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.top, 4)
            }
            .padding(16)
        }
    }
}

private struct LibraryEntryCard: View {
    let entry: LibraryEntry
    @Environment(StoryStudio.self) private var studio

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let story = entry.story {
                NavigationLink(value: story) {
                    StoryCard(story: story)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                HStack {
                    ReadingStatusMenu(story: story)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: entry.request?.storyRequest.genre.symbol ?? "sparkles")
                        .font(.system(size: 24)).foregroundStyle(Theme.accent)
                        .frame(width: 56, height: 56)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 6) {
                        if let request = entry.request?.storyRequest {
                            Text("\(request.language.nativeName) · \(request.level.name)")
                                .font(.subheadline.weight(.semibold))
                            Text("\(request.genre.rawValue) · \(request.length.label)")
                                .font(.caption).foregroundStyle(Theme.muted)
                            if !request.topic.isEmpty {
                                Text(request.topic).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                            }
                        } else {
                            Text("正在准备短文").font(.subheadline.weight(.semibold))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
            if !entry.jobs.isEmpty {
                if entry.story != nil { Divider().padding(.horizontal, 16) }
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(entry.jobs) { job in JobStatusRow(job: job) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, entry.story == nil ? 0 : 16)
            }
        }
        .background(Theme.raised)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        .contextMenu {
            if let story = entry.story {
                Button("重新生成封面", systemImage: "photo") { studio.generateCover(for: story) }
                Button("重新生成音频", systemImage: "waveform") { studio.generateAudio(for: story) }
                Button("删除", systemImage: "trash", role: .destructive) { studio.delete(story) }
            }
        }
    }
}

private struct JobStatusRow: View {
    let job: BackendJob
    @Environment(StoryStudio.self) private var studio

    private var resource: String {
        switch job.kind {
        case "cover": return "封面"
        case "audio": return "音频"
        case "analysis": return "第 \((job.sentenceIndex ?? 0) + 1) 句解析"
        default: return "短文"
        }
    }

    private var status: String {
        if job.status == "failed" { return "\(resource)生成失败" }
        if job.status == "queued" { return "\(resource)等待处理…" }
        switch job.kind {
        case "cover": return "正在绘制封面…"
        case "audio": return "正在生成朗读音频…"
        case "analysis": return "正在解析第 \((job.sentenceIndex ?? 0) + 1) 句…"
        default: return "正在创作并逐词标注…"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if job.isActive { ProgressView().controlSize(.small) }
                else { Image(systemName: "exclamationmark.circle").foregroundStyle(.red) }
                Text(status).font(.caption).foregroundStyle(job.status == "failed" ? .red : Theme.muted)
                Spacer(minLength: 0)
                if job.isActive {
                    TimelineView(.periodic(from: Story.date(job.createdAt), by: 1)) { context in
                        Text("\(max(0, Int(context.date.timeIntervalSince(Story.date(job.createdAt)))))s")
                            .font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                    }
                }
            }
            if job.status == "failed" {
                if let error = job.error { Text(error).font(.caption).foregroundStyle(.red).lineLimit(3) }
                HStack {
                    Button("重试") { studio.retry(job.id) }
                    Button("忽略") { studio.dismiss(job.id) }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

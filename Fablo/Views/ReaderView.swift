import SwiftUI

struct ReaderView: View {
    let story: Story

    @Environment(SpeechPlayer.self) private var player
    @Environment(StoryStudio.self) private var studio

    @AppStorage("showFurigana") private var showFurigana = true
    @AppStorage("showRomaji") private var showRomaji = true
    @AppStorage("showAllTranslations") private var showAllTranslations = false
    @AppStorage("speechRate") private var speechRate = 1.0
    @AppStorage("loopPlayback") private var loopPlayback = false

    @State private var content: StoryContent?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedID: Int?
    @State private var analysisTarget: SentenceRef?
    @State private var scrollPosition = ScrollPosition(idType: Int.self)

    private var options: ReadingOptions {
        ReadingOptions(showFurigana: showFurigana, showRomaji: showRomaji)
    }

    private var isPlayingThisStory: Bool { player.storyID == story.id }
    private var speakingID: Int? { isPlayingThisStory ? player.currentID : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let content {
                    let all = content.allSentences
                    let paragraphEnds = Set(content.numberedParagraphs.compactMap { $0.last?.id })
                    ForEach(all) { ref in
                        sentenceView(ref)
                            .padding(.bottom, sentenceSpacing(after: ref.id, paragraphEnds: paragraphEnds))
                    }
                } else if isLoading {
                    ProgressView("正在读取短文…").frame(maxWidth: .infinity).padding(.vertical, 40)
                } else {
                    VStack(spacing: 12) {
                        Text(errorMessage ?? "无法读取这篇短文").foregroundStyle(Theme.muted)
                        Button("重试") { Task { await load() } }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 12)
            .padding(.bottom, 120)
        }
        .scrollPosition($scrollPosition, anchor: .center)
        .onChange(of: speakingID) { _, id in
            // Only follow playback when it moves on; the sentence the reader just tapped is already in view.
            guard let id, id != selectedID else { return }
            withAnimation(.snappy) {
                selectedID = id
                scrollPosition.scrollTo(id: id, anchor: .center)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ReadingStatusMenu(story: story) }
            ToolbarItem(placement: .topBarTrailing) { settingsMenu }
        }
        .safeAreaInset(edge: .bottom) { playbackBar }
        .sheet(item: $analysisTarget) { ref in
            if let content {
                AnalysisView(story: story, content: content, ref: ref)
            }
        }
        .task { await load() }
        .onDisappear {
            if isPlayingThisStory { player.stop() }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoverView(story: story)
                .aspectRatio(3 / 2, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if story.coverData == nil, story.coverFailed {
                        Button("重新生成封面", systemImage: "arrow.clockwise") {
                            studio.generateCover(for: story)
                        }
                        .buttonStyle(.glass)
                        .padding(12)
                    }
                }
                .padding(.bottom, 8)

            Text(story.title)
                .font(story.language == .ja ? .system(size: 28, weight: .bold) : .system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text(story.titleZh)
                .font(.title3)
                .foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                TagLabel(text: "\(story.language.code) · \(story.level)")
                TagLabel(text: story.genre, systemImage: story.genreSymbol)
            }
            if !story.summaryZh.isEmpty {
                Text(story.summaryZh)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 2)
            }
            Text("点击句子查看翻译与成分，点击「解析」看详细讲解")
                .font(.caption)
                .foregroundStyle(Theme.muted.opacity(0.8))
                .padding(.top, 6)
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 30)
    }

    // MARK: Sentences

    private func load() async {
        errorMessage = nil
        defer { isLoading = false }
        content = story.decodedContent()
        isLoading = content == nil
        if content == nil, let cached = await story.client.cachedStory(story.id) {
            guard !Task.isCancelled else { return }
            story.restoreCachedDetails(cached)
            content = story.decodedContent()
            isLoading = content == nil
        }
        if let content { StoryAudioStore.shared.prepare(StoryAudioSource(story: story, content: content)) }
        do {
            let record = try await story.client.story(story.id)
            guard !Task.isCancelled else { return }
            story.apply(record)
            content = story.decodedContent()
            if let content { StoryAudioStore.shared.prepare(StoryAudioSource(story: story, content: content)) }
        } catch {
            guard !Task.isCancelled, !(error is CancellationError) else { return }
            if case BackendError.http(404, _) = error {
                content = nil
                studio.removeMissingStory(story.id)
            } else if (error as? BackendError)?.invalidatesConnection == true {
                content = nil
                studio.rejectConnection(error)
            }
            if content == nil { errorMessage = error.localizedDescription }
        }
    }

    private func sentenceView(_ ref: SentenceRef) -> some View {
        SentenceView(
            ref: ref,
            language: story.language,
            options: options,
            isSelected: selectedID == ref.id,
            isSpeaking: speakingID == ref.id,
            speakingWord: speakingID == ref.id ? player.currentWord : nil,
            showTranslation: showAllTranslations,
            onSelect: {
                withAnimation(.snappy(duration: 0.25)) {
                    selectedID = selectedID == ref.id ? nil : ref.id
                }
            },
            onPlay: {
                if speakingID == ref.id {
                    player.stop()
                } else {
                    play(from: ref.id, continuous: false)
                }
            },
            onAnalyze: { analysisTarget = ref }
        )
    }

    private func sentenceSpacing(after id: Int, paragraphEnds: Set<Int>) -> CGFloat {
        let isJapanese = story.language == .ja
        if paragraphEnds.contains(id) { return isJapanese ? 52 : 36 }
        return isJapanese ? 32 : 20
    }

    private func play(from id: Int, continuous: Bool) {
        guard let content else { return }
        player.play(StoryAudioSource(story: story, content: content), from: id, rate: speechRate,
                    continuous: continuous, looping: loopPlayback)
    }

    // MARK: Chrome

    private var settingsMenu: some View {
        Menu {
            if story.language == .ja {
                Toggle("显示假名", systemImage: "textformat.size.smaller", isOn: $showFurigana)
                Toggle("显示罗马音", systemImage: "character.textbox", isOn: $showRomaji)
            }
            Toggle("显示全部翻译", systemImage: "translate", isOn: $showAllTranslations)
        } label: {
            Image(systemName: "textformat")
        }
    }

    /// Controls in the bar share one height and sit `barInset` from every edge of the capsule.
    private static let barControlHeight: CGFloat = 40
    private static let barInset: CGFloat = 6

    private var playbackBar: some View {
        HStack(spacing: 12) {
            Button(action: togglePlayAll) {
                Image(systemName: isPlayingThisStory && player.isPlayingAll && !player.isPaused ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: Self.barControlHeight, height: Self.barControlHeight)
                    .background(Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(content == nil)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.subheadline.weight(.semibold))
                Text(statusSubtitle).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            if isPlayingThisStory && player.isLoading {
                ProgressView()
            }
            loopButton
            rateMenu
        }
        .padding(Self.barInset)
        .background {
            // Keep the menu's Liquid Glass transition scoped to its own label.
            Capsule()
                .fill(.clear)
                .glassEffect(.regular, in: .capsule)
                .allowsHitTesting(false)
        }
        // The whole capsule is the control; otherwise taps fall through to the sentences underneath.
        .contentShape(.capsule)
        .onTapGesture(perform: togglePlayAll)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var loopButton: some View {
        Button {
            loopPlayback.toggle()
        } label: {
            Image(systemName: "repeat")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(loopPlayback ? Theme.accent : Theme.muted)
                .frame(width: Self.barControlHeight, height: Self.barControlHeight)
                .background(loopPlayback ? Theme.accent.opacity(0.15) : Theme.card, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(loopPlayback ? "循环播放：开" : "循环播放：关")
        .onChange(of: loopPlayback) { _, looping in player.setLooping(looping) }
    }

    private static let rates = [0.5, 0.75, 1.0, 1.25, 1.5]

    private var rateMenu: some View {
        Menu {
            Picker("语速", selection: $speechRate) {
                ForEach(Self.rates, id: \.self) { rate in
                    Text(Self.rateLabel(rate)).tag(rate)
                }
            }
        } label: {
            Text(Self.rateLabel(speechRate))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .frame(minWidth: 56, minHeight: Self.barControlHeight)
                .background(Theme.card, in: Capsule())
        }
        .accessibilityLabel("语速 \(Self.rateLabel(speechRate))")
        .onChange(of: speechRate) { _, rate in player.setRate(rate) }
    }

    private static func rateLabel(_ rate: Double) -> String {
        String(format: "%g×", rate)
    }

    private func togglePlayAll() {
        if isPlayingThisStory && player.isPlayingAll {
            player.isPaused ? player.resume() : player.pause()
        } else {
            play(from: selectedID ?? 0, continuous: true)
        }
    }

    private var statusTitle: String {
        if isPlayingThisStory, let id = player.currentID {
            if player.isLoading { return "正在准备朗读音频…" }
            return player.isPaused ? "已暂停 · 第 \(id + 1) 句" : "正在朗读第 \(id + 1) 句"
        }
        if let selectedID { return "从第 \(selectedID + 1) 句开始朗读" }
        return "朗读全文"
    }

    private var statusSubtitle: String {
        if let error = player.errorMessage { return error }
        let count = content?.allSentences.count ?? 0
        return "\(count) 句"
    }
}

struct CoverView: View {
    let story: Story
    @Environment(StoryStudio.self) private var studio
    @State private var loadingFailed = false

    var body: some View {
        ZStack {
            if let data = story.coverData, let image = UIImage(data: data) {
                Color.clear.overlay {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                .clipped()
            } else {
                LinearGradient(
                    colors: [Theme.accent.opacity(0.35), Theme.card],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(spacing: 8) {
                    Image(systemName: story.genreSymbol).font(.system(size: 40)).foregroundStyle(Theme.accent.opacity(0.7))
                    if studio.coversInProgress.contains(story.id) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("正在绘制封面…").font(.caption)
                        }
                        .foregroundStyle(Theme.muted)
                    } else if loadingFailed {
                        Button("重新加载封面") { Task { await loadCover() } }
                            .font(.caption)
                    }
                }
            }
        }
        .task(id: story.coverVersion) { await loadCover() }
    }

    private func loadCover() async {
        guard let version = story.coverVersion, story.coverData == nil else { return }
        loadingFailed = false
        do {
            let data = try await story.client.asset("cover", storyID: story.id, version: version)
            guard !Task.isCancelled, story.coverVersion == version else { return }
            story.coverData = data
        } catch { if !Task.isCancelled { loadingFailed = true } }
    }
}

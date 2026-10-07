import SwiftData
import SwiftUI

struct ReaderView: View {
    let story: Story

    @Environment(SpeechPlayer.self) private var player
    @Environment(StoryStudio.self) private var studio
    @Environment(\.modelContext) private var modelContext

    @AppStorage("showFurigana") private var showFurigana = true
    @AppStorage("showRomaji") private var showRomaji = true
    @AppStorage("showAllTranslations") private var showAllTranslations = false
    @AppStorage("speechRate") private var speechRate = 1.0

    @State private var content: StoryContent?
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
                        sentenceView(ref, all: all)
                            .padding(.bottom, sentenceSpacing(after: ref.id, paragraphEnds: paragraphEnds))
                    }
                } else {
                    ContentUnavailableView("无法读取这篇短文", systemImage: "exclamationmark.triangle")
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 12)
            .padding(.bottom, 120)
        }
        .scrollPosition($scrollPosition, anchor: .center)
        .onChange(of: speakingID) { _, id in
            guard let id else { return }
            withAnimation(.snappy) {
                selectedID = id
                scrollPosition.scrollTo(id: id, anchor: .center)
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { settingsMenu }
        }
        .safeAreaInset(edge: .bottom) { playbackBar }
        .sheet(item: $analysisTarget) { ref in
            if let content {
                AnalysisView(story: story, content: content, ref: ref)
            }
        }
        .task {
            if content == nil { content = story.decodedContent() }
        }
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
                            studio.generateCover(for: story, in: modelContext)
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

    private func sentenceView(_ ref: SentenceRef, all: [SentenceRef]) -> some View {
        SentenceView(
            ref: ref,
            language: story.language,
            options: options,
            isSelected: selectedID == ref.id,
            isSpeaking: speakingID == ref.id,
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
                    play(from: ref.id, all: all, continuous: false)
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

    private func play(from id: Int, all: [SentenceRef], continuous: Bool) {
        player.play(
            all.map { SpeechPlayer.Item(id: $0.id, text: $0.sentence.text) },
            from: id,
            storyID: story.id,
            language: story.language,
            level: story.level,
            rate: speechRate,
            continuous: continuous
        )
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

    private var playbackBar: some View {
        HStack(spacing: 12) {
            Button(action: togglePlayAll) {
                Image(systemName: isPlayingThisStory && player.isPlayingAll ? "stop.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle).font(.subheadline.weight(.semibold))
                Text(statusSubtitle).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer()
            if isPlayingThisStory && player.isLoading {
                ProgressView()
            }
            rateMenu
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .capsule)
        // The whole capsule is the control; otherwise taps fall through to the sentences underneath.
        .contentShape(.capsule)
        .onTapGesture(perform: togglePlayAll)
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
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
                .frame(minWidth: 44)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
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
            player.stop()
        } else if let content {
            let all = content.allSentences
            play(from: selectedID ?? all.first?.id ?? 0, all: all, continuous: true)
        }
    }

    private var statusTitle: String {
        if isPlayingThisStory, let id = player.currentID {
            return player.isLoading ? "正在生成第 \(id + 1) 句语音…" : "正在朗读第 \(id + 1) 句"
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
                    }
                }
            }
        }
    }
}

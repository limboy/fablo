import SwiftData
import SwiftUI

struct AnalysisView: View {
    let story: Story
    let content: StoryContent
    let ref: SentenceRef

    @Environment(\.modelContext) private var modelContext
    @Environment(SpeechPlayer.self) private var player
    @AppStorage("speechRate") private var speechRate = 1.0

    @State private var analysis: SentenceAnalysis?
    @State private var errorMessage: String?

    private var isSpeaking: Bool { player.storyID == story.id && player.currentID == ref.id }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    sentenceCard
                    componentLegend
                    if let analysis {
                        sections(analysis)
                    } else if let errorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(errorMessage).foregroundStyle(.red).font(.callout)
                            Button("重试", systemImage: "arrow.clockwise") { Task { await load() } }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("AI 老师正在解析这句话…").foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
            .background(Theme.paper)
            .navigationTitle("第 \(ref.id + 1) 句解析")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .presentationBackground(Theme.paper)
        .task { await load() }
    }

    private var sentenceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SentenceFlow(
                sentence: ref.sentence,
                language: story.language,
                options: ReadingOptions(),
                annotated: true
            )
            Text(ref.sentence.zh)
                .font(.system(size: 16))
                .foregroundStyle(Theme.muted)
            Button {
                if isSpeaking {
                    player.stop()
                } else {
                    let items = content.allSentences.map { SpeechPlayer.Item(id: $0.id, text: $0.sentence.text) }
                    player.play(items, from: ref.id, storyID: story.id, language: story.language,
                                level: story.level, rate: speechRate, continuous: false)
                }
            } label: {
                Label(isSpeaking ? "停止" : "朗读", systemImage: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    /// Lists each chunk with its grammatical role, using the same colors as the sentence.
    private var componentLegend: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("句子成分")
            FlowLayout(lineSpacing: 8) {
                ForEach(Array(ref.sentence.chunks.enumerated()), id: \.offset) { _, chunk in
                    HStack(spacing: 6) {
                        Text(chunk.role.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.muted)
                        Text(chunk.text)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.chunk(chunk.role) ?? Theme.card, in: RoundedRectangle(cornerRadius: 10))
                    .flowGap(8)
                }
            }
            posLegend
        }
    }

    private var posLegend: some View {
        let used = PartOfSpeech.allCases.filter { pos in
            Theme.pos(pos) != nil && ref.sentence.chunks.contains { $0.words.contains { $0.pos == pos } }
        }
        return FlowLayout(lineSpacing: 6) {
            ForEach(used, id: \.self) { pos in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.pos(pos) ?? .clear)
                        .frame(width: 16, height: 6)
                    Text(pos.label).font(.caption).foregroundStyle(Theme.muted)
                }
                .flowGap(12)
            }
        }
    }

    @ViewBuilder
    private func sections(_ analysis: SentenceAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("结构")
            Text(analysis.structure).lineSpacing(5)
        }

        if !analysis.grammar.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("语法点")
                ForEach(analysis.grammar, id: \.self) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.point).font(.headline).foregroundStyle(Theme.accent)
                        Text(item.explanation).lineSpacing(4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.example).font(.callout.weight(.medium))
                            Text(item.exampleZh).font(.callout).foregroundStyle(Theme.muted)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(14)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }

        if !analysis.vocabulary.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("词汇")
                VStack(spacing: 0) {
                    ForEach(Array(analysis.vocabulary.enumerated()), id: \.offset) { index, item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(item.word).font(.headline)
                                if !item.reading.isEmpty {
                                    Text(item.reading).font(.subheadline).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Text(item.meaning).font(.subheadline)
                            }
                            if !item.note.isEmpty {
                                Text(item.note).font(.footnote).foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.vertical, 10)
                        if index < analysis.vocabulary.count - 1 { Divider() }
                    }
                }
                .padding(.horizontal, 14)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }

        if !analysis.nuance.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionTitle("语感提示")
                Text(analysis.nuance)
                    .lineSpacing(4)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.muted)
    }

    private func load() async {
        if let cached = story.analysis(for: ref.id) {
            analysis = cached
            return
        }
        errorMessage = nil
        do {
            let result = try await StoryGenerator.analyze(index: ref.id, in: content, language: story.language, level: story.level)
            story.setAnalysis(result, for: ref.id)
            try? modelContext.save()
            analysis = result
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

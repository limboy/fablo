import SwiftUI

/// Wraps subviews onto lines; each subview can request extra leading space via `.flowGap(_:)`,
/// which is dropped at the start of a line.
struct FlowLayout: Layout {
    var lineSpacing: CGFloat = 6

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(for subviews: Subviews, maxWidth: CGFloat) -> ([Line], [CGSize], [CGFloat]) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var offsets = Array(repeating: CGFloat.zero, count: subviews.count)
        var lines: [Line] = [Line()]
        for (index, subview) in subviews.enumerated() {
            let gap = lines[lines.count - 1].indices.isEmpty ? 0 : subview[FlowGap.self]
            if !lines[lines.count - 1].indices.isEmpty, lines[lines.count - 1].width + gap + sizes[index].width > maxWidth {
                lines.append(Line())
            }
            let actualGap = lines[lines.count - 1].indices.isEmpty ? 0 : gap
            offsets[index] = lines[lines.count - 1].width + actualGap
            lines[lines.count - 1].indices.append(index)
            lines[lines.count - 1].width += actualGap + sizes[index].width
            lines[lines.count - 1].height = max(lines[lines.count - 1].height, sizes[index].height)
        }
        return (lines, sizes, offsets)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let (lines, _, _) = lines(for: subviews, maxWidth: maxWidth)
        let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(lines.count - 1, 0))
        let width = proposal.width ?? lines.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (lines, sizes, offsets) = lines(for: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for line in lines {
            for index in line.indices {
                subviews[index].place(
                    at: CGPoint(x: bounds.minX + offsets[index], y: y),
                    proposal: ProposedViewSize(sizes[index])
                )
            }
            y += line.height + lineSpacing
        }
    }
}

private struct FlowGap: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

extension View {
    func flowGap(_ gap: CGFloat) -> some View { layoutValue(key: FlowGap.self, value: gap) }
}

struct ReadingOptions {
    var showFurigana = true
    var showRomaji = true
}

/// Renders a sentence word by word. When `annotated` is on, chunks get role backgrounds
/// and words get a part-of-speech highlighter underline.
struct SentenceFlow: View {
    let sentence: Sentence
    let language: StoryLanguage
    let options: ReadingOptions
    let annotated: Bool
    var onWordTap: ((Word) -> Void)?

    private struct Cell: Identifiable {
        let id: Int
        let word: Word
        let role: ChunkRole
        let isChunkStart: Bool
        let isChunkEnd: Bool
    }

    private var cells: [Cell] {
        var result: [Cell] = []
        for chunk in sentence.chunks {
            for (offset, word) in chunk.words.enumerated() {
                result.append(Cell(
                    id: result.count,
                    word: word,
                    role: chunk.role,
                    isChunkStart: offset == 0,
                    isChunkEnd: offset == chunk.words.count - 1
                ))
            }
        }
        return result
    }

    var body: some View {
        let cells = cells
        FlowLayout(lineSpacing: language == .ja ? 10 : 8) {
            ForEach(cells) { cell in
                WordCell(
                    word: cell.word,
                    language: language,
                    options: options,
                    chunkColor: annotated ? Theme.chunk(cell.role) : nil,
                    underline: annotated ? Theme.pos(cell.word.pos) : nil,
                    roundLeading: cell.isChunkStart,
                    roundTrailing: cell.isChunkEnd
                )
                .flowGap(gap(for: cell, in: cells))
                .contentShape(Rectangle())
                .onTapGesture { onWordTap?(cell.word) }
                .allowsHitTesting(onWordTap != nil)
            }
        }
    }

    private func gap(for cell: Cell, in cells: [Cell]) -> CGFloat {
        guard cell.id > 0 else { return 0 }
        if language == .ja {
            return cell.isChunkStart && cell.word.pos != .punctuation ? 10 : 0
        }
        // English: words already carry WordCell.englishPadding on each side, which reads as a space.
        let previous = cells[cell.id - 1]
        let hug = -WordCell.englishPadding
        if isOpening(previous, in: cells) { return hug }
        if cell.word.pos == .punctuation {
            return isOpening(cell, in: cells) ? 2 * WordCell.englishPadding : hug
        }
        if previous.word.pos == .punctuation { return 2 * WordCell.englishPadding }
        return cell.isChunkStart && annotated ? 5 : 0
    }

    /// Opening brackets/quotes attach to the following word; straight quotes alternate open/close.
    private func isOpening(_ cell: Cell, in cells: [Cell]) -> Bool {
        let s = cell.word.surface
        if ["“", "‘", "(", "[", "「", "『"].contains(s) { return true }
        guard s == "\"" || s == "'" else { return false }
        let earlier = cells[..<cell.id].filter { $0.word.surface == s }.count
        return earlier.isMultiple(of: 2)
    }
}

struct WordCell: View {
    let word: Word
    let language: StoryLanguage
    let options: ReadingOptions
    let chunkColor: Color?
    let underline: Color?
    let roundLeading: Bool
    let roundTrailing: Bool

    static let englishPadding: CGFloat = 2.5

    private var isJapanese: Bool { language == .ja }
    private var isPunctuation: Bool { word.pos == .punctuation }

    var body: some View {
        VStack(spacing: 1) {
            if isJapanese && options.showFurigana {
                Text(word.furigana ?? " ")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(word.surface)
                .font(isJapanese ? .system(size: 24, weight: .bold) : .system(size: 21, weight: .medium, design: .serif))
                .foregroundStyle(Theme.ink)
                .fixedSize()
                .background(alignment: .bottom) {
                    if let underline {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(underline)
                            .frame(height: 7)
                            .padding(.horizontal, -1)
                            .offset(y: 2)
                    }
                }
                .padding(.horizontal, isJapanese ? (isPunctuation ? 2 : 5) : (isPunctuation ? 0 : Self.englishPadding))
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity)
                .background {
                    if let chunkColor {
                        UnevenRoundedRectangle(
                            topLeadingRadius: roundLeading ? 10 : 0,
                            bottomLeadingRadius: roundLeading ? 10 : 0,
                            bottomTrailingRadius: roundTrailing ? 10 : 0,
                            topTrailingRadius: roundTrailing ? 10 : 0
                        )
                        .fill(chunkColor)
                    }
                }
            if isJapanese && options.showRomaji {
                Text(word.romaji.isEmpty ? " " : word.romaji)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One sentence in the reader: plain when idle; a highlighted card with translation and actions when selected.
struct SentenceView: View {
    let ref: SentenceRef
    let language: StoryLanguage
    let options: ReadingOptions
    let isSelected: Bool
    let isSpeaking: Bool
    let showTranslation: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void
    let onAnalyze: () -> Void

    @State private var tappedWord: WordBox?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SentenceFlow(
                sentence: ref.sentence,
                language: language,
                options: options,
                annotated: isSelected,
                onWordTap: isSelected ? { tappedWord = WordBox(word: $0) } : nil
            )

            if isSelected || showTranslation {
                Text(ref.sentence.zh)
                    .font(.system(size: isSelected ? 19 : 16))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isSelected {
                HStack(spacing: 10) {
                    Button(action: onPlay) {
                        Label(isSpeaking ? "停止" : "朗读", systemImage: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                    }
                    .buttonStyle(.bordered)
                    Button(action: onAnalyze) {
                        Label("解析", systemImage: "text.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .font(.subheadline.weight(.semibold))
                .controlSize(.small)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(isSelected ? 18 : 0)
        .padding(.horizontal, isSelected ? 0 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Theme.card)
            } else if isSpeaking {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.accent.opacity(0.10))
                    .padding(-6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .sheet(item: $tappedWord) { box in
            WordDetailView(word: box.word, language: language)
                .presentationDetents([.height(220)])
        }
        .animation(.snappy(duration: 0.25), value: isSelected)
    }
}

private struct WordBox: Identifiable {
    let id = UUID()
    let word: Word
}

struct WordDetailView: View {
    let word: Word
    let language: StoryLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(word.surface).font(.system(size: 34, weight: .bold))
                if language == .ja, !word.reading.isEmpty, word.reading != word.surface {
                    Text(word.reading).font(.title3).foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            if language == .ja, !word.romaji.isEmpty {
                Text(word.romaji).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 8) {
                TagLabel(text: word.pos.label, color: Theme.pos(word.pos) ?? Theme.card)
                if !word.gloss.isEmpty {
                    Text(word.gloss).font(.title3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationBackground(Theme.paper)
    }
}

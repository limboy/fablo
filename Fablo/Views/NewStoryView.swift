import SwiftUI

struct NewStoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StoryStudio.self) private var studio

    @AppStorage("lastLanguage") private var language: StoryLanguage = .ja
    @AppStorage("lastLevel.en") private var enLevel = "B1"
    @AppStorage("lastLevel.ja") private var jaLevel = "N4"
    @AppStorage("lastGenre") private var genreRaw = StoryGenre.fable.rawValue
    @AppStorage("lastLength") private var lengthRaw = StoryLength.short.rawValue
    @State private var topic = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var submissionKey = UUID()
    @State private var lastRequest: StoryRequest?

    private var levelID: Binding<String> {
        language == .en ? $enLevel : $jaLevel
    }

    private var level: StoryLevel {
        language.levels.first { $0.id == levelID.wrappedValue } ?? language.levels[1]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    section("语言") {
                        HStack(spacing: 12) {
                            ForEach(StoryLanguage.allCases) { option in
                                languageTile(option)
                            }
                        }
                    }

                    section("难度") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                ForEach(language.levels) { option in
                                    chip(option.name, selected: option.id == level.id) {
                                        levelID.wrappedValue = option.id
                                    }
                                }
                            }
                            Text(level.summary)
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                    }

                    section("类型") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(StoryGenre.allCases) { genre in
                                chip(genre.rawValue, systemImage: genre.symbol, selected: genre.rawValue == genreRaw, fill: true) {
                                    genreRaw = genre.rawValue
                                }
                            }
                        }
                    }

                    section("篇幅") {
                        Picker("篇幅", selection: $lengthRaw) {
                            ForEach(StoryLength.allCases) { length in
                                Text("\(length.label) · 约\(length.sentenceCount)句").tag(length.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    section("主题（可选）") {
                        TextField("例如：一只想学游泳的猫、东京的雨天", text: $topic, axis: .vertical)
                            .lineLimit(1...3)
                            .padding(14)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    if let errorMessage { Text(errorMessage).font(.callout).foregroundStyle(.red) }
                }
                .padding(20)
                .padding(.bottom, 80)
            }
            .background(Theme.paper)
            .navigationTitle("新短文")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", systemImage: "xmark") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let request = StoryRequest(
                            language: language,
                            level: level,
                            genre: StoryGenre(rawValue: genreRaw) ?? .fable,
                            length: StoryLength(rawValue: lengthRaw) ?? .short,
                            topic: topic
                        )
                    if lastRequest != request { submissionKey = UUID(); lastRequest = request }
                    isSubmitting = true
                    errorMessage = nil
                    Task {
                        defer { isSubmitting = false }
                        do {
                            try await studio.start(request, idempotencyKey: submissionKey)
                            dismiss()
                        } catch { errorMessage = error.localizedDescription }
                    }
                } label: {
                    Label(isSubmitting ? "正在提交…" : "开始创作", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .disabled(isSubmitting)
            .interactiveDismissDisabled(isSubmitting)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.muted)
            content()
        }
    }

    private func languageTile(_ option: StoryLanguage) -> some View {
        let selected = option == language
        return Button {
            withAnimation(.snappy) { language = option }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(option.glyph).font(.system(size: 28, weight: .bold, design: .serif)).foregroundStyle(selected ? Theme.accent : Theme.muted)
                Text(option.nativeName).font(.headline).foregroundStyle(Theme.ink)
                Text(option.chineseName).font(.caption).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(selected ? Theme.accent.opacity(0.14) : Theme.raised,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private func chip(_ title: String, systemImage: String? = nil, selected: Bool, fill: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage { Image(systemName: systemImage).imageScale(.small) }
                Text(title)
            }
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? Color.white : Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: fill ? .infinity : nil)
            .background(selected ? Theme.accent : Theme.raised, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

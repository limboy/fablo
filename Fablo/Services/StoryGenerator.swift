import Foundation

/// Prompts and JSON schemas for story generation and sentence analysis.
enum StoryGenerator {
    // MARK: Story

    /// - Parameter existing: one line per story already in the library (title + Chinese summary),
    ///   so the model can steer away from themes the learner has already read.
    static func generate(_ request: StoryRequest, avoiding existing: [String]) async throws -> StoryContent {
        let topic = request.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        var user = """
        目标语言：\(request.language.chineseName)
        难度：\(request.level.name)（\(request.level.summary)）
        类型：\(request.genre.rawValue)
        篇幅：约 \(request.length.sentenceCount) 句
        主题：\(topic.isEmpty ? "自由发挥，选一个新鲜有趣的切入点" : topic)
        """
        if !existing.isEmpty {
            user += """


            学习者已经读过下面这些短文。请避开相同或相似的题材、主角、情节和场景，写一篇明显不同的新故事\
            （如果指定了主题，就在该主题下换一个新的角度）：
            \(existing.map { "- \($0)" }.joined(separator: "\n"))
            """
        }
        let content = try await GatewayClient.shared.structured(
            StoryContent.self,
            system: storySystemPrompt,
            user: user,
            schemaName: "story",
            schema: storySchema
        )
        guard !content.allSentences.isEmpty else { throw GatewayError.emptyResponse }
        return content
    }

    private static let storySystemPrompt = """
    你是一位为中文母语者编写外语阅读材料的语言老师。根据用户给出的目标语言、难度、类型、篇幅和主题，写一篇原创短文，并对每个句子做逐词标注。

    写作要求：
    - 词汇和语法严格符合指定难度；内容有趣、完整、有画面感。日语 N5/N4 只使用最基础的汉字，其余写成假名。
    - 「对话」类型：用引号呈现人物对白，每句台词作为独立句子。「新闻报道」类型：使用新闻文体。
    - 「演讲」类型：写成 TED 风格的演讲稿。演讲者用第一人称直接对台下听众说话（可以向听众提问）；开头用一个问题或小故事抓住注意力，全篇围绕一个清晰的核心观点，穿插个人经历或具体例子，结尾回扣主题并给听众一个启发或行动建议。title 用演讲标题。coverPrompt 描述与演讲主题相关的画面，而不是演讲舞台。
    - 分成 2-4 个自然段。
    - 句子 text 必须与其所有词的 s 依次拼接后完全一致（英语词之间的空格不放进 s，标点作为独立词）。

    逐句标注：
    - zh：自然流畅的简体中文翻译。
    - c：把句子切分为语法成分块（chunk）。日语按文节切分（如「二人は」「人を」「信じる」「ことを」「教えてくれた。」）；英语按意群切分（如 "The old man" "walked" "to the sea" "every morning."）。句末标点并入最后一个块。
      role：topic=主题(日语は), subject=主语, object=宾语, predicate=谓语(含助动词/补助动词), complement=补语/表语, modifier=修饰成分（定语、从句内部的成分）, adverbial=状语（时间地点方式等）, connector=连接词, other。从句或定语从句内部的块用 modifier。
    - 每个块的 w 是词列表：
      - 日语：名词与后面的助词分开（「二人」「は」）；动词连同其活用词尾、て形、补助动词可合为一个词（「教えてくれた」）；r 为含汉字词的完整平假名读音（不含汉字则为空字符串）；ro 为该词的平文式罗马字（助词は写作 wa，を写作 wo，へ写作 e），标点的 ro 为空字符串。
      - 英语：r 和 ro 都为空字符串。
      - p：词性。
      - g：实词的简短中文释义；助词、冠词、标点为空字符串。
    - title：目标语言标题；titleZh：中文标题；summaryZh：一句话中文简介。
    - coverPrompt：用英文描述一幅适合作为封面的插画场景（不要包含任何文字）。
    """

    private static let storySchema: [String: Any] = {
        let word: [String: Any] = [
            "type": "object",
            "properties": [
                "s": ["type": "string"],
                "r": ["type": "string"],
                "ro": ["type": "string"],
                "p": ["type": "string", "enum": PartOfSpeech.allCases.map(\.rawValue)],
                "g": ["type": "string"],
            ],
            "required": ["s", "r", "ro", "p", "g"],
            "additionalProperties": false,
        ]
        let chunk: [String: Any] = [
            "type": "object",
            "properties": [
                "role": ["type": "string", "enum": ChunkRole.allCases.map(\.rawValue)],
                "w": ["type": "array", "items": word],
            ],
            "required": ["role", "w"],
            "additionalProperties": false,
        ]
        let sentence: [String: Any] = [
            "type": "object",
            "properties": [
                "text": ["type": "string"],
                "zh": ["type": "string"],
                "c": ["type": "array", "items": chunk],
            ],
            "required": ["text", "zh", "c"],
            "additionalProperties": false,
        ]
        let paragraph: [String: Any] = [
            "type": "object",
            "properties": ["sentences": ["type": "array", "items": sentence]],
            "required": ["sentences"],
            "additionalProperties": false,
        ]
        return [
            "type": "object",
            "properties": [
                "title": ["type": "string"],
                "titleZh": ["type": "string"],
                "summaryZh": ["type": "string"],
                "coverPrompt": ["type": "string"],
                "paragraphs": ["type": "array", "items": paragraph],
            ],
            "required": ["title", "titleZh", "summaryZh", "coverPrompt", "paragraphs"],
            "additionalProperties": false,
        ]
    }()

    // MARK: Cover

    static func coverPrompt(for scene: String) -> String {
        """
        \(scene)
        Style: warm hand-drawn storybook illustration, soft textured gouache and colored pencil, \
        gentle muted palette with cream tones, cozy lighting, wide composition. \
        Absolutely no text, letters, captions or signatures.
        """
    }

    // MARK: Sentence analysis

    static func analyze(index: Int, in content: StoryContent, language: StoryLanguage, level: String) async throws -> SentenceAnalysis {
        let sentences = content.allSentences
        guard sentences.indices.contains(index) else { throw GatewayError.emptyResponse }
        let before = index > 0 ? sentences[index - 1].sentence.text : "（无）"
        let after = index + 1 < sentences.count ? sentences[index + 1].sentence.text : "（无）"
        let user = """
        文章：\(content.title)
        学习者水平：\(level)
        上一句：\(before)
        下一句：\(after)
        要解析的句子：\(sentences[index].sentence.text)
        """
        let system = """
        你是一位耐心、讲解清晰的\(language.chineseName)老师，学生是中文母语者。请解析学生给出的句子，所有解释用简体中文。
        - structure：说明句子主干和成分（主语/谓语/宾语/状语/从句等）是怎样组织起来的，2-4 句话。
        - grammar：句中值得学习的语法点或句型（1-4 个），每个给出名称（如「〜てくれる」「现在完成时」）、讲解、一个新的\(language.chineseName)例句及其中文翻译。
        - vocabulary：句中的重点词汇（2-6 个），reading 填\(language == .ja ? "平假名读音" : "英式或美式 IPA 音标")，meaning 为中文意思，note 为用法提示（可为空字符串）。
        - nuance：语感、语气、文化背景或易错点提示；没有就填空字符串。
        """
        return try await GatewayClient.shared.structured(
            SentenceAnalysis.self,
            system: system,
            user: user,
            schemaName: "analysis",
            schema: analysisSchema
        )
    }

    private static let analysisSchema: [String: Any] = {
        let grammar: [String: Any] = [
            "type": "object",
            "properties": [
                "point": ["type": "string"],
                "explanation": ["type": "string"],
                "example": ["type": "string"],
                "exampleZh": ["type": "string"],
            ],
            "required": ["point", "explanation", "example", "exampleZh"],
            "additionalProperties": false,
        ]
        let vocab: [String: Any] = [
            "type": "object",
            "properties": [
                "word": ["type": "string"],
                "reading": ["type": "string"],
                "meaning": ["type": "string"],
                "note": ["type": "string"],
            ],
            "required": ["word", "reading", "meaning", "note"],
            "additionalProperties": false,
        ]
        return [
            "type": "object",
            "properties": [
                "structure": ["type": "string"],
                "grammar": ["type": "array", "items": grammar],
                "vocabulary": ["type": "array", "items": vocab],
                "nuance": ["type": "string"],
            ],
            "required": ["structure", "grammar", "vocabulary", "nuance"],
            "additionalProperties": false,
        ]
    }()
}

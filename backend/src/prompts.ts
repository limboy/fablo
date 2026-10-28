import { partsOfSpeech, roles, type GenerationRequest, type StoryRecord, sentences } from "./types";

const string = { type: "string" };
const array = (items: unknown) => ({ type: "array", items });
const object = (properties: Record<string, unknown>) => ({ type: "object", properties, required: Object.keys(properties), additionalProperties: false });
const word = object({ s: string, r: string, ro: string, p: { type: "string", enum: partsOfSpeech }, g: string });
const chunk = object({ role: { type: "string", enum: roles }, w: array(word) });
export const storySchema = object({ title: string, titleZh: string, summaryZh: string, coverPrompt: string, paragraphs: array(object({ sentences: array(object({ text: string, zh: string, c: array(chunk) })) })) });
export const analysisSchema = object({
  structure: string, nuance: string,
  grammar: array(object({ point: string, explanation: string, example: string, exampleZh: string })),
  vocabulary: array(object({ word: string, reading: string, meaning: string, note: string })),
});

export const storySystem = `你是一位为中文母语者编写外语阅读材料的语言老师。根据用户给出的目标语言、难度、类型、篇幅和主题，写一篇原创短文，并对每个句子做逐词标注。

写作要求：
- 词汇和语法严格符合指定难度；内容有趣、完整、有画面感。日语 N5/N4 只使用最基础的汉字，其余写成假名。
- 「对话」类型：用引号呈现人物对白，每句台词作为独立句子。「新闻报道」类型：使用新闻文体。
- 「演讲」类型：写成 TED 风格的演讲稿。演讲者用第一人称直接对台下听众说话（可以向听众提问）；开头用一个问题或小故事抓住注意力，全篇围绕一个清晰的核心观点，穿插个人经历或具体例子，结尾回扣主题并给听众一个启发或行动建议。title 用演讲标题。coverPrompt 描述与演讲主题相关的画面，而不是演讲舞台。
- 「句子」类型：不写连贯短文，而是按篇幅要求的句数写互相独立的单句，每句单独成为一个自然段（不受下面 2-4 段的限制）。按 N+1 原则出题：核心词汇在指定难度内，但每句都比该难度的典型句子更长、更有挑战——用定语从句、名词修饰、复句或该难度刚学到/略高一级的句型把信息串起来（例如 N5：「去年の夏に会った人にもう一度会いたいです。」「日本の習慣についてよく知っている外国人を探しています。」，仅示意难度，不要照抄）。每句语法重点和场景都不同，内容自然实用。title 概括这组句子的主题或重点句型，coverPrompt 描述其中一句的画面。
- 分成 2-4 个自然段。
- 日语句子 text 必须与所有词的 s 依次拼接后完全一致。英语 text 保留自然空格，词之间的空格不放进 s，标点作为独立词。

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
- coverPrompt：用英文描述一幅适合作为封面的插画场景（不要包含任何文字）。`;

const levelSummaries: Record<string, string> = {
  A1: "入门 · 常用词、简单现在时", A2: "初级 · 日常话题、过去时", B1: "中级 · 复合句、常见短语", B2: "中高级 · 从句、丰富词汇", C1: "高级 · 地道表达、复杂结构",
  N5: "入门 · 基础汉字、です/ます", N4: "初级 · て形、简单复句", N3: "中级 · 日常文章、常用句型", N2: "中高级 · 报刊随笔、书面语", N1: "高级 · 复杂文体、细腻表达",
};
export function storyUser(r: GenerationRequest, existing: StoryRecord[]): string {
  let user = `目标语言：${r.language === "ja" ? "日语" : "英语"}
难度：${r.level}（${levelSummaries[r.level]}）
类型：${r.genre}
篇幅：约 ${{ short: 6, medium: 12, long: 20 }[r.length]} 句
主题：${r.topic || "自由发挥，选一个新鲜有趣的切入点"}`;
  if (r.genre === "句子") {
    const seen = existing.filter(s => s.genre === "句子" && s.language === r.language).flatMap(s => sentences(s.content).map(s => s.text));
    if (seen.length) return user + "\n\n学习者已经练习过下面这些句子。新句子不要重复或改写它们，换用不同的语法点、词汇和场景：\n" + seen.map(t => `- ${t}`).join("\n");
    return user;
  }
  if (existing.length) user += "\n\n学习者已经读过下面这些短文。请避开相同或相似的题材、主角、情节和场景，写一篇明显不同的新故事（如果指定了主题，就在该主题下换一个新的角度）：\n" + existing.map(s => `- ${s.content.title}（${s.content.titleZh}）：${s.content.summaryZh}`).join("\n");
  return user;
}
export function coverPrompt(scene: string): string {
  return `${scene}\nStyle: warm hand-drawn storybook illustration, soft textured gouache and colored pencil, gentle muted palette with cream tones, cozy lighting, wide composition. Absolutely no text, letters, or signatures.`;
}
export function analysisPrompt(story: StoryRecord, index: number): { system: string; user: string } {
  const all = sentences(story.content), language = story.language === "ja" ? "日语" : "英语";
  return {
    system: `你是一位耐心、讲解清晰的${language}老师，学生是中文母语者。请解析学生给出的句子，所有解释用简体中文。
- structure：说明句子主干和成分（主语/谓语/宾语/状语/从句等）是怎样组织起来的，2-4 句话。
- grammar：句中值得学习的语法点或句型（1-4 个），每个给出名称、讲解、一个新的${language}例句及其中文翻译。
- vocabulary：句中的重点词汇（2-6 个），reading 填${story.language === "ja" ? "平假名读音" : "英式或美式 IPA 音标"}，meaning 为中文意思，note 为用法提示（可为空字符串）。
- nuance：语感、语气、文化背景或易错点提示；没有就填空字符串。`,
    user: `文章：${story.content.title}\n学习者水平：${story.level}\n上一句：${all[index - 1]?.text ?? "（无）"}\n下一句：${all[index + 1]?.text ?? "（无）"}\n要解析的句子：${all[index]!.text}`,
  };
}
export function speechInstructions(story: StoryRecord): string {
  const pace = ["A1", "A2", "N5", "N4"].includes(story.level) ? "slowly and very clearly" : "at a natural, relaxed pace";
  const accent = story.language === "ja" ? "in standard Tokyo Japanese" : "in clear standard English";
  const style = story.genre === "演讲" ? "Deliver it like a warm, engaging speaker giving a TED-style talk to a live audience"
    : story.genre === "句子" ? "Read these independent example sentences aloud like a language teacher, one at a time"
    : "Read this story aloud like an audiobook narrator";
  return `${style}, ${accent}, ${pace}, for language learners. Pause briefly between sentences and a little longer between paragraphs.`;
}

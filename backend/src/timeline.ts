import type { TimedWord } from "./gateway";
import type { Timeline } from "./types";

// Compatible with the existing iOS player and its on-disk timeline cache.
export const TIMELINE_VERSION = 3;
const characters = (text: string): string[] => Array.from(text.normalize("NFKC").toLowerCase()).flatMap(c => {
  const cp = c.codePointAt(0)!;
  if (!/[\p{L}\p{N}]/u.test(c)) return [];
  return [cp >= 0x30a1 && cp <= 0x30f6 ? String.fromCodePoint(cp - 0x60) : c];
});
function timeline(wordStarts: (number | null)[][], measuredEnds: number[] | null, duration: number, isAligned: boolean): Timeline {
  const sentenceStarts: number[] = [];
  for (const words of wordStarts) {
    const spoken = words.filter((v): v is number => v !== null);
    sentenceStarts.push(Math.max(spoken[0] ?? sentenceStarts.at(-1) ?? 0, sentenceStarts.at(-1) ?? 0));
  }
  const sentenceEnds = sentenceStarts.map((start, i) => {
    const next = sentenceStarts[i + 1] ?? duration;
    return measuredEnds && measuredEnds[i]! > start ? Math.min(measuredEnds[i]!, next) : next;
  });
  return { version: TIMELINE_VERSION, duration, wordStarts, sentenceStarts, sentenceEnds, isAligned };
}
export function estimate(sentences: string[][], duration: number): Timeline {
  const total = Math.max(1, sentences.flat().reduce((sum, word) => sum + characters(word).length, 0));
  let elapsed = 0;
  return timeline(sentences.map(words => words.map(word => {
    const length = characters(word).length;
    if (!length) return null;
    const start = duration * elapsed / total;
    elapsed += length;
    return start;
  })), null, duration, false);
}
export function align(sentences: string[][], transcript: TimedWord[], duration: number): Timeline {
  const ref: string[] = [], owners: [number, number][] = [];
  sentences.forEach((words, s) => words.forEach((word, w) => characters(word).forEach(c => { ref.push(c); owners.push([s, w]); })));
  const hyp: string[] = [], hypStarts: number[] = [], hypEnds: number[] = [];
  for (const word of transcript) {
    const chars = characters(word.text), step = word.durationMilliseconds / Math.max(chars.length, 1);
    chars.forEach((c, i) => {
      hyp.push(c);
      hypStarts.push(Math.min(duration, (word.offsetMilliseconds + step * i) / 1000));
      hypEnds.push(Math.min(duration, (word.offsetMilliseconds + step * (i + 1)) / 1000));
    });
  }
  // Bound alignment memory/CPU for imported long documents.
  if (!ref.length || !hyp.length || (ref.length + 1) * (hyp.length + 1) > 4000000) return estimate(sentences, duration);
  const width = hyp.length + 1, dp = new Uint16Array((ref.length + 1) * width);
  for (let i = ref.length - 1; i >= 0; i--) {
    for (let j = hyp.length - 1; j >= 0; j--) dp[i * width + j] = ref[i] === hyp[j] ? 1 + dp[(i + 1) * width + j + 1]! : Math.max(dp[(i + 1) * width + j]!, dp[i * width + j + 1]!);
  }
  const anchors: [number, number][] = [];
  let i = 0, j = 0;
  while (i < ref.length && j < hyp.length) {
    if (ref[i] === hyp[j]) { anchors.push([i++, j++]); }
    else if (dp[(i + 1) * width + j]! >= dp[i * width + j + 1]!) i++;
    else j++;
  }
  if (anchors.length < Math.min(ref.length, hyp.length) / 4) return estimate(sentences, duration);
  const starts = new Array<number>(ref.length), ends = new Array<number>(ref.length);
  let previousRef = -1, previousHyp = -1, previousEnd = 0;
  for (const [r, h] of [...anchors, [ref.length, hyp.length] as [number, number]]) {
    const nextStart = r < ref.length ? hypStarts[h]! : duration;
    const gap = r - previousRef - 1, hasHypGap = h > previousHyp + 1;
    const from = hasHypGap ? hypStarts[previousHyp + 1]! : previousEnd;
    const to = hasHypGap ? hypEnds[h - 1]! : nextStart;
    for (let k = 0; k < gap; k++) {
      starts[previousRef + 1 + k] = from + Math.max(0, to - from) * k / (hasHypGap ? gap : gap + 1);
      ends[previousRef + 1 + k] = hasHypGap ? from + Math.max(0, to - from) * (k + 1) / gap : starts[previousRef + 1 + k]!;
    }
    if (r < ref.length) { starts[r] = nextStart; ends[r] = hypEnds[h]!; previousEnd = ends[r]!; }
    previousRef = r; previousHyp = h;
  }
  const wordStarts = sentences.map(words => words.map((): number | null => null)), sentenceEnds = sentences.map(() => 0);
  let previousStart = 0;
  owners.forEach(([s, w], index) => {
    const start = Math.min(duration, Math.max(previousStart, starts[index]!));
    previousStart = start;
    if (wordStarts[s]![w] === null) wordStarts[s]![w] = start;
    sentenceEnds[s] = Math.max(sentenceEnds[s]!, start, Math.min(duration, ends[index]!));
  });
  return timeline(wordStarts, sentenceEnds, duration, true);
}

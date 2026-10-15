#!/usr/bin/env python3
"""Convert an existing Japanese Short Essays collection without changing its source."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unicodedata
import uuid

FORMAT = "japanese-short-essays-v1"
NAMESPACE = uuid.UUID("b20805d6-cf78-4c91-848b-981ad34a8c21")
GENRES = {"会話": "对话", "インタビュー": "对话", "スピーチ": "演讲", "仕事日誌": "职场", "幻想散文": "奇幻冒险", "物語": "童话寓言"}
POS = {"名詞": "noun", "代名詞": "pronoun", "動詞": "verb", "形容詞": "adjective", "形状詞": "adjective", "副詞": "adverb", "助詞": "particle", "助動詞": "auxiliary", "接続詞": "conjunction", "連体詞": "determiner", "感動詞": "interjection", "補助記号": "punctuation", "記号": "punctuation"}


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def run(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=180)
    if result.returncode:
        raise ValueError(f"{Path(args[0]).name} failed: {result.stderr[-1200:]}")
    return result.stdout


def hira(text):
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in text)


def vocabulary(markdown):
    section = re.search(r"##\s*言葉\s*\n([\s\S]*?)(?=\n##|\Z)", markdown)
    result = {}
    if section:
        for line in section[1].splitlines():
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) >= 3 and cells[0] not in ("表記", "") and not re.fullmatch(r"[-: ]+", cells[0]):
                result[cells[0]] = {"reading": cells[1], "meaning": cells[2]}
    return result


def display_sentence(line):
    # Display speaker labels from the original subtitle; the narration omits them.
    # Some legacy subtitles abbreviate narration or accidentally contain Chinese.
    # The manifest's spoken Japanese is canonical; retain a matching speaker prefix.
    display = line["text"]
    subtitle = line.get("subtitle", "")
    speaker = re.match(r"^([^：:\n]{1,20}[：:])", subtitle)
    normalized = lambda value: "".join(c for c in unicodedata.normalize("NFKC", value) if not c.isspace() and not unicodedata.category(c).startswith("P"))
    if speaker and normalized(subtitle[speaker.end():]) == normalized(display):
        display = speaker[0] + display
    return display


def annotated_sentence(line, parser, mode, romanizer, glossary):
    display = display_sentence(line)
    spoken_offset = len(display) - len(line["text"])
    tokens = list(parser.tokenize(display, mode))
    boundaries = {token.end(): i + 1 for i, token in enumerate(tokens)}
    terms = sorted(glossary, key=len, reverse=True)
    words, spoken = [], []
    i = 0
    while i < len(tokens):
        token = tokens[i]
        start, end = token.begin(), token.end()
        surface, reading = token.surface(), hira(token.reading_form())
        meaning = glossary.get(token.dictionary_form(), {}).get("meaning", "")
        following = i + 1
        for term in terms:
            term_end = start + len(term)
            if display.startswith(term, start) and term_end in boundaries:
                surface, end, following = term, term_end, boundaries[term_end]
                reading, meaning = hira(glossary[term]["reading"]), glossary[term]["meaning"]
                break
        i = following
        if not surface.strip():
            continue
        pos = POS.get(token.part_of_speech()[0], "other")
        if token.part_of_speech()[1] == "数詞":
            pos = "number"
        romaji = "" if pos == "punctuation" else "".join(item["hepburn"] for item in romanizer.convert(reading))
        if pos == "particle" and surface in ("は", "へ", "を"):
            romaji = {"は": "wa", "へ": "e", "を": "wo"}[surface]
        words.append({"s": surface, "r": reading if re.search(r"[\u3400-\u9fff々]", surface) else "", "ro": romaji, "p": pos, "g": meaning})
        spoken.append(end > spoken_offset and pos != "punctuation")
    if "".join(w["s"] for w in words) != re.sub(r"\s", "", display):
        raise ValueError("Tokenizer changed the source text")
    return {"text": display, "zh": line["translation"], "c": [{"role": "other", "w": words}]}, spoken


def subtitle_times(path, lines):
    blocks = re.split(r"\n\s*\n", path.read_text().strip().replace("\r\n", "\n"))
    result = []
    def seconds(value):
        hours, minutes, rest = value.replace(",", ".").split(":")
        return int(hours) * 3600 + int(minutes) * 60 + float(rest)
    for block in blocks:
        match = re.search(r"(\d\d:\d\d:\d\d[,\.]\d{3})\s*-->\s*(\d\d:\d\d:\d\d[,\.]\d{3})\s*\n([^\n]+)", block)
        if not match:
            raise ValueError("Invalid SRT cue")
        index = len(result)
        if index >= len(lines) or match[3].strip() != (lines[index].get("subtitle") or lines[index]["text"]):
            raise ValueError("SRT cue does not match its source sentence")
        start, end = seconds(match[1]), seconds(match[2])
        if end < start or (result and start < result[-1][1] - 0.001):
            raise ValueError("SRT times overlap or run backwards")
        result.append((start, end))
    if len(result) != len(lines):
        raise ValueError("SRT sentence count does not match manifest")
    return result


def timeline(sentences, spoken, cues, duration):
    if cues[-1][1] > duration + 0.25:
        raise ValueError(f"Subtitles exceed audio duration: {cues[-1][1]} > {duration}")
    starts, ends, word_starts = [], [], []
    for sentence, flags, (start, end) in zip(sentences, spoken, cues):
        start, end = round(min(start, duration), 6), round(min(end, duration), 6)
        start = max(start, ends[-1] if ends else 0)
        end = max(start, end)
        weights = [max(1, len(w["r"] or w["s"])) if flag else 0 for w, flag in zip(sentence["c"][0]["w"], flags)]
        total, elapsed, values = max(1, sum(weights)), 0, []
        for weight in weights:
            values.append(max(start, min(end, round(start + (end - start) * elapsed / total, 6))) if weight else None)
            elapsed += weight
        starts.append(start)
        ends.append(end)
        word_starts.append(values)
    return {"version": 3, "duration": duration, "sentenceStarts": starts, "sentenceEnds": ends, "wordStarts": word_starts, "isAligned": False}


def prepare(directory, output, titles, parser, mode, romanizer, args):
    manifest = json.loads((directory / "manifest.json").read_text())
    if manifest["language"] != "ja" or not manifest["lines"]:
        raise ValueError("Expected a nonempty Japanese manifest")
    markdown = (directory / "essay.md").read_text()
    summary = re.search(r"##\s*中文梗概\s*\n([\s\S]*?)(?=\n##|\Z)", markdown)
    if not summary:
        raise ValueError("Missing Chinese summary")
    title_zh = titles.get(directory.name, titles.get(manifest["title"], ""))
    levels = re.findall(r"N[1-5]", manifest["level"])
    if not levels:
        raise ValueError("Unrecognized JLPT level")
    level = min(levels)  # N5–N4 is catalogued at its more advanced level, N4.
    glossary = vocabulary(markdown)
    annotated = [annotated_sentence(line, parser, mode, romanizer, glossary) for line in manifest["lines"]]
    sentences, spoken = [s for s, _ in annotated], [flags for _, flags in annotated]
    count = len(sentences)
    story = {
        "source": {"format": FORMAT, "id": directory.name, "metadata": {
            "manifest": manifest, "essayMarkdown": markdown, "annotation": "Sudachi dictionary segmentation and readings; source vocabulary glosses; no syntactic role inference",
            "timing": "Original SRT sentence boundaries; estimated word positions; speaker labels are unspoken",
        }},
        "createdAt": datetime.strptime(directory.name[:10], "%Y-%m-%d").replace(tzinfo=timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "generationRequest": {"language": "ja", "level": level, "genre": GENRES.get(manifest["genre"], "日常生活"), "length": "short" if count <= 8 else "medium" if count <= 15 else "long", "topic": manifest["topic"]},
        "content": {"title": manifest["title"], "titleZh": title_zh, "summaryZh": summary[1].strip(), "coverPrompt": f"An illustration set in Japan. Scene: {manifest['setting']}. Topic: {manifest['topic']}. No text or lettering.", "paragraphs": [{"sentences": sentences}]},
        "analyses": {},
    }
    if len(json.dumps(story["source"]["metadata"], ensure_ascii=False).encode()) > 64 * 1024:
        raise ValueError("Source metadata exceeds 64 KiB")
    id = str(uuid.uuid5(NAMESPACE, FORMAT + ":" + directory.name))
    cover = max((p for p in (directory / "cover.png", directory / "cover.jpg") if p.exists()), key=lambda p: p.stat().st_mtime_ns, default=None)
    audio, srt = directory / "audio.mp3", directory / "audio.srt"
    if audio.exists() != srt.exists():
        raise ValueError("Audio and SRT must both be present or both be absent")
    digest = hashlib.sha256(b"fablo-import-adapter-v1\0" + json.dumps(story, ensure_ascii=False, sort_keys=True).encode())
    for p in (cover, audio if audio.exists() else None, srt if srt.exists() else None):
        digest.update(p.read_bytes() if p else b"missing")
    checksum = digest.hexdigest()
    target = output / id
    marker = target / "prepared.json"
    previous = json.loads(marker.read_text()) if marker.exists() else {}
    if previous.get("checksum") == checksum and previous.get("adapterVersion") == 2:
        return {"id": id, "directory": id, "title": manifest["title"], "audio": audio.exists(), "cover": cover is not None, "sentences": count, "reused": True}
    staging = Path(tempfile.mkdtemp(prefix=".preparing-", dir=output))
    try:
        write_json(staging / "story.json", story)
        if cover:
            if previous.get("checksum") == checksum and (target / "cover.jpg").exists():
                shutil.copy2(target / "cover.jpg", staging / "cover.jpg")
            else:
                run([args.ffmpeg, "-v", "error", "-nostdin", "-y", "-i", str(cover), "-frames:v", "1", "-vf", "scale='min(1200,iw)':-2", "-q:v", "3", str(staging / "cover.jpg")])
        if audio.exists():
            if previous.get("checksum") == checksum and (target / "audio.m4a").exists():
                shutil.copy2(target / "audio.m4a", staging / "audio.m4a")
            else:
                run([args.ffmpeg, "-v", "error", "-nostdin", "-y", "-i", str(audio), "-vn", "-map_metadata", "-1", "-c:a", "aac", "-b:a", "64k", "-movflags", "+faststart", str(staging / "audio.m4a")])
            duration = float(run([args.ffprobe, "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", str(staging / "audio.m4a")]).strip())
            write_json(staging / "timeline.json", timeline(sentences, spoken, subtitle_times(srt, manifest["lines"]), duration))
        write_json(staging / "prepared.json", {"checksum": checksum, "adapterVersion": 2})
        if target.exists():
            shutil.rmtree(target)
        staging.rename(target)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    return {"id": id, "directory": id, "title": manifest["title"], "audio": audio.exists(), "cover": cover is not None, "sentences": count, "reused": False}


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("source", type=Path)
    cli.add_argument("--output", required=True, type=Path)
    cli.add_argument("--titles", type=Path, help="Optional JSON map from source folder or Japanese title to Chinese title")
    cli.add_argument("--ffmpeg", default="ffmpeg")
    cli.add_argument("--ffprobe", default="ffprobe")
    args = cli.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if output == source or source in output.parents:
        cli.error("Output must be outside the source collection")
    try:
        from sudachipy import dictionary, tokenizer
        from pykakasi import kakasi
    except ImportError:
        cli.error("Install the preparation dependencies with pip install -r scripts/requirements-import.txt")
    parser, romanizer = dictionary.Dictionary().create(), kakasi()
    titles = json.loads(args.titles.read_text()) if args.titles else {}
    output.mkdir(parents=True, exist_ok=True)
    bundle = {"format": "fablo-import-bundle-v1", "stories": [], "errors": []}
    directories = sorted(p.parent for p in source.glob("*/manifest.json"))
    if not directories:
        cli.error("No manifest.json files found")
    for index, directory in enumerate(directories, 1):
        try:
            entry = prepare(directory, output, titles, parser, tokenizer.Tokenizer.SplitMode.C, romanizer, args)
            bundle["stories"].append(entry)
            print(f"[{index}/{len(directories)}] {entry['title']} ({'cached' if entry['reused'] else 'prepared'})", flush=True)
        except Exception as error:
            bundle["errors"].append({"directory": directory.name, "error": str(error)})
            print(f"[{index}/{len(directories)}] FAILED {directory.name}: {error}", flush=True)
    write_json(output / "bundle.json", bundle)
    print(json.dumps({"prepared": len(bundle["stories"]), "errors": len(bundle["errors"]), "output": str(output)}, ensure_ascii=False))
    if bundle["errors"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

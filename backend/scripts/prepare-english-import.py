#!/usr/bin/env python3
"""Convert an existing English Short Essays collection without changing its source."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import re

spec = importlib.util.spec_from_file_location("essay_import", Path(__file__).with_name("prepare-japanese-import.py"))
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)

FORMAT = "english-short-essays-v1"
GENRES = {"mini-speech": "演讲", "speech": "演讲", "dialogue": "对话"}
POS = {"NOUN": "noun", "PROPN": "noun", "PRON": "pronoun", "VERB": "verb", "AUX": "auxiliary", "ADJ": "adjective", "ADV": "adverb", "ADP": "preposition", "CCONJ": "conjunction", "SCONJ": "conjunction", "DET": "determiner", "INTJ": "interjection", "NUM": "number", "PUNCT": "punctuation"}
TOKEN = re.compile(r"\d+(?:[.,]\d+)+|\w+(?:[’'\-‑]\w+)*|\.{2,}|[^\s]", re.UNICODE)


def vocabulary(markdown):
    section = re.search(r"##\s*Vocabulary\s*\n([\s\S]*?)(?=\n##|\Z)", markdown, re.IGNORECASE)
    result = {}
    if section:
        for line in section[1].splitlines():
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if len(cells) >= 2 and cells[0].lower() not in ("word", "word/phrase", "word or phrase", "english", "item", "expression", "phrase", "") and not re.fullmatch(r"[-: ]+", cells[0]):
                result[cells[0].casefold()] = cells[-1]
    return result


def annotated_sentence(line, parser, glossary):
    display = shared.display_sentence(line)
    if display != line["text"]:
        display = display[:-len(line["text"])].rstrip() + " " + line["text"]
    offset = len(display) - len(line["text"])
    document = parser(display)
    lexical = list(document)
    matches = list(TOKEN.finditer(display))
    boundaries = {match.end(): index + 1 for index, match in enumerate(matches)}
    # Keep short vocabulary phrases intact; long phrases remain wrappable words.
    terms = sorted((term for term in glossary if len(term) <= 32 and len(term.split()) <= 4), key=len, reverse=True)
    words, spoken = [], []
    i = 0
    while i < len(matches):
        match = matches[i]
        start, end = match.start(), match.end()
        surface, meaning = match[0], ""
        following = i + 1
        for term in terms:
            term_end = start + len(term)
            if display[start:term_end].casefold() == term and term_end in boundaries:
                end, surface, following, meaning = term_end, display[start:term_end], boundaries[term_end], glossary[term]
                break
        i = following
        span = document.char_span(start, end, alignment_mode="expand")
        head = span.root if span is not None else next((t for t in lexical if t.idx <= start < t.idx + len(t.text)), None)
        punctuation = re.fullmatch(r"[^\w\s]+", surface) is not None
        pos = "punctuation" if punctuation else POS.get(head.pos_, "other") if head is not None else "other"
        if not meaning:
            meaning = glossary.get(surface.casefold(), "") or (glossary.get(head.lemma_.casefold(), "") if head is not None else "")
        words.append({"s": surface, "r": "", "ro": "", "p": pos, "g": meaning})
        spoken.append(end > offset and not punctuation)
    if re.sub(r"\s", "", "".join(w["s"] for w in words)) != re.sub(r"\s", "", display):
        raise ValueError("Tokenizer changed the source text")
    return {"text": display, "zh": line["translation"], "c": [{"role": "other", "w": words}]}, spoken


def prepare(directory, output, titles, parser, args):
    manifest = json.loads((directory / "manifest.json").read_text())
    if manifest["language"] != "en" or not manifest["lines"]:
        raise ValueError("Expected a nonempty English manifest")
    markdown = (directory / "essay.md").read_text()
    summary = re.search(r"##\s*中文梗概\s*\n([\s\S]*?)(?=\n##|\Z)", markdown)
    if not summary:
        raise ValueError("Missing Chinese summary")
    levels = re.findall(r"[ABC][12]", manifest["level"])
    if not levels:
        raise ValueError("Unrecognized CEFR level")
    level = max(levels)
    glossary = vocabulary(markdown)
    annotated = [annotated_sentence(line, parser, glossary) for line in manifest["lines"]]
    sentences, spoken = [s for s, _ in annotated], [flags for _, flags in annotated]
    count = len(sentences)
    story = {
        "source": {"format": FORMAT, "id": directory.name, "metadata": {
            "manifest": manifest, "essayMarkdown": markdown, "annotation": "spaCy English lexical classes and lemmas; source vocabulary glosses; no syntactic role inference",
            "timing": "Original SRT segment boundaries; estimated word positions; matching speaker labels are unspoken",
        }},
        "createdAt": datetime.strptime(directory.name[:10], "%Y-%m-%d").replace(tzinfo=timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "generationRequest": {"language": "en", "level": level, "genre": GENRES.get(manifest["genre"], "日常生活"), "length": "short" if count <= 8 else "medium" if count <= 15 else "long", "topic": manifest["topic"]},
        "content": {"title": manifest["title"], "titleZh": titles.get(directory.name, titles.get(manifest["title"], "")), "summaryZh": summary[1].strip(), "coverPrompt": f"An editorial illustration. Scene: {manifest['setting']}. Topic: {manifest['topic']}. No text or lettering.", "paragraphs": [{"sentences": sentences}]},
        "analyses": {},
    }
    return shared.prepare_entry(directory, output, story, sentences, spoken, args)


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("source", type=Path)
    cli.add_argument("--output", required=True, type=Path)
    cli.add_argument("--titles", type=Path)
    cli.add_argument("--model", default="en_core_web_sm")
    cli.add_argument("--ffmpeg", default="ffmpeg")
    cli.add_argument("--ffprobe", default="ffprobe")
    args = cli.parse_args()
    source, output = args.source.resolve(), args.output.resolve()
    if output == source or source in output.parents:
        cli.error("Output must be outside the source collection")
    try:
        import spacy
        parser = spacy.load(args.model, disable=["ner"])
    except (ImportError, OSError):
        cli.error("Install spaCy and its English model: pip install 'spacy>=3.8,<4'; python -m spacy download en_core_web_sm")
    titles = json.loads(args.titles.read_text()) if args.titles else {}
    output.mkdir(parents=True, exist_ok=True)
    bundle = {"format": "fablo-import-bundle-v1", "stories": [], "errors": []}
    directories = sorted(p.parent for p in source.glob("*/manifest.json"))
    if not directories:
        cli.error("No manifest.json files found")
    for index, directory in enumerate(directories, 1):
        try:
            entry = prepare(directory, output, titles, parser, args)
            bundle["stories"].append(entry)
            print(f"[{index}/{len(directories)}] {entry['title']} ({'cached' if entry['reused'] else 'prepared'})", flush=True)
        except Exception as error:
            bundle["errors"].append({"directory": directory.name, "error": str(error)})
            print(f"[{index}/{len(directories)}] FAILED {directory.name}: {error}", flush=True)
    shared.write_json(output / "bundle.json", bundle)
    print(json.dumps({"prepared": len(bundle["stories"]), "errors": len(bundle["errors"]), "output": str(output)}))
    if bundle["errors"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()

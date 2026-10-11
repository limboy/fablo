# Fablo

AI-generated reading practice for Chinese speakers learning English or Japanese. Pick a language, level, genre and length, and Fablo writes an original short story at your level, illustrates it, narrates it, and annotates every sentence.

## Features

- **Stories at your level** — English (CEFR A1–C1) or Japanese (JLPT N5–N1), in 14 genres from everyday life and fables to news reports, dialogues and TED-style talks. Short, medium or long (about 6 / 12 / 20 sentences), with an optional topic.
- **Fresh every time** — new stories are steered away from themes already in your library.
- **Annotated sentences** — each sentence is split into grammatical chunks (subject, predicate, object, …) with per-word part of speech, Chinese gloss, and for Japanese, furigana and romaji. Every sentence has a Chinese translation.
- **Sentence analysis** — tap a sentence for an explanation of its structure, grammar points with new examples, key vocabulary (IPA or kana readings) and nuance notes.
- **Narration** — the whole story is narrated in one pass with word-level highlighting, adjustable speed, pause/resume, looping, and background playback.
- **Cover art** — each story gets a storybook-style illustration.

All explanations are in Simplified Chinese.

## How it works

Everything goes through [Vercel AI Gateway](https://vercel.com/ai-gateway) via a thin client in [GatewayClient.swift](Fablo/Services/GatewayClient.swift):

| Task | Model |
| --- | --- |
| Story generation & sentence analysis (structured JSON output) | `google/gemini-3.8-flash` |
| Cover illustration | `openai/gpt-image-2.5-sunburst` |
| Narration | `google/gemini-3.8-flash-tts` |
| Word timings for highlighting | `microsoft/mai-transcribe-2` |

Stories are stored locally with SwiftData.

## Project layout

```
Fablo/
  App/        App entry point
  Models/     Story (SwiftData) and generated content types
  Services/   AI Gateway client, prompts, audio generation and playback
  Views/      Library, new story, reader, sentence analysis
marketing-video/   Remotion promo video
project.yml        XcodeGen spec
```

## Getting started

Requirements: Xcode with the iOS 26 SDK, and a Vercel AI Gateway API key.

1. Add your key:

   ```bash
   cp Secrets.swift.example Fablo/Services/Secrets.swift
   ```

   Then replace `YOUR_VERCEL_AI_GATEWAY_KEY` in `Fablo/Services/Secrets.swift`. This file is gitignored.

2. Open the project and run on an iPhone or simulator:

   ```bash
   open Fablo.xcodeproj
   ```

   For on-device builds, change `DEVELOPMENT_TEAM` in `project.yml` (or in Xcode's Signing settings) to your own team.

If you change `project.yml`, regenerate the Xcode project with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate
```

> **Note:** the API key is compiled into the app binary, where it can be extracted. Put the gateway behind your own backend before distributing the app.

## Marketing video

`marketing-video/` is a [Remotion](https://www.remotion.dev) project for the promo video.

```bash
cd marketing-video && npm install && npm run dev
```

Render with `npx remotion render`.

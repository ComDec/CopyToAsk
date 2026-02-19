# CopyToAsk

[![CI](https://github.com/ComDec/CopyToAsk/actions/workflows/ci.yml/badge.svg)](https://github.com/ComDec/CopyToAsk/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ComDec/CopyToAsk)](https://github.com/ComDec/CopyToAsk/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)](#requirements)

English | [中文](README.zh-CN.md)

CopyToAsk is a lightweight macOS menu bar app that explains or answers questions about the text you currently have selected, powered by OpenAI.

## Features

- Explain selected text with a global hotkey (anchored near selection when possible)
- Ask follow-up questions in a small chat UI (streaming responses)
- Context panel: append multiple selections as “context” and reuse them across prompts
- Translate To: translate the Explain result into 8 languages (EN/ZH/JA/KO/FR/DE/ES/RU)
- Interface language: English / 中文 (affects menu labels, Settings UI, button labels, etc.)
- Explain language is separate from interface language (set in menu: Tools → Explain Language)
- Configurable prompts via `prompts.json`
- Local history (JSONL) + one-click summary to Markdown
- Built-in Diagnostics and a stable local codesign helper to avoid repeated TCC prompts

## Requirements

- macOS 13+
- Xcode Command Line Tools (`swiftc`)
- An OpenAI API key (or a Codex CLI token)

## Install / Build

```bash
./build.sh
open build/CopyToAsk.app
```

Default hotkeys:

- Explain: `Ctrl + Option + E`
- Ask: `Ctrl + Option + A`
- Add Context: `Ctrl + Option + S`

## Setup

OpenAI authentication:

1) Recommended: set `OPENAI_API_KEY` in your environment
2) Or use the app menu: Settings → OpenAI Auth… (stores the key in Keychain)
3) Or choose “Codex Login” if you already use the `codex` CLI

## Usage

- Explain: select text in any app → press Explain hotkey → get a panel near your selection
- Ask: select text → press Ask hotkey → type a question (Tab can insert a “ghost prompt”)
- Context:
  - press “Set Context” on selected text to append to context
  - open “Current Context” to review / delete / clear
- Translate To (Explain panel): pick a target language from the dropdown

## Permissions

- Accessibility (required): to read selected text and selection bounds
- Input Monitoring (optional): improves the Cmd+C fallback on newer macOS versions

### Avoid re-authorizing after rebuilds

macOS privacy permissions (TCC: Accessibility / Input Monitoring) are tied to your app’s code signature.

If you build with ad-hoc signing, macOS may treat each rebuild as a new app and prompt again.

Create a stable local self-signed identity once:

```bash
./scripts/setup_local_codesign_identity.sh
```

`build.sh` will automatically prefer the `CopyToAsk Local Dev` identity when present.

## Prompts

Prompts live in:

`~/Library/Application Support/CopyToAsk/prompts.json`

Keys (default):

- `explain.zh` / `explain.en`
- `translate` (generic translate)
- `translateExplain` (optional; falls back to `translate`)

## Data Storage

- History JSONL: `~/Library/Application Support/CopyToAsk/History/YYYY-MM-DD.jsonl`
- Summaries: `~/Library/Application Support/CopyToAsk/History/Summaries/*.md`

## CI / CD

- CI (`.github/workflows/ci.yml`): builds the app on macOS for every push / PR
- Release (`.github/workflows/release.yml`): builds and publishes a zipped `.app` on version tags (`v*`)

## Contributing

PRs are welcome.

- Keep changes focused and easy to review
- Run `./build.sh` before opening a PR
- If you touch any UI strings, consider the interface language setting (EN/ZH)

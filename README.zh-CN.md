# CopyToAsk

[![CI](https://github.com/ComDec/CopyToAsk/actions/workflows/ci.yml/badge.svg)](https://github.com/ComDec/CopyToAsk/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/ComDec/CopyToAsk)](https://github.com/ComDec/CopyToAsk/releases)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)](#%E4%BE%9D%E8%B5%96)

[English](README.md) | 中文

CopyToAsk 是一个轻量的 macOS 菜单栏应用：你在任意应用里选中一段文本后，可以用快捷键快速“解释 / 提问 / 翻译”，并支持上下文拼接与本地历史记录。

## 功能特性

- 全局快捷键解释选中文本（尽量锚定在选区附近弹出）
- Ask 聊天界面：对选中文本持续追问（流式输出）
- Context 上下文：把多段选中文本加入上下文并复用
- Translate To：把 Explain 的结果翻译成 8 种语言（英/中/日/韩/法/德/西/俄）
- 界面语言：English / 中文（影响菜单、设置页、按钮等 UI 文案）
- Explain 输出语言与界面语言独立（在菜单 Tools → Explain Language 里设置）
- `prompts.json` 可配置提示词
- 本地历史（JSONL）+ 一键汇总成 Markdown
- 自带 Diagnostics 与本地稳定签名脚本，减少反复授权（TCC）

## 依赖

- macOS 13+
- Xcode Command Line Tools（用于 `swiftc`）
- OpenAI API Key（或 Codex CLI token）

## 安装 / 构建

```bash
./build.sh
open build/CopyToAsk.app
```

默认快捷键：

- Explain：`Ctrl + Option + E`
- Ask：`Ctrl + Option + A`
- Add Context：`Ctrl + Option + S`

## 配置

OpenAI 认证方式：

1) 推荐：设置环境变量 `OPENAI_API_KEY`
2) 或：在应用菜单 `Settings…` → `OpenAI Auth…` 保存到钥匙串
3) 或：选择 “Codex Login” 使用本机 `codex` CLI 登录态

## 使用方式

- Explain：在任意应用里选中文本 → 按 Explain 快捷键
- Ask：选中文本 → 按 Ask 快捷键 → 输入问题（Tab 可插入提示语）
- Context：
  - 选中文本后按 “Set Context” 把文本追加到上下文
  - 通过 “Current Context” 查看 / 删除 / 清空
- Translate To（Explain 面板）：选择目标语言即可翻译

## 权限说明

- 辅助功能（Accessibility，必需）：读取选中文本与选区位置
- 输入监控（Input Monitoring，可选）：在较新 macOS 上改善 Cmd+C 兜底路径

### 避免每次重建都要重新授权

macOS 的隐私权限（TCC，例如 Accessibility）与应用的代码签名绑定。

如果使用 ad-hoc 签名，系统可能把每次重建都当成新应用，导致反复授权。

建议只需执行一次：

```bash
./scripts/setup_local_codesign_identity.sh
```

之后 `build.sh` 会优先使用 `CopyToAsk Local Dev` 这个本地签名身份。

## Prompts

提示词文件位置：

`~/Library/Application Support/CopyToAsk/prompts.json`

默认字段：

- `explain.zh` / `explain.en`
- `translate`（通用翻译）
- `translateExplain`（可选；缺省时回退到 `translate`）

## 数据存储

- History JSONL：`~/Library/Application Support/CopyToAsk/History/YYYY-MM-DD.jsonl`
- Summaries：`~/Library/Application Support/CopyToAsk/History/Summaries/*.md`

## CI / CD

- CI（`.github/workflows/ci.yml`）：每次 push / PR 都会在 macOS 上构建
- Release（`.github/workflows/release.yml`）：打 tag（`v*`）自动生成 zip 并发布

## 贡献

欢迎提 PR：

- 保持改动聚焦、易审阅
- 提 PR 前请运行 `./build.sh`
- 如果改动了 UI 文案，请注意界面语言（EN/ZH）

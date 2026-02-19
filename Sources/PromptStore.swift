import Foundation
import Cocoa

struct PromptStore {
  struct PromptConfig: Codable {
    struct Explain: Codable {
      var zh: String
      var en: String
    }

    var explain: Explain
    var translate: String
    var translateExplain: String?

    static func `default`() -> PromptConfig {
      PromptConfig(
        explain: .init(zh: defaultExplainTemplateZh, en: defaultExplainTemplateEn),
        translate: defaultTranslateTemplate,
        translateExplain: defaultTranslateExplainTemplate
      )
    }
  }

  init() {}

  func explainTemplate(language: AnswerLanguage) -> String {
    let cfg = loadConfigEnsuringFile()
    switch language {
    case .zh: return cfg.explain.zh
    case .en: return cfg.explain.en
    }
  }

  func translateTemplate() -> String {
    loadConfigEnsuringFile().translate
  }

  func translateExplainTemplate() -> String {
    let cfg = loadConfigEnsuringFile()
    let t = (cfg.translateExplain ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? cfg.translate : t
  }

  func configFileURL() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return base.appendingPathComponent("CopyToAsk", isDirectory: true)
      .appendingPathComponent("prompts.json")
  }

  func ensureConfigFileExists() {
    let url = configFileURL()
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: url.path) {
      resetToDefaultConfig()
    }
  }

  func resetToDefaultConfig() {
    let url = configFileURL()
    let dir = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(PromptConfig.default()) {
      try? data.write(to: url, options: [.atomic])
    }
  }

  func revealConfigInFinder() {
    ensureConfigFileExists()
    NSWorkspace.shared.activateFileViewerSelecting([configFileURL()])
  }

  func openConfigInEditor() {
    ensureConfigFileExists()
    NSWorkspace.shared.open(configFileURL())
  }

  private func loadConfigEnsuringFile() -> PromptConfig {
    ensureConfigFileExists()
    let url = configFileURL()
    guard let data = try? Data(contentsOf: url) else { return .default() }
    let decoder = JSONDecoder()
    if let cfg = try? decoder.decode(PromptConfig.self, from: data) {
      return cfg
    }
    return .default()
  }

  static let defaultExplainTemplateZh = """
你会收到两段输入：
1) 上下文（可为空）
2) 当前选中文本

上下文：
{context}

选中文本：
{text}

要求：
1) 先用一句话概括
2) 再用 3-6 条要点解释关键概念/隐含前提
3) 如有必要给 1 个简短例子
4) 不确定的地方明确说明不确定
"""

  static let defaultExplainTemplateEn = """
You will receive two inputs:
1) Context (may be empty)
2) Selected text

Context:
{context}

Selected text:
{text}

Requirements:
1) One-sentence summary
2) 3-6 bullet points explaining key concepts/assumptions
3) One short example if helpful
4) If uncertain, say so explicitly
"""

  static let defaultTranslateTemplate = """
Translate the following text to {target_language}.

Rules:
- Preserve formatting (lists/line breaks/code blocks) as much as possible.
- Do not add new information.
- If there are proper nouns, keep them as-is unless the target language commonly translates them.

Text:
{text}
"""

  static let defaultTranslateExplainTemplate = defaultTranslateTemplate
}

enum PromptTemplate {
  static func render(_ template: String, variables: [String: String]) -> String {
    var out = template
    for (k, v) in variables {
      out = out.replacingOccurrences(of: "{\(k)}", with: v)
    }
    return out
  }
}

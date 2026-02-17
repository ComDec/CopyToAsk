import Foundation

struct PromptStore {
  private enum Keys {
    static let explainTemplate = "prompt.explainTemplate"
    static let translateTemplate = "prompt.translateTemplate"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func explainTemplate() -> String {
    (defaults.string(forKey: Keys.explainTemplate) ?? Self.defaultExplainTemplate)
  }

  func translateTemplate() -> String {
    (defaults.string(forKey: Keys.translateTemplate) ?? Self.defaultTranslateTemplate)
  }

  func setExplainTemplate(_ value: String) {
    defaults.set(value, forKey: Keys.explainTemplate)
  }

  func setTranslateTemplate(_ value: String) {
    defaults.set(value, forKey: Keys.translateTemplate)
  }

  func resetExplainTemplate() {
    defaults.removeObject(forKey: Keys.explainTemplate)
  }

  func resetTranslateTemplate() {
    defaults.removeObject(forKey: Keys.translateTemplate)
  }

  static let defaultExplainTemplate = """
请解释下面这段文字的含义，用尽量简明的中文输出：

{text}

要求：
1) 先用一句话概括
2) 再用 3-6 条要点解释关键概念/隐含前提
3) 如有必要给 1 个简短例子
4) 不确定的地方明确说明不确定
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

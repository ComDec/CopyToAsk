import Foundation

enum InterfaceLanguage: String, CaseIterable {
  case en
  case zh

  var displayName: String {
    switch self {
    case .en: return "English"
    case .zh: return "中文"
    }
  }
}

enum TranslateLanguage: String, CaseIterable {
  case en
  case zh
  case ja
  case ko
  case fr
  case de
  case es
  case ru

  static let supported8: [TranslateLanguage] = [.en, .zh, .ja, .ko, .fr, .de, .es, .ru]

  func displayName(interface: InterfaceLanguage) -> String {
    switch interface {
    case .en:
      switch self {
      case .en: return "English"
      case .zh: return "Chinese"
      case .ja: return "Japanese"
      case .ko: return "Korean"
      case .fr: return "French"
      case .de: return "German"
      case .es: return "Spanish"
      case .ru: return "Russian"
      }
    case .zh:
      switch self {
      case .en: return "英语"
      case .zh: return "中文"
      case .ja: return "日语"
      case .ko: return "韩语"
      case .fr: return "法语"
      case .de: return "德语"
      case .es: return "西班牙语"
      case .ru: return "俄语"
      }
    }
  }

  // Keep prompt language names in English; the template is English.
  var targetLanguageNameForPrompt: String {
    switch self {
    case .en: return "English"
    case .zh: return "Chinese"
    case .ja: return "Japanese"
    case .ko: return "Korean"
    case .fr: return "French"
    case .de: return "German"
    case .es: return "Spanish"
    case .ru: return "Russian"
    }
  }
}

extension AnswerLanguage {
  var asTranslateLanguage: TranslateLanguage {
    switch self {
    case .en: return .en
    case .zh: return .zh
    }
  }
}

enum L10nKey {
  case statusTitle
  case menuExplain
  case menuAsk
  case menuSetContext
  case menuCurrentContext
  case menuClearContext
  case menuOpenAIAuth
  case menuTools
  case menuShowDiagnostics
  case menuOpenAccessibilitySettings
  case menuOpenInputMonitoringSettings
  case menuSettings
  case menuQuit
  case menuExplainLanguage
  case explainLanguageChinese
  case explainLanguageEnglish

  case panelExplainTitle
  case panelAskTitle
  case panelSummaryTitle
  case buttonCopy
  case buttonClose
  case buttonSend
  case labelSelectedText
  case labelContext
  case labelTranslateTo

  case askGhostPrompt
  case menuHistoryFolder
}

enum L10n {
  static func text(_ key: L10nKey, lang: InterfaceLanguage) -> String {
    switch lang {
    case .en:
      switch key {
      case .statusTitle: return "Ask"
      case .menuExplain: return "Explain"
      case .menuAsk: return "Ask"
      case .menuSetContext: return "Set Context"
      case .menuCurrentContext: return "Current Context"
      case .menuClearContext: return "Clear Context"
      case .menuOpenAIAuth: return "OpenAI Auth…"
      case .menuTools: return "Tools"
      case .menuShowDiagnostics: return "Show Diagnostics"
      case .menuOpenAccessibilitySettings: return "Accessibility Settings…"
      case .menuOpenInputMonitoringSettings: return "Input Monitoring Settings…"
      case .menuSettings: return "Settings…"
      case .menuQuit: return "Quit"
      case .menuExplainLanguage: return "Explain Language"
      case .explainLanguageChinese: return "Chinese"
      case .explainLanguageEnglish: return "English"

      case .panelExplainTitle: return "Explain"
      case .panelAskTitle: return "Ask"
      case .panelSummaryTitle: return "Summary"
      case .buttonCopy: return "Copy"
      case .buttonClose: return "Close"
      case .buttonSend: return "Send"
      case .labelSelectedText: return "Selected text"
      case .labelContext: return "Context"
      case .labelTranslateTo: return "Translate To"

      case .askGhostPrompt: return "Ask something about the selected text… (Tab to use)"
      case .menuHistoryFolder: return "History Folder"
      }
    case .zh:
      switch key {
      case .statusTitle: return "问"
      case .menuExplain: return "解释"
      case .menuAsk: return "提问"
      case .menuSetContext: return "加入上下文"
      case .menuCurrentContext: return "当前上下文"
      case .menuClearContext: return "清空上下文"
      case .menuOpenAIAuth: return "OpenAI 登录…"
      case .menuTools: return "工具"
      case .menuShowDiagnostics: return "诊断信息"
      case .menuOpenAccessibilitySettings: return "辅助功能设置…"
      case .menuOpenInputMonitoringSettings: return "输入监控设置…"
      case .menuSettings: return "设置…"
      case .menuQuit: return "退出"
      case .menuExplainLanguage: return "解释语言"
      case .explainLanguageChinese: return "中文"
      case .explainLanguageEnglish: return "English"

      case .panelExplainTitle: return "解释"
      case .panelAskTitle: return "提问"
      case .panelSummaryTitle: return "总结"
      case .buttonCopy: return "复制"
      case .buttonClose: return "关闭"
      case .buttonSend: return "发送"
      case .labelSelectedText: return "选中文本"
      case .labelContext: return "上下文"
      case .labelTranslateTo: return "翻译为"

      case .askGhostPrompt: return "针对选中文本提问…（按 Tab 使用提示）"
      case .menuHistoryFolder: return "历史记录文件夹"
      }
    }
  }
}

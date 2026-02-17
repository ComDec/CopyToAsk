import Foundation

enum AnswerLanguage: String, CaseIterable {
  case zh
  case en

  var displayName: String {
    switch self {
    case .zh: return "中文"
    case .en: return "English"
    }
  }

  var targetLanguageNameForPrompt: String {
    switch self {
    case .zh: return "Chinese"
    case .en: return "English"
    }
  }
}

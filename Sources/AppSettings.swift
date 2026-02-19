import Foundation
import Carbon

enum ModelTier: String, CaseIterable {
  case cheap
  case medium
  case detailed

  var displayName: String {
    switch self {
    case .cheap: return "Cheap"
    case .medium: return "Medium"
    case .detailed: return "Detailed"
    }
  }
}

final class AppSettings {
  static let shared = AppSettings()

  private let d: UserDefaults

  private enum Keys {
    static let explainTier = "models.explainTier"
    static let summaryTier = "models.summaryTier"
    static let cheapModel = "models.cheapModelId"
    static let mediumModel = "models.mediumModelId"
    static let detailedModel = "models.detailedModelId"

    static let retentionEnabled = "history.retention.enabled"
    static let retentionDays = "history.retention.days"

    static let defaultLanguage = "answer.defaultLanguage"

    static let interfaceLanguage = "ui.language"

    static let hkExplainCode = "hotkeys.explain.keyCode"
    static let hkExplainMods = "hotkeys.explain.carbonModifiers"
    static let hkAskCode = "hotkeys.ask.keyCode"
    static let hkAskMods = "hotkeys.ask.carbonModifiers"
    static let hkContextCode = "hotkeys.context.keyCode"
    static let hkContextMods = "hotkeys.context.carbonModifiers"

    static let authMethod = "openai.auth.method"
  }

  private init(defaults: UserDefaults = .standard) {
    self.d = defaults
    migrateLegacyHotkeysIfNeeded()
  }

  private func migrateLegacyHotkeysIfNeeded() {
    // Legacy (v0.1) stored a single hotkey under these keys.
    let legacyCodeKey = "hotkey.keyCode"
    let legacyModsKey = "hotkey.carbonModifiers"

    if d.object(forKey: Keys.hkExplainCode) == nil,
       d.object(forKey: legacyCodeKey) != nil {
      let code = d.integer(forKey: legacyCodeKey)
      let mods = d.integer(forKey: legacyModsKey)
      d.set(code, forKey: Keys.hkExplainCode)
      d.set(mods, forKey: Keys.hkExplainMods)
    }
  }

  var explainTier: ModelTier {
    get { ModelTier(rawValue: d.string(forKey: Keys.explainTier) ?? "cheap") ?? .cheap }
    set { d.set(newValue.rawValue, forKey: Keys.explainTier) }
  }

  var summaryTier: ModelTier {
    get { ModelTier(rawValue: d.string(forKey: Keys.summaryTier) ?? "medium") ?? .medium }
    set { d.set(newValue.rawValue, forKey: Keys.summaryTier) }
  }

  var cheapModelId: String {
    get { d.string(forKey: Keys.cheapModel) ?? "gpt-4o-mini" }
    set { d.set(newValue, forKey: Keys.cheapModel) }
  }

  var mediumModelId: String {
    get { d.string(forKey: Keys.mediumModel) ?? "gpt-4o" }
    set { d.set(newValue, forKey: Keys.mediumModel) }
  }

  var detailedModelId: String {
    // Default is editable.
    get { d.string(forKey: Keys.detailedModel) ?? "gpt-4o" }
    set { d.set(newValue, forKey: Keys.detailedModel) }
  }

  func modelId(for tier: ModelTier) -> String {
    switch tier {
    case .cheap: return cheapModelId
    case .medium: return mediumModelId
    case .detailed: return detailedModelId
    }
  }

  var historyRetentionEnabled: Bool {
    get {
      if d.object(forKey: Keys.retentionEnabled) == nil { return true }
      return d.bool(forKey: Keys.retentionEnabled)
    }
    set { d.set(newValue, forKey: Keys.retentionEnabled) }
  }

  var historyRetentionDays: Int {
    get {
      let v = d.integer(forKey: Keys.retentionDays)
      return v > 0 ? v : 30
    }
    set {
      d.set(max(1, newValue), forKey: Keys.retentionDays)
    }
  }

  var defaultAnswerLanguage: AnswerLanguage {
    get { AnswerLanguage(rawValue: d.string(forKey: Keys.defaultLanguage) ?? "zh") ?? .zh }
    set { d.set(newValue.rawValue, forKey: Keys.defaultLanguage) }
  }

  var interfaceLanguage: InterfaceLanguage {
    get { InterfaceLanguage(rawValue: d.string(forKey: Keys.interfaceLanguage) ?? "en") ?? .en }
    set { d.set(newValue.rawValue, forKey: Keys.interfaceLanguage) }
  }

  enum AuthMethod: String {
    case apiKey
    case codex
  }

  var openAIAuthMethod: AuthMethod {
    get { AuthMethod(rawValue: d.string(forKey: Keys.authMethod) ?? "apiKey") ?? .apiKey }
    set { d.set(newValue.rawValue, forKey: Keys.authMethod) }
  }

  func hotKey(for action: HotKeyAction) -> HotKeyDefinition {
    switch action {
    case .explain:
      return loadHotKey(codeKey: Keys.hkExplainCode, modsKey: Keys.hkExplainMods, fallback: HotKeyDefinition(keyCode: 14, carbonModifiers: UInt32(controlKey | optionKey)))
    case .ask:
      // Default: Control+Option+A
      return loadHotKey(codeKey: Keys.hkAskCode, modsKey: Keys.hkAskMods, fallback: HotKeyDefinition(keyCode: 0, carbonModifiers: UInt32(controlKey | optionKey)))
    case .setContext:
      // Default: Control+Option+S
      return loadHotKey(codeKey: Keys.hkContextCode, modsKey: Keys.hkContextMods, fallback: HotKeyDefinition(keyCode: 1, carbonModifiers: UInt32(controlKey | optionKey)))
    }
  }

  func setHotKey(_ def: HotKeyDefinition, for action: HotKeyAction) {
    switch action {
    case .explain:
      d.set(Int(def.keyCode), forKey: Keys.hkExplainCode)
      d.set(Int(def.carbonModifiers), forKey: Keys.hkExplainMods)
    case .ask:
      d.set(Int(def.keyCode), forKey: Keys.hkAskCode)
      d.set(Int(def.carbonModifiers), forKey: Keys.hkAskMods)
    case .setContext:
      d.set(Int(def.keyCode), forKey: Keys.hkContextCode)
      d.set(Int(def.carbonModifiers), forKey: Keys.hkContextMods)
    }
  }

  private func loadHotKey(codeKey: String, modsKey: String, fallback: HotKeyDefinition) -> HotKeyDefinition {
    if d.object(forKey: codeKey) == nil { return fallback }
    let code = d.integer(forKey: codeKey)
    let mods = d.integer(forKey: modsKey)
    return HotKeyDefinition(keyCode: UInt32(code), carbonModifiers: UInt32(mods))
  }
}

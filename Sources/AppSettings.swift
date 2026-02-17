import Foundation

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
  }

  private init(defaults: UserDefaults = .standard) {
    self.d = defaults
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
}

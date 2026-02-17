import Foundation
import Cocoa

struct HistoryEntry: Codable {
  var id: String
  var timestamp: Date
  var appName: String?
  var bundleIdentifier: String?
  var selectionText: String
  var language: String
  var outputText: String
  var model: String
  var source: String
}

final class HistoryStore {
  static let shared = HistoryStore()

  private let fm = FileManager.default
  private let encoder: JSONEncoder

  private init() {
    let e = JSONEncoder()
    e.outputFormatting = []
    e.dateEncodingStrategy = .iso8601
    encoder = e
  }

  func historyDirectoryURL() -> URL {
    let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return base.appendingPathComponent("CopyToAsk", isDirectory: true)
      .appendingPathComponent("History", isDirectory: true)
  }

  func openHistoryFolderInFinder() {
    let url = historyDirectoryURL()
    try? fm.createDirectory(at: url, withIntermediateDirectories: true)
    NSWorkspace.shared.open(url)
  }

  func append(_ entry: HistoryEntry) throws {
    let dir = historyDirectoryURL()
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)

    let day = Self.dayString(for: entry.timestamp)
    let fileURL = dir.appendingPathComponent("\(day).jsonl")

    let data = try encoder.encode(entry)
    var line = data
    line.append(0x0A) // \n

    if fm.fileExists(atPath: fileURL.path) {
      let handle = try FileHandle(forWritingTo: fileURL)
      try handle.seekToEnd()
      try handle.write(contentsOf: line)
      try handle.close()
    } else {
      try line.write(to: fileURL, options: [.atomic])
    }
  }

  func pruneIfEnabled(enabled: Bool, keepDays: Int) -> Int {
    guard enabled else { return 0 }
    return prune(keepDays: keepDays)
  }

  func prune(keepDays: Int) -> Int {
    let dir = historyDirectoryURL()
    let cutoff = Calendar.current.date(byAdding: .day, value: -max(1, keepDays), to: Date()) ?? Date.distantPast

    let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
    let jsonls = files.filter { $0.pathExtension.lowercased() == "jsonl" }

    var deleted = 0
    for url in jsonls {
      let day = url.deletingPathExtension().lastPathComponent
      if let date = Self.dateFromDayString(day) {
        if date < cutoff {
          if (try? fm.removeItem(at: url)) != nil { deleted += 1 }
        }
      } else {
        // Fallback to file mtime.
        let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        if let m = attrs?.contentModificationDate, m < cutoff {
          if (try? fm.removeItem(at: url)) != nil { deleted += 1 }
        }
      }
    }
    return deleted
  }

  private static func dayString(for date: Date) -> String {
    let cal = Calendar.current
    let c = cal.dateComponents([.year, .month, .day], from: date)
    let y = c.year ?? 1970
    let m = c.month ?? 1
    let d = c.day ?? 1
    return String(format: "%04d-%02d-%02d", y, m, d)
  }

  private static func dateFromDayString(_ s: String) -> Date? {
    // Expect YYYY-MM-DD
    let parts = s.split(separator: "-")
    if parts.count != 3 { return nil }
    guard let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
    var comps = DateComponents()
    comps.year = y
    comps.month = m
    comps.day = d
    comps.hour = 0
    comps.minute = 0
    comps.second = 0
    return Calendar.current.date(from: comps)
  }
}

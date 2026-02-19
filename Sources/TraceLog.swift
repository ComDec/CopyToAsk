import Foundation

enum TraceLog {
  // Enable with: COPYTOASK_TRACE_UI=1
  static let enabled: Bool = {
    let v = (ProcessInfo.processInfo.environment["COPYTOASK_TRACE_UI"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return !v.isEmpty && v != "0"
  }()

  static func log(_ message: String) {
    guard enabled else { return }
    let url = URL(fileURLWithPath: "/tmp/copytoask_ui.log")
    let ts = String(format: "%.6f", Date().timeIntervalSince1970)
    let line = "\(ts) \(message)\n"
    guard let data = line.data(using: .utf8) else { return }

    if !FileManager.default.fileExists(atPath: url.path) {
      FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    guard let fh = try? FileHandle(forWritingTo: url) else { return }
    fh.seekToEndOfFile()
    fh.write(data)
    try? fh.close()
  }
}

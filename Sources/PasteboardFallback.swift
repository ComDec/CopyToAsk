import Cocoa
import ApplicationServices

@MainActor
enum PasteboardFallback {
  private struct Snapshot {
    let items: [NSPasteboardItem]
  }

  static func copySelectionViaCmdCAndReadPasteboard() -> String? {
    let pb = NSPasteboard.general
    let beforeChange = pb.changeCount
    let snapshot = snapshotPasteboard(pb)

    // Trigger Cmd+C
    postCmdC()

    // Wait for pasteboard to update (best-effort). If copy injection is blocked
    // by system privacy, changeCount may not advance; in that case, fail.
    var copied: String?
    var didUpdate = false
    let deadline = Date().addingTimeInterval(0.8)
    while Date() < deadline {
      if pb.changeCount != beforeChange {
        didUpdate = true
        copied = pb.string(forType: .string)
        break
      }
      Thread.sleep(forTimeInterval: 0.03)
    }

    // Restore pasteboard (best-effort)
    restorePasteboard(pb, snapshot: snapshot)

    // If copy never updated the pasteboard, don't return a stale clipboard value.
    return didUpdate ? copied : nil
  }

  static func copySelectionViaCmdCAndReadPasteboardAsync() async -> String? {
    let pb = NSPasteboard.general
    let beforeChange = pb.changeCount
    let snapshot = snapshotPasteboard(pb)

    postCmdC()

    let start = Date()
    var copied: String?
    var didUpdate = false
    while Date().timeIntervalSince(start) < 0.8 {
      if pb.changeCount != beforeChange {
        didUpdate = true
        copied = pb.string(forType: .string)
        break
      }
      try? await Task.sleep(nanoseconds: 30_000_000)
    }

    restorePasteboard(pb, snapshot: snapshot)
    return didUpdate ? copied : nil
  }

  private static func snapshotPasteboard(_ pb: NSPasteboard) -> Snapshot {
    let items = (pb.pasteboardItems ?? []).map { item in
      let clone = NSPasteboardItem()
      for t in item.types {
        if let data = item.data(forType: t) {
          clone.setData(data, forType: t)
        }
      }
      return clone
    }
    return Snapshot(items: items)
  }

  private static func restorePasteboard(_ pb: NSPasteboard, snapshot: Snapshot) {
    pb.clearContents()
    for item in snapshot.items {
      pb.writeObjects([item])
    }
  }

  private static func postCmdC() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true) // 'c'
    keyDown?.flags = .maskCommand
    let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
    keyUp?.flags = .maskCommand
    keyDown?.post(tap: .cghidEventTap)
    keyUp?.post(tap: .cghidEventTap)
  }
}

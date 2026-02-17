import Cocoa
import ApplicationServices

enum PasteboardFallback {
  private struct Snapshot {
    let items: [NSPasteboardItem]
  }

  static func copySelectionViaCmdCAndReadPasteboard() -> String? {
    let pb = NSPasteboard.general
    let snapshot = snapshotPasteboard(pb)

    // Trigger Cmd+C
    postCmdC()

    // Wait briefly for pasteboard to update
    Thread.sleep(forTimeInterval: 0.12)

    let copied = pb.string(forType: .string)

    // Restore pasteboard (best-effort)
    restorePasteboard(pb, snapshot: snapshot)

    return copied
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

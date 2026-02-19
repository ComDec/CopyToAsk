import Cocoa

// Deprecated: we no longer rely on highlight overlays for context.
@MainActor
final class ContextHighlightWindowController {
  private var window: NSWindow?
  private var view: HighlightView?

  func show(rect: CGRect) {
    ensureWindow()
    guard let window, let view else { return }

    // Expand a bit for a nicer outline.
    let frame = rect.insetBy(dx: -4, dy: -3)
    window.setFrame(frame, display: true)
    view.highlightRect = CGRect(origin: .zero, size: frame.size)
    window.orderFrontRegardless()
  }

  func hide() {
    window?.orderOut(nil)
  }

  private func ensureWindow() {
    if window != nil { return }

    let w = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.ignoresMouseEvents = true
    w.level = .statusBar
    w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let v = HighlightView(frame: w.contentView?.bounds ?? .zero)
    v.autoresizingMask = [.width, .height]
    w.contentView = v

    window = w
    view = v
  }
}

final class HighlightView: NSView {
  var highlightRect: CGRect = .zero {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard !highlightRect.isEmpty else { return }

    let r = highlightRect.insetBy(dx: 2, dy: 2)
    let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)

    NSColor.systemYellow.withAlphaComponent(0.18).setFill()
    path.fill()

    NSColor.systemYellow.withAlphaComponent(0.85).setStroke()
    path.lineWidth = 2
    path.stroke()
  }
}

import Cocoa

@MainActor
final class ExplainPanelController: NSObject {
  private var panel: NSPanel?
  private var bodyTextView: NSTextView?
  private var languageControl: NSSegmentedControl?

  var onLanguageChanged: ((AnswerLanguage) -> Void)?
  var onClose: (() -> Void)?

  func show(message: String, anchor: SelectionAnchor, language: AnswerLanguage = .zh) {
    ensurePanel()
    setBodyText(message)
    setLanguage(language)
    positionPanel(anchor: anchor)
    panel?.orderFrontRegardless()
  }

  func close() {
    panel?.orderOut(nil)
    onClose?()
  }

  func setBodyText(_ text: String) {
    bodyTextView?.string = text
    bodyTextView?.scrollToEndOfDocument(nil)
  }

  func setLanguage(_ lang: AnswerLanguage) {
    languageControl?.selectedSegment = (lang == .zh) ? 0 : 1
  }

  func setLanguageEnabled(_ enabled: Bool) {
    languageControl?.isEnabled = enabled
  }

  private func ensurePanel() {
    if panel != nil { return }

    let style: NSWindow.StyleMask = [.titled, .fullSizeContentView, .nonactivatingPanel]
    let p = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 260),
      styleMask: style,
      backing: .buffered,
      defer: false
    )
    p.titleVisibility = .hidden
    p.titlebarAppearsTransparent = true
    p.isMovableByWindowBackground = true
    p.isFloatingPanel = true
    p.level = .floating
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    p.isReleasedWhenClosed = false
    p.hasShadow = true
    p.backgroundColor = .clear
    p.hidesOnDeactivate = false

    // Ensure the only close affordance is our in-content button.
    p.standardWindowButton(.closeButton)?.isHidden = true
    p.standardWindowButton(.miniaturizeButton)?.isHidden = true
    p.standardWindowButton(.zoomButton)?.isHidden = true

    let blur = NSVisualEffectView()
    blur.material = .hudWindow
    blur.blendingMode = .behindWindow
    blur.state = .active
    blur.wantsLayer = true
    blur.layer?.cornerRadius = 12
    blur.layer?.masksToBounds = true

    let title = NSTextField(labelWithString: "Explain")
    title.font = .systemFont(ofSize: 13, weight: .semibold)
    title.textColor = .labelColor

    let lang = NSSegmentedControl(labels: [AnswerLanguage.zh.displayName, AnswerLanguage.en.displayName], trackingMode: .selectOne, target: self, action: #selector(languageChanged))
    lang.selectedSegment = 0
    lang.segmentStyle = .rounded
    lang.controlSize = .small
    self.languageControl = lang

    let closeButton = NSButton(title: "Close", target: self, action: #selector(closeTapped))
    closeButton.bezelStyle = .rounded

    let copyButton = NSButton(title: "Copy", target: self, action: #selector(copyTapped))
    copyButton.bezelStyle = .rounded

    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false

    let textView = NSTextView()
    textView.isEditable = false
    textView.drawsBackground = false
    textView.font = .systemFont(ofSize: 13)
    textView.textColor = .labelColor
    textView.textContainerInset = NSSize(width: 6, height: 8)
    scroll.documentView = textView
    self.bodyTextView = textView

    let content = NSView()
    content.addSubview(blur)
    blur.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      blur.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      blur.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      blur.topAnchor.constraint(equalTo: content.topAnchor),
      blur.bottomAnchor.constraint(equalTo: content.bottomAnchor),
    ])

    blur.addSubview(title)
    blur.addSubview(lang)
    blur.addSubview(closeButton)
    blur.addSubview(copyButton)
    blur.addSubview(scroll)

    title.translatesAutoresizingMaskIntoConstraints = false
    lang.translatesAutoresizingMaskIntoConstraints = false
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    copyButton.translatesAutoresizingMaskIntoConstraints = false
    scroll.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      title.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 14),
      title.topAnchor.constraint(equalTo: blur.topAnchor, constant: 10),

      lang.centerYAnchor.constraint(equalTo: title.centerYAnchor),
      lang.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -10),

      closeButton.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -12),
      closeButton.topAnchor.constraint(equalTo: blur.topAnchor, constant: 6),

      copyButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
      copyButton.topAnchor.constraint(equalTo: blur.topAnchor, constant: 6),

      scroll.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 10),
      scroll.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -10),
      scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
      scroll.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -10),
    ])

    p.contentView = content
    panel = p
  }

  @objc private func languageChanged() {
    let idx = languageControl?.selectedSegment ?? 0
    let lang: AnswerLanguage = (idx == 1) ? .en : .zh
    onLanguageChanged?(lang)
  }

  private func positionPanel(anchor: SelectionAnchor) {
    guard let panel else { return }

    let panelSize = panel.frame.size

    let screen = screenFor(anchor: anchor) ?? NSScreen.main
    let visible = screen?.visibleFrame

    func clampToVisible(_ r: NSRect) -> NSRect {
      guard let visible else { return r }
      return clamp(rect: r, to: visible)
    }

    let frame: NSRect
    switch anchor {
    case .rect(let rect):
      // Prefer below selection; if it doesn't fit, place above.
      let below = NSRect(
        x: rect.minX,
        y: rect.minY - panelSize.height - 10,
        width: panelSize.width,
        height: panelSize.height
      )
      let above = NSRect(
        x: rect.minX,
        y: rect.maxY + 10,
        width: panelSize.width,
        height: panelSize.height
      )

      if let visible {
        if visible.contains(below) {
          frame = below
        } else if visible.contains(above) {
          frame = above
        } else {
          // Pick the one with larger intersection area.
          let bArea = visible.intersection(below).width * visible.intersection(below).height
          let aArea = visible.intersection(above).width * visible.intersection(above).height
          frame = (aArea > bArea) ? clampToVisible(above) : clampToVisible(below)
        }
      } else {
        frame = below
      }

    case .mouse:
      let m = NSEvent.mouseLocation
      let r = NSRect(x: m.x + 12, y: m.y - panelSize.height - 12, width: panelSize.width, height: panelSize.height)
      frame = clampToVisible(r)
    }

    panel.setFrame(frame, display: false)
  }

  private func screenFor(anchor: SelectionAnchor) -> NSScreen? {
    switch anchor {
    case .rect(let rect):
      return NSScreen.screens.first(where: { $0.frame.intersects(rect) })
    case .mouse:
      let p = NSEvent.mouseLocation
      return NSScreen.screens.first(where: { $0.frame.contains(p) })
    }
  }

  private func clamp(rect: NSRect, to bounds: NSRect) -> NSRect {
    var r = rect
    if r.maxX > bounds.maxX { r.origin.x = bounds.maxX - r.size.width }
    if r.minX < bounds.minX { r.origin.x = bounds.minX }
    if r.maxY > bounds.maxY { r.origin.y = bounds.maxY - r.size.height }
    if r.minY < bounds.minY { r.origin.y = bounds.minY }
    return r
  }

  @objc private func closeTapped() {
    close()
  }

  @objc private func copyTapped() {
    let text = bodyTextView?.string ?? ""
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
  }
}

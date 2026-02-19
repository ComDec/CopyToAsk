import Cocoa

@MainActor
final class ContextPanelController: NSObject {
  private var panel: NSPanel?
  private var listStack: NSStackView?
  private var emptyLabel: NSTextField?

  var onClear: (() -> Void)?
  var onDeleteItem: ((UUID) -> Void)?
  var isVisible: Bool { panel?.isVisible == true }

  func show(items: [ContextItem], anchor: SelectionAnchor) {
    TraceLog.log("ContextPanelController.show items=\(items.count)")
    ensurePanel()
    reload(items: items)
    positionPanel(anchor: anchor)
    // Do not steal focus from the source app.
    panel?.orderFrontRegardless()
  }

  func hide() {
    panel?.orderOut(nil)
  }

  private func ensurePanel() {
    if panel != nil { return }

    let style: NSWindow.StyleMask = [.titled, .fullSizeContentView, .nonactivatingPanel]
    let p = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
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
    p.isOpaque = false
    p.hidesOnDeactivate = false

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

    let title = NSTextField(labelWithString: "Current Context")
    title.font = .systemFont(ofSize: 13, weight: .semibold)
    title.textColor = .labelColor

    let clearButton = NSButton(title: "Clear All", target: self, action: #selector(clearTapped))
    clearButton.bezelStyle = .rounded

    let closeButton = NSButton(title: "Close", target: self, action: #selector(closeTapped))
    closeButton.bezelStyle = .rounded

    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 10
    stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    stack.translatesAutoresizingMaskIntoConstraints = false
    self.listStack = stack

    let doc = NSView()
    doc.addSubview(stack)
    doc.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
      stack.topAnchor.constraint(equalTo: doc.topAnchor),
      stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
      doc.widthAnchor.constraint(equalToConstant: 380),
    ])
    scroll.documentView = doc

    let empty = NSTextField(labelWithString: "No context set. Use the context hotkey to append selections.")
    empty.font = .systemFont(ofSize: 12)
    empty.textColor = .secondaryLabelColor
    empty.maximumNumberOfLines = 0
    empty.lineBreakMode = .byWordWrapping
    emptyLabel = empty

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
    blur.addSubview(clearButton)
    blur.addSubview(closeButton)
    blur.addSubview(scroll)
    blur.addSubview(empty)

    title.translatesAutoresizingMaskIntoConstraints = false
    clearButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    empty.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      title.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 14),
      title.topAnchor.constraint(equalTo: blur.topAnchor, constant: 10),

      closeButton.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -12),
      closeButton.topAnchor.constraint(equalTo: blur.topAnchor, constant: 6),

      clearButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
      clearButton.topAnchor.constraint(equalTo: blur.topAnchor, constant: 6),

      empty.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 12),
      empty.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -12),
      empty.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 10),

      scroll.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 10),
      scroll.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -10),
      scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
      scroll.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -10),
    ])

    p.contentView = content
    panel = p
  }

  private func reload(items: [ContextItem]) {
    listStack?.arrangedSubviews.forEach { v in
      listStack?.removeArrangedSubview(v)
      v.removeFromSuperview()
    }

    let has = !items.isEmpty
    emptyLabel?.isHidden = has
    listStack?.isHidden = !has

    guard has else { return }

    for item in items {
      let card = ContextCardView(id: item.id, text: item.text)
      card.onDelete = { [weak self] id in
        self?.onDeleteItem?(id)
      }
      listStack?.addArrangedSubview(card)
      card.widthAnchor.constraint(equalToConstant: 380).isActive = true
    }
  }

  private func positionPanel(anchor: SelectionAnchor) {
    guard let panel else { return }
    let size = panel.frame.size
    let screen = screenFor(anchor: anchor) ?? NSScreen.main
    let visible = screen?.visibleFrame

    let origin: CGPoint
    switch anchor {
    case .rect(let rect):
      origin = CGPoint(x: rect.minX, y: rect.maxY + 12)
    case .mouse:
      let m = NSEvent.mouseLocation
      origin = CGPoint(x: m.x + 12, y: m.y + 12)
    }

    var frame = NSRect(origin: origin, size: size)
    if let visible {
      if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.size.width }
      if frame.minX < visible.minX { frame.origin.x = visible.minX }
      if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.size.height }
      if frame.minY < visible.minY { frame.origin.y = visible.minY }
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

  @objc private func clearTapped() {
    onClear?()
  }

  @objc private func closeTapped() {
    hide()
  }
}

struct ContextItem {
  let id: UUID
  let text: String
}

final class ContextCardView: NSView {
  let id: UUID
  var onDelete: ((UUID) -> Void)?

  init(id: UUID, text: String) {
    self.id = id
    super.init(frame: .zero)

    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.separatorColor.cgColor
    layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.35).cgColor

    let delete = NSButton()
    delete.title = ""
    delete.isBordered = false
    delete.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Delete")
    delete.contentTintColor = .secondaryLabelColor
    delete.target = self
    delete.action = #selector(deleteTapped)
    delete.translatesAutoresizingMaskIntoConstraints = false
    delete.setButtonType(.momentaryChange)
    delete.bezelStyle = .regularSquare
    delete.focusRingType = .none

    let label = NSTextField(labelWithString: text)
    label.font = .systemFont(ofSize: 12)
    label.textColor = .labelColor
    label.maximumNumberOfLines = 0
    label.lineBreakMode = .byWordWrapping
    label.translatesAutoresizingMaskIntoConstraints = false

    addSubview(label)
    addSubview(delete)
    translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      delete.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      delete.topAnchor.constraint(equalTo: topAnchor, constant: 8),
      delete.widthAnchor.constraint(equalToConstant: 16),
      delete.heightAnchor.constraint(equalToConstant: 16),

      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      label.trailingAnchor.constraint(lessThanOrEqualTo: delete.leadingAnchor, constant: -8),
      label.topAnchor.constraint(equalTo: topAnchor, constant: 10),

      label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  @objc private func deleteTapped() {
    onDelete?(id)
  }
}

import Cocoa

@MainActor
final class AskInputBar: NSView {
  let textView: AskInputTextView
  private let scroll: NSScrollView
  private let sendButton: NSButton

  var onSend: ((String) -> Void)?

  init(ghostPrompt: String) {
    let tv = AskInputTextView()
    tv.ghostPrompt = ghostPrompt
    self.textView = tv

    scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false

    sendButton = NSButton(title: "Send", target: nil, action: nil)
    super.init(frame: .zero)

    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.separatorColor.cgColor
    layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.20).cgColor

    tv.isRichText = false
    tv.font = .systemFont(ofSize: 12)
    tv.textColor = .labelColor
    tv.drawsBackground = false
    tv.textContainerInset = NSSize(width: 6, height: 8)

    scroll.documentView = tv

    sendButton.target = self
    sendButton.action = #selector(sendTapped)
    sendButton.bezelStyle = .rounded

    addSubview(scroll)
    addSubview(sendButton)
    scroll.translatesAutoresizingMaskIntoConstraints = false
    sendButton.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      sendButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      sendButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
      sendButton.widthAnchor.constraint(equalToConstant: 64),

      scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      scroll.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -10),
      scroll.topAnchor.constraint(equalTo: topAnchor, constant: 10),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

      heightAnchor.constraint(greaterThanOrEqualToConstant: 56),
    ])

    tv.onSubmit = { [weak self] in
      self?.sendTapped()
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func setGhostPrompt(_ text: String) {
    textView.ghostPrompt = text
  }

  func setSendButtonTitle(_ title: String) {
    sendButton.title = title
  }

  func focus() {
    window?.makeFirstResponder(textView)
  }

  func setInteractionEnabled(_ enabled: Bool) {
    textView.isEditable = enabled
    sendButton.isEnabled = enabled
  }

  func clear() {
    textView.string = ""
    textView.updateGhostVisibility()
  }

  @objc private func sendTapped() {
    let s = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !s.isEmpty else { return }
    onSend?(s)
  }
}

final class AskInputTextView: NSTextView {
  var ghostPrompt: String = "" {
    didSet { ghostLabel.stringValue = ghostPrompt; updateGhostVisibility() }
  }

  var onSubmit: (() -> Void)?

  private let ghostLabel: NSTextField = {
    let l = NSTextField(labelWithString: "")
    l.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.9)
    l.font = .systemFont(ofSize: 12)
    l.isSelectable = false
    l.isEditable = false
    l.lineBreakMode = .byWordWrapping
    l.maximumNumberOfLines = 2
    l.alphaValue = 0.0
    return l
  }()

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    if ghostLabel.superview == nil {
      addSubview(ghostLabel)
      ghostLabel.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        ghostLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
        ghostLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
        ghostLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
      ])
    }
    updateGhostVisibility()
  }

  override var string: String {
    didSet { updateGhostVisibility() }
  }

  func updateGhostVisibility() {
    let empty = self.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    ghostLabel.alphaValue = empty ? 1.0 : 0.0
  }

  override func didChangeText() {
    super.didChangeText()
    updateGhostVisibility()
  }

  override func keyDown(with event: NSEvent) {
    // Tab inserts the ghost prompt when empty.
    if event.keyCode == 48 {
      if string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        string = ghostPrompt
        setSelectedRange(NSRange(location: string.count, length: 0))
      }
      return
    }

    // Backspace clears the inserted ghost prompt in one shot.
    if event.keyCode == 51 {
      if string == ghostPrompt {
        string = ""
        return
      }
    }

    // Enter submits; Shift+Enter inserts newline.
    if event.keyCode == 36 {
      if event.modifierFlags.contains(.shift) {
        super.keyDown(with: event)
      } else {
        onSubmit?()
      }
      return
    }

    super.keyDown(with: event)
  }
}

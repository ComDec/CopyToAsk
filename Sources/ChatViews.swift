import Cocoa

@MainActor
final class ChatBubbleView: NSView {
  enum Role {
    case user
    case assistant
    case system
  }

  private let role: Role
  private let iconView = NSImageView()
  private let bubble = NSView()
  private let label = NSTextField(labelWithString: "")

  init(role: Role) {
    self.role = role
    super.init(frame: .zero)

    translatesAutoresizingMaskIntoConstraints = false

    let iconName: String
    switch role {
    case .user: iconName = "person.fill"
    case .assistant: iconName = "sparkles"
    case .system: iconName = "info.circle"
    }
    iconView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
    iconView.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
    iconView.contentTintColor = .secondaryLabelColor
    iconView.translatesAutoresizingMaskIntoConstraints = false

    bubble.wantsLayer = true
    bubble.layer?.cornerRadius = 12
    bubble.layer?.borderWidth = 1
    bubble.layer?.borderColor = NSColor.separatorColor.cgColor
    bubble.translatesAutoresizingMaskIntoConstraints = false

    switch role {
    case .user:
      bubble.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.14).cgColor
    case .assistant:
      bubble.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.65).cgColor
    case .system:
      bubble.layer?.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.12).cgColor
    }

    label.font = .systemFont(ofSize: 12)
    label.textColor = .labelColor
    label.maximumNumberOfLines = 0
    label.lineBreakMode = .byWordWrapping
    label.isSelectable = true
    label.translatesAutoresizingMaskIntoConstraints = false

    bubble.addSubview(label)
    addSubview(iconView)
    addSubview(bubble)

    NSLayoutConstraint.activate([
      iconView.widthAnchor.constraint(equalToConstant: 18),
      iconView.heightAnchor.constraint(equalToConstant: 18),
      iconView.topAnchor.constraint(equalTo: topAnchor, constant: 2),

      label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 10),
      label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -10),
      label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8),
      label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -8),
    ])

    // Bubble max width (window is resizable).
    bubble.widthAnchor.constraint(lessThanOrEqualToConstant: 520).isActive = true

    if role == .user {
      NSLayoutConstraint.activate([
        bubble.trailingAnchor.constraint(equalTo: trailingAnchor),
        iconView.trailingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: -8),
        iconView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
        bubble.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
        bubble.topAnchor.constraint(equalTo: topAnchor),
        bubble.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    } else {
      NSLayoutConstraint.activate([
        iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
        bubble.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
        bubble.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),
        bubble.topAnchor.constraint(equalTo: topAnchor),
        bubble.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func setPlainText(_ text: String) {
    let s = NSAttributedString(string: text, attributes: [
      .font: NSFont.systemFont(ofSize: 12),
      .foregroundColor: NSColor.labelColor,
    ])
    label.attributedStringValue = s
  }

  func setMarkdownStreaming(_ markdown: String) {
    // Keep streaming fast; render markdown on final.
    setPlainText(markdown)
  }

  func setMarkdownFinal(_ markdown: String) {
    if let rendered = renderMarkdown(markdown) {
      label.attributedStringValue = rendered
    } else {
      setPlainText(markdown)
    }
  }

  private func renderMarkdown(_ markdown: String) -> NSAttributedString? {
    if #available(macOS 12.0, *) {
      do {
        var a = try AttributedString(
          markdown: markdown,
          options: AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
          )
        )
        a.foregroundColor = .labelColor
        return NSAttributedString(a)
      } catch {
        return nil
      }
    }
    return nil
  }
}

@MainActor
final class SelectedTextHeaderView: NSView {
  private let titleLabel = NSTextField(labelWithString: "Selected text")
  private let valueTextView = NSTextView()
  private let scroll = NSScrollView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false

    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.borderWidth = 1
    layer?.borderColor = NSColor.separatorColor.cgColor
    layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor

    titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
    titleLabel.textColor = .secondaryLabelColor
    titleLabel.translatesAutoresizingMaskIntoConstraints = false

    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.translatesAutoresizingMaskIntoConstraints = false

    valueTextView.isEditable = false
    valueTextView.drawsBackground = false
    valueTextView.font = .systemFont(ofSize: 11)
    valueTextView.textColor = .labelColor
    valueTextView.textContainerInset = NSSize(width: 6, height: 6)
    valueTextView.textContainer?.widthTracksTextView = true
    valueTextView.textContainer?.lineFragmentPadding = 0
    scroll.documentView = valueTextView

    addSubview(titleLabel)
    addSubview(scroll)

    NSLayoutConstraint.activate([
      titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
      titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

      scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      scroll.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
      scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func setText(_ text: String) {
    valueTextView.string = text
  }

  func setTitle(_ title: String) {
    titleLabel.stringValue = title
  }
}

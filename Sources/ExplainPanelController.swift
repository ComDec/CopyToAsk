import Cocoa

@MainActor
final class ExplainPanelController: NSObject {
  private var panel: NSPanel?
  private var bodyTextView: NSTextView?
  private var headerTitleLabel: NSTextField?

  private var translateRow: NSStackView?
  private var translateLabel: NSTextField?
  private var translatePopup: NSPopUpButton?

  private var copyButton: NSButton?
  private var closeButton: NSButton?

  private var contextTitleLabel: NSTextField?

  private var interfaceLanguage: InterfaceLanguage = .en
  private var pendingTranslateTo: TranslateLanguage = .en
  private var pendingTranslateEnabled: Bool = true

  private var contextContainer: NSView?
  private var contextTextView: NSTextView?
  private var contextHeightConstraint: NSLayoutConstraint?

  private var askInputBar: AskInputBar?
  private var askInputHeightConstraint: NSLayoutConstraint?

  private var pendingAskGhostPrompt: String = ""
  private var pendingAskSelectedText: String = ""
  private var pendingAskInteractionEnabled: Bool = true

  private var askSelectedHeader: SelectedTextHeaderView?
  private var askSelectedHeaderHeightConstraint: NSLayoutConstraint?
  private var askChatScroll: NSScrollView?
  private var askChatDoc: NSView?
  private var askChatStack: NSStackView?
  private var askChatHeightMinConstraint: NSLayoutConstraint?
  private var currentAssistantBubble: ChatBubbleView?
  private var currentAssistantMarkdown: String = ""

  private var renderMarkdownByDefault: Bool = {
    // Default on; opt out with COPYTOASK_RENDER_MARKDOWN=0
    let v = (ProcessInfo.processInfo.environment["COPYTOASK_RENDER_MARKDOWN"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if v == "0" { return false }
    if v.lowercased() == "false" { return false }
    return true
  }()

  private var pendingMarkdown: String = ""
  private var renderWorkItem: DispatchWorkItem?
  private var lastRenderedMarkdown: String = ""

  var onTranslateToChanged: ((TranslateLanguage) -> Void)?
  var onClose: (() -> Void)?
  var onAskSend: ((String) -> Void)?

  func show(
    message: String,
    anchor: SelectionAnchor,
    language: AnswerLanguage = .zh,
    headerTitle: String = "Explain",
    contextText: String? = nil,
    interfaceLanguage: InterfaceLanguage = .en
  ) {
    TraceLog.log("ExplainPanelController.show header=\(headerTitle)")
    ensurePanel()
    self.interfaceLanguage = interfaceLanguage
    applyInterfaceLanguage(headerTitleID: headerTitle)
    setContextText(contextText)

    // Translate control appears only for Explain.
    translateRow?.isHidden = (headerTitle != "Explain")

    if headerTitle == "Ask" {
      showAskInput(true)
      showAskChat(true)
      setBodyText("")
      if !message.isEmpty {
        // Interpret message as an initial system note.
        askAddSystemMessage(message)
      }
    } else {
      showAskChat(false)
      setBodyText(message)
    }

    setTranslateTo(language.asTranslateLanguage)

    applyDefaultSize(for: headerTitle)
    positionPanel(anchor: anchor)

    // Always show the panel.
    panel?.orderFrontRegardless()

    if headerTitle == "Ask" {
      // Ask requires keyboard focus.
      NSApp.activate(ignoringOtherApps: true)
      // Avoid makeKeyAndOrderFront (see SettingsWindowController.show()).
      askInputBar?.focus()
    } else {
      // Explain/context should not steal focus from the source app.
    }
  }

  private func applyDefaultSize(for headerTitle: String) {
    guard let panel else { return }
    let size: NSSize
    if headerTitle == "Ask" {
      // Ask needs more vertical room for selected text + chat + input.
      size = NSSize(width: 560, height: 420)
    } else {
      size = NSSize(width: 520, height: 320)
    }
    panel.setContentSize(size)
  }

  func close() {
    panel?.orderOut(nil)
    onClose?()
  }

  func setBodyText(_ text: String) {
    renderWorkItem?.cancel()
    renderWorkItem = nil
    pendingMarkdown = ""
    lastRenderedMarkdown = ""

    bodyTextView?.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [
      .font: NSFont.systemFont(ofSize: 13),
      .foregroundColor: NSColor.labelColor,
    ]))
    bodyTextView?.scrollToEndOfDocument(nil)
  }

  func setBodyMarkdownStreaming(_ markdown: String) {
    guard renderMarkdownByDefault else {
      setBodyText(markdown)
      return
    }
    pendingMarkdown = markdown
    scheduleMarkdownRender(debounce: 0.08)
  }

  func setBodyMarkdownFinal(_ markdown: String) {
    guard renderMarkdownByDefault else {
      setBodyText(markdown)
      return
    }
    pendingMarkdown = markdown
    renderWorkItem?.cancel()
    renderWorkItem = nil
    if let rendered = renderMarkdown(markdown) {
      bodyTextView?.textStorage?.setAttributedString(rendered)
      bodyTextView?.scrollToEndOfDocument(nil)
    } else {
      setBodyText(markdown)
    }
  }

  private func scheduleMarkdownRender(debounce: TimeInterval) {
    // Avoid re-rendering same content.
    if pendingMarkdown == lastRenderedMarkdown { return }
    renderWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self else { return }
      let text = self.pendingMarkdown
      if text == self.lastRenderedMarkdown { return }
      if let rendered = self.renderMarkdown(text) {
        self.bodyTextView?.textStorage?.setAttributedString(rendered)
        self.bodyTextView?.scrollToEndOfDocument(nil)
        self.lastRenderedMarkdown = text
      } else {
        // Fallback: show plain while markdown is incomplete.
        self.bodyTextView?.string = text
        self.bodyTextView?.scrollToEndOfDocument(nil)
      }
    }
    renderWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: work)
  }

  private func renderMarkdown(_ markdown: String) -> NSAttributedString? {
    if #available(macOS 12.0, *) {
      do {
        var a = try AttributedString(markdown: markdown, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible))
        a.foregroundColor = .labelColor
        return NSAttributedString(a)
      } catch {
        return nil
      }
    }
    return nil
  }

  func setHeaderTitle(_ title: String) {
    headerTitleLabel?.stringValue = localizedHeaderTitle(title)
  }

  private func localizedHeaderTitle(_ id: String) -> String {
    switch id {
    case "Explain":
      return L10n.text(.panelExplainTitle, lang: interfaceLanguage)
    case "Ask":
      return L10n.text(.panelAskTitle, lang: interfaceLanguage)
    case "Summary":
      return L10n.text(.panelSummaryTitle, lang: interfaceLanguage)
    default:
      return id
    }
  }

  private func applyInterfaceLanguage(headerTitleID: String) {
    setHeaderTitle(headerTitleID)
    copyButton?.title = L10n.text(.buttonCopy, lang: interfaceLanguage)
    closeButton?.title = L10n.text(.buttonClose, lang: interfaceLanguage)
    translateLabel?.stringValue = L10n.text(.labelTranslateTo, lang: interfaceLanguage)
    contextTitleLabel?.stringValue = L10n.text(.labelContext, lang: interfaceLanguage)
    askSelectedHeader?.setTitle(L10n.text(.labelSelectedText, lang: interfaceLanguage))
    askInputBar?.setSendButtonTitle(L10n.text(.buttonSend, lang: interfaceLanguage))
    reloadTranslatePopup()
  }

  func setContextText(_ text: String?) {
    let t = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if t.isEmpty {
      contextTextView?.string = ""
      contextContainer?.isHidden = true
      contextHeightConstraint?.constant = 0
    } else {
      contextContainer?.isHidden = false
      contextTextView?.string = t
      contextHeightConstraint?.constant = 90
    }
  }

  func setAskGhostPrompt(_ text: String) {
    pendingAskGhostPrompt = text
    askInputBar?.setGhostPrompt(text)
  }

  func setAskInteractionEnabled(_ enabled: Bool) {
    pendingAskInteractionEnabled = enabled
    askInputBar?.setInteractionEnabled(enabled)
  }

  func clearAskInput() {
    askInputBar?.clear()
  }

  func setAskSelectedText(_ text: String) {
    pendingAskSelectedText = text
    askSelectedHeader?.setText(text)
  }

  func askAddUserMessage(_ text: String) {
    askAppendBubble(role: .user, initial: text, markdown: false)
  }

  func askAddSystemMessage(_ text: String) {
    askAppendBubble(role: .system, initial: text, markdown: false)
  }

  func askStartAssistantMessage() {
    let bubble = askAppendBubble(role: .assistant, initial: "", markdown: true)
    currentAssistantBubble = bubble
    currentAssistantMarkdown = ""
  }

  func askAppendAssistantDelta(_ delta: String) {
    guard let b = currentAssistantBubble else { return }
    currentAssistantMarkdown.append(delta)
    b.setMarkdownStreaming(currentAssistantMarkdown)
  }

  func askFinishAssistantMessage() {
    guard let b = currentAssistantBubble else { return }
    b.setMarkdownFinal(currentAssistantMarkdown)
    currentAssistantBubble = nil
    currentAssistantMarkdown = ""
  }

  func setTranslateTo(_ lang: TranslateLanguage) {
    pendingTranslateTo = lang
    if let popup = translatePopup {
      if let idx = TranslateLanguage.supported8.firstIndex(of: lang), idx < popup.numberOfItems {
        popup.selectItem(at: idx)
      }
    }
  }

  func setTranslateEnabled(_ enabled: Bool) {
    pendingTranslateEnabled = enabled
    translatePopup?.isEnabled = enabled
  }

  private func reloadTranslatePopup() {
    guard let popup = translatePopup else { return }
    let currentRaw = (popup.selectedItem?.representedObject as? String) ?? pendingTranslateTo.rawValue
    let current = TranslateLanguage(rawValue: currentRaw) ?? pendingTranslateTo

    popup.removeAllItems()
    for lang in TranslateLanguage.supported8 {
      popup.addItem(withTitle: lang.displayName(interface: interfaceLanguage))
      popup.lastItem?.representedObject = lang.rawValue
    }

    if let idx = TranslateLanguage.supported8.firstIndex(of: current) {
      popup.selectItem(at: idx)
    } else {
      popup.selectItem(at: 0)
    }
    pendingTranslateTo = current
    popup.isEnabled = pendingTranslateEnabled
  }

  private func ensurePanel() {
    if panel != nil { return }

    let style: NSWindow.StyleMask = [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel]
    let p = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
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
    p.minSize = NSSize(width: 440, height: 260)

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
    self.headerTitleLabel = title

    let tLabel = NSTextField(labelWithString: "Translate To")
    tLabel.font = .systemFont(ofSize: 11, weight: .semibold)
    tLabel.textColor = .secondaryLabelColor
    self.translateLabel = tLabel

    let tPopup = NSPopUpButton()
    tPopup.controlSize = .small
    tPopup.bezelStyle = .rounded
    tPopup.target = self
    tPopup.action = #selector(translateToChanged)
    self.translatePopup = tPopup

    let tRow = NSStackView(views: [tLabel, tPopup])
    tRow.orientation = .horizontal
    tRow.alignment = .centerY
    tRow.spacing = 8
    self.translateRow = tRow

    let closeButton = NSButton(title: "Close", target: self, action: #selector(closeTapped))
    closeButton.bezelStyle = .rounded
    self.closeButton = closeButton

    let copyButton = NSButton(title: "Copy", target: self, action: #selector(copyTapped))
    copyButton.bezelStyle = .rounded
    self.copyButton = copyButton

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

    // Ask mode UI
    let selectedHeader = SelectedTextHeaderView()
    selectedHeader.isHidden = true
    selectedHeader.setText(pendingAskSelectedText)
    askSelectedHeader = selectedHeader
    let chatScroll = NSScrollView()
    chatScroll.drawsBackground = false
    chatScroll.hasVerticalScroller = true
    chatScroll.autohidesScrollers = true
    chatScroll.isHidden = true
    askChatScroll = chatScroll

    let chatDoc = NSView()
    chatDoc.translatesAutoresizingMaskIntoConstraints = false
    askChatDoc = chatDoc

    // Assign first so constraints can safely reference the clip view.
    chatScroll.documentView = chatDoc

    let chatStack = NSStackView()
    chatStack.orientation = .vertical
    chatStack.alignment = .leading
    chatStack.spacing = 10
    chatStack.translatesAutoresizingMaskIntoConstraints = false
    askChatStack = chatStack
    chatDoc.addSubview(chatStack)
    NSLayoutConstraint.activate([
      chatStack.leadingAnchor.constraint(equalTo: chatDoc.leadingAnchor),
      chatStack.trailingAnchor.constraint(equalTo: chatDoc.trailingAnchor),
      chatStack.topAnchor.constraint(equalTo: chatDoc.topAnchor),
      chatStack.bottomAnchor.constraint(equalTo: chatDoc.bottomAnchor),
      // Track the clip view width (avoids some scroll-view anchor issues on macOS 26.x).
      chatDoc.widthAnchor.constraint(equalTo: chatScroll.contentView.widthAnchor),
    ])

    // Context preview (hidden by default)
    let contextBox = NSView()
    contextBox.wantsLayer = true
    contextBox.layer?.cornerRadius = 8
    contextBox.layer?.borderWidth = 1
    contextBox.layer?.borderColor = NSColor.separatorColor.cgColor
    contextBox.layer?.backgroundColor = NSColor.clear.cgColor
    contextBox.isHidden = true
    self.contextContainer = contextBox

    let contextLabel = NSTextField(labelWithString: "Context")
    contextLabel.font = .systemFont(ofSize: 11, weight: .semibold)
    contextLabel.textColor = .secondaryLabelColor
    self.contextTitleLabel = contextLabel

    let contextScroll = NSScrollView()
    contextScroll.hasVerticalScroller = true
    contextScroll.drawsBackground = false

    let ctxTV = NSTextView()
    ctxTV.isEditable = false
    ctxTV.drawsBackground = false
    ctxTV.font = .systemFont(ofSize: 11)
    ctxTV.textColor = .labelColor
    ctxTV.textContainerInset = NSSize(width: 4, height: 4)
    contextScroll.documentView = ctxTV
    self.contextTextView = ctxTV

    let ctxStack = NSStackView(views: [contextLabel, contextScroll])
    ctxStack.orientation = .vertical
    ctxStack.alignment = .leading
    ctxStack.spacing = 6
    ctxStack.translatesAutoresizingMaskIntoConstraints = false
    contextBox.addSubview(ctxStack)
    NSLayoutConstraint.activate([
      ctxStack.leadingAnchor.constraint(equalTo: contextBox.leadingAnchor, constant: 8),
      ctxStack.trailingAnchor.constraint(equalTo: contextBox.trailingAnchor, constant: -8),
      ctxStack.topAnchor.constraint(equalTo: contextBox.topAnchor, constant: 8),
      ctxStack.bottomAnchor.constraint(equalTo: contextBox.bottomAnchor, constant: -8),
    ])

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
    blur.addSubview(tRow)
    blur.addSubview(closeButton)
    blur.addSubview(copyButton)
    blur.addSubview(contextBox)
    blur.addSubview(selectedHeader)
    blur.addSubview(chatScroll)
    blur.addSubview(scroll)

    let askBar = AskInputBar(ghostPrompt: "")
    askBar.isHidden = true
    askBar.setGhostPrompt(pendingAskGhostPrompt)
    askBar.setInteractionEnabled(pendingAskInteractionEnabled)
    askBar.onSend = { [weak self] text in
      self?.onAskSend?(text)
    }
    self.askInputBar = askBar
    blur.addSubview(askBar)

    title.translatesAutoresizingMaskIntoConstraints = false
    tRow.translatesAutoresizingMaskIntoConstraints = false
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    copyButton.translatesAutoresizingMaskIntoConstraints = false
    contextBox.translatesAutoresizingMaskIntoConstraints = false
    selectedHeader.translatesAutoresizingMaskIntoConstraints = false
    chatScroll.translatesAutoresizingMaskIntoConstraints = false
    scroll.translatesAutoresizingMaskIntoConstraints = false
    askBar.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      title.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 14),
      title.topAnchor.constraint(equalTo: blur.topAnchor, constant: 10),

      tRow.centerYAnchor.constraint(equalTo: title.centerYAnchor),
      tRow.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -10),

      closeButton.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -12),
      closeButton.topAnchor.constraint(equalTo: blur.topAnchor, constant: 6),

      copyButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
      copyButton.topAnchor.constraint(equalTo: blur.topAnchor, constant: 6),

      contextBox.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 10),
      contextBox.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -10),
      contextBox.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),

      selectedHeader.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 10),
      selectedHeader.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -10),
      selectedHeader.topAnchor.constraint(equalTo: contextBox.bottomAnchor, constant: 8),

      chatScroll.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 10),
      chatScroll.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -10),
      chatScroll.topAnchor.constraint(equalTo: selectedHeader.bottomAnchor, constant: 8),

      askBar.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 10),
      askBar.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -10),
      askBar.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -10),

      scroll.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 10),
      scroll.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -10),
      scroll.topAnchor.constraint(equalTo: contextBox.bottomAnchor, constant: 8),
      scroll.bottomAnchor.constraint(equalTo: askBar.topAnchor, constant: -8),
    ])

    chatScroll.bottomAnchor.constraint(equalTo: askBar.topAnchor, constant: -8).isActive = true

    let h = contextBox.heightAnchor.constraint(equalToConstant: 0)
    h.isActive = true
    contextHeightConstraint = h

    let ah = askBar.heightAnchor.constraint(equalToConstant: 0)
    ah.isActive = true
    askInputHeightConstraint = ah

    let sh = selectedHeader.heightAnchor.constraint(equalToConstant: 0)
    sh.isActive = true
    askSelectedHeaderHeightConstraint = sh

    p.contentView = content
    panel = p
  }

  private func showAskInput(_ show: Bool) {
    if show {
      askInputBar?.isHidden = false
      askInputHeightConstraint?.constant = 76
    } else {
      askInputBar?.isHidden = true
      askInputHeightConstraint?.constant = 0
    }
  }

  private func showAskChat(_ show: Bool) {
    if show {
      askSelectedHeader?.isHidden = false
      askChatScroll?.isHidden = false
      askSelectedHeaderHeightConstraint?.constant = 64
      // Hide normal body scroll.
      bodyTextView?.enclosingScrollView?.isHidden = true
    } else {
      askSelectedHeader?.isHidden = true
      askChatScroll?.isHidden = true
      askSelectedHeaderHeightConstraint?.constant = 0
      bodyTextView?.enclosingScrollView?.isHidden = false
      currentAssistantBubble = nil
      currentAssistantMarkdown = ""
      clearChat()
    }
  }

  private func clearChat() {
    askChatStack?.arrangedSubviews.forEach { v in
      askChatStack?.removeArrangedSubview(v)
      v.removeFromSuperview()
    }
  }

  @discardableResult
  private func askAppendBubble(role: ChatBubbleView.Role, initial: String, markdown: Bool) -> ChatBubbleView {
    let b = ChatBubbleView(role: role)
    if markdown {
      b.setMarkdownFinal(initial)
    } else {
      b.setPlainText(initial)
    }
    guard let stack = askChatStack else {
      // Fallback if Ask UI isn't initialized.
      setBodyText(initial)
      return b
    }
    stack.addArrangedSubview(b)
    b.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    askChatDoc?.layoutSubtreeIfNeeded()
    if let scroll = askChatScroll {
      scroll.contentView.scrollToVisible(b.frame.insetBy(dx: 0, dy: -40))
    }
    return b
  }

  @objc private func translateToChanged() {
    guard let raw = translatePopup?.selectedItem?.representedObject as? String,
          let lang = TranslateLanguage(rawValue: raw)
    else { return }
    pendingTranslateTo = lang
    onTranslateToChanged?(lang)
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

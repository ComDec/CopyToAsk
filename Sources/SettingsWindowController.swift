import Cocoa
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController {
  private let settings: AppSettings

  private var ui: InterfaceLanguage { settings.interfaceLanguage }

  private func t(_ en: String, _ zh: String) -> String {
    (ui == .zh) ? zh : en
  }

  // Actions provided by AppDelegate.
  var onSetHotKey: ((HotKeyAction) -> Void)?
  var getHotKeyLabel: ((HotKeyAction) -> String)?

  var onSetAPIKey: (() -> Void)?
  var onClearAPIKey: (() -> Void)?
  var getAPIKeyStatus: (() -> String)?

  var onOpenPromptsConfig: (() -> Void)?
  var onRevealPromptsConfig: (() -> Void)?
  var onResetPromptsConfig: (() -> Void)?

  var onOpenHistoryFolder: (() -> Void)?
  var onSummarizeHistoryFile: (([URL]) -> Void)?
  var onPruneHistoryNow: (() -> Void)?

  var onInterfaceLanguageChanged: ((InterfaceLanguage) -> Void)?

  private var hotKeyValueLabel: NSTextField?
  private var askHotKeyValueLabel: NSTextField?
  private var contextHotKeyValueLabel: NSTextField?
  private var apiKeyStatusLabel: NSTextField?
  private var explainTierControl: NSSegmentedControl?
  private var summaryTierControl: NSSegmentedControl?
  private var cheapModelField: NSTextField?
  private var mediumModelField: NSTextField?
  private var detailedModelField: NSTextField?

  private var retentionToggle: NSButton?
  private var retentionDaysField: NSTextField?
  private var retentionStepper: NSStepper?

  private var historyFilePopup: NSPopUpButton?
  private var selectedSummaryFiles: [URL] = []

  private var interfaceLanguagePopup: NSPopUpButton?
  private var interfaceLanguageLabel: NSTextField?

  init(settings: AppSettings = .shared) {
    self.settings = settings
    let w = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    w.title = "CopyToAsk Settings"
    // Ensure it can be reopened reliably and appears over fullscreen apps.
    w.isReleasedWhenClosed = false
    w.collectionBehavior = w.collectionBehavior.union([.canJoinAllSpaces, .fullScreenAuxiliary])
    super.init(window: w)
    setupUI()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func show() {
    TraceLog.log("SettingsWindowController.show")
    refresh()
    if let w = window, !w.isVisible {
      w.center()
    }
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    window?.orderFrontRegardless()
    window?.makeKeyAndOrderFront(nil)
  }

  private func setupUI() {
    guard let content = window?.contentView else { return }

    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false

    let doc = NSView()
    scroll.documentView = doc
    scroll.translatesAutoresizingMaskIntoConstraints = false
    doc.translatesAutoresizingMaskIntoConstraints = false

    content.addSubview(scroll)
    NSLayoutConstraint.activate([
      scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
      scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
      scroll.topAnchor.constraint(equalTo: content.topAnchor),
      scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),

      doc.widthAnchor.constraint(equalTo: scroll.widthAnchor),
    ])

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 18
    stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
    stack.translatesAutoresizingMaskIntoConstraints = false
    doc.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
      stack.topAnchor.constraint(equalTo: doc.topAnchor),
      stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
    ])

    stack.addArrangedSubview(sectionTitle(t("General", "通用")))
    stack.addArrangedSubview(buildHotkeyRow(title: t("Explain hotkey", "解释快捷键"), outLabel: &hotKeyValueLabel, action: #selector(setExplainHotKeyTapped)))
    stack.addArrangedSubview(buildHotkeyRow(title: t("Ask hotkey", "提问快捷键"), outLabel: &askHotKeyValueLabel, action: #selector(setAskHotKeyTapped)))
    stack.addArrangedSubview(buildHotkeyRow(title: t("Context hotkey", "上下文快捷键"), outLabel: &contextHotKeyValueLabel, action: #selector(setContextHotKeyTapped)))

    stack.addArrangedSubview(buildInterfaceLanguageRow())

    stack.addArrangedSubview(sectionTitle("OpenAI"))
    stack.addArrangedSubview(buildAPIKeyRow())

    stack.addArrangedSubview(sectionTitle(t("Models", "模型")))
    stack.addArrangedSubview(buildTierRow(title: t("Explain", "解释"), outControl: &explainTierControl, action: #selector(explainTierChanged)))
    stack.addArrangedSubview(buildTierRow(title: t("Summary", "总结"), outControl: &summaryTierControl, action: #selector(summaryTierChanged)))
    stack.addArrangedSubview(buildModelIdGrid())

    stack.addArrangedSubview(sectionTitle(t("Prompts", "提示词")))
    stack.addArrangedSubview(buildPromptRow())

    stack.addArrangedSubview(sectionTitle(t("History", "历史记录")))
    stack.addArrangedSubview(buildHistoryRow())
    stack.addArrangedSubview(buildRetentionRow())
  }

  private func rebuildUI() {
    guard let window else { return }

    // Replace the contentView to drop previous constraints cleanly.
    window.contentView = NSView()

    hotKeyValueLabel = nil
    askHotKeyValueLabel = nil
    contextHotKeyValueLabel = nil
    apiKeyStatusLabel = nil
    explainTierControl = nil
    summaryTierControl = nil
    cheapModelField = nil
    mediumModelField = nil
    detailedModelField = nil
    retentionToggle = nil
    retentionDaysField = nil
    retentionStepper = nil
    historyFilePopup = nil
    interfaceLanguagePopup = nil
    interfaceLanguageLabel = nil

    setupUI()
  }

  private func sectionTitle(_ text: String) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: 15, weight: .semibold)
    return l
  }

  private func buildHotkeyRow(title: String, outLabel: inout NSTextField?, action: Selector) -> NSView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10

    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.setContentHuggingPriority(.required, for: .horizontal)

    label.widthAnchor.constraint(equalToConstant: 110).isActive = true

    let value = NSTextField(labelWithString: "")
    value.font = .systemFont(ofSize: 13, weight: .semibold)
    outLabel = value

    let set = NSButton(title: t("Set…", "设置…"), target: self, action: action)
    set.bezelStyle = .rounded

    row.addArrangedSubview(label)
    row.addArrangedSubview(value)
    row.addArrangedSubview(set)
    return row
  }

  private func buildInterfaceLanguageRow() -> NSView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10

    let label = NSTextField(labelWithString: t("Interface language", "界面语言"))
    label.font = .systemFont(ofSize: 13)
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.widthAnchor.constraint(equalToConstant: 110).isActive = true
    interfaceLanguageLabel = label

    let popup = NSPopUpButton()
    popup.addItem(withTitle: InterfaceLanguage.en.displayName)
    popup.addItem(withTitle: InterfaceLanguage.zh.displayName)
    popup.target = self
    popup.action = #selector(interfaceLanguageChanged)
    interfaceLanguagePopup = popup

    row.addArrangedSubview(label)
    row.addArrangedSubview(popup)
    return row
  }

  private func buildAPIKeyRow() -> NSView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10

    let label = NSTextField(labelWithString: t("Auth", "认证"))
    label.font = .systemFont(ofSize: 13)
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.widthAnchor.constraint(equalToConstant: 70).isActive = true

    let status = NSTextField(labelWithString: "")
    status.font = .systemFont(ofSize: 12)
    status.textColor = .secondaryLabelColor
    apiKeyStatusLabel = status

    let set = NSButton(title: t("OpenAI Auth…", "OpenAI 登录…"), target: self, action: #selector(setAPIKeyTapped))
    set.bezelStyle = .rounded
    let clear = NSButton(title: t("Clear", "清除"), target: self, action: #selector(clearAPIKeyTapped))
    clear.bezelStyle = .rounded

    row.addArrangedSubview(label)
    row.addArrangedSubview(status)
    row.addArrangedSubview(set)
    row.addArrangedSubview(clear)
    return row
  }

  private func buildTierRow(title: String, outControl: inout NSSegmentedControl?, action: Selector) -> NSView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10

    let label = NSTextField(labelWithString: title)
    label.font = .systemFont(ofSize: 13)
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.widthAnchor.constraint(equalToConstant: 70).isActive = true

    let seg = NSSegmentedControl(labels: [ModelTier.cheap.displayName, ModelTier.medium.displayName, ModelTier.detailed.displayName], trackingMode: .selectOne, target: self, action: action)
    seg.segmentStyle = .rounded
    seg.controlSize = .small
    outControl = seg

    row.addArrangedSubview(label)
    row.addArrangedSubview(seg)
    return row
  }

  private func buildModelIdGrid() -> NSView {
    let grid = NSGridView(views: [
      [NSTextField(labelWithString: t("Cheap model id", "低价模型 ID")), NSTextField(string: "")],
      [NSTextField(labelWithString: t("Medium model id", "中档模型 ID")), NSTextField(string: "")],
      [NSTextField(labelWithString: t("Detailed model id", "高质量模型 ID")), NSTextField(string: "")],
    ])

    grid.rowSpacing = 8
    grid.columnSpacing = 12

    for r in 0..<3 {
      let label = grid.cell(atColumnIndex: 0, rowIndex: r).contentView as! NSTextField
      label.font = .systemFont(ofSize: 12)
      label.textColor = .secondaryLabelColor

      let field = grid.cell(atColumnIndex: 1, rowIndex: r).contentView as! NSTextField
      field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
      field.placeholderString = t("e.g. gpt-4o-mini", "例如 gpt-4o-mini")
      field.target = self
      field.action = #selector(modelIdEdited)
      field.translatesAutoresizingMaskIntoConstraints = false
      field.widthAnchor.constraint(equalToConstant: 360).isActive = true

      if r == 0 { cheapModelField = field }
      if r == 1 { mediumModelField = field }
      if r == 2 { detailedModelField = field }
    }

    return grid
  }

  private func buildPromptRow() -> NSView {
    let col = NSStackView()
    col.orientation = .vertical
    col.alignment = .leading
    col.spacing = 8

    let note = NSTextField(labelWithString: t(
      "Prompts are configured via a JSON file (prompts.json). Edit it in your editor and changes will apply on next request.",
      "提示词通过 JSON 文件（prompts.json）配置。用编辑器修改后，会在下一次请求时生效。"
    ))
    note.font = .systemFont(ofSize: 12)
    note.textColor = .secondaryLabelColor
    note.lineBreakMode = .byWordWrapping
    note.maximumNumberOfLines = 0
    note.translatesAutoresizingMaskIntoConstraints = false
    note.widthAnchor.constraint(equalToConstant: 560).isActive = true

    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10

    let open = NSButton(title: t("Open prompts.json", "打开 prompts.json"), target: self, action: #selector(openPromptsTapped))
    open.bezelStyle = .rounded
    let reveal = NSButton(title: t("Reveal in Finder", "在 Finder 中显示"), target: self, action: #selector(revealPromptsTapped))
    reveal.bezelStyle = .rounded
    let reset = NSButton(title: t("Reset to Default", "恢复默认"), target: self, action: #selector(resetPromptsTapped))
    reset.bezelStyle = .rounded

    row.addArrangedSubview(open)
    row.addArrangedSubview(reveal)
    row.addArrangedSubview(reset)

    col.addArrangedSubview(note)
    col.addArrangedSubview(row)
    return col
  }

  private func buildHistoryRow() -> NSView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10

    let open = NSButton(title: t("Open Folder", "打开文件夹"), target: self, action: #selector(openHistoryTapped))
    open.bezelStyle = .rounded

    let popup = NSPopUpButton()
    popup.controlSize = .small
    popup.target = self
    popup.action = #selector(historyFileSelected)
    popup.addItem(withTitle: t("Select a day…", "选择日期…"))
    historyFilePopup = popup

    let choose = NSButton(title: t("Choose JSONL…", "选择 JSONL…"), target: self, action: #selector(chooseHistoryFileTapped))
    choose.bezelStyle = .rounded

    let summarize = NSButton(title: t("Summarize → Markdown", "汇总 → Markdown"), target: self, action: #selector(summarizeTapped))
    summarize.bezelStyle = .rounded

    row.addArrangedSubview(open)
    row.addArrangedSubview(popup)
    row.addArrangedSubview(choose)
    row.addArrangedSubview(summarize)
    return row
  }

  private func buildRetentionRow() -> NSView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10

    let toggle = NSButton(checkboxWithTitle: t("Auto-delete history older than", "自动删除早于"), target: self, action: #selector(retentionToggled))
    retentionToggle = toggle

    let daysField = NSTextField(string: "")
    daysField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    daysField.alignment = .right
    daysField.target = self
    daysField.action = #selector(retentionDaysEdited)
    daysField.widthAnchor.constraint(equalToConstant: 60).isActive = true
    retentionDaysField = daysField

    let stepper = NSStepper()
    stepper.minValue = 1
    stepper.maxValue = 3650
    stepper.increment = 1
    stepper.target = self
    stepper.action = #selector(retentionStepperChanged)
    retentionStepper = stepper

    let suffix = NSTextField(labelWithString: t("days", "天"))
    suffix.textColor = .secondaryLabelColor

    let prune = NSButton(title: t("Prune Now", "立即清理"), target: self, action: #selector(pruneNowTapped))
    prune.bezelStyle = .rounded

    row.addArrangedSubview(toggle)
    row.addArrangedSubview(daysField)
    row.addArrangedSubview(stepper)
    row.addArrangedSubview(suffix)
    row.addArrangedSubview(prune)
    return row
  }

  func refresh() {
    hotKeyValueLabel?.stringValue = getHotKeyLabel?(.explain) ?? ""
    askHotKeyValueLabel?.stringValue = getHotKeyLabel?(.ask) ?? ""
    contextHotKeyValueLabel?.stringValue = getHotKeyLabel?(.setContext) ?? ""
    apiKeyStatusLabel?.stringValue = getAPIKeyStatus?() ?? ""

    explainTierControl?.selectedSegment = indexForTier(settings.explainTier)
    summaryTierControl?.selectedSegment = indexForTier(settings.summaryTier)

    cheapModelField?.stringValue = settings.cheapModelId
    mediumModelField?.stringValue = settings.mediumModelId
    detailedModelField?.stringValue = settings.detailedModelId

    retentionToggle?.state = settings.historyRetentionEnabled ? .on : .off
    retentionDaysField?.stringValue = String(settings.historyRetentionDays)
    retentionStepper?.integerValue = settings.historyRetentionDays
    setRetentionControlsEnabled(settings.historyRetentionEnabled)

    reloadHistoryFiles()

    let ui = settings.interfaceLanguage
    window?.title = (ui == .zh) ? "CopyToAsk 设置" : "CopyToAsk Settings"
    interfaceLanguageLabel?.stringValue = (ui == .zh) ? "界面语言" : "Interface language"
    interfaceLanguagePopup?.selectItem(at: (ui == .zh) ? 1 : 0)
  }

  private func reloadHistoryFiles() {
    let popup = historyFilePopup
    popup?.removeAllItems()
    popup?.addItem(withTitle: t("Select a day…", "选择日期…"))
    let files = (try? FileManager.default.contentsOfDirectory(at: HistoryStore.shared.historyDirectoryURL(), includingPropertiesForKeys: nil)) ?? []
    let jsonls = files.filter { $0.pathExtension.lowercased() == "jsonl" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    for url in jsonls.prefix(90) {
      popup?.addItem(withTitle: url.deletingPathExtension().lastPathComponent)
      popup?.lastItem?.representedObject = url
    }
  }

  private func setRetentionControlsEnabled(_ enabled: Bool) {
    retentionDaysField?.isEnabled = enabled
    retentionStepper?.isEnabled = enabled
  }

  private func indexForTier(_ tier: ModelTier) -> Int {
    switch tier {
    case .cheap: return 0
    case .medium: return 1
    case .detailed: return 2
    }
  }

  private func tierForIndex(_ idx: Int) -> ModelTier {
    switch idx {
    case 1: return .medium
    case 2: return .detailed
    default: return .cheap
    }
  }

  @objc private func setExplainHotKeyTapped() { onSetHotKey?(.explain) }
  @objc private func setAskHotKeyTapped() { onSetHotKey?(.ask) }
  @objc private func setContextHotKeyTapped() { onSetHotKey?(.setContext) }

  @objc private func interfaceLanguageChanged() {
    let idx = interfaceLanguagePopup?.indexOfSelectedItem ?? 0
    let lang: InterfaceLanguage = (idx == 1) ? .zh : .en
    settings.interfaceLanguage = lang
    onInterfaceLanguageChanged?(lang)

    // Rebuild on next runloop so we don't destroy the active popup mid-action.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.rebuildUI()
      self.refresh()
    }
  }
  @objc private func setAPIKeyTapped() { onSetAPIKey?() }
  @objc private func clearAPIKeyTapped() { onClearAPIKey?() }

  @objc private func explainTierChanged() {
    settings.explainTier = tierForIndex(explainTierControl?.selectedSegment ?? 0)
  }

  @objc private func summaryTierChanged() {
    settings.summaryTier = tierForIndex(summaryTierControl?.selectedSegment ?? 1)
  }

  @objc private func modelIdEdited() {
    let cheap = cheapModelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let medium = mediumModelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let detailed = detailedModelField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !cheap.isEmpty { settings.cheapModelId = cheap }
    if !medium.isEmpty { settings.mediumModelId = medium }
    if !detailed.isEmpty { settings.detailedModelId = detailed }
  }

  @objc private func openPromptsTapped() { onOpenPromptsConfig?() }
  @objc private func revealPromptsTapped() { onRevealPromptsConfig?() }
  @objc private func resetPromptsTapped() { onResetPromptsConfig?() }

  @objc private func openHistoryTapped() { onOpenHistoryFolder?() }

  @objc private func chooseHistoryFileTapped() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = true
    if #available(macOS 12.0, *) {
      panel.allowedContentTypes = [UTType(filenameExtension: "jsonl")].compactMap { $0 }
    } else {
      panel.allowedFileTypes = ["jsonl"]
    }
    panel.directoryURL = HistoryStore.shared.historyDirectoryURL()
    panel.beginSheetModal(for: window!) { [weak self] resp in
      guard resp == .OK else { return }
      guard let self else { return }

      let urls = panel.urls
      if urls.count <= 1 {
        guard let chosen = urls.first else { return }
        self.selectedSummaryFiles = [chosen]
        self.historyFilePopup?.selectItem(at: 0)
        self.historyFilePopup?.addItem(withTitle: chosen.deletingPathExtension().lastPathComponent)
        self.historyFilePopup?.lastItem?.representedObject = chosen
        self.historyFilePopup?.selectItem(at: (self.historyFilePopup?.numberOfItems ?? 1) - 1)
      } else {
        self.selectedSummaryFiles = urls
        self.historyFilePopup?.selectItem(at: 0)
        self.historyFilePopup?.addItem(withTitle: self.t("\(urls.count) files selected", "已选择 \(urls.count) 个文件"))
        self.historyFilePopup?.lastItem?.representedObject = urls
        self.historyFilePopup?.selectItem(at: (self.historyFilePopup?.numberOfItems ?? 1) - 1)
      }
    }
  }

  @objc private func historyFileSelected() {
    // no-op; selection is read on summarize.
  }

  @objc private func summarizeTapped() {
    guard let item = historyFilePopup?.selectedItem else {
      NSSound.beep()
      return
    }
    if let urls = item.representedObject as? [URL], !urls.isEmpty {
      onSummarizeHistoryFile?(urls)
      return
    }
    guard let url = item.representedObject as? URL else {
      NSSound.beep()
      return
    }
    onSummarizeHistoryFile?([url])
  }

  @objc private func retentionToggled() {
    let enabled = (retentionToggle?.state == .on)
    settings.historyRetentionEnabled = enabled
    setRetentionControlsEnabled(enabled)
  }

  @objc private func retentionDaysEdited() {
    let v = Int(retentionDaysField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? settings.historyRetentionDays
    settings.historyRetentionDays = v
    retentionStepper?.integerValue = settings.historyRetentionDays
    retentionDaysField?.stringValue = String(settings.historyRetentionDays)
  }

  @objc private func retentionStepperChanged() {
    let v = retentionStepper?.integerValue ?? settings.historyRetentionDays
    settings.historyRetentionDays = v
    retentionDaysField?.stringValue = String(settings.historyRetentionDays)
  }

  @objc private func pruneNowTapped() { onPruneHistoryNow?() }

}

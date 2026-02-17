import Cocoa
import UniformTypeIdentifiers

@MainActor
final class SettingsWindowController: NSWindowController {
  private let settings: AppSettings

  // Actions provided by AppDelegate.
  var onSetHotKey: (() -> Void)?
  var getHotKeyLabel: (() -> String)?

  var onSetAPIKey: (() -> Void)?
  var onClearAPIKey: (() -> Void)?
  var getAPIKeyStatus: (() -> String)?

  var onEditExplainPrompt: (() -> Void)?
  var onResetExplainPrompt: (() -> Void)?
  var onEditTranslatePrompt: (() -> Void)?
  var onResetTranslatePrompt: (() -> Void)?

  var onOpenHistoryFolder: (() -> Void)?
  var onSummarizeHistoryFile: (([URL]) -> Void)?
  var onPruneHistoryNow: (() -> Void)?

  private var hotKeyValueLabel: NSTextField?
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

  init(settings: AppSettings = .shared) {
    self.settings = settings
    let w = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    w.title = "CopyToAsk Settings"
    super.init(window: w)
    setupUI()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func show() {
    refresh()
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
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

    stack.addArrangedSubview(sectionTitle("General"))
    stack.addArrangedSubview(buildHotkeyRow())

    stack.addArrangedSubview(sectionTitle("OpenAI"))
    stack.addArrangedSubview(buildAPIKeyRow())

    stack.addArrangedSubview(sectionTitle("Models"))
    stack.addArrangedSubview(buildTierRow(title: "Explain", outControl: &explainTierControl, action: #selector(explainTierChanged)))
    stack.addArrangedSubview(buildTierRow(title: "Summary", outControl: &summaryTierControl, action: #selector(summaryTierChanged)))
    stack.addArrangedSubview(buildModelIdGrid())

    stack.addArrangedSubview(sectionTitle("Prompts"))
    stack.addArrangedSubview(buildPromptRow())

    stack.addArrangedSubview(sectionTitle("History"))
    stack.addArrangedSubview(buildHistoryRow())
    stack.addArrangedSubview(buildRetentionRow())
  }

  private func sectionTitle(_ text: String) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: 15, weight: .semibold)
    return l
  }

  private func buildHotkeyRow() -> NSView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10

    let label = NSTextField(labelWithString: "Hotkey")
    label.font = .systemFont(ofSize: 13, weight: .regular)
    label.setContentHuggingPriority(.required, for: .horizontal)

    let value = NSTextField(labelWithString: "")
    value.font = .systemFont(ofSize: 13, weight: .semibold)
    self.hotKeyValueLabel = value

    let set = NSButton(title: "Set…", target: self, action: #selector(setHotKeyTapped))
    set.bezelStyle = .rounded

    row.addArrangedSubview(label)
    row.addArrangedSubview(value)
    row.addArrangedSubview(set)
    return row
  }

  private func buildAPIKeyRow() -> NSView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10

    let label = NSTextField(labelWithString: "API Key")
    label.font = .systemFont(ofSize: 13)
    label.setContentHuggingPriority(.required, for: .horizontal)
    label.widthAnchor.constraint(equalToConstant: 70).isActive = true

    let status = NSTextField(labelWithString: "")
    status.font = .systemFont(ofSize: 12)
    status.textColor = .secondaryLabelColor
    apiKeyStatusLabel = status

    let set = NSButton(title: "Set…", target: self, action: #selector(setAPIKeyTapped))
    set.bezelStyle = .rounded
    let clear = NSButton(title: "Clear", target: self, action: #selector(clearAPIKeyTapped))
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
      [NSTextField(labelWithString: "Cheap model id"), NSTextField(string: "")],
      [NSTextField(labelWithString: "Medium model id"), NSTextField(string: "")],
      [NSTextField(labelWithString: "Detailed model id"), NSTextField(string: "")],
    ])

    grid.rowSpacing = 8
    grid.columnSpacing = 12

    for r in 0..<3 {
      let label = grid.cell(atColumnIndex: 0, rowIndex: r).contentView as! NSTextField
      label.font = .systemFont(ofSize: 12)
      label.textColor = .secondaryLabelColor

      let field = grid.cell(atColumnIndex: 1, rowIndex: r).contentView as! NSTextField
      field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
      field.placeholderString = "e.g. gpt-4o-mini"
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
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10

    let editExplain = NSButton(title: "Edit Explain…", target: self, action: #selector(editExplainTapped))
    editExplain.bezelStyle = .rounded
    let resetExplain = NSButton(title: "Reset Explain", target: self, action: #selector(resetExplainTapped))
    resetExplain.bezelStyle = .rounded
    let editTranslate = NSButton(title: "Edit Translate…", target: self, action: #selector(editTranslateTapped))
    editTranslate.bezelStyle = .rounded
    let resetTranslate = NSButton(title: "Reset Translate", target: self, action: #selector(resetTranslateTapped))
    resetTranslate.bezelStyle = .rounded

    row.addArrangedSubview(editExplain)
    row.addArrangedSubview(resetExplain)
    row.addArrangedSubview(editTranslate)
    row.addArrangedSubview(resetTranslate)
    return row
  }

  private func buildHistoryRow() -> NSView {
    let row = NSStackView()
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 10

    let open = NSButton(title: "Open Folder", target: self, action: #selector(openHistoryTapped))
    open.bezelStyle = .rounded

    let popup = NSPopUpButton()
    popup.controlSize = .small
    popup.target = self
    popup.action = #selector(historyFileSelected)
    popup.addItem(withTitle: "Select a day…")
    historyFilePopup = popup

    let choose = NSButton(title: "Choose JSONL…", target: self, action: #selector(chooseHistoryFileTapped))
    choose.bezelStyle = .rounded

    let summarize = NSButton(title: "Summarize → Markdown", target: self, action: #selector(summarizeTapped))
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

    let toggle = NSButton(checkboxWithTitle: "Auto-delete history older than", target: self, action: #selector(retentionToggled))
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

    let suffix = NSTextField(labelWithString: "days")
    suffix.textColor = .secondaryLabelColor

    let prune = NSButton(title: "Prune Now", target: self, action: #selector(pruneNowTapped))
    prune.bezelStyle = .rounded

    row.addArrangedSubview(toggle)
    row.addArrangedSubview(daysField)
    row.addArrangedSubview(stepper)
    row.addArrangedSubview(suffix)
    row.addArrangedSubview(prune)
    return row
  }

  func refresh() {
    hotKeyValueLabel?.stringValue = getHotKeyLabel?() ?? ""
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
  }

  private func reloadHistoryFiles() {
    let popup = historyFilePopup
    popup?.removeAllItems()
    popup?.addItem(withTitle: "Select a day…")
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

  @objc private func setHotKeyTapped() { onSetHotKey?() }
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

  @objc private func editExplainTapped() { onEditExplainPrompt?() }
  @objc private func resetExplainTapped() { onResetExplainPrompt?() }
  @objc private func editTranslateTapped() { onEditTranslatePrompt?() }
  @objc private func resetTranslateTapped() { onResetTranslatePrompt?() }

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
        self.historyFilePopup?.addItem(withTitle: "\(urls.count) files selected")
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

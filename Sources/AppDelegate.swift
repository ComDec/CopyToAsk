import Cocoa
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var explainMenuItem: NSMenuItem?
  private var askMenuItem: NSMenuItem?
  private var contextMenuItem: NSMenuItem?
  private var showContextMenuItem: NSMenuItem?
  private var clearContextMenuItem: NSMenuItem?
  private var authMenuItem: NSMenuItem?
  private var toolsMenuItem: NSMenuItem?
  private var diagnosticsMenuItem: NSMenuItem?
  private var openAccessibilityMenuItem: NSMenuItem?
  private var openInputMonitoringMenuItem: NSMenuItem?
  private var openHistoryMenuItem: NSMenuItem?
  private var settingsMenuItem: NSMenuItem?
  private var quitMenuItem: NSMenuItem?

  private var explainLanguageMenuItem: NSMenuItem?
  private var explainLanguageChineseMenuItem: NSMenuItem?
  private var explainLanguageEnglishMenuItem: NSMenuItem?
  private let hotKeyManager = HotKeyManager()
  private let hotKeyRecorder = HotKeyRecorderPanelController()
  private let aiClient = OpenAIClient()
  private let keychain = KeychainStore(service: "com.copytoask.CopyToAsk")
  private let promptStore = PromptStore()
  private let historyStore = HistoryStore.shared
  private let settings = AppSettings.shared
  private lazy var settingsWindow = SettingsWindowController(settings: settings)

  private struct ExplainSession {
    let id: UUID
    let panel: ExplainPanelController
    let selectionText: String
    let anchor: SelectionAnchor
    let source: String
    let historyID: String
    let baseLanguage: AnswerLanguage
    var answers: [TranslateLanguage: String]
    var explainTask: Task<Void, Never>?
    var translateTask: Task<Void, Never>?

    // Ask conversation (OpenAI-managed via Responses API)
    var askPreviousResponseId: String?
    var askTranscriptMarkdown: String
  }

  private var sessions: [UUID: ExplainSession] = [:]

  private var apiKeyCache: String?
  private var apiKeyLoaded = false
  private var hasAPIKeyFlag: Bool {
    UserDefaults.standard.bool(forKey: "openai.hasApiKey")
  }

  private var recordingHotKeyAction: HotKeyAction = .explain

  private struct PinnedContext {
    var id: UUID
    var text: String
    var anchor: SelectionAnchor
    var source: String
  }

  private var pinnedContexts: [PinnedContext] = []
  private let contextPanel = ContextPanelController()

  func applicationDidFinishLaunching(_ notification: Notification) {
    TraceLog.log("applicationDidFinishLaunching")
    setupMainMenu()
    setupStatusItem()

    promptStore.ensureConfigFileExists()

    hotKeyManager.setHandler(for: .explain) { [weak self] in
      Task { @MainActor in self?.triggerExplain() }
    }
    hotKeyManager.setHandler(for: .ask) { [weak self] in
      Task { @MainActor in self?.triggerAsk() }
    }
    hotKeyManager.setHandler(for: .setContext) { [weak self] in
      Task { @MainActor in self?.triggerSetContext() }
    }

    _ = hotKeyManager.register(action: .explain, definition: settings.hotKey(for: .explain))
    _ = hotKeyManager.register(action: .ask, definition: settings.hotKey(for: .ask))
    _ = hotKeyManager.register(action: .setContext, definition: settings.hotKey(for: .setContext))

    hotKeyRecorder.onSave = { [weak self] def in
      guard let self else { return }
      self.settings.setHotKey(def, for: self.recordingHotKeyAction)
      let status = self.hotKeyManager.register(action: self.recordingHotKeyAction, definition: def)
      if status != noErr {
        let a = NSAlert()
        a.messageText = "Failed to register hotkey"
        a.informativeText = "OSStatus: \(status)"
        a.runModal()
      }
      self.refreshHotKeyUI()
      self.settingsWindow.refresh()
    }

    refreshHotKeyUI()

    settingsWindow.onSetHotKey = { [weak self] action in
      self?.beginSetHotKey(action)
    }
    settingsWindow.getHotKeyLabel = { [weak self] action in
      guard let self else { return "" }
      let def = self.hotKeyManager.getDefinition(for: action) ?? self.settings.hotKey(for: action)
      return HotKeyRecorderPanelController.format(def: def)
    }
    settingsWindow.onSetAPIKey = { [weak self] in self?.setAPIKey() }
    settingsWindow.onClearAPIKey = { [weak self] in self?.clearAPIKey() }
    settingsWindow.getAPIKeyStatus = { [weak self] in
      guard let self else { return "" }
      let ui = self.settings.interfaceLanguage
      if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return (ui == .zh) ? "使用环境变量 OPENAI_API_KEY" : "Using OPENAI_API_KEY env var"
      }
      switch self.settings.openAIAuthMethod {
      case .apiKey:
        let saved = UserDefaults.standard.bool(forKey: "openai.hasApiKey")
        if ui == .zh {
          return saved ? "API Key（钥匙串）" : "API Key（未设置）"
        }
        return saved ? "API Key (Keychain)" : "API Key (not set)"
      case .codex:
        let tok = self.loadCodexToken()
        if ui == .zh {
          return (tok != nil) ? "Codex（已登录）" : "Codex（未登录）"
        }
        return (tok != nil) ? "Codex (token found)" : "Codex (not logged in)"
      }
    }
    settingsWindow.onOpenPromptsConfig = { [weak self] in self?.promptStore.openConfigInEditor() }
    settingsWindow.onRevealPromptsConfig = { [weak self] in self?.promptStore.revealConfigInFinder() }
    settingsWindow.onResetPromptsConfig = { [weak self] in self?.promptStore.resetToDefaultConfig() }

    contextPanel.onClear = { [weak self] in
      Task { @MainActor in self?.clearContext() }
    }
    contextPanel.onDeleteItem = { [weak self] id in
      Task { @MainActor in self?.deleteContextItem(id) }
    }
    settingsWindow.onOpenHistoryFolder = { [weak self] in self?.openHistoryFolder() }
    settingsWindow.onSummarizeHistoryFile = { [weak self] urls in self?.summarizeHistoryFiles(urls) }
    settingsWindow.onPruneHistoryNow = { [weak self] in self?.pruneHistoryNow() }

    settingsWindow.onInterfaceLanguageChanged = { [weak self] _ in
      Task { @MainActor in
        self?.refreshLocalizedUI()
      }
    }

    _ = AXSelectionReader.ensureAccessibilityPermission(prompt: false)

    refreshLocalizedUI()

    // Apply retention policy at launch.
    _ = historyStore.pruneIfEnabled(enabled: settings.historyRetentionEnabled, keepDays: settings.historyRetentionDays)

    // Periodic prune for long-running sessions.
    Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        _ = self.historyStore.pruneIfEnabled(enabled: self.settings.historyRetentionEnabled, keepDays: self.settings.historyRetentionDays)
      }
    }

    // Self-test helper (no-op unless enabled via env var).
    if let mode = ProcessInfo.processInfo.environment["COPYTOASK_SELFTEST"], !mode.isEmpty {
      let logURL = URL(fileURLWithPath: "/tmp/copytoask_selftest.log")
      func log(_ s: String) {
        let line = "\(Date().timeIntervalSince1970) \(s)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: logURL.path) {
          FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        guard let fh = try? FileHandle(forWritingTo: logURL) else { return }
        fh.seekToEndOfFile()
        fh.write(data)
        fh.closeFile()
      }

      log("scheduling mode=\(mode)")
      Task { @MainActor [weak self] in
        guard let self else { return }

        log("task start mode=\(mode)")

        if mode == "settings" {
          log("opening settings")
          self.openSettings()
        } else if mode == "settings-key" {
          log("opening settings (make key)")
          self.openSettings()
          self.settingsWindow.window?.makeKeyAndOrderFront(nil)
        } else if mode == "explain" {
          log("showing explain panel")
          let p = ExplainPanelController()
          p.show(message: "Selftest", anchor: .mouse, language: self.settings.defaultAnswerLanguage, headerTitle: "Explain", contextText: nil)
          log("explain panel shown")
        } else if mode == "context" {
          log("showing context panel")
          self.contextPanel.show(items: [], anchor: .mouse)
        } else {
          log("showing all windows")
          self.openSettings()
          let p = ExplainPanelController()
          p.show(message: "Selftest", anchor: .mouse, language: self.settings.defaultAnswerLanguage, headerTitle: "Explain", contextText: nil)
          self.contextPanel.show(items: [], anchor: .mouse)
        }

        log("sleeping")
        try? await Task.sleep(nanoseconds: 600_000_000)
        log("terminating")
        NSApp.terminate(nil)
      }
    }
  }

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = L10n.text(.statusTitle, lang: settings.interfaceLanguage)

    let menu = NSMenu()

    let explainItem = NSMenuItem(title: L10n.text(.menuExplain, lang: settings.interfaceLanguage), action: #selector(explainFromMenu), keyEquivalent: "")
    explainItem.target = self
    explainItem.image = symbolImage("text.magnifyingglass")
    menu.addItem(explainItem)
    explainMenuItem = explainItem

    let askItem = NSMenuItem(title: L10n.text(.menuAsk, lang: settings.interfaceLanguage), action: #selector(askFromMenu), keyEquivalent: "")
    askItem.target = self
    askItem.image = symbolImage("questionmark.bubble")
    menu.addItem(askItem)
    askMenuItem = askItem

    let setContextItem = NSMenuItem(title: L10n.text(.menuSetContext, lang: settings.interfaceLanguage), action: #selector(setContextFromMenu), keyEquivalent: "")
    setContextItem.target = self
    setContextItem.image = symbolImage("highlighter")
    menu.addItem(setContextItem)
    contextMenuItem = setContextItem

    let showContextItem = NSMenuItem(title: L10n.text(.menuCurrentContext, lang: settings.interfaceLanguage), action: #selector(showContextFromMenu), keyEquivalent: "")
    showContextItem.target = self
    showContextItem.image = symbolImage("rectangle.stack")
    menu.addItem(showContextItem)
    showContextMenuItem = showContextItem

    let clearContextItem = NSMenuItem(title: L10n.text(.menuClearContext, lang: settings.interfaceLanguage), action: #selector(clearContext), keyEquivalent: "")
    clearContextItem.target = self
    clearContextItem.image = symbolImage("xmark.circle")
    menu.addItem(clearContextItem)
    clearContextMenuItem = clearContextItem

    menu.addItem(.separator())

    let authItem = NSMenuItem(title: L10n.text(.menuOpenAIAuth, lang: settings.interfaceLanguage), action: #selector(setAPIKey), keyEquivalent: "")
    authItem.target = self
    authItem.image = symbolImage("key")
    menu.addItem(authItem)
    authMenuItem = authItem

    let toolsItem = NSMenuItem(title: L10n.text(.menuTools, lang: settings.interfaceLanguage), action: nil, keyEquivalent: "")
    let toolsMenu = NSMenu(title: L10n.text(.menuTools, lang: settings.interfaceLanguage))
    toolsItem.submenu = toolsMenu
    menu.addItem(toolsItem)
    toolsMenuItem = toolsItem

    let diagItem = NSMenuItem(title: L10n.text(.menuShowDiagnostics, lang: settings.interfaceLanguage), action: #selector(showDiagnostics), keyEquivalent: "")
    diagItem.target = self
    diagItem.image = symbolImage("stethoscope")
    toolsMenu.addItem(diagItem)
    diagnosticsMenuItem = diagItem

    // Explain output language (separate from interface language)
    let explainLangItem = NSMenuItem(title: L10n.text(.menuExplainLanguage, lang: settings.interfaceLanguage), action: nil, keyEquivalent: "")
    let explainLangMenu = NSMenu(title: L10n.text(.menuExplainLanguage, lang: settings.interfaceLanguage))
    explainLangItem.submenu = explainLangMenu
    toolsMenu.addItem(explainLangItem)
    explainLanguageMenuItem = explainLangItem

    let zhItem = NSMenuItem(title: L10n.text(.explainLanguageChinese, lang: settings.interfaceLanguage), action: #selector(setExplainLanguageChinese), keyEquivalent: "")
    zhItem.target = self
    explainLangMenu.addItem(zhItem)
    explainLanguageChineseMenuItem = zhItem

    let enItem = NSMenuItem(title: L10n.text(.explainLanguageEnglish, lang: settings.interfaceLanguage), action: #selector(setExplainLanguageEnglish), keyEquivalent: "")
    enItem.target = self
    explainLangMenu.addItem(enItem)
    explainLanguageEnglishMenuItem = enItem

    updateExplainLanguageMenuState()

    let openAxItem = NSMenuItem(title: L10n.text(.menuOpenAccessibilitySettings, lang: settings.interfaceLanguage), action: #selector(openAccessibilitySettings), keyEquivalent: "")
    openAxItem.target = self
    openAxItem.image = symbolImage("hand.raised")
    toolsMenu.addItem(openAxItem)
    openAccessibilityMenuItem = openAxItem

    let openInputItem = NSMenuItem(title: L10n.text(.menuOpenInputMonitoringSettings, lang: settings.interfaceLanguage), action: #selector(openInputMonitoringSettings), keyEquivalent: "")
    openInputItem.target = self
    openInputItem.image = symbolImage("keyboard")
    toolsMenu.addItem(openInputItem)
    openInputMonitoringMenuItem = openInputItem

    let openHistoryItem = NSMenuItem(title: L10n.text(.menuHistoryFolder, lang: settings.interfaceLanguage), action: #selector(openHistoryFolder), keyEquivalent: "")
    openHistoryItem.target = self
    openHistoryItem.image = symbolImage("folder")
    toolsMenu.addItem(openHistoryItem)
    openHistoryMenuItem = openHistoryItem

    let settingsItem = NSMenuItem(title: L10n.text(.menuSettings, lang: settings.interfaceLanguage), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
    settingsItem.target = self
    settingsItem.image = symbolImage("gearshape")
    menu.addItem(settingsItem)
    settingsMenuItem = settingsItem

    menu.addItem(.separator())

    let quitItem = NSMenuItem(title: L10n.text(.menuQuit, lang: settings.interfaceLanguage), action: #selector(quit), keyEquivalent: "q")
    quitItem.target = self
    quitItem.image = symbolImage("power")
    menu.addItem(quitItem)
    quitMenuItem = quitItem

    statusItem.menu = menu
  }

  private func symbolImage(_ name: String) -> NSImage? {
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
    let out = img.withSymbolConfiguration(cfg) ?? img
    out.isTemplate = true
    return out
  }

  private func refreshLocalizedUI() {
    let ui = settings.interfaceLanguage

    statusItem.button?.title = L10n.text(.statusTitle, lang: ui)

    // Base titles (hotkey text is appended in refreshHotKeyUI()).
    explainMenuItem?.title = L10n.text(.menuExplain, lang: ui)
    askMenuItem?.title = L10n.text(.menuAsk, lang: ui)
    contextMenuItem?.title = L10n.text(.menuSetContext, lang: ui)
    showContextMenuItem?.title = L10n.text(.menuCurrentContext, lang: ui)
    clearContextMenuItem?.title = L10n.text(.menuClearContext, lang: ui)
    authMenuItem?.title = L10n.text(.menuOpenAIAuth, lang: ui)
    toolsMenuItem?.title = L10n.text(.menuTools, lang: ui)
    toolsMenuItem?.submenu?.title = L10n.text(.menuTools, lang: ui)
    diagnosticsMenuItem?.title = L10n.text(.menuShowDiagnostics, lang: ui)
    openAccessibilityMenuItem?.title = L10n.text(.menuOpenAccessibilitySettings, lang: ui)
    openInputMonitoringMenuItem?.title = L10n.text(.menuOpenInputMonitoringSettings, lang: ui)
    openHistoryMenuItem?.title = L10n.text(.menuHistoryFolder, lang: ui)
    settingsMenuItem?.title = L10n.text(.menuSettings, lang: ui)
    quitMenuItem?.title = L10n.text(.menuQuit, lang: ui)

    explainLanguageMenuItem?.title = L10n.text(.menuExplainLanguage, lang: ui)
    explainLanguageMenuItem?.submenu?.title = L10n.text(.menuExplainLanguage, lang: ui)
    explainLanguageChineseMenuItem?.title = L10n.text(.explainLanguageChinese, lang: ui)
    explainLanguageEnglishMenuItem?.title = L10n.text(.explainLanguageEnglish, lang: ui)
    updateExplainLanguageMenuState()

    refreshHotKeyUI()
    settingsWindow.refresh()
  }

  private func refreshHotKeyUI() {
    let explainDef = hotKeyManager.getDefinition(for: .explain) ?? settings.hotKey(for: .explain)
    let askDef = hotKeyManager.getDefinition(for: .ask) ?? settings.hotKey(for: .ask)
    let ctxDef = hotKeyManager.getDefinition(for: .setContext) ?? settings.hotKey(for: .setContext)

    let ui = settings.interfaceLanguage
    explainMenuItem?.title = "\(L10n.text(.menuExplain, lang: ui)) (\(HotKeyRecorderPanelController.format(def: explainDef)))"
    askMenuItem?.title = "\(L10n.text(.menuAsk, lang: ui)) (\(HotKeyRecorderPanelController.format(def: askDef)))"
    contextMenuItem?.title = "\(L10n.text(.menuSetContext, lang: ui)) (\(HotKeyRecorderPanelController.format(def: ctxDef)))"
  }

  private func updateExplainLanguageMenuState() {
    let lang = settings.defaultAnswerLanguage
    explainLanguageChineseMenuItem?.state = (lang == .zh) ? .on : .off
    explainLanguageEnglishMenuItem?.state = (lang == .en) ? .on : .off
  }

  @objc private func setExplainLanguageChinese() {
    settings.defaultAnswerLanguage = .zh
    updateExplainLanguageMenuState()
  }

  @objc private func setExplainLanguageEnglish() {
    settings.defaultAnswerLanguage = .en
    updateExplainLanguageMenuState()
  }

  @objc private func showDiagnostics() {
    TraceLog.log("showDiagnostics")
    let trusted = AXSelectionReader.ensureAccessibilityPermission(prompt: false)
    let bundlePath = Bundle.main.bundlePath
    let bundleID = Bundle.main.bundleIdentifier ?? "(nil)"
    let pid = ProcessInfo.processInfo.processIdentifier

    let codesign = codesignSummary(bundlePath: bundlePath)

    let (axText, axRect) = AXSelectionReader.readSelectedTextAndBounds()
    let axLen = axText?.count ?? 0

    let pbText = PasteboardFallback.copySelectionViaCmdCAndReadPasteboard()
    let pbLen = pbText?.count ?? 0

    let rectDesc: String
    if let axRect {
      rectDesc = "{x:\(Int(axRect.origin.x)), y:\(Int(axRect.origin.y)), w:\(Int(axRect.size.width)), h:\(Int(axRect.size.height))}"
    } else {
      rectDesc = "nil"
    }

    let msg = [
      "Bundle: \(bundlePath)",
      "Bundle ID: \(bundleID)",
      "PID: \(pid)",
      "Codesign: \(codesign)",
      "AX trusted: \(trusted)",
      "AX selectedText length: \(axLen)",
      "AX bounds: \(rectDesc)",
      "Pasteboard fallback length: \(pbLen)",
      "",
      "Tip: Select some text in another app, then open this Diagnostics again.",
    ].joined(separator: "\n")

    let alert = NSAlert()
    alert.messageText = "CopyToAsk Diagnostics"
    alert.informativeText = msg
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  private func codesignSummary(bundlePath: String) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
    p.arguments = ["-dv", "--verbose=4", bundlePath]

    let pipe = Pipe()
    p.standardError = pipe
    p.standardOutput = pipe

    do {
      try p.run()
    } catch {
      return "unavailable"
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let out = String(data: data, encoding: .utf8) ?? ""

    var authorities: [String] = []
    var signature: String?
    var teamID: String?
    var cdhash: String?
    for rawLine in out.split(separator: "\n") {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.hasPrefix("Authority=") {
        authorities.append(String(line.dropFirst("Authority=".count)))
      } else if line.hasPrefix("Signature=") {
        signature = String(line.dropFirst("Signature=".count))
      } else if line.hasPrefix("TeamIdentifier=") {
        teamID = String(line.dropFirst("TeamIdentifier=".count))
      } else if line.hasPrefix("CDHash=") {
        cdhash = String(line.dropFirst("CDHash=".count))
      }
    }

    var parts: [String] = []
    if let a = authorities.first { parts.append(a) }
    if let signature { parts.append("sig=\(signature)") }
    if let teamID { parts.append("team=\(teamID)") }
    if let cdhash { parts.append("cdhash=\(cdhash)") }
    if parts.isEmpty { return "unknown" }
    return parts.joined(separator: ", ")
  }

  @objc private func openAccessibilitySettings() {
    // Works on most macOS versions; if it fails, user can navigate manually.
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }

  @objc private func openInputMonitoringSettings() {
    // Input Monitoring (privacy) controls synthetic keyboard events on newer macOS.
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
      NSWorkspace.shared.open(url)
    }
  }

  private func setupMainMenu() {
    // Even for menu bar apps, having a main menu improves standard
    // text editing shortcuts (Cmd+V/C/X/A) in alerts and text fields.
    let main = NSMenu()

    let appItem = NSMenuItem()
    main.addItem(appItem)
    let appMenu = NSMenu()
    appItem.submenu = appMenu
    appMenu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))

    let editItem = NSMenuItem()
    main.addItem(editItem)
    let editMenu = NSMenu(title: "Edit")
    editItem.submenu = editMenu
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    NSApp.mainMenu = main
  }

  @objc private func explainFromMenu() {
    TraceLog.log("menu: explain")
    // Defer until after the status menu dismisses.
    DispatchQueue.main.async {
      self.triggerExplain()
    }
  }

  @objc private func askFromMenu() {
    TraceLog.log("menu: ask")
    // Defer until after the status menu dismisses.
    DispatchQueue.main.async {
      self.triggerAsk()
    }
  }

  @objc private func setContextFromMenu() {
    TraceLog.log("menu: setContext")
    // Defer until after the status menu dismisses.
    DispatchQueue.main.async {
      self.triggerSetContext()
    }
  }

  @MainActor
  private func triggerAsk() {
    handleAskHotKey()
  }

  @MainActor
  private func triggerSetContext() {
    handleSetContextHotKey()
  }

  @objc private func showContextFromMenu() {
    TraceLog.log("menu: showContext")
    // Defer until after the status menu dismisses.
    DispatchQueue.main.async {
      self.contextPanel.show(items: self.contextPanelItems(), anchor: self.pinnedContexts.last?.anchor ?? .mouse)
    }
  }

  @objc private func clearContext() {
    TraceLog.log("menu: clearContext")
    pinnedContexts.removeAll()
    contextPanel.hide()
  }

  private func deleteContextItem(_ id: UUID) {
    pinnedContexts.removeAll(where: { $0.id == id })
    if pinnedContexts.isEmpty {
      contextPanel.hide()
    } else {
      contextPanel.show(items: contextPanelItems(), anchor: pinnedContexts.last?.anchor ?? .mouse)
    }
  }

  private func contextPanelItems() -> [ContextItem] {
    pinnedContexts.map { ContextItem(id: $0.id, text: $0.text) }
  }

  private func aggregatedContextText() -> String? {
    let texts = pinnedContexts.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    guard !texts.isEmpty else { return nil }
    if texts.count == 1 { return texts[0] }
    return texts.enumerated().map { idx, t in
      "Context \(idx + 1):\n\(t)"
    }.joined(separator: "\n\n---\n\n")
  }

  private func beginSetHotKey(_ action: HotKeyAction) {
    recordingHotKeyAction = action
    hotKeyRecorder.show(current: settings.hotKey(for: action))
  }

  private func ensureAccessibilityOrPrompt() -> Bool {
    let trusted = AXSelectionReader.ensureAccessibilityPermission(prompt: true)
    guard !trusted else { return true }

    let cs = codesignSummary(bundlePath: Bundle.main.bundlePath)
    let adhoc = cs.contains("sig=adhoc") || cs.contains("team=not set")

    var extra = ""
    if adhoc {
      extra = "\n\nNote: this build is ad-hoc signed. macOS may require re-authorizing Accessibility after each rebuild. To keep permissions stable, run ./scripts/setup_local_codesign_identity.sh and rebuild, then re-add CopyToAsk in Accessibility."
    }

    let alert = NSAlert()
    alert.messageText = "Accessibility permission required"
    alert.informativeText = "CopyToAsk needs Accessibility permission to read selected text. Open System Settings → Privacy & Security → Accessibility.\n\nAfter enabling, quit and relaunch CopyToAsk." + extra
    alert.addButton(withTitle: "Open Settings")
    alert.addButton(withTitle: "OK")

      NSApp.activate(ignoringOtherApps: true)
      let resp = alert.runModal()
      if resp == .alertFirstButtonReturn {
        self.openAccessibilitySettings()
      }
    return false
  }

  private func handleSetContextHotKey() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      let selection = await SelectionCapture.capture()
      let text = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)
      if text.isEmpty {
        let trusted = AXSelectionReader.ensureAccessibilityPermission(prompt: false)
        if !trusted { _ = self.ensureAccessibilityOrPrompt() }
        return
      }

      let safeAnchor: SelectionAnchor
      switch selection.anchor {
      case .rect(let rect):
        let ok = NSScreen.screens.contains(where: { $0.frame.intersects(rect) })
        safeAnchor = ok ? .rect(rect) : .mouse
      case .mouse:
        safeAnchor = .mouse
      }

      pinnedContexts.append(PinnedContext(id: UUID(), text: text, anchor: safeAnchor, source: selection.source))
      self.contextPanel.show(items: self.contextPanelItems(), anchor: safeAnchor)
    }
  }

  private func handleAskHotKey() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      let selection = await SelectionCapture.capture()
      let text = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)

      let trusted = AXSelectionReader.ensureAccessibilityPermission(prompt: false)
      if text.isEmpty && !trusted {
        _ = self.ensureAccessibilityOrPrompt()
      }

      let ui = settings.interfaceLanguage
      let baseLang: AnswerLanguage = (ui == .zh) ? .zh : .en
      let id = UUID()
      let panel = ExplainPanelController()
      panel.onClose = { [weak self] in Task { @MainActor in self?.closeSession(id) } }

      let ghost = L10n.text(.askGhostPrompt, lang: ui)
      panel.setAskGhostPrompt(ghost)
      panel.setAskInteractionEnabled(true)
      panel.onAskSend = { [weak self] q in
        Task { @MainActor in self?.sendAskTurn(sessionID: id, question: q) }
      }

      let pending = ExplainSession(
        id: id,
        panel: panel,
        selectionText: text,
        anchor: selection.anchor,
        source: selection.source,
        historyID: UUID().uuidString,
        baseLanguage: baseLang,
        answers: [:],
        explainTask: nil,
        translateTask: nil,
        askPreviousResponseId: nil,
        askTranscriptMarkdown: ""
      )
      sessions[id] = pending

      panel.setAskSelectedText(text)
      panel.show(message: "", anchor: selection.anchor, language: baseLang, headerTitle: "Ask", contextText: nil, interfaceLanguage: ui)
      if text.isEmpty {
        let msg = trusted
          ? "No selected text found."
          : "No selected text found. Enable Accessibility (and optionally Input Monitoring)."
        panel.askAddSystemMessage(msg)
      }
    }
  }

  private func sendAskTurn(sessionID: UUID, question: String) {
    guard var s = sessions[sessionID] else { return }

    TraceLog.log("ask: send session=\(sessionID.uuidString.prefix(8)) qLen=\(question.count) prev=\(s.askPreviousResponseId != nil)")

    guard let apiKey = resolveAPIKey() else {
      TraceLog.log("ask: missing api key")
      s.panel.setBodyText("Missing OpenAI API key. Use Settings → OpenAI → Set… or set env var OPENAI_API_KEY.")
      return
    }

    let model = settings.modelId(for: settings.explainTier)
    let outputLang = (s.baseLanguage == .en) ? "English" : "Chinese"
    let instructions = "You are a helpful assistant. Answer in \(outputLang) using Markdown."

    // Build OpenAI-managed conversation: first call includes selection + context; follow-ups only include user question.
    let input: String
    if s.askPreviousResponseId == nil {
      var first = ""
      if let ctx = aggregatedContextText(), !ctx.isEmpty {
        first += "Context:\n\(ctx)\n\n"
      }
      first += "Selected text:\n\(s.selectionText)\n\n"
      first += "User question:\n\(question)"
      input = first
    } else {
      input = question
    }

    s.panel.setAskInteractionEnabled(false)
    s.panel.askAddUserMessage(question)
    s.panel.askStartAssistantMessage()
    sessions[sessionID] = s

    var capturedResponseId: String?
    let task = Task { [weak self, weak panel = s.panel] in
      guard let self, let panel else { return }
      do {
        var receivedChars = 0
        var loggedFirstDelta = false
        for try await delta in self.aiClient.streamResponseText(
          apiKey: apiKey,
          model: model,
          instructions: instructions,
          input: input,
          previousResponseId: self.sessions[sessionID]?.askPreviousResponseId,
          onResponseId: { rid in capturedResponseId = rid }
        ) {
          if Task.isCancelled { return }
          receivedChars += delta.count
          if !loggedFirstDelta {
            loggedFirstDelta = true
            TraceLog.log("ask: first delta len=\(delta.count)")
          }
          await MainActor.run {
            panel.askAppendAssistantDelta(delta)
          }
        }

        TraceLog.log("ask: stream done chars=\(receivedChars) rid=\(capturedResponseId ?? "(nil)")")

        await MainActor.run {
          guard var cur = self.sessions[sessionID] else { return }
          if let capturedResponseId { cur.askPreviousResponseId = capturedResponseId }
          cur.explainTask = nil
          self.sessions[sessionID] = cur
          panel.askFinishAssistantMessage()
          panel.setAskInteractionEnabled(true)
          panel.clearAskInput()
        }
      } catch {
        TraceLog.log("ask: stream error \(error.localizedDescription)")
        await MainActor.run {
          panel.setAskInteractionEnabled(true)
          panel.askAddSystemMessage("Request failed: \(error.localizedDescription)")
        }
      }
    }

    s.explainTask?.cancel()
    s.explainTask = task
    sessions[sessionID] = s
  }

  private func buildAskPrompt(text: String, question: String, language: AnswerLanguage, context: String?) -> [OpenAIClient.Message] {
    let outputLang = (language == .en) ? "English" : "Chinese"
    let system = "You are a helpful assistant. Answer in \(outputLang) using Markdown. Use the provided context only if it is relevant."

    var user = ""
    if let context, !context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      user += "Context (previous selection):\n\(context)\n\n"
    }
    user += "Selected text:\n\(text)\n\n"
    user += "User prompt:\n\(question)"

    return [
      .init(role: "system", content: system),
      .init(role: "user", content: user),
    ]
  }

  @MainActor
  private func triggerExplain() {
    Task { @MainActor [weak self] in
      guard let self else { return }

      // Capture selection BEFORE showing UI to avoid stealing focus and losing selection.
      let selection = await SelectionCapture.capture()
      let text = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)

      let trusted = AXSelectionReader.ensureAccessibilityPermission(prompt: false)
      if text.isEmpty && !trusted {
        _ = self.ensureAccessibilityOrPrompt()
      }

      let baseLang = settings.defaultAnswerLanguage
      let ui = settings.interfaceLanguage
      let id = UUID()
      let panel = ExplainPanelController()
      panel.onClose = { [weak self] in Task { @MainActor in self?.closeSession(id) } }
      panel.onTranslateToChanged = { [weak self] target in
        Task { @MainActor in self?.switchTranslation(sessionID: id, target: target) }
      }

      let session = ExplainSession(
        id: id,
        panel: panel,
        selectionText: text,
        anchor: selection.anchor,
        source: selection.source,
        historyID: UUID().uuidString,
        baseLanguage: baseLang,
        answers: [:],
        explainTask: nil,
        translateTask: nil,
        askPreviousResponseId: nil,
        askTranscriptMarkdown: ""
      )
      self.sessions[id] = session

      if text.isEmpty {
        let msg: String
        if trusted {
          msg = "No selected text found. Select some text and press the hotkey."
        } else {
          msg = "No selected text found. Enable Accessibility (and optionally Input Monitoring) in System Settings → Privacy & Security → Accessibility."
        }
        panel.show(message: msg, anchor: selection.anchor, language: baseLang, headerTitle: "Explain", contextText: aggregatedContextText(), interfaceLanguage: ui)
        panel.setTranslateEnabled(false)
        return
      }

      panel.show(message: "Loading…", anchor: selection.anchor, language: baseLang, headerTitle: "Explain", contextText: aggregatedContextText(), interfaceLanguage: ui)
      panel.setTranslateEnabled(false)

      guard let apiKey = resolveAPIKey() else {
        panel.setBodyText("Missing OpenAI API key. Use Settings → OpenAI → Set… or set env var OPENAI_API_KEY.")
        panel.setTranslateEnabled(false)
        return
      }

      let ctx = aggregatedContextText()
      let prompt = buildExplainPrompt(text: text, language: baseLang, context: ctx)
      let model = settings.modelId(for: settings.explainTier)

      let explainTask = Task { [weak self, weak panel] in
        guard let self, let panel else { return }
        do {
          var accumulated = ""
          for try await delta in self.aiClient.streamChatCompletion(apiKey: apiKey, model: model, messages: prompt) {
            if Task.isCancelled { return }
            accumulated.append(delta)
            await MainActor.run { panel.setBodyMarkdownStreaming(accumulated) }
          }

          let final = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
          await MainActor.run {
            if var s = self.sessions[id] {
              s.answers[baseLang.asTranslateLanguage] = final
              s.explainTask = nil
              self.sessions[id] = s
            }
            panel.setTranslateTo(baseLang.asTranslateLanguage)
            panel.setTranslateEnabled(true)
            panel.setBodyMarkdownFinal(final)
          }

          do {
            let app = NSWorkspace.shared.frontmostApplication
            let historyID = self.sessions[id]?.historyID ?? UUID().uuidString
            let entry = HistoryEntry(
              id: historyID,
              timestamp: Date(),
              appName: app?.localizedName,
              bundleIdentifier: app?.bundleIdentifier,
              selectionText: text,
              language: baseLang.rawValue,
              outputText: final,
              model: model,
              source: selection.source
            )
            try self.historyStore.append(entry)
          } catch {
            // Non-fatal.
          }
        } catch {
          await MainActor.run {
            panel.setBodyText("Request failed: \(error.localizedDescription)")
            panel.setTranslateEnabled(true)
          }
        }
      }

      if var s = self.sessions[id] {
        s.explainTask = explainTask
        self.sessions[id] = s
      }
    }
  }

  private func switchTranslation(sessionID: UUID, target: TranslateLanguage) {
    guard var s = sessions[sessionID] else { return }

    let baseTL = s.baseLanguage.asTranslateLanguage

    // Original.
    if target == baseTL, let base = s.answers[baseTL], !base.isEmpty {
      s.panel.setBodyMarkdownFinal(base)
      s.panel.setTranslateTo(baseTL)
      return
    }

    // Cached.
    if let cached = s.answers[target], !cached.isEmpty {
      s.panel.setBodyMarkdownFinal(cached)
      s.panel.setTranslateTo(target)
      return
    }

    guard let base = s.answers[baseTL], !base.isEmpty else {
      s.panel.setBodyText("Please wait for the explanation to finish, then translate.")
      s.panel.setTranslateTo(baseTL)
      return
    }

    s.translateTask?.cancel()
    s.panel.setTranslateEnabled(false)
    s.panel.setBodyText("Translating…")

    guard let apiKey = resolveAPIKey() else {
      s.panel.setBodyText("Missing OpenAI API key.")
      s.panel.setTranslateEnabled(true)
      sessions[sessionID] = s
      return
    }

    let prompt = buildTranslatePrompt(text: base, target: target)
    let model = settings.modelId(for: .cheap)

    let t = Task { [weak self, weak panel = s.panel] in
      guard let self, let panel else { return }
      do {
        var accumulated = ""
        for try await delta in self.aiClient.streamChatCompletion(apiKey: apiKey, model: model, messages: prompt) {
          if Task.isCancelled { return }
          accumulated.append(delta)
          panel.setBodyMarkdownStreaming(accumulated)
        }

        let final = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run {
          guard var cur = self.sessions[sessionID] else { return }
          cur.answers[target] = final
          cur.translateTask = nil
          self.sessions[sessionID] = cur
          panel.setTranslateTo(target)
          panel.setTranslateEnabled(true)
          panel.setBodyMarkdownFinal(final)
        }

        // Save history (translated answer).
        do {
          let app = NSWorkspace.shared.frontmostApplication
          let historyID = self.sessions[sessionID]?.historyID ?? UUID().uuidString
          let entry = HistoryEntry(
            id: historyID,
            timestamp: Date(),
            appName: app?.localizedName,
            bundleIdentifier: app?.bundleIdentifier,
            selectionText: self.sessions[sessionID]?.selectionText ?? "",
            language: target.rawValue,
            outputText: final,
            model: model,
            source: "translate"
          )
          try self.historyStore.append(entry)
        } catch {
          // Non-fatal.
        }
      } catch {
        await MainActor.run {
          panel.setBodyText("Translation failed: \(error.localizedDescription)")
          panel.setTranslateEnabled(true)
          panel.setTranslateTo(baseTL)
        }
      }
    }

    s.translateTask = t
    sessions[sessionID] = s
  }

  private func closeSession(_ id: UUID) {
    guard let s = sessions.removeValue(forKey: id) else { return }
    s.explainTask?.cancel()
    s.translateTask?.cancel()
  }

  @objc private func setAPIKey() {
    TraceLog.log("menu: openaiAuth")
    // Defer until after the status menu dismisses; improves focus.
    DispatchQueue.main.async {
      let chooser = NSAlert()
      chooser.messageText = "Sign In"
      chooser.informativeText = "Choose how you want to authenticate."
      chooser.addButton(withTitle: "API Key")
      chooser.addButton(withTitle: "Codex Login")
      chooser.addButton(withTitle: "Cancel")

      NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
      let resp = chooser.runModal()
      if resp == .alertFirstButtonReturn {
        self.settings.openAIAuthMethod = .apiKey
        self.presentAPIKeyEntryAndSave()
      } else if resp == .alertSecondButtonReturn {
        self.settings.openAIAuthMethod = .codex
        self.startCodexLogin()
      }
      self.settingsWindow.refresh()
    }
  }

  private func presentAPIKeyEntryAndSave() {
    let alert = NSAlert()
    alert.messageText = "Set OpenAI API Key"
    alert.informativeText = "Validated before saving. Stored locally in Keychain (account: openai_api_key)."
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")

    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
    field.placeholderString = "sk-…"
    alert.accessoryView = field

    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    alert.window.initialFirstResponder = field

    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else { return }
    let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return }

    Task {
      do {
        try await self.aiClient.validateAPIKey(apiKey: key, model: "gpt-4o-mini")

        // Keychain operations may trigger UI prompts; run on MainActor.
        try await MainActor.run {
          try self.keychain.writeString(key, account: "openai_api_key")
        }

        UserDefaults.standard.set(true, forKey: "openai.hasApiKey")
        await MainActor.run {
          self.settings.openAIAuthMethod = .apiKey
          self.apiKeyCache = key
          self.apiKeyLoaded = true
          let ok = NSAlert()
          ok.messageText = "API Key Verified"
          ok.informativeText = "Saved to Keychain."
          ok.addButton(withTitle: "OK")
          ok.runModal()
          self.settingsWindow.refresh()
        }
      } catch {
        await MainActor.run {
          let a = NSAlert()
          a.messageText = "API Key Validation Failed"
          a.informativeText = error.localizedDescription + "\n\nIf this happened after validation, Keychain write may have been blocked."
          a.addButton(withTitle: "OK")
          a.runModal()
        }
      }
    }
  }

  private func startCodexLogin() {
    let alert = NSAlert()
    alert.messageText = "Codex Login"
    alert.informativeText = "This prototype expects a local codex CLI login. If you have the codex CLI installed, run the command below in Terminal. After login, try Explain/Ask again."
    alert.addButton(withTitle: "Copy Command")
    alert.addButton(withTitle: "OK")

    let cmd = "codex auth login"
    let field = NSTextField(labelWithString: cmd)
    field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    alert.accessoryView = field

    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    let resp = alert.runModal()
    if resp == .alertFirstButtonReturn {
      let pb = NSPasteboard.general
      pb.clearContents()
      pb.setString(cmd, forType: .string)
    }
  }

  @objc private func openHistoryFolder() {
    TraceLog.log("menu: historyFolder")
    historyStore.openHistoryFolderInFinder()
  }

  @objc private func openSettingsFromMenu() {
    TraceLog.log("menu: settings")
    // Defer until after the status menu dismisses.
    DispatchQueue.main.async {
      self.openSettings()
    }
  }

  @objc private func openSettings() {
    TraceLog.log("openSettings() show")
    settingsWindow.show()
  }

  private func pruneHistoryNow() {
    let deleted = historyStore.pruneIfEnabled(enabled: settings.historyRetentionEnabled, keepDays: settings.historyRetentionDays)
    let a = NSAlert()
    a.messageText = "History Pruned"
    a.informativeText = "Deleted files: \(deleted)"
    a.addButton(withTitle: "OK")
    a.runModal()
    settingsWindow.refresh()
  }

  private func summarizeHistoryFiles(_ urls: [URL]) {
    let files = urls.filter { $0.pathExtension.lowercased() == "jsonl" }
    guard !files.isEmpty else { return }

    let id = UUID()
    let panel = ExplainPanelController()
    panel.onClose = { [weak self] in Task { @MainActor in self?.closeSession(id) } }

    let session = ExplainSession(
      id: id,
      panel: panel,
      selectionText: "",
      anchor: .mouse,
      source: "summary",
      historyID: UUID().uuidString,
      baseLanguage: .zh,
      answers: [:],
      explainTask: nil,
      translateTask: nil,
      askPreviousResponseId: nil,
      askTranscriptMarkdown: ""
    )
    sessions[id] = session

    panel.show(message: "Summarizing…", anchor: .mouse, language: .zh, headerTitle: "Summary", interfaceLanguage: settings.interfaceLanguage)
    panel.setTranslateEnabled(false)

    guard let apiKey = resolveAPIKey() else {
      panel.setBodyText("Missing OpenAI API key.")
      return
    }

    let label = summaryLabel(for: files)
    let model = settings.modelId(for: settings.summaryTier)

    let task = Task { [weak self, weak panel] in
      guard let self, let panel else { return }

      var allEntries: [HistoryEntry] = []
      for url in files {
        if Task.isCancelled { return }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if !text.isEmpty {
          allEntries.append(contentsOf: self.parseHistoryJSONL(text))
        }
      }

      if allEntries.isEmpty {
        await MainActor.run { panel.setBodyText("History files are empty.") }
        return
      }

      let compact = self.buildHistorySummaryInput(entries: allEntries, maxChars: 70_000)
      let prompt = self.buildHistorySummaryPrompt(dayLabel: label, content: compact)

      do {
        var md = ""
        for try await delta in self.aiClient.streamChatCompletion(apiKey: apiKey, model: model, messages: prompt) {
          if Task.isCancelled { return }
          md.append(delta)
          panel.setBodyMarkdownStreaming(md)
        }

        let final = md.trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run { panel.setBodyMarkdownFinal(final) }
        let outURL = try self.writeMarkdownSummary(final, dayLabel: label)
        await MainActor.run {
          panel.setBodyText(final + "\n\nSaved: \(outURL.path)")
        }
        NSWorkspace.shared.open(outURL)
      } catch {
        await MainActor.run {
          panel.setBodyText("Summary failed: \(error.localizedDescription)")
        }
      }
    }

    if var s = sessions[id] {
      s.explainTask = task
      sessions[id] = s
    }
  }

  private func summaryLabel(for urls: [URL]) -> String {
    let names = urls.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    if names.count == 1 { return names[0] }
    return "\(names.first!)_to_\(names.last!)"
  }

  private func parseHistoryJSONL(_ text: String) -> [HistoryEntry] {
    var out: [HistoryEntry] = []
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    for line in text.split(separator: "\n") {
      guard let data = String(line).data(using: .utf8) else { continue }
      if let e = try? decoder.decode(HistoryEntry.self, from: data) {
        out.append(e)
      }
    }
    return out
  }

  private func buildHistorySummaryInput(entries: [HistoryEntry], maxChars: Int) -> String {
    // Keep newest first, but include enough context.
    let sorted = entries.sorted { $0.timestamp < $1.timestamp }
    var out = ""
    for e in sorted {
      let ts = ISO8601DateFormatter().string(from: e.timestamp)
      out.append("- [\(ts)] (\(e.language)) selection: \(e.selectionText)\n")
      out.append("  answer: \(e.outputText)\n")
      out.append("\n")
      if out.count > maxChars { break }
    }
    return out
  }

  private func buildHistorySummaryPrompt(dayLabel: String, content: String) -> [OpenAIClient.Message] {
    let system = "You are a careful summarizer. Produce a Markdown document summarizing the user's learning for the day based ONLY on the provided logs. Do not invent facts. Output in Chinese (keep code/terms as-is when appropriate)."
    let user = "请把下面 \(dayLabel) 这段时间范围内的解释记录，整理成一篇结构清晰的 Markdown 笔记。\n\n要求：\n- 使用标题/小标题/要点列表\n- 按主题归类（合并重复概念）\n- 给出一个简短的‘关键收获’(Key Takeaways)\n- 简洁但有用，不要编造\n\n记录：\n\n\(content)"
    return [
      .init(role: "system", content: system),
      .init(role: "user", content: user),
    ]
  }

  private func writeMarkdownSummary(_ markdown: String, dayLabel: String) throws -> URL {
    let base = historyStore.historyDirectoryURL().appendingPathComponent("Summaries", isDirectory: true)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    let url = base.appendingPathComponent("\(dayLabel).md")
    try markdown.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  @objc private func clearAPIKey() {
    do {
      try keychain.delete(account: "openai_api_key")
      UserDefaults.standard.set(false, forKey: "openai.hasApiKey")
      apiKeyCache = nil
      apiKeyLoaded = true
      settingsWindow.refresh()
    } catch {
      let err = NSAlert(error: error)
      err.runModal()
    }
  }

  private func loadAPIKeyIfNeeded() -> String? {
    if apiKeyLoaded { return apiKeyCache }
    apiKeyLoaded = true
    // If the user never saved a key, don't touch Keychain (avoids prompts).
    guard hasAPIKeyFlag else { return nil }
    if let key = (try? keychain.readString(account: "openai_api_key")) ?? nil, !key.isEmpty {
      apiKeyCache = key
      return key
    }
    return nil
  }

  private func resolveAPIKey() -> String? {
    let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let env, !env.isEmpty { return env }

    switch settings.openAIAuthMethod {
    case .apiKey:
      return loadAPIKeyIfNeeded()
    case .codex:
      return loadCodexToken()
    }
  }

  private func loadCodexToken() -> String? {
    // Best-effort: support env vars first.
    let envNames = ["OPENAI_ACCESS_TOKEN", "CODEX_ACCESS_TOKEN", "CODEX_TOKEN"]
    for name in envNames {
      if let v = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
        return v
      }
    }

    let home = FileManager.default.homeDirectoryForCurrentUser
    let candidates: [URL] = [
      home.appendingPathComponent(".config/codex/auth.json"),
      home.appendingPathComponent(".codex/auth.json"),
      home.appendingPathComponent(".config/openai/auth.json"),
    ]
    for url in candidates {
      if let token = readTokenFromJSON(url: url) {
        return token
      }
    }
    return nil
  }

  private func readTokenFromJSON(url: URL) -> String? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    let keys = ["access_token", "token", "api_key"]
    for k in keys {
      if let v = obj[k] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return v.trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    return nil
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func buildExplainPrompt(text: String, language: AnswerLanguage, context: String?) -> [OpenAIClient.Message] {
    let style: String
    switch settings.explainTier {
    case .cheap:
      style = "Be concise."
    case .medium:
      style = "Provide a clear explanation with key points."
    case .detailed:
      style = "Be thorough: include extra context, assumptions, and a brief example when helpful."
    }

    let outputLang = (language == .en) ? "English" : "Chinese"
    let system = "You are a helpful assistant. The user will provide selected text from their screen. Explain its meaning accurately. If the text is ambiguous, ask brief clarifying questions. Do not fabricate sources. Output in \(outputLang) using Markdown. \(style)"
    let template = promptStore.explainTemplate(language: language)
    let user = PromptTemplate.render(template, variables: [
      "text": text,
      "context": context ?? "",
    ])
    return [
      .init(role: "system", content: system),
      .init(role: "user", content: user),
    ]
  }

  private func buildTranslatePrompt(text: String, target: TranslateLanguage) -> [OpenAIClient.Message] {
    let system = "You are a translation engine. Translate faithfully and do not add new information."
    let template = promptStore.translateExplainTemplate()
    let user = PromptTemplate.render(template, variables: [
      "text": text,
      "target_language": target.targetLanguageNameForPrompt,
    ])
    return [
      .init(role: "system", content: system),
      .init(role: "user", content: user),
    ]
  }

}

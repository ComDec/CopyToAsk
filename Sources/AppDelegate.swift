import Cocoa
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var explainMenuItem: NSMenuItem?
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
    var answers: [AnswerLanguage: String]
    var explainTask: Task<Void, Never>?
    var translateTask: Task<Void, Never>?
  }

  private var sessions: [UUID: ExplainSession] = [:]

  private var apiKeyCache: String?
  private var apiKeyLoaded = false
  private var hasAPIKeyFlag: Bool {
    UserDefaults.standard.bool(forKey: "openai.hasApiKey")
  }

  private enum DefaultsKeys {
    static let hotKeyCode = "hotkey.keyCode"
    static let hotKeyMods = "hotkey.carbonModifiers"
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    setupMainMenu()
    setupStatusItem()

    let initialHotKey = loadHotKeyFromDefaults() ?? HotKeyDefinition.default
    hotKeyManager.register(defaultIfNil: initialHotKey)
    hotKeyManager.onHotKey = { [weak self] in
      self?.handleExplainHotKey()
    }

    hotKeyRecorder.onSave = { [weak self] def in
      guard let self else { return }
      self.saveHotKeyToDefaults(def)
      let status = self.hotKeyManager.setHotKey(def)
      if status != noErr {
        let a = NSAlert()
        a.messageText = "Failed to register hotkey"
        a.informativeText = "OSStatus: \(status)"
        a.runModal()
      }
      self.refreshHotKeyUI()
    }

    refreshHotKeyUI()

    settingsWindow.onSetHotKey = { [weak self] in self?.setHotKey() }
    settingsWindow.getHotKeyLabel = { [weak self] in
      guard let self else { return "" }
      return HotKeyRecorderPanelController.format(def: self.hotKeyManager.getHotKey())
    }
    settingsWindow.onSetAPIKey = { [weak self] in self?.setAPIKey() }
    settingsWindow.onClearAPIKey = { [weak self] in self?.clearAPIKey() }
    settingsWindow.getAPIKeyStatus = { [weak self] in
      guard self != nil else { return "" }
      if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return "Using OPENAI_API_KEY env var"
      }
      let saved = UserDefaults.standard.bool(forKey: "openai.hasApiKey")
      return saved ? "Saved in Keychain" : "Not set"
    }
    settingsWindow.onEditExplainPrompt = { [weak self] in self?.editExplainPrompt() }
    settingsWindow.onResetExplainPrompt = { [weak self] in self?.resetExplainPrompt() }
    settingsWindow.onEditTranslatePrompt = { [weak self] in self?.editTranslatePrompt() }
    settingsWindow.onResetTranslatePrompt = { [weak self] in self?.resetTranslatePrompt() }
    settingsWindow.onOpenHistoryFolder = { [weak self] in self?.openHistoryFolder() }
    settingsWindow.onSummarizeHistoryFile = { [weak self] urls in self?.summarizeHistoryFiles(urls) }
    settingsWindow.onPruneHistoryNow = { [weak self] in self?.pruneHistoryNow() }

    _ = AXSelectionReader.ensureAccessibilityPermission(prompt: true)

    // Apply retention policy at launch.
    _ = historyStore.pruneIfEnabled(enabled: settings.historyRetentionEnabled, keepDays: settings.historyRetentionDays)

    // Periodic prune for long-running sessions.
    Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        _ = self.historyStore.pruneIfEnabled(enabled: self.settings.historyRetentionEnabled, keepDays: self.settings.historyRetentionDays)
      }
    }
  }

  private func setupStatusItem() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = "Ask"

    let menu = NSMenu()

    let explainItem = NSMenuItem(title: "Explain Selection", action: #selector(explainFromMenu), keyEquivalent: "")
    explainItem.target = self
    explainItem.image = symbolImage("text.magnifyingglass")
    menu.addItem(explainItem)
    explainMenuItem = explainItem

    let setHotKeyItem = NSMenuItem(title: "Set Hotkey…", action: #selector(setHotKey), keyEquivalent: "")
    setHotKeyItem.target = self
    setHotKeyItem.image = symbolImage("keyboard")
    menu.addItem(setHotKeyItem)

    let resetHotKeyItem = NSMenuItem(title: "Reset Hotkey", action: #selector(resetHotKey), keyEquivalent: "")
    resetHotKeyItem.target = self
    resetHotKeyItem.image = symbolImage("arrow.counterclockwise")
    menu.addItem(resetHotKeyItem)

    menu.addItem(.separator())

    let setKeyItem = NSMenuItem(title: "Set OpenAI API Key…", action: #selector(setAPIKey), keyEquivalent: "")
    setKeyItem.target = self
    setKeyItem.image = symbolImage("key")
    menu.addItem(setKeyItem)

    let clearKeyItem = NSMenuItem(title: "Clear OpenAI API Key", action: #selector(clearAPIKey), keyEquivalent: "")
    clearKeyItem.target = self
    clearKeyItem.image = symbolImage("trash")
    menu.addItem(clearKeyItem)

    menu.addItem(.separator())

    let diagItem = NSMenuItem(title: "Diagnostics…", action: #selector(showDiagnostics), keyEquivalent: "")
    diagItem.target = self
    diagItem.image = symbolImage("stethoscope")
    menu.addItem(diagItem)

    let openAxItem = NSMenuItem(title: "Open Accessibility Settings", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    openAxItem.target = self
    openAxItem.image = symbolImage("hand.raised")
    menu.addItem(openAxItem)

    let openHistoryItem = NSMenuItem(title: "Open History Folder", action: #selector(openHistoryFolder), keyEquivalent: "")
    openHistoryItem.target = self
    openHistoryItem.image = symbolImage("folder")
    menu.addItem(openHistoryItem)

    let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    settingsItem.target = self
    settingsItem.image = symbolImage("gearshape")
    menu.addItem(settingsItem)

    menu.addItem(.separator())

    let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
    quitItem.target = self
    quitItem.image = symbolImage("power")
    menu.addItem(quitItem)

    statusItem.menu = menu
  }

  private func symbolImage(_ name: String) -> NSImage? {
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
    let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
    let out = img.withSymbolConfiguration(cfg) ?? img
    out.isTemplate = true
    return out
  }

  private func refreshHotKeyUI() {
    let def = hotKeyManager.getHotKey()
    let title = "Explain Selection (\(HotKeyRecorderPanelController.format(def: def)))"
    explainMenuItem?.title = title
  }

  private func loadHotKeyFromDefaults() -> HotKeyDefinition? {
    let d = UserDefaults.standard
    if d.object(forKey: DefaultsKeys.hotKeyCode) == nil { return nil }
    let code = d.integer(forKey: DefaultsKeys.hotKeyCode)
    let mods = d.integer(forKey: DefaultsKeys.hotKeyMods)
    return HotKeyDefinition(keyCode: UInt32(code), carbonModifiers: UInt32(mods))
  }

  private func saveHotKeyToDefaults(_ def: HotKeyDefinition) {
    let d = UserDefaults.standard
    d.set(Int(def.keyCode), forKey: DefaultsKeys.hotKeyCode)
    d.set(Int(def.carbonModifiers), forKey: DefaultsKeys.hotKeyMods)
  }

  @objc private func showDiagnostics() {
    let trusted = AXSelectionReader.ensureAccessibilityPermission(prompt: false)
    let bundlePath = Bundle.main.bundlePath
    let pid = ProcessInfo.processInfo.processIdentifier

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
      "PID: \(pid)",
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

  @objc private func openAccessibilitySettings() {
    // Works on most macOS versions; if it fails, user can navigate manually.
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
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
    handleExplainHotKey()
  }

  @objc private func setHotKey() {
    hotKeyRecorder.show(current: hotKeyManager.getHotKey())
  }

  @objc private func resetHotKey() {
    let def = HotKeyDefinition.default
    saveHotKeyToDefaults(def)
    let status = hotKeyManager.setHotKey(def)
    if status != noErr {
      let a = NSAlert()
      a.messageText = "Failed to register hotkey"
      a.informativeText = "OSStatus: \(status)"
      a.runModal()
    }
    refreshHotKeyUI()
  }

  private func handleExplainHotKey() {
    Task { [weak self] in
      guard let self else { return }

      guard AXSelectionReader.ensureAccessibilityPermission(prompt: true) else {
        let id = UUID()
        let panel = ExplainPanelController()
        panel.onClose = { [weak self] in Task { @MainActor in self?.closeSession(id) } }
        let session = ExplainSession(id: id, panel: panel, selectionText: "", anchor: .mouse, source: "none", historyID: UUID().uuidString, answers: [:], explainTask: nil, translateTask: nil)
        self.sessions[id] = session
        panel.show(message: "Please enable Accessibility permission for CopyToAsk in System Settings → Privacy & Security → Accessibility.", anchor: .mouse, language: .en)
        panel.setLanguageEnabled(false)
        return
      }

      let selection = await SelectionCapture.capture()
      let text = selection.text.trimmingCharacters(in: .whitespacesAndNewlines)

      let id = UUID()
      let panel = ExplainPanelController()
      panel.onClose = { [weak self] in Task { @MainActor in self?.closeSession(id) } }
      panel.onLanguageChanged = { [weak self] lang in Task { @MainActor in self?.switchLanguage(sessionID: id, lang: lang) } }

      let session = ExplainSession(
        id: id,
        panel: panel,
        selectionText: text,
        anchor: selection.anchor,
        source: selection.source,
        historyID: UUID().uuidString,
        answers: [:],
        explainTask: nil,
        translateTask: nil
      )
      self.sessions[id] = session

      if text.isEmpty {
        panel.show(message: "No selected text found. Select some text and press the hotkey.", anchor: selection.anchor, language: .zh)
        panel.setLanguageEnabled(false)
        return
      }

      panel.show(message: "Loading…", anchor: selection.anchor, language: .zh)
      panel.setLanguageEnabled(false)

      guard let apiKey = resolveAPIKey() else {
        panel.setBodyText("Missing OpenAI API key. Use Settings → OpenAI → Set… or set env var OPENAI_API_KEY.")
        panel.setLanguageEnabled(false)
        return
      }

      let prompt = buildExplainPrompt(text: text)
      let model = settings.modelId(for: settings.explainTier)

      let explainTask = Task { [weak self, weak panel] in
        guard let self, let panel else { return }
        do {
          var accumulated = ""
          for try await delta in self.aiClient.streamChatCompletion(apiKey: apiKey, model: model, messages: prompt) {
            if Task.isCancelled { return }
            accumulated.append(delta)
            panel.setBodyText(accumulated)
          }

          let final = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
          await MainActor.run {
            if var s = self.sessions[id] {
              s.answers[.zh] = final
              s.explainTask = nil
              self.sessions[id] = s
            }
            panel.setLanguage(.zh)
            panel.setLanguageEnabled(true)
          }

          // Save history (Chinese answer).
          do {
            let app = NSWorkspace.shared.frontmostApplication
            let historyID = self.sessions[id]?.historyID ?? UUID().uuidString
            let entry = HistoryEntry(
              id: historyID,
              timestamp: Date(),
              appName: app?.localizedName,
              bundleIdentifier: app?.bundleIdentifier,
              selectionText: text,
              language: "zh",
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
            panel.setLanguageEnabled(true)
          }
        }
      }

      if var s = self.sessions[id] {
        s.explainTask = explainTask
        self.sessions[id] = s
      }
    }
  }

  private func switchLanguage(sessionID: UUID, lang: AnswerLanguage) {
    guard var s = sessions[sessionID] else { return }

    if let cached = s.answers[lang], !cached.isEmpty {
      s.panel.setBodyText(cached)
      s.panel.setLanguage(lang)
      return
    }

    guard let zh = s.answers[.zh], !zh.isEmpty else {
      s.panel.setBodyText("Please wait for the explanation to finish, then switch language.")
      s.panel.setLanguage(.zh)
      return
    }

    s.translateTask?.cancel()
    s.panel.setLanguageEnabled(false)
    s.panel.setBodyText("Translating…")

    guard let apiKey = resolveAPIKey() else {
      s.panel.setBodyText("Missing OpenAI API key.")
      s.panel.setLanguageEnabled(true)
      sessions[sessionID] = s
      return
    }

    let prompt = buildTranslatePrompt(text: zh, target: lang)
    let model = settings.modelId(for: .cheap)

    let t = Task { [weak self, weak panel = s.panel] in
      guard let self, let panel else { return }
      do {
        var accumulated = ""
        for try await delta in self.aiClient.streamChatCompletion(apiKey: apiKey, model: model, messages: prompt) {
          if Task.isCancelled { return }
          accumulated.append(delta)
          panel.setBodyText(accumulated)
        }

        let final = accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
        await MainActor.run {
          guard var cur = self.sessions[sessionID] else { return }
          cur.answers[lang] = final
          cur.translateTask = nil
          self.sessions[sessionID] = cur
          panel.setLanguage(lang)
          panel.setLanguageEnabled(true)
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
            language: lang.rawValue,
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
          panel.setLanguageEnabled(true)
          panel.setLanguage(.zh)
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
    // Defer until after the status menu dismisses; improves focus.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let alert = NSAlert()
      alert.messageText = "Set OpenAI API Key"
      alert.informativeText = "Stored locally in Keychain (account: openai_api_key)."
      alert.addButton(withTitle: "Save")
      alert.addButton(withTitle: "Cancel")

      let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
      field.placeholderString = "sk-…"
      alert.accessoryView = field

      NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
      alert.window.initialFirstResponder = field
      alert.window.makeKeyAndOrderFront(nil)
      alert.window.makeFirstResponder(field)

      let response = alert.runModal()
      guard response == .alertFirstButtonReturn else { return }
      let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !key.isEmpty else { return }

      // Validate first (do not touch Keychain if invalid).
      Task {
        do {
          try await self.aiClient.validateAPIKey(apiKey: key, model: "gpt-4o-mini")
          try self.keychain.writeString(key, account: "openai_api_key")
          UserDefaults.standard.set(true, forKey: "openai.hasApiKey")
          await MainActor.run {
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
            a.informativeText = error.localizedDescription
            a.addButton(withTitle: "OK")
            a.runModal()
          }
        }
      }
    }
  }

  @objc private func openHistoryFolder() {
    historyStore.openHistoryFolderInFinder()
  }

  @objc private func openSettings() {
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
      answers: [:],
      explainTask: nil,
      translateTask: nil
    )
    sessions[id] = session

    panel.show(message: "Summarizing…", anchor: .mouse, language: .en)
    panel.setLanguageEnabled(false)

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
          panel.setBodyText(md)
        }

        let final = md.trimmingCharacters(in: .whitespacesAndNewlines)
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
    return loadAPIKeyIfNeeded()
  }

  @objc private func quit() {
    NSApp.terminate(nil)
  }

  private func buildExplainPrompt(text: String) -> [OpenAIClient.Message] {
    let style: String
    switch settings.explainTier {
    case .cheap:
      style = "Be concise."
    case .medium:
      style = "Provide a clear explanation with key points."
    case .detailed:
      style = "Be thorough: include extra context, assumptions, and a brief example when helpful."
    }

    let system = "You are a helpful assistant. The user will provide selected text from their screen. Explain its meaning accurately. If the text is ambiguous, ask brief clarifying questions. Do not fabricate sources. Output in Chinese. \(style)"
    let template = promptStore.explainTemplate()
    let user = PromptTemplate.render(template, variables: ["text": text])
    return [
      .init(role: "system", content: system),
      .init(role: "user", content: user),
    ]
  }

  private func buildTranslatePrompt(text: String, target: AnswerLanguage) -> [OpenAIClient.Message] {
    let system = "You are a translation engine. Translate faithfully and do not add new information."
    let template = promptStore.translateTemplate()
    let user = PromptTemplate.render(template, variables: [
      "text": text,
      "target_language": target.targetLanguageNameForPrompt,
    ])
    return [
      .init(role: "system", content: system),
      .init(role: "user", content: user),
    ]
  }

  @objc private func editExplainPrompt() {
    editLongText(title: "Edit Explain Prompt", note: "Use {text} as placeholder for the selected text.", initial: promptStore.explainTemplate()) { [weak self] newValue in
      self?.promptStore.setExplainTemplate(newValue)
    }
  }

  @objc private func resetExplainPrompt() {
    promptStore.resetExplainTemplate()
  }

  @objc private func editTranslatePrompt() {
    editLongText(title: "Edit Translation Prompt", note: "Use {text} and {target_language} placeholders.", initial: promptStore.translateTemplate()) { [weak self] newValue in
      self?.promptStore.setTranslateTemplate(newValue)
    }
  }

  @objc private func resetTranslatePrompt() {
    promptStore.resetTranslateTemplate()
  }

  private func editLongText(title: String, note: String, initial: String, onSave: @escaping (String) -> Void) {
    DispatchQueue.main.async {
      let alert = NSAlert()
      alert.messageText = title
      alert.informativeText = note
      alert.addButton(withTitle: "Save")
      alert.addButton(withTitle: "Cancel")

      let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 220))
      tv.string = initial
      tv.isRichText = false
      tv.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

      let scroll = NSScrollView(frame: tv.frame)
      scroll.hasVerticalScroller = true
      scroll.documentView = tv
      scroll.contentView.postsBoundsChangedNotifications = true

      alert.accessoryView = scroll

      NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
      let response = alert.runModal()
      guard response == .alertFirstButtonReturn else { return }

      let value = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !value.isEmpty else { return }
      onSave(value)
    }
  }

}

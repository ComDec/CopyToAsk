import Cocoa
import Carbon

@MainActor
final class HotKeyRecorderPanelController: NSObject {
  private var panel: NSPanel?
  private var label: NSTextField?
  private var display: NSTextField?
  private var saveButton: NSButton?
  private var cancelButton: NSButton?
  private var localMonitor: Any?

  private var captured: HotKeyDefinition?
  var onSave: ((HotKeyDefinition) -> Void)?

  func show(current: HotKeyDefinition) {
    ensureUI()
    captured = nil
    updateDisplay(text: "Press a new shortcut…")
    setButtonsEnabled(false)
    panel?.center()
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    panel?.makeKeyAndOrderFront(nil)
    installLocalMonitorIfNeeded()
  }

  private func ensureUI() {
    if panel != nil { return }

    let p = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 160),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    p.title = "Set Hotkey"
    p.isFloatingPanel = true
    p.level = .floating
    p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))

    let label = NSTextField(labelWithString: "Focus this window and press the desired shortcut (must include at least one modifier).")
    label.lineBreakMode = .byWordWrapping
    label.maximumNumberOfLines = 0
    label.font = .systemFont(ofSize: 12)

    let display = NSTextField(labelWithString: "")
    display.font = .systemFont(ofSize: 16, weight: .semibold)
    display.alignment = .center

    let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
    save.keyEquivalent = "\r"
    save.bezelStyle = .rounded

    let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
    cancel.bezelStyle = .rounded

    content.addSubview(label)
    content.addSubview(display)
    content.addSubview(save)
    content.addSubview(cancel)

    label.translatesAutoresizingMaskIntoConstraints = false
    display.translatesAutoresizingMaskIntoConstraints = false
    save.translatesAutoresizingMaskIntoConstraints = false
    cancel.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
      label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
      label.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),

      display.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
      display.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
      display.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 14),

      cancel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
      cancel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),

      save.trailingAnchor.constraint(equalTo: cancel.leadingAnchor, constant: -10),
      save.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
    ])

    p.contentView = content
    panel = p
    self.label = label
    self.display = display
    self.saveButton = save
    self.cancelButton = cancel
  }

  private func installLocalMonitorIfNeeded() {
    if localMonitor != nil { return }
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
      guard let self else { return event }
      // Esc cancels.
      if event.keyCode == 53 {
        Task { @MainActor in self.close() }
        return nil
      }

      let mods = event.modifierFlags.intersection([.command, .option, .shift, .control])
      if mods.isEmpty {
        Task { @MainActor in
          self.updateDisplay(text: "Add a modifier (Ctrl/Opt/Cmd/Shift)")
          self.setButtonsEnabled(false)
        }
        return nil
      }

      let def = HotKeyDefinition(eventKeyCode: event.keyCode, cocoaModifiers: mods)
      captured = def
      Task { @MainActor in
        self.updateDisplay(text: Self.format(def: def))
        self.setButtonsEnabled(true)
      }
      return nil
    }
  }

  private func removeLocalMonitorIfNeeded() {
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
      self.localMonitor = nil
    }
  }

  private func updateDisplay(text: String) {
    display?.stringValue = text
  }

  private func setButtonsEnabled(_ enabled: Bool) {
    saveButton?.isEnabled = enabled
  }

  @objc private func saveTapped() {
    guard let captured else { return }
    onSave?(captured)
    close()
  }

  @objc private func cancelTapped() {
    close()
  }

  private func close() {
    panel?.orderOut(nil)
    removeLocalMonitorIfNeeded()
  }

  static func format(def: HotKeyDefinition) -> String {
    var parts: [String] = []
    let m = def.carbonModifiers
    if (m & UInt32(controlKey)) != 0 { parts.append("⌃") }
    if (m & UInt32(optionKey)) != 0 { parts.append("⌥") }
    if (m & UInt32(shiftKey)) != 0 { parts.append("⇧") }
    if (m & UInt32(cmdKey)) != 0 { parts.append("⌘") }
    parts.append(keyName(for: def.keyCode))
    return parts.joined()
  }

  private static func keyName(for keyCode: UInt32) -> String {
    // Minimal map for common keys; fallback to numeric.
    switch keyCode {
    case 0: return "A"
    case 1: return "S"
    case 2: return "D"
    case 3: return "F"
    case 4: return "H"
    case 5: return "G"
    case 6: return "Z"
    case 7: return "X"
    case 8: return "C"
    case 9: return "V"
    case 11: return "B"
    case 12: return "Q"
    case 13: return "W"
    case 14: return "E"
    case 15: return "R"
    case 16: return "Y"
    case 17: return "T"
    case 31: return "O"
    case 32: return "U"
    case 34: return "I"
    case 35: return "P"
    case 37: return "L"
    case 38: return "J"
    case 40: return "K"
    case 45: return "N"
    case 46: return "M"
    case 36: return "↩"
    case 49: return "Space"
    default:
      return "#\(keyCode)"
    }
  }
}

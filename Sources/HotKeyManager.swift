import Cocoa
import Carbon

struct HotKeyDefinition: Equatable {
  var keyCode: UInt32
  var carbonModifiers: UInt32

  static let `default` = HotKeyDefinition(keyCode: 14, carbonModifiers: UInt32(controlKey | optionKey)) // Control+Option+E

  init(keyCode: UInt32, carbonModifiers: UInt32) {
    self.keyCode = keyCode
    self.carbonModifiers = carbonModifiers
  }

  init(eventKeyCode: UInt16, cocoaModifiers: NSEvent.ModifierFlags) {
    self.keyCode = UInt32(eventKeyCode)
    var m: UInt32 = 0
    if cocoaModifiers.contains(.control) { m |= UInt32(controlKey) }
    if cocoaModifiers.contains(.option) { m |= UInt32(optionKey) }
    if cocoaModifiers.contains(.shift) { m |= UInt32(shiftKey) }
    if cocoaModifiers.contains(.command) { m |= UInt32(cmdKey) }
    self.carbonModifiers = m
  }
}

enum HotKeyAction: Int, CaseIterable {
  case explain = 1
  case ask = 2
  case setContext = 3
}

final class HotKeyManager {
  private var eventHandlerRef: EventHandlerRef?
  private let signature = OSType(UInt32(truncatingIfNeeded: 0x43544F41)) // 'CTOA'

  private var refs: [HotKeyAction: EventHotKeyRef] = [:]
  private var defs: [HotKeyAction: HotKeyDefinition] = [:]
  private var handlers: [HotKeyAction: () -> Void] = [:]

  func installIfNeeded() {
    if eventHandlerRef != nil { return }
    var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
      guard let userData else { return noErr }
      let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
      var hkID = EventHotKeyID()
      GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
      guard hkID.signature == manager.signature else { return noErr }
      guard let action = HotKeyAction(rawValue: Int(hkID.id)) else { return noErr }
      manager.handlers[action]?()
      return noErr
    }, 1, &eventSpec, selfPtr, &eventHandlerRef)
  }

  func setHandler(for action: HotKeyAction, handler: @escaping () -> Void) {
    handlers[action] = handler
  }

  func getDefinition(for action: HotKeyAction) -> HotKeyDefinition? {
    defs[action]
  }

  @discardableResult
  func register(action: HotKeyAction, definition: HotKeyDefinition) -> OSStatus {
    installIfNeeded()

    if let ref = refs[action] {
      UnregisterEventHotKey(ref)
      refs.removeValue(forKey: action)
    }

    defs[action] = definition

    var ref: EventHotKeyRef?
    let hkID = EventHotKeyID(signature: signature, id: UInt32(action.rawValue))
    let status = RegisterEventHotKey(definition.keyCode, definition.carbonModifiers, hkID, GetApplicationEventTarget(), 0, &ref)
    if status == noErr, let ref {
      refs[action] = ref
    }
    return status
  }

  func unregisterAll() {
    for (_, ref) in refs {
      UnregisterEventHotKey(ref)
    }
    refs.removeAll()
    defs.removeAll()
  }

  deinit {
    unregisterAll()
    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
    }
  }
}

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

final class HotKeyManager {
  var onHotKey: (() -> Void)?

  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?

  private var current = HotKeyDefinition.default
  private let hotKeyID = EventHotKeyID(signature: OSType(UInt32(truncatingIfNeeded: 0x43544F41)), id: 1) // 'CTOA'

  func register(defaultIfNil def: HotKeyDefinition? = nil) {
    if eventHandlerRef == nil {
      var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
      let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
      InstallEventHandler(GetApplicationEventTarget(), { _, eventRef, userData in
        guard let userData else { return noErr }
        let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        var hkID = EventHotKeyID()
        GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hkID)
        if hkID.signature == manager.hotKeyID.signature && hkID.id == manager.hotKeyID.id {
          manager.onHotKey?()
        }
        return noErr
      }, 1, &eventSpec, selfPtr, &eventHandlerRef)
    }

    if let def { current = def }
    registerOrReregisterCurrent()
  }

  @discardableResult
  func setHotKey(_ def: HotKeyDefinition) -> OSStatus {
    current = def
    return registerOrReregisterCurrent()
  }

  func getHotKey() -> HotKeyDefinition {
    current
  }

  @discardableResult
  private func registerOrReregisterCurrent() -> OSStatus {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
    let status = RegisterEventHotKey(current.keyCode, current.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    return status
  }

  deinit {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
    }
    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
    }
  }
}

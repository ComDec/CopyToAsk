import Cocoa
import ApplicationServices

// Uses PasteboardFallback for Cmd+C fallback.

enum SelectionAnchor {
  case rect(CGRect)
  case mouse
}

struct CapturedSelection {
  let text: String
  let anchor: SelectionAnchor
  let source: String
}

@MainActor
enum AXSelectionReader {
  static func ensureAccessibilityPermission(prompt: Bool) -> Bool {
    let opts: [String: Any] = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: prompt]
    return AXIsProcessTrustedWithOptions(opts as CFDictionary)
  }

  static func readSelectedTextAndBounds() -> (text: String?, rect: CGRect?) {
    let systemWide = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    let focusedErr = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
    guard focusedErr == .success, let focusedElement = focused else {
      return (nil, nil)
    }
    guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
      return (nil, nil)
    }
    let focusedAX = (focusedElement as! AXUIElement)

    // Some apps expose selection attributes on a parent of the focused element.
    let candidates = walkUpParents(from: focusedAX, maxDepth: 6)

    var bestText: String?
    var bestRect: CGRect?

    for el in candidates {
      if bestText == nil {
        bestText = readSelectedText(from: el)
      }
      if bestRect == nil {
        bestRect = readSelectedBounds(from: el)
      }
      if bestText != nil, bestRect != nil { break }
    }

    return (bestText, bestRect)
  }

  private static func readSelectedText(from element: AXUIElement) -> String? {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
    guard err == .success else { return nil }
    return value as? String
  }

  private static func readSelectedBounds(from element: AXUIElement) -> CGRect? {
    var rangeValue: CFTypeRef?
    let rangeErr = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue)
    guard rangeErr == .success, let axRange = rangeValue else { return nil }
    guard CFGetTypeID(axRange) == AXValueGetTypeID() else { return nil }
    let v = (axRange as! AXValue)
    guard AXValueGetType(v) == .cfRange else { return nil }

    var boundsValue: CFTypeRef?
    let paramErr = AXUIElementCopyParameterizedAttributeValue(
      element,
      kAXBoundsForRangeParameterizedAttribute as CFString,
      v,
      &boundsValue
    )
    guard paramErr == .success, let boundsValue else { return nil }
    guard CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
    let b = (boundsValue as! AXValue)
    guard AXValueGetType(b) == .cgRect else { return nil }

    var cgRect = CGRect.zero
    guard AXValueGetValue(b, .cgRect, &cgRect) else { return nil }
    if cgRect.isEmpty { return nil }
    return cgRect
  }

  private static func walkUpParents(from element: AXUIElement, maxDepth: Int) -> [AXUIElement] {
    var out: [AXUIElement] = [element]
    var current: AXUIElement? = element
    var depth = 0
    while depth < maxDepth, let c = current {
      var parentValue: CFTypeRef?
      let err = AXUIElementCopyAttributeValue(c, kAXParentAttribute as CFString, &parentValue)
      guard err == .success, let pv = parentValue else { break }
      guard CFGetTypeID(pv) == AXUIElementGetTypeID() else { break }
      let parent = pv as! AXUIElement
      out.append(parent)
      current = parent
      depth += 1
    }
    return out
  }
}

@MainActor
enum SelectionCapture {
  static func capture() async -> CapturedSelection {
    let trusted = AXSelectionReader.ensureAccessibilityPermission(prompt: false)
    var rect: CGRect? = nil
    if trusted {
      let (text, axRect) = AXSelectionReader.readSelectedTextAndBounds()
      rect = axRect

      let axText = (text ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
      if !axText.isEmpty {
        return CapturedSelection(text: axText, anchor: rect.map { .rect($0) } ?? .mouse, source: "accessibility")
      }
    }

    if let fallback = await PasteboardFallback.copySelectionViaCmdCAndReadPasteboardAsync() {
      let fb = fallback.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
      if !fb.isEmpty {
        return CapturedSelection(text: fb, anchor: rect.map { .rect($0) } ?? .mouse, source: "pasteboard")
      }
    }

    return CapturedSelection(text: "", anchor: .mouse, source: "none")
  }
}

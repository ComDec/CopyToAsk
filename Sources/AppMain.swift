import Cocoa

@main
final class AppMain: NSObject {
  @MainActor
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menubar style; no Dock icon
    // NSApplication.delegate is not a strong reference; ensure the delegate stays alive
    // even under -O (the optimizer can shorten local lifetimes).
    withExtendedLifetime(delegate) {
      app.run()
    }
  }
}

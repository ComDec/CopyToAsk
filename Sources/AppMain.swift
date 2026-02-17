import Cocoa

@main
final class AppMain: NSObject {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menubar style; no Dock icon
    app.run()
  }
}

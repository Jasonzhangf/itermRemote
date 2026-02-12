import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Headless mode: keep the daemon running but do not show a visible window or
    // steal focus from the user.
    // Trigger with: ITERMREMOTE_HEADLESS=1
    if ProcessInfo.processInfo.environment["ITERMREMOTE_HEADLESS"] == "1" {
      self.alphaValue = 0.0
      self.ignoresMouseEvents = true
      self.level = .floating
      self.collectionBehavior = [.canJoinAllSpaces, .stationary]
      self.isReleasedWhenClosed = false
      self.orderOut(nil)
      NSApp.setActivationPolicy(.prohibited)
    }

    super.awakeFromNib()
  }
}

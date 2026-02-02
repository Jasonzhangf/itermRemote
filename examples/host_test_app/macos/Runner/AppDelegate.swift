import Cocoa
import FlutterMacOS

import Foundation

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "itermRemote/window_list",
      binaryMessenger: controller.engine.binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "listWindows":
        result(Self.listWindows())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.applicationDidFinishLaunching(notification)
  }

  private static func listWindows() -> [[String: Any]] {
    guard let windowInfoList = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly],
      kCGNullWindowID
    ) as? [[String: Any]] else {
      return []
    }

    var out: [[String: Any]] = []
    for info in windowInfoList {
      guard let owner = info[kCGWindowOwnerName as String] as? String else {
        continue
      }
      guard let bounds = info[kCGWindowBounds as String] as? [String: Any] else {
        continue
      }
      let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
      if layer != 0 {
        continue
      }
      let windowNumber = (info[kCGWindowNumber as String] as? Int) ?? 0
      out.append([
        "ownerName": owner,
        "windowNumber": windowNumber,
        "bounds": bounds,
      ])
    }
    return out
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

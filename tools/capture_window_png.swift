import Cocoa
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Usage:
//   swiftc tools/capture_window_png.swift -o build/capture_window_png
//   build/capture_window_png --windowNumber 123 --out /tmp/out.png
//   build/capture_window_png --titleContains iTerm2 --out /tmp/out.png

struct Args {
  var windowNumber: Int?
  var titleContains: String?
  var outPath: String = "/tmp/window.png"
  var listOnly: Bool = false
}

func parseArgs() -> Args {
  var a = Args()
  var i = 1
  let argv = CommandLine.arguments
  while i < argv.count {
    let s = argv[i]
    switch s {
    case "--windowNumber":
      i += 1
      if i < argv.count { a.windowNumber = Int(argv[i]) }
    case "--titleContains":
      i += 1
      if i < argv.count { a.titleContains = argv[i] }
    case "--out":
      i += 1
      if i < argv.count { a.outPath = argv[i] }
    case "--list":
      a.listOnly = true
    default:
      break
    }
    i += 1
  }
  return a
}

func listWindows() -> [[String: Any]] {
  let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
  guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    return []
  }
  return infoList
}

func pickWindowId(infoList: [[String: Any]], args: Args) -> CGWindowID? {
  if let n = args.windowNumber {
    for w in infoList {
      if let num = w[kCGWindowNumber as String] as? Int, num == n {
        return CGWindowID(num)
      }
    }
  }
  if let needle = args.titleContains?.lowercased(), !needle.isEmpty {
    for w in infoList {
      let name = (w[kCGWindowName as String] as? String ?? "").lowercased()
      let owner = (w[kCGWindowOwnerName as String] as? String ?? "").lowercased()
      if name.contains(needle) || owner.contains(needle) {
        if let num = w[kCGWindowNumber as String] as? Int {
          return CGWindowID(num)
        }
      }
    }
  }
  return nil
}

func savePNG(image: CGImage, to path: String) -> Bool {
  let url = URL(fileURLWithPath: path)
  guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    return false
  }
  CGImageDestinationAddImage(dest, image, nil)
  return CGImageDestinationFinalize(dest)
}

let args = parseArgs()
let infoList = listWindows()

if args.listOnly {
  // Print a small subset for human scanning.
  for w in infoList.prefix(50) {
    let num = w[kCGWindowNumber as String] as? Int ?? -1
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let name = w[kCGWindowName as String] as? String ?? ""
    print("\(num)\t\(owner)\t\(name)")
  }
  exit(0)
}

guard let wid = pickWindowId(infoList: infoList, args: args) else {
  fputs("Failed to resolve window id. Use --list to inspect candidates.\n", stderr)
  exit(2)
}

let image = CGWindowListCreateImage(
  .null,
  [.optionIncludingWindow],
  wid,
  [.boundsIgnoreFraming, .bestResolution]
)

guard let cg = image else {
  fputs("Failed to capture window image (check Screen Recording permission).\n", stderr)
  exit(3)
}

let ok = savePNG(image: cg, to: args.outPath)
if !ok {
  fputs("Failed to save PNG to \(args.outPath)\n", stderr)
  exit(4)
}

print("Saved: \(args.outPath)")

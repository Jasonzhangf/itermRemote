import Foundation
import ScreenCaptureKit
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import CoreMedia

// Build:
//   xcrun swiftc -O -parse-as-library tools/sck_capture.swift -o build/sck_capture \
//     -framework ScreenCaptureKit -framework CoreMedia -framework CoreVideo -framework CoreImage -framework Foundation
//
// Usage:
//   build/sck_capture list
//   build/sck_capture capture --titleContains "iTerm2" --out /tmp/iterm.png

struct Args {
  var cmd: String = ""
  var titleContains: String = ""
  var outPath: String = "/tmp/capture.png"
}

func parseArgs() -> Args {
  var a = Args()
  let argv = CommandLine.arguments
  if argv.count >= 2 {
    a.cmd = argv[1]
  }
  var i = 2
  while i < argv.count {
    let s = argv[i]
    switch s {
    case "--titleContains":
      i += 1
      if i < argv.count { a.titleContains = argv[i] }
    case "--out":
      i += 1
      if i < argv.count { a.outPath = argv[i] }
    default:
      break
    }
    i += 1
  }
  return a
}

func savePNG(ciImage: CIImage, to path: String) throws {
  let url = URL(fileURLWithPath: path)
  let ctx = CIContext(options: nil)
  guard let cg = ctx.createCGImage(ciImage, from: ciImage.extent) else {
    throw NSError(domain: "sck_capture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGImage"])
  }
  guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    throw NSError(domain: "sck_capture", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create destination"])
  }
  CGImageDestinationAddImage(dest, cg, nil)
  if !CGImageDestinationFinalize(dest) {
    throw NSError(domain: "sck_capture", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to finalize PNG"])
  }
}

final class OneFrameOutput: NSObject, SCStreamOutput {
  private let done: (CIImage?) -> Void
  private var fired = false

  init(done: @escaping (CIImage?) -> Void) {
    self.done = done
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
    guard outputType == .screen else { return }
    if fired { return }
    fired = true
    guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      done(nil)
      return
    }
    done(CIImage(cvPixelBuffer: pb))
  }
}

func run() async -> Int32 {
  let args = parseArgs()

  if args.cmd == "list" {
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
      for w in content.windows {
        let title = w.title ?? ""
        let app = w.owningApplication?.applicationName ?? ""
        print("\(w.windowID)\t\(app)\t\(title)")
      }
      return 0
    } catch {
      fputs("list failed: \(error)\n", stderr)
      return 2
    }
  }

  if args.cmd == "capture" {
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
      let needle = args.titleContains.lowercased()
      let target = content.windows.first { w in
        let title = (w.title ?? "").lowercased()
        let app = (w.owningApplication?.applicationName ?? "").lowercased()
        if needle.isEmpty { return false }
        return title.contains(needle) || app.contains(needle)
      }
      guard let win = target else {
        fputs("capture failed: no window matched --titleContains\n", stderr)
        return 3
      }

      let filter = SCContentFilter(desktopIndependentWindow: win)
      let cfg = SCStreamConfiguration()
      cfg.width = max(1, Int(win.frame.width))
      cfg.height = max(1, Int(win.frame.height))
      cfg.pixelFormat = kCVPixelFormatType_32BGRA
      cfg.showsCursor = false
      cfg.capturesAudio = false
      cfg.minimumFrameInterval = CMTime(value: 1, timescale: 2)

      let q = DispatchQueue(label: "sck_capture")
      let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)

      let img: CIImage? = await withCheckedContinuation { cont in
        let output = OneFrameOutput { img in
          cont.resume(returning: img)
        }
        do {
          try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: q)
          Task {
            do {
              try await stream.startCapture()
            } catch {
              cont.resume(returning: nil)
            }
          }
        } catch {
          cont.resume(returning: nil)
        }
      }

      try? await stream.stopCapture()

      guard let ci = img else {
        fputs("capture failed: no frame captured (permission?)\n", stderr)
        return 4
      }

      let outUrl = URL(fileURLWithPath: args.outPath)
      try FileManager.default.createDirectory(at: outUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
      try savePNG(ciImage: ci, to: args.outPath)
      print("Saved: \(args.outPath)")
      return 0
    } catch {
      fputs("capture failed: \(error)\n", stderr)
      return 5
    }
  }

  fputs("Usage: sck_capture list | capture --titleContains <needle> --out <path>\n", stderr)
  return 1
}

@main
struct Main {
  static func main() async {
    let rc = await run()
    exit(rc)
  }
}

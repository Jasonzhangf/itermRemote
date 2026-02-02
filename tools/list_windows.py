#!/usr/bin/env python3
import json
import subprocess
import sys

swift_code = '''
import Cocoa
import CoreGraphics
import Foundation

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    print("[]")
    exit(0)
}
var result: [[String: Any]] = []
for w in infoList.prefix(200):
    let num = w[kCGWindowNumber as String] as? Int ?? -1
    let owner = w[kCGWindowOwnerName as String] as? String ?? ""
    let name = w[kCGWindowName as String] as? String ?? ""
    let layer = w[kCGWindowLayer as String] as? Int ?? 0
    let bounds = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    # Only include top-level windows (layer 0)
    if layer == 0 and (owner.lowercased().contains("iterm") or owner.lowercased().contains("flutter") or owner.lowercased().contains("host")):
        result.append([
            "windowNumber": num,
            "owner": owner,
            "name": name,
            "bounds": bounds
        ])
let data = try JSONSerialization.data(withJSONObject: result)
print(String(data: data, encoding: .utf8) ?? "[]")
'''

# Compile and run
proc = subprocess.run(["swiftc", "-", "-o", "/tmp/list_windows"], input=swift_code.encode(), capture_output=True)
if proc.returncode != 0:
    print("Compilation failed:", proc.stderr.decode(), file=sys.stderr)
    sys.exit(1)

proc = subprocess.run(["/tmp/list_windows"], capture_output=True, text=True)
try:
    windows = json.loads(proc.stdout)
    for w in windows:
        print(f"{w['windowNumber']}\t{w['owner']}\t{w['name']}\t{w['bounds']}")
except Exception as e:
    print("Failed to parse output:", e, file=sys.stderr)
    print("stdout:", proc.stdout[:500], file=sys.stderr)

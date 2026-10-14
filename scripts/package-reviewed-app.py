#!/usr/bin/env python3
"""Package a verified ad-hoc developer build. This does not confer Apple trust or notarization."""
from __future__ import annotations
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time


def run(*args: str, capture: bool = False) -> str:
    result = subprocess.run(args, check=True, text=True, stdout=subprocess.PIPE if capture else None,
                            timeout=120)
    return result.stdout.strip() if capture else ""


def main() -> None:
    if sys.platform != "darwin" or len(sys.argv) != 2:
        raise SystemExit("Usage on macOS: python3 scripts/package-reviewed-app.py path/to/DiskOdds.app")
    source = Path(sys.argv[1]).resolve(strict=True)
    info = plistlib.loads((source / "Contents/Info.plist").read_bytes())
    if source.suffix != ".app" or info.get("CFBundleIdentifier") != "com.kamatbot.DiskOdds":
        raise SystemExit("Refusing to sign an unexpected bundle")
    output = Path.cwd()
    archive = output / "DiskOdds-macOS-arm64-dev.zip"
    macho_magic = {bytes.fromhex(h) for h in ("feedface", "cefaedfe", "feedfacf", "cffaedfe", "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}
    with tempfile.TemporaryDirectory(prefix="diskodds-package-") as temp:
        app = Path(temp) / "staging/DiskOdds.app"
        app.parent.mkdir()
        run("/usr/bin/ditto", str(source), str(app))
        bundles: list[Path] = []
        binaries: list[Path] = []
        for directory, directories, files in os.walk(app, followlinks=False):
            directories[:] = [d for d in directories if not (Path(directory) / d).is_symlink()]
            current = Path(directory)
            if current != app and current.suffix in {".app", ".framework", ".xpc", ".appex"}:
                bundles.append(current)
            for name in files:
                file = current / name
                if file.is_symlink():
                    continue
                with file.open("rb") as handle:
                    if handle.read(4) in macho_magic:
                        binaries.append(file)
        if not binaries:
            raise RuntimeError("No Mach-O executables found")
        # Sign code inside out; --deep is for verification, not signing.
        for path in sorted(binaries, key=lambda p: len(p.parts), reverse=True):
            run("/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(path))
        for path in sorted(bundles, key=lambda p: len(p.parts), reverse=True) + [app]:
            run("/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", str(path))
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app))
        run("/usr/bin/codesign", "--display", "--verbose=4", str(app))
        executable = info["CFBundleExecutable"]
        architectures = run("/usr/bin/lipo", "-archs", str(app / "Contents/MacOS" / executable), capture=True)
        if architectures != "arm64":
            raise RuntimeError(f"Unexpected architectures: {architectures}")
        run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive))
        unpacked = Path(temp) / "round-trip"
        unpacked.mkdir()
        run("/usr/bin/ditto", "-x", "-k", str(archive), str(unpacked))
        verified = unpacked / "DiskOdds.app"
        run("/usr/bin/codesign", "--verify", "--deep", "--strict", "--verbose=2", str(verified))
        metadata = {"commit": run("git", "rev-parse", "HEAD", capture=True),
                    "tree": run("git", "rev-parse", "HEAD^{tree}", capture=True),
                    "bundleIdentifier": info["CFBundleIdentifier"], "version": info.get("CFBundleShortVersionString"),
                    "architecture": architectures, "configuration": "Release", "signature": "ad-hoc",
                    "developerID": False, "notarized": False, "zipRoundTripSignatureVerified": True}
        (output / "build-metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
        # Only synthetic demo mode; never initiate real scans or cleanup in CI.
        with (output / "smoke-launch.log").open("w") as log:
            process = subprocess.Popen([str(verified / "Contents/MacOS" / executable), "--diskodds-demo"],
                                       stdout=log, stderr=subprocess.STDOUT)
            try:
                time.sleep(8)
                if process.poll() is not None:
                    raise RuntimeError(f"Packaged app exited during launch: {process.returncode}")
                query = '''import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
let candidates = windows.filter { w in
    guard w[kCGWindowOwnerPID as String] as? Int == pid,
          w[kCGWindowLayer as String] as? Int == 0,
          let b = w[kCGWindowBounds as String] as? [String: Double] else { return false }
    return b["Width", default: 0] >= 1100 && b["Height", default: 0] >= 600
}.sorted { a, b in
    let x = a[kCGWindowBounds as String] as! [String: Double]
    let y = b[kCGWindowBounds as String] as! [String: Double]
    return x["Width", default: 0] * x["Height", default: 0] > y["Width", default: 0] * y["Height", default: 0]
}
guard let window = candidates.first else { exit(2) }
let data = try JSONSerialization.data(withJSONObject: window, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
'''
                query_file = Path(temp) / "window.swift"
                query_file.write_text(query)
                window = json.loads(run("/usr/bin/swift", str(query_file), str(process.pid), capture=True))
                if process.poll() is not None:
                    raise RuntimeError("Packaged app exited before window validation")
                result = {"launched": True, "demoMode": True, "window": window, "screenshotCaptured": False}
                try:
                    run("/usr/sbin/screencapture", "-x", "-o", "-l", str(window["kCGWindowNumber"]),
                        str(output / "diskodds-preview.png"))
                    result["screenshotCaptured"] = True
                except subprocess.CalledProcessError as error:
                    result["screenshotError"] = str(error)
                (output / "smoke-result.json").write_text(json.dumps(result, indent=2) + "\n")
            finally:
                if process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=10)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (output / "SHA256SUMS.txt").write_text(f"{digest}  {archive.name}\n")
    print("Verified developer build, ZIP round trip, and synthetic demo launch. NOT notarized.")


if __name__ == "__main__":
    main()

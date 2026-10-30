#!/usr/bin/env python3
"""Validate the icon registered in an actual packaged macOS application."""

from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile


def main():
    app = Path(sys.argv[1]).resolve(strict=True)
    repo = Path(__file__).resolve().parent.parent
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    assert info.get("CFBundleIconFile") == "Tidy.icns", "App does not register Tidy.icns"
    icon = app / "Contents/Resources/Tidy.icns"
    assert icon.is_file() and not icon.is_symlink(), "Registered icon is missing or linked"
    assert icon.read_bytes() == (repo / "Packaging/Icons/Tidy.icns").read_bytes(), "Packaged icon is stale"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    with tempfile.TemporaryDirectory(prefix="tidy-icon-check-") as temporary:
        iconset = Path(temporary) / "Tidy.iconset"
        subprocess.run(["iconutil", "--convert", "iconset", "--output", str(iconset), str(icon)], check=True)
        for points in [16, 32, 128, 256, 512]:
            for scale, suffix in [(1, ""), (2, "@2x")]:
                image = (iconset / f"icon_{points}x{points}{suffix}.png").read_bytes()
                assert image[:8] == b"\x89PNG\r\n\x1a\n"
                assert struct.unpack(">II", image[16:24]) == (points * scale, points * scale), "Incorrect icon representation"
    print("PASS: registered current raccoon icon, all standard/Retina sizes, and packaged app signature.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Check the packaging CLI and mounted artifact without installing or launching Tidy."""

import hashlib
import copy
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import sys
import tempfile
import zipfile


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    repo = Path(__file__).resolve().parent.parent
    archive = Path(sys.argv[1]).resolve(strict=True)
    mode = sys.argv[2] if len(sys.argv) == 3 else "--unqualified"
    assert mode in {"--unqualified", "--experimental-beta"}
    beta = mode == "--experimental-beta"
    flavor = "experimental-beta" if beta else "unqualified"
    payload_name = "Tidy-Experimental-Beta" if beta else "Tidy-Unqualified-Development"
    app_name = "Tidy Beta.app" if beta else "Tidy Unqualified Development.app"
    before = sha256(archive)
    scratch = Path(tempfile.mkdtemp(
        prefix="tidy-dmg-test-",
        dir="/private/var/folders/jc/5pmbdfgj29bgb2ftjl_t4jph0000gn/T/opencode"))
    refused = subprocess.run(
        ["bash", str(repo / "scripts/package-dmg.sh"), "--release", str(archive)],
        cwd=repo, capture_output=True, text=True, timeout=30)
    assert refused.returncode == 2, "Candidate packaging must not offer a release-gate override"
    for name in ["../escape.txt", "/absolute-escape.txt"]:
        bad = scratch / "unsafe.zip"
        with zipfile.ZipFile(bad, "w") as source:
            source.writestr(name, "Unsafe fixture")
        rejected = subprocess.run(
            ["bash", str(repo / "scripts/package-dmg.sh"), mode, str(bad)],
            cwd=repo, capture_output=True, text=True, timeout=30)
        assert rejected.returncode != 0 and "Unsafe or unexpected archive path" in rejected.stderr
        assert not (scratch / "escape.txt").exists()
    with zipfile.ZipFile(bad, "w") as source:
        link = zipfile.ZipInfo(payload_name + "/escape")
        link.create_system = 3
        link.external_attr = (stat.S_IFLNK | 0o777) << 16
        source.writestr(link, "/Applications")
    rejected = subprocess.run(
        ["bash", str(repo / "scripts/package-dmg.sh"), mode, str(bad)],
        cwd=repo, capture_output=True, text=True, timeout=30)
    assert rejected.returncode != 0 and "Escaping archive symlink" in rejected.stderr
    other_mode = "--unqualified" if beta else "--experimental-beta"
    rejected = subprocess.run(
        ["bash", str(repo / "scripts/package-dmg.sh"), other_mode, str(archive)],
        cwd=repo, capture_output=True, text=True, timeout=30)
    assert rejected.returncode != 0, "Packaging modes must not relabel each other's archives"
    if not beta:
        # Renaming the outer app directory preserves its signature. Forging unsigned
        # beta notes/provenance must still fail the signed bundle identity/source check.
        forged = scratch / "relabeled-beta.zip"
        with zipfile.ZipFile(archive) as source, zipfile.ZipFile(forged, "w") as target:
            build = source.read(payload_name + "/BUILD.txt").decode()
            for entry in source.infolist():
                if entry.filename == payload_name + "/BUILD.txt":
                    continue
                renamed = copy.copy(entry)
                renamed.filename = entry.filename.replace(payload_name, "Tidy-Experimental-Beta", 1).replace(
                    "Tidy Unqualified Development.app", "Tidy Beta.app", 1)
                target.writestr(renamed, source.read(entry))
            target.writestr("Tidy-Experimental-Beta/BUILD.txt", build + "\nPackaging flavor: experimental-beta\n")
            target.writestr("Tidy-Experimental-Beta/BETA-NOTES.md", "Experimental beta fixture\n")
            target.writestr("Tidy-Experimental-Beta/LICENSE.txt", (repo / "LICENSE").read_bytes())
        rejected = subprocess.run(
            ["bash", str(repo / "scripts/package-dmg.sh"), "--experimental-beta", str(forged)],
            cwd=repo, capture_output=True, text=True, timeout=60)
        assert rejected.returncode != 0 and "signed experimental-beta metadata/license" in rejected.stderr, rejected.stdout + rejected.stderr
    result = subprocess.run(
        ["bash", str(repo / "scripts/package-dmg.sh"), mode, str(archive)],
        cwd=repo, capture_output=True, text=True, timeout=300)
    assert result.returncode == 0, result.stdout + result.stderr
    prefix = f"Local {flavor} DMG: "
    output = next(line.removeprefix(prefix)
                  for line in result.stdout.splitlines() if line.startswith(prefix))
    directory = Path(output).resolve(strict=True)
    assert directory.is_relative_to(repo / ".build/direct-download")
    manifest = json.loads((directory / "DMG_BUILD.json").read_text())
    assert manifest["sourceArchiveSHA256"] == before
    assert manifest["publicReleaseApproved"] is False
    assert manifest["packagingFlavor"] == flavor
    image = directory / manifest["imageName"]
    assert image.suffix == ".dmg" and sha256(archive) == before
    image_info = plistlib.loads(subprocess.check_output(["hdiutil", "imageinfo", "-plist", str(image)]))
    assert image_info["Format"] == "UDZO"
    assert image_info["Properties"]["Compressed"] is True
    assert image_info["Properties"]["Encrypted"] is False
    subprocess.run(["hdiutil", "verify", str(image)], check=True, capture_output=True)
    subprocess.run(["codesign", "--verify", "--strict", str(image)], check=True, capture_output=True)

    mount = scratch / "mounted"
    mount.mkdir()
    attached = False
    try:
        subprocess.run(
            ["hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", str(mount), str(image)],
            check=True, capture_output=True, timeout=60)
        attached = True
        assert (mount / "Applications").is_symlink()
        assert os.readlink(mount / "Applications") == "/Applications"
        assert "no hardware is formally qualified" in (mount / "README.txt").read_text()
        if beta:
            assert (mount / "LICENSE.txt").read_bytes() == (repo / "LICENSE").read_bytes()
            assert "experimental beta" in (mount / "BETA-NOTES.md").read_text().lower()
        app = mount / app_name
        if beta:
            provenance = json.loads((app / "Contents/Resources/Tidy-BUILD.json").read_text())
            assert provenance["applicationSource"] == manifest["applicationSource"]
            assert provenance["packagingFlavor"] == flavor
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)],
                       check=True, capture_output=True)
        prefix = payload_name + "/" + app_name + "/"
        expected = set()
        with zipfile.ZipFile(archive) as source:
            for entry in source.infolist():
                if not entry.filename.startswith(prefix) or entry.is_dir():
                    continue
                relative = entry.filename[len(prefix):]
                expected.add(relative)
                item = app / relative
                if stat.S_ISLNK(entry.external_attr >> 16):
                    assert item.is_symlink() and os.readlink(item).encode() == source.read(entry)
                else:
                    assert not item.is_symlink()
                    assert sha256(item) == hashlib.sha256(source.read(entry)).hexdigest(), relative
        actual = {str(item.relative_to(app)) for item in app.rglob("*")
                  if item.is_symlink() or item.is_file()}
        assert actual == expected, "Mounted application content changed during DMG packaging"
    finally:
        if attached:
            subprocess.run(["hdiutil", "detach", str(mount)], check=True, capture_output=True, timeout=60)

    print("PASS: unsafe archives/release override rejected; signed read-only DMG, Applications link, warnings, exact app contents and unchanged ZIP.")
    print("No app installed/launched, no notarization submission and no publication.")
    print("DMG evidence:", directory)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Opt-in SIGKILL qualification using owned APFS clones of approved local weights."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile


def hashes(directory):
    result = {}
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise RuntimeError("Model fixtures must not contain symbolic links")
        if not path.is_file():
            continue
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        result[str(path.relative_to(directory))] = digest.hexdigest()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--runs", type=int, choices=range(1, 6), default=3)
    args = parser.parse_args()
    project = Path(__file__).resolve().parent.parent
    source = args.source.resolve(strict=True)
    revision = "50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b"
    if source.name != revision or not source.is_dir():
        raise RuntimeError("Supply the already-approved local candidate directory")
    executable = project / ".build/TidyModelSmoke.app/Contents/MacOS/TidyModelSmoke"
    if not executable.is_file():
        raise RuntimeError("Run bash scripts/model-smoke.sh --package-only first")
    baseline = hashes(source)
    output = Path(tempfile.mkdtemp(prefix="model-lifecycle-", dir=project / ".build"))
    root = output / "Models"
    root.mkdir()
    alias = revision + "-qualification"
    canary = root / "unrelated-user-data.txt"
    canary.write_bytes(b"Preserve unrelated lifecycle fixture.\n")
    (root / ".tidy-lifecycle-fixture").write_text("owned same-artifact lifecycle fixture\n")
    bin_path = subprocess.run(
        ["swift", "build", "--show-bin-path"], cwd=project, check=True, capture_output=True, text=True
    ).stdout.strip()
    escaped = bin_path.replace("\\", "\\\\").replace('"', '\\"')
    policy = f'(version 1) (allow default) (deny network*) (deny file-read* (subpath "{escaped}"))'
    results = []

    def worker(checkpoint, label):
        env = dict(os.environ, NSUnbufferedIO="YES", TIDY_LIFECYCLE_ROOT=str(root),
                   TIDY_LIFECYCLE_CHECKPOINT=checkpoint)
        with (output / f"{label}.log").open("w") as log:
            process = subprocess.run(
                ["sandbox-exec", "-p", policy, str(executable), "--model-lifecycle-worker"],
                env=env, stdout=log, stderr=subprocess.STDOUT, timeout=90, cwd=project
            )
        return process.returncode, (output / f"{label}.log").read_text()

    try:
        for name in [revision, alias]:
            subprocess.run(["cp", "-cR", str(source), str(root / name)], check=True)
            for relative in baseline:
                if (source / relative).stat().st_ino == (root / name / relative).stat().st_ino:
                    raise RuntimeError("Qualification copy must not share file inodes")
        for run in range(1, args.runs + 1):
            for checkpoint in ["before-selection", "after-selection"]:
                (root / "active-revision").write_text(revision)
                code, log = worker(checkpoint, f"run-{run}-{checkpoint}")
                if code != -signal.SIGKILL or f"checkpoint={checkpoint}" not in log:
                    raise RuntimeError("Child did not reach the intended native-load SIGKILL checkpoint")
                expected = revision if checkpoint == "before-selection" else alias
                if (root / "active-revision").read_text() != expected:
                    raise RuntimeError("Selection did not match the checkpoint's durable outcome")
                code, log = worker("restore", f"run-{run}-{checkpoint}-restore")
                if code != 0 or "fresh readiness and inference; no transfer" not in log:
                    raise RuntimeError("Fresh process failed to reverify and infer from retained selection")
                for name in [revision, alias]:
                    if hashes(root / name) != baseline:
                        raise RuntimeError("An isolated model clone changed")
                if canary.read_bytes() != b"Preserve unrelated lifecycle fixture.\n":
                    raise RuntimeError("Unrelated fixture changed")
                results.append({"run": run, "checkpoint": checkpoint, "selected": expected,
                                "freshVerificationAndInference": "pass", "cloneHashes": "unchanged"})
                print(f"PASS run={run} {checkpoint}: SIGKILL, fresh verification/inference, hashes", flush=True)
        if hashes(source) != baseline:
            raise RuntimeError("Approved source weights changed")
    finally:
        # Only these two explicitly created clone directories are removed; retain
        # checkpoint logs, selection and unrelated controls for inspection.
        for name in [revision, alias]:
            clone = root / name
            if clone.is_dir():
                shutil.rmtree(clone)
        (output / "results.json").write_text(json.dumps({
            "observations": results, "sourceSHA256": baseline,
            "limit": "Same approved artifact under two fixture revision names; not two reviewed production revisions or pressure qualification"
        }, indent=2) + "\n")
        print(f"Evidence: {output}", flush=True)


if __name__ == "__main__":
    main()

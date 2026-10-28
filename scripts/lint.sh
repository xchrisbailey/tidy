#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift format lint --strict --recursive Package.swift Sources Tests
plutil -lint Packaging/Info.plist Packaging/Tidy.entitlements
bash -n scripts/build-app.sh scripts/lint.sh

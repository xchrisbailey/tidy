#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift format lint --strict --recursive Package.swift Sources Tests
plutil -lint Packaging/Info.plist Packaging/Tidy.entitlements Packaging/ModelSmoke.entitlements Packaging/InspectionService-Info.plist Packaging/InspectionSmoke.entitlements
bash -n scripts/*.sh

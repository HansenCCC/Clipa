#!/bin/zsh
set -euo pipefail

TESTS_DIR="${0:A:h}"
PROJECT_DIR="${TESTS_DIR:h}"
OUT="${TMPDIR:-/tmp}/clipa-panel-controller-harness-$$"
trap 'rm -f "$OUT"' EXIT

xcrun swiftc -swift-version 5 -parse-as-library \
  -framework AppKit -framework SwiftUI \
  "$TESTS_DIR/PanelControllerHarness.swift" \
  "$PROJECT_DIR/Clipa/Services/PanelController.swift" \
  -o "$OUT"
"$OUT"

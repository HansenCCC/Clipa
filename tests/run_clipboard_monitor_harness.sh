#!/bin/zsh
set -euo pipefail

TESTS_DIR="${0:A:h}"
PROJECT_DIR="${TESTS_DIR:h}"
OUT="${TMPDIR:-/tmp}/clipa-clipboard-monitor-harness-$$"
trap 'rm -f "$OUT"' EXIT

xcrun swiftc -swift-version 5 -parse-as-library \
  -framework AppKit -framework SwiftData -framework CryptoKit \
  "$TESTS_DIR/ClipboardMonitorHarness.swift" \
  "$PROJECT_DIR/Clipa/Services/ClipboardMonitor.swift" \
  -o "$OUT"
"$OUT"

#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --disable-sandbox --target PromptFoundryCore
VERIFY_BIN_DIR="$(swift build --disable-sandbox --show-bin-path)"
swiftc -parse-as-library -swift-version 5 -target arm64-apple-macos14.0 \
  -I "$VERIFY_BIN_DIR/Modules" \
  Sources/PromptFoundryApp/ViewModels/WorkspaceViewModel.swift \
  Sources/PromptFoundryApp/Support/DesktopPanels.swift \
  Sources/PromptFoundryApp/Support/CodexDesktopNavigator.swift \
  Tests/PromptFoundryV2Tests/WorkflowTests.swift \
  "$VERIFY_BIN_DIR"/PromptFoundryCore.build/*.swift.o \
  -o "$VERIFY_BIN_DIR/WorkflowVerification"
"$VERIFY_BIN_DIR/WorkflowVerification"

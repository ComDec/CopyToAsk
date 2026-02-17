#!/bin/zsh
set -euo pipefail

APP_NAME="CopyToAsk"
BUNDLE_ID="com.copytoask.CopyToAsk"

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

mkdir -p "$BUILD_DIR"
rm -rf "$APP_DIR"

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

SWIFT_SOURCES=(
  "$ROOT_DIR/Sources/AppMain.swift"
  "$ROOT_DIR/Sources/AppDelegate.swift"
  "$ROOT_DIR/Sources/AnswerLanguage.swift"
  "$ROOT_DIR/Sources/AppSettings.swift"
  "$ROOT_DIR/Sources/HotKeyManager.swift"
  "$ROOT_DIR/Sources/HotKeyRecorderPanelController.swift"
  "$ROOT_DIR/Sources/PromptStore.swift"
  "$ROOT_DIR/Sources/HistoryStore.swift"
  "$ROOT_DIR/Sources/AXSelectionReader.swift"
  "$ROOT_DIR/Sources/PasteboardFallback.swift"
  "$ROOT_DIR/Sources/ExplainPanelController.swift"
  "$ROOT_DIR/Sources/OpenAIClient.swift"
  "$ROOT_DIR/Sources/KeychainStore.swift"
  "$ROOT_DIR/Sources/SettingsWindowController.swift"
)

swiftc \
  -O -g \
  -target arm64-apple-macosx13.0 \
  -framework Cocoa \
  -framework ApplicationServices \
  -framework Carbon \
  -framework Security \
  "${SWIFT_SOURCES[@]}" \
  -o "$APP_DIR/Contents/MacOS/$APP_NAME"

sed \
  -e "s/\${APP_NAME}/$APP_NAME/g" \
  -e "s/\${BUNDLE_ID}/$BUNDLE_ID/g" \
  "$ROOT_DIR/Resources/Info.plist" \
  > "$APP_DIR/Contents/Info.plist"

chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# Ad-hoc sign if available (helps some system prompts).
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
fi

echo "Built: $APP_DIR"

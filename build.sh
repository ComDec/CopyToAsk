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
  "$ROOT_DIR/Sources/Localization.swift"
  "$ROOT_DIR/Sources/AppSettings.swift"
  "$ROOT_DIR/Sources/HotKeyManager.swift"
  "$ROOT_DIR/Sources/HotKeyRecorderPanelController.swift"
  "$ROOT_DIR/Sources/PromptStore.swift"
  "$ROOT_DIR/Sources/TraceLog.swift"
  "$ROOT_DIR/Sources/HistoryStore.swift"
  "$ROOT_DIR/Sources/ContextHighlightWindowController.swift"
  "$ROOT_DIR/Sources/ContextPanelController.swift"
  "$ROOT_DIR/Sources/AXSelectionReader.swift"
  "$ROOT_DIR/Sources/PasteboardFallback.swift"
  "$ROOT_DIR/Sources/ExplainPanelController.swift"
  "$ROOT_DIR/Sources/AskInputBar.swift"
  "$ROOT_DIR/Sources/ChatViews.swift"
  "$ROOT_DIR/Sources/OpenAIClient.swift"
  "$ROOT_DIR/Sources/KeychainStore.swift"
  "$ROOT_DIR/Sources/SettingsWindowController.swift"
)

swiftc \
  -O -g \
  -target "${COPYTOASK_TARGET_ARCH:-$(uname -m)}-apple-macosx${COPYTOASK_MACOS_MIN_VERSION:-13.0}" \
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

# Copy bundled resources (icons, etc.)
if [ -d "$ROOT_DIR/Resources" ]; then
  cp -R "$ROOT_DIR/Resources/"* "$APP_DIR/Contents/Resources/" 2>/dev/null || true
fi

chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# Codesign
#
# TCC permissions (Accessibility, etc.) are tied to code signature identity.
# Ad-hoc signing changes every build, causing you to re-authorize after rebuilds.
# Use a stable identity when available.
if command -v codesign >/dev/null 2>&1; then
  IDENTITY="${COPYTOASK_CODESIGN_IDENTITY:-}"

  if [ -z "$IDENTITY" ] && command -v security >/dev/null 2>&1; then
    # Prefer local dev identity if present.
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/CopyToAsk Local Dev/ {print $2; exit}')
  fi

  if [ -z "$IDENTITY" ] && command -v security >/dev/null 2>&1; then
    # Fall back to any Apple-provided development identity.
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')
  fi

  if [ -n "$IDENTITY" ]; then
    echo "Codesign: $IDENTITY"
    codesign --force --deep --sign "$IDENTITY" --timestamp=none "$APP_DIR"
  else
    echo "Codesign: ad-hoc (no identity found)"
    echo "Tip: run ./scripts/setup_local_codesign_identity.sh to create a stable local identity."
    codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true
  fi
fi

echo "Built: $APP_DIR"

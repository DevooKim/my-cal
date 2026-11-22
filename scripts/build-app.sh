#!/usr/bin/env bash
# MyCal.app 번들을 build/ 아래에 만든다.
# SIGN_IDENTITY를 지정하지 않으면 ad-hoc 서명한다. ad-hoc 서명은 빌드마다 서명이 바뀌어
# macOS가 다른 앱으로 인식하므로, 다시 빌드하면 캘린더 권한을 다시 허용해야 한다.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/MyCal.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MyCal" "$APP/Contents/MacOS/MyCal"
cp Support/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"

echo "built $APP"

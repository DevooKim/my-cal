#!/usr/bin/env bash
# 앱을 빌드하고 Applications 폴더 바로가기를 넣은 배포용 DMG를 만든다.
# 사용법: ./scripts/make-dmg.sh [출력 폴더]   (기본값: build/)
set -euo pipefail

cd "$(dirname "$0")/.."

OUT_DIR="${1:-build}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Support/Info.plist)"
DMG="$OUT_DIR/MyCal-$VERSION.dmg"

./scripts/build-app.sh

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R build/MyCal.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$OUT_DIR"
hdiutil create -volname "MyCal" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

echo "built $DMG"

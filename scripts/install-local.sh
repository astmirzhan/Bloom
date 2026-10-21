#!/bin/bash
# Builds Release, signs it ad hoc for this Mac only (no Developer ID, no
# notarization) and installs it to /Applications with the bloom command.
# For a personal build; `make release` makes the distributable one.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED="$HOME/Library/Caches/Converter/DerivedData"
CLI_BUILD="$HOME/Library/Caches/Converter/CLIRelease"
APP=/Applications/Bloom.app

set -o pipefail
xcodebuild -project Converter/Converter.xcodeproj -scheme Converter -configuration Release \
    -derivedDataPath "$DERIVED" build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
swift build -c release --arch arm64 --package-path Packages/ConverterCore --scratch-path "$CLI_BUILD" 2>&1 | tail -1
CLI="$(swift build -c release --arch arm64 --package-path Packages/ConverterCore --scratch-path "$CLI_BUILD" --show-bin-path)/bloom"

pkill -x Bloom || true
rm -rf "$APP"
ditto "$DERIVED/Build/Products/Release/Bloom.app" "$APP"
mkdir -p "$APP/Contents/Helpers"
cp "$CLI" "$APP/Contents/Helpers/bloom"

sign() { codesign --force --options runtime --sign - "$@"; }
# Inside out: nested code first, the app last.
sign --identifier io.github.astmirzhan.Bloom.cli "$APP/Contents/Helpers/bloom"
sign --entitlements Converter/QuickAction/QuickAction.entitlements "$APP/Contents/PlugIns/ConverterQuickAction.appex"
sign "$APP"
codesign --verify --deep --strict "$APP"

BIN="$(brew --prefix 2>/dev/null || echo /usr/local)/bin"
ln -sf "$APP/Contents/Helpers/bloom" "$BIN/bloom"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$APP"
open "$APP"
echo "Installed $("$APP/Contents/Helpers/bloom" --version) to $APP"

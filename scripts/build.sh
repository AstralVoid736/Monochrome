#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
MODE="${1:---native}"
if [[ "$MODE" != "--native" && "$MODE" != "--universal" ]]; then
  printf 'Usage: bash scripts/build.sh [--native|--universal]\n' >&2; exit 2
fi
APP="${MONOCHROME_APP_PATH:-dist/Monochrome.app}"
if [[ "$APP" != *.app ]]; then printf 'Output must end in .app\n' >&2; exit 2; fi
mkdir -p .build "$APP/Contents/MacOS"
SOURCES=(Sources/GrayscaleController.swift Sources/NativeGrayscaleBackend.swift Sources/SingleInstanceLock.swift Sources/HotKeyController.swift Sources/NativeHotKeyRegistrar.swift Sources/StatusBarController.swift Sources/MonochromeApp.swift)
compile() {
  xcrun swiftc -O -whole-module-optimization -warnings-as-errors -target "$1-apple-macos13.0" "${SOURCES[@]}" -framework AppKit -framework Carbon -o ".build/Monochrome-$1"
}
if [[ "$MODE" == "--universal" ]]; then
  compile arm64
  compile x86_64
  xcrun lipo -create .build/Monochrome-arm64 .build/Monochrome-x86_64 -output "$APP/Contents/MacOS/Monochrome"
else
  ARCH="$(uname -m)"
  compile "$ARCH"
  cp ".build/Monochrome-$ARCH" "$APP/Contents/MacOS/Monochrome"
fi
cp Resources/Info.plist "$APP/Contents/Info.plist"
BUNDLE_RESOURCES="$APP/Contents/Resources"
mkdir -p "$BUNDLE_RESOURCES/ru.lproj"
cp Resources/ru.lproj/Localizable.strings "$BUNDLE_RESOURCES/ru.lproj/"
xcrun swiftc -warnings-as-errors scripts/MakeIcon.swift -o .build/make-icon
.build/make-icon .build/Monochrome.iconset
iconutil -c icns .build/Monochrome.iconset -o "$BUNDLE_RESOURCES/Monochrome.icns"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict "$APP"
printf 'Built %s (%s; ad-hoc signed, not notarized)\n' "$APP" "$MODE"

#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Expected a numeric major.minor.patch app version, got: $VERSION" >&2
    exit 1
fi
if [[ -n "${RELEASE_TAG:-}" && "$RELEASE_TAG" != "v$VERSION" ]]; then
    echo "Release tag $RELEASE_TAG does not match app version v$VERSION in Resources/Info.plist." >&2
    exit 1
fi

./scripts/build.sh

APP="$PROJECT_ROOT/dist/Monitor.app"
ARCH="$(lipo -archs "$APP/Contents/MacOS/Monitor")"
case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "Unsupported app architecture: $ARCH" >&2; exit 1 ;;
esac
if [[ -n "${EXPECTED_ARCH:-}" && "$ARCH" != "$EXPECTED_ARCH" ]]; then
    echo "Expected $EXPECTED_ARCH, but built $ARCH." >&2
    exit 1
fi

OUTPUT="$PROJECT_ROOT/dist/release"
ARCHIVE="Monitor-$VERSION-macos-$ARCH.zip"
mkdir -p "$OUTPUT"
# Archive the bundle before artifact upload so executable bits and bundle metadata survive.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/$ARCHIVE"

# Verify the delivered bundle, not just the app in the build directory.
VERIFY_DIR="$(mktemp -d "$PROJECT_ROOT/.build/release-check.XXXXXX")"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$OUTPUT/$ARCHIVE" "$VERIFY_DIR"
test -x "$VERIFY_DIR/Monitor.app/Contents/MacOS/Monitor"
test -f "$VERIFY_DIR/Monitor.app/Contents/Resources/ChromeExtension/manifest.json"
codesign --verify --deep --strict "$VERIFY_DIR/Monitor.app"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$VERIFY_DIR/Monitor.app/Contents/Info.plist")" = "$VERSION"

cd "$OUTPUT"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
printf '\nPackaged: %s/%s\n' "$OUTPUT" "$ARCHIVE"

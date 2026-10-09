#!/usr/bin/env bash
#
# Build ankerctl.app: a native macOS wrapper around the ankerctl web interface.
#
#   macos/build-app.sh            build macos/dist/ankerctl.app, a .zip and a .dmg
#
# Environment variables:
#   PYTHON             Python 3.10+ interpreter to build the server with
#                      (default: first of python3.13/3.12/3.11/3.10/python3 found)
#   VERSION            Version string for Info.plist (default: from git describe)
#   CODESIGN_IDENTITY  Signing identity (default: "-" for ad-hoc signing)
#   SKIP_DMG=1         Do not create a disk image
#
# The app bundles a PyInstaller build of ankerctl, so it only runs on the CPU
# architecture of the machine (and Python) it was built with.

set -euo pipefail

MACOS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$MACOS_DIR/.." && pwd)"
BUILD_DIR="$MACOS_DIR/build"
DIST_DIR="$MACOS_DIR/dist"
APP="$DIST_DIR/ankerctl.app"
PYINSTALLER_VERSION="6.21.0"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

step() { printf '\n==> %s\n' "$*"; }

find_python() {
    if [[ -n "${PYTHON:-}" ]]; then
        echo "$PYTHON"
        return
    fi
    for candidate in python3.13 python3.12 python3.11 python3.10 python3; do
        if command -v "$candidate" >/dev/null &&
           "$candidate" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null; then
            command -v "$candidate"
            return
        fi
    done
    echo "error: Python 3.10 or newer is required (set PYTHON=/path/to/python3)" >&2
    exit 1
}

PYTHON_BIN="$(find_python)"
ARCH="$(uname -m)"
# Use the most recent vX.Y.Z tag; CFBundleShortVersionString must be numeric.
VERSION="${VERSION:-$(git -C "$ROOT_DIR" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)}"
VERSION="${VERSION#v}"
if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    # No release tag yet: fall back to the latest version in the changelog.
    VERSION="$(sed -n 's/^## \[\([0-9][0-9.]*\)\].*/\1/p' "$ROOT_DIR/CHANGELOG.md" | head -n 1)"
    VERSION="${VERSION:-0.0.0}"
fi
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"

step "Preparing Python build environment ($("$PYTHON_BIN" --version))"
VENV="$BUILD_DIR/venv"
if [[ ! -x "$VENV/bin/python" ]]; then
    "$PYTHON_BIN" -m venv "$VENV"
fi
"$VENV/bin/python" -m pip install --quiet --upgrade pip
"$VENV/bin/python" -m pip install --quiet -r "$ROOT_DIR/requirements.txt" "pyinstaller==$PYINSTALLER_VERSION"

step "Building ankerctl server with PyInstaller"
"$VENV/bin/python" -m PyInstaller \
    --clean --noconfirm --log-level WARN \
    --distpath "$BUILD_DIR/server" \
    --workpath "$BUILD_DIR/pyinstaller" \
    "$MACOS_DIR/ankerctl-server.spec"
"$BUILD_DIR/server/ankerctl/ankerctl" --help >/dev/null

step "Building Swift app"
swift build --package-path "$MACOS_DIR" --configuration release
SWIFT_BIN="$(swift build --package-path "$MACOS_DIR" --configuration release --show-bin-path)/AnkerCtl"

step "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SWIFT_BIN" "$APP/Contents/MacOS/AnkerCtl"
cp "$MACOS_DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cp -R "$BUILD_DIR/server/ankerctl" "$APP/Contents/Resources/ankerctl"
cp "$ROOT_DIR/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" \
    "$MACOS_DIR/Resources/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

step "Code signing (identity: $CODESIGN_IDENTITY)"
sign() {
    codesign "$@" 2>&1 | { grep -v "replacing existing signature" || true; }
    return "${PIPESTATUS[0]}"
}
SIGN_ARGS=(--force --timestamp=none --sign "$CODESIGN_IDENTITY")
if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
    SIGN_ARGS=(--force --timestamp --options runtime --sign "$CODESIGN_IDENTITY")
fi
# Sign nested code inside-out: Python extension modules and libraries first,
# then the server executable, then the app itself.
while IFS= read -r -d '' file; do
    if file -b "$file" | grep -q "Mach-O"; then
        sign "${SIGN_ARGS[@]}" "$file"
    fi
done < <(find "$APP/Contents/Resources/ankerctl/_internal" -type f -print0)
sign "${SIGN_ARGS[@]}" --entitlements "$MACOS_DIR/Resources/server.entitlements" \
    "$APP/Contents/Resources/ankerctl/ankerctl"
sign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict --deep "$APP"

step "Packaging"
ZIP="$DIST_DIR/ankerctl-macos-app-$ARCH.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "$ZIP"

if [[ "${SKIP_DMG:-}" != "1" ]]; then
    DMG="$DIST_DIR/ankerctl-macos-app-$ARCH.dmg"
    STAGING="$BUILD_DIR/dmg"
    rm -rf "$STAGING" "$DMG"
    mkdir -p "$STAGING"
    cp -R "$APP" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    # hdiutil occasionally fails with "Resource busy" on CI runners; retry.
    for attempt in 1 2 3; do
        if hdiutil create -quiet -volname "ankerctl" -srcfolder "$STAGING" -fs HFS+ -format UDZO "$DMG"; then
            break
        elif [[ $attempt == 3 ]]; then
            exit 1
        fi
        sleep 5
    done
    rm -rf "$STAGING"
    echo "$DMG"
fi

step "Done: $APP ($VERSION, $ARCH)"

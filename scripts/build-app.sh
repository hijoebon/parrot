#!/usr/bin/env bash
# Build Parrot.app — a menu-bar agent bundle from the SPM executable.
# Requires full Xcode (for AppKit/SwiftUI/Vision). Run: bash scripts/build-app.sh
set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG" --product Parrot --jobs "${PARROT_BUILD_JOBS:-4}"

BIN="$(swift build -c "$CONFIG" --product Parrot --show-bin-path)/Parrot"
APP="$ROOT/build/Parrot.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
cp "$BIN" "$MACOS/Parrot"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$RES/AppIcon.icns"
fi
if [[ -f "$ROOT/Resources/MenuBarIconTemplate.png" ]]; then
    cp "$ROOT/Resources/MenuBarIconTemplate.png" "$RES/MenuBarIconTemplate.png"
fi
while IFS= read -r -d '' lproj; do
    cp -R "$lproj" "$RES/"
done < <(find "$ROOT/Resources" -maxdepth 1 -type d -name "*.lproj" -print0)

BUNDLE_ID="${PARROT_BUNDLE_ID:-com.parrot.app}"
DISPLAY_NAME="${PARROT_DISPLAY_NAME:-Parrot}"
URL_SCHEME="${PARROT_URL_SCHEME:-parrot}"
PLIST="$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $DISPLAY_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $DISPLAY_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLName $BUNDLE_ID.url" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 $URL_SCHEME" "$PLIST"
echo "  bundle: $BUNDLE_ID, scheme: $URL_SCHEME"

# Pin a signing identity so macOS can recognize the app across local builds.
# In development mode, signing failure must not produce an ad-hoc bundle.
if [[ "${PARROT_LOCAL_DEV_SIGN:-0}" == "1" ]]; then
    identity_file="$ROOT/build/local-dev-signing-identity"
    SIGN_IDENTITY="${PARROT_SIGN_IDENTITY:-}"
    if [[ -z "$SIGN_IDENTITY" && -s "$identity_file" ]]; then
        IFS= read -r SIGN_IDENTITY < "$identity_file"
    fi
    if [[ -z "$SIGN_IDENTITY" ]]; then
        SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { count++; identity=$2 } END { if (count == 1) print identity }')"
    fi
    if [[ -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ]]; then
        echo "Local signing needs one valid Apple Development identity. Set PARROT_SIGN_IDENTITY to select an installed signing identity." >&2
        exit 1
    fi
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
    codesign --verify --deep --strict "$APP"
    printf '%s\n' "$SIGN_IDENTITY" > "$identity_file"
    echo "  signed for local development with a pinned identity"
else
    SIGN_IDENTITY="${PARROT_SIGN_IDENTITY:-Parrot Dev}"
    if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
        codesign --force --deep --sign "$SIGN_IDENTITY" "$APP" >/dev/null 2>&1 \
            && echo "  signed with: $SIGN_IDENTITY (TCC grants persist across rebuilds)" \
            || { echo "  (signing with '$SIGN_IDENTITY' failed, falling back to ad-hoc)"; codesign --force --deep --sign - "$APP" >/dev/null 2>&1; }
    else
        echo "  ('$SIGN_IDENTITY' cert not found, using ad-hoc — Accessibility grant resets each rebuild)"
        codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"
    fi
fi

echo "==> done: $APP"
echo "    Launch: open \"$APP\"  (grant Accessibility + Screen Recording on first use)"

#!/bin/zsh
# Build Ambient.app. A bundle, not a bare binary — TCC will not reliably grant
# microphone or accessibility to a loose executable.
set -e
cd "$(dirname "$0")"

# Build outside the project tree: SwiftPM's build database is unreliable under
# a sandboxed path with a space in it.
SCRATCH="${TMPDIR:-/tmp}/ambient-build"
swift build -c release --scratch-path "$SCRATCH"
BIN="$SCRATCH/release"
if [[ ! -x "$BIN/Ambient" ]]; then echo "build failed: no binary at $BIN"; exit 1; fi

APP="Ambient.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Ambient" "$APP/Contents/MacOS/Ambient"
cp -R Resources/. "$APP/Contents/Resources/" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Ambient</string>
  <key>CFBundleDisplayName</key><string>Ambient</string>
  <key>CFBundleExecutable</key><string>Ambient</string>
  <key>CFBundleIdentifier</key><string>com.hansonmethod.ambient</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>Ambient listens on-device so you can talk instead of type.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Speech is transcribed on-device. Audio never leaves this machine.</string>
</dict>
</plist>
PLIST

# Sign with a stable identity if one is installed. Ad-hoc signatures change on
# every build, so macOS treats each build as a brand new app and silently drops
# Screen Recording and Accessibility — which is indistinguishable from the app
# being broken. See signing/README.
# Not `-v`: a self-signed certificate is reported untrusted (CSSMERR_TP_NOT_TRUSTED)
# and so never appears in the "valid identities" list — but codesign signs with it
# perfectly well. Trust governs verification, not signing.
IDENTITY=$(security find-identity -p codesigning 2>/dev/null | grep -o '"Ambient Dev"' | head -1 | tr -d '"')
if [[ -n "$IDENTITY" ]]; then
  codesign --force --sign "$IDENTITY" --timestamp=none "$APP" >/dev/null 2>&1 \
    && echo "signed with $IDENTITY (permissions persist)" \
    || codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1
else
  codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 || true
  echo "ad-hoc signed — permissions will reset on each rebuild (see signing/README)"
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true
# Let the signature settle before anything launches it: opening a bundle that
# was rewritten a moment ago can be evaluated against the old signature, and
# the app comes up with every permission missing.
sleep 1
echo "built $PWD/$APP"

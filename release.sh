#!/bin/zsh
# Cut a release friends can actually open.
#
# Without a Developer ID and notarization, macOS 26 refuses a downloaded app
# outright — not a scary dialog, a refusal. So this script tells you exactly
# which step you are missing rather than producing a build nobody can run.
set -e
cd "$(dirname "$0")"

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: ./release.sh 0.2   (the version friends will see)"; exit 1
fi

DEV_ID=$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')

echo "── building $VERSION"
# The version goes in before signing. Stamping it afterwards invalidated the
# signature, and macOS revoked microphone, speech and screen access every time.
./make.sh "$VERSION" >/dev/null

if [[ -z "$DEV_ID" ]]; then
  cat <<'MSG'

── STOP: no Developer ID certificate on this machine.

The build works locally, but anyone who downloads it will be blocked by
Gatekeeper. To distribute you need:

  1. Apple Developer Program — $99/year — developer.apple.com/programs
  2. Xcode or the developer portal → create a "Developer ID Application"
     certificate and install it in your login keychain
  3. An app-specific password for notarization:
       xcrun notarytool store-credentials ambient \
         --apple-id you@example.com --team-id TEAMID --password APP-SPECIFIC-PW

Then run this script again. Until then, hand friends the .zip below and tell
them to right-click → Open, then Privacy & Security → Open Anyway. It works,
but it is a bad first impression and it is the single biggest thing between
this and a real launch.

MSG
  SIGNED=no
else
  echo "── signing with $DEV_ID"
  codesign --force --deep --options runtime --timestamp \
    --sign "$DEV_ID" Ambient.app
  SIGNED=yes
fi

if ! codesign --verify --deep --strict Ambient.app 2>/dev/null; then
  echo "── STOP: signature does not verify; refusing to package"; exit 1
fi

echo "── packaging"
rm -rf dist && mkdir -p dist
ditto -c -k --keepParent Ambient.app "dist/Ambient-$VERSION.zip"

if [[ "$SIGNED" == "yes" ]]; then
  echo "── notarizing (a few minutes)"
  xcrun notarytool submit "dist/Ambient-$VERSION.zip" --keychain-profile ambient --wait
  xcrun stapler staple Ambient.app
  rm "dist/Ambient-$VERSION.zip"
  ditto -c -k --keepParent Ambient.app "dist/Ambient-$VERSION.zip"
  echo "── notarized and stapled"
fi

shasum -a 256 "dist/Ambient-$VERSION.zip" | tee "dist/Ambient-$VERSION.sha256"
echo
echo "dist/Ambient-$VERSION.zip is ready."
echo "Upload it as a GitHub release tagged v$VERSION, and the app's update"
echo "check will offer it to everyone running an older build."

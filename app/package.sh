#!/bin/bash
# Distribution build for personal use across your own Macs — universal binary + DMG.
#
# This is the ad-hoc-signed sibling of release.sh. release.sh needs a paid
# "Developer ID Application" certificate to notarize; without one, the app is
# signed ad-hoc, which is fine on your own machines but makes Gatekeeper block
# it after a download. See the note printed at the end for the one-time unblock.
set -e
cd "$(dirname "$0")"
APP="ClaudeCodexBattery.app"
NAME="ClaudeCodexBattery"
BID="com.dennykim.claude-codex-battery-app"
VERSION="$(cat ../VERSION)"
DMG="ClaudeCodexBattery-v${VERSION}-custom.dmg"
VOLNAME="Claude Codex Battery"
DEPLOY_TARGET="12.0"

echo "🔨 Compiling universal binary (arm64 + x86_64)…"
rm -rf "$APP" "$NAME" "$NAME-arm64" "$NAME-x86_64" "$DMG"
for ARCH in arm64 x86_64; do
  swiftc -O -target "${ARCH}-apple-macos${DEPLOY_TARGET}" *.swift \
    -o "$NAME-$ARCH" -framework Cocoa -framework ServiceManagement
done
lipo -create "$NAME-arm64" "$NAME-x86_64" -output "$NAME"
rm -f "$NAME-arm64" "$NAME-x86_64"
lipo -info "$NAME"

echo "📦 Assembling .app bundle…"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
mv "$NAME" "$APP/Contents/MacOS/$NAME"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BID</string>
  <key>CFBundleName</key><string>Claude Codex Battery</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>$DEPLOY_TARGET</string>
</dict>
</plist>
PLIST

echo "✍️  Ad-hoc signing…"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "💿 Creating DMG…"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
# A leftover mount of the same volume name would make hdiutil suffix the new one
while [ -d "/Volumes/$VOLNAME" ]; do hdiutil detach "/Volumes/$VOLNAME" >/dev/null 2>&1 || break; done
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo
echo "✅ $(pwd)/$DMG (v$VERSION, universal)"
echo
echo "On the other Mac: open the DMG, drag the app to Applications, then run once:"
echo "  xattr -dr com.apple.quarantine /Applications/ClaudeCodexBattery.app"
echo "Without that, Gatekeeper blocks the ad-hoc signature after a download."

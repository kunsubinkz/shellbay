#!/bin/bash
# Builds a release Shellbay.app and packages it into dist/Shellbay-<version>.dmg (drag-to-Applications layout)
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/bundle.sh release
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" dist/Shellbay.app/Contents/Info.plist)
STAGE=$(mktemp -d)
cp -R dist/Shellbay.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="dist/Shellbay-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Shellbay" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Created $DMG"

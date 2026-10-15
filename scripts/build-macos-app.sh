#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${1:-$HOME/Desktop/SkillDock.app}"
CONTENTS="$APP_PATH/Contents"
MACOS="$CONTENTS/MacOS"
mkdir -p "$MACOS" "$CONTENTS/Resources"
swiftc -parse-as-library -swift-version 5 -O \
  -target arm64-apple-macosx14.0 \
  -framework SwiftUI -framework AppKit \
  "$PROJECT_ROOT"/native/*.swift \
  -o "$MACOS/SkillDock"
cp "$PROJECT_ROOT/native/Resources/SkillDock.icns" "$CONTENTS/Resources/SkillDock.icns"
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key><string>SkillDock</string>
  <key>CFBundleExecutable</key><string>SkillDock</string>
  <key>CFBundleIdentifier</key><string>local.skilldock.manager</string>
  <key>CFBundleName</key><string>SkillDock</string>
  <key>CFBundleIconFile</key><string>SkillDock.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.6.0</string>
  <key>CFBundleVersion</key><string>9</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleLocalizations</key><array><string>zh_CN</string><string>en</string></array>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
# Finder caches icons against the bundle directory's modification time.
# Changes inside Contents alone leave that time unchanged.
touch "$APP_PATH"
xattr -cr "$APP_PATH"
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
echo "Built and verified $APP_PATH"

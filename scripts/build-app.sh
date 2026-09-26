#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
configuration=${1:-debug}
case "$configuration" in
    debug|release) ;;
    *) echo 'Usage: build-app.sh [debug|release]' >&2; exit 1 ;;
esac
swift build -c "$configuration" --product PhosphorusWriter
app=.build/Phosphorus.app
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp LICENSE "$app/Contents/Resources/LICENSE"
cp ".build/$configuration/PhosphorusWriter" "$app/Contents/MacOS/PhosphorusWriter"
build=$(git rev-list --count HEAD)
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PhosphorusWriter</string>
<key>CFBundleIdentifier</key><string>com.jacobheric.phosphorus-writer</string>
<key>CFBundleName</key><string>Phosphorus</string>
<key>CFBundleDisplayName</key><string>Phosphorus</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>$build</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Jacob Heric. MIT License.</string>
</dict></plist>
PLIST

#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build --product PhosphorusWriter
app=.build/Phosphorus\ Writer.app
mkdir -p "$app/Contents/MacOS"
cp .build/debug/PhosphorusWriter "$app/Contents/MacOS/PhosphorusWriter"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PhosphorusWriter</string>
<key>CFBundleIdentifier</key><string>com.jacobheric.phosphorus-writer</string>
<key>CFBundleName</key><string>Phosphorus Writer</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
open "$app"

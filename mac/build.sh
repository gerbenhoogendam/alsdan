#!/bin/bash
# Bouwt build/Als-Dan.app: swift build, dan een .app met de foto's van de onderdelen, de firmware en esptool erin, getekend met de
# Developer ID uit de sleutelhanger (dan onthoudt macOS de toestemming voor camera en microfoon). SIGN=- ./build.sh tekent ad hoc.
# Starten: open build/Als-Dan.app   Testen: swift test
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Als-Dan.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/parts" "$APP/Contents/Resources/firmware"
cp .build/release/AlsDan "$APP/Contents/MacOS/Als-Dan"
cp ../web/parts/*.jpg "$APP/Contents/Resources/parts/"
cp ../web/firmware/*.bin "$APP/Contents/Resources/firmware/"
cp -R Fonts "$APP/Contents/Resources/Fonts"   # Barlow (SIL Open Font License, licentie erbij)
ESPTOOL=$(ls -d ~/Library/Arduino15/packages/esp32/tools/esptool_py/*/esptool 2>/dev/null | tail -1)
if [ -n "$ESPTOOL" ]; then cp "$ESPTOOL" "$APP/Contents/Resources/esptool"; else echo "Let op: esptool niet gevonden (Arduino ESP32-core), firmware zetten werkt dan niet"; fi

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>Als-Dan</string>
	<key>CFBundleDisplayName</key><string>Als-Dan</string>
	<key>CFBundleExecutable</key><string>Als-Dan</string>
	<key>CFBundleIdentifier</key><string>nl.techno-otter.AlsDan</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>0.1</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.education</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSCameraUsageDescription</key><string>Om een foto te maken van een onderdeel, zodat Claude ziet wat het is en welke kleur de draadjes hebben.</string>
	<key>NSMicrophoneUsageDescription</key><string>Om je eigen geluiden op te nemen, en om te horen of er geklapt wordt of de deurbel gaat (voor regels met De Mac hoort).</string>
</dict>
</plist>
EOF

SIGN=${SIGN:-$(security find-identity -v -p codesigning | grep -o '"Developer ID Application[^"]*"' | head -1 | tr -d '"')}
codesign --force --sign "${SIGN:--}" "$APP"
echo "Klaar: $APP (getekend met ${SIGN:--})"

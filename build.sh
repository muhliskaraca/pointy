#!/bin/zsh
# Baut Pointy und installiert es nach ~/Applications.
#   ./build.sh           bauen und installieren
#   ./build.sh --start   danach gleich starten
#   ./build.sh --nur-bauen   nur bauen, nichts installieren
#
# Signatur: ohne Angabe wird ad hoc signiert ("-"). Dann fragt macOS nach jedem
# Neubau wieder nach den Rechten. Wer eine Apple-Development-Identität hat,
# trägt sie ein, dann bleiben die Rechte erhalten:
#   security find-identity -p codesigning -v
#   POINTY_SIGN_ID="Apple Development: Dein Name (XXXXXXXXXX)" ./build.sh
set -e
cd "$(dirname "$0")"
NAME=Pointy
KENNUNG=local.pointy.app
APP="build/$NAME.app"
ZIEL="$HOME/Applications/$NAME.app"
SIGN_ID="${POINTY_SIGN_ID:--}"

command -v swiftc >/dev/null || { echo "swiftc fehlt. Erst: xcode-select --install"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" \
  -o "$APP/Contents/MacOS/$NAME" Sources/*.swift
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$SIGN_ID" --identifier "$KENNUNG" "$APP"
echo "gebaut: $APP"
[[ "$1" == "--nur-bauen" ]] && exit 0

pkill -x "$NAME" 2>/dev/null || true
sleep 0.5
mkdir -p "$HOME/Applications"
rm -rf "$ZIEL"
cp -R "$APP" "$ZIEL"

# Autostart beim Anmelden (abschalten: Menüleiste > Autostart ausschalten)
PLIST="$HOME/Library/LaunchAgents/$KENNUNG.plist"
if [[ ! -f "$PLIST" ]]; then
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$KENNUNG</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-a</string>
		<string>$ZIEL</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF
fi
echo "installiert: $ZIEL"
if [[ "$1" == "--start" ]]; then open "$ZIEL"; fi

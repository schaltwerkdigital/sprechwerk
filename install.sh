#!/bin/bash
set -euo pipefail

# Sprechwerk installieren oder aktualisieren.
#
#   curl -fsSL https://raw.githubusercontent.com/schaltwerkdigital/sprechwerk/main/install.sh | bash
#   ./install.sh                      neueste Version von GitHub
#   ./install.sh ~/Downloads/Sprechwerk.zip   eine ZIP, die schon da ist (z. B. aus Slack)
#
# Einstellungen, Wörterbuch und Sprachmodelle liegen außerhalb der App und bleiben erhalten.

REPO="schaltwerkdigital/sprechwerk"
ASSET="Sprechwerk.zip"
APP_NAME="Sprechwerk"
DEST_DIR="/Applications"
DEST="$DEST_DIR/$APP_NAME.app"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [ "$(uname -m)" != "arm64" ]; then
    echo "Hinweis: Auf Intel-Macs läuft nur Whisper, Parakeet und Meetings brauchen Apple Silicon."
fi

ZIP="${1:-}"
if [ -n "$ZIP" ]; then
    [ -f "$ZIP" ] || { echo "❌ Datei nicht gefunden: $ZIP"; exit 1; }
    echo "📦 Nehme $ZIP"
elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "⬇️  Lade die neueste Version über gh ..."
    gh release download --repo "$REPO" --pattern "$ASSET" --dir "$WORK"
    ZIP="$WORK/$ASSET"
else
    echo "⬇️  Lade die neueste Version ..."
    if ! curl -fsSL "https://github.com/$REPO/releases/latest/download/$ASSET" -o "$WORK/$ASSET"; then
        echo "❌ Download fehlgeschlagen. Ist das Repository privat, mit 'gh auth login' anmelden"
        echo "   oder die ZIP aus dem Release laden und './install.sh <zip>' ausführen."
        exit 1
    fi
    ZIP="$WORK/$ASSET"
fi

ditto -x -k "$ZIP" "$WORK/unpacked"
NEW_APP="$(find "$WORK/unpacked" -maxdepth 2 -name "$APP_NAME.app" -type d | head -1)"
[ -n "$NEW_APP" ] || { echo "❌ In der ZIP steckt keine $APP_NAME.app."; exit 1; }
VERSION="$(defaults read "$NEW_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")"

if [ ! -w "$DEST_DIR" ]; then
    echo "❌ $DEST_DIR ist nicht beschreibbar. Mit einem Admin-Konto ausführen."
    exit 1
fi

UPDATE=false
if [ -d "$DEST" ]; then
    UPDATE=true
    if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        echo "⏹  Beende $APP_NAME ..."
        osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
            sleep 0.5
        done
        pkill -x "$APP_NAME" 2>/dev/null || true
    fi
    rm -rf "$DEST"
fi

ditto "$NEW_APP" "$DEST"
# Interne App ohne Apple-Notarisierung: die Download-Markierung entfernen, sonst blockiert
# Gatekeeper den Start.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo ""
if [ "$UPDATE" = true ]; then
    echo "✅ $APP_NAME $VERSION ist aktualisiert."
    echo ""
    echo "Fügt Sprechwerk keinen Text mehr ein: Einstellungen > Allgemein >"
    echo "„Freigabe zurücksetzen“ und Sprechwerk in den Bedienungshilfen wieder erlauben."
else
    echo "✅ $APP_NAME $VERSION ist installiert."
    echo ""
    echo "Der Einrichtungsassistent führt durch Mikrofon, Bedienungshilfen und das"
    echo "Sprachmodell (Parakeet Ultra, einmalig ca. 630 MB)."
fi
open "$DEST"

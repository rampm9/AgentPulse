#!/usr/bin/env bash
# Assembles AgentPulse.app bundle.
# Usage: ./Scripts/bundle.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/AgentPulse.app"
BIN_DIR="$ROOT/.build/bin"
mkdir -p "$BIN_DIR"
BINARY="$BIN_DIR/AgentPulse"

echo "Building AgentPulse executable..."
if swift build --package-path "$ROOT" 2>/dev/null; then
    SPM_BIN="$(swift build --package-path "$ROOT" --show-bin-path)/AgentPulse"
    cp "$SPM_BIN" "$BINARY"
else
    echo "Falling back to swiftc compiler..."
    swiftc -lsqlite3 -o "$BINARY" "$ROOT"/Sources/AgentPulse/*.swift
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BINARY" "$APP/Contents/MacOS/AgentPulse"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature so the app bundle launches cleanly on macOS
codesign --force --sign - "$APP" >/dev/null

echo "✅ Successfully built and signed $APP"

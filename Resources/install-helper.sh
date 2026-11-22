#!/bin/bash
# Installs the BatteryCare root helper as a LaunchDaemon. Run as root.
set -euo pipefail
SRC="$1"
LABEL=com.batterycare.helper
BIN=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist

launchctl bootout system/$LABEL 2>/dev/null || true
mkdir -p /Library/PrivilegedHelperTools
cp "$SRC" "$BIN"
chown root:wheel "$BIN"; chmod 755 "$BIN"
mkdir -p /Users/Shared/BatteryCare; chmod 777 /Users/Shared/BatteryCare

cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$BIN</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>/Users/Shared/BatteryCare/helper.log</string>
  <key>StandardErrorPath</key><string>/Users/Shared/BatteryCare/helper.log</string>
</dict></plist>
PL
chown root:wheel "$PLIST"; chmod 644 "$PLIST"
launchctl bootstrap system "$PLIST"

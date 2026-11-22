#!/bin/bash
# Stops the helper (it restores default charging on SIGTERM) and removes it. Run as root.
LABEL=com.batterycare.helper
launchctl bootout system/$LABEL 2>/dev/null || true
sleep 1
rm -f /Library/LaunchDaemons/$LABEL.plist /Library/PrivilegedHelperTools/$LABEL /Users/Shared/BatteryCare/status.json
pmset -a disablesleep 0 2>/dev/null || true
exit 0

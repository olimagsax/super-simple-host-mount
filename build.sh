#!/bin/zsh
# Builds "SSH Mounts.app" into ~/Applications (needs Xcode command line tools).
set -e
cd "$(dirname "$0")"
APP="$HOME/Applications/SSH Mounts.app"
pkill SSHMounts 2>/dev/null || true
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
swiftc -O main.swift -o "$APP/Contents/MacOS/SSHMounts"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
mkdir -p ~/.config/ssh-mounts
[ -f ~/.config/ssh-mounts/servers.json ] || cp servers.example.json ~/.config/ssh-mounts/servers.json
echo "Built $APP"
open "$APP"

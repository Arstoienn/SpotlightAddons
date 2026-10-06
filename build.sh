#!/bin/sh
# Builds Spotlight Plus.app, signs it, installs it into /Applications, and restarts it.
set -e
cd "$(dirname "$0")"

app="build/Spotlight Plus.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Info.plist "$app/Contents/"
cp AppIcon.icns "$app/Contents/Resources/"   # drawn by icon.swift
swiftc -O -o "$app/Contents/MacOS/SpotlightPlus" Sources/*.swift

# A real identity keeps the Accessibility permission across rebuilds; ad hoc loses it every time.
identity=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')
codesign --force --sign "${identity:--}" "$app"

# Spotlight Solve is the name it had before: left running or installed, there would be two cards.
pkill -x SpotlightPlus || true
pkill -x SpotlightSolve || true
rm -rf "/Applications/Spotlight Plus.app" "/Applications/Spotlight Solve.app"
cp -R "$app" /Applications/
open "/Applications/Spotlight Plus.app"
echo "Installed and started /Applications/Spotlight Plus.app (signed with ${identity:-ad hoc})"

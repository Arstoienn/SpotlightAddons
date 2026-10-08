#!/bin/sh
# Builds Spotlight Add-ons.app, signs it, installs it into /Applications, and restarts it.
set -e
cd "$(dirname "$0")"

app="build/Spotlight Add-ons.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Info.plist "$app/Contents/"
cp AppIcon.icns "$app/Contents/Resources/"   # drawn by icon.swift
swiftc -O -o "$app/Contents/MacOS/SpotlightAddons" Sources/*.swift

# A real identity keeps the Accessibility permission across rebuilds; ad hoc loses it every time.
identity=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')
codesign --force --sign "${identity:--}" "$app"

# Spotlight Plus and Spotlight Solve are the names it had before: left running or installed, there would be two cards.
pkill -x SpotlightAddons || true
pkill -x SpotlightPlus || true
pkill -x SpotlightSolve || true
rm -rf "/Applications/Spotlight Add-ons.app" "/Applications/Spotlight Plus.app" "/Applications/Spotlight Solve.app"
cp -R "$app" /Applications/
open "/Applications/Spotlight Add-ons.app"
echo "Installed and started /Applications/Spotlight Add-ons.app (signed with ${identity:-ad hoc})"

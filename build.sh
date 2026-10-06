#!/bin/sh
# Builds Spotlight Solve.app, signs it, installs it into /Applications, and restarts it.
set -e
cd "$(dirname "$0")"

app="build/Spotlight Solve.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/"
swiftc -O -o "$app/Contents/MacOS/SpotlightSolve" Sources/*.swift

# A real identity keeps the Accessibility permission across rebuilds; ad hoc loses it every time.
identity=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')
codesign --force --sign "${identity:--}" "$app"

pkill -x SpotlightSolve || true
rm -rf "/Applications/Spotlight Solve.app"
cp -R "$app" /Applications/
open "/Applications/Spotlight Solve.app"
echo "Installed and started /Applications/Spotlight Solve.app (signed with ${identity:-ad hoc})"

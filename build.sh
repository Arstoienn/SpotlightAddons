#!/bin/sh
# Builds Spotlight Add-ons.app, signs it, installs it into /Applications, and restarts it.
set -e
cd "$(dirname "$0")"

# --no-install builds a reviewable app entirely in this worktree.
case "${1:-}" in --no-install|"") ;; *) echo "Usage: ./build.sh [--no-install]" >&2; exit 2 ;; esac
./setup-astronomy.sh
app="build/Spotlight Add-ons.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Info.plist "$app/Contents/"
mkdir -p "$app/Contents/Resources/Astronomy"
cp Resources/Astronomy/engine.py Resources/Astronomy/methods.json Resources/Astronomy/requirements.txt "$app/Contents/Resources/Astronomy/"
cp build/astronomy-data/de440s.bsp "$app/Contents/Resources/Astronomy/"
cp -R build/astronomy-runtime "$app/Contents/Resources/Astronomy/runtime"
# Python runs with -B: bytecode writes must never invalidate the signed app's resource seal.
find "$app/Contents/Resources/Astronomy/runtime" -type d -name __pycache__ -prune -exec rm -rf {} +
cp AppIcon.icns "$app/Contents/Resources/"   # drawn by icon.swift
swiftc -O -o "$app/Contents/MacOS/SpotlightAddons" Sources/*.swift

# A real identity keeps the Accessibility permission across rebuilds; ad hoc loses it every time.
identity=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')
# Sign nested Python executables and extensions before signing the app bundle.
find "$app/Contents/Resources/Astronomy/runtime" -type f \( -name '*.so' -o -name '*.dylib' -o -name 'python3.13' \) -exec codesign --force --sign "${identity:--}" {} \;
codesign --force --sign "${identity:--}" "$app"
"$app/Contents/MacOS/SpotlightAddons" --astronomy-check '@redshift(500 nm,600 nm)' > build/astronomy-package-check.txt
codesign --verify --deep --strict "$app"
if [ "${1:-}" = "--no-install" ]; then
    echo "Built $app"
    exit 0
fi

# Spotlight Plus and Spotlight Solve are the names it had before: left running or installed, there would be two cards.
pkill -x SpotlightAddons || true
pkill -x SpotlightPlus || true
pkill -x SpotlightSolve || true
rm -rf "/Applications/Spotlight Add-ons.app" "/Applications/Spotlight Plus.app" "/Applications/Spotlight Solve.app"
cp -R "$app" /Applications/
# Left in build/, the copy would be found by Spotlight too, and listed beside the installed one.
rm -rf "$app"
open "/Applications/Spotlight Add-ons.app"
echo "Installed and started /Applications/Spotlight Add-ons.app (signed with ${identity:-ad hoc})"

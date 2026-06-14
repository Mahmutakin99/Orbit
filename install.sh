#!/bin/bash
set -e

echo "→ Building Orbit..."
xcodebuild -scheme Orbit -configuration Release -derivedDataPath build -quiet

APP="build/Build/Products/Release/Orbit.app"

if [ ! -d "$APP" ]; then
  echo "Build failed — $APP not found." >&2
  exit 1
fi

echo "→ Installing to /Applications..."
cp -R "$APP" /Applications/

echo "→ Done. Launch Orbit from /Applications or Spotlight."
open /Applications/Orbit.app

#!/bin/bash
set -e

echo "→ Building Orbit..."
xcodebuild -scheme Orbit -configuration Release -derivedDataPath build -quiet

APP="build/Build/Products/Release/Orbit.app"

if [ ! -d "$APP" ]; then
  echo "Build failed — $APP not found." >&2
  exit 1
fi

# Re-sign with a STABLE identity so macOS keeps Screen Recording / Accessibility
# permissions across rebuilds. Ad-hoc signatures (xcodebuild's default here)
# change their cdhash every build, which makes TCC treat each build as a brand
# new app and re-prompt for permission. Signing with the Apple Development cert
# gives a stable "designated requirement" → permissions persist.
IDENTITY="4F987AF97DDF2A961B5D3245F9777E44796D133A" # Apple Development: Mahmut AKIN
if security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "→ Signing with stable identity..."
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "⚠︎ Stable signing identity not found — falling back to ad-hoc."
  echo "  (Screen Recording permission may be re-requested after each build.)"
fi

echo "→ Installing to /Applications..."
rm -rf /Applications/Orbit.app
cp -R "$APP" /Applications/

echo "→ Done. Launch Orbit from /Applications or Spotlight."
open /Applications/Orbit.app

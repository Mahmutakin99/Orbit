#!/bin/bash
set -e

# ── Mevcut sürümü oku ──────────────────────────────────────────────────────────
PLIST="Orbit/Info.plist"
CURRENT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")

# Patch numarasını otomatik artır  (1.3.0 → 1.3.1)
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
DEFAULT_NEXT="$MAJOR.$MINOR.$((PATCH + 1))"

# ── Kullanıcıdan sürüm al ──────────────────────────────────────────────────────
echo "Mevcut sürüm: $CURRENT"
read -rp "Yeni sürüm [$DEFAULT_NEXT]: " INPUT
VERSION="${INPUT:-$DEFAULT_NEXT}"

# ── Release notu ──────────────────────────────────────────────────────────────
read -rp "Release notu (kısa açıklama): " NOTES

# ── Info.plist güncelle ───────────────────────────────────────────────────────
BUILD=$(echo "$VERSION" | tr -d '.')   # 1.4.0 → 140
/usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set CFBundleVersion $BUILD"               "$PLIST"
echo "✓ Sürüm $VERSION olarak güncellendi"

# ── Build + sign ──────────────────────────────────────────────────────────────
echo "→ Build alınıyor..."
xcodebuild -scheme Orbit -configuration Release -derivedDataPath build -quiet
APP="build/Build/Products/Release/Orbit.app"
IDENTITY="4F987AF97DDF2A961B5D3245F9777E44796D133A"
codesign --force --sign "$IDENTITY" "$APP"
echo "✓ Build + imza tamamlandı"

# ── Zip ───────────────────────────────────────────────────────────────────────
ZIP="build/Build/Products/Release/Orbit.app.zip"
rm -f "$ZIP"
(cd build/Build/Products/Release && zip -r --symlinks Orbit.app.zip Orbit.app -q)
echo "✓ Zip oluşturuldu"

# ── Commit + push ─────────────────────────────────────────────────────────────
git add -A
git commit -m "Release $VERSION — $NOTES"
git push origin main
echo "✓ Kod GitHub'a gönderildi"

# ── GitHub release ────────────────────────────────────────────────────────────
gh release create "v$VERSION" "$ZIP" \
  --title "v$VERSION — $NOTES" \
  --notes "## v$VERSION
$NOTES"
echo ""
echo "✅ Yayınlandı → https://github.com/Mahmutakin99/Orbit/releases/tag/v$VERSION"

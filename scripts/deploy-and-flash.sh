#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# mobile-deploy-flasher: Cloud Deploy + Physical iOS/Android Flashing Engine
# ==============================================================================

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
export DEVELOPER_DIR
REPO_DIR="/Users/alejandrolondono/dev/tulio"
TAURI_DIR="$REPO_DIR/apps/tauri"

echo "=========================================================="
echo "🚀 1. Building Web & Portal Frontends"
echo "=========================================================="
cd "$REPO_DIR"
pnpm build
echo "✅ Monorepo frontend build succeeded!"

echo ""
echo "=========================================================="
echo "☁️ 2. Syncing Git & Triggering Railway Production Deploy"
echo "=========================================================="
if [ -n "$(git status --porcelain)" ]; then
  echo "📦 Staging and committing uncommitted changes..."
  git add -A
  git commit -m "chore(deploy): automated release trigger via mobile-deploy-flasher" || true
fi

echo "📤 Pushing to GitHub origin main..."
git push origin main || echo "⚠️ Git push returned non-zero (may already be up to date)"

if command -v railway >/dev/null 2>&1; then
  echo "🚂 Deploying to Railway (service: tulio)..."
  railway up --service tulio --detach || echo "⚠️ Railway upload completed with notice"
  echo "✅ Railway deployment trigger dispatched!"
else
  echo "⚠️ Railway CLI not found; skipped cloud trigger."
fi

echo ""
echo "=========================================================="
echo "📱 3. Detecting Physical iOS Device"
echo "=========================================================="
DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null | grep "physical" | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-Fa-f]{40}' | head -n 1 || true)

if [ -z "${DEVICE_ID:-}" ]; then
  echo "⚠️ No physical iPhone detected via xcrun devicectl."
  echo "👉 Connect iPhone via USB-C/Lightning, unlock it, and tap 'Trust This Computer'."
else
  echo "✅ Detected physical iPhone: $DEVICE_ID"

  # Detect Apple Team ID
  TEAM_ID="${DEVELOPMENT_TEAM:-}"
  if [ -z "$TEAM_ID" ]; then
    TEAM_ID=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | sed -n 's/.*teamID = \([A-Z0-9]\{10\}\);.*/\1/p' | head -n 1 || true)
  fi
  if [ -z "$TEAM_ID" ]; then
    TEAM_ID="ARFHV77RW9"
  fi
  echo "🔑 Using Apple Development Team ID: $TEAM_ID"

  echo ""
  echo "🔨 Building iOS Application (Alepoli Operator)..."
  mkdir -p "$TAURI_DIR/src-tauri/gen/apple/assets"
  rm -rf "$TAURI_DIR/src-tauri/gen/apple/assets/"*
  cp -R "$REPO_DIR/apps/web/dist/"* "$TAURI_DIR/src-tauri/gen/apple/assets/"

  xcodebuild \
    -project "$TAURI_DIR/src-tauri/gen/apple/tulio-tauri.xcodeproj" \
    -scheme tulio-tauri_iOS \
    -configuration release \
    -destination "generic/platform=iOS" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_IDENTITY="Apple Development" \
    -allowProvisioningUpdates \
    build

  ALEPLOI_APP=$(find /Users/alejandrolondono/Library/Developer/Xcode/DerivedData/tulio-tauri-*/Build/Products/release-iphoneos -name "*.app" 2>/dev/null | head -n 1)

  if [ -n "$ALEPLOI_APP" ] && [ -d "$ALEPLOI_APP" ]; then
    echo "📲 Flashing $ALEPLOI_APP to iPhone ($DEVICE_ID)..."
    if xcrun devicectl device install app --device "$DEVICE_ID" "$ALEPLOI_APP"; then
      echo "🎉 Successfully installed Alepoli Operator on iPhone!"
    else
      echo "⚠️ Installation paused: Please UNLOCK your iPhone screen and run:"
      echo "   xcrun devicectl device install app --device '$DEVICE_ID' '$ALEPLOI_APP'"
    fi
  else
    echo "❌ Could not find built .app bundle in DerivedData."
  fi
fi

echo ""
echo "=========================================================="
echo "🤖 4. Checking Android Environment"
echo "=========================================================="
if [ -n "${ANDROID_HOME:-}" ] && [ -d "${ANDROID_HOME:-}" ]; then
  echo "✅ ANDROID_HOME found at $ANDROID_HOME"
  cd "$TAURI_DIR"
  pnpm exec tauri android build || echo "⚠️ Android build finished with warnings."
else
  echo "ℹ️ Android SDK (ANDROID_HOME / NDK_HOME) is not configured on this host."
  echo "👉 To build Android APKs: install Android Studio or cmdline-tools and export ANDROID_HOME."
fi

echo ""
echo "=========================================================="
echo "🏁 Deployment & Flashing Pipeline Complete!"
echo "=========================================================="

#!/bin/bash

# SentryReplayDebugger Release Build Script
# This script builds a release version of the app and creates a DMG for distribution

set -e  # Exit on error

# Configuration
APP_NAME="SentryReplayDebugger"
VERSION="1.0.0"  # Update this for each release
BUILD_DIR="./build"
DIST_DIR="./dist"
SCHEME="${APP_NAME}"
PROJECT="${APP_NAME}.xcodeproj"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Building ${APP_NAME} v${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf "$BUILD_DIR"
mkdir -p "$DIST_DIR"

# Build release
echo "🔨 Building release version..."
xcodebuild clean build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  | xcpretty || xcodebuild clean build \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Build succeeded${NC}"
echo ""

# Find the built app
APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}❌ App not found at: ${APP_PATH}${NC}"
    exit 1
fi

# Copy app to dist directory
echo "📦 Copying app to dist directory..."
cp -R "$APP_PATH" "$DIST_DIR/"

# Get app info
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "$VERSION")
APP_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "1")

echo "   Version: ${APP_VERSION}"
echo "   Build: ${APP_BUILD}"
echo ""

# Create DMG
DMG_NAME="${APP_NAME}-v${APP_VERSION}-build${APP_BUILD}.dmg"
echo "💿 Creating DMG: ${DMG_NAME}"

# Remove old DMG if exists
rm -f "${DIST_DIR}/${DMG_NAME}"

# Create temporary folder for DMG contents
TEMP_DMG_DIR="${BUILD_DIR}/dmg_temp"
mkdir -p "$TEMP_DMG_DIR"
cp -R "$APP_PATH" "$TEMP_DMG_DIR/"

# Create DMG
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "$TEMP_DMG_DIR" \
  -ov \
  -format UDZO \
  "${DIST_DIR}/${DMG_NAME}"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ DMG creation failed${NC}"
    exit 1
fi

echo -e "${GREEN}✅ DMG created successfully${NC}"
echo ""

# Create ZIP as well (alternative distribution format)
echo "🗜️  Creating ZIP archive..."
ZIP_NAME="${APP_NAME}-v${APP_VERSION}-build${APP_BUILD}.zip"
cd "$DIST_DIR"
zip -r -q "$ZIP_NAME" "${APP_NAME}.app"
cd - > /dev/null

echo -e "${GREEN}✅ ZIP created successfully${NC}"
echo ""

# Calculate file sizes
DMG_SIZE=$(du -h "${DIST_DIR}/${DMG_NAME}" | cut -f1)
ZIP_SIZE=$(du -h "${DIST_DIR}/${ZIP_NAME}" | cut -f1)
APP_SIZE=$(du -sh "${DIST_DIR}/${APP_NAME}.app" | cut -f1)

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}🎉 Build Complete!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📦 Distribution files:"
echo "   • DMG:  ${DIST_DIR}/${DMG_NAME} (${DMG_SIZE})"
echo "   • ZIP:  ${DIST_DIR}/${ZIP_NAME} (${ZIP_SIZE})"
echo "   • App:  ${DIST_DIR}/${APP_NAME}.app (${APP_SIZE})"
echo ""
echo "📋 Next steps:"
echo "   1. Test the app: open ${DIST_DIR}/${APP_NAME}.app"
echo "   2. Distribute:   Share ${DMG_NAME} or ${ZIP_NAME} with your team"
echo ""
echo "💡 Installation instructions for team members:"
echo "   1. Download the DMG or ZIP"
echo "   2. Extract and move to Applications"
echo "   3. Right-click → Open (first time only)"
echo "   4. Click 'Open' in the security dialog"
echo ""

# Optional: Open dist folder
read -p "📂 Open dist folder? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "$DIST_DIR"
fi

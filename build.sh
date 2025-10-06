#!/bin/bash

set -e  # Exit on error

echo "🔨 Building SentryReplayDebugger..."

# Build the project
xcodebuild -project SentryReplayDebugger.xcodeproj \
           -scheme SentryReplayDebugger \
           -configuration Release \
           clean build

echo "✅ Build completed successfully!"
echo "📦 App location: build/Release/SentryReplayDebugger.app"
echo "🚀 Launching app..."

# Launch the app
open build/Release/SentryReplayDebugger.app

# Sentry Replay Debugger

A macOS application for debugging and inspecting Sentry Session Replay data. View replay segments, inspect events, and render HTML snapshots from rrweb events.

## Features

- **Segment Browser**: View all replay segments with timestamps and metadata
- **Event Inspector**: Inspect individual replay events with JSON data viewer
- **HTML Renderer**: Visualize DOM snapshots at any point in the replay
- **Event Filtering**: Filter by event type, timestamp, and more
- **Search**: Global search across all segments and events
- **Incremental Rendering**: Efficient HTML rendering with DOM mutation support

## Prerequisites

- macOS 14.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

## Configuration

### Sentry Error Tracking

The app uses Sentry for error tracking. To configure:

1. Get your Sentry DSN from your Sentry project settings:
   - Go to https://sentry.io/settings/YOUR_ORG/projects/YOUR_PROJECT/keys/
   - Copy your DSN

2. Configure the DSN in Xcode:
   - Open the project in Xcode
   - Go to **Product > Scheme > Edit Scheme**
   - Select **Run** in the left sidebar
   - Go to the **Arguments** tab
   - Under **Environment Variables**, click the **+** button
   - Add:
     - Name: `SENTRY_DSN`
     - Value: `your-actual-sentry-dsn-here`

The app will run without Sentry if the DSN is not configured (it will print a warning in the console).

## Building the Project

### Option 1: Using Xcode (Recommended)

#### 1. Clone the Repository

```bash
git clone <repository-url>
cd replay-debugger
```

#### 2. Open in Xcode

```bash
open SentryReplayDebugger.xcodeproj
```

Or simply double-click `SentryReplayDebugger.xcodeproj` in Finder.

#### 3. Select Target and Build

1. In Xcode, select the **SentryReplayDebugger** scheme from the scheme selector
2. Choose **My Mac** as the destination
3. Build and run with `⌘R` or click the Run button

The app will build and launch automatically.

### Option 2: Using Command Line

#### 1. Clone the Repository

```bash
git clone <repository-url>
cd replay-debugger
```

#### 2. Build the Project

```bash
xcodebuild -project SentryReplayDebugger.xcodeproj \
           -scheme SentryReplayDebugger \
           -configuration Release \
           clean build
```

#### 3. Locate the Built App

The app will be built to:
```bash
build/Release/SentryReplayDebugger.app
```

Or use `xcodebuild` to find the exact path:
```bash
xcodebuild -project SentryReplayDebugger.xcodeproj \
           -scheme SentryReplayDebugger \
           -configuration Release \
           -showBuildSettings | grep -m 1 "BUILD_DIR" | grep -oEi "\/.*"
```

#### 4. Run the App

```bash
open build/Release/SentryReplayDebugger.app
```

Or directly:
```bash
./build/Release/SentryReplayDebugger.app/Contents/MacOS/SentryReplayDebugger
```

#### Quick Build & Run Script

Create a `build.sh` script for convenience:

```bash
#!/bin/bash

# Build the project
xcodebuild -project SentryReplayDebugger.xcodeproj \
           -scheme SentryReplayDebugger \
           -configuration Release \
           clean build

# Launch the app
open build/Release/SentryReplayDebugger.app
```

Make it executable:
```bash
chmod +x build.sh
./build.sh
```

## Loading Replay Data

### From Sentry URL

1. Launch the app
2. Paste a Sentry replay URL in the text field at the top
3. Click "Fetch" or press `⌘R`

Example URL format:
```
https://sentry.io/organizations/YOUR_ORG/replays/YOUR_REPLAY_ID/
```

### From Clipboard (JSON)

1. Copy replay segment JSON data to your clipboard
2. Press `⇧⌘V` or click "Load JSON" in the toolbar
3. The app will parse and display the segments

### From Debug File (Development)

For development/testing, place a `billy.json` file in the project root directory. The app will automatically load it on launch.

Supported formats:
- Array of segment objects: `[{segment1}, {segment2}, ...]`
- Array of event arrays: `[[event1, event2], [event3, event4], ...]`
- Single segment object: `{segment: {...}}`

## Usage

### Keyboard Shortcuts

- `⌘R` - Fetch replay from URL
- `⇧⌘V` - Load JSON from clipboard
- `⌘F` - Open global search

### Filtering Events

1. Click the **Filters** button in the toolbar
2. Filter by:
   - Event type (DomContentLoaded, FullSnapshot, IncrementalSnapshot, etc.)
   - Timestamp (before/after a specific time)
   - Invert filter option

### Inspecting Events

1. Select a segment from the left sidebar
2. Select an event from the middle panel
3. View:
   - **JSON data** in the top-right panel
   - **Rendered HTML** in the bottom-right panel

Toggle between **Rendered** and **Source** views in the HTML panel.

## Architecture

The app is structured around three main components:

- **Segments**: Batches of events sent from the browser
- **Events**: Individual rrweb events (DOM snapshots, mutations, etc.)
- **HTML Renderer**: Processes rrweb events to reconstruct and display the page state

Events are flattened across all segments for rendering, with proper handling of Meta and FullSnapshot events from prior segments.

## Development

### Debug HTML Output

When rendering HTML, the app writes debug output to:
```
~/Library/Containers/com.sentry.SentryReplayDebugger/Data/tmp/sentry-replay-debug.html
```

This file is automatically opened in your browser on first render.

### Project Structure

```
SentryReplayDebugger/
├── Models/              # Data models (ReplaySegment, ReplayEvent)
├── Views/               # SwiftUI views
├── Utilities/           # Helper classes (RRWebEventProcessor, etc.)
├── Services/            # API services (SentryAPIService)
└── ContentView.swift    # Main app view
```

## Troubleshooting

### "Failed to fetch replay data"

- Verify the Sentry URL is correct
- Check your network connection
- Ensure you have access to the organization/project

### "No HTML generated"

- The selected event needs a FullSnapshot event before it
- Try selecting an earlier event or a different segment

### Events not rendering correctly

- Ensure you're viewing events in sorted order (toggle in the Events panel)
- Check that all segments loaded successfully

## License

[Add your license here]

## Contributing

[Add contribution guidelines here]

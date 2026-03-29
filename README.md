# Sentry Replay Debugger

A macOS application for debugging and inspecting Sentry Session Replay data. View replay segments, inspect events, and render HTML snapshots from rrweb events.

## Features

- **Authentication**: OAuth login via Sentry for secure access
- **Segment Browser**: View all replay segments with timestamps and metadata
- **Event Inspector**: Inspect individual replay events with JSON data viewer
- **HTML Renderer**: Visualize DOM snapshots at any point in the replay
- **Event Filtering**: Filter by event type, timestamp, node ID, and more
- **Search**: Global search across all segments and events with match navigation
- **Incremental Rendering**: Efficient HTML rendering with DOM mutation support
- **Segment Export**: Export replay segments for sharing
- **cURL Import**: Paste cURL commands to load replay data directly

## Prerequisites

- macOS 14.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

## Configuration

**For local development**, copy the template config and fill in your values:

```bash
cp Config.example.xcconfig Config.xcconfig
```

Then edit `Config.xcconfig` with your actual credentials:

```
SENTRY_DSN = https://YOUR_KEY@oNNN.ingest.sentry.io/YOUR_PROJECT_ID
OAUTH_CLIENT_ID = your-oauth-client-id
OAUTH_CLIENT_SECRET = your-oauth-client-secret
```

**For release/CI builds**, set `SENTRY_DSN`, `OAUTH_CLIENT_ID`, and `OAUTH_CLIENT_SECRET` as secrets in your GitHub repository settings.

The `OAUTH_CLIENT_ID` and `OAUTH_CLIENT_SECRET` are required for Sentry OAuth login. The app will run without Sentry error tracking if no DSN is configured (it will print a warning in the console).

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

All loading is done via the clipboard. Copy your data, then press `⌘V` or click the **Paste** button in the toolbar. The app auto-detects the format:

### Sentry URL

Copy a Sentry replay URL to your clipboard and paste it into the app.

Example URL format:
```
https://sentry.io/organizations/YOUR_ORG/replays/YOUR_REPLAY_ID/
```

### cURL Command

Copy a cURL command (e.g., from browser DevTools) that fetches replay segment data and paste it into the app.

### JSON Data

Copy raw replay JSON to your clipboard and paste it into the app.

Supported JSON formats:
- Array of segment objects: `[{segment1}, {segment2}, ...]`
- Array of event arrays: `[[event1, event2], [event3, event4], ...]`
- Single segment object: `{segment: {...}}`

## Usage

### Keyboard Shortcuts

- `⌘V` - Load from clipboard (URL, cURL, or JSON)
- `⌘F` - Open global search
- `⌘G` - Next search match
- `⇧⌘G` - Previous search match
- `ESC` - Close search
- `↑` / `↓` - Navigate events
- `←` / `→` - Navigate segments

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

When rendering HTML, the app writes debug output to the system temporary directory:
```
$TMPDIR/sentry-replay-debug.html
```

This file is automatically opened in your browser on first render.

### Project Structure

```
SentryReplayDebugger/
├── Config.swift                    # Build configuration (DSN, OAuth)
├── ContentView.swift               # Main app view
├── SentryReplayDebuggerApp.swift   # App entry point
├── Models/
│   ├── ReplayModels.swift          # ReplaySegment, ReplayEvent
│   └── UserProfile.swift           # Sentry user profile
├── Views/
│   ├── EmptyStateView.swift        # Empty/onboarding state
│   ├── HTMLRendererView.swift       # HTML snapshot renderer
│   ├── HTMLSourceView.swift         # HTML source code viewer
│   ├── JSONInspectorView.swift      # JSON data inspector
│   ├── LoginView.swift              # OAuth login
│   ├── SegmentListView.swift        # Segment/event browser
│   └── UserAvatarView.swift         # User avatar display
├── Utilities/
│   ├── CURLParser.swift             # cURL command parser
│   ├── DOMNode.swift                # DOM tree representation
│   ├── HTMLBeautifier.swift         # HTML formatting
│   ├── RRWebEventProcessor.swift    # rrweb event processing
│   ├── RRWebHTMLConverter.swift     # rrweb to HTML conversion
│   ├── SegmentExporter.swift        # Segment export
│   └── SentryURLParser.swift        # Sentry URL parsing
└── Services/
    ├── AuthService.swift            # OAuth authentication
    ├── KeychainHelper.swift         # Secure credential storage
    └── SentryAPIService.swift       # Sentry API client
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

This project is licensed under the [Apache License 2.0](LICENSE.md). See the [LICENSE.md](LICENSE.md) file for details.

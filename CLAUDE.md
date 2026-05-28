# Claude Code Development Guidelines

This file contains guidelines and rules for AI assistants working on this codebase.

## Project Overview

SentryReplayDebugger is a macOS application for debugging and inspecting Sentry Session Replay data. It's built with SwiftUI and uses the Sentry Cocoa SDK.

## General Instructions

- Don't ever say "You're absolutely right!", "You're right" etc. Prefer something like "OK, let's try...". Generally, write responses in terse language. Stay on point. Reduce adjectives and flowery language. 

## Development Expertise

You are an expert macOS developer specializing in building apps with clean, unobtrusive design. Use modern frameworks for building delightful user experiences and implement best practices for safe and performant code. Omit unnecessary code comments.

## Architecture Considerations

- Prioritize asynchronous operations and non-blocking I/O
- Implement proper memory management to prevent leaks
- Use lightweight data structures and efficient serialization
- Design modular components that can be easily tested in isolation
- Consider device capabilities and iOS version compatibility
- Implement circuit breaker patterns for external service calls
- Factor out models and views into their own files instead of adding everything to a single file

## macOS Development Standards

- Follow Apple's Human Interface Guidelines for any UI components
- Use SwiftUI for modern interface development where appropriate
- Implement proper accessibility support
- Handle app lifecycle events correctly (foreground/background transitions)
- Leverage system frameworks like os.log for internal logging
- Implement proper keychain usage for sensitive data storage

## Development Environment

### Prerequisites
- macOS 14.0 or later
- Xcode 15.0 or later
- Swift 5.9 or later

### Dependencies
- Managed via Swift Package Manager
- Primary dependency: `sentry-cocoa` @ 8.57.0

## Testing

### Running Tests

The project has two test suites:
1. **Unit Tests** (`SentryReplayDebuggerTests`) - 8 test files covering core functionality
2. **UI Tests** (`SentryReplayDebuggerUITests`) - 2 test files for UI validation

**Run all tests:**
```bash
xcodebuild test -project SentryReplayDebugger.xcodeproj \
  -scheme SentryReplayDebugger \
  -destination 'platform=macOS,arch=arm64'
```

**Run unit tests only:**
```bash
xcodebuild build -project SentryReplayDebugger.xcodeproj \
  -target SentryReplayDebuggerTests \
  -destination 'platform=macOS,arch=arm64'
```

### Test Files

**Unit Tests** (`SentryReplayDebuggerTests/`):
- `CURLParserTests.swift` - cURL command parsing
- `DOMNodeTests.swift` - DOM node manipulation
- `HTMLBeautifierTests.swift` - HTML formatting
- `ReplayModelsTests.swift` - Data model validation
- `RRWebEventProcessorTests.swift` - Event processing logic
- `RRWebHTMLConverterTests.swift` - HTML conversion
- `SentryReplayDebuggerTests.swift` - General app tests
- `SentryURLParserTests.swift` - URL parsing

**UI Tests** (`SentryReplayDebuggerUITests/`):
- `SegmentListViewUITests.swift` - Segment list UI tests
- `HTMLRendererViewUITests.swift` - HTML renderer UI tests

### Known Test Issues

**Preview Content Directory:**
If you encounter the error `One of the paths in DEVELOPMENT_ASSET_PATHS does not exist: .../Preview Content`, create the directory:
```bash
mkdir -p "SentryReplayDebugger/Preview Content"
```

This is a SwiftUI requirement and the directory may not be tracked by git if empty.

## Code Conventions

### XCTest UI Testing on macOS

When writing UI tests for SwiftUI `List` views on macOS:
- ✅ Use `app.scrollViews["identifier"]` to access List elements
- ❌ Do NOT use `app.lists["identifier"]` - this API doesn't exist for macOS

Example:
```swift
// Correct ✅
let eventsList = app.scrollViews["events-list"]

// Incorrect ❌
let eventsList = app.lists["events-list"]
```

### Accessibility Identifiers

The codebase uses accessibility identifiers for UI testing. When adding new UI elements that need to be tested:
- Use `.accessibilityIdentifier("element-name")` on SwiftUI views
- Follow the naming convention: `kebab-case` with descriptive names
- Examples: `"segments-scroll-view"`, `"events-list"`, `"event-row-event-1"`

## Git Subtrees and Worktrees

This project works correctly in git subtrees/worktrees. The development environment has been verified to work in temporary directories like `/var/folders/...`.

## Building

### Command Line Build
```bash
xcodebuild build -project SentryReplayDebugger.xcodeproj \
  -scheme SentryReplayDebugger \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64'
```

### Using Xcode
Open `SentryReplayDebugger.xcodeproj` in Xcode and build with ⌘B.

## Linting & Formatting

Formatting is owned by **swift-format** (`.swift-format`); code-quality linting by **SwiftLint** (`.swiftlint.yml`). The two are kept non-overlapping so they don't fight. CI (`.github/workflows/lint.yml`) runs both and **fails** on any formatting deviation (`swift-format lint --strict`) or SwiftLint error.

```bash
scripts/lint.sh         # check formatting + lint (matches CI)
scripts/lint.sh --fix   # reformat in place and apply SwiftLint autocorrections
```

Run `scripts/lint.sh --fix` before committing. `swift-format` ships with the Xcode toolchain (`xcrun swift-format`); install SwiftLint via `brew install swiftlint`.

Note: `redundant_discardable_let` is disabled — `let _ = sideEffect()` is the SwiftUI ViewBuilder idiom for inline side effects, and rewriting it to `_ = ...` produces code ViewBuilder rejects.

## Project Structure

```
SentryReplayDebugger/
├── Models/              # Data models (ReplaySegment, ReplayEvent)
├── Views/               # SwiftUI views
├── Utilities/           # Helper classes (RRWebEventProcessor, etc.)
└── Services/            # API services (SentryAPIService)
```

## Configuration

### Sentry Error Tracking

The app uses Sentry for error tracking. Configure via environment variable:
- Variable: `SENTRY_DSN`
- Set in: Xcode > Product > Scheme > Edit Scheme > Run > Arguments > Environment Variables
- The app will run without Sentry if DSN is not configured (with console warning)

## Performance Notes

The codebase includes performance optimizations:
- Cached segment sizes (`approximateSize` property)
- Sampled column width calculations (first 50 segments)
- Fixed event column width to avoid full iteration
- Local variables for repeated property access
When making changes, consider performance impact on large replay datasets.

# OAuth Setup Instructions

## Required Manual Configuration Steps

### 1. Register Custom URL Scheme in Xcode

To enable OAuth callback handling, you need to register a custom URL scheme in your Xcode project:

1. Open the Xcode project (`SentryReplayDebugger.xcodeproj`)
2. Select the project in the Project Navigator
3. Select the "SentryReplayDebugger" target
4. Go to the "Info" tab
5. Expand "URL Types" section (or add it if it doesn't exist)
6. Click the "+" button to add a new URL Type
7. Fill in the following:
   - **Identifier**: `com.sentry.replay-debugger.oauth`
   - **URL Schemes**: `sentry-replay-debugger`
   - **Role**: Editor

### 2. Configure OAuth Credentials

Update the OAuth configuration in `SentryReplayDebugger/Services/SentryOAuthService.swift`:

```swift
// Lines 10-14 in SentryOAuthService.swift
private let clientId = "YOUR_SENTRY_CLIENT_ID"  // Replace with actual Sentry OAuth Client ID
private let clientSecret = "YOUR_SENTRY_CLIENT_SECRET"  // Replace with actual Sentry OAuth Client Secret
```

**To obtain these credentials:**
1. Log in to your Sentry organization
2. Go to Settings → Developer Settings → Applications
3. Create a new OAuth application
4. Set the redirect URI to: `sentry-replay-debugger://oauth/callback`
5. Copy the Client ID and Client Secret to the service file

### 3. Adjust OAuth Scopes (if needed)

The default scopes are set to `project:read org:read` in line 40 of `SentryOAuthService.swift`:

```swift
URLQueryItem(name: "scope", value: "project:read org:read")
```

Adjust these scopes based on what permissions your app needs:
- `project:read` - Read project information
- `project:write` - Write project information
- `org:read` - Read organization information
- `org:write` - Write organization information
- `event:read` - Read event data
- `event:write` - Write event data

### 4. Verify Entitlements

The following entitlements have been added to `SentryReplayDebugger.entitlements`:
- ✅ `keychain-access-groups` - For secure token storage

### 5. Test OAuth Flow

Once configured:
1. Build and run the app
2. Click the "Login" button in the toolbar (next to Replay URL input)
3. Complete the OAuth flow in the browser
4. Verify that you're redirected back to the app
5. Confirm that API requests use the OAuth token

## Architecture Overview

### Components Created

1. **KeychainManager** (`Utilities/KeychainManager.swift`)
   - Securely stores OAuth tokens in macOS Keychain
   - Manages access token, refresh token, and expiry

2. **SentryOAuthService** (`Services/SentryOAuthService.swift`)
   - Handles OAuth 2.0 authorization flow
   - Uses `ASWebAuthenticationSession` for secure authentication
   - Manages token refresh automatically
   - Published `isAuthenticated` state for UI binding

3. **Updated ContentView** (`ContentView.swift`)
   - Login/Logout button in toolbar
   - Reactive UI based on authentication state

4. **Updated SentryAPIService** (`Services/SentryAPIService.swift`)
   - Fetches tokens from Keychain instead of UserDefaults
   - Uses OAuth tokens for API authentication

### OAuth Flow Sequence

1. User clicks "Login" button
2. `ASWebAuthenticationSession` opens Sentry OAuth page
3. User authenticates with Sentry
4. Sentry redirects to `sentry-replay-debugger://oauth/callback?code=...`
5. App receives callback via URL scheme handler
6. App exchanges authorization code for access token
7. Tokens stored securely in Keychain
8. API requests automatically use stored token

### Security Features

- ✅ Tokens stored in macOS Keychain (not UserDefaults)
- ✅ Uses Apple's `ASWebAuthenticationSession` for secure OAuth
- ✅ Automatic token refresh before expiration
- ✅ Tokens cleared completely on logout
- ✅ 60-second buffer before token expiry for refresh

## Troubleshooting

### OAuth Redirect Not Working
- Verify URL scheme is registered in Xcode project Info tab
- Check that redirect URI matches exactly: `sentry-replay-debugger://oauth/callback`
- Ensure app is running when OAuth flow completes

### Token Storage Issues
- Verify Keychain entitlement is properly configured
- Check that bundle identifier matches entitlement: `com.sentry.replay-debugger`
- Review Console.app for Keychain-related errors

### Authentication Session Not Starting
- Ensure app has proper windowing (one window must be key window)
- Check that `ASWebAuthenticationSession` presentation context is valid
- Verify user didn't deny browser access in System Preferences

## Additional Notes

- The OAuth service uses singleton pattern (`SentryOAuthService.shared`)
- Authentication state is published via `@Published` for SwiftUI reactivity
- Tokens refresh automatically 60 seconds before expiration
- All OAuth operations are async/await for modern Swift concurrency

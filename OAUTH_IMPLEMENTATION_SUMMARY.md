# OAuth Authentication Implementation - Summary

## Overview
Successfully implemented OAuth 2.0 authentication for the Sentry Replay Debugger macOS application. A login/logout button has been added to the toolbar next to the Replay URL input field.

## Files Created

### 1. KeychainManager.swift
**Location**: `SentryReplayDebugger/Utilities/KeychainManager.swift`

**Purpose**: Provides secure token storage using macOS Keychain

**Key Features**:
- Securely stores OAuth access token, refresh token, and expiry timestamp
- Uses macOS Security framework (`SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete`)
- Includes token expiration checking with 60-second buffer
- Complete cleanup on logout
- Error handling with custom `KeychainError` enum

**Main Methods**:
- `saveAccessToken(_:)` / `getAccessToken()`
- `saveRefreshToken(_:)` / `getRefreshToken()`
- `saveTokenExpiry(_:)` / `getTokenExpiry()`
- `isTokenExpired()` - Checks if token needs refresh
- `clearAllTokens()` - Removes all stored credentials

### 2. SentryOAuthService.swift
**Location**: `SentryReplayDebugger/Services/SentryOAuthService.swift`

**Purpose**: Manages the complete OAuth 2.0 authentication flow

**Key Features**:
- Uses `ASWebAuthenticationSession` for secure browser-based OAuth
- Implements OAuth 2.0 authorization code flow
- Automatic token refresh before expiration
- Published `@Published` properties for SwiftUI reactivity
- Singleton pattern for app-wide authentication state

**Main Methods**:
- `login()` - Initiates OAuth flow with Sentry
- `logout()` - Clears all tokens and resets auth state
- `refreshTokenIfNeeded()` - Automatically refreshes expired tokens
- `checkAuthenticationStatus()` - Verifies current auth state

**OAuth Configuration** (requires manual setup):
- `clientId` - Sentry OAuth application Client ID (line 10)
- `clientSecret` - Sentry OAuth application Client Secret (line 11)
- `authorizationEndpoint` - Sentry OAuth authorization URL
- `tokenEndpoint` - Sentry OAuth token exchange URL
- `redirectURI` - Custom URL scheme for callback (`sentry-replay-debugger://oauth/callback`)

**Published Properties**:
- `isAuthenticated: Bool` - Current authentication state
- `userInfo: String?` - Optional user information (future enhancement)

## Files Modified

### 1. ContentView.swift
**Changes**:
- Added `@StateObject` for `SentryOAuthService` (line 97)
- Added Login/Logout button in toolbar (lines 443-454)
- Implemented `handleLogin()` and `handleLogout()` methods (lines 1473-1490)
- Added `onOpenURL` modifier for OAuth callback handling (lines 583-596)

**UI Changes**:
- Login button shows when not authenticated (icon: `person.crop.circle.badge.checkmark`)
- Logout button shows when authenticated (icon: `person.crop.circle.badge.xmark`)
- Button placement: Left of Replay URL TextField in toolbar
- Error messages display for failed authentication attempts

### 2. SentryAPIService.swift
**Changes**:
- Updated `getAuthToken()` to check Keychain first (lines 58-67)
- Falls back to UserDefaults for backward compatibility
- Added automatic token refresh before API requests (line 19)
- Added 401 Unauthorized error handling (lines 38-40)
- Added new `APIError.unauthorized` case (line 356)

**Token Priority**:
1. OAuth token from Keychain (primary)
2. Legacy token from UserDefaults (fallback)

### 3. SentryReplayDebugger.entitlements
**Changes**:
- Added `keychain-access-groups` entitlement (lines 9-12)
- Keychain group: `$(AppIdentifierPrefix)com.sentry.replay-debugger`

### 4. SentryReplayDebuggerApp.swift
**Changes**:
- Added `.handlesExternalEvents(matching:)` modifier (line 11)
- Enables app to receive OAuth callback URLs

## OAuth Flow Sequence

1. **User Clicks Login Button**
   - `handleLogin()` called in ContentView
   - `SentryOAuthService.login()` initiated

2. **Authorization Request**
   - App generates authorization URL with client ID, redirect URI, and scopes
   - `ASWebAuthenticationSession` opens Sentry OAuth page in secure browser
   - User enters Sentry credentials and authorizes application

3. **Authorization Callback**
   - Sentry redirects to: `sentry-replay-debugger://oauth/callback?code=AUTH_CODE`
   - `ASWebAuthenticationSession` automatically captures the callback
   - App extracts authorization code from URL

4. **Token Exchange**
   - App sends POST request to token endpoint with authorization code
   - Receives access token, refresh token, and expiry information
   - Tokens stored securely in macOS Keychain

5. **Authenticated State**
   - `isAuthenticated` property set to `true`
   - UI updates to show Logout button
   - API requests automatically include OAuth token

6. **Automatic Token Refresh**
   - Before each API request, checks if token will expire soon (60s buffer)
   - If needed, uses refresh token to get new access token
   - Happens transparently without user interaction

7. **Logout**
   - User clicks Logout button
   - All tokens cleared from Keychain
   - `isAuthenticated` set to `false`
   - UI updates to show Login button

## Security Features

✅ **Keychain Storage**: Tokens stored in macOS Keychain, not UserDefaults or files
✅ **ASWebAuthenticationSession**: Apple's secure OAuth flow implementation
✅ **Token Refresh**: Automatic refresh before expiration (60s buffer)
✅ **Secure Cleanup**: Complete token removal on logout
✅ **401 Handling**: Proper unauthorized response handling
✅ **App Sandboxing**: Works within macOS sandbox restrictions
✅ **No Token Logging**: No sensitive data logged in production

## Configuration Required

### 1. Register URL Scheme in Xcode
**Steps**:
1. Open `SentryReplayDebugger.xcodeproj` in Xcode
2. Select project → Target → Info tab
3. Add URL Type:
   - **Identifier**: `com.sentry.replay-debugger.oauth`
   - **URL Schemes**: `sentry-replay-debugger`
   - **Role**: Editor

### 2. Configure OAuth Credentials
**File**: `SentryReplayDebugger/Services/SentryOAuthService.swift` (lines 10-14)

**Sentry Setup**:
1. Go to Sentry.io → Organization Settings → Developer Settings → Applications
2. Create new OAuth Application
3. Set Redirect URI: `sentry-replay-debugger://oauth/callback`
4. Copy Client ID and Client Secret
5. Update in `SentryOAuthService.swift`:
   ```swift
   private let clientId = "YOUR_ACTUAL_CLIENT_ID"
   private let clientSecret = "YOUR_ACTUAL_CLIENT_SECRET"
   ```

### 3. Adjust OAuth Scopes (Optional)
**File**: `SentryReplayDebugger/Services/SentryOAuthService.swift` (line 40)

Current scopes: `project:read org:read`

Available scopes:
- `project:read`, `project:write`
- `org:read`, `org:write`
- `event:read`, `event:write`
- `team:read`, `team:write`

## Testing Checklist

- [ ] URL scheme registered in Xcode project
- [ ] OAuth credentials configured in `SentryOAuthService.swift`
- [ ] Build succeeds without errors
- [ ] Login button appears in toolbar
- [ ] Clicking Login opens Sentry OAuth page
- [ ] After authentication, redirects back to app
- [ ] Logout button appears after successful login
- [ ] API requests include OAuth token
- [ ] 401 errors show "Please login with OAuth" message
- [ ] Tokens persist across app restarts
- [ ] Logout clears tokens completely
- [ ] Token refresh works automatically

## Architecture Benefits

1. **Secure by Default**: Uses Apple's security best practices
2. **Backward Compatible**: Falls back to UserDefaults tokens during migration
3. **Reactive UI**: SwiftUI automatically updates based on auth state
4. **Modern Swift**: Uses async/await and structured concurrency
5. **Singleton Pattern**: Consistent auth state across the app
6. **Error Handling**: Comprehensive error types and user feedback
7. **Automatic Refresh**: Transparent token refresh without user action

## Future Enhancements

- [ ] Display user's name/email in UI after login
- [ ] Add organization/project picker after authentication
- [ ] Implement token migration from UserDefaults to Keychain
- [ ] Add "Remember Me" preference
- [ ] Support multiple Sentry accounts
- [ ] Add OAuth scope permission display
- [ ] Implement biometric authentication (Touch ID/Face ID) for token access

## Troubleshooting

### Login Button Does Nothing
- Check Console.app for errors
- Verify URL scheme is registered
- Ensure OAuth credentials are configured

### Redirect Fails After Authentication
- Verify redirect URI matches exactly: `sentry-replay-debugger://oauth/callback`
- Check URL scheme spelling in Xcode project
- Ensure app is running when callback occurs

### 401 Unauthorized After Login
- Verify OAuth scopes include required permissions
- Check that access token is being saved to Keychain
- Confirm token is being included in Authorization header

### Token Not Persisting
- Check Keychain entitlements are properly configured
- Verify bundle identifier matches: `com.sentry.replay-debugger`
- Review Console.app for Keychain access errors

## Documentation

For detailed setup instructions, see: `OAUTH_SETUP_INSTRUCTIONS.md`

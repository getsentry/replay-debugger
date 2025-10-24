# Next Steps: OAuth Authentication Setup

## Immediate Action Items

### ⚠️ Required: Configure OAuth in Xcode (5 minutes)

Since the URL scheme cannot be configured programmatically, you must do this manually in Xcode:

1. **Open Xcode Project**
   ```bash
   open SentryReplayDebugger.xcodeproj
   ```

2. **Register URL Scheme**
   - Select project in Navigator
   - Select "SentryReplayDebugger" target
   - Click "Info" tab
   - Expand "URL Types" (or add if missing)
   - Click "+" to add new URL Type:
     - **Identifier**: `com.sentry.replay-debugger.oauth`
     - **URL Schemes**: `sentry-replay-debugger`
     - **Role**: `Editor`

3. **Verify Entitlements**
   - Select "Signing & Capabilities" tab
   - Confirm "App Sandbox" shows:
     - ✅ Network: Outgoing Connections (Client)
     - ✅ Keychain Sharing (with group: `com.sentry.replay-debugger`)

### ⚠️ Required: Get Sentry OAuth Credentials (10 minutes)

1. **Create OAuth Application in Sentry**
   - Go to: https://sentry.io/settings/[YOUR_ORG]/developer-settings/
   - Click "New Internal Integration" or "New Public Application"
   - Fill in:
     - **Name**: Sentry Replay Debugger
     - **Redirect URL**: `sentry-replay-debugger://oauth/callback`
     - **Scopes**: Select at least:
       - ✅ `project:read`
       - ✅ `org:read`
       - ✅ `event:read` (if needed for replay data)

2. **Copy Credentials**
   - After creating, copy:
     - Client ID
     - Client Secret

3. **Update Code**
   - Open: `SentryReplayDebugger/Services/SentryOAuthService.swift`
   - Replace lines 10-11:
     ```swift
     private let clientId = "YOUR_SENTRY_CLIENT_ID"        // ← Paste Client ID here
     private let clientSecret = "YOUR_SENTRY_CLIENT_SECRET" // ← Paste Client Secret here
     ```

### ✅ Optional: Verify Implementation

1. **Build the Project**
   ```bash
   xcodebuild -project SentryReplayDebugger.xcodeproj -scheme SentryReplayDebugger -configuration Debug
   ```

2. **Run in Xcode**
   - Press `⌘R` or click Run
   - You should see the Login button in the toolbar

3. **Test OAuth Flow**
   - Click the Login button
   - Browser should open with Sentry OAuth page
   - After authorizing, app should show Logout button
   - Try fetching a replay to verify authentication works

## Implementation Summary

### ✅ Completed Tasks

- [x] Created `KeychainManager.swift` for secure token storage
- [x] Created `SentryOAuthService.swift` for OAuth flow
- [x] Added Login/Logout button to toolbar UI
- [x] Updated `SentryAPIService.swift` to use Keychain tokens
- [x] Added Keychain entitlements to `.entitlements` file
- [x] Added URL callback handler to `ContentView`
- [x] Added external event handling to `SentryReplayDebuggerApp`
- [x] Implemented automatic token refresh
- [x] Added 401 Unauthorized error handling

### ⏳ Pending Manual Steps

- [ ] Register URL scheme in Xcode project Info
- [ ] Create Sentry OAuth application
- [ ] Configure Client ID and Client Secret in code
- [ ] Test OAuth login flow
- [ ] Verify API requests use OAuth token

## File Changes Overview

### New Files Created (2)
```
SentryReplayDebugger/
├── Services/
│   └── SentryOAuthService.swift          ← OAuth flow management
└── Utilities/
    └── KeychainManager.swift              ← Secure token storage
```

### Modified Files (4)
```
SentryReplayDebugger/
├── ContentView.swift                      ← Added Login/Logout UI
├── SentryReplayDebuggerApp.swift         ← Added URL event handling
├── Services/
│   └── SentryAPIService.swift            ← Uses Keychain tokens
└── SentryReplayDebugger.entitlements     ← Added Keychain access
```

### Documentation Files (3)
```
├── OAUTH_SETUP_INSTRUCTIONS.md           ← Detailed setup guide
├── OAUTH_IMPLEMENTATION_SUMMARY.md       ← Technical implementation details
└── NEXT_STEPS.md                         ← This file
```

## Quick Reference

### OAuth Endpoints (Sentry)
- **Authorization**: `https://sentry.io/oauth/authorize/`
- **Token**: `https://sentry.io/oauth/token/`
- **Redirect URI**: `sentry-replay-debugger://oauth/callback`

### Key Components
- **OAuth Service**: `SentryOAuthService.shared`
- **Keychain Manager**: `KeychainManager.shared`
- **Auth State**: `oauthService.isAuthenticated` (Boolean)

### UI Flow
```
User clicks "Login"
    ↓
Browser opens Sentry OAuth page
    ↓
User authorizes application
    ↓
App receives callback: sentry-replay-debugger://oauth/callback?code=...
    ↓
App exchanges code for tokens
    ↓
Tokens saved to Keychain
    ↓
UI shows "Logout" button
    ↓
API requests include Bearer token
```

## Need Help?

### Common Issues

**Q: Login button doesn't open browser**
- A: Check Console.app for errors. Verify URL scheme is registered.

**Q: Browser opens but doesn't redirect back**
- A: Ensure redirect URI matches exactly in Sentry and code.

**Q: 401 error after logging in**
- A: Verify OAuth scopes include required permissions.

**Q: Token doesn't persist after app restart**
- A: Check Keychain entitlements and bundle identifier.

### Debug Logging

Enable debug logging in `SentryOAuthService.swift` by adding:
```swift
#if DEBUG
NSLog("🔐 OAuth: Starting login flow")
NSLog("🔐 OAuth: Token exchange successful")
NSLog("🔐 OAuth: Token saved to Keychain")
#endif
```

### Console Commands

Check if app can access Keychain:
```bash
security find-generic-password -s "com.sentry.replay-debugger" -a "sentry-access-token"
```

### Testing Without OAuth

For development, you can temporarily use the old UserDefaults method:
```swift
UserDefaults.standard.set("YOUR_BEARER_TOKEN", forKey: "SentryAuthToken")
```

The code maintains backward compatibility with this approach.

## Success Criteria

You'll know it's working when:
- ✅ Login button appears in toolbar
- ✅ Clicking Login opens Sentry OAuth page in browser
- ✅ After authorizing, app shows Logout button
- ✅ Fetching replay data works without authentication errors
- ✅ Token persists after closing and reopening the app
- ✅ Clicking Logout clears the session

## Additional Resources

- **Sentry OAuth Documentation**: https://docs.sentry.io/api/auth/
- **Apple ASWebAuthenticationSession**: https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession
- **Keychain Services**: https://developer.apple.com/documentation/security/keychain_services

---

**Ready to proceed?** Start with the "Required" sections above, then build and test!

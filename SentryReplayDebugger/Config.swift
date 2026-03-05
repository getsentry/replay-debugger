import Foundation

enum Config {
    static var sentryDSN: String {
        // 1. Read from Info.plist (injected at build time via SENTRY_DSN build setting)
        if let plistDSN = Bundle.main.infoDictionary?["SentryDSN"] as? String,
           !plistDSN.isEmpty,
           !plistDSN.hasPrefix("$(") {
            return plistDSN
        }

        // 2. Fallback to environment variable (for local development via Xcode scheme)
        if let envDSN = ProcessInfo.processInfo.environment["SENTRY_DSN"], !envDSN.isEmpty {
            return envDSN
        }

        print("⚠️ Warning: SENTRY_DSN not configured. Sentry will not track errors.")
        print("   For CI/release builds: set SENTRY_DSN in your build environment.")
        print("   For local development: Edit Scheme > Run > Arguments > Environment Variables.")
        return ""
    }

    // MARK: - OAuth2 (PKCE)

    /// OAuth client ID from Sentry Developer Settings
    /// Create an application at: https://sentry.io/settings/YOUR_ORG/developer-settings/
    static let oauthClientId = "PLACEHOLDER_CLIENT_ID"

    static let oauthAuthorizeURL = "https://sentry.io/oauth/authorize/"
    static let oauthTokenURL = "https://sentry.io/oauth/token/"
    static let oauthRedirectURI = "sentry-replay-debugger://callback"
}

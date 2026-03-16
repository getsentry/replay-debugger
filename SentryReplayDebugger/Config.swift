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

    // MARK: - OAuth2 (ILOC)

    /// Instance-level OAuth Client credentials.
    /// Injected at build time via OAUTH_CLIENT_ID / OAUTH_CLIENT_SECRET build settings.
    /// For local development, set these in Config.xcconfig.
    /// For CI, they are passed as xcargs from GH Action secrets.
    static var oauthClientId: String {
        Bundle.main.object(forInfoDictionaryKey: "OAUTH_CLIENT_ID") as? String ?? ""
    }

    static var oauthClientSecret: String {
        Bundle.main.object(forInfoDictionaryKey: "OAUTH_CLIENT_SECRET") as? String ?? ""
    }

    static let oauthAuthorizeURL = "https://bv.ngrok.io/oauth/authorize/"
    static let oauthTokenURL = "https://bv.ngrok.io/oauth/token/"
    static let oauthRedirectURI = "sentry-replay-debugger://sentry.io/callback"
}

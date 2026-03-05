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
}

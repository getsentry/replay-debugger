import Foundation

enum Config {
    /// Sentry DSN for error tracking
    /// Get your DSN from: https://sentry.io/settings/YOUR_ORG/projects/YOUR_PROJECT/keys/
    ///
    /// To configure:
    /// 1. In Xcode, go to Product > Scheme > Edit Scheme
    /// 2. Select "Run" on the left sidebar
    /// 3. Go to "Arguments" tab
    /// 4. Under "Environment Variables", add:
    ///    Name: SENTRY_DSN
    ///    Value: your-actual-sentry-dsn
    static var sentryDSN: String {
        // Read from environment variable
        if let envDSN = ProcessInfo.processInfo.environment["SENTRY_DSN"], !envDSN.isEmpty {
            return envDSN
        }

        // If not set, return empty string (Sentry won't initialize)
        print("⚠️ Warning: SENTRY_DSN not configured. Sentry will not track errors.")
        print("   To configure: Edit Scheme > Run > Arguments > Environment Variables")
        print("   Add SENTRY_DSN with your DSN from Sentry project settings.")
        return ""
    }
}

import SwiftUI
import Sentry

@main
struct SentryReplayDebuggerApp: App {
    init() {
        // Only initialize Sentry if DSN is configured
        let dsn = Config.sentryDSN
        guard !dsn.isEmpty else {
            return
        }

        SentrySDK.start { options in
            options.dsn = dsn
            options.debug = true // Enable debug when first installing is always helpful

            // Set tracesSampleRate to 1.0 to capture 100% of transactions for performance monitoring.
            // We recommend adjusting this value in production.
            options.tracesSampleRate = 1.0

            // Attach stack traces to all messages logged
            options.attachStacktrace = true
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)
    }
}
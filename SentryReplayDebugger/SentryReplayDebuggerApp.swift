import SwiftUI
import Sentry

@main
struct SentryReplayDebuggerApp: App {
    @StateObject private var authService = AuthService.shared

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
            Group {
                if authService.isAuthenticated {
                    ContentView()
                } else {
                    LoginView(authService: authService)
                }
            }
            .environmentObject(authService)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .appInfo) {
                if authService.isAuthenticated {
                    Button("Sign Out") {
                        authService.logout()
                    }
                }
            }
        }
    }
}
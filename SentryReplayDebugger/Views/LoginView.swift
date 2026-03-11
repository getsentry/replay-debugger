import SwiftUI

struct LoginView: View {
    static let brandPurple = Color(.displayP3, red: 0.438, green: 0.332, blue: 0.964)

    @ObservedObject var authService: AuthService

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)

                VStack(spacing: 8) {
                    Text("Replay Debugger")
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                if authService.isLoading {
                    ProgressView("Authenticating…")
                        .controlSize(.small)
                } else {
                    Button(action: startLogin) {
                        Text("Sign in to Sentry")
                            .frame(maxWidth: 220)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(Self.brandPurple)
                    .keyboardShortcut(.defaultAction)
                }

                if let error = authService.errorMessage {
                    Label(error, systemImage: "exclamation.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(40)
            .frame(width: 380)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .toolbar(.hidden, for: .windowToolbar)
    }

    private func startLogin() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        authService.login(anchor: window)
    }
}

#Preview("Login") {
    LoginView(authService: AuthService.shared)
        .frame(width: 500, height: 450)
}

#Preview("Login - Error") {
    LoginView(authService: {
        let service = AuthService.shared
        service.errorMessage = "Unable to connect to Sentry"
        return service
    }())
    .frame(width: 500, height: 450)
}

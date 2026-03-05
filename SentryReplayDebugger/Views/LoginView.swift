import SwiftUI

struct LoginView: View {
    @ObservedObject var authService: AuthService

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)

                VStack(spacing: 8) {
                    Text("Sentry Replay Debugger")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Sign in to access your replay data")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                if authService.isLoading {
                    ProgressView("Authenticating…")
                        .controlSize(.small)
                } else {
                    Button(action: startLogin) {
                        Text("Sign in with Sentry")
                            .frame(maxWidth: 220)
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func startLogin() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first else { return }
        authService.login(anchor: window)
    }
}

#Preview {
    LoginView(authService: AuthService.shared)
}

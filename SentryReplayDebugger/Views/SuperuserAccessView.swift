import SwiftUI

struct SuperuserAccessView: View {
    @Binding var isPresented: Bool
    let onSuccess: () -> Void

    @State private var password: String = ""
    @State private var selectedCategory: SuperuserAccessCategory = .debugging
    @State private var reason: String = ""
    @State private var errorText: String?
    @State private var isLoading = true
    @State private var isAuthenticating = false
    @State private var showWebAuthn = false
    @State private var webAuthnData: String?
    @State private var challengeJSON: String?
    @State private var pendingSessionLogin = false
    @State private var has2FA = false

    private var userEmail: String? {
        AuthService.shared.userProfile?.email
    }

    private var isReasonValid: Bool {
        reason.count >= 4 && reason.count <= 128
    }

    private var needsPassword: Bool {
        !has2FA
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Superuser Access Required")
                .font(.headline)

            Text("You are accessing a resource that requires superuser re-authentication.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let email = userEmail {
                Text("Authenticating as \(email)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if needsPassword {
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            Picker("Category", selection: $selectedCategory) {
                ForEach(SuperuserAccessCategoryGroup.all, id: \.name) { group in
                    Section(group.name) {
                        ForEach(group.categories, id: \.rawValue) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                }
            }
            .pickerStyle(.menu)

            TextField("e.g. Investigating issue PROJ-1234", text: $reason)
                .textFieldStyle(.roundedBorder)

            Text("We recommend linking to a ticket (e.g. Zendesk, Linear, or GitHub)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if isAuthenticating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(showWebAuthn ? "Tap your security key..." : "Fetching challenge...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Authenticate") {
                    authenticate()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!isReasonValid || (needsPassword && password.isEmpty) || isLoading || isAuthenticating)
            }
        }
        .padding(24)
        .frame(width: 460)
        .task {
            do {
                try await SuperuserService.shared.seedCSRF()
                let result = try await SuperuserService.shared.fetchAuthenticators()
                if case .webAuthn(let challenge, let data) = result {
                    has2FA = true
                    challengeJSON = challenge
                    webAuthnData = data
                }
            } catch {
                errorText = error.localizedDescription
            }
            isLoading = false
        }
        .background {
            if showWebAuthn, let webAuthnData {
                WebAuthnBridgeView(
                    webAuthnData: webAuthnData,
                    onSuccess: { response in
                        handleWebAuthnSuccess(response)
                    },
                    onError: { error in
                        handleWebAuthnError(error)
                    }
                )
                .frame(width: 0, height: 0)
            }
        }
    }

    private func authenticate() {
        isAuthenticating = true
        errorText = nil
        showWebAuthn = false
        pendingSessionLogin = false

        Task {
            do {
                if has2FA {
                    // 2FA — trigger WebAuthn for login
                    pendingSessionLogin = true
                    showWebAuthn = true
                } else {
                    // No 2FA — login with just password
                    guard let email = userEmail else {
                        throw SuperuserError.invalidResponse
                    }
                    try await SuperuserService.shared.loginWithPassword(
                        email: email, password: password
                    )
                    try await performElevation()
                }
            } catch {
                self.isAuthenticating = false
                self.password = ""
                self.errorText = error.localizedDescription
            }
        }
    }

    private func performElevation() async throws {
        // Re-fetch authenticators for the elevation step (now using session cookie)
        let result = try await SuperuserService.shared.fetchAuthenticators()
        switch result {
        case .webAuthn(let challenge, let data):
            self.pendingSessionLogin = false
            self.challengeJSON = challenge
            self.webAuthnData = data
            self.showWebAuthn = true
        case .noAuthenticator:
            try await SuperuserService.shared.elevateSimple(
                category: selectedCategory,
                reason: reason
            )
            isPresented = false
            onSuccess()
        }
    }

    private func handleWebAuthnSuccess(_ response: WebAuthnResponse) {
        guard let challengeJSON else {
            errorText = "Missing challenge data"
            isAuthenticating = false
            return
        }

        Task {
            do {
                if pendingSessionLogin {
                    // Complete login with 2FA
                    try await SuperuserService.shared.loginWith2FA(
                        challengeJSON: challengeJSON,
                        webAuthnResponse: response
                    )
                    self.pendingSessionLogin = false
                    self.showWebAuthn = false

                    // Session established — proceed to elevation
                    try await performElevation()
                } else {
                    // WebAuthn for superuser elevation
                    try await SuperuserService.shared.elevate(
                        challengeJSON: challengeJSON,
                        webAuthnResponse: response,
                        category: selectedCategory,
                        reason: reason
                    )
                    isPresented = false
                    onSuccess()
                }
            } catch {
                errorText = error.localizedDescription
                isAuthenticating = false
                showWebAuthn = false
            }
        }
    }

    private func handleWebAuthnError(_ error: String) {
        errorText = error
        isAuthenticating = false
        showWebAuthn = false
    }
}

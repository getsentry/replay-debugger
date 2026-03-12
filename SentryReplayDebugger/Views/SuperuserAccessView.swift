import SwiftUI

struct SuperuserAccessView: View {
    @Binding var isPresented: Bool
    let onSuccess: () -> Void

    @State private var selectedCategory: SuperuserAccessCategory = .debugging
    @State private var reason: String = ""
    @State private var errorText: String?
    @State private var isAuthenticating = false
    @State private var showWebAuthn = false
    @State private var webAuthnData: String?
    @State private var challengeJSON: String?

    private var isReasonValid: Bool {
        reason.count >= 4 && reason.count <= 128
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Superuser Access Required")
                .font(.headline)

            Text("You are accessing a resource that requires superuser re-authentication.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

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
                .disabled(!isReasonValid || isAuthenticating)
            }
        }
        .padding(24)
        .frame(width: 460)
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

        Task {
            do {
                let result = try await SuperuserService.shared.fetchAuthenticators()
                self.challengeJSON = result.challengeJSON
                self.webAuthnData = result.webAuthnData
                self.showWebAuthn = true
            } catch {
                self.isAuthenticating = false
                self.errorText = error.localizedDescription
            }
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
                try await SuperuserService.shared.elevate(
                    challengeJSON: challengeJSON,
                    webAuthnResponse: response,
                    category: selectedCategory,
                    reason: reason
                )
                isPresented = false
                onSuccess()
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

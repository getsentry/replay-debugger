import Foundation

@MainActor
class SuperuserService: ObservableObject {
    static let shared = SuperuserService()

    private let session = URLSession.shared

    private init() {}

    func fetchAuthenticators() async throws -> (challengeJSON: String, webAuthnData: String) {
        let url = URL(string: "https://sentry.io/api/0/authenticators/")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")

        if let token = await AuthService.shared.validAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SuperuserError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw SuperuserError.httpError(httpResponse.statusCode, body)
        }

        guard let authenticators = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SuperuserError.invalidResponse
        }

        guard let u2fEntry = authenticators.first(where: { ($0["id"] as? String) == "u2f" }) else {
            throw SuperuserError.noU2FAuthenticator
        }

        guard let challenge = u2fEntry["challenge"] as? [String: Any],
              let webAuthnData = challenge["webAuthnAuthenticationData"] as? String else {
            throw SuperuserError.missingChallengeData
        }

        let challengeData = try JSONSerialization.data(withJSONObject: challenge)
        let challengeJSON = String(data: challengeData, encoding: .utf8) ?? "{}"

        return (challengeJSON: challengeJSON, webAuthnData: webAuthnData)
    }

    func elevate(
        challengeJSON: String,
        webAuthnResponse: WebAuthnResponse,
        category: SuperuserAccessCategory,
        reason: String
    ) async throws {
        let url = URL(string: "https://sentry.io/api/0/auth/")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")

        if let token = await AuthService.shared.validAccessToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let responseDict: [String: String] = [
            "keyHandle": webAuthnResponse.keyHandle,
            "clientData": webAuthnResponse.clientData,
            "signatureData": webAuthnResponse.signatureData,
            "authenticatorData": webAuthnResponse.authenticatorData,
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseDict)
        let responseJSON = String(data: responseData, encoding: .utf8) ?? "{}"

        let body: [String: Any] = [
            "isSuperuserModal": true,
            "superuserAccessCategory": category.rawValue,
            "superuserReason": reason,
            "challenge": challengeJSON,
            "response": responseJSON,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SuperuserError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = json["detail"] as? String {
                throw SuperuserError.elevationFailed(detail)
            }
            throw SuperuserError.httpError(httpResponse.statusCode, body)
        }
    }
}

enum SuperuserError: Error, LocalizedError {
    case invalidResponse
    case httpError(Int, String)
    case noU2FAuthenticator
    case missingChallengeData
    case elevationFailed(String)
    case webAuthnFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, _):
            return "HTTP error \(code)"
        case .noU2FAuthenticator:
            return "No U2F/WebAuthn authenticator found on your account"
        case .missingChallengeData:
            return "Missing WebAuthn challenge data"
        case .elevationFailed(let detail):
            return "Superuser elevation failed: \(detail)"
        case .webAuthnFailed(let detail):
            return "WebAuthn authentication failed: \(detail)"
        }
    }
}

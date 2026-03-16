import Foundation

enum AuthenticatorResult {
    case webAuthn(challengeJSON: String, webAuthnData: String)
    case noAuthenticator
}

@MainActor
class SuperuserService: ObservableObject {
    static let shared = SuperuserService()

    private static let baseHost = "bv.ngrok.io"
    private static let baseURL = "https://\(baseHost)"

    private let session = URLSession.shared

    private init() {}

    // MARK: - Session Establishment

    func seedCSRF() async throws {
        let url = URL(string: "\(Self.baseURL)/api/0/auth/")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        let _ = try await session.data(for: request)
    }

    func loginWithPassword(email: String, password: String) async throws {
        guard let csrfToken = csrfCookieValue() else {
            throw SuperuserError.sessionNotEstablished
        }

        let url = URL(string: "\(Self.baseURL)/api/0/auth/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        request.setValue("\(Self.baseURL)/", forHTTPHeaderField: "Referer")
        request.setValue(csrfToken, forHTTPHeaderField: "X-CSRFToken")

        let loginBody: [String: String] = [
            "username": email,
            "password": password,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: loginBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SuperuserError.httpError(code, body)
        }
    }

    func loginWith2FA(
        challengeJSON: String,
        webAuthnResponse: WebAuthnResponse
    ) async throws {
        guard let csrfToken = csrfCookieValue() else {
            throw SuperuserError.sessionNotEstablished
        }

        let responseDict: [String: String] = [
            "keyHandle": webAuthnResponse.keyHandle,
            "clientData": webAuthnResponse.clientData,
            "signatureData": webAuthnResponse.signatureData,
            "authenticatorData": webAuthnResponse.authenticatorData,
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseDict)
        let responseJSON = String(data: responseData, encoding: .utf8) ?? "{}"

        let url = URL(string: "\(Self.baseURL)/api/0/auth/")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        request.setValue("\(Self.baseURL)/", forHTTPHeaderField: "Referer")
        request.setValue(csrfToken, forHTTPHeaderField: "X-CSRFToken")

        let loginBody: [String: Any] = [
            "challenge": challengeJSON,
            "response": responseJSON,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: loginBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw SuperuserError.httpError(code, body)
        }
    }

    // MARK: - Authenticators

    func fetchAuthenticators() async throws -> AuthenticatorResult {
        let url = URL(string: "\(Self.baseURL)/api/0/authenticators/")!
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
            return .noAuthenticator
        }

        guard let challenge = u2fEntry["challenge"] as? [String: Any],
              let webAuthnData = challenge["webAuthnAuthenticationData"] as? String else {
            throw SuperuserError.missingChallengeData
        }

        let challengeData = try JSONSerialization.data(withJSONObject: challenge)
        let challengeJSON = String(data: challengeData, encoding: .utf8) ?? "{}"

        return .webAuthn(challengeJSON: challengeJSON, webAuthnData: webAuthnData)
    }

    // MARK: - Elevation

    func elevate(
        challengeJSON: String,
        webAuthnResponse: WebAuthnResponse,
        category: SuperuserAccessCategory,
        reason: String
    ) async throws {
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
        try await sendElevateRequest(body: body)
    }

    func elevateSimple(
        category: SuperuserAccessCategory,
        reason: String
    ) async throws {
        let body: [String: Any] = [
            "isSuperuserModal": true,
            "superuserAccessCategory": category.rawValue,
            "superuserReason": reason,
        ]
        try await sendElevateRequest(body: body)
    }

    // MARK: - Private

    private func sendElevateRequest(body: [String: Any]) async throws {
        guard let csrfToken = csrfCookieValue() else {
            throw SuperuserError.sessionNotEstablished
        }

        let url = URL(string: "\(Self.baseURL)/api/0/auth/")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Accept")
        request.setValue("\(Self.baseURL)/", forHTTPHeaderField: "Referer")
        request.setValue(csrfToken, forHTTPHeaderField: "X-CSRFToken")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SuperuserError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let responseBody = String(data: data, encoding: .utf8) ?? "<no body>"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = json["detail"] as? String {
                throw SuperuserError.elevationFailed(detail)
            }
            throw SuperuserError.httpError(httpResponse.statusCode, responseBody)
        }
    }

    private func cookieValue(named baseName: String) -> String? {
        guard let url = URL(string: Self.baseURL),
              let cookies = HTTPCookieStorage.shared.cookies(for: url) else {
            return nil
        }
        // Dev server prefixes cookie names with "devserver-"
        return cookies.first { $0.name == baseName || $0.name == "devserver-\(baseName)" }?.value
    }

    private func csrfCookieValue() -> String? {
        cookieValue(named: "sc")
    }

    static func clearSessionCookies() {
        guard let url = URL(string: baseURL),
              let cookies = HTTPCookieStorage.shared.cookies(for: url) else {
            return
        }
        for cookie in cookies {
            HTTPCookieStorage.shared.deleteCookie(cookie)
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
    case sessionNotEstablished

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
        case .sessionNotEstablished:
            return "Session not established — enter your password to authenticate"
        }
    }
}

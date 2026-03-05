import Foundation
import AuthenticationServices
import CryptoKit

enum AuthError: LocalizedError {
    case invalidCallbackURL
    case missingAuthCode
    case tokenExchangeFailed(String)
    case noToken

    var errorDescription: String? {
        switch self {
        case .invalidCallbackURL:
            return "Invalid callback URL from Sentry"
        case .missingAuthCode:
            return "No authorization code received"
        case .tokenExchangeFailed(let detail):
            return "Token exchange failed: \(detail)"
        case .noToken:
            return "Not authenticated"
        }
    }
}

struct OAuthTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiresIn: Int?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
    }
}

@MainActor
class AuthService: ObservableObject {
    static let shared = AuthService()

    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let clientId = Config.oauthClientId
    private let authorizeURL = Config.oauthAuthorizeURL
    private let tokenURL = Config.oauthTokenURL
    private let redirectURI = Config.oauthRedirectURI

    private static let accessTokenKey = "oauth_access_token"
    private static let refreshTokenKey = "oauth_refresh_token"
    private static let tokenExpiryKey = "oauth_token_expiry"

    private var codeVerifier: String?
    private var webAuthSession: ASWebAuthenticationSession?
    private var presentationContextProvider: WindowPresentationContextProvider?

    private init() {
        isAuthenticated = loadAccessToken() != nil
    }

    // MARK: - PKCE

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Login

    func login(anchor: ASPresentationAnchor) {
        let verifier = generateCodeVerifier()
        self.codeVerifier = verifier
        let challenge = generateCodeChallenge(from: verifier)

        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let url = components.url else {
            errorMessage = "Failed to build authorization URL"
            return
        }

        isLoading = true
        errorMessage = nil

        let callbackScheme = URL(string: redirectURI)?.scheme ?? "sentry-replay-debugger"

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false

                if let error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        return
                    }
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let callbackURL else {
                    self.errorMessage = AuthError.invalidCallbackURL.localizedDescription
                    return
                }

                await self.handleCallback(url: callbackURL)
            }
        }

        let contextProvider = WindowPresentationContextProvider(anchor: anchor)
        self.presentationContextProvider = contextProvider
        session.presentationContextProvider = contextProvider
        session.prefersEphemeralWebBrowserSession = false
        self.webAuthSession = session
        session.start()
    }

    // MARK: - Token Exchange

    private func handleCallback(url: URL) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            errorMessage = AuthError.missingAuthCode.localizedDescription
            return
        }

        guard let verifier = codeVerifier else {
            errorMessage = "Missing PKCE code verifier"
            return
        }

        isLoading = true

        do {
            let tokenResponse = try await exchangeCode(code, codeVerifier: verifier)
            saveTokens(tokenResponse)
            isAuthenticated = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        codeVerifier = nil
    }

    private func exchangeCode(_ code: String, codeVerifier: String) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "grant_type=authorization_code",
            "code=\(code)",
            "client_id=\(clientId)",
            "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)",
            "code_verifier=\(codeVerifier)",
        ].joined(separator: "&")

        request.httpBody = params.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.tokenExchangeFailed("Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    // MARK: - Token Refresh

    func refreshTokenIfNeeded() async -> Bool {
        guard let refreshToken = KeychainHelper.loadString(key: Self.refreshTokenKey) else {
            return false
        }

        if let expiryData = KeychainHelper.load(key: Self.tokenExpiryKey),
           let expiryString = String(data: expiryData, encoding: .utf8),
           let expiryInterval = Double(expiryString) {
            let expiry = Date(timeIntervalSince1970: expiryInterval)
            if expiry.timeIntervalSinceNow > 60 {
                return true
            }
        }

        do {
            let tokenResponse = try await refreshAccessToken(refreshToken)
            saveTokens(tokenResponse)
            return true
        } catch {
            NSLog("⚠️ Token refresh failed: \(error.localizedDescription)")
            await MainActor.run {
                isAuthenticated = false
            }
            return false
        }
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
            "client_id=\(clientId)",
        ].joined(separator: "&")

        request.httpBody = params.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.tokenExchangeFailed("Refresh failed")
        }

        return try JSONDecoder().decode(OAuthTokenResponse.self, from: data)
    }

    // MARK: - Token Storage

    private func saveTokens(_ response: OAuthTokenResponse) {
        KeychainHelper.saveString(key: Self.accessTokenKey, value: response.accessToken)

        if let refreshToken = response.refreshToken {
            KeychainHelper.saveString(key: Self.refreshTokenKey, value: refreshToken)
        }

        if let expiresIn = response.expiresIn {
            let expiry = Date().addingTimeInterval(Double(expiresIn))
            let expiryString = String(expiry.timeIntervalSince1970)
            KeychainHelper.saveString(key: Self.tokenExpiryKey, value: expiryString)
        }
    }

    nonisolated func loadAccessToken() -> String? {
        return KeychainHelper.loadString(key: Self.accessTokenKey)
    }

    func validAccessToken() async -> String? {
        let refreshed = await refreshTokenIfNeeded()
        guard refreshed else { return nil }
        return loadAccessToken()
    }

    func handleUnauthorized() {
        isAuthenticated = false
    }

    // MARK: - Logout

    func logout() {
        KeychainHelper.delete(key: Self.accessTokenKey)
        KeychainHelper.delete(key: Self.refreshTokenKey)
        KeychainHelper.delete(key: Self.tokenExpiryKey)
        isAuthenticated = false
        errorMessage = nil
    }
}

// MARK: - ASWebAuthenticationSession Presentation

private class WindowPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return anchor
    }
}

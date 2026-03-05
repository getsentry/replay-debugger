import Foundation
import AuthenticationServices

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
    private let clientSecret = Config.oauthClientSecret
    private let authorizeURL = Config.oauthAuthorizeURL
    private let tokenURL = Config.oauthTokenURL
    private let redirectURI = Config.oauthRedirectURI

    private static let accessTokenKey = "oauth_access_token"
    private static let refreshTokenKey = "oauth_refresh_token"
    private static let tokenExpiryKey = "oauth_token_expiry"

    private var webAuthSession: ASWebAuthenticationSession?
    private var presentationContextProvider: WindowPresentationContextProvider?

    private init() {
        isAuthenticated = loadAccessToken() != nil
    }

    // MARK: - Login

    func login(anchor: ASPresentationAnchor) {
        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
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

        isLoading = true

        do {
            let tokenResponse = try await exchangeCode(code)
            saveTokens(tokenResponse)
            isAuthenticated = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func exchangeCode(_ code: String) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        let encoded = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") ?? ""
        request.httpBody = encoded.data(using: .utf8)

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

    // MARK: - Token Expiry & Refresh

    nonisolated func isTokenExpired(bufferSeconds: TimeInterval = 60) -> Bool {
        guard let expiryString = KeychainHelper.loadString(key: Self.tokenExpiryKey),
              let expiryInterval = Double(expiryString) else {
            // No expiry stored — treat as expired to be safe
            return true
        }
        let expiry = Date(timeIntervalSince1970: expiryInterval)
        return expiry.timeIntervalSinceNow <= bufferSeconds
    }

    func refreshTokenIfNeeded() async -> Bool {
        guard isTokenExpired() else { return false }
        return await performTokenRefresh()
    }

    private func performTokenRefresh() async -> Bool {
        guard let token = KeychainHelper.loadString(key: Self.refreshTokenKey) else {
            return false
        }

        do {
            let tokenResponse = try await refreshAccessToken(token)
            saveTokens(tokenResponse)
            return true
        } catch {
            NSLog("⚠️ Token refresh failed: \(error.localizedDescription)")
            return false
        }
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret),
        ]
        let encoded = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") ?? ""
        request.httpBody = encoded.data(using: .utf8)

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
        // Proactive: refresh before expiry
        if let token = loadAccessToken(), !isTokenExpired() {
            return token
        }

        // Token expired or missing — try refresh
        if await performTokenRefresh() {
            return loadAccessToken()
        }

        return nil
    }

    /// Reactive 401 handler: attempt refresh and return new token, or sign out
    func handleUnauthorizedAndRetry() async -> String? {
        if await performTokenRefresh() {
            return loadAccessToken()
        }

        // Refresh failed — credentials are dead
        KeychainHelper.delete(key: Self.accessTokenKey)
        KeychainHelper.delete(key: Self.refreshTokenKey)
        KeychainHelper.delete(key: Self.tokenExpiryKey)
        isAuthenticated = false
        return nil
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

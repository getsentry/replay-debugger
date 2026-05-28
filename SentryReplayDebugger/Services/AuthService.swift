import AuthenticationServices
import Foundation

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
    @Published var userProfile: UserProfile?

    private let clientId = Config.oauthClientId
    private let clientSecret = Config.oauthClientSecret
    private let authorizeURL = Config.oauthAuthorizeURL
    private let tokenURL = Config.oauthTokenURL
    private let redirectURI = Config.oauthRedirectURI

    private static let accessTokenKey = "oauth_access_token"
    private static let refreshTokenKey = "oauth_refresh_token"
    private static let tokenExpiryKey = "oauth_token_expiry"
    private static let userProfileKey = "user_profile"

    private var webAuthSession: ASWebAuthenticationSession?
    private var presentationContextProvider: WindowPresentationContextProvider?

    private init() {
        let hasToken = loadAccessToken() != nil
        isAuthenticated = hasToken
        if hasToken {
            userProfile = Self.loadCachedProfile()
            Task { await fetchUserProfile() }
        }
    }

    // MARK: - Login

    private var pendingOAuthState: String?

    func login(anchor: ASPresentationAnchor) {
        let state = UUID().uuidString
        pendingOAuthState = state

        var components = URLComponents(string: authorizeURL)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "org:read project:read team:read event:read openid profile email"),
            URLQueryItem(name: "state", value: state),
        ]

        guard let url = components.url else {
            errorMessage = "Failed to build authorization URL"
            return
        }

        isLoading = true
        errorMessage = nil

        let callbackScheme = URL(string: redirectURI)?.scheme ?? "sentry-replay-debugger"

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) {
            [weak self] callbackURL, error in
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
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            errorMessage = AuthError.missingAuthCode.localizedDescription
            return
        }

        let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value
        guard returnedState == pendingOAuthState else {
            errorMessage = "OAuth state mismatch — possible CSRF attack"
            pendingOAuthState = nil
            return
        }
        pendingOAuthState = nil

        isLoading = true

        do {
            let tokenResponse = try await exchangeCode(code)
            saveTokens(tokenResponse)
            isAuthenticated = true
            errorMessage = nil
            await fetchUserProfile()
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

    func isTokenExpired(bufferSeconds: TimeInterval = 60) -> Bool {
        guard let expiryString = KeychainHelper.loadString(key: Self.tokenExpiryKey),
            let expiryInterval = Double(expiryString)
        else {
            // No expiry stored — assume valid (server may not send expires_in)
            return false
        }
        let expiry = Date(timeIntervalSince1970: expiryInterval)
        return expiry.timeIntervalSinceNow <= bufferSeconds
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
            httpResponse.statusCode == 200
        else {
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

    func loadAccessToken() -> String? {
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
        logout()
        return nil
    }

    // MARK: - User Profile

    func fetchUserProfile() async {
        do {
            let profile = try await SentryAPIService.shared.fetchUserProfile()
            userProfile = profile
            Self.cacheProfile(profile)
        } catch {
            NSLog("⚠️ Failed to fetch user profile: \(error.localizedDescription)")
        }
    }

    private static func cacheProfile(_ profile: UserProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            KeychainHelper.save(key: userProfileKey, data: data)
        }
    }

    private static func loadCachedProfile() -> UserProfile? {
        guard let data = KeychainHelper.load(key: userProfileKey) else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    // MARK: - Logout

    func logout() {
        KeychainHelper.delete(key: Self.accessTokenKey)
        KeychainHelper.delete(key: Self.refreshTokenKey)
        KeychainHelper.delete(key: Self.tokenExpiryKey)
        KeychainHelper.delete(key: Self.userProfileKey)
        isAuthenticated = false
        userProfile = nil
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

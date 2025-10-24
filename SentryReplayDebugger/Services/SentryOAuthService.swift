import Foundation
import AuthenticationServices

/// Manages OAuth 2.0 authentication flow with Sentry
class SentryOAuthService: NSObject, ObservableObject {
    static let shared = SentryOAuthService()

    // MARK: - OAuth Configuration
    // TODO: Replace these with actual Sentry OAuth configuration values
    // These values should be obtained from Sentry's OAuth app registration
    private let clientId = "YOUR_SENTRY_CLIENT_ID"
    private let clientSecret = "YOUR_SENTRY_CLIENT_SECRET" // Only needed for confidential clients
    private let authorizationEndpoint = "https://sentry.io/oauth/authorize/"
    private let tokenEndpoint = "https://sentry.io/oauth/token/"
    private let redirectURI = "sentry-replay-debugger://oauth/callback"

    // MARK: - Published Properties
    @Published var isAuthenticated: Bool = false
    @Published var userInfo: String?

    // MARK: - Private Properties
    private var authSession: ASWebAuthenticationSession?
    private let keychainManager = KeychainManager.shared

    private override init() {
        super.init()
        checkAuthenticationStatus()
    }

    // MARK: - Public Methods

    /// Check if user is currently authenticated
    func checkAuthenticationStatus() {
        if let token = keychainManager.getAccessToken() {
            if keychainManager.isTokenExpired() {
                // Try to refresh the token
                Task {
                    await refreshTokenIfNeeded()
                }
            } else {
                isAuthenticated = true
            }
        } else {
            isAuthenticated = false
        }
    }

    /// Start the OAuth login flow
    @MainActor
    func login() async throws {
        // Build authorization URL
        var components = URLComponents(string: authorizationEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "project:read org:read") // Adjust scopes as needed
        ]

        guard let authURL = components.url else {
            throw OAuthError.invalidURL
        }

        return try await withCheckedThrowingContinuation { continuation in
            // Create authentication session
            authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "sentry-replay-debugger"
            ) { [weak self] callbackURL, error in
                guard let self = self else { return }

                if let error = error {
                    // Check if user cancelled
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: OAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: OAuthError.authenticationFailed(error))
                    }
                    return
                }

                guard let callbackURL = callbackURL else {
                    continuation.resume(throwing: OAuthError.invalidCallback)
                    return
                }

                // Extract authorization code from callback URL
                guard let code = self.extractAuthorizationCode(from: callbackURL) else {
                    continuation.resume(throwing: OAuthError.noAuthorizationCode)
                    return
                }

                // Exchange code for tokens
                Task {
                    do {
                        try await self.exchangeCodeForToken(code: code)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            authSession?.presentationContextProvider = self
            authSession?.prefersEphemeralWebBrowserSession = false

            if !authSession!.start() {
                continuation.resume(throwing: OAuthError.sessionStartFailed)
            }
        }
    }

    /// Logout and clear all stored tokens
    func logout() {
        keychainManager.clearAllTokens()
        isAuthenticated = false
        userInfo = nil
    }

    /// Refresh the access token if it's expired
    func refreshTokenIfNeeded() async {
        guard keychainManager.isTokenExpired() else {
            return
        }

        guard let refreshToken = keychainManager.getRefreshToken() else {
            // No refresh token available, user needs to login again
            await MainActor.run {
                self.logout()
            }
            return
        }

        do {
            try await refreshAccessToken(refreshToken: refreshToken)
        } catch {
            // Refresh failed, logout user
            await MainActor.run {
                self.logout()
            }
        }
    }

    // MARK: - Private Methods

    private func extractAuthorizationCode(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return nil
        }

        return queryItems.first(where: { $0.name == "code" })?.value
    }

    private func exchangeCodeForToken(code: String) async throws {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Build request body
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret)
        ]

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OAuthError.tokenExchangeFailed
        }

        // Parse token response
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        // Store tokens in Keychain
        try keychainManager.saveAccessToken(tokenResponse.accessToken)

        if let refreshToken = tokenResponse.refreshToken {
            try keychainManager.saveRefreshToken(refreshToken)
        }

        // Calculate and store expiry time
        if let expiresIn = tokenResponse.expiresIn {
            let expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
            try keychainManager.saveTokenExpiry(expiry)
        }

        await MainActor.run {
            self.isAuthenticated = true
        }
    }

    private func refreshAccessToken(refreshToken: String) async throws {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Build request body
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "client_secret", value: clientSecret)
        ]

        request.httpBody = bodyComponents.query?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OAuthError.tokenRefreshFailed
        }

        // Parse token response
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        // Update tokens in Keychain
        try keychainManager.saveAccessToken(tokenResponse.accessToken)

        if let newRefreshToken = tokenResponse.refreshToken {
            try keychainManager.saveRefreshToken(newRefreshToken)
        }

        // Calculate and store new expiry time
        if let expiresIn = tokenResponse.expiresIn {
            let expiry = Date().addingTimeInterval(TimeInterval(expiresIn))
            try keychainManager.saveTokenExpiry(expiry)
        }

        await MainActor.run {
            self.isAuthenticated = true
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension SentryOAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first { $0.isKeyWindow } ?? NSApplication.shared.windows.first!
    }
}

// MARK: - Models

private struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - Errors

enum OAuthError: Error, LocalizedError {
    case invalidURL
    case userCancelled
    case authenticationFailed(Error)
    case invalidCallback
    case noAuthorizationCode
    case sessionStartFailed
    case tokenExchangeFailed
    case tokenRefreshFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid OAuth URL"
        case .userCancelled:
            return "Login cancelled by user"
        case .authenticationFailed(let error):
            return "Authentication failed: \(error.localizedDescription)"
        case .invalidCallback:
            return "Invalid callback URL"
        case .noAuthorizationCode:
            return "No authorization code received"
        case .sessionStartFailed:
            return "Failed to start authentication session"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for token"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        }
    }
}

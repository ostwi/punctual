import AppKit
import AuthenticationServices
import Foundation

enum AuthError: LocalizedError {
    case notConfigured
    case invalidCallback
    case stateMismatch
    case tokenExchangeFailed(String)
    case signedOut
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Google OAuth client ID is not configured (see OAuthConfig.swift)."
        case .invalidCallback: "Google returned an invalid sign-in response."
        case .stateMismatch: "Sign-in state validation failed."
        case .tokenExchangeFailed(let detail): "Token request failed: \(detail)"
        case .signedOut: "You are signed out."
        case .cancelled: "Sign-in was cancelled."
        }
    }
}

/// Owns the OAuth lifecycle: interactive sign-in (ASWebAuthenticationSession + PKCE),
/// silent access-token refresh, and sign-out/revocation.
@MainActor
final class GoogleAuthController {
    private let tokenStore = TokenStore()
    // Both must outlive session.start(), or the auth window vanishes immediately.
    private var activeSession: ASWebAuthenticationSession?
    private let presentationContext = AuthPresentationContext()
    private var refreshTask: Task<OAuthTokens, Error>?

    var storedTokens: OAuthTokens? { tokenStore.load() }

    // MARK: - Interactive sign-in

    func signIn() async throws -> OAuthTokens {
        guard OAuthConfig.isConfigured else { throw AuthError.notConfigured }

        let pkce = PKCE()
        let state = UUID().uuidString

        var components = URLComponents(url: OAuthConfig.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: OAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: OAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: OAuthConfig.scopes),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callback: .customScheme(OAuthConfig.redirectScheme)
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = presentationContext
            activeSession = session
            // An LSUIElement app is never "active"; without this the auth window opens behind everything.
            NSApp.activate(ignoringOtherApps: true)
            session.start()
        }
        activeSession = nil

        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state else { throw AuthError.stateMismatch }
        guard let code = items.first(where: { $0.name == "code" })?.value else { throw AuthError.invalidCallback }

        let tokens = try await requestTokens(parameters: [
            "code": code,
            "code_verifier": pkce.verifier,
            "client_id": OAuthConfig.clientID,
            "redirect_uri": OAuthConfig.redirectURI,
            "grant_type": "authorization_code",
        ], previousTokens: nil)
        tokenStore.save(tokens)
        return tokens
    }

    // MARK: - Token refresh

    /// Returns a token valid for at least the next 60 seconds, refreshing if needed.
    /// Concurrent callers share one in-flight refresh.
    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let tokens = tokenStore.load() else { throw AuthError.signedOut }
        if !forceRefresh && !tokens.isExpiringSoon { return tokens.accessToken }

        if let task = refreshTask { return try await task.value.accessToken }
        let task = Task<OAuthTokens, Error> {
            do {
                let refreshed = try await requestTokens(parameters: [
                    "refresh_token": tokens.refreshToken,
                    "client_id": OAuthConfig.clientID,
                    "grant_type": "refresh_token",
                ], previousTokens: tokens)
                tokenStore.save(refreshed)
                return refreshed
            } catch AuthError.tokenExchangeFailed(let detail) where detail.contains("invalid_grant") {
                // Token revoked (or expired while the consent screen is in Testing mode).
                tokenStore.clear()
                throw AuthError.signedOut
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value.accessToken
    }

    // MARK: - Sign-out

    func signOut() async {
        if let tokens = tokenStore.load() {
            var request = URLRequest(url: OAuthConfig.revocationEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "token=\(tokens.refreshToken)".data(using: .utf8)
            _ = try? await URLSession.shared.data(for: request)
        }
        tokenStore.clear()
    }

    // MARK: - Token endpoint

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Double
        let refreshToken: String?
        let idToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
        }
    }

    private func requestTokens(parameters: [String: String], previousTokens: OAuthTokens?) async throws -> OAuthTokens {
        var request = URLRequest(url: OAuthConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            throw AuthError.tokenExchangeFailed(body)
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return OAuthTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? previousTokens?.refreshToken ?? "",
            expiry: Date(timeIntervalSinceNow: decoded.expiresIn),
            email: decoded.idToken.flatMap(Self.email(fromIDToken:)) ?? previousTokens?.email
        )
    }

    /// Extracts the email claim from a JWT id_token without signature verification —
    /// the token came straight from Google's token endpoint over TLS, and it is
    /// used for display only.
    private static func email(fromIDToken idToken: String) -> String? {
        let segments = idToken.split(separator: ".")
        guard segments.count == 3,
              let payload = Data(base64URLEncoded: String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return nil }
        return json["email"] as? String
    }
}

/// A menu-bar app has no window to anchor the auth sheet to; an empty fresh
/// window is a valid anchor on macOS.
private final class AuthPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}

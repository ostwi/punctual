import Foundation

/// Google OAuth configuration.
///
/// The client ID below is a shared, public identifier for this app — for
/// installed apps (Google client type "iOS") there is no client secret, and
/// the authorization-code exchange is protected by PKCE, so committing it to
/// an open-source repo is safe and standard practice.
///
/// Maintainer setup (one time — see README "Maintainer: OAuth client" section):
/// 1. https://console.cloud.google.com → create a project.
/// 2. APIs & Services → Library → enable "Google Calendar API".
/// 3. OAuth consent screen → User type: **External**; scope
///    `calendar.readonly` is *sensitive*, so submit for Google verification
///    (homepage + privacy policy required) to lift the "unverified app"
///    warning and the 100-user cap.
/// 4. Credentials → Create credentials → OAuth client ID → Application type:
///    **iOS** (bundle ID: com.jakubostwald.Reminder).
/// 5. Paste the client ID below.
///
/// Forks that change the bundle ID must create their own client ID.
enum OAuthConfig {
    static let clientID = "REPLACE_ME.apps.googleusercontent.com"

    static var isConfigured: Bool { !clientID.hasPrefix("REPLACE_ME") }

    /// "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc"
    static var redirectScheme: String {
        let parts = clientID.split(separator: ".").map(String.init)
        return parts.reversed().joined(separator: ".")
    }

    static var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    static let scopes = "openid email https://www.googleapis.com/auth/calendar.readonly"

    static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revocationEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
}

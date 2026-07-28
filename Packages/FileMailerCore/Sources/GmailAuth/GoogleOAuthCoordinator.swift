@preconcurrency import AppAuth
import AppKit
import FileMailerDomain
import Foundation

public enum OAuthError: Error, LocalizedError, Sendable {
    case missingClientID
    case missingRedirectScheme
    case invalidRedirectScheme
    case discoveryFailed
    case cancelled
    case missingToken
    case invalidIDToken
    case invalidIssuer
    case invalidAudience
    case expiredIDToken
    case nonceMismatch
    case unverifiedEmail
    case missingIdentity
    case insufficientScopes
    case refreshFailed
    case revocationFailed

    public var errorDescription: String? {
        switch self {
        case .missingClientID: "Ajoutez GOOGLE_CLIENT_ID dans Config/Local.xcconfig."
        case .missingRedirectScheme:
            "Ajoutez GOOGLE_REDIRECT_SCHEME dans Config/Local.xcconfig."
        case .invalidRedirectScheme:
            "Le schéma de redirection Google OAuth est invalide."
        case .discoveryFailed: "Impossible de charger la configuration OpenID de Google."
        case .cancelled: "La connexion Google a été annulée."
        case .missingToken: "Google n’a pas renvoyé les jetons attendus."
        case .invalidIDToken: "Le jeton d’identité Google est invalide."
        case .invalidIssuer: "L’émetteur OpenID ne correspond pas à Google."
        case .invalidAudience: "Le jeton d’identité ne cible pas cette application."
        case .expiredIDToken: "Le jeton d’identité a expiré."
        case .nonceMismatch: "La vérification du nonce OAuth a échoué."
        case .unverifiedEmail: "L’adresse Gmail n’est pas vérifiée."
        case .missingIdentity: "Le compte Google ne fournit pas d’identité exploitable."
        case .insufficientScopes: "Google n’a pas accordé toutes les autorisations nécessaires."
        case .refreshFailed: "Le compte Gmail doit être reconnecté."
        case .revocationFailed: "Le retrait local est terminé, mais la révocation Google a échoué."
        }
    }
}

@MainActor
public final class GoogleOAuthCoordinator: OAuthCoordinating, @unchecked Sendable {
    public static let gmailSendScope = "https://www.googleapis.com/auth/gmail.send"
    public static let driveFileScope = "https://www.googleapis.com/auth/drive.file"

    public static let standardScopes = [
        OIDScopeOpenID,
        OIDScopeEmail,
        OIDScopeProfile,
        gmailSendScope
    ]

    private let store: any OAuthStateStoring
    private let presentingWindow: @MainActor @Sendable () -> NSWindow?
    private let session: URLSession
    private var authorizationFlow: (any OIDExternalUserAgentSession)?

    public init(
        store: any OAuthStateStoring,
        session: URLSession = .shared,
        presentingWindow: @escaping @MainActor @Sendable () -> NSWindow?
    ) {
        self.store = store
        self.session = session
        self.presentingWindow = presentingWindow
    }

    public func authorize(
        clientID: String,
        redirectScheme: String
    ) async throws -> GmailAccountSummary {
        try await authorize(
            clientID: clientID,
            redirectScheme: redirectScheme,
            additionalScopes: [],
            loginHint: nil
        )
    }

    public func authorize(
        clientID: String,
        redirectScheme: String,
        additionalScopes: Set<String>,
        loginHint: String?
    ) async throws -> GmailAccountSummary {
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRedirectScheme = redirectScheme.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmedClientID.isEmpty else { throw OAuthError.missingClientID }
        guard !trimmedRedirectScheme.isEmpty else {
            throw OAuthError.missingRedirectScheme
        }
        guard trimmedRedirectScheme.contains("."),
              let redirectURL = URL(
                string: "\(trimmedRedirectScheme):/oauth2redirect"
              )
        else {
            throw OAuthError.invalidRedirectScheme
        }
        guard let window = presentingWindow() else { throw OAuthError.cancelled }

        defer {
            authorizationFlow = nil
        }

        let issuer = URL(string: "https://accounts.google.com")!
        let configuration = try await discoverConfiguration(issuer: issuer)
        let requestedScopes = Array(
            Set(Self.standardScopes).union(additionalScopes)
        ).sorted()
        var additionalParameters = [
            "access_type": "offline",
            "include_granted_scopes": "true",
            "prompt": additionalScopes.isEmpty ? "select_account" : "consent"
        ]
        if let loginHint = loginHint?.trimmingCharacters(in: .whitespacesAndNewlines),
           !loginHint.isEmpty {
            additionalParameters["login_hint"] = loginHint
        }
        let request = OIDAuthorizationRequest(
            configuration: configuration,
            clientId: trimmedClientID,
            clientSecret: nil,
            scopes: requestedScopes,
            redirectURL: redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: additionalParameters
        )

        let state: OIDAuthState = try await withCheckedThrowingContinuation { continuation in
            authorizationFlow = OIDAuthState.authState(
                byPresenting: request,
                presenting: window
            ) { state, error in
                if let state {
                    continuation.resume(returning: state)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: OAuthError.cancelled)
                }
            }
        }

        guard let idToken = state.lastTokenResponse?.idToken else {
            throw OAuthError.missingToken
        }
        let claims = try Self.validateIDToken(
            idToken,
            clientID: trimmedClientID,
            expectedNonce: request.nonce
        )
        guard let subject = claims["sub"] as? String,
              let email = claims["email"] as? String
        else {
            throw OAuthError.missingIdentity
        }
        let accountID = GmailAccountID(rawValue: subject)
        let requiredScopes = Set(Self.standardScopes).union(additionalScopes)
        let granted = Self.resolvedGrantedScopes(
            state.scope,
            requestedScopes: requiredScopes
        )
        guard requiredScopes.isSubset(of: granted) else {
            throw OAuthError.insufficientScopes
        }
        try await store.save(AuthStateArchive.encode(state), for: accountID)
        return GmailAccountSummary(
            id: accountID,
            email: email,
            displayName: claims["name"] as? String,
            isDefault: false,
            lastUsedAt: Date(),
            grantedScopes: granted,
            authStatus: .connected
        )
    }

    public func remove(accountID: GmailAccountID, revoke: Bool) async throws {
        var revocationFailed = false
        if revoke, let data = try await store.load(for: accountID),
           let state = try? AuthStateArchive.decode(data),
           let token = state.refreshToken ?? state.lastTokenResponse?.accessToken {
            var components = URLComponents(string: "https://oauth2.googleapis.com/revoke")!
            components.queryItems = [URLQueryItem(name: "token", value: token)]
            var request = URLRequest(url: components.url!)
            request.httpMethod = "POST"
            request.setValue(
                "application/x-www-form-urlencoded",
                forHTTPHeaderField: "Content-Type"
            )
            do {
                let (_, response) = try await session.data(for: request)
                revocationFailed = !((response as? HTTPURLResponse).map {
                    (200..<300).contains($0.statusCode)
                } ?? false)
            } catch {
                revocationFailed = true
            }
        }
        try await store.delete(for: accountID)
        if revocationFailed { throw OAuthError.revocationFailed }
    }

    private func discoverConfiguration(issuer: URL) async throws -> OIDServiceConfiguration {
        try await withCheckedThrowingContinuation { continuation in
            OIDAuthorizationService.discoverConfiguration(forIssuer: issuer) {
                configuration, error in
                if let configuration {
                    continuation.resume(returning: configuration)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: OAuthError.discoveryFailed)
                }
            }
        }
    }

    /// OAuth 2.0 permits the token response to omit `scope` when it is unchanged
    /// from the authorization request. AppAuth exposes that case as `nil`, not as
    /// the requested scopes. Treat an omitted value as the original request while
    /// still rejecting an explicit, incomplete scope list.
    private static func resolvedGrantedScopes(
        _ responseScope: String?,
        requestedScopes: Set<String>
    ) -> Set<String> {
        let scopes = Set(
            (responseScope ?? "")
                .split(separator: " ")
                .map { normalizedGoogleScope(String($0)) }
        )
        return scopes.isEmpty ? requestedScopes : scopes
    }

    /// Google returns the two OpenID profile scopes using their API URL aliases
    /// in some token responses. Normalize them to the OpenID values we request
    /// before checking that the user accepted the authorization.
    private static func normalizedGoogleScope(_ scope: String) -> String {
        switch scope {
        case "https://www.googleapis.com/auth/userinfo.email":
            OIDScopeEmail
        case "https://www.googleapis.com/auth/userinfo.profile":
            OIDScopeProfile
        default:
            scope
        }
    }

    private static func validateIDToken(
        _ token: String,
        clientID: String,
        expectedNonce: String?
    ) throws -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payload = decodeBase64URL(String(parts[1])),
              let claims = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else {
            throw OAuthError.invalidIDToken
        }
        let issuer = claims["iss"] as? String
        guard issuer == "https://accounts.google.com" || issuer == "accounts.google.com" else {
            throw OAuthError.invalidIssuer
        }
        let audienceMatches: Bool
        if let audience = claims["aud"] as? String {
            audienceMatches = audience == clientID
        } else if let audiences = claims["aud"] as? [String] {
            audienceMatches = audiences.contains(clientID)
        } else {
            audienceMatches = false
        }
        guard audienceMatches else { throw OAuthError.invalidAudience }
        guard let expiration = claims["exp"] as? TimeInterval,
              Date(timeIntervalSince1970: expiration) > Date()
        else {
            throw OAuthError.expiredIDToken
        }
        if let expectedNonce {
            guard claims["nonce"] as? String == expectedNonce else {
                throw OAuthError.nonceMismatch
            }
        }
        guard claims["email_verified"] as? Bool == true else {
            throw OAuthError.unverifiedEmail
        }
        return claims
    }

    private static func decodeBase64URL(_ input: String) -> Data? {
        var value = input.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        value += String(repeating: "=", count: (4 - value.count % 4) % 4)
        return Data(base64Encoded: value)
    }
}

@preconcurrency import AppAuth
import FileMailerDomain
import Foundation

public actor AppAuthTokenProvider: TokenProviding {
    private let store: any OAuthStateStoring
    private var states: [GmailAccountID: OIDAuthState] = [:]

    public init(store: any OAuthStateStoring) {
        self.store = store
    }

    public func validAccessToken(for accountID: GmailAccountID) async throws -> String {
        let state = try await loadState(for: accountID)
        if let expiration = state.lastTokenResponse?.accessTokenExpirationDate,
           expiration.timeIntervalSinceNow < 60 {
            state.setNeedsTokenRefresh()
        }
        let token: String = try await withCheckedThrowingContinuation { continuation in
            state.performAction { accessToken, _, error in
                if let accessToken {
                    continuation.resume(returning: accessToken)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: OAuthError.refreshFailed)
                }
            }
        }
        try await store.save(AuthStateArchive.encode(state), for: accountID)
        return token
    }

    public func purge(accountID: GmailAccountID) async throws {
        states.removeValue(forKey: accountID)
        try await store.delete(for: accountID)
    }

    private func loadState(for accountID: GmailAccountID) async throws -> OIDAuthState {
        if let state = states[accountID] { return state }
        guard let data = try await store.load(for: accountID) else {
            throw OAuthError.refreshFailed
        }
        let state = try AuthStateArchive.decode(data)
        states[accountID] = state
        return state
    }
}

@preconcurrency import AppAuth
import FileMailerDomain
import Foundation
import Security

public protocol OAuthStateStoring: Sendable {
    func save(_ data: Data, for accountID: GmailAccountID) async throws
    func load(for accountID: GmailAccountID) async throws -> Data?
    func delete(for accountID: GmailAccountID) async throws
}

public enum OAuthStoreError: Error, LocalizedError, Sendable {
    case keychain(OSStatus)
    case archive

    public var errorDescription: String? {
        switch self {
        case let .keychain(status): "Erreur Trousseau \(status)."
        case .archive: "L’état OAuth ne peut pas être lu."
        }
    }
}

public actor KeychainOAuthStateStore: OAuthStateStoring {
    private let service: String

    public init(baseBundleID: String) {
        service = "\(baseBundleID).oauth"
    }

    public func save(_ data: Data, for accountID: GmailAccountID) throws {
        let query = baseQuery(accountID)
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw OAuthStoreError.keychain(status) }
    }

    public func load(for accountID: GmailAccountID) throws -> Data? {
        var query = baseQuery(accountID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw OAuthStoreError.keychain(status)
        }
        return data
    }

    public func delete(for accountID: GmailAccountID) throws {
        let status = SecItemDelete(baseQuery(accountID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OAuthStoreError.keychain(status)
        }
    }

    private func baseQuery(_ accountID: GmailAccountID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.rawValue,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}

enum AuthStateArchive {
    static func encode(_ state: OIDAuthState) throws -> Data {
        do {
            return try NSKeyedArchiver.archivedData(
                withRootObject: state,
                requiringSecureCoding: true
            )
        } catch {
            throw OAuthStoreError.archive
        }
    }

    static func decode(_ data: Data) throws -> OIDAuthState {
        do {
            guard let state = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: OIDAuthState.self,
                from: data
            ) else {
                throw OAuthStoreError.archive
            }
            return state
        } catch {
            throw OAuthStoreError.archive
        }
    }
}

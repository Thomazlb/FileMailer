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
        case let .keychain(status): FileMailerLocalization.current.format("Keychain error %@.", String(status))
        case .archive: FileMailerLocalization.current.string("The OAuth state could not be read.")
        }
    }
}

public actor KeychainOAuthStateStore: OAuthStateStoring {
    private let service: String
    private let usesProtectedKeychain: Bool

    public init(baseBundleID: String) {
        service = "\(baseBundleID).oauth"
        // Unsigned community builds can only use the file-based login keychain.
        let task = SecTaskCreateFromSelf(nil)
        usesProtectedKeychain = task.flatMap {
            SecTaskCopyValueForEntitlement($0, "com.apple.application-identifier" as CFString, nil)
        } is String
    }

    public func save(_ data: Data, for accountID: GmailAccountID) throws {
        let query = baseQuery(accountID, protected: usesProtectedKeychain)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let changes = [kSecValueData as String: data]
            status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        }
        guard status == errSecSuccess else { throw OAuthStoreError.keychain(status) }
    }

    public func load(for accountID: GmailAccountID) throws -> Data? {
        if usesProtectedKeychain, let data = try read(baseQuery(accountID, protected: true)) {
            return data
        }
        // Preserve sessions created by FileMailer before it selected a keychain explicitly.
        return try read(baseQuery(accountID, protected: false))
    }

    private func read(_ attributes: [String: Any]) throws -> Data? {
        var query = attributes
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
        for protected in usesProtectedKeychain ? [false, true] : [false] {
            let status = SecItemDelete(baseQuery(accountID, protected: protected) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw OAuthStoreError.keychain(status)
            }
        }
    }

    private func baseQuery(_ accountID: GmailAccountID, protected: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountID.rawValue,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
        if protected { query[kSecUseDataProtectionKeychain as String] = true }
        return query
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

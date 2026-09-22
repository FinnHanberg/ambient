import Foundation
import Security

/// The API key lives in the Keychain, not in a dotfile you have to create by
/// hand. A file at ~/.ambient/key is still read once, if one exists, and then
/// migrated and deleted.
enum Secrets {
    static let service = "com.hansonmethod.ambient"
    private static let account = "anthropic"

    static var legacyFile: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ambient/key")
    }

    static func load() -> String? {
        if let k = fromKeychain(), !k.isEmpty { return k }
        if let k = fromLegacyFile() {
            save(k)
            try? FileManager.default.removeItem(at: legacyFile)
            Log.say("secrets · migrated key from file to keychain")
            return k
        }
        return nil
    }

    static var present: Bool { load() != nil }

    @discardableResult
    static func save(_ raw: String) -> Bool {
        let key = clean(raw)
        guard !key.isEmpty else { return false }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(q as CFDictionary)
        try? FileManager.default.removeItem(at: legacyFile)
    }

    /// Tolerates what actually ends up on a clipboard: quotes, a shell-style
    /// assignment, stray whitespace, or a rich-text wrapper from TextEdit.
    static func clean(_ raw: String) -> String {
        var s = raw
        if s.hasPrefix("{\\rtf"), let r = s.range(of: "sk-ant") {
            s = String(s[r.lowerBound...])
            if let end = s.rangeOfCharacter(from: CharacterSet(charactersIn: "\\ \n\r\t}")) {
                s = String(s[..<end.lowerBound])
            }
        }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["ANTHROPIC_API_KEY=", "export ANTHROPIC_API_KEY=", "x-api-key:"] {
            if s.hasPrefix(prefix) { s = String(s.dropFirst(prefix.count)) }
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \n\r\t"))
        return s
    }

    static func looksLikeKey(_ s: String) -> Bool { clean(s).hasPrefix("sk-ant") }

    // MARK: -

    // MARK: - Shared keychain plumbing

    static func read(account: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func delete(account: String) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(q as CFDictionary)
    }

    private static func fromKeychain() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func fromLegacyFile() -> String? {
        guard let s = try? String(contentsOf: legacyFile, encoding: .utf8) else { return nil }
        let k = clean(s)
        return k.isEmpty ? nil : k
    }
}

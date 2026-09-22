import Foundation
import SwiftUI

/// Turning a purchase into a working app.
///
/// The provider is configuration, not code: the endpoint lives in
/// `~/.ambient/license.json` so Polar, Lemon Squeezy, Gumroad or a proxy of
/// your own can be swapped without shipping a new build. Locking a binary to
/// one payment vendor is the part of this that is hardest to undo later.
@MainActor
final class License: ObservableObject {
    static let shared = License()

    struct Config: Codable {
        /// Anything that accepts `{"key": "...", "product": "..."}` and answers
        /// with a JSON body containing a truthy `valid`, `activated` or `status`.
        var endpoint: String
        var product: String
        var buyURL: String
    }

    @Published private(set) var status: Status = .free
    @Published var busy = false

    enum Status: Equatable {
        case free
        case active(String)          // masked key
        case refused(String)
    }

    private var file: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ambient/license.json")
    }

    /// Absent config means the app simply has no paid tier yet — which is a
    /// legitimate state to ship in, not an error.
    var config: Config? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    var sellable: Bool { config != nil }

    private init() {
        if let key = Secrets.license(), !key.isEmpty {
            status = .active(License.mask(key))
            Usage.shared.pro = true
        }
    }

    static func mask(_ key: String) -> String {
        guard key.count > 8 else { return "••••" }
        return String(key.prefix(4)) + "••••" + String(key.suffix(4))
    }

    // MARK: - Activation

    func activate(_ raw: String) async {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        guard let config else {
            status = .refused("No licence server configured.")
            return
        }
        busy = true
        defer { busy = false }

        guard let url = URL(string: config.endpoint) else {
            status = .refused("Licence server address is not a URL.")
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try? JSONSerialization.data(
            withJSONObject: ["key": key, "product": config.product])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = code == 200 && License.looksValid(data)
            if ok {
                Secrets.saveLicense(key)
                status = .active(License.mask(key))
                Usage.shared.pro = true
                Log.say("licence · activated")
            } else {
                status = .refused(code == 404 || code == 400
                                  ? "That key wasn't recognised."
                                  : "Licence server said no (\(code)).")
                Log.say("licence · refused \(code)")
            }
        } catch {
            // Never strand a paying user on a flaky network.
            status = .refused("Couldn't reach the licence server.")
            Log.say("licence · unreachable — \(error.localizedDescription)")
        }
    }

    func deactivate() {
        Secrets.clearLicense()
        Usage.shared.pro = false
        status = .free
    }

    /// Tolerant on purpose: every vendor spells success differently, and this
    /// should not need a new build when one of them renames a field.
    private static func looksValid(_ data: Data) -> Bool {
        guard let any = try? JSONSerialization.jsonObject(with: data) else { return false }
        guard let obj = any as? [String: Any] else { return false }
        for key in ["valid", "activated", "success", "ok"] {
            if let b = obj[key] as? Bool { return b }
        }
        if let s = obj["status"] as? String {
            return ["granted", "active", "valid", "ok"].contains(s.lowercased())
        }
        // Nested one level — most vendors wrap the useful part.
        for value in obj.values {
            if let nested = value as? [String: Any] {
                for key in ["valid", "activated", "status"] {
                    if let b = nested[key] as? Bool, b { return true }
                    if let s = nested[key] as? String,
                       ["granted", "active", "valid"].contains(s.lowercased()) { return true }
                }
            }
        }
        return false
    }
}

extension Secrets {
    private static let licenceAccount = "licence"

    static func license() -> String? { read(account: licenceAccount) }
    static func saveLicense(_ key: String) { write(key, account: licenceAccount) }
    static func clearLicense() { delete(account: licenceAccount) }
}

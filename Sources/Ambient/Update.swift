import AppKit
import SwiftUI

/// Telling people a newer build exists.
///
/// Deliberately not an auto-updater. Friends testing a thing you are still
/// changing daily want to know a build landed, not to have it swapped under
/// them mid-pass. It reads a releases feed, compares versions and offers the
/// download page — nothing is installed behind anyone's back.
@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()

    @Published private(set) var latest: String?
    @Published private(set) var page: URL?
    @Published private(set) var checking = false

    /// Any URL returning GitHub's release shape. Configuration rather than a
    /// constant, so the feed can move without a new build.
    private var feed: URL? {
        let f = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ambient/updates.txt")
        if let raw = try? String(contentsOf: f, encoding: .utf8) {
            return URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var available: Bool {
        guard let latest else { return false }
        return Updates.compare(latest, current) == .orderedDescending
    }

    func check() async {
        guard let feed, !checking else { return }
        checking = true
        defer { checking = false }
        do {
            var req = URLRequest(url: feed)
            req.timeoutInterval = 10
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "accept")
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            let tag = (obj["tag_name"] as? String) ?? (obj["version"] as? String)
            latest = tag?.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            page = (obj["html_url"] as? String).flatMap(URL.init)
            Log.say("updates · latest=\(latest ?? "?") current=\(current)")
        } catch {
            Log.say("updates · check failed — \(error.localizedDescription)")
        }
    }

    /// Numeric, component-wise. String comparison calls 0.10 older than 0.9.
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r ? .orderedDescending : .orderedAscending }
        }
        return .orderedSame
    }
}

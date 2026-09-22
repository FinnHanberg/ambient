import Foundation

/// Always-on trace to ~/.ambient/debug.log.
///
/// This exists because two rounds of this build failed in ways that looked
/// identical from outside — a stuck state and a dead one both just sit there.
/// Every step of a turn writes a line, so the next failure names itself.
enum Log {
    private static let queue = DispatchQueue(label: "ambient.log")
    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f
    }()

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ambient/debug.log")
    }

    static func say(_ s: String) {
        let line = "\(fmt.string(from: Date()))  \(s)\n"
        queue.async {
            let dir = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Keep it from growing without bound across sessions.
    static func rotate() {
        queue.async {
            guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
                  size > 400_000 else { return }
            try? FileManager.default.removeItem(at: url)
        }
    }
}

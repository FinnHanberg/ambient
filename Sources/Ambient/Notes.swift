import AppKit

/// One thing you said while pointing at something.
struct Note: Codable, Identifiable {
    let id: UUID
    var text: String
    let context: String      // what the cursor was on, as far as the app will say
    let app: String
    var at: Date
    var shots: [String]      // frames from while you were speaking, cursor ringed

    init(id: UUID = UUID(), text: String, context: String, app: String,
         shots: [String] = []) {
        self.id = id
        self.text = text
        self.context = context
        self.app = app
        self.at = Date()
        self.shots = shots
    }
}

/// The running list of feedback from this pass.
///
/// This is the shape the tool actually wanted: you walk an interface, say what
/// is wrong as you point at it, and nothing interrupts you. Answering every
/// sentence out loud and asking permission per sentence is what made it
/// unusable for the job it exists to do.
@MainActor
final class Notes: ObservableObject {
    static let shared = Notes()

    @Published private(set) var items: [Note] = []

    private var file: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ambient/notes.json")
    }

    init() { load() }

    var count: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    func add(_ n: Note) {
        items.append(n)
        save()
        Log.say("note · \(items.count) · “\(n.text)” @ \(n.context)")
    }

    func clear() {
        items.removeAll()
        save()
    }

    /// Continue the previous note instead of starting a new one. The
    /// transcriber finalises on breath pauses, not on thoughts — "of, of, I want
    /// to start by increasing the opacity of this" arrived as three notes.
    func extendLast(with text: String, shots: [String]) -> Bool {
        guard var last = items.last,
              Date().timeIntervalSince(last.at) < 4 else { return false }
        last.text += " " + text
        last.shots.append(contentsOf: shots)
        items[items.count - 1] = last
        save()
        Log.say("note · extended · “\(last.text)”")
        return true
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    func undo() {
        guard !items.isEmpty else { return }
        items.removeLast()
        save()
    }

    /// The batch, as something a coding agent can act on.
    func bundle() -> String {
        guard !items.isEmpty else { return "" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        let apps = Set(items.map(\.app)).sorted().joined(separator: ", ")
        var out = "Feedback pass — \(items.count) note\(items.count == 1 ? "" : "s")"
        if !apps.isEmpty { out += " from \(apps)" }
        out += "\n\n"
        for (i, n) in items.enumerated() {
            out += "\(i + 1). \(n.text)\n"
            for shot in n.shots {
                out += "   screenshot: \(shot)\n"
            }
            if !n.context.isEmpty { out += "   context: \(n.context)\n" }
        }
        let withShots = items.filter { !$0.shots.isEmpty }.count
        if withShots > 0 {
            out += "\nRead the screenshots. Each is a crop taken at the instant a pointing "
            out += "word was spoken, with a ring drawn where the cursor was — so the ring is "
            out += "the thing being talked about."
        }
        return out
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: file)
    }

    private func load() {
        guard let data = try? Data(contentsOf: file),
              let saved = try? JSONDecoder().decode([Note].self, from: data) else { return }
        items = saved
    }
}

/// Delivering the batch to where the build actually lives.
enum Deliver {
    /// The Claude desktop app, if it's running.
    static func claude() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            let n = ($0.localizedName ?? "").lowercased()
            let b = ($0.bundleIdentifier ?? "").lowercased()
            return b.contains("claude") || n == "claude"
        }
    }

    /// Put the batch in front of you in Claude, but do not submit it. Choosing
    /// the conversation is not a decision this app should make — it guessed
    /// wrong often enough to be worse than useless.
    @MainActor
    static func paste(_ text: String) async -> (ok: Bool, text: String) {
        guard !text.isEmpty else { return (false, "nothing to paste") }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        guard let app = claude() else { return (false, "on the clipboard — Claude isn't running") }
        app.activate(options: [])
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            return (false, "on the clipboard")
        }
        key(src, 9, command: true)
        return (true, "pasted — press return to send")
    }

    @MainActor
    static func send(_ text: String) async -> (ok: Bool, text: String) {
        guard !text.isEmpty else { return (false, "nothing to send") }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        guard let app = claude() else {
            return (false, "Claude isn't running — batch is on the clipboard")
        }
        app.activate(options: [])
        try? await Task.sleep(nanoseconds: 450_000_000)

        guard let src = CGEventSource(stateID: .combinedSessionState) else {
            return (false, "on the clipboard — paste it yourself")
        }
        // ⌘V then Return.
        key(src, 9, command: true)      // v
        try? await Task.sleep(nanoseconds: 250_000_000)
        key(src, 36, command: false)    // return
        return (true, "sent to Claude")
    }

    private static func key(_ src: CGEventSource, _ code: CGKeyCode, command: Bool) {
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) else { return }
        if command { down.flags = .maskCommand; up.flags = .maskCommand }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}

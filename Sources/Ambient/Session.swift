import SwiftUI

/// The pass you are making: hold, say what's wrong while pointing at it, let go.
/// Nothing answers back, nothing asks permission, nothing interrupts. The notes
/// stack up until you send them.
@MainActor
final class Session: ObservableObject {
    static let shared = Session()

    enum Phase: Equatable {
        case idle
        case preparing(String)
        case failed(String)
        case hearing
        case thinking
        case noted(String)            // just captured
        case replying(String)         // a direct action wants confirming
        case acting
        case reported(String, Bool)
    }

    @Published var phase: Phase = .preparing("starting")
    @Published var transcript = ""
    @Published var binding = ""
    @Published var spoken = ""
    @Published var level: Double = 0
    @Published var awaitingConfirmation = false
    @Published var visible = false

    /// Optional surfaces, toggled by voice and remembered.
    @Published var showRail = UserDefaults.standard.bool(forKey: "ambient.rail") {
        didSet { UserDefaults.standard.set(showRail, forKey: "ambient.rail") }
    }
    @Published var showPill = UserDefaults.standard.bool(forKey: "ambient.pill") {
        didSet { UserDefaults.standard.set(showPill, forKey: "ambient.pill") }
    }

    /// Ambient's own surfaces are kept out of screenshots so they never occlude
    /// what a note is about. The exception is giving feedback on Ambient itself,
    /// where excluding them leaves a ring pointing at nothing.
    @Published var captureOverlays = UserDefaults.standard.bool(forKey: "ambient.captureSelf") {
        didSet { UserDefaults.standard.set(captureOverlays, forKey: "ambient.captureSelf") }
    }

    private(set) var reply: Reply?
    private var hideWork: DispatchWorkItem?
    private var bindingTimer: Timer?
    private var watchdog: DispatchWorkItem?
    private(set) var engagedNow = false
    /// The pass is running without the keys held.
    @Published var latched = false
    private var lastSegmentAt = Date.distantPast
    /// Raised when a pass finishes with something in it.
    var onPassEnded: (() -> Void)?

    private func arm(_ label: String, seconds: TimeInterval = 9) {
        watchdog?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Log.say("watchdog · \(label) never resolved")
            self.awaitingConfirmation = false
            self.phase = .reported("\(label) timed out — see ~/.ambient/debug.log", false)
            self.hide(after: 5)
        }
        watchdog = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    private func disarm() { watchdog?.cancel(); watchdog = nil }

    // MARK: - Visibility

    func show() { hideWork?.cancel(); visible = true }

    /// Explicit dismissal, from a close button.
    func dismiss() {
        hideWork?.cancel()
        watchdog?.cancel()
        awaitingConfirmation = false
        visible = false
        phase = .idle
        transcript = ""
        spoken = ""
        reply = nil
    }

    func hide(after seconds: TimeInterval) {
        hideWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, !self.awaitingConfirmation else { return }
            self.visible = false
            self.phase = .idle
            self.transcript = ""
            self.spoken = ""
            self.reply = nil
        }
        hideWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: w)
    }

    // MARK: - Engagement

    func engaged() {
        Voice.shared.stop()
        hideWork?.cancel()
        transcript = ""
        spoken = ""
        engagedNow = true
        phase = .hearing
        show()
        startBindingPreview()
        Recorder.shared.start()
    }

    func released() {
        Log.say("released")
        engagedNow = false
        stopBindingPreview()
        Recorder.shared.stop()
        // A pass ends by showing you what it caught, not by firing it somewhere.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            Task { @MainActor in
                guard let self, !self.engagedNow, !Notes.shared.isEmpty else { return }
                self.onPassEnded?()
            }
        }
        if case .hearing = phase { phase = .thinking }
    }

    /// Called once the listener has finished draining. Without it the island
    /// sat on "Reading" until something else happened to move it.
    func settle() {
        guard case .thinking = phase else { return }
        phase = .idle
        hide(after: 0.3)
    }

    private func startBindingPreview() {
        bindingTimer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let s = Pointer.shared.latest else { return }
                self.binding = await Pointer.shared.resolve(s).short
            }
        }
        RunLoop.main.add(t, forMode: .common)
        bindingTimer = t
    }

    private func stopBindingPreview() {
        bindingTimer?.invalidate(); bindingTimer = nil
    }

    // MARK: - A turn

    /// A pass is pure capture.
    ///
    /// Everything said while the keys are held becomes a note — full stop. No
    /// interpretation, no classification, no replies. The previous build ran
    /// every sentence through a chain deciding whether it was a note, a
    /// question or a command, and when it guessed "question" it answered with a
    /// canned refusal and recorded nothing. Asking "do you see this?" mid-pass
    /// produced an error message and an empty batch.
    ///
    /// One chord, one meaning. Talking to it happens in the review panel.
    func heard(_ u: Utterance) {
        let text = u.text.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.say("heard · “\(text)” words=\(u.words.count)")

        // Nothing transcribed: say nothing. A pass should never be interrupted
        // to be told that a breath was not a sentence.
        guard !text.isEmpty else { return }

        // Managing the batch is the one thing that isn't a note.
        if let control = Control.parse(text) {
            run(control)
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let (_, targets) = await Brain.resolve(u)
            await self.capture(u, context: targets.first)
        }
    }

    private func capture(_ u: Utterance, context: Target?) async {
        let id = UUID()
        let short = String(id.uuidString.prefix(8))

        // One frame per pointing word, taken from the instant that word was
        // said. "this is too tight and this should sit under that" yields three.
        var moments = u.words
            .filter { Brain.deictic.contains($0.text.lowercased()
                        .trimmingCharacters(in: .punctuationCharacters)) }
            .map(\.t)
        if moments.isEmpty, let mid = u.words.dropFirst(u.words.count / 2).first?.t {
            moments = [mid]                 // no pointing word: the middle of the sentence
        }
        if moments.isEmpty {
            // No stamped words at all — the transcript came through the volatile
            // path. The ring is still full of perfectly good frames, and every
            // one of these notes used to end up with no picture.
            moments = [Date()]
        }

        var shots: [String] = []
        for (i, moment) in moments.prefix(3).enumerated() {
            if let path = Recorder.shared.save(at: moment, id: "\(short)-\(i + 1)") {
                shots.append(path)
            }
        }
        let frames = Recorder.shared.frameCount
        let dropped = Recorder.shared.dropped
        if !engagedNow { Recorder.shared.discard() }

        // A thought that ran across two finalisations is one note, not two.
        let gap = Date().timeIntervalSince(lastSegmentAt)
        lastSegmentAt = Date()
        if engagedNow, gap < 1.6, Notes.shared.extendLast(with: u.text, shots: shots) {
            phase = .noted(Notes.shared.items.last?.text ?? u.text)
            show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                Task { @MainActor in
                    guard let self, self.engagedNow else { return }
                    if case .noted = self.phase { self.phase = .hearing }
                }
            }
            return
        }

        let n = Note(id: id, text: u.text,
                     context: context?.line ?? "",
                     app: context?.app ?? "",
                     shots: shots)
        Notes.shared.add(n)

        if shots.isEmpty {
            spoken = Shot.screenIsSensitive ? "no frame — a password field is open"
                   : (!Shot.permitted ? "no frame — Screen Recording is off"
                                      : "no frame captured")
        } else {
            spoken = shots.count == 1 ? "" : "\(shots.count) points"
        }
        Log.say("note · shots=\(shots.count) from \(frames) frames (\(dropped) captures overran)")

        phase = .noted(u.text)
        show()
        if engagedNow {
            // Still holding: flash the note, then go straight back to listening
            // so a pass across a whole site never breaks stride.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
                Task { @MainActor in
                    guard let self, self.engagedNow else { return }
                    if case .noted = self.phase { self.phase = .hearing }
                }
            }
        } else {
            hide(after: 2.4)
        }
    }

    private func present(_ r: Reply) {
        Log.say("present · kind=\(r.kind) spoken=“\(r.spoken)”")
        reply = r
        spoken = r.spoken
        phase = .replying(r.detail)
        switch r.kind {
        case .ask:
            awaitingConfirmation = true
            Voice.shared.say(r.spoken)
        case .act:
            awaitingConfirmation = false
            confirm(r)
        case .answer, .refuse:
            awaitingConfirmation = false
            Voice.shared.say(r.spoken)
            hide(after: 4)
        }
    }

    // MARK: - Control phrases

    private func run(_ c: Control) {
        disarm()
        awaitingConfirmation = false
        switch c {
        case .send:
            guard !Notes.shared.isEmpty else {
                phase = .reported("no notes yet", false); show(); hide(after: 2.2); return
            }
            visible = false
            onPassEnded?()

        case .undo:
            Notes.shared.undo()
            phase = .reported("removed the last note · \(Notes.shared.count) left", true)
            show(); hide(after: 2.2)

        case .clear:
            Notes.shared.clear()
            phase = .reported("cleared", true)
            show(); hide(after: 2)

        case .selfCapture(let on):
            captureOverlays = on
            phase = .reported(on ? "Ambient will appear in shots" : "Ambient hidden from shots", true)
            show(); hide(after: 2.4)

        case .rail(let on):
            showRail = on
            phase = .reported(on ? "bottom rail on" : "bottom rail off", true)
            show(); hide(after: 2)

        case .pill(let on):
            showPill = on
            phase = .reported(on ? "cursor pill on" : "cursor pill off", true)
            show(); hide(after: 2)

        case .review:
            let n = Notes.shared.count
            phase = .reported(n == 0 ? "no notes yet" : "\(n) note\(n == 1 ? "" : "s") so far", true)
            show(); hide(after: 3.5)
        }
    }

    // MARK: - Gate

    func confirmPending() { if let r = reply, awaitingConfirmation { confirm(r) } }
    func declinePending() { if awaitingConfirmation { decline() } }

    private func confirm(_ r: Reply) {
        awaitingConfirmation = false
        phase = .acting
        show()
        arm("action", seconds: 30)
        Task { [weak self] in
            let out: (ok: Bool, text: String)
            if r.action != .none {
                out = await Actions.perform(r.action, on: r.targets.first)
            } else {
                out = await Dispatch.run(task: r.task,
                                         app: r.targets.first?.app ?? "",
                                         context: r.targets.map(\.line).joined(separator: "\n"))
            }
            guard let self else { return }
            self.disarm()
            self.phase = .reported(out.text, out.ok)
            self.hide(after: 4)
        }
    }

    private func decline() {
        awaitingConfirmation = false
        reply = nil
        phase = .reported("dropped", true)
        hide(after: 1.8)
    }

    // MARK: -

    func announce(_ text: String, ok: Bool, speak: Bool = false) {
        disarm()
        awaitingConfirmation = false
        spoken = text
        phase = .reported(text, ok)
        show()
        if speak { Voice.shared.say(text) }
        hide(after: ok ? 3 : 7)
    }

    func listenerChanged(_ s: Listener.State) {
        switch s {
        case .preparing(let m): phase = .preparing(m); show()
        case .ready:
            if case .preparing = phase { phase = .idle; hide(after: 1) }
            if case .failed = phase { phase = .idle }
        case .hearing: break
        case .failed(let m): phase = .failed(m); show(); hide(after: 12)
        }
    }
}

/// Phrases that manage the batch rather than joining it.
enum Control {
    case send, undo, clear, review, rail(Bool), pill(Bool), selfCapture(Bool)

    static func parse(_ text: String) -> Control? {
        let t = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .,!?"))
        if has(t, "send it", "send that", "send to claude", "send the notes", "ship it",
               "that's it", "thats it", "go ahead and do it", "execute that", "make it so",
               "send them", "do it now", "run it") { return .send }
        if has(t, "scratch that", "undo that", "remove that", "delete that note",
               "take that back", "ignore that last") { return .undo }
        if has(t, "clear the notes", "clear notes", "start over", "forget everything",
               "wipe the notes") { return .clear }
        if has(t, "how many notes", "what have i said", "read the notes", "where are we",
               "how many so far") { return .review }

        if has(t, "capture yourself", "include yourself", "show yourself in shots",
               "capture the island") { return .selfCapture(true) }
        if has(t, "stop capturing yourself", "exclude yourself", "hide yourself") { return .selfCapture(false) }
        if has(t, "hide bottom ui", "hide the bottom", "hide the rail", "hide bottom bar") { return .rail(false) }
        if has(t, "show bottom ui", "show the bottom", "show the rail", "show bottom bar") { return .rail(true) }
        if has(t, "hide my cursor", "hide the cursor", "hide the pill") { return .pill(false) }
        if has(t, "show my cursor", "show the cursor", "show the pill", "follow my cursor") { return .pill(true) }
        return nil
    }

    private static func has(_ t: String, _ n: String...) -> Bool { n.contains { t.contains($0) } }
}

enum Record {
    static func write(kind: String, heard: String, spoken: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ambient")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = dir.appendingPathComponent("ledger.log")
        let line = "\(ISO8601DateFormatter().string(from: Date()))\t\(kind)\t\(heard)\t\(spoken)\n"
        if let h = try? FileHandle(forWritingTo: f) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? line.write(to: f, atomically: true, encoding: .utf8)
        }
    }
}

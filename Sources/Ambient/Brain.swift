import Foundation

/// What the machine decided to do with what you said.
struct Reply {
    enum Kind { case act, ask, answer, refuse }
    let kind: Kind
    let spoken: String          // one short line, read aloud
    let detail: String          // what shows on the panel
    let targets: [Target]
    let task: String            // the instruction handed to dispatch, if released
    let action: Action          // a real action to carry out, or .none
}

/// Reads an utterance against what was on screen.
///
/// Two paths. The local one always works and never leaves the machine. If a key
/// is present at ~/.ambient/key the reading is done by a model instead, which is
/// what makes it conversational — at the cost of sending the utterance and the
/// on-screen context (not pixels) to the API.
enum Brain {

    static var key: String? { Secrets.load() }
    static var connected: Bool { Secrets.present }

    // MARK: - Classification

    static let verbs: Set<String> = [
        "make","change","move","crop","fix","build","write","open","run","deploy","rename",
        "delete","add","remove","push","commit","export","resize","align","swap","replace",
        "generate","check","find","search","send","draft","copy","set","turn","scale","tighten",
        "reduce","increase","restart","refactor","rewrite","clean","ship","stage","render",
        "pull","install","start","stop","note","save","close","quit","zoom","undo","redo"
    ]

    /// Verbs that change something outside the app. These always ask first.
    static let consequential: Set<String> = [
        "delete","remove","push","commit","deploy","send","ship","publish","rename","replace","quit","install"
    ]

    nonisolated static let deictic: Set<String> = ["this","that","these","those","here","there","it"]

    static func words(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" }).map(String.init)
    }

    static func isAffirmative(_ s: String) -> Bool {
        let w = words(s)
        return w.contains(where: { ["yes","yeah","yep","yup","sure","ok","okay","go","do","please","confirm","correct","right"].contains($0) })
    }

    static func isNegative(_ s: String) -> Bool {
        let w = words(s)
        return w.contains(where: { ["no","nope","nah","stop","cancel","don't","dont","wait","never"].contains($0) })
    }

    // MARK: - Deixis

    /// Join each pointing word back to where the cursor was when it was spoken.
    static func resolve(_ u: Utterance) async -> (String, [Target]) {
        var targets: [Target] = []
        var reading = u.text
        var seen = Set<String>()

        for w in u.words where deictic.contains(w.text.lowercased().trimmingCharacters(in: .punctuationCharacters)) {
            guard let s = Pointer.shared.sample(at: w.t) else { continue }
            let t = await Pointer.shared.resolve(s)
            guard !t.short.isEmpty else { continue }
            if !seen.contains(t.short) { targets.append(t); seen.insert(t.short) }
            if let r = reading.range(of: w.text, options: [.caseInsensitive]) {
                reading.replaceSubrange(r, with: "[\(t.short)]")
            }
        }
        if targets.isEmpty, let s = Pointer.shared.latest {
            let t = await Pointer.shared.resolve(s)
            if !t.short.isEmpty { targets.append(t) }
        }
        return (reading, targets)
    }

    // MARK: - Reading

    static func read(_ u: Utterance) async -> Reply {
        let (reading, targets) = await resolve(u)
        Log.say("brain · reading=“\(reading)” targets=\(targets.count) model=\(connected)")
        let w = words(u.text)
        let verb = w.first(where: { verbs.contains($0) })
        let task = prompt(heard: u.text, reading: reading, targets: targets)

        if let key {
            let outcome = await ask(model: key, heard: u.text, reading: reading,
                                    targets: targets, task: task)
            switch outcome {
            case .reply(let r):
                return r
            case .problem(let why):
                // A key that is present but not working must say so. Reporting
                // this as "no model connected" was a lie the user could not debug.
                Log.say("brain · model failed — \(why)")
                return Reply(kind: .refuse, spoken: why, detail: reading,
                             targets: targets, task: task, action: .none)
            }
        }

        // Local reading. It carries out what it can actually do, rather than
        // describing the instruction back and queueing the words as text.
        let target = targets.first

        // The on-device model reads it first. Keyword matching below is only a
        // fallback for machines where Apple Intelligence is off.
        if let (u, act) = await Local.read(heard: u.text, targets: targets) {
            let spoken = u.reply.trimmingCharacters(in: .whitespacesAndNewlines)

            if Local.wantsHandoff(u) {
                return Reply(kind: .ask, spoken: spoken.isEmpty ? "Hand this off?" : spoken,
                             detail: reading, targets: targets, task: task, action: .none)
            }
            if act == .none {
                return Reply(kind: .answer, spoken: spoken, detail: reading,
                             targets: targets, task: task, action: .none)
            }
            if act == .readAloud {
                let out = await Actions.perform(.readAloud, on: target)
                return Reply(kind: out.ok ? .answer : .refuse, spoken: out.text,
                             detail: target?.line ?? reading,
                             targets: targets, task: task, action: .none)
            }
            if act == .describe {
                let out = await Actions.perform(.describe, on: target)
                return Reply(kind: .answer, spoken: spoken.isEmpty ? out.text : spoken,
                             detail: target?.line ?? reading,
                             targets: targets, task: task, action: .none)
            }
            // Reversible enough to just do; the rest is worth one word of consent.
            let immediate: Bool
            switch act {
            case .copy, .open, .reveal, .shot: immediate = true
            default: immediate = false
            }
            if immediate {
                let out = await Actions.perform(act, on: target)
                return Reply(kind: out.ok ? .answer : .refuse,
                             spoken: spoken.isEmpty ? out.text : spoken,
                             detail: reading, targets: targets, task: task, action: .none)
            }
            return Reply(kind: .ask,
                         spoken: spoken.isEmpty ? Actions.describe(act, target) : spoken,
                         detail: reading, targets: targets, task: task, action: act)
        }

        // Answer the ordinary things first. A model is for open questions, not
        // for "can you hear me".
        if let chat = await MainActor.run(body: { Chat.answer(u.text, target: target) }) {
            Log.say("brain · chat")
            return Reply(kind: .answer, spoken: chat.spoken, detail: reading,
                         targets: targets, task: task, action: .none)
        }

        let action = Actions.parse(u.text)
        Log.say("brain · action=\(action)")

        switch action {
        case .none:
            break

        case .describe, .readAloud:
            // Nothing to confirm — answering is the whole act.
            let out = await Actions.perform(action, on: target)
            return Reply(kind: out.ok ? .answer : .refuse,
                         spoken: out.text,
                         detail: target?.line ?? reading,
                         targets: targets, task: task, action: .none)

        default:
            return Reply(kind: .ask,
                         spoken: Actions.describe(action, target),
                         detail: reading,
                         targets: targets, task: task, action: action)
        }

        let named = target?.short ?? ""
        if let verb {
            let onThing = named.isEmpty ? "" : " on \(named)"
            return Reply(
                kind: .ask,
                spoken: "\(verb.capitalized)\(onThing). Hand it off?",
                detail: reading,
                targets: targets,
                task: task,
                action: .none)
        }

        if u.text.hasSuffix("?") || w.first.map({ ["what","where","why","how","who","which","is","are","can","does","do"].contains($0) }) == true {
            return Reply(
                kind: .refuse,
                spoken: connected
                    ? "I couldn't read that."
                    : "I can't answer that one on my own — but ask me what something is, or tell me to click, copy, read or open it.",
                detail: named.isEmpty ? reading : "\(reading)\n\(named)",
                targets: targets,
                task: task,
                action: .none)
        }

        return Reply(
            kind: .ask,
            spoken: "Hand this off as an instruction?",
            detail: reading,
            targets: targets,
            task: task,
            action: .none)
    }

    static func prompt(heard: String, reading: String, targets: [Target]) -> String {
        """
        Spoken instruction: \(heard)
        Resolved reading:   \(reading)

        On screen when it was said:
        \(targets.enumerated().map { "  \($0.offset + 1). \($0.element.line)" }.joined(separator: "\n"))

        Carry out the instruction. If the target is ambiguous, say what you would
        need to know instead of guessing.
        """
    }

    // MARK: - Model path

    enum Outcome {
        case reply(Reply)
        case problem(String)
    }

    /// Returns a described failure rather than nil, so nothing downstream has to
    /// guess why a reading did not happen.
    private static func ask(model key: String, heard: String, reading: String,
                            targets: [Target], task: String) async -> Outcome {
        let system = """
        You are the reading layer of a voice assistant. The user spoke while pointing at \
        something on screen. Answer in JSON only, no prose, no code fence:
        {"kind":"act|ask|answer|refuse","spoken":"one short sentence, under 12 words, read aloud","detail":"one line for the panel","task":"the instruction to hand an agent, or empty"}
        Use "ask" when acting would change a file, send something, or the target is ambiguous. \
        Use "answer" when the user asked a question you can answer from the context given. \
        Use "act" only for trivially reversible things. Never invent screen content you were not given.
        """
        let user = """
        Heard: \(heard)
        Resolved: \(reading)
        On screen:
        \(targets.map { "- \($0.line)" }.joined(separator: "\n"))
        """

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 300,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]

        let data: Data
        do {
            data = try await send(key: key, body: body)
        } catch let e as ModelError {
            return .problem(e.spoken)
        } catch {
            return .problem("Couldn't reach the API.")
        }

        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = top["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String,
              let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
              let obj = try? JSONSerialization.jsonObject(
                with: Data(text[start...end].utf8)) as? [String: Any]
        else { return .problem("The model sent something I couldn't read.") }

        do {
            let kind: Reply.Kind
            switch obj["kind"] as? String {
            case "act": kind = .act
            case "answer": kind = .answer
            case "refuse": kind = .refuse
            default: kind = .ask
            }
            let t = (obj["task"] as? String) ?? ""
            return .reply(Reply(kind: kind,
                                spoken: (obj["spoken"] as? String) ?? "",
                                detail: (obj["detail"] as? String) ?? reading,
                                targets: targets,
                                task: t.isEmpty ? task : t,
                                action: .none))
        }
    }

    // MARK: - Transport

    struct ModelError: Error {
        let spoken: String
    }

    private static func send(key: String, body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ModelError(spoken: "Couldn't reach the API.")
        }
        guard let http = response as? HTTPURLResponse else { return data }
        switch http.statusCode {
        case 200...299: return data
        case 401, 403:  throw ModelError(spoken: "That API key was rejected.")
        case 429:       throw ModelError(spoken: "Rate limited — try again in a moment.")
        case 400:       throw ModelError(spoken: "The API refused that request.")
        case 500...599: throw ModelError(spoken: "The API is having trouble.")
        default:        throw ModelError(spoken: "API error \(http.statusCode).")
        }
    }

    /// One cheap round trip, used when connecting a key so the result is known
    /// immediately rather than at the next thing you say.
    static func validate(_ key: String) async -> String? {
        do {
            _ = try await send(key: key, body: [
                "model": "claude-haiku-4-5-20251001",
                "max_tokens": 4,
                "messages": [["role": "user", "content": "hi"]]
            ])
            return nil
        } catch let e as ModelError {
            return e.spoken
        } catch {
            return "Couldn't reach the API."
        }
    }
}

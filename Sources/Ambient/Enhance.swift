import Foundation

/// Turning what you said into what you meant.
///
/// Raw capture is deliberately verbatim — it is the record, and it is never
/// destroyed. This is a second reading of that record: fillers stripped,
/// stutters collapsed, "this" replaced with the thing the ring is actually
/// around, one instruction per line.
///
/// Two tiers, same output shape. The local pass is deterministic, instant and
/// free. A model, when one is reachable, rewrites instead — better, but never
/// required for the tool to work.
enum Enhance {

    /// Noise wherever it appears.
    private static let noise = [
        "um", "uh", "erm", "uhm", "ah", "eh", "hmm", "mmm",
        "basically", "actually", "literally", "obviously", "honestly", "really just"
    ]

    /// Scaffolding that only reads as filler when it opens a sentence — "so the
    /// spacing is off" drops it, "space it so the grid lines up" keeps it.
    private static let openers = [
        "so", "and", "but", "then", "now", "okay", "ok", "yeah", "yep", "right",
        "well", "like", "also", "plus", "anyway", "anyways", "i guess", "maybe"
    ]

    private static let phrases = [
        "you know", "i mean", "i think", "sort of", "kind of", "a bit of a",
        "if that makes sense", "or whatever", "and stuff", "thinking out loud",
        "let me just", "i want to start by", "i wanna start by", "what i'd like is",
        "can you", "could you", "i'd like you to", "please"
    ]

    /// Spoken requests are first-person and hedged. A brief is imperative.
    /// "I want to basically increase the opacity of this" is one instruction,
    /// and it should read like one.
    private static let leadIns = [
        "i want to", "i wanna", "i'd like to", "i would like to", "i need to",
        "i'm going to", "im going to", "i'm gonna", "we should", "we need to",
        "we could", "can we", "could we", "let's", "lets", "you should",
        "it should", "it needs to", "make sure to", "i think we should",
        "what i want is to", "the thing is"
    ]

    // MARK: - Local pass

    static func clean(_ note: Note) -> String {
        var t = note.text

        // "like" is filler except where it carries comparison.
        t = t.replacingOccurrences(
            of: #"(?<!feels |looks |works |sounds |reads )\blike\b"#,
            with: " ", options: [.caseInsensitive, .regularExpression])

        for p in phrases {
            t = t.replacingOccurrences(of: p, with: " ", options: [.caseInsensitive])
        }

        for n in noise {
            t = t.replacingOccurrences(of: "\\b\(n)\\b", with: " ",
                                       options: [.caseInsensitive, .regularExpression])
        }

        var words = t.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)

        while let first = words.first, openers.contains(bare(first)), words.count > 1 {
            words.removeFirst()
        }

        // "of, of, I want" — a stutter is the same word twice in a row.
        var deduped: [String] = []
        for w in words where bare(w) != bare(deduped.last ?? "") || bare(w).count > 3 {
            deduped.append(w)
        }
        words = deduped

        t = words.joined(separator: " ")

        // Strip the request framing and leave the instruction.
        var trimmed = true
        while trimmed {
            trimmed = false
            let lower = t.lowercased()
            for lead in leadIns where lower.hasPrefix(lead + " ") {
                t = String(t.dropFirst(lead.count + 1))
                trimmed = true
                break
            }
        }
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+([,.!?])"#, with: "$1", options: .regularExpression)
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;-"))

        // Point the instruction at the thing the ring is around — but only when
        // the word is standing alone. "this heading" already names its subject;
        // substituting into it produces "the button “Save” heading".
        if let subject = subject(of: note) {
            for d in ["this one", "that one", "this", "that", "these", "those"] {
                guard let r = t.range(of: "\\b\(d)\\b",
                                      options: [.caseInsensitive, .regularExpression]),
                      standsAlone(t, after: r) else { continue }
                t.replaceSubrange(r, with: "the \(subject)")
                break
            }
        }

        guard let f = t.first else { return t }
        return f.uppercased() + t.dropFirst()
    }

    /// True when nothing noun-like follows, so the word is the subject itself.
    private static func standsAlone(_ t: String, after r: Range<String.Index>) -> Bool {
        let rest = t[r.upperBound...].trimmingCharacters(in: .whitespaces)
        guard let next = rest.split(separator: " ").first.map(String.init) else { return true }
        let following = ["is", "isn't", "needs", "should", "looks", "feels", "seems", "has",
                         "could", "can", "and", "or", "to", "up", "down", "here", "a", "an",
                         "by", "in", "on", "too", "way", "bit", "much", "more", "less"]
        return following.contains(bare(next))
    }

    /// The element label from the captured context, when there is a usable one.
    private static func subject(of note: Note) -> String? {
        guard let quoted = note.context.range(of: "“"),
              let end = note.context.range(of: "”", range: quoted.upperBound..<note.context.endIndex)
        else { return nil }
        let label = String(note.context[quoted.upperBound..<end.lowerBound])
        guard !label.isEmpty, label.count < 40, !label.contains("http") else { return nil }

        let role = ["button", "link", "image", "heading", "statictext", "textfield", "checkbox"]
            .first { note.context.lowercased().contains(" \($0) ") }
        let kind = role.map { $0 == "statictext" ? "text" : $0 } ?? "element"
        return "\(kind) “\(label)”"
    }

    private static func bare(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    // MARK: - The brief

    /// What gets handed to whoever does the work.
    static func brief(_ items: [Note]) -> String {
        guard !items.isEmpty else { return "" }

        var byPage: [String: [Note]] = [:]
        for n in items { byPage[page(of: n), default: []].append(n) }

        var out = "Feedback pass — \(items.count) item\(items.count == 1 ? "" : "s")\n"
        var index = 1
        for key in byPage.keys.sorted() {
            out += "\n\(key)\n"
            for n in byPage[key] ?? [] {
                out += "\n\(index). \(clean(n))\n"
                for shot in n.shots { out += "   \(shot)\n" }
                if clean(n).caseInsensitiveCompare(n.text) != .orderedSame {
                    out += "   said: “\(n.text)”\n"
                }
                index += 1
            }
        }
        if items.contains(where: { !$0.shots.isEmpty }) {
            out += "\nEach screenshot is a crop from the moment that item was spoken, "
            out += "with a ring drawn on the thing being referred to.\n"
        }
        return out
    }

    private static func page(of n: Note) -> String {
        if let r = n.context.range(of: "https://") {
            let rest = n.context[r.lowerBound...]
            return rest.split(separator: " ").first.map(String.init) ?? n.app
        }
        return n.app.isEmpty ? "Elsewhere" : n.app
    }
}

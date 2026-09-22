import AppKit

/// The small set of things people actually say to a voice assistant before they
/// say anything useful — greetings, "can you hear me", "what can you do".
///
/// None of this needs a model. Answering "is this working?" with "I can't answer
/// that without a model connected" was the single worst thing the app did: it is
/// the first thing anyone says, and the one question it could always answer.
enum Chat {

    struct Answer {
        let spoken: String
        let closes: Bool        // true = end the turn here, nothing to confirm
    }

    @MainActor
    static func answer(_ text: String, target: Target?) -> Answer? {
        let t = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .,!?"))
        guard !t.isEmpty else { return nil }
        let w = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)

        // Is it on? The question the app must never fail.
        if has(t, "can you hear me", "are you there", "you there", "is this working",
               "are you working", "does this work", "is it working", "are you on",
               "are you listening", "do you hear me", "is this thing on", "you working") {
            return Answer(spoken: "Yes — I can hear you.", closes: true)
        }

        if has(t, "what can you do", "what do you do", "help me", "what are my options",
               "how does this work", "how do i use this", "what should i say") {
            return Answer(spoken: "Point at something and say what is this, click this, copy this, read this — or open an app, type, or take a screenshot.",
                          closes: true)
        }

        if has(t, "what are you", "who are you", "what is this app", "what's your name") {
            return Answer(spoken: "Ambient. Hold control and fn, and I listen while you point.", closes: true)
        }

        // Greetings — including the ones that are only a greeting.
        if w.count <= 4, w.contains(where: { ["hi","hey","hello","yo","sup","morning","evening"].contains($0) }) {
            return Answer(spoken: "I'm here.", closes: true)
        }

        if has(t, "thank you", "thanks", "cheers", "nice one", "good job", "perfect") {
            return Answer(spoken: "Any time.", closes: true)
        }

        if has(t, "never mind", "nevermind", "forget it", "cancel that", "ignore that", "stop") {
            return Answer(spoken: "Dropped.", closes: true)
        }

        if has(t, "be quiet", "shut up", "mute", "stop talking", "stop speaking") {
            Voice.shared.muted = true
            return Answer(spoken: "", closes: true)
        }
        if has(t, "speak up", "unmute", "talk to me", "you can talk") {
            Voice.shared.muted = false
            return Answer(spoken: "Talking again.", closes: true)
        }

        if has(t, "what time", "what's the time") {
            let f = DateFormatter(); f.dateFormat = "h:mm"
            return Answer(spoken: "It's \(f.string(from: Date())).", closes: true)
        }

        if has(t, "what day", "what's the date", "what date") {
            let f = DateFormatter(); f.dateFormat = "EEEE d MMMM"
            return Answer(spoken: "It's \(f.string(from: Date())).", closes: true)
        }

        if has(t, "what app", "which app", "where am i", "what am i in", "what's open",
               "what window", "what am i looking at") {
            guard let target, !target.app.isEmpty else {
                return Answer(spoken: "I can't tell what's in front.", closes: true)
            }
            let win = target.window.isEmpty ? "" : ", \(target.window)"
            return Answer(spoken: "\(target.app)\(win).", closes: true)
        }

        if has(t, "can you see", "what do you see", "can you see this", "see my screen") {
            guard let target else { return Answer(spoken: "Nothing under the cursor.", closes: true) }
            return Answer(spoken: "Yes — \(target.short).", closes: true)
        }

        if has(t, "do you have a model", "are you connected", "is a model connected",
               "do you have a brain") {
            return Answer(spoken: Brain.connected
                          ? "Yes, a model is connected."
                          : "No model is connected — I'm working locally.", closes: true)
        }

        return nil
    }

    private static func has(_ t: String, _ needles: String...) -> Bool {
        needles.contains { t.contains($0) }
    }
}

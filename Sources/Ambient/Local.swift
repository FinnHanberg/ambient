import Foundation
import FoundationModels

/// Understanding, done by the on-device model.
///
/// Everything before this was keyword matching wearing a coat — `if
/// text.contains("click")` will never handle "yeah get rid of that one" or
/// "actually put it back". Apple ships a real language model on this machine;
/// it needs no key, no network, and it keeps the conversation in session.
/// The shape of one reading. Built as a runtime schema rather than with the
/// @Generable macro — that macro's plugin ships with full Xcode, and this
/// machine has only the Command Line Tools. The runtime schema is arguably
/// better here anyway: `anyOf` constrains the action to a valid value instead
/// of hoping the model spells it correctly.
struct Understanding {
    let reply: String
    let action: String
    let argument: String
}

enum Schema {
    static let actions = ["none", "describe", "read", "click", "copy", "open",
                          "reveal", "type", "screenshot", "close", "quit", "handoff"]

    static let generation: GenerationSchema? = {
        let action = DynamicGenerationSchema(name: "action", anyOf: actions)
        let root = DynamicGenerationSchema(
            name: "Understanding",
            description: "A spoken reply and the action to take",
            properties: [
                .init(name: "reply",
                      description: "One short sentence to say out loud, under 15 words. Plain and direct.",
                      schema: DynamicGenerationSchema(type: String.self)),
                .init(name: "action",
                      description: "Which action to take",
                      schema: action),
                .init(name: "argument",
                      description: "App name for open, or the text for type. Empty string otherwise.",
                      schema: DynamicGenerationSchema(type: String.self))
            ])
        return try? GenerationSchema(root: root, dependencies: [])
    }()
}

@MainActor
enum Local {
    private static var session: LanguageModelSession?

    enum Readiness {
        case ready
        case off(String)
    }

    static var readiness: Readiness {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .ready
        case .unavailable(let why):
            switch why {
            case .appleIntelligenceNotEnabled:
                return .off("Apple Intelligence is switched off — turn it on in System Settings.")
            case .deviceNotEligible:
                return .off("This Mac can't run the on-device model.")
            case .modelNotReady:
                return .off("The on-device model is still downloading.")
            @unknown default:
                return .off("The on-device model isn't available.")
            }
        @unknown default:
            return .off("The on-device model isn't available.")
        }
    }

    static var available: Bool {
        if case .ready = readiness { return true }
        return false
    }

    private static let instructions = """
    You are Ambient, a voice assistant on a Mac. The user holds a key, speaks, and points \
    at things on screen with the cursor. You are told what the cursor was on.

    Reply in ONE short spoken sentence. Be direct and concrete. Never narrate what you are \
    about to do at length, never list options unless asked, never apologise.

    Choose one action:
      describe   - say what the thing under the cursor is
      read       - read its contents out loud
      click      - press it
      copy       - copy its contents
      open       - launch an app (put the app name in argument)
      reveal     - show it in Finder
      type       - type text (put the text in argument)
      screenshot - capture it
      close      - close the window
      quit       - quit the app
      handoff    - a real task for a coding agent, too big to do here
      none       - just talking; your reply is the whole response

    If the user is chatting, asking whether you can hear them, or asking something you can \
    answer from what you were told, use none and just answer. Use handoff only for genuine \
    work like editing files or building something.
    """

    /// One session for the life of the app, so it remembers the exchange.
    private static func ensure() -> LanguageModelSession? {
        guard available else { return nil }
        if let session { return session }
        let s = LanguageModelSession(instructions: instructions)
        session = s
        return s
    }

    static func reset() { session = nil }

    static func read(heard: String, targets: [Target]) async -> (Understanding, Action)? {
        guard let session = ensure() else { return nil }

        let screen = targets.isEmpty
            ? "Nothing identifiable under the cursor."
            : targets.map { "- \($0.line)" }.joined(separator: "\n")
        let prompt = """
        The user said: "\(heard)"

        Under the cursor when they said it:
        \(screen)
        """

        guard let schema = Schema.generation else { return nil }
        do {
            let raw = try await session.respond(to: prompt, schema: schema).content
            let out = Understanding(
                reply: (try? raw.value(String.self, forProperty: "reply")) ?? "",
                action: (try? raw.value(String.self, forProperty: "action")) ?? "none",
                argument: (try? raw.value(String.self, forProperty: "argument")) ?? "")
            Log.say("local · action=\(out.action) arg=“\(out.argument)” reply=“\(out.reply)”")
            return (out, action(from: out))
        } catch {
            Log.say("local · failed — \(error.localizedDescription)")
            // A session can wedge after a guardrail trip; start a clean one.
            self.session = nil
            return nil
        }
    }

    private static func action(from u: Understanding) -> Action {
        switch u.action.lowercased().trimmingCharacters(in: .whitespaces) {
        case "describe":   return .describe
        case "read":       return .readAloud
        case "click":      return .click
        case "copy":       return .copy
        case "open":       return u.argument.isEmpty ? .none : .open(u.argument)
        case "reveal":     return .reveal
        case "type":       return u.argument.isEmpty ? .none : .type(u.argument)
        case "screenshot": return .shot
        case "close":      return .closeWindow
        case "quit":       return .quitApp
        default:           return .none
        }
    }

    nonisolated static func wantsHandoff(_ u: Understanding) -> Bool {
        u.action.lowercased().contains("handoff")
    }
}

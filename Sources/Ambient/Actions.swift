import AppKit
import ApplicationServices

/// What the local reading can actually carry out, with no model involved.
///
/// The point of the whole thing is that saying something makes something
/// happen. Queueing the sentence as text and calling that done was the reason
/// it felt inert.
enum Action: Equatable {
    case describe               // "what is this"
    case readAloud              // "read this"
    case click                  // "click this" / "press this"
    case copy                   // "copy this"
    case open(String)           // "open figma"
    case reveal                 // "show this in finder"
    case type(String)           // "type hello there"
    case shot                   // "screenshot this"
    case closeWindow
    case quitApp
    case none
}

enum Actions {

    /// True for things that are awkward to undo. These always get confirmed.
    static func risky(_ a: Action) -> Bool {
        switch a {
        case .quitApp, .closeWindow, .type: return true
        default: return false
        }
    }

    // MARK: - Parsing

    static func parse(_ text: String) -> Action {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let w = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !w.isEmpty else { return .none }

        if t.contains("what is") || t.contains("what's this") || t.contains("what am i")
            || t.contains("what's that") { return .describe }
        if starts(w, "read") || t.contains("read this") || t.contains("read that") { return .readAloud }
        if starts(w, "click") || starts(w, "press") || starts(w, "tap") { return .click }
        if starts(w, "copy") { return .copy }
        if t.contains("in finder") || starts(w, "reveal") { return .reveal }
        if starts(w, "screenshot") || t.contains("take a shot") || t.contains("capture this") { return .shot }
        if starts(w, "quit") { return .quitApp }
        if starts(w, "close") { return .closeWindow }

        if let r = after(t, "type ") ?? after(t, "write ") { return .type(r) }
        if let r = after(t, "open ") ?? after(t, "launch ") {
            let name = r.trimmingCharacters(in: CharacterSet(charactersIn: " .,"))
            if !name.isEmpty, !name.hasPrefix("this"), !name.hasPrefix("that") { return .open(name) }
        }
        return .none
    }

    private static func starts(_ w: [String], _ v: String) -> Bool { w.first == v }

    private static func after(_ t: String, _ marker: String) -> String? {
        guard let r = t.range(of: marker) else { return nil }
        let rest = String(t[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    /// One short line, read aloud before or instead of doing the thing.
    static func describe(_ a: Action, _ target: Target?) -> String {
        let thing = target?.short ?? "that"
        switch a {
        case .describe:      return "Looking."
        case .readAloud:     return "Reading it."
        case .click:         return "Click \(thing)?"
        case .copy:          return "Copy \(thing)?"
        case .open(let n):   return "Open \(n)?"
        case .reveal:        return "Show it in Finder?"
        case .type(let s):   return "Type “\(s.prefix(40))”?"
        case .shot:          return "Screenshot it?"
        case .closeWindow:   return "Close this window?"
        case .quitApp:       return "Quit \(target?.app ?? "it")?"
        case .none:          return ""
        }
    }

    // MARK: - Doing

    static func perform(_ a: Action, on target: Target?) async -> (ok: Bool, text: String) {
        switch a {
        case .none:
            return (false, "nothing to do")

        case .describe:
            guard let t = target else { return (false, "nothing under the cursor") }
            let role = t.role.replacingOccurrences(of: "AX", with: "").lowercased()
            let inApp = t.app.isEmpty ? "" : " in \(t.app)"
            // Build a sentence that still says something when the element under
            // the cursor exposes no name — most of them don't.
            if !t.label.isEmpty {
                let kind = role.isEmpty ? "" : ", a \(role),"
                return (true, "\(t.label)\(kind)\(inApp).")
            }
            if !role.isEmpty, role != "group", role != "unknown" {
                return (true, "A \(role)\(inApp).")
            }
            if !t.window.isEmpty {
                return (true, "The \(t.window) window\(inApp.isEmpty ? "" : ",\(inApp)").")
            }
            return t.app.isEmpty
                ? (false, "I can't tell what that is.")
                : (true, "Just \(t.app) — nothing named under the cursor.")

        case .readAloud:
            guard let t = target else { return (false, "nothing under the cursor") }
            let body = t.value.isEmpty ? t.label : t.value
            guard !body.isEmpty else { return (false, "nothing readable there") }
            return (true, String(body.prefix(600)))

        case .click:
            guard let el = target?.element else { return (false, "nothing clickable there") }
            let err = AXUIElementPerformAction(el, kAXPressAction as CFString)
            if err == .success { return (true, "clicked") }
            // Not every element exposes a press action; fall back to a real click.
            guard let t = target else { return (false, "couldn't click that") }
            return (synthesizeClick(at: t.point), "clicked")

        case .copy:
            guard let t = target else { return (false, "nothing to copy") }
            let body = t.value.isEmpty ? t.label : t.value
            guard !body.isEmpty else { return (false, "nothing to copy there") }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body, forType: .string)
            return (true, "copied")

        case .open(let name):
            return await shell("/usr/bin/open", ["-a", name]).ok
                ? (true, "opened \(name)")
                : (false, "couldn't find \(name)")

        case .reveal:
            guard let t = target else { return (false, "nothing there") }
            let candidate = t.value.isEmpty ? t.label : t.value
            let path = (candidate as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else {
                return (false, "that isn't a file I can find")
            }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return (true, "revealed")

        case .type(let body):
            return (typeText(body), "typed")

        case .shot:
            let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")
            let out = dir.appendingPathComponent("ambient-\(Int(Date().timeIntervalSince1970)).png")
            var args = ["-x", out.path]
            if let f = frame(of: target) {
                args = ["-x", "-R\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))", out.path]
            }
            let r = await shell("/usr/sbin/screencapture", args)
            return r.ok ? (true, "saved to Desktop") : (false, "screen capture is not permitted")

        case .closeWindow:
            guard let el = window(of: target) else { return (false, "no window there") }
            var button: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, kAXCloseButtonAttribute as CFString, &button) == .success,
               let b = button, CFGetTypeID(b) == AXUIElementGetTypeID(),
               AXUIElementPerformAction(b as! AXUIElement, kAXPressAction as CFString) == .success {
                return (true, "closed")
            }
            return (false, "couldn't close it")

        case .quitApp:
            guard let id = target?.bundleID,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first else {
                return (false, "couldn't find that app")
            }
            return (app.terminate(), "quit \(target?.app ?? "")")
        }
    }

    // MARK: - Plumbing

    private static func frame(of target: Target?) -> CGRect? {
        guard let el = target?.element else { return nil }
        var pv: CFTypeRef?; var sv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sv) == .success,
              let p = pv, let s = sv,
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero; var size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &origin)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        guard size.width > 4, size.height > 4 else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func window(of target: Target?) -> AXUIElement? {
        guard let pid = target?.bundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: pid).first else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.3)
        var w: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &w) == .success,
              let win = w, CFGetTypeID(win) == AXUIElementGetTypeID() else { return nil }
        return (win as! AXUIElement)
    }

    private static func synthesizeClick(at point: CGPoint) -> Bool {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left) else { return false }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func typeText(_ s: String) -> Bool {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return false }
        for chunk in Array(s.utf16).chunked(into: 16) {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) else { return false }
            var buf = chunk
            e.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: &buf)
            e.post(tap: .cghidEventTap)
        }
        return true
    }

    private static func shell(_ path: String, _ args: [String]) async -> (ok: Bool, out: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
                do { try p.run() } catch { cont.resume(returning: (false, "")); return }
                let d = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (p.terminationStatus == 0, String(data: d, encoding: .utf8) ?? ""))
            }
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

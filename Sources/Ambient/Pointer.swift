import AppKit
import ApplicationServices

struct PointerSample {
    let t: Date
    let point: CGPoint          // top-left origin (AX space)
    let app: String
    let bundleID: String
    let window: String
    let url: String
}

struct Target {
    let app: String
    let bundleID: String
    let window: String
    let role: String
    let label: String
    let value: String
    let point: CGPoint
    let element: AXUIElement?
    let url: String

    var line: String {
        var parts: [String] = [app]
        if !url.isEmpty { parts.append(url) }
        else if !window.isEmpty { parts.append("window “\(window)”") }
        if !role.isEmpty { parts.append(role.replacingOccurrences(of: "AX", with: "").lowercased()) }
        if !label.isEmpty { parts.append("“\(label.prefix(80))”") }
        if !value.isEmpty, value != label { parts.append("value “\(value.prefix(120))”") }
        return parts.joined(separator: " · ")
    }

    var short: String {
        if !label.isEmpty { return "\(app) · \(label.prefix(40))" }
        if !url.isEmpty { return "\(app) · \(shortURL.prefix(40))" }
        let bit = window.isEmpty ? role.replacingOccurrences(of: "AX", with: "") : window
        return bit.isEmpty ? app : "\(app) · \(bit.prefix(40))"
    }

    /// host + path, which is what identifies a page in conversation.
    var shortURL: String {
        guard let u = URL(string: url), let host = u.host() else { return url }
        let path = u.path()
        return path.isEmpty || path == "/" ? host : host + path
    }
}

/// Samples the cursor into a ring buffer so a word spoken at time T can be
/// joined to what the cursor was aimed at at time T.
///
/// Every accessibility call in here runs off the main thread and under a
/// messaging timeout. An unresponsive app on the other end of an AX query
/// blocks the caller, and when the caller was the main thread the whole
/// interface froze — which is indistinguishable from the app hanging.
final class Pointer {
    static let shared = Pointer()

    private var ring: [PointerSample] = []
    private let cap = 600
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "ambient.pointer", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var lastMove = Date()
    private var lastPoint = CGPoint.zero

    /// Shared, timeout-bounded handle. Without the timeout a hung target app
    /// stalls us for the system default of 6 seconds.
    private static let system: AXUIElement = {
        let el = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(el, 0.25)
        return el
    }()

    var dwell: TimeInterval { Date().timeIntervalSince(lastMove) }

    func start() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(100))
        t.setEventHandler { [weak self] in self?.sample() }
        t.resume()
        timer = t
    }

    private func flipY(_ p: NSPoint) -> CGPoint {
        guard let primary = NSScreen.screens.first else { return CGPoint(x: p.x, y: p.y) }
        return CGPoint(x: p.x, y: primary.frame.maxY - p.y)
    }

    private func sample() {
        let p = flipY(NSEvent.mouseLocation)
        if hypot(p.x - lastPoint.x, p.y - lastPoint.y) > 3 {
            lastMove = Date(); lastPoint = p
        }
        let front = NSWorkspace.shared.frontmostApplication
        let pid = front?.processIdentifier
        Pointer.nudgeAccessibility(pid: pid)
        let s = PointerSample(t: Date(), point: p,
                              app: front?.localizedName ?? "",
                              bundleID: front?.bundleIdentifier ?? "",
                              window: Pointer.frontWindowTitle(pid: pid),
                              url: Pointer.frontDocumentURL(pid: pid))
        lock.lock(); ring.append(s); if ring.count > cap { ring.removeFirst(ring.count - cap) }; lock.unlock()
    }

    func sample(at t: Date) -> PointerSample? {
        lock.lock(); defer { lock.unlock() }
        return ring.min(by: { abs($0.t.timeIntervalSince(t)) < abs($1.t.timeIntervalSince(t)) })
    }

    var latest: PointerSample? { lock.lock(); defer { lock.unlock() }; return ring.last }

    /// Resolve off the main thread, always.
    func resolve(_ s: PointerSample) async -> Target {
        await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: Pointer.resolve(s)) }
        }
    }

    // MARK: - Accessibility

    static var axTrusted: Bool { AXIsProcessTrusted() }

    static func requestAX() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private static func str(_ el: AXUIElement, _ attr: String) -> String {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return "" }
        if let s = v as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = v as? NSNumber { return n.stringValue }
        return ""
    }

    /// Browsers publish the current page on the focused window. Without this a
    /// note taken on a website records only "scrollarea", which is useless when
    /// the whole point is walking pages and saying what is wrong on each.
    /// Electron and Chromium apps build no accessibility tree until a client
    /// asks for one. Setting this makes them cooperate; without it every note
    /// taken in Chrome, VS Code or Claude resolves to "scrollarea".
    private static var nudged = Set<pid_t>()

    static func nudgeAccessibility(pid: pid_t?) {
        guard let pid, axTrusted, !nudged.contains(pid) else { return }
        nudged.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    private static func frontDocumentURL(pid: pid_t?) -> String {
        guard let pid, axTrusted else { return "" }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var w: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &w) == .success,
              let win = w, CFGetTypeID(win) == AXUIElementGetTypeID() else { return "" }
        let doc = str(win as! AXUIElement, kAXDocumentAttribute as String)
        return doc.hasPrefix("http") ? doc : ""
    }

    private static func frontWindowTitle(pid: pid_t?) -> String {
        guard let pid, axTrusted else { return "" }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        var w: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &w) == .success,
              let win = w, CFGetTypeID(win) == AXUIElementGetTypeID() else { return "" }
        return str(win as! AXUIElement, kAXTitleAttribute as String)
    }

    static func resolve(_ s: PointerSample) -> Target {
        let bare = Target(app: s.app, bundleID: s.bundleID, window: s.window,
                          role: "", label: "", value: "", point: s.point, element: nil, url: s.url)
        guard axTrusted else { return bare }

        var ref: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(s.point.x), Float(s.point.y), &ref) == .success,
              let el = ref else { return bare }
        AXUIElementSetMessagingTimeout(el, 0.25)

        var role = str(el, kAXRoleAttribute as String)
        var label = str(el, kAXTitleAttribute as String)
        if label.isEmpty { label = str(el, kAXDescriptionAttribute as String) }
        var value = str(el, kAXValueAttribute as String)

        var hop = el
        var climbs = 0
        while label.isEmpty && value.isEmpty && climbs < 4 {
            var p: CFTypeRef?
            guard AXUIElementCopyAttributeValue(hop, kAXParentAttribute as CFString, &p) == .success,
                  let par = p, CFGetTypeID(par) == AXUIElementGetTypeID() else { break }
            hop = par as! AXUIElement
            AXUIElementSetMessagingTimeout(hop, 0.25)
            label = str(hop, kAXTitleAttribute as String)
            if label.isEmpty { label = str(hop, kAXDescriptionAttribute as String) }
            value = str(hop, kAXValueAttribute as String)
            if !label.isEmpty || !value.isEmpty { role = str(hop, kAXRoleAttribute as String) }
            climbs += 1
        }

        return Target(app: s.app, bundleID: s.bundleID, window: s.window,
                      role: role, label: label, value: value, point: s.point, element: el, url: s.url)
    }
}

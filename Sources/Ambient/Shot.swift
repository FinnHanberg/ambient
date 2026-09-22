import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// A picture of what you were pointing at.
///
/// The first build grounded notes in the accessibility tree and treated pixels
/// as a fallback that should have to earn its place. That was wrong for this
/// job: Chrome and every Electron app refuse to expose their content tree
/// unless a screen reader is running, so a note taken on a website resolved to
/// "scrollarea" no matter how precisely you pointed. A crop around the cursor
/// shows the actual thing, in every app, with no cooperation required.
enum Shot {

    static var dir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ambient/shots")
    }

    static var permitted: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    /// A crop framed on the cursor.
    ///
    /// Clamping a fixed rectangle into the display puts the subject hard against
    /// an edge whenever the cursor is near one — pointing at something in the
    /// menu bar produced a 600pt tall crop with the subject in the top 40pt and
    /// half a page of unrelated content beneath it. Shrink the box instead, so
    /// the subject stays near the middle of whatever is captured.
    static func crop(around point: CGPoint, size: CGSize) -> CGRect {
        let bounds = displayBounds(containing: point)

        let above = point.y - bounds.minY
        let below = bounds.maxY - point.y
        let left = point.x - bounds.minX
        let right = bounds.maxX - point.x

        let halfH = max(150, min(size.height / 2, max(above, below) == above ? below : above))
        let halfW = max(220, min(size.width / 2, max(left, right) == left ? right : left))

        var rect = CGRect(x: point.x - halfW, y: point.y - halfH,
                          width: halfW * 2, height: halfH * 2)
        rect.origin.x = max(bounds.minX, min(rect.origin.x, bounds.maxX - rect.width))
        rect.origin.y = max(bounds.minY, min(rect.origin.y, bounds.maxY - rect.height))
        return rect
    }

    /// Write an in-memory frame out with the cursor ringed.
    static func write(_ image: CGImage, cursor: CGPoint, regionSize: CGSize, id: String) -> String? {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent("\(id).png")
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try? png.write(to: out)
        mark(out, at: cursor, in: regionSize)
        return out.path
    }

    /// A crop centred on the cursor, wide enough to carry context but tight
    /// enough that the subject is obvious.
    /// macOS turns on secure event input whenever a password field has focus —
    /// login sheets, Touch ID prompts, password managers, sudo in a terminal.
    /// It is the same signal that stops keyloggers, and it is exactly the moment
    /// a tool that silently screenshots the screen must not.
    static var screenIsSensitive: Bool { IsSecureEventInputEnabled() }

    static func around(_ point: CGPoint, id: UUID) async -> String? {
        guard permitted else { return nil }
        guard !screenIsSensitive else {
            Log.say("shot · skipped — secure input active")
            return nil
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let w: CGFloat = 900, h: CGFloat = 600
        var rect = CGRect(x: point.x - w / 2, y: point.y - h / 2, width: w, height: h)

        // Clamp into the display the cursor is actually on.
        let bounds = displayBounds(containing: point)
        rect.origin.x = min(max(bounds.minX, rect.origin.x), bounds.maxX - w)
        rect.origin.y = min(max(bounds.minY, rect.origin.y), bounds.maxY - h)

        let out = dir.appendingPathComponent("\(id.uuidString.prefix(8)).png")
        let ok = await run(["-x", "-R\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))", out.path])
        guard ok, FileManager.default.fileExists(atPath: out.path) else { return nil }
        mark(out, at: CGPoint(x: point.x - rect.minX, y: point.y - rect.minY), in: rect.size)
        return out.path
    }

    static func offset(_ point: CGPoint) -> String {
        "the ring on the image marks exactly where the cursor was"
    }

    /// Draw the cursor position onto the crop. Coordinates in a caption have to
    /// be reconciled against the image's scale by whoever reads it; a ring does
    /// not. A crop with three candidate elements in it is otherwise ambiguous.
    static func mark(_ file: URL, at point: CGPoint, in size: CGSize) {
        guard let data = try? Data(contentsOf: file),
              let rep = NSBitmapImageRep(data: data) else { return }
        let pixels = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let scale = pixels.width / max(size.width, 1)

        let image = NSImage(size: pixels)
        image.addRepresentation(rep)
        image.lockFocus()
        let c = NSPoint(x: point.x * scale, y: pixels.height - point.y * scale)  // flip to AppKit
        let r: CGFloat = 16 * scale
        NSColor.black.withAlphaComponent(0.85).setStroke()
        var ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ring.lineWidth = 5 * scale
        ring.stroke()
        NSColor.white.setStroke()
        ring = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ring.lineWidth = 2.5 * scale
        ring.stroke()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let out = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return }
        try? out.write(to: file)
    }

    private static func displayBounds(containing point: CGPoint) -> CGRect {
        // Screen frames are bottom-left origin; the pointer is in top-left space.
        guard let primary = NSScreen.screens.first else {
            return CGRect(x: 0, y: 0, width: 1512, height: 982)
        }
        let flipTop = primary.frame.maxY
        for s in NSScreen.screens {
            let f = CGRect(x: s.frame.minX, y: flipTop - s.frame.maxY,
                           width: s.frame.width, height: s.frame.height)
            if f.contains(point) { return f }
        }
        return CGRect(x: 0, y: 0, width: primary.frame.width, height: primary.frame.height)
    }

    private static func run(_ args: [String]) async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                p.arguments = args
                do { try p.run() } catch { cont.resume(returning: false); return }
                p.waitUntilExit()
                cont.resume(returning: p.terminationStatus == 0)
            }
        }
    }
}

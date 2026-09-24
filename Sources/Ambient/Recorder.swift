import AppKit
import ScreenCaptureKit

/// Frames captured while you hold the keys, kept in memory only.
///
/// A single screenshot taken after you let go answers one question — where the
/// cursor ended up. But a sentence often points at several things: "this is too
/// tight, and this should sit under that." Sampling while you speak means each
/// pointing word can be matched to what was on screen at that word.
///
/// Nothing here is written to disk. Frames that don't end up attached to a note
/// are dropped when the hold ends.
@MainActor
final class Recorder {
    static let shared = Recorder()

    private struct Frame {
        let image: CGImage
        let at: Date
        let rect: CGRect        // the region captured, in pointer space
        let cursor: CGPoint     // cursor within that region, in points
    }

    private var frames: [Frame] = []
    private var timer: Timer?
    private var busy = false
    /// Captures that overran their slot. Talking fast makes these pile up, and
    /// a gap in the ring is a note with no picture.
    private(set) var dropped = 0
    private let cap = 30                    // rolling 10s — a segment only ever needs the seconds just gone
    private let size = CGSize(width: 900, height: 600)

    var frameCount: Int { frames.count }

    func start() {
        guard Shot.permitted else {
            Log.say("recorder · NOT STARTED — no screen recording permission for this app")
            return
        }
        frames.removeAll()
        dropped = 0
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 0.33, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.grab() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Task { await grab() }               // don't wait a third of a second for the first
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called once the notes have taken what they need.
    func discard() {
        frames.removeAll()
    }

    private var complained = false

    private func grab() async {
        if Shot.screenIsSensitive {
            if !complained { complained = true; Log.say("recorder · skipping — secure input active") }
            return
        }
        guard !busy else { dropped += 1; return }
        busy = true
        defer { busy = false }

        guard let sample = Pointer.shared.latest else {
            if !complained { complained = true; Log.say("recorder · no pointer sample") }
            return
        }
        let rect = Shot.crop(around: sample.point, size: size)
        do {
            let full = try await SCScreenshotManager.captureImage(in: rect)
            let image = Recorder.halve(full) ?? full
            frames.append(Frame(image: image, at: Date(), rect: rect,
                                cursor: CGPoint(x: sample.point.x - rect.minX,
                                                y: sample.point.y - rect.minY)))
            if frames.count > cap { frames.removeFirst(frames.count - cap) }
        } catch {
            Log.say("recorder · capture failed — \(error.localizedDescription)")
        }
    }

    /// Retina frames are 8MB each; a rolling window of them is a quarter of a
    /// gigabyte. Half scale is still far more than legible.
    private static func halve(_ image: CGImage) -> CGImage? {
        let w = image.width / 2, h = image.height / 2
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// The frame nearest a given instant, written out with the cursor marked.
    func save(at moment: Date, id: String) -> String? {
        guard let f = frames.min(by: {
            abs($0.at.timeIntervalSince(moment)) < abs($1.at.timeIntervalSince(moment))
        }) else {
            Log.say("shot · no frames captured at all for this note")
            return nil
        }
        let drift = abs(f.at.timeIntervalSince(moment))
        // A late frame is worth far more than no frame: the page has usually
        // not moved, and a note with no picture is the thing he notices.
        if drift > 2.5 {
            Log.say("shot · nearest frame is \(String(format: "%.1f", drift))s off — using it anyway")
        }
        return Shot.write(f.image, cursor: f.cursor, regionSize: f.rect.size, id: id)
    }
}

import AVFoundation

/// The microphone tap.
///
/// Deliberately not main-actor isolated. A tap buffer is only valid for the
/// duration of its callback — the engine reuses the storage immediately after —
/// so conversion has to happen synchronously on the audio thread. Hopping the
/// buffer to another actor first and converting it there reads whatever the
/// engine has since written into it.
final class AudioTap {
    private let lock = NSLock()
    private var feeding = false
    private var converter: AVAudioConverter?
    private var outFormat: AVAudioFormat?
    private var fed: Double = 0

    /// Called on the audio thread. Keep both cheap.
    var onLevel: ((Double) -> Void)?
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    func configure(from input: AVAudioFormat, to output: AVAudioFormat) {
        lock.lock(); defer { lock.unlock() }
        converter = AVAudioConverter(from: input, to: output)
        outFormat = output
    }

    func setFeeding(_ on: Bool) {
        lock.lock(); feeding = on; lock.unlock()
    }

    var fedSeconds: Double {
        lock.lock(); defer { lock.unlock() }; return fed
    }

    /// Call whenever a new analyzer is created. Its audio timeline restarts at
    /// zero, and a counter that kept running across the rebuild made every word
    /// timestamp fail its sanity check and fall back to "now" — which silently
    /// resolved every "this" to wherever the cursor ended up.
    func resetClock() {
        lock.lock(); fed = 0; lock.unlock()
    }

    func receive(_ buf: AVAudioPCMBuffer) {
        let level = AudioTap.rms(buf)
        onLevel?(level)

        lock.lock()
        let on = feeding
        let conv = converter
        let out = outFormat
        lock.unlock()
        guard on, let conv, let out else { return }

        let ratio = out.sampleRate / buf.format.sampleRate
        let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio + 1024)
        guard let dst = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: cap) else { return }

        var err: NSError?
        var served = false
        conv.convert(to: dst, error: &err) { _, status in
            if served { status.pointee = .noDataNow; return nil }
            served = true
            status.pointee = .haveData
            return buf
        }
        guard err == nil, dst.frameLength > 0 else { return }

        lock.lock(); fed += Double(dst.frameLength) / out.sampleRate; lock.unlock()
        onBuffer?(dst)
    }

    private static func rms(_ buf: AVAudioPCMBuffer) -> Double {
        guard let ch = buf.floatChannelData?[0] else { return 0 }
        let n = Int(buf.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += ch[i] * ch[i] }
        return min(1, Double(sqrt(sum / Float(max(n, 1)))) * 14)
    }
}

import AVFoundation

/// It answers out loud. Short lines only — anything long gets read on the panel
/// instead, because spoken text cannot be skimmed.
@MainActor
final class Voice: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = Voice()

    private let synth = AVSpeechSynthesizer()
    private(set) var speaking = false
    /// Off by default. A synthetic voice reading every reply was the single
    /// most irritating thing about the previous build.
    @Published var muted = true
    var onFinish: (() -> Void)?

    private override init() {
        super.init()
        synth.delegate = self
    }

    /// Prefer a premium or enhanced voice if the user has one installed —
    /// the default compact voice is the thing that makes assistants sound cheap.
    private lazy var voice: AVSpeechSynthesisVoice? = {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
        return all.first { $0.quality == .premium }
            ?? all.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }()

    func say(_ text: String) {
        guard !muted, !text.isEmpty else { onFinish?(); return }
        stop()
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = 0.52
        u.pitchMultiplier = 1.0
        u.postUtteranceDelay = 0
        speaking = true
        synth.speak(u)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        speaking = false
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false; self.onFinish?() }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }
}

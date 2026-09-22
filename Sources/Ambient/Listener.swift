import AVFoundation
import Speech

/// A word with the wall-clock instant it was actually spoken.
/// The time comes from the transcriber's own audio time range, not from when
/// the result happened to arrive — so "make *this* bigger" resolves against
/// where the cursor was at the word, even if the text lands 400ms later.
struct StampedWord {
    let text: String
    let t: Date
}

struct Utterance {
    let words: [StampedWord]
    let text: String
}

@MainActor
protocol ListenerDelegate: AnyObject {
    func listener(volatile text: String)
    func listener(finished u: Utterance)
    func listener(state: Listener.State)
    func listener(level: Double)
}

/// Transcription on macOS 26's SpeechAnalyzer.
///
/// The old SFSpeechRecognizer path is deliberately gone: it refuses to run
/// unless the user has Dictation switched on system-wide, and it reports that
/// as an error on a restart loop that looks exactly like silence.
/// SpeechAnalyzer carries its own model and has no such dependency.
@MainActor
final class Listener {
    enum State: Equatable {
        case preparing(String)
        case ready
        case hearing
        case failed(String)
    }

    weak var delegate: ListenerDelegate?
    private(set) var state: State = .preparing("starting") {
        didSet { Log.say("state · \(state)"); delegate?.listener(state: state) }
    }

    private var engine: AVAudioEngine?
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var feed: AsyncStream<AnalyzerInput>.Continuation?
    private let tap = AudioTap()
    private var analyzerFormat: AVAudioFormat?
    private var audioFormat: AVAudioFormat?

    private var engaged = false
    private var engagedAt = Date()
    /// Audio time only advances while engaged, so it cannot be compared to wall
    /// clock directly — each turn is anchored to the stream position at engage.
    private var engageStreamTime: Double = 0
    private var finalWords: [StampedWord] = []
    private var sawFinal = false
    private var volatileText = ""

    // MARK: - Setup

    func prepare() async {
        let locale = Locale(identifier: "en-US")
        let t = SpeechTranscriber(locale: locale,
                                  transcriptionOptions: [],
                                  reportingOptions: [.volatileResults],
                                  attributeOptions: [.audioTimeRange])
        transcriber = t

        do {
            Log.say("prepare · checking installed locales")
            let installed = await SpeechTranscriber.installedLocales
            Log.say("prepare · locales ok (\(installed.count))")
            if !installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) {
                state = .preparing("downloading speech model")
                if let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) {
                    try await req.downloadAndInstall()
                }
            }
            _ = try? await AssetInventory.reserve(locale: locale)

            Log.say("prepare · reserving locale")
            analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [t])
            Log.say("prepare · format \(analyzerFormat?.sampleRate ?? -1)")
            let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
            feed = cont

            let a = SpeechAnalyzer(modules: [t])
            analyzer = a
            // Do not await this. The analyzer waits on its input sequence, and
            // the microphone now opens only while the chord is held — awaiting
            // it here meant prepare() never returned, the listener never
            // reached ready, and every engage silently bailed.
            Task { try? await a.start(inputSequence: stream) }

            consume(t)
            try configureAudio()
            state = .ready
        } catch {
            state = .failed(short(error))
        }
    }

    private func consume(_ t: SpeechTranscriber) {
        Task { [weak self] in
            do {
                for try await result in t.results {
                    guard let self else { return }
                    if result.isFinal {
                        self.absorbFinal(result.text)
                    } else {
                        self.absorbVolatile(result.text)
                    }
                }
            } catch {
                await MainActor.run { self?.state = .failed(self?.short(error) ?? "transcription stopped") }
            }
        }
    }

    // MARK: - Engagement

    /// Audio is only fed to the analyzer while engaged. Releasing the keys
    /// genuinely stops transcription — it is not listening in the background.
    func engage() {
        guard case .ready = state, !engaged else { return }
        engaged = true
        openMicrophone()
        tap.setFeeding(true)
        engagedAt = Date()
        engageStreamTime = tap.fedSeconds
        finalWords = []
        sawFinal = false
        volatileText = ""
        state = .hearing
        Log.say("engage · streamTime=\(String(format: "%.2f", tap.fedSeconds))")
    }

    func release() async {
        guard engaged else { return }
        engaged = false
        tap.setFeeding(false)
        closeMicrophone()
        state = .ready
        Log.say("release · fed=\(String(format: "%.2f", tap.fedSeconds))s")

        try? await analyzer?.finalize(through: nil)

        // Wait for finalisation to land, but never indefinitely. Whatever we
        // have when the deadline passes is what we go with.
        let deadline = Date().addingTimeInterval(1.6)
        while !sawFinal, Date() < deadline {
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        let words = finalWords
        var text = words.isEmpty
            ? volatileText.trimmingCharacters(in: .whitespacesAndNewlines)
            : words.map(\.text).joined(separator: " ")
        // The recogniser opens a turn with leading dots and commas while it
        // settles. They are not speech.
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: ". ,…"))
        Log.say("release · final=\(words.count) volatile=“\(volatileText)” text=“\(text)”")

        volatileText = ""
        delegate?.listener(volatile: "")

        // Always deliver, even empty. A turn that ends without a word still has
        // to end — the previous build returned here and left the panel reading
        // forever.
        delegate?.listener(finished: Utterance(words: words, text: text))
    }

    // MARK: - Results

    private func absorbVolatile(_ s: AttributedString) {
        volatileText = String(s.characters)
        delegate?.listener(volatile: volatileText)
    }

    private func absorbFinal(_ s: AttributedString) {
        sawFinal = true
        let before = finalWords.count
        for run in s.runs {
            let word = String(s[run.range].characters).trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty else { continue }
            var when = Date()
            if let range = run.audioTimeRange {
                // Audio time is measured from the start of the fed stream; the
                // offset within this turn is what maps onto wall clock.
                let offset = CMTimeGetSeconds(range.start) - engageStreamTime
                if offset.isFinite, offset >= -1, offset < 600 {
                    when = engagedAt.addingTimeInterval(max(0, offset))
                }
            }
            finalWords.append(StampedWord(text: word, t: when))
        }
        volatileText = ""

        // A pass over a whole site is one long hold with many things said in it.
        // The transcriber finalises at natural pauses, so each finalisation is a
        // segment — emit it now rather than collecting a five-minute monologue
        // into a single note.
        if engaged, finalWords.count > before {
            let segment = Array(finalWords[before...])
            finalWords = []
            let text = segment.map(\.text).joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: ". ,…"))
            // Single words and stutters are not feedback.
            if text.split(separator: " ").count >= 3 {
                Log.say("segment · “\(text)”")
                delegate?.listener(finished: Utterance(words: segment, text: text))
            }
        }
    }

    // MARK: - Audio
    /// Nothing here touches the input node.
    ///
    /// Merely reading `engine.inputNode` opens the audio input device, and it
    /// stays open for the life of the engine — which is why the orange
    /// recording indicator stayed lit at idle even though no buffers were being
    /// used. The engine is now built per pass and thrown away afterwards.
    private func configureAudio() throws {
        guard analyzerFormat != nil else { throw Err.msg("no compatible audio format") }

        // Wire the tap to the analyzer once, here — not inside the per-pass
        // engine setup. Rebuilding the engine each pass dropped this wiring,
        // and the result was audio captured and fed nowhere: every pass
        // transcribed zero words while looking perfectly healthy in the log.
        let sink = feed
        tap.onBuffer = { buf in sink?.yield(AnalyzerInput(buffer: buf)) }
        tap.onLevel = { [weak self] level in
            Task { @MainActor in self?.delegate?.listener(level: level) }
        }
        Log.say("audio · wired (device opens only while recording)")
    }

    private func openMicrophone() {
        guard engine == nil, let outFormat = analyzerFormat else { return }
        let e = AVAudioEngine()
        let input = e.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else { Log.say("audio · input unavailable"); return }
        tap.configure(from: inFormat, to: outFormat)
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [tap] buf, _ in
            tap.receive(buf)
        }
        e.prepare()
        do { try e.start() } catch {
            Log.say("audio · could not start — \(error.localizedDescription)"); return
        }
        engine = e
        Log.say("audio · open \(Int(inFormat.sampleRate))→\(Int(outFormat.sampleRate))")
    }

    private func closeMicrophone() {
        guard let e = engine else { return }
        e.stop()
        e.inputNode.removeTap(onBus: 0)
        engine = nil
        delegate?.listener(level: 0)
        Log.say("audio · closed")
    }

    // MARK: - Errors

    enum Err: Error { case msg(String) }

    private func short(_ e: Error) -> String {
        if case Err.msg(let m) = e { return m }
        let ns = e as NSError
        return "\(ns.localizedDescription) (\(ns.domain) \(ns.code))"
    }
}

import AVFoundation
import Foundation
import Speech

/// Proves the transcription path end-to-end without a microphone.
///
/// `--check` only proved the listener reached `.ready`, which it does even when
/// the analyzer silently produces nothing — the exact failure that shipped.
/// This pushes known speech through the same converter and the same analyzer
/// input stream the tap uses, so a pass either yields words or names where it
/// stopped.
@MainActor
enum Probe {
    static func run(_ phrase: String) async -> Bool {
        let spoken = "/tmp/ambient-probe.aiff"
        let say = Process()
        say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        say.arguments = ["-o", spoken, phrase]
        do { try say.run() } catch { print("could not synthesise speech: \(error)"); return false }
        say.waitUntilExit()
        guard FileManager.default.fileExists(atPath: spoken) else {
            print("no audio produced"); return false
        }
        print("spoke:  “\(phrase)”")

        let locale = Locale(identifier: "en-US")
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [.volatileResults],
                                            attributeOptions: [.audioTimeRange])

        guard let installed = try? await SpeechTranscriber.installedLocales,
              installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) })
        else { print("FAIL · en-US model not installed"); return false }

        guard let analyzerFormat = await SpeechAnalyzer
            .bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            print("FAIL · no compatible audio format"); return false
        }

        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        var heard = ""
        let collector = Task {
            do {
                for try await result in transcriber.results where result.isFinal {
                    heard += String(result.text.characters)
                }
            } catch { print("results error: \(error)") }
        }

        do { try await analyzer.start(inputSequence: stream) }
        catch { print("FAIL · analyzer refused to start: \(error)"); return false }

        // Same conversion the microphone tap performs.
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: spoken)),
              let converter = AVAudioConverter(from: file.processingFormat, to: analyzerFormat) else {
            print("FAIL · could not open or convert the audio"); return false
        }
        var fed = 0
        while true {
            guard let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096),
                  (try? file.read(into: inBuf)) != nil, inBuf.frameLength > 0 else { break }
            let ratio = analyzerFormat.sampleRate / file.processingFormat.sampleRate
            let cap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio + 1024)
            guard let out = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: cap) else { break }
            var err: NSError?
            var served = false
            converter.convert(to: out, error: &err) { _, status in
                if served { status.pointee = .noDataNow; return nil }
                served = true; status.pointee = .haveData; return inBuf
            }
            guard err == nil, out.frameLength > 0 else { break }
            fed += Int(out.frameLength)
            cont.yield(AnalyzerInput(buffer: out))
        }
        print("fed:    \(fed) frames at \(Int(analyzerFormat.sampleRate)) Hz")

        cont.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        _ = await collector.result

        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        print("heard:  “\(text)”")
        if text.isEmpty {
            print("FAIL · analyzer accepted audio and returned nothing")
            return false
        }
        print("PASS · transcription path works")
        return true
    }
}

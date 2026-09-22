import AppKit

/// Released work is handed to ~/.ambient/dispatch.sh. Nothing is wired to a
/// specific agent, so changing where work goes is an edit to five lines.
enum Dispatch {

    static var hook: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ambient/dispatch.sh")
    }

    static func installDefaultHookIfMissing() {
        let dir = hook.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: hook.path) else { return }
        let script = """
        #!/bin/zsh
        # Ambient dispatch hook — receives one confirmed instruction.
        #
        #   $AMBIENT_TASK     the instruction, formatted for an agent
        #   $AMBIENT_APP      app that was under the cursor
        #   $AMBIENT_CONTEXT  what was on screen, one line per target
        #
        # Whatever this prints is spoken back and shown on the panel, so keep it
        # to one short line. Default: queue it and put it on the clipboard.

        QUEUE="$HOME/.ambient/queue"
        mkdir -p "$QUEUE"
        STAMP=$(date +%Y%m%d-%H%M%S)
        printf '%s\\n' "$AMBIENT_TASK" > "$QUEUE/$STAMP.txt"
        printf '%s' "$AMBIENT_TASK" | pbcopy
        echo "queued · on clipboard"
        """
        try? script.write(to: hook, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)
    }

    static func run(task: String, app: String, context: String) async -> (ok: Bool, text: String) {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/zsh")
                p.arguments = [hook.path]
                var env = ProcessInfo.processInfo.environment
                env["AMBIENT_TASK"] = task
                env["AMBIENT_APP"] = app
                env["AMBIENT_CONTEXT"] = context
                p.environment = env
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do { try p.run() } catch {
                    cont.resume(returning: (false, error.localizedDescription)); return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let out = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                cont.resume(returning: (p.terminationStatus == 0,
                                        out.isEmpty ? "exit \(p.terminationStatus)" : String(out.suffix(240))))
            }
        }
    }
}

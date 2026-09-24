import AppKit
import AVFoundation
import Combine
import Speech
import SwiftUI

/// Borderless, but still able to take key input.
///
/// A `.titled` window with a transparent background still draws the system's
/// own window shadow around the whole frame — which is larger than the card
/// inside it and carries the titled corner radius, so it reads as a ghost
/// outline floating behind the panel. Borderless removes that chrome; this
/// subclass restores the one thing borderless gives up.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ListenerDelegate, NSMenuDelegate {
    private var review: NSPanel!
    private var settings: NSPanel!
    private var welcome: NSPanel!
    private var bottom: NSPanel!
    private var rail: NSPanel!
    private var pill: NSPanel!
    private var pillTimer: Timer?
    private var status: NSStatusItem!
    private let listener = Listener()
    private let session = Session.shared
    private var monitors: [Any] = []
    private var bag = Set<AnyCancellable>()
    private var held = false

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Type.register()
        stayAwake()
        Dispatch.installDefaultHookIfMissing()
        buildBottom()
        buildSurfaces()
        buildReview()
        buildSettings()
        buildWelcome()
        buildStatusItem()
        session.onPassEnded = { [weak self] in self?.showReview() }
        Notes.shared.$items
            .sink { [weak self] items in self?.status?.length = items.isEmpty ? 38 : 54 }
            .store(in: &bag)
        Pointer.shared.start()
        Log.say("permissions · screenRecording=\(Shot.permitted) accessibility=\(Pointer.axTrusted)")
        Log.say("model · \(Local.readiness)")
        // Ask for both up front, at launch, together. Deferring the screen
        // request until after the model check meant it could never fire on a
        // machine where something earlier returned first.
        // On a first run the onboarding asks for these, each on the screen that
        // explains it. Firing the prompts here as well would be the batch of
        // unexplained dialogs it exists to avoid.
        if !Welcome.seen {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showWelcome()
            }
        } else {
            if !Pointer.axTrusted { Pointer.requestAX() }
            if !Shot.permitted { _ = Shot.requestPermission() }
        }
        watchPermissions()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.listener.refresh() }
        }
        Task { await Updates.shared.check() }
        hotkeys()
        observe()
        watchAccessibility()

        listener.delegate = self
        Task {
            Log.say("startup · authorizing")
            guard await authorize() else {
                session.phase = .failed("Microphone or speech access denied. Grant it in Privacy & Security.")
                session.show()
                return
            }
            Log.say("startup · authorized, preparing listener")
            await listener.prepare()
            Log.say("startup · listener prepared")
            announceBrain()
        }
    }

    /// Permission state read once at launch cannot show a grant that arrives a
    /// minute later — and macOS only hands screen access to a process that
    /// started after the grant. Both facts together meant granting correctly
    /// still looked like nothing happening. Watch for it and restart.
    private var sawScreen = Shot.permitted
    private var sawAX = Pointer.axTrusted

    private func watchPermissions() {
        let t = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                let screen = Shot.permitted
                let ax = Pointer.axTrusted

                if ax != self.sawAX {
                    self.sawAX = ax
                    Log.say("permissions · accessibility -> \(ax)")
                    if ax { self.session.announce("Accessibility granted.", ok: true) }
                }
                if screen != self.sawScreen {
                    self.sawScreen = screen
                    Log.say("permissions · screenRecording -> \(screen)")
                    if screen { self.restartForScreenAccess() }
                }
                // Once everything is granted there is nothing left to watch.
                if screen, ax { t.invalidate() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
    }

    /// Screen access only applies to a process launched after the grant, so the
    /// only honest response to being granted it is to come back.
    private func restartForScreenAccess() {
        session.announce("Screen Recording granted — restarting.", ok: true)
        let url = Bundle.main.bundleURL
        Log.say("restarting for screen access")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-n", url.path]
            try? p.run()
            NSApp.terminate(nil)
        }
    }

    /// Whether there is any real reading behind the voice is the single biggest
    /// determinant of how the thing feels. It should not take a conversation to
    /// find out that there isn't one.
    private func announceBrain() {
        if !Shot.permitted {
            session.announce("Screen Recording is off — notes can't show what you pointed at.", ok: false)
            return
        }
        if case .off(let why) = Local.readiness, !Brain.connected {
            session.announce("No model yet — \(why)", ok: false)
        }
    }

    /// An accessory app with no visible window is a prime candidate for App Nap,
    /// which throttles timers and event monitors — so the chord stops being
    /// noticed until you bring the app forward, which for a background tool is
    /// indistinguishable from it being dead.
    private var activity: NSObjectProtocol?

    private func stayAwake() {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .suddenTerminationDisabled, .automaticTerminationDisabled],
            reason: "Listening for the capture chord")
    }

    /// Only ever *ask* when the answer is unknown.
    ///
    /// Re-requesting an already-granted permission on every launch is not free:
    /// the callback sometimes never fires, and because the whole startup awaits
    /// it, the app would sit there with no microphone and no explanation. This
    /// was the intermittent "completely broken" launch.
    private func authorize() async -> Bool {
        let speech: Bool
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            speech = await withCheckedContinuation { c in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
            }
        case .authorized:
            speech = true
        default:
            speech = false
        }

        let mic: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: mic = await AVCaptureDevice.requestAccess(for: .audio)
        case .authorized:    mic = true
        default:             mic = false
        }

        Log.say("startup · speech=\(speech) mic=\(mic)")
        return speech && mic
    }

    // MARK: - Surfaces

    /// The reading surface. Everything with words in it lives down here, where
    /// the eye already is and where there is room to wrap.
    private func buildBottom() {
        bottom = overlayPanel(size: NSSize(width: 560 + Chrome.bleed * 2, height: 440))
        bottom.contentView = NSHostingView(rootView: HUD(s: session))
    }

    /// Two pass-through windows for the optional surfaces. Both are display
    /// only — the island remains the thing that answers.
    private func buildSurfaces() {
        rail = overlayPanel(size: NSSize(width: 460, height: 60))
        rail.contentView = NSHostingView(rootView: Rail(s: session).padding(10))

        pill = overlayPanel(size: NSSize(width: 380, height: 44))
        let host = NSHostingView(rootView:
            HStack { Pill(s: session); Spacer(minLength: 0) }.padding(6))
        pill.contentView = host
    }

    private func overlayPanel(size: NSSize) -> NSPanel {
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.sharingType = .none
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.alphaValue = 0
        return p          // ordered in only when it has something to show
    }

    /// The pill is only useful where the eye already is.
    private func followCursor() {
        pillTimer?.invalidate()
        guard session.showPill else { fade(pill, to: 0); return }
        let t = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.session.showPill else { return }
                let m = NSEvent.mouseLocation
                self.pill.setFrameOrigin(NSPoint(x: m.x + 14, y: m.y - self.pill.frame.height - 4))
            }
        }
        RunLoop.main.add(t, forMode: .common)
        pillTimer = t
    }

    private func placeSurfaces() {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        rail.setFrameOrigin(NSPoint(x: f.midX - rail.frame.width / 2, y: f.minY + 18))
        bottom.setFrameOrigin(NSPoint(x: f.midX - bottom.frame.width / 2,
                                      y: f.minY + (session.showRail ? 74 : 40)))
    }

    /// The review is a real window: it takes clicks, takes key, and closes on
    /// escape. The pass HUD deliberately cannot, so the two are separate.
    private func buildReview() {
        review = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 400),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        review.isMovableByWindowBackground = true
        review.backgroundColor = .clear
        review.isOpaque = false
        review.hasShadow = false        // the card draws its own
        review.level = .floating
        review.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        review.isReleasedWhenClosed = false

        let host = NSHostingView(rootView: Review(
            close: { [weak self] in self?.hideReview() },
            settings: { [weak self] in self?.hideReview(); self?.showSettings() }))
        review.contentView = host
        review.setContentSize(host.fittingSize)
    }

    private func buildSettings() {
        settings = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        settings.isMovableByWindowBackground = true
        settings.backgroundColor = .clear
        settings.isOpaque = false
        settings.hasShadow = false
        settings.level = .floating
        settings.isReleasedWhenClosed = false
        settings.sharingType = .none
        let host = NSHostingView(rootView:
            SettingsView(s: session, close: { [weak self] in self?.settings.orderOut(nil) }))
        settings.contentView = host
        settings.setContentSize(host.fittingSize)
    }

    private func buildWelcome() {
        welcome = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        welcome.isMovableByWindowBackground = true
        welcome.backgroundColor = .clear
        welcome.isOpaque = false
        welcome.hasShadow = false
        welcome.level = .floating
        welcome.isReleasedWhenClosed = false
        welcome.sharingType = .none
        let host = NSHostingView(rootView:
            WelcomeView(s: session, done: { [weak self] in self?.finishWelcome() }))
        welcome.contentView = host
        welcome.setContentSize(host.fittingSize)
    }

    @objc private func showWelcome() {
        Welcome.shared.step = 0
        Welcome.shared.heardSomething = false
        if let host = welcome.contentView as? NSHostingView<WelcomeView> {
            welcome.setContentSize(host.fittingSize)
        }
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            welcome.setFrameOrigin(NSPoint(x: f.midX - welcome.frame.width / 2,
                                           y: f.midY - welcome.frame.height / 2))
        }
        welcome.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finishWelcome() {
        Welcome.seen = true
        welcome.orderOut(nil)
    }

    @objc private func showSettings() {
        if let host = settings.contentView as? NSHostingView<SettingsView> {
            settings.setContentSize(host.fittingSize)
        }
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            settings.setFrameOrigin(NSPoint(x: f.midX - settings.frame.width / 2,
                                            y: f.midY - settings.frame.height / 2))
        }
        settings.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showReview() {
        guard !Notes.shared.isEmpty else {
            session.announce("Nothing recorded yet.", ok: false); return
        }
        session.visible = false
        if let host = review.contentView as? NSHostingView<Review> {
            review.setContentSize(host.fittingSize)
        }
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            review.setFrameOrigin(NSPoint(x: f.midX - review.frame.width / 2,
                                          y: f.midY - review.frame.height / 2))
        }
        review.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func hideReview() { review.orderOut(nil) }

    /// Top centre of the *whole* screen, not the visible frame — the island has
    /// to reach the notch, which sits above the menu bar.
    private func place() { placeSurfaces() }

    /// The window follows the session: on screen only when there is something to
    /// see, and clickable only while it is waiting on an answer.
    private func observe() {
        session.$visible
            .removeDuplicates()
            .sink { [weak self] on in
                guard let self else { return }
                self.placeSurfaces()
                self.fade(self.bottom, to: on ? 1 : 0)
            }
            .store(in: &bag)

        // The rail stands by whenever it is enabled; the pill only while the
        // cursor means something.
        Publishers.CombineLatest(session.$showRail, session.$visible)
            .sink { [weak self] on, _ in
                guard let self else { return }
                self.placeSurfaces()
                self.fade(self.rail, to: on ? 1 : 0)
            }
            .store(in: &bag)

        // Clickable only while it is genuinely on screen and not mid-pass. Any
        // other combination means a transparent window collecting clicks.
        session.$visible
            .combineLatest(session.$latched)
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.bottom.ignoresMouseEvents = !self.session.visible || self.session.engagedNow
            }
            .store(in: &bag)

        session.$captureOverlays
            .removeDuplicates()
            .sink { [weak self] on in
                guard let self else { return }
                let mode: NSWindow.SharingType = on ? .readOnly : .none
                self.bottom.sharingType = mode
                self.rail.sharingType = mode
                self.pill.sharingType = mode
            }
            .store(in: &bag)

        session.$showPill
            .removeDuplicates()
            .sink { [weak self] on in
                guard let self else { return }
                self.followCursor()
                self.fade(self.pill, to: on ? 1 : 0)
            }
            .store(in: &bag)
    }

    private func buildStatusItem() {
        // Explicit width: a hosted view can report zero intrinsic size, and a
        // zero-width status item is an app with no way to quit it.
        status = NSStatusBar.system.statusItem(withLength: 38)
        if let button = status.button {
            let host = NSHostingView(rootView: MenuBarView(s: session))
            host.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                host.topAnchor.constraint(equalTo: button.topAnchor),
                host.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
        }
        rebuildMenu()
    }

    /// Hidden means *gone*, not transparent.
    ///
    /// A borderless window left on screen at alpha 0 still receives clicks. The
    /// bottom panel was doing exactly that: invisible, 560×420, parked over the
    /// middle-bottom of the display, swallowing every click in that region for
    /// as long as the app was idle.
    private func fade(_ window: NSWindow, to alpha: CGFloat) {
        if alpha > 0 {
            window.alphaValue = window.isVisible ? window.alphaValue : 0
            window.orderFrontRegardless()
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = alpha > 0 ? 0.16 : 0.22
            window.animator().alphaValue = alpha
        }, completionHandler: {
            if alpha == 0 { window.orderOut(nil) }
        })
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let hint = NSMenuItem(title: session.engagedNow ? "Recording — tap ⌃ fn to finish"
                                                        : "Tap ⌃ fn to start a pass",
                              action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        let rev = NSMenuItem(title: Notes.shared.isEmpty ? "No notes yet"
                                  : "Review \(Notes.shared.count) notes…",
                             action: #selector(showReview), keyEquivalent: "r")
        rev.target = self
        rev.isEnabled = !Notes.shared.isEmpty
        menu.addItem(rev)

        let check = NSMenuItem(title: "Check capture", action: #selector(checkCapture), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        menu.addItem(.separator())

        let tour = NSMenuItem(title: "Show welcome…", action: #selector(showWelcome), keyEquivalent: "")
        tour.target = self
        menu.addItem(tour)

        let set = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        set.target = self
        menu.addItem(set)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Ambient", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
    }



    /// Copy the key, click once. Asking someone to hand-create a dotfile was a
    /// setup step that silently did nothing when it went wrong.
    @objc private func connectModel() {
        let raw = NSPasteboard.general.string(forType: .string) ?? ""
        guard Secrets.looksLikeKey(raw) else {
            session.announce("Copy your API key first — the clipboard doesn't have one.", ok: false)
            return
        }
        let key = Secrets.clean(raw)
        session.announce("Checking that key…", ok: true, speak: false)
        Task {
            if let why = await Brain.validate(key) {
                Secrets.clear()
                session.announce(why, ok: false)
            } else {
                Secrets.save(key)
                session.announce("Model connected.", ok: true)
            }
            rebuildMenu()
        }
    }

    @objc private func openIntelligenceSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?AppleIntelligence")!)
    }

    @objc private func disconnectModel() {
        Secrets.clear()
        rebuildMenu()
        session.announce("Model disconnected.", ok: true)
    }

    /// Verification has to run inside the app. Launching the binary from a
    /// terminal makes the terminal's owner the responsible process for TCC, so
    /// it can report success while Ambient itself has no permission at all —
    /// and it prompts the wrong application for the grant.
    @objc private func checkCapture() {
        guard Shot.permitted else {
            session.announce("Screen Recording is off for Ambient — Privacy & Security → Screen Recording → add Ambient.", ok: false)
            return
        }
        session.announce("Capturing a test frame…", ok: true)
        let r = Recorder.shared
        r.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                r.stop()
                let n = r.frameCount
                if let path = r.save(at: Date().addingTimeInterval(-0.5), id: "check") {
                    r.discard()
                    self.session.announce("\(n) frames — opening the test crop", ok: true)
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } else {
                    r.discard()
                    self.session.announce("Captured nothing — Ambient has no screen access.", ok: false)
                }
            }
        }
    }

    @objc private func openLedger() {
        let f = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ambient/ledger.log")
        if !FileManager.default.fileExists(atPath: f.path) {
            try? "".write(to: f, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.activateFileViewerSelecting([f])
    }

    @objc private func openHook() { NSWorkspace.shared.open(Dispatch.hook) }

    /// The hold-to-speak chord is read through a global event monitor, which
    /// silently receives nothing until Accessibility is granted. That failure is
    /// indistinguishable from a broken app, so it is stated on the panel and
    /// cleared the moment the grant lands.
    private func watchAccessibility() {
        guard !Pointer.axTrusted else { return }
        session.phase = .failed("Accessibility access needed — without it the ⌃ fn key can't be seen. Privacy & Security → Accessibility → add Ambient.")
        session.show()
        let t = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard Pointer.axTrusted else { return }
                timer.invalidate()
                guard let self else { return }
                if case .failed = self.session.phase {
                    self.session.phase = .idle
                    self.session.hide(after: 0.2)
                }
            }
        }
        RunLoop.main.add(t, forMode: .common)
    }

    // MARK: - Hold to speak

    private func hotkeys() {
        let flags = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            Task { @MainActor in self?.modifiers(e.modifierFlags) }
        })
        if let flags { monitors.append(flags) }

        let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] e in
            Task { @MainActor in self?.modifiers(e.modifierFlags) }
            return e
        })
        if let local { monitors.append(local) }

        let esc = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            if e.keyCode == 53, self?.review.isVisible == true { self?.hideReview(); return nil }
            return e
        })
        if let esc { monitors.append(esc) }

        let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] e in
            guard e.modifierFlags.contains(.option) else { return }
            Task { @MainActor in
                switch e.keyCode {
                case 36: self?.session.confirmPending()
                case 47: self?.session.declinePending()
                default: break
                }
            }
        })
        if let keys { monitors.append(keys) }
    }

    /// Tap to latch, or hold to talk.
    ///
    /// Holding Control turns every click into a secondary click, so a chord you
    /// must keep down makes it impossible to navigate the thing you are giving
    /// feedback on. A quick tap now latches the pass open and leaves both hands
    /// free; holding still works for a single remark.
    private var chordDownAt: Date?
    private var latched = false

    private func modifiers(_ f: NSEvent.ModifierFlags) {
        let want = f.contains(.function) && f.contains(.control)
        guard want != held else { return }
        held = want

        if want {
            chordDownAt = Date()
            if latched {
                latched = false
                endPass()
            } else {
                startPass()
            }
            return
        }

        let heldFor = Date().timeIntervalSince(chordDownAt ?? Date())
        if heldFor < 0.6, session.engagedNow {
            latched = true
            session.latched = true
        } else if !latched {
            endPass()
        }
    }

    /// A latched pass holds the microphone open with nothing held down. Walk
    /// away and it stays open — a battery and privacy cost with no upside.
    private var idleEnd: DispatchWorkItem?

    private func armIdleTimeout() {
        idleEnd?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, self.session.engagedNow, self.latched else { return }
            Log.say("pass · ended after 5 minutes with nothing said")
            self.endPass()
        }
        idleEnd = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 300, execute: w)
    }

    private func startPass() {
        session.latched = false
        session.engaged()
        listener.engage()
        armIdleTimeout()
    }

    private func endPass() {
        idleEnd?.cancel()
        session.latched = false
        session.released()
        Task {
            await listener.release()
            session.settle()
        }
    }

    // MARK: - ListenerDelegate

    /// Rebuilt on open so the connection state is never stale.
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in self.rebuildMenu() }
    }

    func listener(volatile text: String) {
        session.transcript = text
        if !text.isEmpty {
            armIdleTimeout()
            if !Welcome.seen { Welcome.shared.heardSomething = true }
        }
    }

    func listener(level: Double) { session.level = level }

    func listener(state: Listener.State) { session.listenerChanged(state) }

    func listener(finished u: Utterance) { session.heard(u) }
}

let args = CommandLine.arguments
if args.contains("--frames") {
    // Proves ScreenCaptureKit can actually grab frames under this app's identity.
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        Pointer.shared.start()
        guard Shot.permitted else {
            print("SCREEN RECORDING OFF — Privacy & Security → Screen Recording → add Ambient")
            exit(1)
        }
        let r = Recorder.shared
        r.start()
        print("recording 2s — move the cursor over something…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MainActor.assumeIsolated {
                r.stop()
                print("captured \(r.frameCount) frames in memory")
                if let p = r.save(at: Date().addingTimeInterval(-1), id: "frametest") {
                    print("wrote \(p)")
                    r.discard()
                    exit(0)
                }
                print("NO FRAME SAVED")
                exit(2)
            }
        }
    }
    NSApplication.shared.run()
}

if args.contains("--notes") {
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let n = Notes.shared
        print("\(n.count) note(s)\n")
        if args.contains("--raw") {
            print(n.bundle().isEmpty ? "(empty)" : n.bundle())
        } else {
            print(Enhance.brief(n.items).isEmpty ? "(empty)" : Enhance.brief(n.items))
        }
        if args.contains("--clear") { n.clear(); print("\ncleared") }
        exit(0)
    }
    NSApplication.shared.run()
}

if args.contains("--brain") {
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        switch Local.readiness {
        case .ready: print("ON-DEVICE MODEL READY — Apple Intelligence, no key needed")
        case .off(let why): print("ON-DEVICE MODEL OFF — \(why)")
        }
        print("schema built: \(Schema.generation != nil)")
        print("cloud key stored: \(Secrets.present)")
        print("screen recording: \(Shot.permitted)")
        exit(0)
    }
    NSApplication.shared.run()
}

if args.contains("--ask") {
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let phrase = Array(args.drop(while: { $0 != "--ask" }).dropFirst())
            .first(where: { !$0.hasPrefix("--") }) ?? "can you hear me"
        Pointer.shared.start()
        print("ask · “\(phrase)”")
        Task {
            let t = Pointer.shared.latest.map { Pointer.resolve($0) }
            guard let (u, act) = await Local.read(heard: phrase, targets: t.map { [$0] } ?? []) else {
                print("NO LOCAL MODEL"); exit(1)
            }
            print("  reply:  “\(u.reply)”")
            print("  action: \(act)")
            exit(0)
        }
    }
    NSApplication.shared.run()
}

if args.contains("--parse") {
    // Exercise the whole action vocabulary without performing anything.
    _ = NSApplication.shared
    let phrases = args.contains("--all") ? [
        "what is this", "read this to me", "click this", "press that button",
        "copy this", "open figma", "launch terminal", "show this in finder",
        "type hello there", "screenshot this", "close this window", "quit this app",
        "crop this down to the hero", "hey what's going on"
    ] : Array(args.drop(while: { $0 != "--parse" }).dropFirst())
    for p in phrases where !p.hasPrefix("--") {
        print(String(format: "%-34@ → %@", p as NSString, "\(Actions.parse(p))" as NSString))
    }
    exit(0)
}

if args.contains("--connect") {
    // Same path as the menu item, for when you are already in a terminal.
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let raw = NSPasteboard.general.string(forType: .string) ?? ""
        guard Secrets.looksLikeKey(raw) else {
            print("NOTHING TO CONNECT — copy your Anthropic API key first (clipboard has \(raw.count) chars)")
            exit(1)
        }
        let key = Secrets.clean(raw)
        print("checking \(key.prefix(7))… (\(key.count) chars)")
        Task {
            if let why = await Brain.validate(key) {
                Secrets.clear()
                print("REJECTED — \(why)")
                exit(2)
            }
            Secrets.save(key)
            print("CONNECTED — key stored in the keychain")
            exit(0)
        }
    }
    NSApplication.shared.run()
}

if args.contains("--model") {
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        guard let k = Secrets.load() else { print("NO KEY STORED"); exit(1) }
        print("key stored · \(k.prefix(7))… (\(k.count) chars)")
        Task {
            if let why = await Brain.validate(k) { print("REJECTED — \(why)"); exit(2) }
            print("MODEL OK — key works"); exit(0)
        }
    }
    NSApplication.shared.run()
}
if args.contains("--selftest") {
    // Drives a whole turn with a synthetic utterance — everything downstream of
    // transcription. Two builds in a row ended in a state that never resolved;
    // this is how that stops being discovered by the user.
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        Pointer.shared.start()
        let s = Session.shared
        var seen: [String] = []
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { t in
            MainActor.assumeIsolated {
                let now = "\(s.phase)"
                if seen.last != now { seen.append(now); print("  → \(now)") }
                switch s.phase {
                case .reported, .replying, .failed:
                    t.invalidate()
                    print("  says: “\(s.spoken)”")
                    print(s.awaitingConfirmation ? "RESOLVED (awaiting answer)" : "RESOLVED")
                    exit(0)
                default: break
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 14) {
            print("HUNG — phase never resolved: \(seen)"); exit(1)
        }
        let custom = Array(args.drop(while: { $0 != "--selftest" }).dropFirst())
            .first(where: { !$0.hasPrefix("--") })
        let spoken = args.contains("--empty") ? "" : (custom ?? "open this folder")
        print("selftest · “\(spoken)”")
        let u = Utterance(words: spoken.isEmpty ? [] :
                          spoken.split(separator: " ").map { StampedWord(text: String($0), t: Date()) },
                          text: spoken)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { s.heard(u) } }
    }
    NSApplication.shared.run()
}
if args.contains("--loopback") {
    // The complete chain including the microphone: speak through the
    // speakers, listen with the real input, report what came back.
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        final class Sink: ListenerDelegate {
            var text = ""
            var peak = 0.0
            func listener(volatile t: String) {}
            func listener(finished u: Utterance) { text = u.text }
            func listener(state s: Listener.State) {}
            func listener(level: Double) { peak = max(peak, level) }
        }
        let sink = Sink()
        let l = Listener()
        l.delegate = sink
        Task {
            let phrase = "the spacing under this heading is far too tight"
            let file = "/tmp/ambient-loop.aiff"
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-o", file, phrase]
            try? say.run(); say.waitUntilExit()

            await l.prepare()
            l.engage()
            try? await Task.sleep(nanoseconds: 300_000_000)

            let play = Process()
            play.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
            play.arguments = [file]
            try? play.run()
            play.waitUntilExit()

            try? await Task.sleep(nanoseconds: 600_000_000)
            await l.release()
            print("mic level peak · \(String(format: "%.3f", sink.peak))")
            print("heard          · “\(sink.text)”")
            if sink.text.isEmpty {
                print("FAIL · microphone audio produced no transcript")
                exit(1)
            }
            print("PASS · full chain works, microphone included")
            exit(0)
        }
    }
    NSApplication.shared.run()
}

if args.contains("--mic") {
    // Is the input device actually delivering signal? Everything downstream
    // is proven; this is the last unknown.
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        print("input device · \(Int(fmt.sampleRate)) Hz · \(fmt.channelCount) ch")
        var peak: Float = 0
        var frames = 0
        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { buf, _ in
            frames += Int(buf.frameLength)
            guard let ch = buf.floatChannelData?[0] else { return }
            for i in 0..<Int(buf.frameLength) { peak = max(peak, abs(ch[i])) }
        }
        engine.prepare()
        do { try engine.start() } catch {
            print("FAIL · engine would not start: \(error)"); exit(1)
        }
        print("listening 4s — say something")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            engine.stop()
            print("frames · \(frames)")
            print("peak   · \(String(format: "%.4f", peak))")
            if frames == 0 { print("FAIL · no buffers at all from the input device") }
            else if peak < 0.001 { print("FAIL · buffers arriving but SILENT (peak \(peak))") }
            else { print("PASS · microphone is delivering signal") }
            exit(peak < 0.001 ? 1 : 0)
        }
    }
    NSApplication.shared.run()
}

if args.contains("--probe-live") {
    // The same audio, but through the real Listener: prepare → engage →
    // feed → release. Isolates everything except the microphone hardware.
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        final class Sink: ListenerDelegate {
            var text = ""
            var words = 0
            func listener(volatile t: String) {}
            func listener(finished u: Utterance) { text = u.text; words = u.words.count }
            func listener(state s: Listener.State) { print("  state · \(s)") }
            func listener(level: Double) {}
        }
        let sink = Sink()
        let l = Listener()
        l.delegate = sink
        Task {
            let phrase = "the spacing under this heading is too tight"
            let out = "/tmp/ambient-probe.aiff"
            let say = Process()
            say.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            say.arguments = ["-o", out, phrase]
            try? say.run(); say.waitUntilExit()

            await l.prepare()
            l.engage()
            let fed = l.inject(URL(fileURLWithPath: out))
            print("  fed \(fed) frames through the live feed")
            try? await Task.sleep(nanoseconds: 400_000_000)
            await l.release()
            print("  heard: “\(sink.text)” (\(sink.words) words)")
            if sink.text.isEmpty {
                print("FAIL · live path swallowed the audio")
                exit(1)
            }
            print("PASS · live path works")
            exit(0)
        }
    }
    NSApplication.shared.run()
}

if args.contains("--probe") {
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let phrase = Array(args.drop(while: { $0 != "--probe" }).dropFirst())
            .first(where: { !$0.hasPrefix("--") }) ?? "the spacing under this heading is too tight"
        Task { exit(await Probe.run(phrase) ? 0 : 1) }
    }
    NSApplication.shared.run()
}

if args.contains("--recover") {
    // Proves the listener rebuilds itself instead of sitting there looking
    // healthy — the "it stops working until I restart it" bug.
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        let l = Listener()
        Task {
            await l.prepare()
            guard case .ready = l.state else { print("FAILED to prepare: \(l.state)"); exit(1) }
            print("1. prepared            → \(l.state)")
            for i in 1...3 {
                await l.refresh()
                guard case .ready = l.state else {
                    print("BROKE after rebuild \(i): \(l.state)"); exit(2)
                }
                print("\(i + 1). rebuilt (cycle \(i))  → \(l.state)")
            }
            print("RECOVERS — three teardown/rebuild cycles, still ready")
            exit(0)
        }
    }
    NSApplication.shared.run()
}

if args.contains("--check") {
    // Proves the transcription pipeline reaches ready — model installed, audio
    // running — without anyone having to speak.
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        print("accessibility trusted: \(Pointer.axTrusted)")
        let l = Listener()
        Task {
            await l.prepare()
            switch l.state {
            case .ready:            print("READY — transcription live"); exit(0)
            case .preparing(let m): print("STILL PREPARING — \(m)"); exit(3)
            case .failed(let m):    print("FAILED — \(m)"); exit(2)
            case .hearing:          print("READY"); exit(0)
            }
        }
    }
    NSApplication.shared.run()
}
if args.contains("--render-welcome"), let i = args.firstIndex(of: "--render-welcome"), i + 1 < args.count {
    _ = NSApplication.shared
    let step = Int(args.dropFirst(i + 2).first ?? "0") ?? 0
    MainActor.assumeIsolated { Type.register(); Render.welcome(path: args[i + 1], step: step) }
}

if args.contains("--render-settings"), let i = args.firstIndex(of: "--render-settings"), i + 1 < args.count {
    _ = NSApplication.shared
    MainActor.assumeIsolated { Type.register(); Render.settings(path: args[i + 1]) }
}

if args.contains("--render-review"), let i = args.firstIndex(of: "--render-review"), i + 1 < args.count {
    _ = NSApplication.shared
    MainActor.assumeIsolated { Render.review(path: args[i + 1]) }
}

if args.contains("--render"), let i = args.firstIndex(of: "--render"), i + 1 < args.count {
    _ = NSApplication.shared
    MainActor.assumeIsolated { Render.run(path: args[i + 1]) }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()

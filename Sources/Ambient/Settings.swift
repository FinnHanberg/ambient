import AppKit
import SwiftUI

/// One window, no sidebar, no tabs — rows in sections, the way a Mac settings
/// pane is built. The plan sits at the top: it is the only row that asks for
/// something, and burying an ask reads as either shame or a trap.
struct SettingsView: View {
    @ObservedObject var s: Session
    @ObservedObject var usage = Usage.shared
    @ObservedObject var voice = Voice.shared
    @ObservedObject var updates = Updates.shared
    @ObservedObject var license = License.shared
    @State private var key = ""
    var close: () -> Void
    /// ImageRenderer cannot draw ScrollView contents; the static render lays
    /// the rows out directly instead.
    var scrolls: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "Ambient", meta: "0.1", trailing: { EmptyView() }, close: close)
            Divider().overlay(Chrome.rule)

            Group {
                let rows = VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(text: "Plan")
                    PlanCard()

                    if license.sellable { licenceRow }

                    SectionLabel(text: "Capture")
                    row("command", "Chord", "Tap to start a pass, tap to finish") {
                        Text("⌃ fn").font(Type.meta(12)).foregroundStyle(.white.opacity(0.55))
                    }
                    row("camera.viewfinder", "Screenshots",
                        Shot.permitted ? "Skipped while a password field is open"
                                       : "Screen Recording is off") { state(Shot.permitted) }
                    row("accessibility", "Accessibility",
                        "Needed to see the chord and what you point at") { state(Pointer.axTrusted) }

                    SectionLabel(text: "Output")
                    row("wand.and.sparkles", "Clean up transcripts",
                        "Rewrites filler and “this” into an instruction") {
                        Switch(on: .constant(true), enabled: false)
                    }
                    row("speaker.wave.2", "Spoken replies", "Never during a pass") {
                        Switch(on: Binding(get: { !voice.muted }, set: { voice.muted = !$0 }))
                    }
                    row("brain", "On-device model",
                        Local.available ? "Apple Intelligence" : "Apple Intelligence is off") {
                        state(Local.available)
                    }

                    SectionLabel(text: "About")
                    row("arrow.down.circle", "Version",
                        updates.available ? "Version \(updates.latest ?? "") is available"
                                          : "You're on the latest build") {
                        if updates.available, let page = updates.page {
                            PillButton(label: "Get it") { NSWorkspace.shared.open(page) }
                        } else {
                            Text(updates.current).font(Type.meta(12))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }

                    SectionLabel(text: "Surfaces")
                    row("rectangle.bottomthird.inset.filled", "Bottom rail",
                        "A status strip while a pass runs") { Switch(on: $s.showRail) }
                    row("cursorarrow.rays", "Cursor pill",
                        "Names what the next “this” will bind to") { Switch(on: $s.showPill) }
                    row("eye", "Include Ambient in screenshots",
                        "For giving feedback on Ambient itself") { Switch(on: $s.captureOverlays) }
                }
                .padding(.bottom, 8)

                if scrolls { ScrollView { rows }.frame(maxHeight: 440) } else { rows }
            }

            Divider().overlay(Chrome.rule)
            footer
        }
        .panelCard(width: 460)
    }

    /// Only shown once a licence server is configured — an app with no paid
    /// tier should not display an empty one.
    @ViewBuilder
    private var licenceRow: some View {
        switch license.status {
        case .active(let masked):
            row("checkmark.seal", "Licence", masked) {
                QuietButton(label: "Remove") { license.deactivate() }
            }
        default:
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 12) {
                    Image(systemName: "key").font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.42)).frame(width: 18)
                    TextField("Licence key", text: $key)
                        .textFieldStyle(.plain)
                        .font(Type.ui(12.5))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7)
                            .fill(.white.opacity(0.05))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Chrome.hair, lineWidth: 1)))
                    PillButton(label: license.busy ? "Checking" : "Activate", strong: true) {
                        Task { await license.activate(key) }
                    }
                }
                if case .refused(let why) = license.status {
                    Text(why).font(Type.ui(11)).foregroundStyle(.white.opacity(0.55))
                        .padding(.leading, 30)
                }
            }
            .padding(.horizontal, Chrome.gutter).padding(.vertical, 9)
        }
    }

    // MARK: - Rows

    private func row<C: View>(_ icon: String, _ label: String, _ detail: String,
                              @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.42))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(Type.ui(13)).foregroundStyle(.white.opacity(0.92))
                Text(detail).font(Type.ui(11)).foregroundStyle(.white.opacity(0.36))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            control()
        }
        .padding(.horizontal, Chrome.gutter)
        .padding(.vertical, 9)
    }

    private func state(_ ok: Bool) -> some View {
        Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(ok ? 0.5 : 0.8))
    }

    private var footer: some View {
        HStack(spacing: 14) {
            QuietButton(label: "Record", icon: "doc.text") {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [FileManager.default.homeDirectoryForCurrentUser
                        .appendingPathComponent(".ambient/ledger.log")])
            }
            QuietButton(label: "Diagnostics", icon: "ladybug") {
                NSWorkspace.shared.activateFileViewerSelecting([Log.url])
            }
            Spacer()
            QuietButton(label: "Quit", icon: "power") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, Chrome.gutter)
        .padding(.vertical, 13)
    }
}

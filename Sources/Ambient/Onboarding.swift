import AppKit
import SwiftUI

/// First run.
///
/// Four screens, and the tool is usable after the third. No account: an app
/// that asks who you are before it has done anything for you loses people at
/// the one moment they were willing to try it. Each permission is asked on the
/// screen that shows why it exists, never in a batch up front.
@MainActor
final class Welcome: ObservableObject {
    static let shared = Welcome()

    @Published var step = 0
    @Published var heardSomething = false

    static var seen: Bool {
        get { UserDefaults.standard.bool(forKey: "ambient.onboarded") }
        set { UserDefaults.standard.set(newValue, forKey: "ambient.onboarded") }
    }

    var canAdvance: Bool {
        switch step {
        case 1:  return heardSomething
        case 2:  return Shot.permitted && Pointer.axTrusted
        default: return true
        }
    }
}

struct WelcomeView: View {
    @ObservedObject var w = Welcome.shared
    @ObservedObject var s: Session
    var done: () -> Void
    var scrolls: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "Ambient", meta: step, trailing: { EmptyView() }, close: done)
            Divider().overlay(Chrome.rule)

            Group {
                switch w.step {
                case 0: intro
                case 1: chord
                case 2: permissions
                default: finish
                }
            }
            .frame(height: 230, alignment: .topLeading)

            Divider().overlay(Chrome.rule)
            footer
        }
        .panelCard(width: 480)
    }

    private var step: String { "\(w.step + 1) of 4" }

    // MARK: - Screens

    private var intro: some View {
        screen(title: "Say what's wrong.\nGet a brief.",
               body: "Hold a key, walk a page, and talk while pointing at things. Every remark becomes a note with a picture of exactly what your cursor was on when you said it.") {
            EmptyView()
        }
    }

    private var chord: some View {
        screen(title: "Tap ⌃ fn and say something.",
               body: w.heardSomething
                    ? "That's it. Tap it again to finish a pass."
                    : "Tap the two keys together, say anything, then tap again. Nothing is saved yet.") {
            HStack(spacing: 10) {
                key("control"); key("fn")
                Spacer()
                if w.heardSomething {
                    Label("heard you", systemImage: "checkmark.circle.fill")
                        .font(Type.ui(12))
                        .foregroundStyle(.white.opacity(0.65))
                } else {
                    Waveform(level: s.level)
                }
            }
        }
    }

    private var permissions: some View {
        screen(title: "Two permissions.",
               body: "Ambient asks for each one only where it matters. Nothing leaves your machine.") {
            VStack(spacing: 9) {
                permission("camera.viewfinder", "Screen Recording",
                           "So a note can show what you pointed at",
                           granted: Shot.permitted) {
                    _ = Shot.requestPermission()
                }
                permission("accessibility", "Accessibility",
                           "So the chord works and it can read what's under the cursor",
                           granted: Pointer.axTrusted) {
                    Pointer.requestAX()
                }
            }
        }
    }

    private var finish: some View {
        screen(title: "That's everything.",
               body: "Tap ⌃ fn to start a pass, tap again to finish. The panel shows what it caught, and you copy it or paste it into Claude.") {
            HStack(spacing: 7) {
                Image(systemName: "sparkles").font(.system(size: 11))
                Text("100 notes free, then 25 a month. Capture is never counted.")
                    .font(Type.ui(11.5))
            }
            .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: - Parts

    private func screen<C: View>(title: String, body: String,
                                 @ViewBuilder extra: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Type.ui(21, .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(body)
                .font(Type.ui(13))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            extra()
        }
        .padding(.horizontal, Chrome.gutter)
        .padding(.top, 20).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func key(_ symbol: String) -> some View {
        Text(symbol == "control" ? "⌃" : "fn")
            .font(Type.ui(13, .medium))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 34, height: 28)
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(.white.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Chrome.hair, lineWidth: 1)))
    }

    private func permission(_ icon: String, _ name: String, _ why: String,
                            granted: Bool, ask: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.42)).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(Type.ui(13)).foregroundStyle(.white.opacity(0.92))
                Text(why).font(Type.ui(11)).foregroundStyle(.white.opacity(0.36))
            }
            Spacer(minLength: 8)
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.55))
            } else {
                PillButton(label: "Allow", strong: true, action: ask)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i == w.step ? 0.7 : 0.15))
                    .frame(width: i == w.step ? 14 : 5, height: 5)
            }
            Spacer()
            if w.step < 3 {
                QuietButton(label: "Skip", action: done)
                PillButton(label: w.step == 2 && !w.canAdvance ? "Waiting" : "Continue",
                           strong: true) {
                    if w.canAdvance { w.step += 1 }
                }
                .opacity(w.canAdvance ? 1 : 0.45)
            } else {
                PillButton(label: "Start using it", strong: true, action: done)
            }
        }
        .padding(.horizontal, Chrome.gutter).padding(.vertical, 13)
        .animation(.easeOut(duration: 0.18), value: w.step)
    }
}

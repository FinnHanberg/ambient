import SwiftUI

/// The reading surface. One card, the same card as every other panel: 12pt
/// radius, a hairline, one restrained shadow. Nothing here is a special case.
struct HUD: View {
    @ObservedObject var s: Session
    @ObservedObject var notes = Notes.shared

    init(s: Session) { self.s = s }

    private let hair = Color.white.opacity(0.12)

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if s.visible {
                card.transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .padding(18)
        .frame(width: 560, alignment: .bottom)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: s.visible)
        .animation(.easeOut(duration: 0.16), value: s.phase)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 11) {
            status
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.055))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(hair, lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 14, y: 4)
        )
        .overlay(alignment: .topTrailing) { closeButton }
    }

    // MARK: - Status line

    private var status: some View {
        HStack(spacing: 9) {
            mark
            Text(label)
                .font(Type.meta(9.5, .medium))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.42))
            Spacer(minLength: 24)
            if notes.count > 0 {
                Text("\(notes.count)")
                    .font(Type.meta(10.5, .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 7).padding(.vertical, 1.5)
                    .background(Capsule().strokeBorder(hair, lineWidth: 1))
                    .padding(.trailing, s.engagedNow ? 0 : 22)
            }
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch s.phase {
        case .hearing:                  Waveform(level: s.level)
        case .thinking, .acting:        Pulse()
        case .noted:                    symbol("checkmark")
        case .reported(_, let ok):      symbol(ok ? "checkmark" : "exclamationmark.triangle")
        case .failed:                   symbol("exclamationmark.triangle")
        case .preparing:                Pulse()
        default:                        symbol("waveform")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .frame(width: 18, alignment: .leading)
    }

    private var label: String {
        switch s.phase {
        case .hearing:      return s.latched ? "RECORDING" : "LISTENING"
        case .thinking:     return "READING"
        case .acting:       return "WORKING"
        case .noted:        return "NOTED"
        case .preparing:    return "STARTING"
        case .failed:       return "NOT LISTENING"
        case .reported:     return "DONE"
        case .replying:     return "REPLY"
        case .idle:         return notes.isEmpty ? "READY" : "PAUSED"
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        switch s.phase {
        case .idle:
            line(notes.isEmpty ? "Tap ⌃ fn and say what's wrong."
                               : "\(notes.count) notes held. Tap ⌃ fn to add more.")

        case .preparing(let m):
            line(m)

        case .failed(let m):
            line(m, strong: true)

        case .hearing:
            VStack(alignment: .leading, spacing: 8) {
                Text(s.transcript.isEmpty ? "Say what's wrong while pointing at it."
                                          : s.transcript)
                    .font(Type.ui(15))
                    .foregroundStyle(.white.opacity(s.transcript.isEmpty ? 0.3 : 0.96))
                    .fixedSize(horizontal: false, vertical: true)
                if !s.binding.isEmpty { binding }
            }

        case .noted(let text):
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(Type.ui(14))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                if !s.binding.isEmpty { binding }
            }

        case .thinking, .acting:
            EmptyView()

        case .reported(let text, _):
            line(text, strong: true)

        case .replying(let detail):
            VStack(alignment: .leading, spacing: 5) {
                Text(s.spoken).font(Type.ui(14, .medium)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(Type.meta(10.5)).foregroundStyle(.white.opacity(0.4))
                    .lineLimit(2)
            }
        }
    }

    private func line(_ text: String, strong: Bool = false) -> some View {
        Text(text)
            .font(Type.ui(strong ? 14 : 13))
            .foregroundStyle(.white.opacity(strong ? 0.9 : 0.5))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// What the next “this” will bind to.
    private var binding: some View {
        HStack(spacing: 6) {
            Image(systemName: "scope")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.35))
            Text(s.binding)
                .font(Type.meta(10))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(0.05))
            .overlay(Capsule().strokeBorder(hair, lineWidth: 1)))
    }

    /// Every panel gets a way out; waiting for a timer is not a dismissal.
    @ViewBuilder
    private var closeButton: some View {
        if !s.engagedNow {
            Button { s.dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }
}

/// Bars that answer to the microphone. A dead input and a quiet room are
/// otherwise the same picture.
struct Waveform: View {
    let level: Double
    private let weights: [Double] = [0.5, 0.85, 1.0, 0.7, 0.42]

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(0.8))
                    .frame(width: 2.5, height: max(3, 3 + level * 14 * weights[i]))
            }
        }
        .frame(width: 18, height: 17)
        .animation(.spring(response: 0.18, dampingFraction: 0.6), value: level)
    }
}

struct Pulse: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(.white.opacity(on ? 0.65 : 0.2))
            .frame(width: 6, height: 6)
            .frame(width: 18, alignment: .leading)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

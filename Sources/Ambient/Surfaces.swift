import AppKit
import SwiftUI

/// Two optional capture surfaces, asked for by voice.
///
/// Neither replaces the island — they answer different questions. The rail says
/// "a pass is running" from the calmest place on screen; the pill says "this is
/// what the next 'this' will bind to", right where you are looking.
struct Rail: View {
    @ObservedObject var s: Session
    @ObservedObject var notes = Notes.shared

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(s.engagedNow ? Color(red: 0.78, green: 0.33, blue: 0.24)
                                   : .white.opacity(0.25))
                .frame(width: 7, height: 7)
            Text(s.engagedNow ? "RECORDING" : "READY")
                .font(Type.meta(10, .medium))
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.55))
            if notes.count > 0 {
                Text("\(notes.count)")
                    .font(Type.meta(11, .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 10)
            Text(s.binding.isEmpty ? "—" : s.binding)
                .font(Type.meta(10))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.black.opacity(0.92))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.white.opacity(0.11), lineWidth: 1))
        )
    }
}

struct Pill: View {
    @ObservedObject var s: Session

    var body: some View {
        HStack(spacing: 9) {
            if s.engagedNow {
                Waveform(level: s.level)
                    .frame(width: 24)
            } else {
                Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1)
                    .frame(width: 8, height: 8)
            }
            Text(s.binding.isEmpty ? "nothing under the cursor" : s.binding)
                .font(Type.meta(10.5))
                .foregroundStyle(.white.opacity(s.binding.isEmpty ? 0.35 : 0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 11).padding(.vertical, 7)
        .background(
            Capsule().fill(.black.opacity(0.92))
                .overlay(Capsule().strokeBorder(.white.opacity(0.11), lineWidth: 1))
        )
        .fixedSize()
    }
}

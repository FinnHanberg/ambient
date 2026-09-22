import AppKit
import SwiftUI

/// Presence lives in the menu bar, which is where a Mac says a thing is
/// running — the same place Screen Recording, Time Machine and every capture
/// tool report from. The notch is a camera housing, not a surface; treating it
/// as one borrows an iPhone idiom for a desktop app.
struct MenuBarView: View {
    @ObservedObject var s: Session
    @ObservedObject var notes = Notes.shared

    var body: some View {
        HStack(spacing: 5) {
            if s.engagedNow {
                Bars(level: s.level)
            } else {
                Image(systemName: notes.isEmpty ? "waveform" : "waveform.badge.checkmark")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
            }
            if notes.count > 0 {
                Text("\(notes.count)")
                    .font(Type.meta(11, .medium))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .animation(.easeOut(duration: 0.18), value: s.engagedNow)
    }
}

/// Four bars that answer to the microphone, sized for the menu bar. The tint
/// follows the menu bar's own appearance rather than a fixed colour, so it
/// reads on light and dark wallpapers alike.
private struct Bars: View {
    let level: Double
    private let weights: [Double] = [0.55, 1.0, 0.78, 0.45]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .frame(width: 2, height: max(3, 3 + level * 12 * weights[i]))
            }
        }
        .foregroundStyle(.primary)
        .frame(height: 16)
        .animation(.spring(response: 0.16, dampingFraction: 0.6), value: level)
    }
}

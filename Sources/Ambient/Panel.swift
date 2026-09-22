import SwiftUI

/// The chrome every surface shares.
///
/// The review panel and the settings window had drifted into two slightly
/// different cards — different radii, different padding, different header
/// rhythm. They are the same object seen twice, so the treatment lives in one
/// place and neither can drift again.
enum Chrome {
    static let radius: CGFloat = 12
    static let hair = Color.white.opacity(0.12)
    static let rule = Color.white.opacity(0.07)
    static let ground = Color(white: 0.055)

    /// The horizontal rhythm every row, header and footer sits on.
    static let gutter: CGFloat = 18
}

extension View {
    /// One card treatment: hairline, restrained shadow, room for the shadow to
    /// fall so the window cannot clip it into a hard edge.
    func panelCard(width: CGFloat) -> some View {
        self
            .frame(width: width)
            .background(
                RoundedRectangle(cornerRadius: Chrome.radius, style: .continuous)
                    .fill(Chrome.ground)
                    .overlay(
                        RoundedRectangle(cornerRadius: Chrome.radius, style: .continuous)
                            .strokeBorder(Chrome.hair, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.36), radius: 20, y: 7)
            )
            .padding(20)
    }
}

/// A title, optional meta, trailing controls, and always a way out.
struct PanelHeader<Trailing: View>: View {
    let title: String
    var meta: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    let close: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Text(title)
                .font(Type.ui(14, .semibold))
                .foregroundStyle(.white)
            if let meta {
                Text(meta)
                    .font(Type.meta(10.5))
                    .foregroundStyle(.white.opacity(0.32))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            trailing()
            IconButton("xmark", action: close)
        }
        .padding(.horizontal, Chrome.gutter)
        .padding(.vertical, 14)
    }
}

struct IconButton: View {
    let name: String
    var size: CGFloat = 9
    let action: () -> Void

    init(_ name: String, size: CGFloat = 9, action: @escaping () -> Void) {
        self.name = name; self.size = size; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }
}

/// Section label — the only thing that separates one group of rows from another.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Type.meta(9.5, .medium))
            .tracking(1.1)
            .foregroundStyle(.white.opacity(0.28))
            .padding(.horizontal, Chrome.gutter)
            .padding(.top, 16).padding(.bottom, 7)
    }
}

/// Pill actions. Exactly one per surface is `strong`.
struct PillButton: View {
    let label: String
    var strong = false
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 10, weight: .medium))
                }
                Text(label).font(Type.ui(12, .medium))
            }
            .foregroundStyle(strong ? Color(white: 0.06) : .white.opacity(0.62))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(strong ? Color.white.opacity(0.92) : Color.white.opacity(0.06))
                    .overlay(Capsule().strokeBorder(strong ? .clear : Chrome.hair, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

struct QuietButton: View {
    let label: String
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { Image(systemName: icon).font(.system(size: 11)) }
                Text(label).font(Type.ui(11.5))
            }
            .foregroundStyle(.white.opacity(0.45))
        }
        .buttonStyle(.plain)
    }
}

/// A switch drawn rather than borrowed: `Toggle` is AppKit-backed, takes the
/// system accent — the one place a monochrome interface leaks blue — and cannot
/// be drawn by the static renderer at all.
struct Switch: View {
    @Binding var on: Bool
    var enabled: Bool = true

    var body: some View {
        Capsule()
            .fill(.white.opacity(on ? 0.82 : 0.12))
            .frame(width: 34, height: 20)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(on ? Color(white: 0.08) : Color(white: 0.62))
                    .frame(width: 15, height: 15)
                    .padding(2.5)
            }
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Capsule())
            .onTapGesture { if enabled { on.toggle() } }
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: on)
            .accessibilityAddTraits(.isButton)
    }
}

/// A thin progress track. Used for the allowance and nothing else.
struct Meter: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.1))
                Capsule().fill(.white.opacity(0.72))
                    .frame(width: max(2, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 3)
    }
}

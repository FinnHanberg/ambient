import SwiftUI

/// The plan, argued from the user's own numbers.
///
/// It sits at the top because it is the only row that asks for something, and
/// burying an ask reads as either shame or a trap. The persuasion is one line:
/// what this has already saved them, computed from passes they actually took.
/// No urgency, no countdown, no invented figure.
struct PlanCard: View {
    @ObservedObject var usage = Usage.shared
    var upgrade: () -> Void = {}

    private var grant: Int { usage.onStarter ? usage.starterGrant : usage.monthlyGrant }
    private var used: Double { 1 - Double(usage.remaining) / Double(max(1, grant)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(usage.pro ? "Pro" : "Free")
                    .font(Type.ui(15, .semibold))
                    .foregroundStyle(.white)
                if !usage.pro {
                    Text("\(usage.remaining) notes left")
                        .font(Type.meta(11))
                        .foregroundStyle(.white.opacity(usage.remaining < 10 ? 0.7 : 0.35))
                }
                Spacer(minLength: 10)
                if !usage.pro {
                    PillButton(label: "Upgrade — €15/mo", strong: true, action: upgrade)
                }
            }

            if !usage.pro {
                Meter(fraction: used)

                // The whole argument, in the user's own units.
                if usage.lifetimeNotes >= 5 {
                    Text("You've captured \(usage.lifetimeNotes) notes — \(usage.saved) of writing you didn't do.")
                        .font(Type.ui(12))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.28))
                    Text("\(usage.monthlyGrant) more on \(usage.renews) · capture and raw export are never counted")
                        .font(Type.ui(10.5))
                        .foregroundStyle(.white.opacity(0.3))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Unlimited notes. Thank you.")
                    .font(Type.ui(12))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, Chrome.gutter)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(0.035))
                .padding(.horizontal, Chrome.gutter - 8)
        )
    }
}

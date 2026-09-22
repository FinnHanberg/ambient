import Foundation
import SwiftUI

/// The free allowance.
///
/// Counts briefs written — never passes, notes or screenshots. Capture has to
/// stay unmetered or people point at fewer things to protect a balance, and
/// pointing is the whole mechanic. The meter only moves on a deliberate act,
/// taken at the review panel, where the choice already lives.
@MainActor
final class Usage: ObservableObject {
    static let shared = Usage()

    /// Notes, not passes or screenshots — and crucially they are only ever
    /// *spent at export*. Capture stays uncounted, so nobody points at fewer
    /// things to protect a balance; a fourteen-note pass simply costs fourteen
    /// when you send it.
    let starterGrant = 100
    /// Not a trial that ends — a free tier that persists, so someone reviewing
    /// occasionally stays free and uninstalling is never the cheaper option.
    let monthlyGrant = 25

    /// Never resets. Only used to tell you what the tool has actually done
    /// for you — the one persuasive number that is yours rather than ours.
    @Published private(set) var lifetimeNotes: Int
    @Published private(set) var starterUsed: Int
    @Published private(set) var monthUsed: Int
    @Published var pro: Bool {
        didSet { UserDefaults.standard.set(pro, forKey: "ambient.pro") }
    }

    private var month: String {
        didSet { UserDefaults.standard.set(month, forKey: "ambient.month") }
    }

    private init() {
        let d = UserDefaults.standard
        starterUsed = d.integer(forKey: "ambient.starterUsed")
        lifetimeNotes = d.integer(forKey: "ambient.lifetimeNotes")
        pro = d.bool(forKey: "ambient.pro")
        let now = Usage.monthKey()
        month = d.string(forKey: "ambient.month") ?? now
        monthUsed = d.integer(forKey: "ambient.monthUsed")
        if month != now { month = now; monthUsed = 0; persist() }
    }

    private static func monthKey() -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"
        return f.string(from: Date())
    }

    var onStarter: Bool { starterUsed < starterGrant }

    var remaining: Int {
        if pro { return .max }
        return onStarter ? starterGrant - starterUsed : max(0, monthlyGrant - monthUsed)
    }

    var exhausted: Bool { !pro && remaining <= 0 }

    /// Roughly how long writing a pass up by hand would take.
    static func writingTime(notes: Int) -> String {
        let minutes = max(2, notes * 4)
        if minutes < 60 { return "about \(minutes) minutes" }
        let h = Double(minutes) / 60
        return h < 1.6 ? "about an hour" : String(format: "about %.0f hours", h.rounded())
    }

    /// When the monthly allowance comes back.
    var renews: String {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .month, value: 1,
                                  to: cal.date(from: cal.dateComponents([.year, .month], from: Date()))!)
        else { return "next month" }
        let f = DateFormatter(); f.dateFormat = "d MMMM"
        return f.string(from: next)
    }

    func spend(_ n: Int) {
        guard n > 0 else { return }
        lifetimeNotes += n
        UserDefaults.standard.set(lifetimeNotes, forKey: "ambient.lifetimeNotes")
        guard !pro else { return }
        if onStarter { starterUsed += n } else { monthUsed += n }
        persist()
        Log.say("usage · spent \(n) · remaining=\(remaining)")
    }

    /// Can this pass be exported in full on the free tier?
    func covers(_ n: Int) -> Bool { pro || remaining >= n }

    private func persist() {
        let d = UserDefaults.standard
        d.set(starterUsed, forKey: "ambient.starterUsed")
        d.set(monthUsed, forKey: "ambient.monthUsed")
        d.set(month, forKey: "ambient.month")
    }

    /// For trying the states out without burning a real allowance.
    func reset() {
        starterUsed = 0; monthUsed = 0; month = Usage.monthKey(); persist()
    }

    /// What has already been avoided, in the user's own units.
    var saved: String { Usage.writingTime(notes: lifetimeNotes) }
}

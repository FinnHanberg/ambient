import AppKit
import SwiftUI

/// One typeface across the whole app.
///
/// Inter ships inside the bundle as a variable font rather than relying on what
/// happens to be in the user's font library — the machine this was built on had
/// only the SemiBold face installed, which would have rendered every weight
/// semibold and looked like a mistake.
enum Type {
    static let family = "InterVariable"

    private static var registered = false

    static func register() {
        guard !registered else { return }
        registered = true
        guard let url = Bundle.main.url(forResource: "InterVariable", withExtension: "ttf") else {
            Log.say("type · InterVariable not in bundle — falling back to the system face")
            return
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            Log.say("type · could not register Inter — \(error?.takeUnretainedValue().localizedDescription ?? "unknown")")
        }
    }

    static var available: Bool {
        NSFontManager.shared.availableFontFamilies.contains(family)
            || NSFont(name: family, size: 12) != nil
    }

    /// Interface text.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard available else { return .system(size: size, weight: weight) }
        return .custom(family, size: size).weight(weight)
    }

    /// Technical strings — paths, URLs, roles, counts. Same face as everything
    /// else, with fixed-width figures so counts don't jitter as they change.
    /// A second typeface for these was a leftover, and it read as one.
    static func meta(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard available else { return .system(size: size, weight: weight).monospacedDigit() }
        return .custom(family, size: size).weight(weight).monospacedDigit()
    }
}

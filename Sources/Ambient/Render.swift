import AppKit
import SwiftUI

/// `Ambient --render sheet.png` draws every state of the panel and exits.
/// The surface can then be designed and reviewed without speaking to it.
enum Render {
    @MainActor
    static func welcome(path: String, step: Int) {
        Welcome.shared.step = step
        let v = WelcomeView(s: Session(), done: {}, scrolls: false)
        let r = ImageRenderer(content: v)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: path))
        print("rendered \(path)"); exit(0)
    }

    @MainActor
    static func settings(path: String) {
        let v = SettingsView(s: Session(), close: {}, scrolls: false)
        let r = ImageRenderer(content: v)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
        try? png.write(to: URL(fileURLWithPath: path))
        print("rendered \(path)"); exit(0)
    }

    @MainActor
    static func review(path: String) {
        let v = Review(close: {}, scrolls: false)
        let r = ImageRenderer(content: v)
        r.scale = 2
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("rendered \(path)")
        exit(0)
    }

    @MainActor
    static func run(path: String) {
        var shots: [NSImage] = []

        for (title, configure) in states {
            let s = Session()
            s.visible = true
            configure(s)
            let card = VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(Type.meta(9, .medium))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.3))
                HUD(s: s).frame(width: 600, height: 190, alignment: .bottom)
            }
            .padding(.horizontal, 16)
            let r = ImageRenderer(content: card)
            r.scale = 2
            if let img = r.nsImage { shots.append(img) }
        }

        let width: CGFloat = 632
        let total = shots.reduce(CGFloat(0)) { $0 + $1.size.height }
        let sheet = NSImage(size: NSSize(width: width, height: total + 32))
        sheet.lockFocus()
        NSColor(calibratedWhite: 0.17, alpha: 1).setFill()
        NSRect(origin: .zero, size: sheet.size).fill()
        var y = total + 16
        for img in shots {
            y -= img.size.height
            img.draw(at: NSPoint(x: 16, y: y), from: .zero, operation: .sourceOver, fraction: 1)
        }
        sheet.unlockFocus()

        guard let tiff = sheet.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("rendered \(path)")
        exit(0)
    }

    private static let states: [(String, @MainActor (Session) -> Void)] = [
        ("recording", { s in
            s.phase = .hearing; s.level = 0.62; s.latched = true
            s.transcript = "the spacing under this heading is way too tight"
            s.binding = "heading “The Art of Branding”"
        }),
        ("noted", { s in
            s.phase = .noted("the spacing under this heading is way too tight")
            s.binding = "heading “The Art of Branding”"
        }),
        ("idle with notes", { s in s.phase = .idle }),
        ("hearing", { s in
            s.phase = .hearing
            s.transcript = "crop this down to the hero and push it"
            s.binding = "Figma · hero-01.png"
            s.level = 0.55
        }),
        ("noted", { s in
            s.phase = .noted("this heading is way too tight against the image")
        }),
        ("asking", { s in
            s.phase = .replying("crop [Figma · hero-01.png] down to the hero and push it")
            s.spoken = "Crop hero-01 and push it. Confirm?"
            s.awaitingConfirmation = true
        }),
        ("answering", { s in
            s.phase = .replying("Figma · window “AXIAL — Mockups” · image · “hero-01.png”")
            s.spoken = "A 2400 by 1600 image in the AXIAL mockups file."
        }),
        ("acting", { s in s.phase = .acting }),
        ("reported", { s in s.phase = .reported("queued · on clipboard", true) }),
        ("failed", { s in s.phase = .failed("Microphone access denied. Grant it in Privacy & Security.") })
    ]
}

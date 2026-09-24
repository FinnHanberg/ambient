import AppKit
import SwiftUI

/// What you just recorded, before it goes anywhere.
///
/// Same chrome as the settings window — same gutter, same header rhythm, same
/// card. A pass ends here rather than being fired at whichever Claude window
/// happened to be frontmost.
struct Review: View {
    @ObservedObject var notes = Notes.shared
    @ObservedObject var usage = Usage.shared
    @AppStorage("ambient.clean") private var clean = true
    @State private var flash: String? = nil
    var close: () -> Void
    var settings: () -> Void = {}
    var scrolls: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: notes.count == 1 ? "1 note" : "\(notes.count) notes",
                        meta: pages,
                        trailing: { header },
                        close: close)
            Divider().overlay(Chrome.rule)

            if notes.isEmpty {
                Text("Nothing recorded.")
                    .font(Type.ui(13))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, Chrome.gutter).padding(.vertical, 22)
            } else {
                Group {
                    if scrolls {
                        ScrollView { list }.frame(height: min(360, CGFloat(notes.count) * 78 + 2))
                    } else { list }
                }
                ledger
            }

            if !usage.pro, !usage.covers(notes.count), !notes.isEmpty {
                Divider().overlay(Chrome.rule)
                allowance
            }

            Divider().overlay(Chrome.rule)
            footer
        }
        .panelCard(width: 540)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if !usage.pro, !notes.isEmpty, usage.covers(notes.count) {
            Text("\(usage.remaining) left")
                .font(Type.meta(10.5))
                .foregroundStyle(.white.opacity(usage.remaining < 10 ? 0.65 : 0.3))
        }
        toggle
    }

    /// Raw is the record; clean is the reading of it. One click apart so
    /// neither has to be trusted blindly.
    private var toggle: some View {
        HStack(spacing: 0) {
            ForEach([true, false], id: \.self) { wantsClean in
                Button { clean = wantsClean } label: {
                    Text(wantsClean ? "Clean" : "Raw")
                        .font(Type.meta(10, .medium))
                        .foregroundStyle(.white.opacity(clean == wantsClean ? 0.9 : 0.38))
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(clean == wantsClean ? 0.13 : 0)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().strokeBorder(Chrome.hair, lineWidth: 1))
    }

    // MARK: - Rows

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(Array(notes.items.enumerated()), id: \.element.id) { i, n in
                row(i + 1, n)
                if i < notes.count - 1 {
                    Divider().overlay(Chrome.rule).padding(.leading, Chrome.gutter)
                }
            }
        }
    }

    private func row(_ i: Int, _ n: Note) -> some View {
        NoteRow(index: i, note: n, clean: clean,
                copy: { copyOne(n) },
                copyImage: { copyImage(n) },
                remove: { notes.remove(n.id) })
    }

    // MARK: - Meta

    private var pages: String {
        let set = Set(notes.items.map(page))
        return set.count <= 1 ? (set.first ?? "") : "\(set.count) pages"
    }

    private func page(_ n: Note) -> String {
        guard let r = n.context.range(of: "https://") else { return n.app }
        let rest = n.context[r.lowerBound...]
        let url = rest.split(separator: " ").first.map(String.init) ?? n.app
        return URL(string: url)?.host() ?? url
    }

    /// What the pass just saved, in the units the user bills in.
    @ViewBuilder
    private var ledger: some View {
        if notes.count > 1 {
            HStack(spacing: 6) {
                Text("\(notes.count) notes")
                Text("·").foregroundStyle(.white.opacity(0.2))
                Text(pages)
                Text("·").foregroundStyle(.white.opacity(0.2))
                Text("\(Usage.writingTime(notes: notes.count)) of writing")
                    .foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
            }
            .font(Type.meta(10.5))
            .foregroundStyle(.white.opacity(0.32))
            .padding(.horizontal, Chrome.gutter)
            .padding(.top, 11).padding(.bottom, 2)
        }
    }

    /// A wall with a date on it is a pause; without one it is an ultimatum.
    private var allowance: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("This pass is \(notes.count) notes and you have \(usage.remaining) left")
                .font(Type.ui(12.5, .medium))
                .foregroundStyle(.white.opacity(0.9))
            Text("\(usage.monthlyGrant) more on \(usage.renews). Raw export keeps working either way.")
                .font(Type.ui(11))
                .foregroundStyle(.white.opacity(0.42))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Chrome.gutter).padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 9) {
            PillButton(label: locked ? "Copy raw" : (clean ? "Copy brief" : "Copy"),
                       strong: true, icon: "doc.on.doc") { copy() }
            PillButton(label: "Open Claude", icon: "arrow.up.forward.app") { send() }
            Spacer(minLength: 8)
            if let flash {
                Text(flash).font(Type.meta(10.5)).foregroundStyle(.white.opacity(0.6))
            }
            QuietButton(label: "Discard") { notes.clear(); close() }
            IconButton("gearshape", action: settings)
        }
        .padding(.horizontal, Chrome.gutter)
        .padding(.vertical, 13)
    }

    // MARK: - Actions

    private var locked: Bool { clean && !usage.covers(notes.count) }

    private var payload: String {
        locked ? notes.bundle() : (clean ? Enhance.brief(notes.items) : notes.bundle())
    }

    private func take() { usage.spend(notes.count) }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        take()
        show(locked ? "copied — verbatim" : (clean ? "copied — brief" : "copied — verbatim"))
    }

    private func send() {
        Task {
            let out = await Deliver.paste(payload)
            take()
            show(out.text)
        }
    }

    /// A single note, text and picture together on the clipboard. Whatever it
    /// is pasted into takes the half it understands.
    private func copyOne(_ n: Note) {
        let board = NSPasteboard.general
        board.clearContents()
        var items: [NSPasteboardWriting] = [notes.one(n, clean: clean && !locked) as NSString]
        if let path = n.shots.first, let img = NSImage(contentsOfFile: path) {
            items.append(img)
        }
        board.writeObjects(items)
        usage.spend(1)
        show("note copied")
    }

    /// Just the picture — for dropping into a message or a canvas.
    private func copyImage(_ n: Note) {
        guard let path = n.shots.first, let img = NSImage(contentsOfFile: path) else {
            show("no picture on that note"); return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        show("picture copied")
    }

    private func show(_ s: String) {
        flash = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if flash == s { flash = nil } }
    }
}

/// One note. The row-level actions only appear on hover: three buttons on
/// every row would make a ten-note pass look like a control panel.
private struct NoteRow: View {
    let index: Int
    let note: Note
    let clean: Bool
    let copy: () -> Void
    let copyImage: () -> Void
    let remove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(Type.meta(10))
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 12, alignment: .trailing)
                .padding(.top, 3)

            Button(action: copyImage) { thumb }
                .buttonStyle(.plain)
                .help("Copy just the picture")

            VStack(alignment: .leading, spacing: 3) {
                Text(clean ? Enhance.clean(note) : note.text)
                    .font(Type.ui(13))
                    .foregroundStyle(.white.opacity(0.94))
                    .fixedSize(horizontal: false, vertical: true)
                Text(place(note.context))
                    .font(Type.meta(10))
                    .foregroundStyle(.white.opacity(0.32))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            HStack(spacing: 2) {
                if hovering {
                    Button(action: copy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help("Copy this note and its picture")
                }
                Button(action: remove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(hovering ? 0.5 : 0.24))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Remove this note")
            }
        }
        .padding(.horizontal, Chrome.gutter)
        .padding(.vertical, 11)
        .background(Color.white.opacity(hovering ? 0.03 : 0))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private var thumb: some View {
        if let path = note.shots.first, let img = NSImage(contentsOfFile: path) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 76, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.white.opacity(hovering ? 0.3 : 0.12), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.04))
                .frame(width: 76, height: 50)
                .overlay(Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.22)))
        }
    }

    private func place(_ context: String) -> String {
        context.replacingOccurrences(of: "Google Chrome · ", with: "")
    }
}

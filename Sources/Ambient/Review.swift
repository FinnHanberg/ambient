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
        HStack(alignment: .top, spacing: 12) {
            Text("\(i)")
                .font(Type.meta(10))
                .foregroundStyle(.white.opacity(0.3))
                .frame(width: 12, alignment: .trailing)
                .padding(.top, 3)

            thumb(n)

            VStack(alignment: .leading, spacing: 3) {
                Text(clean ? Enhance.clean(n) : n.text)
                    .font(Type.ui(13))
                    .foregroundStyle(.white.opacity(0.94))
                    .fixedSize(horizontal: false, vertical: true)
                Text(place(n.context))
                    .font(Type.meta(10))
                    .foregroundStyle(.white.opacity(0.32))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            Button { notes.remove(n.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Remove this note")
        }
        .padding(.horizontal, Chrome.gutter)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func thumb(_ n: Note) -> some View {
        if let path = n.shots.first, let img = NSImage(contentsOfFile: path) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 76, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Chrome.hair, lineWidth: 1))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.04))
                .frame(width: 76, height: 50)
                .overlay(Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.22)))
        }
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

    private func place(_ context: String) -> String {
        context.replacingOccurrences(of: "Google Chrome · ", with: "")
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

    private func show(_ s: String) {
        flash = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if flash == s { flash = nil } }
    }
}

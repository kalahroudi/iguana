import SwiftUI
import AppKit
import IguanaKit

enum Theme {
    static let accent = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0.659, green: 0.941, blue: 0.416, alpha: 1) : NSColor(srgbRed: 0.122, green: 0.541, blue: 0.298, alpha: 1) })
    static let selection = accent.opacity(0.16)
    static let tile = Color.primary.opacity(0.07)
}

/// Lives only while the popover is open. All state is dropped on close.
@MainActor @Observable
final class PopoverModel {
    var query = "" { didSet { selection = 0; refresh() } }
    var items: [Scanned] = [] { didSet { refresh() } }
    var loaded = false
    var trusted = Scanner.trusted
    var selection = 0
    var version = 0 { didSet { refresh() } }                      // bumped when pins or positions change, to refresh sections
    private(set) var sections: [IguanaKit.Section] = []
    private(set) var rows: [Row] = []
    var mouseAnchor = NSPoint.zero
    var notice: String?
    var stats: StatsSample?
    var showStats = Prefs.shared.showStats
    var close: () -> Void = {}
    private let reader = StatsReader()
    private var statsTask: Task<Void, Never>?
    private var icons: [String: NSImage] = [:]

    /// Sections are computed once per change, not on every view update, so arrow-key navigation stays cheap.
    private func refresh() {
        sections = Organizer.sections(items.map(\.item), pinned: Prefs.shared.pinned, query: query)
        rows = Organizer.flat(sections)
        selection = min(selection, max(rows.count - 1, 0))
    }

    func load() {
        trusted = Scanner.trusted
        startStats()
        guard trusted else { loaded = true; return }
        Task { await rescan(); loaded = true }
    }

    func rescan() async {
        var list = await Scanner.scan()
        // Items switched off in Settings that macOS no longer lists: keep showing the ones Iguana tucked itself.
        var ghosts = Prefs.shared.ghosts
        ghosts.removeAll { g in list.contains { $0.item.id == g.id && !$0.item.tucked } }
        for g in ghosts where !list.contains(where: { $0.item.id == g.id }) {
            list.append(Scanned(item: BarItem(id: g.id, pid: 0, owner: g.owner, bundleID: g.bundleID, name: g.name, detail: "", x: -1, tucked: true), element: nil))
        }
        Prefs.shared.ghosts = ghosts
        items = list
        version += 1
    }

    func stop() { statsTask?.cancel(); statsTask = nil }

    private func startStats() {
        guard showStats else { return }
        stats = reader.sample()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                self.stats = self.reader.sample()
            }
        }
    }
    func toggleStats() { showStats.toggle(); Prefs.shared.showStats = showStats; if showStats { startStats() } else { stop(); stats = nil } }

    func move(_ d: Int) { guard !rows.isEmpty else { return }; mouseAnchor = NSEvent.mouseLocation; selection = (selection + d + rows.count) % rows.count }

    /// Opening a tucked-away item brings it back first (it has to be in the bar to have a menu), then opens it.
    func open(_ row: Row) {
        close()
        if row.group == .hidden {
            Task { @MainActor in
                await Self.setTucked([row.item], tucked: false)
                for _ in 0..<20 {                                           // wait for the item to reappear
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    if let s = await Scanner.scan().first(where: { $0.item.id == row.id && !$0.item.tucked }), let el = s.element { Scanner.press(el); return }
                }
            }
        } else if let el = items.first(where: { $0.item.id == row.id })?.element {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { Scanner.press(el) }
        }
    }
    func openSelected() { if rows.indices.contains(selection) { open(rows[selection]) } }

    /// Third-party items sitting in the bar that you have not pinned: what "Tidy up" will tuck away.
    var tidyTargets: [Scanned] {
        items.filter { !$0.item.isSystem && !$0.item.tucked && !Prefs.shared.pinned.contains($0.item.id) }.sorted { $0.item.x < $1.item.x }
    }

    func togglePin(_ row: Row) {
        guard !row.item.isFixed else { return }
        Prefs.shared.togglePin(row.id); version += 1
        if row.group == .hidden { close(); Task { @MainActor in await Self.setTucked([row.item], tucked: false) } }   // pinning something tucked away brings it back
    }
    func pinSelected() { if rows.indices.contains(selection) { togglePin(rows[selection]) } }

    func hideSelected() { if rows.indices.contains(selection) { tuck(rows[selection]) } }

    func tuck(_ row: Row) {
        guard !row.item.isFixed else { notice = "macOS keeps \(row.item.name) in place."; return }
        if row.group == .pinned { Prefs.shared.togglePin(row.id) }
        guard row.group != .hidden else { return }
        close()
        Task { @MainActor in await Self.setTucked([row.item], tucked: true) }
    }

    func tidy() {
        let targets = tidyTargets.map(\.item)
        guard !targets.isEmpty else { return }
        close()
        Task { @MainActor in await Self.setTucked(targets, tucked: true) }
    }

    /// Flips the matching switches in System Settings → Menu Bar. The name Settings uses is the app's, or the system item's own.
    static func setTucked(_ items: [BarItem], tucked: Bool) async {
        let names = Dictionary(items.map { ($0.isSystem ? $0.name : $0.owner, $0) }, uniquingKeysWith: { a, _ in a })
        let done = await MenuBarSettings.apply(names.keys.map { ($0, !tucked) })
        var ghosts = Prefs.shared.ghosts
        for (name, item) in names where done.contains(name) && item.isSystem {
            ghosts.removeAll { $0.id == item.id }
            if tucked { ghosts.append(.init(id: item.id, name: item.name, owner: item.owner, bundleID: item.bundleID)) }
        }
        Prefs.shared.ghosts = ghosts
    }

    func icon(for item: BarItem) -> NSImage? {
        if let i = icons[item.id] { return i }
        guard let b = item.bundleID, !BarItem.systemOwners.contains(b) else { return nil }
        let img = NSRunningApplication(processIdentifier: item.pid)?.icon
        if let img { img.size = NSSize(width: 16, height: 16); icons[item.id] = img }
        return img
    }
}

struct PopoverView: View {
    @Bindable var model: PopoverModel
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 6) {
            search
            if !model.trusted { permission } else if !model.loaded { Color.clear.frame(height: 60) } else { list }
            if model.trusted, model.loaded, model.query.isEmpty, !model.tidyTargets.isEmpty { tidyBanner }
            if let n = model.notice { Text(n).font(.system(size: 11.5)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8) }
            if let s = model.stats { StatsStrip(s: s) }
            footer
        }
        .padding(8)
        .frame(width: 340)
        .onAppear { focused = true }
        .background(hotkeys)
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 13, weight: .medium))
            TextField("Search menu bar", text: $model.query)
                .textFieldStyle(.plain).font(.system(size: 13.5)).focused($focused)
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                .onKeyPress(.return) { model.openSelected(); return .handled }
                .onKeyPress(.escape) { model.close(); return .handled }
                .onSubmit { model.openSelected() }
            Text("⌃⌥␣").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 1).overlay(RoundedRectangle(cornerRadius: 5).stroke(.quaternary))
        }
        .padding(.horizontal, 10).frame(height: 34)
        .background(Theme.tile, in: RoundedRectangle(cornerRadius: 9))
    }

    private var list: some View {
        let secs = model.sections
        let height = min(440, CGFloat(model.rows.count) * 38 + CGFloat(secs.count) * 30)
        var offset = 0
        let starts = secs.map { sec -> Int in defer { offset += sec.rows.count }; return offset }
        return Group {
            if secs.isEmpty {
                Text(model.query.isEmpty ? "No menu bar items found" : "Nothing matches “\(model.query)”")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 26)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {                                  // eager: rows never pop in and out while you navigate
                            ForEach(Array(secs.enumerated()), id: \.element.id) { si, sec in
                                HStack { Text(sec.group.rawValue.uppercased()); Spacer(); Text("\(sec.rows.count)") }
                                    .font(.system(size: 10.5, weight: .medium)).tracking(0.6).foregroundStyle(.secondary)
                                    .padding(.horizontal, 8).padding(.top, 9).padding(.bottom, 4)
                                ForEach(Array(sec.rows.enumerated()), id: \.element.id) { ri, row in
                                    let i = starts[si] + ri
                                    RowView(row: row, selected: i == model.selection, icon: model.icon(for: row.item),
                                            onPin: { model.togglePin(row) }, onTuck: { model.tuck(row) })
                                        .id(row.id)
                                        .onTapGesture { model.open(row) }
                                        .onHover { inside in
                                            // Only follow the mouse when it really moved; scrolling under a still pointer must not steal the selection.
                                            let m = NSEvent.mouseLocation
                                            if inside, hypot(m.x - model.mouseAnchor.x, m.y - model.mouseAnchor.y) > 3 { model.selection = i }
                                        }
                                }
                            }
                        }
                    }
                    .scrollIndicators(.never)
                    .onChange(of: model.selection) { _, s in
                        if model.rows.indices.contains(s) { withAnimation(nil) { proxy.scrollTo(model.rows[s].id) } }
                    }
                }
                .frame(height: height)
            }
        }
    }

    private var tidyBanner: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(model.tidyTargets.count) icons are crowding your bar").font(.system(size: 12.5, weight: .semibold))
                Text("Tuck them away. They stay one click from here.").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button("Tidy up") { model.tidy() }.buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.small)
        }
        .padding(10).background(Theme.selection, in: RoundedRectangle(cornerRadius: 9))
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Allow Accessibility").font(.system(size: 13, weight: .semibold))
            Text("Iguana reads and opens menu bar items through macOS Accessibility. It never records your screen or sends anything anywhere.")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open Settings") { Scanner.requestTrust(); NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
                Button("Check again") { model.load() }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack {
            Text("↩ open · ⌘P pin · ⌘Delete tuck away").lineLimit(1)
            Spacer()
            Text("\(model.items.count) items")
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 8).padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(.quaternary).frame(height: 0.5) }
    }

    private var hotkeys: some View {
        Group {
            Button("") { model.pinSelected() }.keyboardShortcut("p", modifiers: .command)
            Button("") { model.hideSelected() }.keyboardShortcut(.delete, modifiers: .command)
            Button("") { model.toggleStats() }.keyboardShortcut("m", modifiers: .command)
        }.opacity(0).frame(width: 0, height: 0)
    }
}

struct StatsStrip: View {
    let s: StatsSample
    var body: some View {
        HStack(spacing: 10) {
            cell("CPU", s.cpu, "\(Int(s.cpu * 100))%")
            cell("RAM", s.ram, formatBytes(s.ramUsed))
            cell("GPU", s.gpu ?? 0, s.gpu.map { "\(Int($0 * 100))%" } ?? "n/a")
            cell("VRAM", s.vramUsed.map { Double($0) / Double(s.ramTotal) } ?? 0, s.vramUsed.map(formatBytes) ?? "n/a")
        }
        .padding(.horizontal, 8).padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(.quaternary).frame(height: 0.5) }
    }
    private func cell(_ name: String, _ v: Double, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack { Text(name).foregroundStyle(.secondary); Spacer(minLength: 2); Text(text).monospacedDigit() }.font(.system(size: 10.5, weight: .medium))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.tile)
                GeometryReader { g in Capsule().fill(Theme.accent).frame(width: max(3, g.size.width * min(max(v, 0), 1))) }
            }.frame(height: 4)
        }.frame(maxWidth: .infinity)
    }
}

struct RowView: View {
    let row: Row
    let selected: Bool
    let icon: NSImage?
    let onPin: () -> Void
    let onTuck: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(Theme.tile)
                if let icon { Image(nsImage: icon) } else {
                    Image(systemName: Symbols.name(for: row.item.name)).font(.system(size: 12, weight: .medium))
                }
            }.frame(width: 24, height: 24)
            name.font(.system(size: 13, weight: .medium)).lineLimit(1)
            Spacer(minLength: 8)
            Text(row.item.detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
            if selected && !row.item.isFixed {
                if row.group != .hidden {
                    Button(action: onTuck) { Image(systemName: "eye.slash").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 22, height: 26).contentShape(Rectangle()) }
                        .buttonStyle(.plain).help("Tuck away: hide this icon from the menu bar (⌘⌫)")
                }
            }
            Button(action: onPin) {
                Image(systemName: row.group == .pinned ? "pin.fill" : "pin").font(.system(size: 11))
                    .foregroundStyle(row.group == .pinned ? Theme.accent : .secondary)
                    .frame(width: 22, height: 26).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(row.group == .pinned ? "Unpin" : row.group == .hidden ? "Bring back to the menu bar and pin (⌘P)" : "Pin: keep in the menu bar (⌘P)")
            .opacity(row.item.isFixed ? 0 : (selected || row.group == .pinned) ? 1 : 0).disabled(row.item.isFixed)
        }
        .padding(.horizontal, 8).frame(height: 38)
        .background(selected ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private var name: Text {
        let chars = Array(row.item.name)
        let hits = Set(row.nameMatch)
        return chars.enumerated().reduce(Text("")) { acc, e in
            hits.contains(e.offset) ? acc + Text(String(e.element)).foregroundColor(Theme.accent).bold() : acc + Text(String(e.element))
        }
    }
}

enum Symbols {
    static func name(for title: String) -> String {
        let t = title.lowercased()
        let map: [(String, String)] = [("wi-fi", "wifi"), ("wifi", "wifi"), ("battery", "battery.100"), ("bluetooth", "wave.3.right"), ("sound", "speaker.wave.2"),
            ("volume", "speaker.wave.2"), ("clock", "clock"), ("focus", "moon"), ("display", "display"), ("keyboard", "keyboard"), ("vpn", "lock.shield"),
            ("control", "switch.2"), ("siri", "waveform"), ("spotlight", "magnifyingglass"), ("playing", "play.circle"), ("mirror", "rectangle.on.rectangle"),
            ("user", "person.crop.circle"), ("airdrop", "dot.radiowaves.right"), ("time machine", "clock.arrow.circlepath")]
        return map.first { t.contains($0.0) }?.1 ?? "circle.grid.2x2"
    }
}

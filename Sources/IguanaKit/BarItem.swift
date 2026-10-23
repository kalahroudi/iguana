import Foundation

/// One status item found in the menu bar.
public struct BarItem: Identifiable, Hashable, Sendable {
    public let id: String          // stable across launches: owner + the item's own identifier
    public let pid: Int32
    public let owner: String       // app name
    public let bundleID: String?
    public let name: String        // what the row shows
    public let detail: String      // short status, may be empty
    public let x: Double           // position in the bar, for ordering
    /// Switched off in System Settings → Menu Bar, so it is not in the bar even though it is still listed here.
    public var tucked: Bool = false
    /// Apple's own items (clock, Control Center, Spotlight…) stay where macOS puts them.
    public var isFixed: Bool { id.hasSuffix(".clock") || id.hasSuffix(".controlcenter") || id.hasSuffix("/Clock") || id.hasSuffix("/Control Center") }
    public var isSystem: Bool { bundleID.map { BarItem.systemOwners.contains($0) } ?? false }

    public init(id: String, pid: Int32, owner: String, bundleID: String?, name: String, detail: String, x: Double, tucked: Bool = false) {
        self.tucked = tucked; self.id = id; self.pid = pid; self.owner = owner; self.bundleID = bundleID; self.name = name; self.detail = detail; self.x = x
    }

    public static let systemOwners: Set<String> = ["com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.MenuBarAgent", "com.apple.campo"]

    /// Builds a row from the raw accessibility strings. System items are named by their own title ("Wi-Fi"),
    /// app items by the app, with the item's title as the detail.
    public static func make(pid: Int32, owner: String, bundleID: String?, title: String, description: String,
                            identifier: String, help: String, index: Int, x: Double) -> BarItem {
        let own = [title, description].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty } ?? ""
        let key = !identifier.isEmpty ? identifier : (!own.isEmpty ? own : "#\(index)")
        let id = "\(bundleID ?? owner)/\(key)"
        if let b = bundleID, systemOwners.contains(b) {
            let n = own.isEmpty ? "System item" : own
            let d = [description, help].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty && $0 != n && $0.lowercased().prefix(6) != n.lowercased().prefix(6) } ?? ""
            return BarItem(id: id, pid: pid, owner: owner, bundleID: bundleID, name: n, detail: d, x: x)
        }
        return BarItem(id: id, pid: pid, owner: owner, bundleID: bundleID, name: owner, detail: own == owner ? "" : own, x: x)
    }
}

public enum Group: String, CaseIterable, Sendable {
    case pinned = "Pinned", stack = "In the bar", hidden = "Tucked away"
}

public struct Row: Identifiable, Equatable, Sendable {
    public let item: BarItem
    public let group: Group
    public let nameMatch: [Int]    // highlighted character offsets in item.name
    public var id: String { item.id }
}

public struct Section: Identifiable, Equatable, Sendable {
    public let group: Group
    public let rows: [Row]
    public var id: Group { group }
}

/// Turns the raw item list into the grouped, filtered list the popover shows.
public enum Organizer {
    public static func sections(_ items: [BarItem], pinned: Set<String>, query: String) -> [Section] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var buckets: [Group: [(Row, Int)]] = [:]
        for item in items {
            let group: Group = pinned.contains(item.id) && !item.tucked ? .pinned : item.tucked ? .hidden : .stack
            var score = 0, idx: [Int] = []
            if !q.isEmpty {
                let a = Fuzzy.match(q, in: item.name), b = Fuzzy.match(q, in: item.detail + " " + item.owner)
                guard a != nil || b != nil else { continue }
                score = max(a?.score ?? 0, (b?.score ?? 0) - 10); idx = a?.indices ?? []
            }
            buckets[group, default: []].append((Row(item: item, group: group, nameMatch: idx), score))
        }
        return Group.allCases.compactMap { g in
            guard let rows = buckets[g], !rows.isEmpty else { return nil }
            let sorted = q.isEmpty ? rows.sorted { $0.0.item.x > $1.0.item.x }       // nearest the clock first
                                   : rows.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.item.x > $1.0.item.x }
            return Section(group: g, rows: sorted.map(\.0))
        }
    }

    public static func flat(_ s: [Section]) -> [Row] { s.flatMap(\.rows) }
}

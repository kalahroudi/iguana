import AppKit
import ApplicationServices
import IguanaKit

struct Scanned { var item: BarItem; let element: AXUIElement? }      // element is nil for items switched off in Settings that no longer exist

/// Reads other apps' menu bar items through the accessibility API. Nothing is cached between scans, and nothing runs unless asked.
enum Scanner {
    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func scan() async -> [Scanned] {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)   // global default: a hung app must not stall the list
        let me = getpid()
        let apps = NSWorkspace.shared.runningApplications.filter { $0.processIdentifier != me && !$0.isTerminated && $0.activationPolicy != .prohibited }
        return await withTaskGroup(of: [Scanned].self) { group in
            for app in apps {
                group.addTask { items(of: app.processIdentifier, owner: app.localizedName ?? "App", bundleID: app.bundleIdentifier) }
            }
            var all: [Scanned] = []
            for await part in group { all += part }
            return all
        }
    }

    private static func items(of pid: pid_t, owner: String, bundleID: String?) -> [Scanned] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)                        // a hung app must not stall the list
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXExtrasMenuBar" as CFString, &bar) == .success, let bar else { return [] }
        var kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success,
              let list = kids as? [AXUIElement] else { return [] }
        // Apple's own items live in one process ("MenuBarAgent") and expose no names themselves, but the element under
        // each one carries an identifier like com.apple.menuextra.wifi. Names are cached, because an item tucked away
        // is off screen and cannot be hit-tested.
        let agent = bundleID == "com.apple.MenuBarAgent"
        return list.enumerated().compactMap { i, el in
            var title = str(el, kAXTitleAttribute), ident = str(el, kAXIdentifierAttribute), desc = str(el, kAXDescriptionAttribute)
            if agent {
                let key = CFHash(el)
                if let c = cache.get(key) { (ident, title, desc) = c }
                else if let hit = identify(el), let n = SystemNames.name(forIdentifier: hit.id) { ident = hit.id; title = n; desc = hit.detail; cache.set(key, (ident, title, desc)) }
                else { return nil }
            }
            let p = point(el)
            var item = BarItem.make(pid: pid, owner: owner, bundleID: bundleID, title: title, description: agent ? "" : desc,
                                    identifier: ident, help: agent ? desc : str(el, kAXHelpAttribute), index: i, x: Double(p.x))
            if !agent { item.tucked = !isShown(el, pid: pid) }
            return Scanned(item: item, element: el)
        }
    }

    /// An item switched off in System Settings stays in the accessibility list with a stale position, but nothing answers there.
    /// So: it is in the bar only if the element under its position belongs to its own app.
    private static func isShown(_ el: AXUIElement, pid: pid_t) -> Bool {
        guard let f = frame(el), f.width > 0 else { return false }
        let sys = AXUIElementCreateSystemWide()
        for dx in [0, -3, 3] as [CGFloat] {
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(sys, Float(f.midX + dx), Float(f.midY), &hit) == .success, let hit else { continue }
            var p: pid_t = 0
            AXUIElementGetPid(hit, &p)
            if p == pid { return true }
        }
        return false
    }

    private final class Cache: @unchecked Sendable {
        private var d: [CFHashCode: (String, String, String)] = [:]; private let lock = NSLock()
        func get(_ k: CFHashCode) -> (String, String, String)? { lock.lock(); defer { lock.unlock() }; return d[k] }
        func set(_ k: CFHashCode, _ v: (String, String, String)) { lock.lock(); d[k] = v; lock.unlock() }
    }
    private static let cache = Cache()

    /// The identifier (and any description) of whatever is drawn at the item's position.
    private static func identify(_ el: AXUIElement) -> (id: String, detail: String)? {
        guard let f = frame(el), f.maxX > 0, f.minX < 20_000 else { return nil }
        let sys = AXUIElementCreateSystemWide()
        for dx in [0, -4, 4, -8, 8, -2, 2] as [CGFloat] {
            var hit: AXUIElement?
            guard AXUIElementCopyElementAtPosition(sys, Float(f.midX + dx), Float(f.midY), &hit) == .success, let hit else { continue }
            let id = str(hit, kAXIdentifierAttribute)
            if id.hasPrefix("com.apple.menuextra.") { return (id, str(hit, kAXDescriptionAttribute)) }
        }
        return nil
    }

    private static func str(_ el: AXUIElement, _ attr: String) -> String {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? (v as? String ?? "") : ""
    }

    private static func point(_ el: AXUIElement) -> CGPoint {
        var v: CFTypeRef?, p = CGPoint.zero
        if AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &v) == .success, let v { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
        return p
    }

    @discardableResult static func press(_ el: AXUIElement) -> Bool { AXUIElementPerformAction(el, kAXPressAction as CFString) == .success }
}

extension Scanner {
    /// Debug aid for `--list`: every attribute of an item, so unnamed items can be understood.
    static func dump(_ el: AXUIElement) -> String {
        var names: CFArray?
        AXUIElementCopyAttributeNames(el, &names)
        return (names as? [String] ?? []).map { n in
            var v: CFTypeRef?; AXUIElementCopyAttributeValue(el, n as CFString, &v)
            return "\(n)=\(v.map { "\($0)" }.map { String($0.prefix(60)) } ?? "nil")"
        }.joined(separator: "; ")
    }
}

extension Scanner {
    static func frame(_ el: AXUIElement) -> CGRect? {
        var pv: CFTypeRef?, sv: CFTypeRef?, p = CGPoint.zero, s = CGSize.zero
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pv) == .success, let pv,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sv) == .success, let sv,
              AXValueGetValue(pv as! AXValue, .cgPoint, &p), AXValueGetValue(sv as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }
}

extension Scanner {
    /// Right edge of the frontmost app's menus (File, Edit, Help...). Status items pushed under it are hidden by macOS.
    static func menuEnd() -> (Double, String)? {
        guard let app = NSWorkspace.shared.menuBarOwningApplication else { return nil }
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.25)
        var bar: CFTypeRef?, kids: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXMenuBarAttribute as CFString, &bar) == .success, let bar,
              AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &kids) == .success,
              let list = kids as? [AXUIElement] else { return nil }
        let end = list.compactMap { frame($0)?.maxX }.max()
        return end.map { (Double($0), app.localizedName ?? "?") }
    }
}

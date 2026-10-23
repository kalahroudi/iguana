import AppKit
import ApplicationServices

/// Hides and shows menu bar items the way macOS itself does it: the switches in System Settings → Menu Bar
/// ("Menu Bar Controls" and "Allow in the Menu Bar"). Iguana flips them for you, so an item that is switched off is
/// really gone from the bar, for every app, with no tricks. Always runs as one batch so Settings is opened only once.
@MainActor
enum MenuBarSettings {
    private static let bundleID = "com.apple.systempreferences"
    private static let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!

    struct Switch { let label: String; let element: AXUIElement }

    /// Sets each named item on or off. Returns the names whose switch ended up in the requested state.
    static func apply(_ changes: [(name: String, on: Bool)]) async -> Set<String> {
        guard !changes.isEmpty, Scanner.trusted else { return [] }
        let front = NSWorkspace.shared.frontmostApplication
        let wasRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first != nil

        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        cfg.hides = true                                           // keep Settings out of sight while we work
        _ = try? await NSWorkspace.shared.open(url, configuration: cfg)

        var done: Set<String> = []
        if let app = await settingsApp() {
            let root = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(root, 1.0)
            if let switches = await waitForSwitches(root) {
                var pending = Dictionary(grouping: switches) { norm($0.label) }
                for (name, on) in changes {
                    for sw in pending[norm(name)] ?? [] {
                        if value(sw.element) != on { AXUIElementPerformAction(sw.element, kAXPressAction as CFString) }
                    }
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
                for (name, on) in changes {
                    let list = pending[norm(name)] ?? []
                    if !list.isEmpty, list.allSatisfy({ value($0.element) == on }) { done.insert(name) }
                }
                pending.removeAll()
            }
            if !wasRunning { app.terminate() } else { app.hide() }
        }
        if let front, front.bundleIdentifier != bundleID { front.activate() }
        return done
    }

    private static func settingsApp() async -> NSRunningApplication? {
        for _ in 0..<30 {
            if let a = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first { return a }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return nil
    }

    /// The pane loads a moment after Settings starts; wait until its switches are there.
    private static func waitForSwitches(_ root: AXUIElement) async -> [Switch]? {
        for _ in 0..<40 {
            let s = switches(in: root)
            if s.count > 4 { return s }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return nil
    }

    /// Every checkbox in the Menu Bar pane, labelled by its own description or by the text just before it.
    private static func switches(in root: AXUIElement) -> [Switch] {
        var out: [Switch] = []
        var lastText = ""
        func walk(_ e: AXUIElement, _ depth: Int) {
            guard depth < 16 else { return }
            let role = str(e, kAXRoleAttribute)
            if role == "AXStaticText" { let v = str(e, kAXValueAttribute); if !v.isEmpty { lastText = v } }
            if role == "AXCheckBox" {
                let d = str(e, kAXDescriptionAttribute)
                out.append(Switch(label: d.isEmpty ? lastText : d, element: e))
                lastText = ""
            }
            var kids: CFTypeRef?
            if AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &kids) == .success, let k = kids as? [AXUIElement] { k.forEach { walk($0, depth + 1) } }
        }
        walk(root, 0)
        return out.filter { !$0.label.isEmpty }
    }

    private static func str(_ e: AXUIElement, _ a: String) -> String {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? (v as? String ?? "") : ""
    }
    private static func value(_ e: AXUIElement) -> Bool {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXValueAttribute as CFString, &v) == .success else { return true }
        return (v as? NSNumber)?.boolValue ?? true
    }
    /// Settings writes "Wi‑Fi" with a non-breaking hyphen; compare names loosely.
    static func norm(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{2011}", with: "-").lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

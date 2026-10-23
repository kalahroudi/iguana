import Foundation
import ServiceManagement
import IguanaKit

/// The only state Iguana keeps: which items you pinned or hid, and whether it starts at login.
final class Prefs {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    var pinned: Set<String> { get { Set(d.stringArray(forKey: "pinned") ?? []) } set { d.set(Array(newValue).sorted(), forKey: "pinned") } }

    func togglePin(_ id: String) { var p = pinned; if !p.insert(id).inserted { p.remove(id) }; pinned = p }

    /// Apple's own items switched off in Settings vanish from the accessibility list, so Iguana remembers them to keep them listed.
    struct Ghost: Codable { let id: String; let name: String; let owner: String; let bundleID: String? }
    var ghosts: [Ghost] {
        get { (d.data(forKey: "ghosts")).flatMap { try? JSONDecoder().decode([Ghost].self, from: $0) } ?? [] }
        set { d.set(try? JSONEncoder().encode(newValue), forKey: "ghosts") }
    }

    var showStats: Bool { get { UserDefaults.standard.object(forKey: "showStats") as? Bool ?? true } set { UserDefaults.standard.set(newValue, forKey: "showStats") } }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }
    func setLaunchAtLogin(_ on: Bool) { try? (on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()) }

    /// Opt in to launch at login once; after that the user's choice wins.
    func firstRunDefaults() {
        guard !d.bool(forKey: "launchDefaulted") else { return }
        d.set(true, forKey: "launchDefaulted"); setLaunchAtLogin(true)
    }
}

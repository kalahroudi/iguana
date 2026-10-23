import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Menu bar item + popover. The popover's views exist only while it is open; nothing polls while it is closed.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var model: PopoverModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "iguana.main"
        statusItem.button?.image = StatusIcon.image()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem.button?.setAccessibilityLabel("Iguana")
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        Hotkey.register { [weak self] in self?.toggle() }
        Prefs.shared.firstRunDefaults()
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { toggle() }
    }

    private func toggle() {
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        let m = PopoverModel()
        m.close = { [weak self] in self?.popover.performClose(nil) }
        model = m
        let host = NSHostingController(rootView: PopoverView(model: m))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        m.load()
    }

    func popoverDidClose(_ notification: Notification) {
        model?.stop()
        popover.contentViewController = nil      // free every view and the scanned items
        model = nil
    }

    private func showMenu() {
        let m = NSMenu()
        let login = m.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; login.state = Prefs.shared.launchAtLogin ? .on : .off
        let ax = m.addItem(withTitle: Scanner.trusted ? "Accessibility: allowed" : "Allow Accessibility…", action: #selector(askAX), keyEquivalent: "")
        ax.target = self; ax.isEnabled = !Scanner.trusted
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Iguana", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = m; statusItem.button?.performClick(nil); statusItem.menu = nil
    }
    @objc private func toggleLogin() { Prefs.shared.setLaunchAtLogin(!Prefs.shared.launchAtLogin) }
    @objc private func askAX() { Scanner.requestTrust() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

/// Global ⌃⌥Space through Carbon's hot key API: no permission needed, no polling.
enum Hotkey {
    nonisolated(unsafe) private static var action: (() -> Void)?
    static func register(_ handler: @escaping () -> Void) {
        action = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { Hotkey.action?() }; return noErr
        }, 1, &spec, nil, nil)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x49475541, id: 1), GetApplicationEventTarget(), 0, &ref)
    }
}

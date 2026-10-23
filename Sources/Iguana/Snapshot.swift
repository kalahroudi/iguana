import SwiftUI
import AppKit
import IguanaKit
import ApplicationServices

/// `Iguana --snapshot out.png [query]` renders the popover with sample data (never real data) for docs and layout checks.
@MainActor enum Snapshot {
    static func run(path: String, query: String) {
        let m = PopoverModel()
        let dummy = AXUIElementCreateSystemWide()
        func it(_ id: String, _ n: String, _ d: String, _ x: Double) -> Scanned {
            Scanned(item: BarItem(id: id, pid: 0, owner: n, bundleID: "com.apple.controlcenter", name: n, detail: d, x: x), element: dummy)
        }
        m.items = [it("wifi", "Wi-Fi", "Home 5G", 900), it("bat", "Battery", "87%", 860), it("clock", "Clock", "18:12", 820),
                   it("bt", "Bluetooth", "2 devices", 780), it("snd", "Sound", "Speakers", 740), it("focus", "Focus", "Off", 700),
                   it("disp", "Display", "Built-in", 660), it("kbd", "Keyboard", "EN", 620), it("vpn", "VPN", "Connected", 580), it("mic", "Microphone", "In use", 100)]
        m.items[9].item.tucked = true
        m.items[0].item.tucked = false
        Prefs.shared.pinned = ["wifi", "bat", "clock"]; m.stats = StatsSample(cpu: 0.12, ram: 0.61, ramUsed: 19 << 30, ramTotal: 32 << 30, gpu: 0.08, vramUsed: 3 << 30)
        m.loaded = true; m.trusted = true; m.query = query
        let host = NSHostingView(rootView: PopoverView(model: m).background(Color(nsColor: .windowBackgroundColor)))
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        Prefs.shared.pinned = []
        exit(0)
    }
}

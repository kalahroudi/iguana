import XCTest
@testable import IguanaKit

final class IguanaKitTests: XCTestCase {
    func item(_ id: String, _ name: String, x: Double, detail: String = "") -> BarItem {
        BarItem(id: id, pid: 1, owner: name, bundleID: nil, name: name, detail: detail, x: x)
    }

    func testFuzzyPrefersContiguousAndPrefix() {
        XCTAssertEqual(Fuzzy.match("bl", in: "Bluetooth")?.indices, [0, 1])
        XCTAssertNotNil(Fuzzy.match("btth", in: "Bluetooth"))
        XCTAssertNil(Fuzzy.match("xyz", in: "Bluetooth"))
        XCTAssertGreaterThan(Fuzzy.match("wi", in: "Wi-Fi")!.score, Fuzzy.match("wi", in: "Display widget")!.score)
        XCTAssertEqual(Fuzzy.match("", in: "x")?.indices, [])
    }

    func testSectionsGroupByTucked() {
        var mic = item("c", "Mic", x: 50); mic.tucked = true
        let items = [item("a", "Battery", x: 100), item("b", "Wi-Fi", x: 200), mic, item("d", "Clock", x: 300)]
        let s = Organizer.sections(items, pinned: ["d"], query: "")
        XCTAssertEqual(s.map(\.group), [.pinned, .stack, .hidden])
        XCTAssertEqual(s[1].rows.map(\.item.name), ["Wi-Fi", "Battery"])    // right-most first
        XCTAssertEqual(s[2].rows.map(\.item.name), ["Mic"])                  // switched off in Settings
    }

    func testSearchHighlightsAcrossGroups() {
        var mic = item("c", "Microphone", x: 1); mic.tucked = true
        let items = [mic, item("a", "Battery", x: 200)]
        let s = Organizer.sections(items, pinned: [], query: "mic")
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s[0].group, .hidden)
        XCTAssertEqual(s[0].rows[0].nameMatch, [0, 1, 2])
    }

    func testCPULoad() {
        let a = CPUTicks(user: 100, system: 50, idle: 850, nice: 0), b = CPUTicks(user: 150, system: 70, idle: 880, nice: 0)
        XCTAssertEqual(b.load(since: a), 0.7, accuracy: 0.001)       // 70 busy of 100 elapsed
        XCTAssertEqual(a.load(since: a), 0)
    }

    func testSystemItemNaming() {
        let w = BarItem.make(pid: 5, owner: "Control Center", bundleID: "com.apple.controlcenter", title: "Wi-Fi", description: "Home 5G",
                             identifier: "com.apple.menuextra.wifi", help: "", index: 0, x: 10)
        XCTAssertEqual(w.name, "Wi-Fi"); XCTAssertEqual(w.detail, "Home 5G"); XCTAssertEqual(w.id, "com.apple.controlcenter/com.apple.menuextra.wifi")
        let a = BarItem.make(pid: 6, owner: "Timer", bundleID: "x.timer", title: "12:00", description: "", identifier: "", help: "", index: 0, x: 1)
        XCTAssertEqual(a.name, "Timer"); XCTAssertEqual(a.detail, "12:00")
    }

    func testUnnamedSystemItem() {
        let u = BarItem.make(pid: 1, owner: "MenuBarAgent", bundleID: "com.apple.MenuBarAgent", title: "", description: "", identifier: "", help: "", index: 2, x: 5)
        XCTAssertEqual(u.name, "System item"); XCTAssertEqual(u.id, "com.apple.MenuBarAgent/#2")
    }

    func testSystemNames() {
        XCTAssertEqual(SystemNames.name(forIdentifier: "com.apple.menuextra.wifi"), "Wi-Fi")
        XCTAssertEqual(SystemNames.name(forIdentifier: "com.apple.menuextra.controlcenter"), "Control Center")
        XCTAssertEqual(SystemNames.name(forIdentifier: "com.apple.menuextra.fooBar"), "Foo Bar")
        XCTAssertNil(SystemNames.name(forIdentifier: "x.y"))
        XCTAssertTrue(SystemNames.isFixed(identifier: "com.apple.menuextra.clock"))
        XCTAssertFalse(SystemNames.isFixed(identifier: "com.apple.menuextra.battery"))
    }
}

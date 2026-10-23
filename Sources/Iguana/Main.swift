import AppKit
import IguanaKit

/// Plain AppKit entry point: no SwiftUI App scene, so no stray Settings window.
@main
enum IguanaMain {
    static let delegate = MainActor.assumeIsolated { AppDelegate() }

    static func main() {
        let args = CommandLine.arguments
        if args.contains("--self-test") { print("ok"); exit(0) }
        if let i = args.firstIndex(of: "--write-iconset"), i + 1 < args.count {
            MainActor.assumeIsolated { do { try AppIcon.writeIconset(to: args[i + 1]); exit(0) } catch { print(error); exit(1) } }
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated { _ = NSApplication.shared; Snapshot.run(path: args[i + 1], query: i + 2 < args.count ? args[i + 2] : "") }
        }
        if args.contains("--stats") { let r = StatsReader(); _ = r.sample(); Thread.sleep(forTimeInterval: 1); print(r.sample()); exit(0) }
        if args.contains("--list") {                      // debugging aid: print what the scanner sees
            setvbuf(stdout, nil, _IONBF, 0); print("accessibility trusted: \(Scanner.trusted)")
            let sem = DispatchSemaphore(value: 0)
            Task.detached { for s in await Scanner.scan().sorted(by: { $0.item.x > $1.item.x }) { print(String(format: "%7.0f  %@ | %@ | %@", s.item.x, s.item.name, s.item.detail, s.item.id)) }; sem.signal() }
            sem.wait(); exit(0)
        }
        // One copy only: a second would fight over the menu bar item.
        if let id = Bundle.main.bundleIdentifier {
            for attempt in 0..<10 {
                let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != getpid() && !$0.isTerminated }
                guard let other = others.first else { break }
                if attempt == 9 { other.activate(); exit(0) }
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            app.delegate = delegate
            app.run()
        }
    }
}

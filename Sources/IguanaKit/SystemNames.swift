import Foundation

/// macOS tags its own menu bar items with identifiers like `com.apple.menuextra.wifi`. This turns them into names a person would use.
public enum SystemNames {
    static let known: [String: String] = [
        "wifi": "Wi-Fi", "battery": "Battery", "bluetooth": "Bluetooth", "clock": "Clock", "controlcenter": "Control Center",
        "sound": "Sound", "volume": "Sound", "display": "Display", "focusmode": "Focus", "focus": "Focus", "airplay": "Screen Mirroring",
        "screenmirroring": "Screen Mirroring", "vpn": "VPN", "airdrop": "AirDrop", "textinput": "Input Source", "keyboardbrightness": "Keyboard Brightness",
        "spotlight": "Spotlight", "siri": "Siri", "timemachine": "Time Machine", "user": "Fast User Switching", "nowplaying": "Now Playing",
        "wirelessnetworks": "Wi-Fi", "stagemanager": "Stage Manager", "weather": "Weather", "accessibility": "Accessibility Shortcuts",
    ]

    public static func name(forIdentifier id: String) -> String? {
        guard id.hasPrefix("com.apple.menuextra.") else { return nil }
        let key = String(id.dropFirst("com.apple.menuextra.".count))
        if let n = known[key.lowercased()] { return n }
        // Unknown ones: "someThing" -> "Some Thing".
        var out = ""
        for c in key { if c.isUppercase, !out.isEmpty { out.append(" ") }; out.append(out.isEmpty ? Character(c.uppercased()) : c) }
        return out.isEmpty ? nil : out
    }

    /// Items macOS does not let you move.
    public static func isFixed(identifier: String) -> Bool {
        identifier.hasSuffix(".clock") || identifier.hasSuffix(".controlcenter")
    }
}

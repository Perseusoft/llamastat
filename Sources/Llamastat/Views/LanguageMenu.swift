import AppKit
import Foundation

/// Per-app language override. macOS reads `AppleLanguages` from the app's defaults at launch,
/// so changing it needs a relaunch.
@MainActor
enum AppLanguage {
    /// nil = follow the system.
    static var current: String? {
        UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"]
            .flatMap { ($0 as? [String])?.first }
    }

    static func select(_ code: String?) {
        guard code != current else { return }
        if let code {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? relaunch.run()
        NSApplication.shared.terminate(nil)
    }
}

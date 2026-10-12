import SwiftUI

/// Per-app language override. macOS reads `AppleLanguages` from the app's defaults at launch,
/// so changing it needs a relaunch.
struct LanguageMenu: View {
    private static let options: [(code: String?, name: String)] = [
        (nil, String(localized: "System")),
        ("en", "English"),
        ("es", "Español"),
    ]

    private var current: String? {
        UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"]
            .flatMap { ($0 as? [String])?.first }
    }

    var body: some View {
        Menu {
            ForEach(Self.options, id: \.name) { option in
                Button {
                    select(option.code)
                } label: {
                    if option.code == current {
                        Label(option.name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: option.name)
                    }
                }
            }
        } label: {
            Image(systemName: "globe")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Language")
    }

    private func select(_ code: String?) {
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

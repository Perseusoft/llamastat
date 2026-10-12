import SwiftUI

@main
struct LlamastatApp: App {
    @State private var monitor = Monitor()
    @State private var settings = AppSettings.shared

    init() {
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.render(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(monitor)
                .environment(settings)
                .fitWindowToContent()
        } label: {
            StatusLabel(monitor: monitor, settings: settings)
                .task { monitor.start() }
                .modifier(OpenSettingsOnLaunch())
        }
        .menuBarExtraStyle(.window)

        Window("Llamastat", id: SettingsWindow.id) {
            SettingsWindow()
                .environment(monitor)
                .environment(settings)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// `--open-settings [page]` opens the settings window at launch (handy for screenshots).
private struct OpenSettingsOnLaunch: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task {
            let args = CommandLine.arguments
            guard args.contains("--open-settings") else { return }
            openWindow(id: SettingsWindow.id)
            NSApp.activate(ignoringOtherApps: true)
            // `--window-shot out.png`: draw the window into a PNG after it has collected some samples.
            guard let i = args.firstIndex(of: "--window-shot"), i + 1 < args.count else { return }
            try? await Task.sleep(for: .seconds(15))
            if let view = NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue.hasPrefix(SettingsWindow.id) == true })?.contentView?.superview,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
            }
            NSApp.terminate(nil)
        }
    }
}

/// `Llamastat --snapshot out.png`: samples for a few seconds, renders the popover to a PNG and exits.
/// Used for README screenshots and checking the layout without clicking the menu bar.
@MainActor
enum Snapshot {
    static func render(to url: URL, seconds: Int = 8) {
        let monitor = Monitor()
        Task { @MainActor in
            for _ in 0..<seconds {
                await monitor.tick()
                try? await Task.sleep(for: .seconds(1))
            }
            let settings = AppSettings.shared
            // Menu bar items with every widget on, monochrome and colored, on light and dark bars.
            let allWidgets = MenuBarWidget.allCases.map { WidgetSetting(widget: $0, enabled: true) }
            let previewSettings = AppSettings.scratch()
            previewSettings.widgets = allWidgets
            previewSettings.tokensOnlyWhileGenerating = false
            let bars = VStack(alignment: .leading, spacing: 6) {
                ForEach([false, true], id: \.self) { colored in
                    ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                        StatusContent(monitor: monitor, settings: previewSettings, colored: colored)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(scheme == .dark ? Color(white: 0.15) : Color(white: 0.92))
                            .environment(\.colorScheme, scheme)
                    }
                }
            }
            .padding(8)
            let barImage = ImageRenderer(content: bars)
            barImage.scale = 2
            if let image = barImage.nsImage, let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: url.deletingPathExtension().appendingPathExtension("menubar.png"))
            }

            let view = PopoverView()
                .environment(monitor)
                .environment(settings)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let image = renderer.nsImage,
               let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: url)
            }
            exit(0)
        }
    }
}

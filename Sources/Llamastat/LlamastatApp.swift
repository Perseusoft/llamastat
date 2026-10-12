import SwiftUI

@main
struct LlamastatApp: App {
    @State private var monitor = Monitor()

    init() {
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            Snapshot.render(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(monitor)
        } label: {
            StatusLabel(monitor: monitor)
                .task { monitor.start() }
        }
        .menuBarExtraStyle(.window)
    }
}

/// What sits in the menu bar: live t/s while generating, else the loaded model.
struct StatusLabel: View {
    var monitor: Monitor

    var body: some View {
        if monitor.isGenerating {
            Text("🦙 \(Format.rate(monitor.generationRate))")
        } else if let model = monitor.active.first {
            Text("🦙 \(Format.shortName(model.info.name))")
        } else if monitor.onlineBackends.isEmpty {
            Text("🦙 off")
        } else {
            Text("🦙")
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
            let view = PopoverView()
                .environment(monitor)
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

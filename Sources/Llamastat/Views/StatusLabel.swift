import SwiftUI

/// The menu bar item. MenuBarExtra labels only take Text/Image, so the widgets are drawn
/// as a SwiftUI view and rasterized into an NSImage (template image when monochrome).
struct StatusLabel: View {
    var monitor: Monitor
    var settings: AppSettings

    var body: some View {
        // ImageRenderer evaluates the content outside this body, so Observation can't see what it
        // reads. Touch the inputs here so the label re-renders on every tick and settings change.
        let _ = (settings.widgets, settings.icon, settings.tokensOnlyWhileGenerating, monitor.history.last?.time)
        let content = StatusContent(monitor: monitor, settings: settings, colored: settings.coloredMenuBar)
        if let image = render(content) {
            Image(nsImage: image)
        } else {
            Text(verbatim: "🦙")
        }
    }

    private func render(_ content: StatusContent) -> NSImage? {
        // Colored mode can't be a template, so match the menu bar's light/dark appearance by hand.
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage, image.size.width > 0 else { return nil }
        // Template images are tinted by the system to match the menu bar (light/dark, tinted).
        image.isTemplate = !settings.coloredMenuBar
        return image
    }
}

struct StatusContent: View {
    var monitor: Monitor
    var settings: AppSettings
    var colored: Bool

    private var tint: Color { colored ? .primary : .black }

    var body: some View {
        let widgets = settings.widgets.filter(\.enabled).map(\.widget).filter(isShown)
        HStack(spacing: 5) {
            if widgets.isEmpty {
                IconView(icon: settings.icon, tint: tint)
            }
            ForEach(widgets) { widget in
                view(for: widget)
            }
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundStyle(tint)
        .frame(height: 18)
        .fixedSize()
    }

    private func isShown(_ widget: MenuBarWidget) -> Bool {
        switch widget {
        case .tokensPerSecond: !settings.tokensOnlyWhileGenerating || monitor.isGenerating
        case .model: !monitor.active.isEmpty && !(settings.tokensOnlyWhileGenerating && monitor.isGenerating && hasTokens)
        case .context: monitor.contextFraction != nil
        default: true
        }
    }

    /// While generating, tokens/s replaces the model name to keep the item short.
    private var hasTokens: Bool { settings.widgets.contains { $0.widget == .tokensPerSecond && $0.enabled } }

    @ViewBuilder private func view(for widget: MenuBarWidget) -> some View {
        switch widget {
        case .icon:
            IconView(icon: settings.icon, tint: tint)
                .opacity(monitor.onlineBackends.isEmpty ? 0.4 : 1)
        case .tokensPerSecond:
            Text(verbatim: Format.rate(monitor.generationRate) == "—" ? "0 t/s" : Format.rate(monitor.generationRate))
        case .model:
            Text(verbatim: monitor.active.map { Format.shortName($0.info.name) }.joined(separator: " + "))
        case .ram:
            Label(Format.percent(monitor.memory.usedFraction), systemImage: "memorychip")
                .foregroundStyle(colored && monitor.memory.usedFraction > 0.85 ? Palette.warning : tint)
        case .gpu:
            Label(Format.percent(monitor.gpu?.utilization ?? 0), systemImage: "cpu")
        case .context:
            Label(Format.percent(monitor.contextFraction), systemImage: "text.alignleft")
        case .ramBar:
            VerticalBar(fraction: monitor.memory.usedFraction, color: colored ? Palette.memory : tint)
        case .sparkline:
            Sparkline(values: monitor.recentHistory.suffix(30).map(\.generationRate), color: colored ? Palette.generation : tint)
        }
    }
}

struct IconView: View {
    var icon: MenuBarIcon
    var tint: Color

    var body: some View {
        if let emoji = icon.emoji {
            // In monochrome mode the template mask turns the emoji into a silhouette.
            Text(verbatim: emoji).font(.system(size: 13))
        } else {
            Image(systemName: icon.symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(tint)
        }
    }
}

/// Stats-style vertical fill bar.
struct VerticalBar: View {
    var fraction: Double
    var color: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1.5).stroke(color.opacity(0.6), lineWidth: 1)
            RoundedRectangle(cornerRadius: 1.5).fill(color)
                .frame(height: max(1, 14 * min(max(fraction, 0), 1)))
                .padding(1.5)
        }
        .frame(width: 7, height: 16)
    }
}

/// Tiny area chart for the menu bar.
struct Sparkline: View {
    var values: [Double]
    var color: Color
    var width: CGFloat = 34

    var body: some View {
        let peak = max(values.max() ?? 0, 1)
        Canvas { context, size in
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(values.count - 1)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            for (i, value) in values.enumerated() {
                path.addLine(to: CGPoint(x: CGFloat(i) * step, y: size.height * (1 - value / peak)))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(color.opacity(0.5)))
            context.stroke(path, with: .color(color), lineWidth: 1)
        }
        .frame(width: width, height: 15)
        .overlay(Rectangle().stroke(color.opacity(0.4), lineWidth: 0.5))
    }
}

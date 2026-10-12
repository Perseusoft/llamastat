import Charts
import ServiceManagement
import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case dashboard, menuBar, panel, backends, general
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .dashboard: "Dashboard"
        case .menuBar: "Menu bar"
        case .panel: "Panel"
        case .backends: "Backends"
        case .general: "General"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "square.grid.3x3.fill"
        case .menuBar: "menubar.rectangle"
        case .panel: "rectangle.portrait.topthird.inset.filled"
        case .backends: "server.rack"
        case .general: "gearshape"
        }
    }
}

struct SettingsWindow: View {
    static let id = "settings"
    @State private var page: SettingsPage? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $page) { page in
                Label(page.title, systemImage: page.symbol).tag(page)
            }
            .navigationSplitViewColumnWidth(170)
        } detail: {
            ScrollView {
                Group {
                    switch page ?? .dashboard {
                    case .dashboard: DashboardPage()
                    case .menuBar: MenuBarPage()
                    case .panel: PanelPage()
                    case .backends: BackendsPage()
                    case .general: GeneralPage()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .navigationTitle(page?.title ?? "Llamastat")
        }
        .frame(width: 780, height: 560)
        .onAppear {
            // SwiftUI restores the last selection; `--open-settings <page>` should win.
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--open-settings"), i + 1 < args.count, let requested = SettingsPage(rawValue: args[i + 1]) {
                page = requested
            }
        }
    }
}

/// White rounded panel like Stats' settings cards.
struct Card<Content: View>: View {
    var title: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title).font(.headline)
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.track, lineWidth: 0.5))
    }
}

// MARK: - Dashboard

struct DashboardPage: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        VStack(spacing: 14) {
            memoryCard
            Card(title: "Tokens per second") {
                TimeChart(history: monitor.history, value: \.generationRate, color: Palette.generation, unit: "t/s")
            }
            HStack(alignment: .top, spacing: 14) {
                Card(title: "GPU") {
                    HStack {
                        Ring(fraction: monitor.gpu?.utilization ?? 0, color: Palette.gpu,
                             label: Format.percent(monitor.gpu?.utilization), caption: "", size: 70)
                        TimeChart(history: monitor.history, value: { $0.gpu * 100 }, color: Palette.gpu, unit: "%", maxY: 100, height: 80)
                    }
                }
                Card(title: "Swap") {
                    HStack {
                        Ring(fraction: monitor.memory.swapTotal == 0 ? 0 : Double(monitor.memory.swapUsed) / Double(monitor.memory.swapTotal),
                             color: Palette.prompt, label: Format.gigabytes(monitor.memory.swapUsed), caption: "", size: 70)
                        TimeChart(history: monitor.history, value: { Double($0.swap) / 1_073_741_824 }, color: Palette.prompt, unit: "GB", height: 80)
                    }
                }
            }
            ForEach(monitor.active) { model in
                Card {
                    Text(verbatim: model.info.name).font(.headline)
                    ModelDetails(model: model)
                }
            }
        }
    }

    private var memoryCard: some View {
        let memory = monitor.memory
        let app = memory.used - min(memory.used, memory.wired + memory.compressed)
        let free = memory.total - min(memory.total, memory.used)
        return Card {
            HStack(spacing: 18) {
                Ring(fraction: memory.usedFraction, color: memory.usedFraction > 0.85 ? Palette.warning : Palette.memory,
                     label: Format.percent(memory.usedFraction), caption: "RAM", size: 80, lineWidth: 8)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Used: \(Format.gigabytes(memory.used))")
                        Spacer()
                        Text("Total: \(Format.gigabytes(memory.total))")
                    }
                    .font(.callout)
                    GeometryReader { geo in
                        HStack(spacing: 0) {
                            segment(app, of: memory.total, Palette.generation, geo.size.width)
                            segment(memory.wired, of: memory.total, Palette.gpu, geo.size.width)
                            segment(memory.compressed, of: memory.total, Palette.warning, geo.size.width)
                            Spacer(minLength: 0)
                        }
                        .background(Palette.track)
                        .clipShape(Capsule())
                    }
                    .frame(height: 10)
                    HStack(spacing: 14) {
                        legend(Palette.generation, "App", app)
                        legend(Palette.gpu, "Wired", memory.wired)
                        legend(Palette.warning, "Compressed", memory.compressed)
                        legend(Palette.track, "Free", free)
                    }
                    .font(.caption)
                }
            }
            TimeChart(history: monitor.history, value: { $0.memory * 100 }, color: Palette.memory, unit: "%", maxY: 100, height: 90)
        }
    }

    private func segment(_ value: UInt64, of total: UInt64, _ color: Color, _ width: CGFloat) -> some View {
        Rectangle().fill(color).frame(width: total == 0 ? 0 : width * CGFloat(Double(value) / Double(total)))
    }

    private func legend(_ color: Color, _ title: LocalizedStringKey, _ value: UInt64) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title) + Text(verbatim: ": ")
            Text(verbatim: Format.gigabytes(value)).fontWeight(.semibold)
        }
    }
}

struct TimeChart: View {
    var history: [Sample]
    var value: (Sample) -> Double
    var color: Color
    var unit: String
    var maxY: Double?
    var height: CGFloat = 140

    var body: some View {
        let peak = maxY ?? max(history.map(value).max() ?? 0, 10)
        Chart(history) { sample in
            AreaMark(x: .value("t", sample.time), y: .value(unit, value(sample)))
                .foregroundStyle(color.opacity(0.35).gradient)
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", sample.time), y: .value(unit, value(sample)))
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.2))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...peak)
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisValueLabel(format: .dateTime.hour().minute().second()) } }
        .frame(height: height)
    }
}

// MARK: - Menu bar

struct MenuBarPage: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 14) {
            Card(title: "Preview") {
                HStack {
                    Spacer()
                    StatusContent(monitor: monitor, settings: settings, colored: true)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.secondary.opacity(0.15)))
                    Spacer()
                }
            }
            Card(title: "Icon") {
                HStack(spacing: 10) {
                    ForEach(MenuBarIcon.allCases) { icon in
                        Button { settings.icon = icon } label: {
                            IconView(icon: icon, tint: .primary)
                                .frame(width: 40, height: 32)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(settings.icon == icon ? Color.accentColor.opacity(0.25) : Palette.track.opacity(0.4)))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(settings.icon == icon ? Color.accentColor : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Card(title: "Widgets") {
                Text("Turn widgets on and drag them to change the order.").font(.caption).foregroundStyle(.secondary)
                List {
                    ForEach($settings.widgets) { $item in
                        HStack {
                            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                            Image(systemName: item.widget.symbol).frame(width: 20)
                            Text(item.widget.title)
                            Spacer()
                            Toggle("", isOn: $item.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        }
                    }
                    .onMove { settings.widgets.move(fromOffsets: $0, toOffset: $1) }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .frame(height: CGFloat(settings.widgets.count) * 30 + 8)
            }
            Card(title: "Options") {
                Toggle("Colored (otherwise follows the menu bar color)", isOn: $settings.coloredMenuBar)
                Toggle("Show tokens/s only while generating", isOn: $settings.tokensOnlyWhileGenerating)
                Button("Restore defaults") { settings.resetMenuBar() }
            }
        }
    }
}

// MARK: - Panel

struct PanelPage: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Card(title: "Sections shown in the panel") {
            ForEach(PopoverSection.allCases) { section in
                Toggle(section.title, isOn: Binding(
                    get: { settings.isVisible(section) },
                    set: { settings.setVisible(section, $0) }
                ))
            }
        }
    }
}

// MARK: - Backends

struct BackendsPage: View {
    @Environment(Monitor.self) private var monitor
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 14) {
            Card {
                header(.llamaCpp, isOn: $settings.llamaCppEnabled)
                LabeledContent("URL") { TextField("", text: $settings.llamaCppURL).textFieldStyle(.roundedBorder) }
                LabeledContent("LaunchAgent") { TextField("", text: $settings.routerLabel).textFieldStyle(.roundedBorder) }
                Text("Router mode (llama-server --models-preset). Add metrics = 1 to each preset for token stats.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Card {
                header(.ollama, isOn: $settings.ollamaEnabled)
                LabeledContent("URL") { TextField("", text: $settings.ollamaURL).textFieldStyle(.roundedBorder) }
                Text("Ollama doesn't expose token counters; only memory, context and expiry are shown.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func header(_ kind: BackendKind, isOn: Binding<Bool>) -> some View {
        let online = monitor.backends.first { $0.kind == kind }?.online ?? false
        return HStack {
            Text(verbatim: kind.rawValue).font(.headline)
            Circle().fill(online ? Color.green : Palette.track).frame(width: 8, height: 8)
            Text(online ? "Online" : "Offline").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
    }
}

// MARK: - General

struct GeneralPage: View {
    @Environment(AppSettings.self) private var settings
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var settings = settings
        VStack(spacing: 14) {
            Card {
                Picker("Language", selection: Binding(get: { AppLanguage.current }, set: { AppLanguage.select($0) })) {
                    Text("System").tag(String?.none)
                    Text(verbatim: "English").tag(String?.some("en"))
                    Text(verbatim: "Español").tag(String?.some("es"))
                }
                Text("Changing the language restarts the app.").font(.caption).foregroundStyle(.secondary)
            }
            Card {
                Picker("Update every", selection: $settings.refreshInterval) {
                    Text(verbatim: "1 s").tag(1.0)
                    Text(verbatim: "2 s").tag(2.0)
                    Text(verbatim: "5 s").tag(5.0)
                }
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(verbatim: loginError).font(.caption).foregroundStyle(Palette.warning)
                }
            }
            Card {
                HStack {
                    Text(verbatim: "Llamastat \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                }
            }
        }
    }
}

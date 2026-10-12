import Foundation
import Observation
import SwiftUI

/// Things that can be shown in the menu bar, in the user's order.
enum MenuBarWidget: String, CaseIterable, Codable, Identifiable {
    case icon, tokensPerSecond, model, ram, gpu, context, ramBar, sparkline
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .icon: "Icon"
        case .tokensPerSecond: "Tokens per second"
        case .model: "Loaded model"
        case .ram: "RAM %"
        case .gpu: "GPU %"
        case .context: "Context used %"
        case .ramBar: "RAM bar"
        case .sparkline: "Tokens/s graph"
        }
    }

    var symbol: String {
        switch self {
        case .icon: "face.smiling"
        case .tokensPerSecond: "speedometer"
        case .model: "cube"
        case .ram: "memorychip"
        case .gpu: "cpu"
        case .context: "text.alignleft"
        case .ramBar: "chart.bar.fill"
        case .sparkline: "waveform.path.ecg"
        }
    }
}

struct WidgetSetting: Codable, Identifiable, Equatable {
    var widget: MenuBarWidget
    var enabled: Bool
    var id: String { widget.rawValue }
}

enum MenuBarIcon: String, CaseIterable, Codable, Identifiable {
    case llama, chip, brain, bolt, sparkles
    var id: String { rawValue }

    /// Emoji are drawn as text; the rest are SF Symbols.
    var emoji: String? { self == .llama ? "🦙" : nil }
    var symbol: String {
        switch self {
        case .llama: "pawprint.fill"
        case .chip: "cpu"
        case .brain: "brain"
        case .bolt: "bolt.fill"
        case .sparkles: "sparkles"
        }
    }
}

enum PopoverSection: String, CaseIterable, Codable, Identifiable {
    case rings, warnings, history, models, memory, modelList
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .rings: "Gauges"
        case .warnings: "Warnings"
        case .history: "History"
        case .models: "Loaded model details"
        case .memory: "Memory"
        case .modelList: "Models"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    var widgets: [WidgetSetting] { didSet { save(widgets, "widgets") } }
    var icon: MenuBarIcon { didSet { save(icon, "icon") } }
    var coloredMenuBar: Bool { didSet { save(coloredMenuBar, "coloredMenuBar") } }
    /// Hide tokens/s while nothing is generating, so the menu bar stays quiet.
    var tokensOnlyWhileGenerating: Bool { didSet { save(tokensOnlyWhileGenerating, "tokensOnlyWhileGenerating") } }
    var hiddenSections: Set<PopoverSection> { didSet { save(hiddenSections, "hiddenSections") } }
    var refreshInterval: Double { didSet { save(refreshInterval, "refreshInterval") } }
    var llamaCppEnabled: Bool { didSet { save(llamaCppEnabled, "llamaCppEnabled") } }
    var llamaCppURL: String { didSet { save(llamaCppURL, "llamaCppURL") } }
    var routerLabel: String { didSet { save(routerLabel, "routerLabel") } }
    var ollamaEnabled: Bool { didSet { save(ollamaEnabled, "ollamaEnabled") } }
    var ollamaURL: String { didSet { save(ollamaURL, "ollamaURL") } }

    static let defaultWidgets: [WidgetSetting] = [
        .init(widget: .icon, enabled: true),
        .init(widget: .tokensPerSecond, enabled: true),
        .init(widget: .model, enabled: true),
        .init(widget: .sparkline, enabled: false),
        .init(widget: .ram, enabled: false),
        .init(widget: .ramBar, enabled: false),
        .init(widget: .gpu, enabled: false),
        .init(widget: .context, enabled: false),
    ]

    /// False for throwaway copies (screenshots) so they never touch the user's saved settings.
    private let persists: Bool

    /// A non-persisting copy, for previews.
    static func scratch() -> AppSettings { AppSettings(persists: false) }

    private init(persists: Bool = true) {
        self.persists = persists
        widgets = Self.load("widgets") ?? Self.defaultWidgets
        icon = Self.load("icon") ?? .llama
        coloredMenuBar = Self.load("coloredMenuBar") ?? false
        tokensOnlyWhileGenerating = Self.load("tokensOnlyWhileGenerating") ?? true
        hiddenSections = Self.load("hiddenSections") ?? []
        refreshInterval = Self.load("refreshInterval") ?? 1
        llamaCppEnabled = Self.load("llamaCppEnabled") ?? true
        llamaCppURL = Self.load("llamaCppURL") ?? "http://127.0.0.1:8080"
        routerLabel = Self.load("routerLabel") ?? "com.local.llama-router"
        ollamaEnabled = Self.load("ollamaEnabled") ?? true
        ollamaURL = Self.load("ollamaURL") ?? "http://127.0.0.1:11434"

        // Widgets added in later versions show up at the end, disabled.
        let known = Set(widgets.map(\.widget))
        widgets += MenuBarWidget.allCases.filter { !known.contains($0) }.map { .init(widget: $0, enabled: false) }
    }

    func isVisible(_ section: PopoverSection) -> Bool { !hiddenSections.contains(section) }

    func setVisible(_ section: PopoverSection, _ visible: Bool) {
        if visible { hiddenSections.remove(section) } else { hiddenSections.insert(section) }
    }

    func resetMenuBar() {
        widgets = Self.defaultWidgets
        icon = .llama
        coloredMenuBar = false
        tokensOnlyWhileGenerating = true
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        guard persists else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: "settings.\(key)")
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: "settings.\(key)") else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

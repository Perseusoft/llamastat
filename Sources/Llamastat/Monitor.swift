import Foundation
import Observation

/// One point of the history charts.
struct Sample: Identifiable, Sendable {
    var id: Date { time }
    var time: Date
    var generationRate: Double
    var promptRate: Double
    var gpu: Double
    var memory: Double
}

/// Live view of a loaded model, merged with its process stats.
struct ActiveModel: Identifiable, Sendable {
    var id: String { info.id }
    var info: ModelInfo
    var process: ProcessSample?
    var cpu: Double?
    var generationRate: Double = 0
    var promptRate: Double = 0
    var stats: ModelStats { info.stats ?? ModelStats() }
    var isBusy: Bool { stats.requestsProcessing > 0 || stats.slotsBusy > 0 }
}

@MainActor
@Observable
final class Monitor {
    static let historyLength = 120

    private(set) var backends: [BackendSnapshot] = []
    private(set) var active: [ActiveModel] = []
    private(set) var memory = SystemStats.memory()
    private(set) var gpu: GPUSnapshot?
    private(set) var history: [Sample] = []
    private(set) var sessionTokens: Double = 0
    var lastError: String?
    var pending: Set<String> = []

    let sources: [any ModelBackend] = [LlamaCppBackend(), OllamaBackend()]
    let routerLabel = "com.local.llama-router"

    private var previous: [String: (time: Date, predicted: Double, prompt: Double, cpu: UInt64)] = [:]
    private var task: Task<Void, Never>?

    var allModels: [ModelInfo] { backends.flatMap(\.models) }
    var onlineBackends: [BackendSnapshot] { backends.filter(\.online) }
    var generationRate: Double { active.reduce(0) { $0 + $1.generationRate } }
    var isGenerating: Bool { active.contains(where: \.isBusy) }
    /// Today's footgun: two backends each holding a model in unified memory.
    var multipleBackendsLoaded: Bool { Set(active.map(\.info.backend)).count > 1 }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func tick() async {
        let snapshots = await withTaskGroup(of: (Int, BackendSnapshot).self) { group in
            for (i, source) in sources.enumerated() {
                group.addTask { (i, await source.snapshot()) }
            }
            var result = [BackendSnapshot?](repeating: nil, count: sources.count)
            for await (i, snapshot) in group { result[i] = snapshot }
            return result.compactMap { $0 }
        }
        let now = Date()
        backends = snapshots
        memory = SystemStats.memory()
        gpu = SystemStats.gpu()

        var nextPrevious: [String: (time: Date, predicted: Double, prompt: Double, cpu: UInt64)] = [:]
        active = snapshots.flatMap(\.models).filter { $0.state == .loaded }.map { info in
            var model = ActiveModel(info: info)
            model.process = info.processMatch.flatMap(ProcessScanner.find)
            let stats = model.stats
            let cpuNanos = model.process?.cpuNanos ?? 0
            if let last = previous[info.id] {
                let dt = now.timeIntervalSince(last.time)
                if dt > 0 {
                    // Counters reset when a model reloads; ignore negative deltas.
                    let generated = max(0, stats.generatedTokens - last.predicted)
                    model.generationRate = generated / dt
                    model.promptRate = max(0, stats.promptTokensTotal - last.prompt) / dt
                    sessionTokens += generated
                    if cpuNanos >= last.cpu {
                        model.cpu = Double(cpuNanos - last.cpu) / (dt * 1e9)
                    }
                }
            }
            nextPrevious[info.id] = (now, stats.generatedTokens, stats.promptTokensTotal, cpuNanos)
            return model
        }
        previous = nextPrevious

        history.append(Sample(
            time: now,
            generationRate: generationRate,
            promptRate: active.reduce(0) { $0 + $1.promptRate },
            gpu: gpu?.utilization ?? 0,
            memory: memory.usedFraction
        ))
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    func toggle(_ model: ModelInfo) {
        guard let source = sources.first(where: { $0.kind == model.backend }) else { return }
        pending.insert(model.id)
        Task {
            do {
                if model.state == .unloaded {
                    try await source.load(model: model.name)
                } else {
                    try await source.unload(model: model.name)
                }
                lastError = nil
            } catch {
                lastError = "\(model.name): \(error.localizedDescription)"
            }
            pending.remove(model.id)
            await tick()
        }
    }

    func restartRouter() {
        run("/bin/launchctl", ["kickstart", "-k", "gui/\(getuid())/\(routerLabel)"])
    }

    private func run(_ path: String, _ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try? process.run()
    }
}

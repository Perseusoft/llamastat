import Foundation

/// llama-server in router mode (`--models-preset`). Per-model endpoints are reached
/// through the router with `?model=<id>`; `/metrics` needs `metrics = 1` in the preset.
final class LlamaCppBackend: ModelBackend {
    let kind = BackendKind.llamaCpp
    let baseURL: URL

    init(baseURL: URL = URL(string: "http://127.0.0.1:8080")!) {
        self.baseURL = baseURL
    }

    func snapshot() async -> BackendSnapshot {
        guard let data = try? await HTTP.get(baseURL.appending(path: "v1/models")),
              let list = try? JSONDecoder().decode(ModelList.self, from: data)
        else { return BackendSnapshot(kind: kind, online: false) }

        var models: [ModelInfo] = []
        for entry in list.data {
            let state = ModelState(rawValue: entry.status?.value ?? "") ?? .unloaded
            let args = entry.status?.args ?? []
            var info = ModelInfo(
                backend: kind,
                name: entry.id,
                state: state,
                sizeBytes: Self.argument("--model", in: args).flatMap(Self.fileSize),
                processMatch: ProcessMatch(executableName: "llama-server", argumentContains: ["--alias", entry.id])
            )
            if state == .loaded {
                info.stats = await stats(for: entry.id)
                if info.stats?.contextSize == nil {
                    info.stats?.contextSize = Self.argument("--ctx-size", in: args).flatMap { Int($0) }
                }
            }
            models.append(info)
        }
        return BackendSnapshot(kind: kind, online: true, models: models)
    }

    func load(model: String) async throws {
        _ = try await HTTP.post(baseURL.appending(path: "models/load"), json: ["model": model])
    }

    func unload(model: String) async throws {
        _ = try await HTTP.post(baseURL.appending(path: "models/unload"), json: ["model": model])
    }

    private func stats(for model: String) async -> ModelStats {
        var stats = ModelStats()
        // The router autoloads a model on any request naming it; without this, polling
        // stats right after an eject loads the model straight back.
        let query = [URLQueryItem(name: "model", value: model), URLQueryItem(name: "autoload", value: "false")]

        if let data = try? await HTTP.get(baseURL.appending(path: "metrics").appending(queryItems: query)) {
            let metrics = Prometheus.parse(String(decoding: data, as: UTF8.self))
            stats.promptTokensTotal = metrics["llamacpp:prompt_tokens_total"] ?? 0
            stats.predictedTokensTotal = metrics["llamacpp:tokens_predicted_total"] ?? 0
            // The *_tokens_seconds gauges reset on every scrape, so average the cumulative counters instead.
            stats.promptTokensPerSecond = Self.ratio(stats.promptTokensTotal, metrics["llamacpp:prompt_seconds_total"])
            stats.predictedTokensPerSecond = Self.ratio(stats.predictedTokensTotal, metrics["llamacpp:tokens_predicted_seconds_total"])
            stats.requestsProcessing = Int(metrics["llamacpp:requests_processing"] ?? 0)
            stats.requestsDeferred = Int(metrics["llamacpp:requests_deferred"] ?? 0)
        }

        if let data = try? await HTTP.get(baseURL.appending(path: "slots").appending(queryItems: query)),
           let slots = try? JSONDecoder().decode([Slot].self, from: data) {
            stats.slotsTotal = slots.count
            stats.slotsBusy = slots.filter(\.is_processing).count
            stats.contextSize = slots.first?.n_ctx
            // Busy slot first, otherwise the one that served the latest task.
            let current = slots.first(where: \.is_processing)
                ?? slots.filter { $0.id_task != nil }.max { ($0.id_task ?? 0) < ($1.id_task ?? 0) }
            // n_prompt_tokens grows as the slot decodes, so it already is the context in use.
            stats.contextUsed = current?.n_prompt_tokens
            // /metrics only counts a request once it finishes; this is the live part.
            stats.inFlightTokens = slots.filter(\.is_processing)
                .reduce(0) { $0 + Double($1.next_token?.first?.n_decoded ?? 0) }
        }
        return stats
    }

    private static func ratio(_ tokens: Double, _ seconds: Double?) -> Double? {
        guard let seconds, seconds > 0 else { return nil }
        return tokens / seconds
    }

    private static func argument(_ flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    private static func fileSize(_ path: String) -> UInt64? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.uint64Value
    }

    private struct ModelList: Decodable {
        struct Entry: Decodable {
            struct Status: Decodable {
                var value: String
                var args: [String]?
            }
            var id: String
            var status: Status?
        }
        var data: [Entry]
    }

    private struct Slot: Decodable {
        struct NextToken: Decodable { var n_decoded: Int? }
        var id: Int
        var n_ctx: Int?
        var is_processing: Bool
        var id_task: Int?
        var n_prompt_tokens: Int?
        var next_token: [NextToken]?
    }
}

enum Prometheus {
    /// Parses `name value` lines; labels are dropped (llama.cpp doesn't use them).
    static func parse(_ text: String) -> [String: Double] {
        var result: [String: Double] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: " ")
            guard parts.count >= 2, let value = Double(parts[1]) else { continue }
            let name = parts[0].split(separator: "{").first.map(String.init) ?? String(parts[0])
            result[name] = value
        }
        return result
    }
}

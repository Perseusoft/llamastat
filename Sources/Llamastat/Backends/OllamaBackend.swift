import Foundation

/// Ollama's native API. It doesn't expose live token counters, so stats are limited
/// to what `/api/ps` reports (VRAM, context length, keep-alive expiry).
final class OllamaBackend: ModelBackend {
    let kind = BackendKind.ollama
    let baseURL: URL

    init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.baseURL = baseURL
    }

    func snapshot() async -> BackendSnapshot {
        guard let tagsData = try? await HTTP.get(baseURL.appending(path: "api/tags")),
              let tags = try? JSONDecoder().decode(Tags.self, from: tagsData)
        else { return BackendSnapshot(kind: kind, online: false) }

        var running: [String: Running.Model] = [:]
        if let psData = try? await HTTP.get(baseURL.appending(path: "api/ps")),
           let ps = try? JSONDecoder.ollama.decode(Running.self, from: psData) {
            for model in ps.models { running[model.name] = model }
        }

        let models = tags.models.map { tag in
            let live = running[tag.name]
            var info = ModelInfo(
                backend: kind,
                name: tag.name,
                state: live == nil ? .unloaded : .loaded,
                sizeBytes: tag.size,
                // Runners get the blob path, not the model name; good enough with one model loaded.
                processMatch: live.map { _ in ProcessMatch(executableName: "llama-server", argumentContains: [".ollama/models/blobs"]) }
            )
            if let live {
                info.stats = ModelStats(contextSize: live.context_length, vramBytes: live.size_vram, expiresAt: live.expires_at)
            }
            return info
        }
        return BackendSnapshot(kind: kind, online: true, models: models)
    }

    func load(model: String) async throws {
        _ = try await HTTP.post(baseURL.appending(path: "api/generate"), json: ["model": model, "keep_alive": "15m"])
    }

    func unload(model: String) async throws {
        _ = try await HTTP.post(baseURL.appending(path: "api/generate"), json: ["model": model, "keep_alive": 0])
    }

    private struct Tags: Decodable {
        struct Model: Decodable {
            var name: String
            var size: UInt64?
        }
        var models: [Model]
    }

    private struct Running: Decodable {
        struct Model: Decodable {
            var name: String
            var digest: String
            var size_vram: UInt64?
            var context_length: Int?
            var expires_at: Date?
        }
        var models: [Model]
    }
}

private extension JSONDecoder {
    static let ollama: JSONDecoder = {
        let decoder = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            // Ollama sends nanosecond precision; ISO8601DateFormatter only takes milliseconds.
            let trimmed = string.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
            if let date = withFraction.date(from: trimmed) ?? plain.date(from: trimmed) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: string))
        }
        return decoder
    }()
}

import Foundation

/// A local inference server (llama.cpp router, Ollama, ...).
protocol ModelBackend: AnyObject, Sendable {
    var kind: BackendKind { get }
    var baseURL: URL { get }
    func snapshot() async -> BackendSnapshot
    func load(model: String) async throws
    func unload(model: String) async throws
}

enum BackendKind: String, Sendable {
    case llamaCpp = "llama.cpp"
    case ollama = "Ollama"
}

struct BackendSnapshot: Sendable {
    var kind: BackendKind
    var online: Bool
    var models: [ModelInfo] = []
}

enum ModelState: String, Sendable {
    case loaded, loading, unloaded
}

struct ModelInfo: Identifiable, Sendable {
    var id: String { "\(backend.rawValue)/\(name)" }
    var backend: BackendKind
    var name: String
    var state: ModelState
    /// Bytes on disk (Ollama reports it; llama.cpp we read from the gguf path).
    var sizeBytes: UInt64?
    /// Matches the server process so we can read its RAM/CPU.
    var processMatch: ProcessMatch?
    var stats: ModelStats?
}

/// How to find the OS process serving a model.
struct ProcessMatch: Sendable {
    var executableName: String
    var argumentContains: [String]
}

/// Live counters for a loaded model. Totals are cumulative since the model loaded.
struct ModelStats: Sendable {
    var promptTokensTotal: Double = 0
    var predictedTokensTotal: Double = 0
    /// Tokens decoded so far by requests still running (not yet in predictedTokensTotal).
    var inFlightTokens: Double = 0
    var generatedTokens: Double { predictedTokensTotal + inFlightTokens }
    var promptTokensPerSecond: Double?
    var predictedTokensPerSecond: Double?
    var requestsProcessing: Int = 0
    var requestsDeferred: Int = 0
    var contextSize: Int?
    var contextUsed: Int?
    var slotsTotal: Int = 0
    var slotsBusy: Int = 0
    var vramBytes: UInt64?
    var expiresAt: Date?
}

enum BackendError: LocalizedError {
    case http(Int, String)
    var errorDescription: String? {
        switch self {
        case let .http(code, body): "HTTP \(code): \(body)"
        }
    }
}

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        return URLSession(configuration: config)
    }()

    static func get(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try check(response, data)
        return data
    }

    static func post(_ url: URL, json: [String: Any], timeout: TimeInterval = 180) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (data, response) = try await session.data(for: request)
        try check(response, data)
        return data
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw BackendError.http(http.statusCode, String(decoding: data.prefix(300), as: UTF8.self))
        }
    }
}

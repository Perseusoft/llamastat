import Charts
import SwiftUI

struct PopoverView: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            rings
            warnings
            SectionHeader(title: "Historial")
            HistoryChart(history: monitor.history)
            ForEach(monitor.active) { model in
                SectionHeader(title: Format.shortName(model.info.name))
                ModelDetails(model: model)
            }
            SectionHeader(title: "Memoria")
            memoryDetails
            SectionHeader(title: "Modelos")
            ModelList()
            footer
        }
        .padding(14)
        .frame(width: 300)
    }

    private var header: some View {
        HStack {
            Text("Llamastat").font(.headline)
            Spacer()
            ForEach(monitor.backends, id: \.kind) { backend in
                HStack(spacing: 4) {
                    Circle().fill(backend.online ? Color.green : Palette.track).frame(width: 6, height: 6)
                    Text(backend.kind.rawValue).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.bottom, 10)
    }

    private var rings: some View {
        let peak = max(monitor.history.map(\.generationRate).max() ?? 0, 1)
        return HStack(alignment: .center) {
            Ring(fraction: monitor.memory.usedFraction, color: monitor.memory.usedFraction > 0.85 ? Palette.warning : Palette.memory,
                 label: Format.percent(monitor.memory.usedFraction), caption: "RAM", size: 58)
            Spacer()
            Ring(fraction: monitor.generationRate / peak, color: Palette.generation,
                 label: monitor.generationRate > 0 ? String(format: "%.0f", monitor.generationRate) : "0",
                 caption: "tokens/s", size: 84, lineWidth: 8)
            Spacer()
            Ring(fraction: monitor.gpu?.utilization ?? 0, color: Palette.gpu,
                 label: Format.percent(monitor.gpu?.utilization), caption: "GPU", size: 58)
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder private var warnings: some View {
        if monitor.multipleBackendsLoaded {
            Warning(text: "Hay modelos cargados en más de un backend. Ojo con la RAM.")
        }
        if monitor.memory.swapTotal > 0, Double(monitor.memory.swapUsed) / Double(monitor.memory.swapTotal) > 0.8 {
            Warning(text: "Swap casi lleno (\(Format.gigabytes(monitor.memory.swapUsed))). El sistema va a ir lento.")
        }
        if let error = monitor.lastError {
            Warning(text: error)
        }
    }

    private var memoryDetails: some View {
        let memory = monitor.memory
        return VStack(spacing: 5) {
            DetailRow(color: Palette.memory, label: "En uso", value: "\(Format.gigabytes(memory.used)) / \(Format.gigabytes(memory.total))")
            UsageBar(fraction: memory.usedFraction, color: Palette.memory)
            DetailRow(color: nil, label: "Wired", value: Format.gigabytes(memory.wired))
            DetailRow(color: nil, label: "Comprimida", value: Format.gigabytes(memory.compressed))
            DetailRow(color: nil, label: "Swap", value: Format.gigabytes(memory.swapUsed))
            if let gpuMemory = monitor.gpu?.memoryInUse {
                DetailRow(color: Palette.gpu, label: "GPU", value: Format.gigabytes(gpuMemory))
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Reiniciar router") { monitor.restartRouter() }
            Spacer()
            Button("Salir") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.borderless)
        .font(.caption)
        .padding(.top, 12)
    }
}

private struct Warning: View {
    var text: String
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(Palette.warning)
            .padding(.top, 8)
    }
}

struct HistoryChart: View {
    var history: [Sample]

    var body: some View {
        VStack(spacing: 4) {
            Chart(history) { sample in
                AreaMark(x: .value("t", sample.time), y: .value("tok/s", sample.generationRate))
                    .foregroundStyle(Palette.generation.opacity(0.35).gradient)
                    .interpolationMethod(.monotone)
                LineMark(x: .value("t", sample.time), y: .value("tok/s", sample.generationRate))
                    .foregroundStyle(Palette.generation)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
            .chartYScale(domain: 0...max(history.map(\.generationRate).max() ?? 0, 10))
            .frame(height: 64)

            Chart(history) { sample in
                BarMark(x: .value("t", sample.time), y: .value("GPU", sample.gpu * 100), width: .fixed(1.5))
                    .foregroundStyle(Palette.gpu.opacity(0.8))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...100)
            .frame(height: 24)

            HStack {
                Legend(color: Palette.generation, text: "tokens/s")
                Legend(color: Palette.gpu, text: "GPU")
                Spacer()
                Text("últimos \(Monitor.historyLength) s").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Palette.track.opacity(0.4)))
    }
}

private struct Legend: View {
    var color: Color
    var text: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct ModelDetails: View {
    var model: ActiveModel

    var body: some View {
        let stats = model.stats
        VStack(spacing: 5) {
            DetailRow(color: model.isBusy ? .green : Palette.track, label: "Estado",
                      value: model.isBusy ? "generando" : "en espera")
            DetailRow(color: nil, label: "Backend", value: model.info.backend.rawValue)
            if let size = stats.contextSize {
                let used = stats.contextUsed ?? 0
                DetailRow(color: Palette.prompt, label: "Contexto",
                          value: "\(Format.count(Double(used))) / \(Format.context(size))")
                UsageBar(fraction: Double(used) / Double(max(size, 1)), color: Palette.prompt)
            }
            if stats.slotsTotal > 0 {
                DetailRow(color: nil, label: "Slots ocupados", value: "\(stats.slotsBusy) / \(stats.slotsTotal)")
            }
            if model.info.backend == .llamaCpp {
                DetailRow(color: Palette.generation, label: "Generación (media)", value: Format.rate(stats.predictedTokensPerSecond))
                DetailRow(color: Palette.prompt, label: "Prompt (media)", value: Format.rate(stats.promptTokensPerSecond))
                DetailRow(color: nil, label: "Tokens generados", value: Format.count(stats.generatedTokens))
                DetailRow(color: nil, label: "Tokens de prompt", value: Format.count(stats.promptTokensTotal))
            }
            if let vram = stats.vramBytes {
                DetailRow(color: Palette.gpu, label: "VRAM", value: Format.bytes(vram))
            }
            if let process = model.process {
                DetailRow(color: Palette.memory, label: "RAM del proceso", value: Format.gigabytes(max(process.residentBytes, process.footprintBytes)))
            }
            if let cpu = model.cpu {
                DetailRow(color: nil, label: "CPU", value: Format.percent(cpu))
            }
            if let expires = stats.expiresAt {
                DetailRow(color: nil, label: "Se descarga", value: expires.formatted(.relative(presentation: .named)))
            }
        }
    }
}

struct ModelList: View {
    @Environment(Monitor.self) private var monitor

    var body: some View {
        VStack(spacing: 6) {
            if monitor.allModels.isEmpty {
                Text(monitor.onlineBackends.isEmpty ? "Ningún backend responde" : "Sin modelos")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(monitor.allModels) { model in
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.state == .loaded ? Color.green : model.state == .loading ? Color.yellow : Palette.track)
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.name).font(.system(size: 12)).lineLimit(1)
                        Text("\(model.backend.rawValue) · \(Format.bytes(model.sizeBytes))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if monitor.pending.contains(model.id) || model.state == .loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(model.state == .unloaded ? "Cargar" : "Descargar") { monitor.toggle(model) }
                            .controlSize(.small)
                    }
                }
            }
        }
    }
}

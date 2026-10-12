import SwiftUI

enum Palette {
    static let generation = Color.blue
    static let prompt = Color.teal
    static let gpu = Color.orange
    static let memory = Color.purple
    static let warning = Color.red
    static let track = Color.secondary.opacity(0.2)
}

/// Ring gauge like Stats' header dials.
struct Ring: View {
    var fraction: Double
    var color: Color
    var label: String
    var caption: String
    var size: CGFloat = 64
    var lineWidth: CGFloat = 6

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Palette.track, lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: max(0.001, min(fraction, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: fraction)
                Text(label)
                    .font(.system(size: size * 0.2, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .padding(lineWidth + 2)
            }
            .frame(width: size, height: size)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Centered small-caps divider: ─── TITLE ───
struct SectionHeader: View {
    var title: String
    var body: some View {
        HStack(spacing: 8) {
            line
            Text(title.uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(1)
                .foregroundStyle(.secondary)
                .fixedSize()
            line
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
    private var line: some View { Rectangle().fill(Palette.track).frame(height: 1) }
}

struct DetailRow: View {
    var color: Color?
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 6) {
            if let color {
                Circle().fill(color).frame(width: 8, height: 8)
            }
            Text(label + ":")
            Spacer()
            Text(value).monospacedDigit().fontWeight(.medium)
        }
        .font(.system(size: 12))
    }
}

/// Thin horizontal usage bar (context window, memory).
struct UsageBar: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(color).frame(width: geo.size.width * max(0, min(fraction, 1)))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

enum Format {
    static func bytes(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }

    static func gigabytes(_ value: UInt64) -> String {
        String(format: "%.1f GB", Double(value) / 1_073_741_824)
    }

    static func rate(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return value >= 100 ? String(format: "%.0f t/s", value) : String(format: "%.1f t/s", value)
    }

    static func percent(_ fraction: Double?) -> String {
        guard let fraction else { return "—" }
        return String(format: "%.0f%%", fraction * 100)
    }

    static func count(_ value: Double) -> String {
        switch value {
        case 1_000_000...: String(format: "%.1fM", value / 1_000_000)
        case 10_000...: String(format: "%.0fk", value / 1_000)
        case 1_000...: String(format: "%.1fk", value / 1_000)
        default: String(format: "%.0f", value)
        }
    }

    /// Context sizes are powers of two: 32768 reads as "32k", not "33k".
    static func context(_ tokens: Int) -> String {
        tokens >= 1024 && tokens % 1024 == 0 ? "\(tokens / 1024)k" : count(Double(tokens))
    }

    static func shortName(_ model: String) -> String {
        model.split(separator: ":").first.map(String.init) ?? model
    }
}

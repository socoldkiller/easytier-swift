import EasyTierCore
import SwiftUI

struct TrafficView: View {
    @Environment(EasyTierAppStore.self) private var store

    private var instance: NetworkInstance? { store.selectedRunningInstance }
    private var samples: [TrafficSample] { store.selectedTrafficSamples }
    private var latest: TrafficSample? { samples.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                StatusMetric(title: "Network", value: instance?.name ?? store.selectedConfig?.network_name ?? "-", systemImage: "network")
                StatusMetric(title: "Upload", value: ByteFormatter.formatRate(latest?.txBytesPerSecond ?? 0), systemImage: "arrow.up")
                StatusMetric(title: "Download", value: ByteFormatter.formatRate(latest?.rxBytesPerSecond ?? 0), systemImage: "arrow.down")
                StatusMetric(title: "Samples", value: "\(samples.count)", systemImage: "waveform.path.ecg")
                Spacer(minLength: 0)
            }

            if instance == nil {
                ContentUnavailableView(
                    "No Traffic Data",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Run the selected network to start collecting traffic samples.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 18) {
                        LegendItem(color: .green, title: "Upload")
                        LegendItem(color: .blue, title: "Download")
                        Spacer()
                        Text("Last 120 seconds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    TrafficLineChart(samples: samples)
                        .frame(minHeight: 280)
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding()
    }
}

private struct StatusMetric: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct LegendItem: View {
    var color: Color
    var title: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TrafficLineChart: View {
    var samples: [TrafficSample]

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let plotRect = CGRect(
                    x: 44,
                    y: 12,
                    width: max(1, size.width - 54),
                    height: max(1, size.height - 38)
                )
                let txValues = samples.map(\.txBytesPerSecond)
                let rxValues = samples.map(\.rxBytesPerSecond)
                let maxValue = max((txValues + rxValues).max() ?? 0, 1)

                drawGrid(in: plotRect, context: &context, maxValue: maxValue)
                drawLine(values: txValues, in: plotRect, maxValue: maxValue, color: .green, context: &context)
                drawLine(values: rxValues, in: plotRect, maxValue: maxValue, color: .blue, context: &context)
            }
            .overlay(alignment: .bottomLeading) {
                HStack {
                    Text(samples.first?.timestamp.formatted(date: .omitted, time: .standard) ?? "--:--:--")
                    Spacer()
                    Text(samples.last?.timestamp.formatted(date: .omitted, time: .standard) ?? "--:--:--")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 44)
                .padding(.trailing, 10)
            }
            .overlay {
                if samples.isEmpty {
                    ContentUnavailableView("Waiting For Samples", systemImage: "waveform.path.ecg")
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        }
    }

    private func drawGrid(in rect: CGRect, context: inout GraphicsContext, maxValue: Double) {
        var grid = Path()
        for index in 0...4 {
            let y = rect.minY + rect.height * CGFloat(index) / 4
            grid.move(to: CGPoint(x: rect.minX, y: y))
            grid.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        context.stroke(grid, with: .color(.secondary.opacity(0.22)), lineWidth: 1)

        for index in 0...2 {
            let value = maxValue * Double(2 - index) / 2
            let y = rect.minY + rect.height * CGFloat(index) / 2
            context.draw(
                Text(ByteFormatter.formatRate(value))
                    .font(.caption2)
                    .foregroundStyle(.secondary),
                at: CGPoint(x: rect.minX - 8, y: y),
                anchor: .trailing
            )
        }
    }

    private func drawLine(values: [Double], in rect: CGRect, maxValue: Double, color: Color, context: inout GraphicsContext) {
        guard values.count > 1 else { return }

        var path = Path()
        for (index, value) in values.enumerated() {
            let x = rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = rect.maxY - rect.height * CGFloat(min(max(value, 0), maxValue) / maxValue)
            let point = CGPoint(x: x, y: y)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }

        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
    }
}

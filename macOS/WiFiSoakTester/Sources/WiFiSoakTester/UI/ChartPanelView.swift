import SwiftUI
import Charts

struct ChartPanelView: View {
    let samples: [SessionSample]
    let useMbps: Bool
    let showTotalSeries: Bool
    let theme: ThemePalette
    let appearanceMode: AppearanceMode

    private var isClassic: Bool {
        appearanceMode == .classic
    }

    private var speedFactor: Double {
        useMbps ? 8 / 1_000_000 : 1 / 1_048_576
    }

    private var speedLabel: String {
        useMbps ? "Speed (Mbps)" : "Speed (MB/s)"
    }

    private var maxSpeed: Double {
        max(samples.map { $0.speedBps * speedFactor }.max() ?? 0, 1)
    }

    private var maxTotalBytes: Double {
        max(Double(samples.last?.totalBytes ?? 0), 1)
    }

    var body: some View {
        Chart {
            ForEach(samples) { sample in
                if !isClassic {
                    AreaMark(
                        x: .value("Time", sample.timestamp),
                        y: .value(speedLabel, sample.speedBps * speedFactor)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                theme.cyan.opacity(0.30),
                                theme.cyan.opacity(0.05),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value(speedLabel, sample.speedBps * speedFactor)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [theme.cyan, theme.sky],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineStyle(
                    StrokeStyle(
                        lineWidth: isClassic ? 1.8 : 2.2,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .interpolationMethod(isClassic ? .linear : .catmullRom)
            }

            if showTotalSeries {
                ForEach(samples) { sample in
                    let normalizedTotal = (Double(sample.totalBytes) / maxTotalBytes) * maxSpeed
                    LineMark(
                        x: .value("Time", sample.timestamp),
                        y: .value("Total (normalized)", normalizedTotal)
                    )
                    .foregroundStyle(theme.amber)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [4, 3]))
                    .interpolationMethod(isClassic ? .linear : .catmullRom)
                }
            }
        }
        .chartLegend(position: .top, alignment: .leading)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8))
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartPlotStyle { plot in
            plot
                .background(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(isClassic ? 0.10 : 0.18),
                            Color.black.opacity(isClassic ? 0.03 : 0.06)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
        }
        .frame(minHeight: 300)
    }
}

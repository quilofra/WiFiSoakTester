import SwiftUI

struct MenuBarStatusView: View {
    @ObservedObject var viewModel: SoakTestViewModel
    @Environment(\.openWindow) private var openWindow

    private var theme: ThemePalette {
        viewModel.appearanceMode == .classic ? VisualTheme.monochrome : viewModel.themePalette
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("WiFi Soak Tester", systemImage: "wifi.router.fill")
                    .font(.headline)
                Spacer()
                statusBadge(
                    text: viewModel.menuBarStateText,
                    color: viewModel.isRunning ? theme.mint : .secondary
                )
            }

            metricRow(
                icon: "speedometer",
                text: viewModel.useMbps ? ValueFormatting.speedMbps(viewModel.currentSpeedBps) : ValueFormatting.speedMBps(viewModel.currentSpeedBps),
                tint: theme.cyan
            )
            metricRow(icon: "internaldrive", text: ValueFormatting.bytes(viewModel.totalBytes), tint: theme.sky)
            metricRow(
                icon: "exclamationmark.arrow.triangle.2.circlepath",
                text: "Errors: \(viewModel.errors)  Retries: \(viewModel.retries)",
                tint: theme.amber
            )

            if viewModel.lastErrorMessage != "-" {
                Text(viewModel.lastErrorMessage)
                    .font(.caption2)
                    .foregroundStyle(theme.coral)
                    .lineLimit(2)
            }

            if let startValidationError = viewModel.startValidationError, !viewModel.isRunning {
                Text(startValidationError)
                    .font(.caption2)
                    .foregroundStyle(theme.amber)
                    .lineLimit(2)
            }

            Divider()

            HStack {
                Button(viewModel.isRunning ? "Stop" : "Start") {
                    if viewModel.isRunning {
                        viewModel.stop()
                    } else {
                        viewModel.start()
                    }
                }
                .disabled(!viewModel.isRunning && !viewModel.canStart)

                Button("Open Window") {
                    openWindow(id: "main")
                }
            }
        }
        .padding(12)
        .frame(width: 280)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    theme.sky.opacity(0.10),
                    theme.mint.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func metricRow(icon: String, text: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private func statusBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(color.opacity(0.45), lineWidth: 1)
            )
    }
}

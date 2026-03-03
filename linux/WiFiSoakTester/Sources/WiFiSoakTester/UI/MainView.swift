import SwiftUI

private enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case endpoints = "Endpoints"
    case configuration = "Configuration"
    case export = "Export"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "chart.line.uptrend.xyaxis"
        case .endpoints: return "link"
        case .configuration: return "slider.horizontal.3"
        case .export: return "square.and.arrow.up"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard: return "Live metrics and chart"
        case .endpoints: return "Allowed static test URLs"
        case .configuration: return "Engine and sink settings"
        case .export: return "Manual and automatic reports"
        }
    }

    func accent(using theme: ThemePalette) -> Color {
        switch self {
        case .dashboard: return theme.cyan
        case .endpoints: return theme.mint
        case .configuration: return theme.indigo
        case .export: return theme.amber
        }
    }
}

struct MainView: View {
    @ObservedObject var viewModel: SoakTestViewModel

    @SceneStorage("selectedSection") private var selectedSectionRaw: String = SidebarSection.dashboard.rawValue
    @State private var selectedEndpointID: UUID?

    private let statsColumns = [
        GridItem(.adaptive(minimum: 180), spacing: 12)
    ]

    private var selectedSection: SidebarSection {
        get { SidebarSection(rawValue: selectedSectionRaw) ?? .dashboard }
        nonmutating set { selectedSectionRaw = newValue.rawValue }
    }

    private var selectedSectionOptionalBinding: Binding<SidebarSection?> {
        Binding<SidebarSection?>(
            get: { selectedSection },
            set: { newValue in
                guard let newValue else { return }
                selectedSection = newValue
            }
        )
    }

    private var theme: ThemePalette {
        isClassicAppearance ? VisualTheme.monochrome : viewModel.themePalette
    }

    private var isClassicAppearance: Bool {
        viewModel.appearanceMode == .classic
    }

    private var metricsOverview: [(title: String, value: String, accent: Color)] {
        [
            ("Current", speedText(viewModel.currentSpeedBps), theme.cyan),
            ("Moving Avg", speedText(viewModel.movingAverageBps), theme.sky),
            ("Global Avg", speedText(viewModel.globalAverageBps), theme.indigo),
            ("Total", ValueFormatting.bytes(viewModel.totalBytes), theme.mint),
            ("Elapsed", ValueFormatting.elapsed(viewModel.elapsedSeconds), theme.amber),
            ("Switches", "\(viewModel.switchCount)", theme.coral),
            ("Errors", "\(viewModel.errors)", theme.coral),
            ("Retries", "\(viewModel.retries)", theme.amber),
            ("p50 / p95", "\(speedText(viewModel.p50Bps)) / \(speedText(viewModel.p95Bps))", theme.sky),
            ("Below minRate", String(format: "%.2f%%", viewModel.belowThresholdPercent), theme.indigo),
            ("Samples", "\(viewModel.samples.count)", theme.mint)
        ]
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isRunning)
        .animation(.easeInOut(duration: 0.35), value: viewModel.themePreset)
        .animation(.easeInOut(duration: 0.30), value: viewModel.appearanceMode)
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel.userError != nil },
                set: { if !$0 { viewModel.userError = nil } }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(viewModel.userError ?? "")
            }
        )
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            sidebarStatusCard
                .padding(.horizontal, 8)
                .padding(.top, 8)

            List(selection: selectedSectionOptionalBinding) {
                ForEach(SidebarSection.allCases) { section in
                    let isSelected = selectedSection == section
                    let sectionAccent = section.accent(using: theme)
                    sidebarRow(
                        section: section,
                        isSelected: isSelected,
                        sectionAccent: sectionAccent
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSection = section
                    }
                    .tag(section)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(isClassicAppearance ? 0.96 : 0.90),
                    theme.sky.opacity(isClassicAppearance ? 0.06 : 0.12),
                    theme.mint.opacity(isClassicAppearance ? 0.04 : 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle("WiFi Soak Tester")
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                let stateColor: Color = viewModel.isRunning
                    ? (isClassicAppearance ? .secondary : .green)
                    : .secondary
                Text(viewModel.menuBarStateText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stateColor)
                Text(viewModel.useMbps ? ValueFormatting.speedMbps(viewModel.currentSpeedBps) : ValueFormatting.speedMBps(viewModel.currentSpeedBps))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }

    private var sidebarStatusCard: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(viewModel.isRunning ? theme.mint : theme.indigo.opacity(0.55))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.menuBarStateText)
                    .font(.caption.weight(.semibold))
                Text(viewModel.useMbps ? ValueFormatting.speedMbps(viewModel.currentSpeedBps) : ValueFormatting.speedMBps(viewModel.currentSpeedBps))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isClassicAppearance ? Color.white.opacity(0.06) : theme.cyan.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isClassicAppearance ? Color.white.opacity(0.12) : theme.cyan.opacity(0.35), lineWidth: 1)
        )
    }

    private var detail: some View {
        ZStack {
            SoakBackground(theme: theme, isClassic: isClassicAppearance)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleHeader

                    switch selectedSection {
                    case .dashboard:
                        dashboardSection
                    case .endpoints:
                        endpointSection
                    case .configuration:
                        configurationSection
                    case .export:
                        exportSection
                    }
                }
                .padding(18)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(viewModel.isRunning ? "Stop" : "Start") {
                    if viewModel.isRunning {
                        viewModel.stop()
                    } else {
                        viewModel.start()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isRunning && !viewModel.canStart)

                Button("Export CSV") {
                    viewModel.exportCSV()
                }
                .disabled(viewModel.samples.isEmpty)

                Button("Report HTML") {
                    viewModel.generateHTMLReport()
                }
                .disabled(viewModel.samples.isEmpty)
            }
        }
    }

    private var titleHeader: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Image(systemName: "wifi.router.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(theme.cyan)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(theme.cyan.opacity(0.18))
                            )

                        Text("Wi-Fi / ISP Soak Test")
                            .font(.system(size: 29, weight: .semibold, design: .rounded))
                    }
                    Text("Usa solo endpoints estáticos permitidos explícitamente para testing.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    statusPill(
                        text: "Preventing sleep: \(viewModel.preventingSleep ? "ON" : "OFF")",
                        color: viewModel.preventingSleep ? (isClassicAppearance ? .secondary : .mint) : .secondary
                    )
                    statusPill(
                        text: "Status: \(viewModel.statusMessage)",
                        color: viewModel.isRunning ? (isClassicAppearance ? .secondary : .green) : .secondary
                    )
                }
            }

            if let startValidationError = viewModel.startValidationError, !viewModel.isRunning {
                Divider().padding(.vertical, 2)
                Label(startValidationError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var dashboardSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassCard {
                LazyVGrid(columns: statsColumns, alignment: .leading, spacing: 10) {
                    ForEach(Array(metricsOverview.enumerated()), id: \.offset) { _, item in
                        StatCell(
                            title: item.title,
                            value: item.value,
                            accent: item.accent,
                            isClassic: isClassicAppearance
                        )
                    }
                }

                Divider().padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 8) {
                    infoStrip(
                        title: "Active worker(s)",
                        value: viewModel.activeURLText,
                        accent: theme.sky
                    )

                    infoStrip(
                        title: "Last engine event",
                        value: viewModel.lastEngineEvent,
                        accent: theme.mint
                    )

                    infoStrip(
                        title: "Last error",
                        value: viewModel.lastErrorMessage,
                        accent: theme.coral
                    )
                }

                if !viewModel.recentEvents.isEmpty {
                    Divider().padding(.vertical, 2)
                    Text("Recent events")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(viewModel.recentEvents.suffix(8).enumerated()), id: \.offset) { _, entry in
                                Text(entry)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Picker("Window", selection: $viewModel.chartWindow) {
                            ForEach(SoakTestViewModel.ChartWindow.allCases) { window in
                                Text(window.rawValue).tag(window)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 230)

                        Toggle("Total accumulated", isOn: $viewModel.showTotalSeries)
                        Toggle("Mbps", isOn: $viewModel.useMbps)
                        Spacer()
                    }

                    ChartPanelView(
                        samples: viewModel.chartSamples,
                        useMbps: viewModel.useMbps,
                        showTotalSeries: viewModel.showTotalSeries,
                        theme: theme,
                        appearanceMode: viewModel.appearanceMode
                    )
                }
            }
        }
    }

    private var endpointSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Allowed Test Endpoints")
                    .font(.title3.weight(.semibold))

                if hasPlaceholderEndpoints {
                    Text("Current list uses placeholder URLs from example.com. Replace them with explicitly allowed testing endpoints.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let startValidationError = viewModel.startValidationError {
                    Text(startValidationError)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Table(viewModel.endpointRows, selection: $selectedEndpointID) {
                    TableColumn("URL") { row in
                        TextField("https://...", text: endpointBinding(for: row.id))
                            .textFieldStyle(.roundedBorder)
                    }
                    .width(min: 450)

                    TableColumn("Action") { row in
                        Button {
                            viewModel.removeEndpoint(id: row.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                    .width(60)
                }
                .frame(minHeight: 300)

                HStack(spacing: 10) {
                    Button("Add") { viewModel.addEndpoint() }
                    Button("Import TXT") { viewModel.importURLList() }
                    Button("Export TXT") { viewModel.exportURLList() }
                    if let selectedEndpointID {
                        Button("Delete Selected") {
                            viewModel.removeEndpoint(id: selectedEndpointID)
                        }
                    }
                    Spacer()
                }
                .font(.callout)
            }
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Appearance")
                        .font(.title3.weight(.semibold))

                    HStack {
                        Text("Aspecto:")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Picker("Aspecto", selection: $viewModel.appearanceMode) {
                            ForEach(AppearanceMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .tint(theme.cyan)
                    }

                    if viewModel.appearanceMode == .enhanced {
                        HStack {
                            Text("Palette:")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Picker("Theme", selection: $viewModel.themePreset) {
                                ForEach(ThemePreset.allCases) { preset in
                                    Text(preset.rawValue).tag(preset)
                                }
                            }
                            .pickerStyle(.segmented)
                            .tint(theme.cyan)
                        }
                    }
                    Text(
                        viewModel.appearanceMode == .enhanced
                            ? "Modo actual colorido con gradientes y acentos."
                            : "Modo clasico glassy, similar a la apariencia anterior."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Duration and workers")
                        .font(.title3.weight(.semibold))

                    Picker("Duration", selection: $viewModel.durationPreset) {
                        ForEach(DurationPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.durationPreset == .custom {
                        HStack {
                            Text("Custom hours")
                            TextField("12", value: $viewModel.customDurationHours, format: .number.precision(.fractionLength(0...1)))
                                .frame(width: 120)
                        }
                    }

                    HStack {
                        Text("Concurrency")
                        Stepper(value: $viewModel.concurrency, in: 1...4) {
                            Text("\(viewModel.concurrency)")
                                .monospacedDigit()
                        }
                        .frame(width: 140)
                        Spacer()
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Rate behavior")
                        .font(.title3.weight(.semibold))

                    Toggle("Saturate at maximum", isOn: $viewModel.saturateMaximum)
                    Toggle("Stable mode", isOn: $viewModel.stableMode)

                    if viewModel.stableMode || !viewModel.saturateMaximum {
                        HStack {
                            Text("Max rate (Mbps)")
                            TextField("100", value: $viewModel.maxRateMbps, format: .number.precision(.fractionLength(0...2)))
                                .frame(width: 120)
                        }
                    }

                    HStack {
                        Text("Moving average window (s)")
                        Stepper(value: $viewModel.movingAverageWindowSeconds, in: 5...30) {
                            Text("\(viewModel.movingAverageWindowSeconds)")
                                .monospacedDigit()
                        }
                        .frame(width: 140)
                        Spacer()
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Timeout, retries and URL switching")
                        .font(.title3.weight(.semibold))

                    HStack {
                        Text("Timeout (s)")
                        TextField("15", value: $viewModel.timeoutSeconds, format: .number.precision(.fractionLength(0...2)))
                            .frame(width: 90)
                        Text("Max retries")
                        TextField("5", value: $viewModel.maxRetries, format: .number)
                            .frame(width: 70)
                    }

                    HStack {
                        Text("Backoff base (s)")
                        TextField("1.5", value: $viewModel.backoffSeconds, format: .number.precision(.fractionLength(0...2)))
                            .frame(width: 90)
                    }

                    HStack {
                        Text("minRate (MB/s)")
                        TextField("1", value: $viewModel.minRateMBps, format: .number.precision(.fractionLength(0...2)))
                            .frame(width: 90)
                        Text("switchAfter (s)")
                        TextField("20", value: $viewModel.switchAfterSeconds, format: .number.precision(.fractionLength(0...1)))
                            .frame(width: 90)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sink")
                        .font(.title3.weight(.semibold))

                    Picker("Sink mode", selection: $viewModel.sinkMode) {
                        ForEach(SinkMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    if viewModel.sinkMode == .ringBuffer {
                        HStack {
                            Text("Cache size (GiB)")
                            TextField("2", value: $viewModel.ringCacheGiB, format: .number.precision(.fractionLength(1)))
                                .frame(width: 90)
                        }

                        HStack {
                            Text("Segment size (MiB)")
                            TextField("64", value: $viewModel.ringSegmentMiB, format: .number)
                                .frame(width: 90)
                        }

                        HStack {
                            Text("Folder")
                            TextField("Choose folder", text: $viewModel.ringDirectoryPath)
                                .textFieldStyle(.roundedBorder)
                            Button("Browse") { viewModel.chooseRingDirectory() }
                        }
                    }
                }
            }
        }
    }

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Manual export")
                        .font(.title3.weight(.semibold))

                    Toggle("CSV: only last 24h", isOn: $viewModel.exportOnlyLast24h)

                    HStack {
                        Button("Export CSV") { viewModel.exportCSV() }
                            .disabled(viewModel.samples.isEmpty)
                        Button("Generate report.html") { viewModel.generateHTMLReport() }
                            .disabled(viewModel.samples.isEmpty)
                    }
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Auto-export with rotation")
                        .font(.title3.weight(.semibold))

                    Toggle("Enable auto-export", isOn: $viewModel.autoExportEnabled)

                    HStack {
                        Text("Interval (min)")
                        Stepper(value: $viewModel.autoExportIntervalMinutes, in: 1...60) {
                            Text("\(viewModel.autoExportIntervalMinutes)")
                                .monospacedDigit()
                        }
                        .frame(width: 140)
                    }

                    HStack {
                        Text("Max files")
                        TextField("48", value: $viewModel.autoExportMaxFiles, format: .number)
                            .frame(width: 90)
                        Text("Max MB")
                        TextField("200", value: $viewModel.autoExportMaxTotalMB, format: .number)
                            .frame(width: 90)
                    }

                    Toggle("Include report_current.html", isOn: $viewModel.autoExportIncludeHTML)

                    HStack {
                        Text("Folder")
                        TextField("Choose folder", text: $viewModel.autoExportDirectoryPath)
                            .textFieldStyle(.roundedBorder)
                        Button("Browse") { viewModel.chooseAutoExportDirectory() }
                    }

                    Text("Auto-export status: \(viewModel.autoExportStatus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Last error: \(viewModel.lastErrorMessage)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func endpointBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                viewModel.endpointRows.first(where: { $0.id == id })?.value ?? ""
            },
            set: { newValue in
                if let index = viewModel.endpointRows.firstIndex(where: { $0.id == id }) {
                    viewModel.endpointRows[index].value = newValue
                }
            }
        )
    }

    private var hasPlaceholderEndpoints: Bool {
        viewModel.endpointRows.contains { row in
            row.value.lowercased().contains("example.com")
        }
    }

    private func speedText(_ bps: Double) -> String {
        viewModel.useMbps ? ValueFormatting.speedMbps(bps) : ValueFormatting.speedMBps(bps)
    }

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(
                    LinearGradient(
                        colors: [color.opacity(0.55), Color.white.opacity(0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
            }
    }

    private func sidebarRow(section: SidebarSection, isSelected: Bool, sectionAccent: Color) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(sectionAccent.opacity(isSelected ? 0.26 : (isClassicAppearance ? 0.08 : 0.14)))
                    .frame(width: 26, height: 26)
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? sectionAccent : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(section.rawValue)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(section.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)

            if isSelected {
                Circle()
                    .fill(sectionAccent)
                    .frame(width: 8, height: 8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    isSelected
                        ? LinearGradient(
                            colors: [
                                sectionAccent.opacity(isClassicAppearance ? 0.18 : 0.26),
                                sectionAccent.opacity(isClassicAppearance ? 0.06 : 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [
                                Color.white.opacity(isClassicAppearance ? 0.02 : 0.04),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected
                        ? sectionAccent.opacity(isClassicAppearance ? 0.30 : 0.45)
                        : Color.white.opacity(isClassicAppearance ? 0.08 : 0.12),
                    lineWidth: 1
                )
        )
    }

    private func infoStrip(title: String, value: String, accent: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(title):")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .lineLimit(2)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(accent.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct GlassCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.white.opacity(0.03)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.34),
                                Color.white.opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: Color.black.opacity(0.07), radius: 14, x: 0, y: 9)
    }
}

private struct StatCell: View {
    let title: String
    let value: String
    let accent: Color
    let isClassic: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .rounded).monospacedDigit())
                .lineLimit(1)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(isClassic ? 0.12 : 0.21),
                            accent.opacity(isClassic ? 0.03 : 0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(isClassic ? 0.22 : 0.38), lineWidth: 1)
        )
    }
}

private struct SoakBackground: View {
    let theme: ThemePalette
    let isClassic: Bool

    var body: some View {
        let background = ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    theme.sky.opacity(isClassic ? 0.07 : 0.14),
                    theme.mint.opacity(isClassic ? 0.05 : 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if !isClassic {
                Circle()
                    .fill(theme.cyan.opacity(0.18))
                    .frame(width: 560, height: 560)
                    .blur(radius: 80)
                    .offset(x: -260, y: -210)

                Circle()
                    .fill(theme.amber.opacity(0.12))
                    .frame(width: 500, height: 500)
                    .blur(radius: 90)
                    .offset(x: 280, y: 250)

                Circle()
                    .fill(theme.indigo.opacity(0.12))
                    .frame(width: 420, height: 420)
                    .blur(radius: 85)
                    .offset(x: 180, y: -200)
            }
        }

        if isClassic {
            background
        } else {
            background.drawingGroup()
        }
    }
}

import SwiftUI

// MARK: - Build System Panel

/// Pannello per build, profiling e monitoraggio memoria.
struct BuildSystemPanel: View {
    @ObservedObject var store: BuildProgressStore
    let projectPath: String

    @State private var selectedTab: Tab = .build

    enum Tab: String, CaseIterable {
        case build = "Build"
        case profiling = "Profiling"
        case memory = "Memoria"
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            tabContent
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            Spacer()
            buildStateIndicator
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var buildStateIndicator: some View {
        switch store.buildState {
        case .idle:
            Label("Pronto", systemImage: "checkmark.circle")
                .foregroundColor(.secondary)
        case .building:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(store.currentStep)
                    .font(.caption)
                    .lineLimit(1)
            }
        case .succeeded:
            Label("Completato", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundColor(.red)
                .lineLimit(1)
        case .profiling:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Profiling...")
                    .font(.caption)
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .build:
            buildTab
        case .profiling:
            profilingTab
        case .memory:
            memoryTab
        }
    }

    // MARK: - Build Tab

    private var buildTab: some View {
        VStack(spacing: 0) {
            // Barra progresso
            if case .building = store.buildState {
                ProgressView(value: store.progress)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }

            // Actions
            HStack(spacing: 8) {
                Button("Build") { store.startBuild(projectPath: projectPath) }
                    .buttonStyle(.bordered)
                Button("Pulisci Log") { store.clearLogs() }
                    .buttonStyle(.bordered)
                Spacer()
                Text("\(store.logEntries.count) voci")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Log
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(store.logEntries) { entry in
                        logEntryRow(entry)
                    }
                }
                .padding(8)
            }
        }
    }

    private func logEntryRow(_ entry: BuildProgressStore.BuildLogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(logColor(entry.level))
                .frame(width: 6, height: 6)
                .padding(.top, 5)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(logColor(entry.level))
                .textSelection(.enabled)
        }
    }

    private func logColor(_ level: BuildProgressStore.BuildLogEntry.LogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }

    // MARK: - Profiling Tab

    private var profilingTab: some View {
        VStack(spacing: 12) {
            if let result = store.profilingResult {
                profilingResultView(result)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Nessun risultato di profiling")
                        .font(.headline)
                    Text("Avvia il profiling dal menu Build")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func profilingResultView(_ result: ProfileService.ProfileResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                metricRow("CPU", value: String(format: "%.1f%%", result.summary.cpuUsagePercent))
                metricRow("Memoria picco", value: String(format: "%.1f MB", result.summary.peakMemoryMB))
                metricRow("Allocazioni", value: "\(result.summary.allocations)")
                metricRow("Leak rilevati", value: "\(result.summary.leaksDetected)")
                metricRow("Stato termico", value: result.summary.thermalState)
                metricRow("Durata", value: String(format: "%.1fs", result.duration))

                if let path = result.traceFilePath {
                    HStack {
                        Text("Trace:")
                            .font(.caption).bold()
                        Text(path)
                            .font(.system(size: 10, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .padding()
        }
    }

    private func metricRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .bold()
        }
    }

    // MARK: - Memory Tab

    private var memoryTab: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("Snapshot") { store.captureMemorySnapshot() }
                    .buttonStyle(.bordered)
                Button("Rileva Leak") { store.detectLeaks() }
                    .buttonStyle(.bordered)
                Spacer()
                Text("\(store.memorySnapshots.count) snapshot")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            if store.memorySnapshots.isEmpty {
                Text("Nessuno snapshot catturato")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.memorySnapshots.indices, id: \.self) { idx in
                    let snapshot = store.memorySnapshots[idx]
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption).bold()
                        HStack(spacing: 12) {
                            Text(String(format: "RSS: %.1f MB", snapshot.residentMemoryMB))
                            Text(String(format: "VM: %.1f MB", snapshot.virtualMemoryMB))
                            if !snapshot.leaks.isEmpty {
                                Text("\(snapshot.leaks.count) leak")
                                    .foregroundColor(.red)
                            }
                        }
                        .font(.system(size: 11, design: .monospaced))
                    }
                }
            }
        }
    }
}

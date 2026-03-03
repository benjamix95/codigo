import SwiftUI

extension BrowserPanelView {
    // MARK: - Console Drawer

    func consoleDrawer(store: BrowserSessionStore) -> some View {
        VStack(spacing: 0) {
            consoleToolbar(store: store)
            Divider().opacity(0.15)
            consoleLogsList(store: store)
        }
        .background(DesignSystem.Colors.backgroundPrimary)
    }

    private func consoleToolbar(store: BrowserSessionStore) -> some View {
        HStack(spacing: 6) {
            Text("Console")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Spacer()

            Picker("", selection: $consoleFilterLevel) {
                Text("All").tag(ConsoleLogLevel?.none)
                ForEach(ConsoleLogLevel.allCases, id: \.self) { level in
                    Label(level.rawValue.capitalized, systemImage: level.icon)
                        .tag(ConsoleLogLevel?.some(level))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 80)
            .controlSize(.small)

            let errorCount = store.consoleLogs.filter { $0.level == .error }.count
            let warnCount = store.consoleLogs.filter { $0.level == .warn }.count

            if errorCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "xmark.octagon.fill").font(.system(size: 9))
                    Text("\(errorCount)").font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(DesignSystem.Colors.error)
            }

            if warnCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                    Text("\(warnCount)").font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(DesignSystem.Colors.warning)
            }

            Button { store.clearConsoleLogs() } label: {
                Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain).help("Clear console")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func consoleLogsList(store: BrowserSessionStore) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let logs = store.filteredLogs(level: consoleFilterLevel)
                    ForEach(logs) { entry in
                        consoleLogRow(entry).id(entry.id)
                    }
                }
                .padding(.horizontal, 8)
            }
            .onChange(of: store.consoleLogs.count) { _, _ in
                if let last = store.filteredLogs(level: consoleFilterLevel).last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func consoleLogRow(_ entry: ConsoleLogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: entry.level.icon)
                .font(.system(size: 9))
                .foregroundStyle(colorForLevel(entry.level))
                .frame(width: 12, alignment: .center)
                .padding(.top, 2)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(colorForLevel(entry.level))
                .textSelection(.enabled)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
        .background(
            entry.level == .error ? DesignSystem.Colors.error.opacity(0.06)
            : entry.level == .warn ? DesignSystem.Colors.warning.opacity(0.04)
            : Color.clear
        )
    }

    private func colorForLevel(_ level: ConsoleLogLevel) -> Color {
        switch level {
        case .error: return DesignSystem.Colors.error
        case .warn: return DesignSystem.Colors.warning
        case .info: return DesignSystem.Colors.info
        case .debug: return DesignSystem.Colors.textTertiary
        case .log: return DesignSystem.Colors.textSecondary
        }
    }
}

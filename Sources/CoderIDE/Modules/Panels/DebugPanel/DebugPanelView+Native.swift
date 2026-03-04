import SwiftUI

extension DebugPanelView {
    var nativeDebugContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            nativeDebugHeader
            nativeLaunchEditor
            nativeBreakpointsCard
            nativeWatchEditor
            nativeDebugControls

            if debugStore.nativeSession.callStack.isEmpty && debugStore.nativeSession.watchVariables.isEmpty {
                emptyState(
                    icon: "terminal",
                    title: "Native debugger idle",
                    subtitle: "Start a native LLDB session to inspect call stack and watch values"
                )
            } else {
                nativeCallStackSection
                nativeWatchSection
            }
        }
    }

    var nativeDebugHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Adapter")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                Text(debugStore.nativeSession.adapter)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(accent)
                Spacer()
                Text(debugStore.nativeSession.status.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(nativeStatusColor(debugStore.nativeSession.status))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(nativeStatusColor(debugStore.nativeSession.status).opacity(0.12), in: Capsule())
            }
            if let target = debugStore.nativeSession.targetPath, !target.isEmpty {
                Text(target)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
            }
            if let lastError = debugStore.nativeSession.lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.error)
                    .lineLimit(3)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    var nativeCallStackSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Call Stack")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            ForEach(debugStore.nativeSession.callStack) { frame in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8))
                        .foregroundStyle(accent.opacity(0.7))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(frame.function)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                        Text("\((frame.filePath as NSString).lastPathComponent):\(frame.line)")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    Spacer()
                }
                .padding(.vertical, 3)
            }
        }
        .padding(10)
        .background(accent.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    var nativeWatchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Watch Variables")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            ForEach(debugStore.nativeSession.watchVariables) { watch in
                HStack(alignment: .top, spacing: 6) {
                    Text(watch.expression)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accent)
                    Text("=")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text(watch.value)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    func nativeStatusColor(_ status: NativeDebugStatus) -> Color {
        switch status {
        case .idle: return .secondary
        case .running: return DesignSystem.Colors.info
        case .paused: return DesignSystem.Colors.warning
        case .stopped: return DesignSystem.Colors.success
        case .error: return DesignSystem.Colors.error
        }
    }
}

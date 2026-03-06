import SwiftUI

extension DebugPanelView {
    var nativeLaunchEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Target")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            TextField("/path/to/app-or-binary", text: $debugStore.nativeTargetPathInput)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

            Text("Arguments (comma/newline separated)")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            TextField("--flag, value", text: $debugStore.nativeArgumentsInput, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2 ... 4)
                .font(.system(size: 10.5, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
        .onAppear {
            debugStore.primeNativeTargetInputIfNeeded()
        }
        .disabled(!debugStore.isNativeDebugEnabled)
        .opacity(debugStore.isNativeDebugEnabled ? 1 : 0.65)
    }

    var nativeWatchEditor: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Watch expressions (comma/newline separated)")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            HStack(spacing: 6) {
                TextField("counter, self.state, currentUser.id", text: $debugStore.nativeWatchExpressionsInput, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(2 ... 4)
                    .font(.system(size: 10.5, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

                Button("Apply") {
                    onNativeApplyWatches()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .semibold))
                .disabled(debugStore.nativeWatchExpressionsInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .disabled(!debugStore.isNativeDebugEnabled)
        .opacity(debugStore.isNativeDebugEnabled ? 1 : 0.65)
    }

    var nativeDebugControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button("Start") { onNativeStart() }
                Button("Stop") { onNativeStop() }
                Button("Refresh") { onNativeRefresh() }
                Button("Sync") { onNativeSync() }
            }

            HStack(spacing: 6) {
                Button("Step In") { onNativeStepIn() }
                Button("Step Over") { onNativeStepOver() }
                Button("Step Out") { onNativeStepOut() }

                Spacer()

                if let lastCommand = debugStore.nativeSession.lastCommand, !lastCommand.isEmpty {
                    Text(lastCommand)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(accent)
        .disabled(!debugStore.isNativeDebugEnabled)
        .opacity(debugStore.isNativeDebugEnabled ? 1 : 0.65)
    }
}

import SwiftUI
import Foundation

extension DebugPanelView {
    var nativeBreakpointsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Breakpoints")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                Text("\(debugStore.breakpoints.filter(\.isActive).count)/\(debugStore.breakpoints.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            nativeBreakpointForm

            if debugStore.breakpoints.isEmpty {
                Text("Nessun breakpoint configurato")
                    .font(.system(size: 9.5))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(debugStore.breakpoints) { breakpoint in
                        nativeBreakpointRow(breakpoint)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    private var nativeBreakpointForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("File path (Sources/App.swift)", text: $debugStore.nativeBreakpointFilePathInput)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 6) {
                TextField("Line", text: $debugStore.nativeBreakpointLineInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    .frame(maxWidth: 72)

                TextField("Condition (optional)", text: $debugStore.nativeBreakpointConditionInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))

                Button("Add") {
                    debugStore.addBreakpointFromNativeInputs()
                }
                .buttonStyle(.borderless)
                .font(.system(size: 10, weight: .semibold))
                .disabled(
                    debugStore.nativeBreakpointFilePathInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || debugStore.nativeBreakpointLineInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
    }

    private func nativeBreakpointRow(_ breakpoint: DebugBreakpoint) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                debugStore.toggleBreakpoint(id: breakpoint.id)
            } label: {
                Image(systemName: breakpoint.isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(breakpoint.isActive ? accent : DesignSystem.Colors.textQuaternary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("\((breakpoint.filePath as NSString).lastPathComponent):\(breakpoint.line)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Text(breakpoint.filePath)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .lineLimit(1)

                if let condition = breakpoint.condition, !condition.isEmpty {
                    Text("if \(condition)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(accent.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer()

            Button(role: .destructive) {
                debugStore.removeBreakpoint(id: breakpoint.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.error)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
    }
}

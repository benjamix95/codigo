import SwiftUI
import CoderEngine

extension DebugPanelView {
    var markersContent: some View {
        Group {
            if !debugStore.instrumentationPoints.isEmpty {
                instrumentationSection
            }

            if debugStore.debugMarkers.isEmpty && debugStore.instrumentationPoints.isEmpty {
                emptyState(
                    icon: "mappin.slash",
                    title: "No markers",
                    subtitle: "The agent inserts markers during the fix phase"
                )
            } else if !debugStore.debugMarkers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(debugStore.debugMarkers.count) markers in \(debugStore.markedFileCount) files")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Spacer()
                    }

                    ForEach(debugStore.debugMarkers) { marker in
                        markerRow(marker)
                    }
                }
            }
        }
    }

    var instrumentationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.info)
                Text("Instrumentation")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                Text("\(debugStore.instrumentationPoints.count) in \(debugStore.instrumentedFileCount) files")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            ForEach(debugStore.instrumentationPoints) { point in
                instrumentationRow(point)
            }
        }
        .padding(10)
        .background(DesignSystem.Colors.info.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DesignSystem.Colors.info.opacity(0.1), lineWidth: 0.5)
        )
    }

    func instrumentationRow(_ point: InstrumentationPoint) -> some View {
        HStack(spacing: 8) {
            Image(systemName: instrumentationIcon(point.type))
                .font(.system(size: 10))
                .foregroundStyle(instrumentationColor(point.type))

            VStack(alignment: .leading, spacing: 1) {
                Text((point.filePath as NSString).lastPathComponent)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                HStack(spacing: 4) {
                    Text("L\(point.lineNumber)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Text(point.type.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(instrumentationColor(point.type))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(instrumentationColor(point.type).opacity(0.1), in: Capsule())
                }
            }

            Spacer()

            Button {
                debugStore.removeInstrumentation(id: point.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }

    func instrumentationIcon(_ type: InstrumentationPoint.InstrumentationType) -> String {
        switch type {
        case .logging:    return "text.quote"
        case .assertion:  return "exclamationmark.triangle"
        case .timing:     return "clock"
        case .variable:   return "curlybraces"
        }
    }

    func instrumentationColor(_ type: InstrumentationPoint.InstrumentationType) -> Color {
        switch type {
        case .logging:    return DesignSystem.Colors.info
        case .assertion:  return DesignSystem.Colors.warning
        case .timing:     return .purple
        case .variable:   return .cyan
        }
    }

    func markerRow(_ marker: DebugMarker) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 1) {
                Text((marker.filePath as NSString).lastPathComponent)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                HStack(spacing: 4) {
                    Text("Line \(marker.lineNumber)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Text(marker.markerComment)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                debugStore.removeDebugMarker(id: marker.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
    }

}

import SwiftUI
import CoderEngine

// MARK: - IndexCircleBadge

/// Indicatore compatto: rosso = in attesa / errore, arancio = indicizzazione (codebase + vettoriale), giallo-oro in corso, verde = pronto.
struct IndexCircleBadge: View {
    let state: WorkspaceIndexBadgeState
    var dimension: CGFloat = 13
    private var lineWidth: CGFloat { max(1.0, dimension * 0.12) }

    private var fraction: Double {
        if state.isFullyIndexed { return 1.0 }
        if let p = state.progress { return min(1.0, max(0.0, p.fraction)) }
        return 0
    }

    private var trackColor: Color {
        if !state.indexingEnabled { return Color.secondary.opacity(0.25) }
        if state.shouldShowErrorNotice { return DesignSystem.Colors.error.opacity(0.35) }
        if state.isFullyIndexed { return DesignSystem.Colors.success.opacity(0.25) }
        if state.isIndexingActive { return Color.orange.opacity(0.35) }
        if state.shouldShowWaitNotice { return DesignSystem.Colors.error.opacity(0.3) }
        return Color.secondary.opacity(0.25)
    }

    private var progressColor: Color {
        if !state.indexingEnabled { return .secondary }
        if state.shouldShowErrorNotice { return DesignSystem.Colors.error }
        if state.isFullyIndexed { return DesignSystem.Colors.success }
        if state.isIndexingActive { return Color.orange }
        if state.shouldShowWaitNotice { return Color.red.opacity(0.9) }
        return .secondary
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    progressColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.22), value: fraction)

            centerContent
                .frame(width: dimension * 0.62, height: dimension * 0.62)
        }
        .frame(width: dimension, height: dimension)
        .help(helpText)
    }

    @ViewBuilder
    private var centerContent: some View {
        if !state.indexingEnabled, state.hasWorkspacePaths {
            Image(systemName: "minus")
                .font(.system(size: dimension * 0.35, weight: .bold))
                .foregroundStyle(.secondary)
        } else if state.isFullyIndexed {
            Image(systemName: "checkmark")
                .font(.system(size: dimension * 0.38, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.success)
        } else if state.shouldShowErrorNotice {
            Image(systemName: "exclamationmark")
                .font(.system(size: dimension * 0.38, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.error)
        } else if state.isIndexingActive {
            Text("\(state.displayPercent)")
                .font(.system(size: dimension * 0.42, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.orange)
                .minimumScaleFactor(0.4)
        } else if state.shouldShowWaitNotice {
            Image(systemName: "clock")
                .font(.system(size: dimension * 0.36, weight: .semibold))
                .foregroundStyle(Color.red.opacity(0.85))
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: dimension * 0.28, height: dimension * 0.28)
        }
    }

    private var helpText: String {
        if !state.indexingEnabled {
            return "Indice automatico disattivato"
        }
        if state.shouldShowErrorNotice {
            return "Errore durante l’indicizzazione"
        }
        if state.isFullyIndexed {
            return "Indicizzazione completa — codebase e ricerca vettoriale pronti"
        }
        if state.isIndexingActive {
            return "Indicizzazione: \(state.displayPercentText) (file, semantic index, database vettoriale)"
        }
        if state.shouldShowWaitNotice {
            return "Attendere il completamento dell’indice (codebase + DB vettoriale)"
        }
        return "Stato indice"
    }
}

import CoderEngine
import SwiftUI

// MARK: - Pipeline: coda eventi con proiezione sospesa

extension DebugPanelView {

    @ViewBuilder
    func suppressedDebugProjectionBufferBanner(
        integration: PipelineIntegrationService
    ) -> some View {
        let _ = integration.debugProjectionBufferRevision
        if let cid = conversationId,
           integration.isDebugProjectionSuppressed(for: cid) {
            let pending = integration.pendingBufferedDebugEventCount(for: cid)
            if pending > 0 {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.warning)
                    Text(
                        "Proiezione debug sospesa: \(pending) eventi in coda. Riprendi l’esecuzione o togli lo Stop per applicarli al pannello."
                    )
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DesignSystem.Colors.warning.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.warning.opacity(0.35), lineWidth: 0.6)
                )
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
        }
    }
}

import CoderEngine
import SwiftUI

extension ReviewPanelFindingDetail {
    var summarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("SUMMARY")
            Text(finding.message)
                .font(.system(size: 11))
                .foregroundStyle(.primary.opacity(0.85))
                .textSelection(.enabled)
        }
    }

    var verificationSection: AnyView? {
        guard let verification = finding.verificationReport,
              !verification.isEmpty
        else { return nil }
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("CAUSE / VERIFICATION")
                detailBlock(verification)
            }
        )
    }

    var remediationSection: AnyView? {
        guard let fix = finding.suggestedFix,
              !fix.isEmpty
        else { return nil }
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("REMEDIATION")
                detailBlock(fix)
            }
        )
    }

    var invariantSection: AnyView? {
        var lines: [String] = []
        if let invariant = finding.expectedInvariant, !invariant.isEmpty {
            lines.append("Invariante: \(invariant)")
        }
        if let reasoning = finding.reproOrReasoning, !reasoning.isEmpty {
            lines.append("Reasoning: \(reasoning)")
        }
        guard !lines.isEmpty else { return nil }
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("INVARIANT / REPRO")
                detailBlock(lines.joined(separator: "\n\n"))
            }
        )
    }

    var patchFailureSection: AnyView? {
        guard patch == nil, let patchFailureComment else { return nil }
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("PATCH STATUS")
                detailBlock(patchFailureComment.content)
            }
        )
    }

    func validationSection(for patch: ReviewPatchArtifact) -> AnyView? {
        var lines = ["validation: \(patch.validationStatus.rawValue)"]
        if let summary = patch.validationSummary, !summary.isEmpty {
            lines.append("summary: \(summary)")
        }
        if let applyMessage = patch.applyMessage, !applyMessage.isEmpty {
            lines.append("message: \(applyMessage)")
        }
        guard !lines.isEmpty else { return nil }
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("VALIDATION")
                detailBlock(lines.joined(separator: "\n"))
            }
        )
    }

    func detailBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.8))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                )
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    func patchPresentation(_ patch: ReviewPatchArtifact) -> some View {
        let diff = patch.diffPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        if diff.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("PATCH")
                Text("Diff in preparazione: attendi il completamento di «Prepare Patch».")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        } else {
            patchSection(patch)
        }
    }

    func patchSection(_ patch: ReviewPatchArtifact) -> some View {
        let immersive = chrome == .immersive
        let corner: CGFloat = immersive ? 12 : 6
        return VStack(alignment: .leading, spacing: 6) {
            sectionLabel("PATCH PREVIEW")
            Text(patch.diffPreview)
                .font(.system(size: immersive ? 9.5 : 9, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.8))
                .padding(immersive ? 10 : 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(immersive ? 0.55 : 0.5))
                )
            HStack(spacing: 8) {
                Text("Verify: \(patch.verifyStatus.rawValue)")
                Text("Validation: \(patch.validationStatus.rawValue)")
                Text("PR: \(patch.prStatus.rawValue)")
                Text("Merge: \(patch.mergeStatus.rawValue)")
            }
            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
            .foregroundStyle(.quaternary)
        }
        .padding(immersive ? 10 : 0)
        .background(
            RoundedRectangle(cornerRadius: immersive ? 14 : 0, style: .continuous)
                .fill(Color.primary.opacity(immersive ? 0.03 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: immersive ? 14 : 0, style: .continuous)
                .strokeBorder(store.accent.opacity(immersive ? 0.22 : 0), lineWidth: immersive ? 0.9 : 0)
        )
    }

    var commentsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel("COMMENTS (\(finding.comments.count))")
            ForEach(finding.comments, id: \.id) { comment in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(comment.author)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(store.accent)
                        Spacer()
                        Text(comment.createdAt, style: .relative)
                            .font(.system(size: 8))
                            .foregroundStyle(.quaternary)
                    }
                    Text(comment.content)
                        .font(.system(size: 10))
                        .foregroundStyle(.primary.opacity(0.8))
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                )
            }
        }
    }

    var actionsSection: some View {
        let bugConfirmed = finding.isBugConfirmedForPatchPreparation
        let applyReady = patch?.isReadyForUserApply == true
        let isApplyingThisFinding = store.applyingPatchFindingId == finding.id
        return VStack(alignment: .leading, spacing: 8) {
            if let patch, patch.isPanelApplySuccess {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Applicazione confermata dopo suite test completa")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Puoi aprire una pull request dal pulsante a destra.")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if patch.canInitiatePullRequestFromPanel, let sessionId = store.selectedSessionId {
                        Button {
                            Task { await store.openPatchPullRequest(sessionId: sessionId, findingId: finding.id) }
                        } label: {
                            Label("Crea PR", systemImage: "arrow.triangle.pull")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(store.accent)
                        .controlSize(.small)
                    } else if let urlString = patch.prURL?.trimmingCharacters(in: .whitespacesAndNewlines),
                              !urlString.isEmpty,
                              let url = URL(string: urlString) {
                        Link(destination: url) {
                            Label("Apri PR", systemImage: "arrow.up.right.square")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.green.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.green.opacity(0.25), lineWidth: 0.5)
                )
            }

            HStack(spacing: 8) {
                if (finding.status.isOpenState || finding.status == .patchFailed),
                   let sessionId = store.selectedSessionId {
                    if !bugConfirmed {
                        Button {
                            Task { await store.verifyFindingDeepAnalysis(sessionId: sessionId, findingId: finding.id) }
                        } label: {
                            Label("Verify bug", systemImage: "checkmark.shield")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                    }

                    if bugConfirmed && (patch == nil || finding.status == .patchFailed) {
                        Button {
                            Task { await store.preparePatch(sessionId: sessionId, findingId: finding.id) }
                        } label: {
                            Label(
                                finding.status == .patchFailed ? "Retry Prepare" : "Prepare Patch",
                                systemImage: "wand.and.stars"
                            )
                            .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if patch != nil && !applyReady {
                        Button {
                            Task {}
                        } label: {
                            Label("Apply Patch", systemImage: "wrench.and.screwdriver")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(true)
                        .help("Il diff deve essere verificato prima dell’applicazione.")
                    }

                    if applyReady {
                        if isApplyingThisFinding {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Build e suite test…")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 4)
                        } else {
                            Button {
                                Task { await store.applyPatch(sessionId: sessionId, findingId: finding.id) }
                            } label: {
                                Label("Apply Patch", systemImage: "wrench.and.screwdriver")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(store.accent)
                            .controlSize(.small)
                        }
                    }

                    Button {
                        Task {
                            await store.dismissFinding(
                                sessionId: sessionId, findingId: finding.id, reason: "dismissed"
                            )
                        }
                    } label: {
                        Label("Dismiss", systemImage: "xmark.circle")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isApplyingThisFinding)
                }
                if let sessionId = store.selectedSessionId,
                   store.currentPatches.contains(where: { $0.findingId == finding.id }) {
                    Button {
                        Task { await store.revalidatePatch(sessionId: sessionId, findingId: finding.id) }
                    } label: {
                        Label("Revalidate", systemImage: "checkmark.seal")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isApplyingThisFinding)

                    Button {
                        Task { await store.rollbackPatch(sessionId: sessionId, findingId: finding.id) }
                    } label: {
                        Label("Rollback", systemImage: "arrow.uturn.backward.circle")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isApplyingThisFinding)

                    if let p = patch,
                       p.prURL != nil || p.prStatus == .opened || p.status == .prOpened
                    {
                        Button {
                            Task { await store.mergePatchPullRequest(sessionId: sessionId, findingId: finding.id) }
                        } label: {
                            Label("Merge PR", systemImage: "arrow.triangle.merge")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isApplyingThisFinding)
                    }
                }
                Spacer()
            }
        }
        .disabled(store.isRunning)
        .opacity(store.isRunning ? 0.72 : 1)
    }

    func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.quaternary)
            .tracking(0.6)
    }
}

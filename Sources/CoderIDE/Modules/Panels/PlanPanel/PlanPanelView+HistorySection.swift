import SwiftUI

extension PlanPanelView {
    var historySection: some View {
        let conv = chatStore.conversation(for: conversationId)
        let ctxId = conv?.contextId
        let ctxPath = conv?.contextFolderPath
        let items = planHistoryStore.entriesForContext(
            contextId: ctxId,
            contextFolderPath: ctxPath
        )

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("History")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if workspaceSource == .manualShortcut {
                    Text("manual")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                        )
                }
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                if !items.isEmpty && (ctxId != nil || ctxPath != nil) {
                    Button(role: .destructive) {
                        showDeleteAllHistoryConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("Delete all history")
                }
            }

            if items.isEmpty {
                Text("No saved plans for this context.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                ForEach(items) { entry in
                    let selectedHistoryOptionId = selectedOptionIdForHistoryEntry(entry)
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button {
                            if planHistoryStore.selectedEntryId == entry.id {
                                planHistoryStore.setSelectedEntry(id: nil)
                            } else {
                                planHistoryStore.setSelectedEntry(id: entry.id)
                                let choice = resolvedBuildContent(for: entry) ?? ""
                                if PlanOptionsParser.hasRequiredTodoHeader(choice),
                                   !PlanOptionsParser.extractTodosFromOptionText(choice).isEmpty {
                                    onHistoryEntrySelectedForBuild?()
                                }
                            }
                            historySelectionVersion &+= 1
                        } label: {
                            let isActive = planHistoryStore.selectedEntryId == entry.id
                            Text(isActive ? "Hide" : "Preview")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isActive ? planColor : .secondary)
                        }
                        .buttonStyle(.plain)

                        if !entry.options.isEmpty {
                            Menu {
                                ForEach(entry.options.sorted(by: { $0.id < $1.id })) { option in
                                    Button {
                                        planHistoryStore.updateChosenPath(id: entry.id, chosenPath: option.fullText)
                                        planHistoryStore.setSelectedEntry(id: entry.id)
                                        onHistoryEntrySelectedForBuild?()
                                        historySelectionVersion &+= 1
                                        buildHint = "Selected Option \(option.id)"
                                    } label: {
                                        HStack {
                                            Text("Option \(option.id): \(option.title)")
                                                .lineLimit(1)
                                            if selectedHistoryOptionId == option.id {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "list.number")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .help("Select option for rebuild")
                        }

                        Button {
                            guard isPlanBuildEnabled(
                                phase: planFlowPhase,
                                hasBuildChoice: true,
                                allowIdleRebuild: true,
                                providerExecutionCapable: isActiveProviderExecutionCapable
                            ) else {
                                buildHint = phaseHint ?? "Build unavailable in this phase."
                                return
                            }
                            planHistoryStore.setSelectedEntry(id: entry.id)
                            guard let choice = resolvedBuildContent(for: entry) else {
                                buildHint = "Select an option before rebuilding."
                                return
                            }
                            let hasRequiredTodoHeader = PlanOptionsParser.hasRequiredTodoHeader(choice)
                            let extractedTodos = PlanOptionsParser.extractTodosFromOptionText(choice)
                            guard hasRequiredTodoHeader, !extractedTodos.isEmpty else {
                                buildHint = "Build requires a todo checklist."
                                return
                            }
                            onBuild(choice, planProviderId, true)
                            planHistoryStore.markRebuilt(id: entry.id)
                            historySelectionVersion &+= 1
                            buildHint = "Rebuild started..."
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)

                        Button {
                            _ = planHistoryStore.duplicateEntry(id: entry.id)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)

                        Button {
                            downloadPlan(entry)
                        } label: {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            if planHistoryStore.selectedEntryId == entry.id {
                                historySelectionVersion &+= 1
                            }
                            planHistoryStore.deleteEntry(id: entry.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                planHistoryStore.selectedEntryId == entry.id
                                    ? DesignSystem.Colors.planColor.opacity(0.12)
                                    : Color(nsColor: .controlBackgroundColor).opacity(0.2)
                            )
                    )
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .alert("Delete all history?", isPresented: $showDeleteAllHistoryConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete all", role: .destructive) {
                planHistoryStore.deleteAllForContext(contextId: ctxId, contextFolderPath: ctxPath)
            }
        } message: {
            Text("All saved planning entries for this context will be permanently deleted.")
        }
    }
}

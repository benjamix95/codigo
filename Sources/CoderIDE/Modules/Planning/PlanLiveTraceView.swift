import SwiftUI

private enum PlanTraceFormatters {
    static let hms: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct PlanLiveTraceView: View {
    let activities: [TaskActivity]
    let workspaceHints: [String]
    let onOpenFile: ((String) -> Void)?
    private let maxVisibleEvents = 24
    private let compactLimit = 8

    @State private var isExpanded = false
    @State private var expandedRawById: Set<UUID> = []
    @State private var filePreviewById: [UUID: FileChangePreviewResult] = [:]
    @State private var loadingPreviewIds: Set<UUID> = []

    private var visibleActivities: [TaskActivity] {
        let all = Array(activities.suffix(maxVisibleEvents))
        guard !isExpanded else { return all }

        let running = all.filter { $0.isRunning }
        let rest = all.filter { !$0.isRunning }
        if running.count >= compactLimit {
            return Array(running.suffix(compactLimit))
        }
        let remaining = compactLimit - running.count
        return Array(rest.suffix(remaining)) + running
    }

    private var hiddenCount: Int {
        let totalCapped = min(activities.count, maxVisibleEvents)
        return max(0, totalCapped - visibleActivities.count)
    }

    var body: some View {
        let traceItems = visibleActivities.map(PlanTraceItem.init(activity:))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Plan Trace")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(activities.count) activities")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if !isExpanded && hiddenCount > 0 {
                    Text("+\(hiddenCount) more...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 2)
                }

                ForEach(traceItems) { item in
                    PlanLiveTraceRowView(
                        item: item,
                        workspaceHints: workspaceHints,
                        isExpanded: expandedRawById.contains(item.id),
                        preview: item.fileChange.flatMap { filePreviewById[$0.id] },
                        isLoadingPreview: item.fileChange.map { loadingPreviewIds.contains($0.id) } ?? false,
                        expandedOutput: formattedOutput(for: item),
                        timestampText: timestamp(item.timestamp),
                        onToggleExpanded: { toggleExpanded(item) },
                        onOpenFile: onOpenFile
                    )
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }
}

private extension PlanLiveTraceView {
    func formattedOutput(for item: PlanTraceItem) -> String? {
        guard item.fileChange == nil,
              let raw = PlanTraceItem.rawOutput(for: item.activity) else {
            return nil
        }
        return truncated(raw)
    }

    func toggleExpanded(_ item: PlanTraceItem) {
        if expandedRawById.contains(item.id) {
            expandedRawById.remove(item.id)
            return
        }

        expandedRawById.insert(item.id)
        if let fileChange = item.fileChange {
            loadPreviewIfNeeded(for: fileChange)
        }
    }

    func loadPreviewIfNeeded(for change: ToolTraceFileChange) {
        if filePreviewById[change.id] != nil || loadingPreviewIds.contains(change.id) {
            return
        }

        loadingPreviewIds.insert(change.id)
        let changeId = change.id
        Task { @MainActor in
            let result = await FileChangePreviewResolver.shared.resolvePreview(
                for: change,
                workspaceHints: workspaceHints
            )
            filePreviewById[changeId] = result
            loadingPreviewIds.remove(changeId)
        }
    }

    func timestamp(_ date: Date) -> String {
        PlanTraceFormatters.hms.string(from: date)
    }

    func truncated(_ text: String, maxChars: Int = 6000) -> String {
        if text.count <= maxChars { return text }
        let end = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<end]) + "\n\n... output truncated (\(text.count - maxChars) characters hidden)"
    }
}

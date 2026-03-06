import SwiftUI
import AppKit
import CoderEngine

extension SidebarView {
    var taskCloudSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Task Cloud")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    loadCodexTasks()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            if isLoadingTasks {
                Text("Loading...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let first = codexTasks.first {
                Text(first.title ?? first.id)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
        }
    }

    var footer: some View {
        HStack(spacing: 8) {
            ProfileSwitcherView()

            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.clear)
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsToAccounts)) { _ in
            showSettings = true
        }
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_US")
        f.unitsStyle = .short
        return f
    }()

    func relativeDate(_ date: Date, relativeTo referenceDate: Date = Date()) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: referenceDate)
    }

    func matchesQuery(_ conv: Conversation, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        // Only match on title for the sidebar filter; full-text search across messages
        // is handled by chatStore.searchThreads() which is shown separately below the list.
        return conv.title.lowercased().contains(q)
    }
}

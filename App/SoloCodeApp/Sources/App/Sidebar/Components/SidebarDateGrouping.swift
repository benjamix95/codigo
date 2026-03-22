import Foundation

enum SidebarDateGroup: String, CaseIterable, Identifiable {
    case today = "Today"
    case yesterday = "Yesterday"
    case thisWeek = "This Week"
    case older = "Older"

    var id: String { rawValue }
}

enum SidebarDateGrouper {
    static func group(
        _ conversations: [Conversation],
        referenceDate: Date = Date()
    ) -> [(group: SidebarDateGroup, threads: [Conversation])] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday)!
        let startOfWeek = calendar.date(
            from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
        )!

        var buckets: [SidebarDateGroup: [Conversation]] = [:]

        for conv in conversations {
            let group: SidebarDateGroup
            if conv.createdAt >= startOfToday {
                group = .today
            } else if conv.createdAt >= startOfYesterday {
                group = .yesterday
            } else if conv.createdAt >= startOfWeek {
                group = .thisWeek
            } else {
                group = .older
            }
            buckets[group, default: []].append(conv)
        }

        return SidebarDateGroup.allCases.compactMap { group in
            guard let threads = buckets[group], !threads.isEmpty else { return nil }
            return (group: group, threads: threads)
        }
    }
}

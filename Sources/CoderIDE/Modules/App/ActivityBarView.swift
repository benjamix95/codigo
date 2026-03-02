import SwiftUI

enum ActivityBarItem: String, CaseIterable, Identifiable {
    case explorer
    case search
    case sourceControl
    case settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .explorer: return "doc.on.doc"
        case .search: return "magnifyingglass"
        case .sourceControl: return "arrow.triangle.branch"
        case .settings: return "gearshape"
        }
    }

    var tooltip: String {
        switch self {
        case .explorer: return "Explorer"
        case .search: return "Search"
        case .sourceControl: return "Source Control"
        case .settings: return "Settings"
        }
    }
}

struct ActivityBarView: View {
    @Binding var selectedItem: ActivityBarItem?
    @Binding var showSettings: Bool

    private let barWidth: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 12)

            ForEach(ActivityBarItem.allCases.filter { $0 != .settings }) { item in
                activityButton(item)
            }

            Spacer()

            activityButton(.settings)

            Spacer().frame(height: 12)
        }
        .frame(width: barWidth)
        .background(DesignSystem.Colors.backgroundPrimary)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DesignSystem.Colors.border)
                .frame(width: 0.5)
        }
    }

    private func activityButton(_ item: ActivityBarItem) -> some View {
        let isActive = selectedItem == item

        return Button {
            if item == .settings {
                showSettings = true
            } else {
                withAnimation(.snappy(duration: 0.15)) {
                    selectedItem = selectedItem == item ? nil : item
                }
            }
        } label: {
            ZStack(alignment: .leading) {
                if isActive && item != .settings {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.accentColor)
                        .frame(width: 2.5, height: 18)
                        .offset(x: -2)
                }

                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Color.primary : Color.secondary.opacity(0.65))
                    .frame(width: barWidth, height: 36)
            }
        }
        .buttonStyle(.plain)
        .help(item.tooltip)
    }
}

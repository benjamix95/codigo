import SwiftUI

enum ActivityBarItem: String, CaseIterable, Identifiable {
    case explorer
    case search
    case sourceControl
    case settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .explorer: return "folder"
        case .search: return "magnifyingglass"
        case .sourceControl: return "arrow.triangle.branch"
        case .settings: return "slider.horizontal.3"
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

    var shortTitle: String {
        switch self {
        case .explorer: return "Files"
        case .search: return "Search"
        case .sourceControl: return "Git"
        case .settings: return "Prefs"
        }
    }

    var tint: Color {
        switch self {
        case .explorer: return Color(red: 0.35, green: 0.62, blue: 0.96)
        case .search: return Color(red: 0.25, green: 0.78, blue: 0.86)
        case .sourceControl: return Color(red: 0.32, green: 0.78, blue: 0.62)
        case .settings: return .secondary
        }
    }
}

struct ActivityBarView: View {
    @Binding var selectedItem: ActivityBarItem?
    @Binding var showSettings: Bool

    private let barWidth: CGFloat = 60

    var body: some View {
        VStack(spacing: 12) {
            railBrand

            VStack(spacing: 6) {
                ForEach(ActivityBarItem.allCases.filter { $0 != .settings }) { item in
                    activityButton(item)
                }
            }

            Spacer()

            footerButton
        }
        .padding(.vertical, 10)
        .frame(width: barWidth)
    }

    private var railBrand: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.015)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 42, height: 42)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.43, green: 0.71, blue: 0.98),
                                Color(red: 0.38, green: 0.86, blue: 0.74)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .frame(maxWidth: .infinity)
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
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? item.tint.opacity(0.16) : Color.clear)
                    .frame(width: 44, height: 44)

                if isActive {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(item.tint)
                        .frame(width: 3, height: 18)
                        .offset(x: -22)
                }

                Image(systemName: item.icon)
                    .font(.system(size: 15, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? item.tint : Color.secondary.opacity(0.78))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(.plain)
        .help(item.tooltip)
    }

    private var footerButton: some View {
        Button {
            showSettings = true
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .frame(width: 44, height: 44)
                Image(systemName: ActivityBarItem.settings.icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.78))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(.plain)
        .help(ActivityBarItem.settings.tooltip)
    }
}

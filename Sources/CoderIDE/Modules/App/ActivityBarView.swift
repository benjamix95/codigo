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
    let workspaceTitle: String

    private let barWidth: CGFloat = 84

    var body: some View {
        VStack(spacing: 14) {
            railBrand

            VStack(spacing: 10) {
                ForEach(ActivityBarItem.allCases.filter { $0 != .settings }) { item in
                    activityButton(item)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.86))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
            )

            Spacer()

            footerButton
        }
        .frame(width: barWidth)
    }

    private var railBrand: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 20, weight: .semibold))
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

            VStack(spacing: 3) {
                Text(workspaceTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text("WORKBENCH")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(1.0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            isActive
                            ? item.tint.opacity(0.18)
                            : Color.white.opacity(0.02)
                        )
                        .frame(width: 44, height: 38)
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? item.tint : Color.secondary.opacity(0.78))
                }

                Text(item.shortTitle)
                    .font(.system(size: 9.5, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isActive ? Color.white.opacity(0.04) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(item.tooltip)
    }

    private var footerButton: some View {
        Button {
            showSettings = true
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .frame(width: 44, height: 38)
                    Image(systemName: ActivityBarItem.settings.icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.secondary.opacity(0.78))
                }
                Text(ActivityBarItem.settings.shortTitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .help(ActivityBarItem.settings.tooltip)
    }
}

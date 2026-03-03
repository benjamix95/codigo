import SwiftUI

extension DebugPanelView {
    // MARK: - Tab Strip

    var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(DebugTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }

            Spacer()

            filterToggle
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    func tabButton(_ tab: DebugTab) -> some View {
        let isActive = selectedTab == tab
        let badgeCount = tabBadgeCount(tab)

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 9))
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(isActive ? accent : .secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            (isActive ? accent : Color.secondary).opacity(0.12),
                            in: Capsule()
                        )
                }
            }
            .foregroundStyle(isActive ? accent : DesignSystem.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? accent.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    func tabBadgeCount(_ tab: DebugTab) -> Int {
        switch tab {
        case .logs: return debugStore.filteredLogs.count
        case .runtime:
            return debugStore.currentRunId == nil
                ? debugStore.runtimeLogs.count
                : debugStore.currentRunLogs.count
        case .hypotheses: return debugStore.hypotheses.count
        case .markers: return debugStore.debugMarkers.count + debugStore.instrumentationPoints.count
        }
    }

    var filterToggle: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                isFilterExpanded.toggle()
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 12))
                .foregroundStyle(
                    isFilterExpanded || debugStore.severityFilter.count < DebugEntrySeverity.allCases.count
                    ? accent
                    : DesignSystem.Colors.textTertiary
                )
                .frame(width: 28, height: 28)
                .background(
                    (isFilterExpanded ? accent.opacity(0.08) : Color.clear),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .help("Filter severity")
    }

    // MARK: - Scroll Content

    var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if isFilterExpanded {
                        filterBar
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if !debugStore.debugFlowDiagram.isEmpty {
                        MermaidDiagramView(
                            mermaidCode: debugStore.debugFlowDiagram,
                            accentColor: accent
                        )
                    }

                    if !taskActivities.isEmpty {
                        CompactActivityTraceView(
                            activities: taskActivities,
                            accentColor: accent,
                            title: "Activity"
                        )
                    }

                    if !todoStore.todos.isEmpty {
                        todosCard
                    }

                    tabContent

                    Color.clear.frame(height: 1).id("debug-scroll-anchor")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: debugStore.logs.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("debug-scroll-anchor", anchor: .bottom)
                }
            }
            .onChange(of: debugStore.runtimeLogs.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("debug-scroll-anchor", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Filter Bar

    var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(DebugEntrySeverity.allCases, id: \.self) { severity in
                    severityFilterChip(severity)
                }
                Spacer()

                if debugStore.severityFilter.count < DebugEntrySeverity.allCases.count {
                    Button {
                        withAnimation(.quick) {
                            debugStore.severityFilter = Set(DebugEntrySeverity.allCases)
                        }
                    } label: {
                        Text("Reset")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                TextField("Search logs…", text: $debugStore.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))

                if !debugStore.searchQuery.isEmpty {
                    Button {
                        debugStore.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
        .background(DesignSystem.Colors.backgroundSecondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    func severityFilterChip(_ severity: DebugEntrySeverity) -> some View {
        let isActive = debugStore.severityFilter.contains(severity)
        return Button {
            withAnimation(.quick) {
                if isActive {
                    debugStore.severityFilter.remove(severity)
                } else {
                    debugStore.severityFilter.insert(severity)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: severity.icon)
                    .font(.system(size: 8))
                Text(severity.rawValue.capitalized)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(isActive ? severity.color : DesignSystem.Colors.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? severity.color.opacity(0.1) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        isActive ? severity.color.opacity(0.2) : Color.clear,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Content
}

import SwiftUI
import CoderEngine

// MARK: - Breadcrumb Navigation View

/// Vista breadcrumb con path del file e symbol scope corrente.
/// Ogni segmento è cliccabile per navigare; i dropdown mostrano i figli.
struct BreadcrumbNavigationView: View {
    @ObservedObject var store: BreadcrumbStore
    var onNavigateToLine: ((Int) -> Void)?
    var onNavigateToFile: ((String) -> Void)?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(store.segments.enumerated()), id: \.element.id) { idx, segment in
                    if idx > 0 {
                        chevron
                    }
                    segmentView(segment)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Segmento

    @ViewBuilder
    private func segmentView(_ segment: BreadcrumbStore.Segment) -> some View {
        switch segment.kind {
        case .folder:
            segmentLabel(segment, isLast: false)
        case .file:
            fileSegmentMenu(segment)
        case .symbol(let sym):
            symbolSegmentMenu(segment, symbol: sym)
        }
    }

    private func fileSegmentMenu(_ segment: BreadcrumbStore.Segment) -> some View {
        Menu {
            let topLevel = store.topLevelSymbols()
            if topLevel.isEmpty {
                Text("Nessun simbolo").foregroundColor(.secondary)
            } else {
                ForEach(topLevel, id: \.id) { sym in
                    Button {
                        onNavigateToLine?(sym.line)
                    } label: {
                        Label(sym.name, systemImage: sym.kind.sfSymbol)
                    }
                }
            }
        } label: {
            segmentLabel(segment, isLast: store.segments.last?.id == segment.id)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func symbolSegmentMenu(
        _ segment: BreadcrumbStore.Segment,
        symbol: IndexedSymbol
    ) -> some View {
        Menu {
            // Naviga a questo simbolo
            Button {
                onNavigateToLine?(symbol.line)
            } label: {
                Label("Vai a \(symbol.name)", systemImage: "arrow.right")
            }

            let children = store.childrenOf(symbol)
            if !children.isEmpty {
                Divider()
                ForEach(children, id: \.id) { child in
                    Button {
                        onNavigateToLine?(child.line)
                    } label: {
                        Label(child.name, systemImage: child.kind.sfSymbol)
                    }
                }
            }
        } label: {
            segmentLabel(segment, isLast: store.segments.last?.id == segment.id)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - UI Components

    private func segmentLabel(_ segment: BreadcrumbStore.Segment, isLast: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: segment.icon)
                .font(.system(size: 9))
                .foregroundColor(iconColor(for: segment))
            Text(segment.label)
                .font(.system(size: 11, weight: isLast ? .medium : .regular))
                .foregroundStyle(isLast ? .primary : .secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.primary.opacity(0.04))
        )
        .contentShape(Rectangle())
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.quaternary)
    }

    private func iconColor(for segment: BreadcrumbStore.Segment) -> Color {
        switch segment.kind {
        case .folder: return .secondary
        case .file: return .blue
        case .symbol(let sym):
            if sym.kind.isType { return .purple }
            if sym.kind.isCallable { return .orange }
            return .green
        }
    }
}

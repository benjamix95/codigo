import SwiftUI
import CoderEngine

// MARK: - Minimap View

/// Code overview laterale con highlight delle regioni visibili e click-to-scroll.
struct MinimapView: View {
    let renderData: MinimapRenderer.RenderData
    var onScrollToLine: ((Int) -> Void)?

    @State private var hoveredRegion: String?

    private let minimapWidth: CGFloat = 60

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            ZStack(alignment: .topLeading) {
                // Background
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))

                // Regioni simboli
                ForEach(renderData.regions) { region in
                    regionRect(region, totalHeight: height)
                }

                // Viewport indicator
                viewportOverlay(totalHeight: height)
            }
            .frame(width: minimapWidth)
            .contentShape(Rectangle())
            .onTapGesture { location in
                handleTap(at: location.y, totalHeight: height)
            }
        }
        .frame(width: minimapWidth)
    }

    // MARK: - Regioni

    private func regionRect(_ region: MinimapRenderer.Region, totalHeight: CGFloat) -> some View {
        let y = MinimapRenderer.normalizedY(
            line: region.startLine,
            totalLines: renderData.totalLines
        ) * totalHeight
        let h = MinimapRenderer.normalizedHeight(
            startLine: region.startLine,
            endLine: region.endLine,
            totalLines: renderData.totalLines
        ) * totalHeight

        let isHovered = hoveredRegion == region.id
        let indent = CGFloat(region.depth) * 4

        return Rectangle()
            .fill(regionColor(region, isHovered: isHovered))
            .frame(width: minimapWidth - 8 - indent, height: max(h, 1))
            .offset(x: 4 + indent, y: y)
            .onHover { hovering in
                hoveredRegion = hovering ? region.id : nil
            }
            .help(region.label)
    }

    private func regionColor(_ region: MinimapRenderer.Region, isHovered: Bool) -> Color {
        Color(
            hue: region.kind.hue,
            saturation: isHovered ? 0.7 : 0.4,
            brightness: isHovered ? 0.9 : 0.7
        )
        .opacity(isHovered ? 0.6 : 0.3)
    }

    // MARK: - Viewport Overlay

    private func viewportOverlay(totalHeight: CGFloat) -> some View {
        let startY = MinimapRenderer.normalizedY(
            line: renderData.viewport.startLine,
            totalLines: renderData.totalLines
        ) * totalHeight
        let endY = MinimapRenderer.normalizedY(
            line: renderData.viewport.endLine,
            totalLines: renderData.totalLines
        ) * totalHeight
        let height = max(endY - startY, 8)

        return Rectangle()
            .fill(Color.accentColor.opacity(0.15))
            .overlay(
                Rectangle()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
            .frame(width: minimapWidth, height: height)
            .offset(y: startY)
    }

    // MARK: - Interazione

    private func handleTap(at y: CGFloat, totalHeight: CGFloat) {
        guard totalHeight > 0 else { return }
        let normalizedY = y / totalHeight
        let line = MinimapRenderer.lineFromNormalizedY(normalizedY, totalLines: renderData.totalLines)
        onScrollToLine?(line)
    }
}

// MARK: - Minimap Store

/// Store per gestire lo stato della minimap collegata all'editor.
@MainActor
final class MinimapStore: ObservableObject {
    @Published var renderData: MinimapRenderer.RenderData?
    @Published var isVisible: Bool

    private var currentFilePath: String?
    private var rootPaths: [String] = []
    private weak var codebaseIndex: CodebaseIndex?

    init(isVisible: Bool = true) {
        self.isVisible = isVisible
    }

    func configure(codebaseIndex: CodebaseIndex, rootPaths: [String]) {
        self.codebaseIndex = codebaseIndex
        self.rootPaths = rootPaths
    }

    /// Aggiorna la minimap per il file corrente.
    func update(filePath: String, totalLines: Int, visibleRange: ClosedRange<Int>) async {
        currentFilePath = filePath

        let symbols = await loadSymbols(filePath: filePath)
        let viewport = MinimapRenderer.Viewport(
            startLine: visibleRange.lowerBound,
            endLine: visibleRange.upperBound
        )

        renderData = MinimapRenderer.render(
            symbols: symbols,
            totalLines: totalLines,
            viewport: viewport
        )
    }

    /// Aggiorna solo la viewport senza ricaricare i simboli.
    func updateViewport(visibleRange: ClosedRange<Int>) {
        guard let data = renderData else { return }
        let viewport = MinimapRenderer.Viewport(
            startLine: visibleRange.lowerBound,
            endLine: visibleRange.upperBound
        )
        renderData = MinimapRenderer.RenderData(
            totalLines: data.totalLines,
            regions: data.regions,
            viewport: viewport
        )
    }

    func toggle() {
        isVisible.toggle()
        UserDefaults.standard.set(isVisible, forKey: "minimap_visible")
    }

    // MARK: - Privato

    private func loadSymbols(filePath: String) async -> [IndexedSymbol] {
        guard let index = codebaseIndex else { return [] }

        var relativePath = filePath
        for root in rootPaths {
            if filePath.hasPrefix(root + "/") {
                relativePath = String(filePath.dropFirst(root.count + 1))
                break
            }
        }

        return await index.symbolsInFile(relativePath)
    }
}

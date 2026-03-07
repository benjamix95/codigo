import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Mermaid Diagram Card View

struct MermaidDiagramView: View {
    let mermaidCode: String
    let accentColor: Color

    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded = true
    @State private var diagramHeight: CGFloat = 200
    @State private var latestDiagramSVG = ""
    @State private var latestDiagramURL: URL?
    @State private var latestDiagramPNGURL: URL?
    @State private var latestDiagramPNGData: Data?
    @State private var isHoveringOpen = false
    @State private var isHoveringSave = false
    @State private var isHoveringCopy = false
    @State private var showCopied = false
    @State private var diagramError: String? = nil
    @State private var reloadToken = UUID()

    private var hasRendered: Bool {
        !latestDiagramSVG.isEmpty || latestDiagramPNGData != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            if isExpanded {
                diagramContent
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(colorScheme == .dark ? 0.35 : 0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 0) {
            // Left: collapse + label
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text("Diagram")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            // Right: actions
            if hasRendered {
                HStack(spacing: 2) {
                    // Copy to clipboard
                    toolbarButton(
                        icon: showCopied ? "checkmark" : "doc.on.doc",
                        tooltip: "Copy PNG to clipboard",
                        isHovering: $isHoveringCopy
                    ) {
                        copyToClipboard()
                    }

                    // Open externally
                    toolbarButton(
                        icon: "arrow.up.right.square",
                        tooltip: "Open in Preview",
                        isHovering: $isHoveringOpen
                    ) {
                        openDiagram()
                    }

                    // Save
                    toolbarButton(
                        icon: "arrow.down.to.line",
                        tooltip: "Save as PNG",
                        isHovering: $isHoveringSave
                    ) {
                        saveDiagram()
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func toolbarButton(
        icon: String,
        tooltip: String,
        isHovering: Binding<Bool>,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovering.wrappedValue ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering.wrappedValue = $0 }
        .help(tooltip)
    }

    // MARK: - Diagram Content

    private var diagramContent: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)

            if let errorMessage = diagramError {
                diagramErrorView(errorMessage)
            } else {
                MermaidWebView(
                    mermaidCode: mermaidCode,
                    accentColor: accentColor,
                    isDarkMode: colorScheme == .dark,
                    onImageRendered: { svg in
                        diagramError = nil
                        latestDiagramSVG = svg
                        latestDiagramURL = writeTempFile(svg.data(using: .utf8), ext: "svg", replacing: latestDiagramURL)
                    },
                    onImageRenderedPNG: { png in
                        diagramError = nil
                        latestDiagramPNGData = png
                        latestDiagramPNGURL = writeTempFile(png, ext: "png", replacing: latestDiagramPNGURL)
                    },
                    onHeightChanged: { h in
                        withAnimation(.easeOut(duration: 0.15)) {
                            diagramHeight = min(max(h, 100), 800)
                        }
                    },
                    onError: { error in
                        diagramError = error
                    }
                )
                .id(reloadToken)
                .frame(height: diagramHeight)
            }
        }
    }

    private func diagramErrorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.orange)

                Text("Diagram rendering failed")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Text(message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(6)

            Button {
                diagramError = nil
                reloadToken = UUID()
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(12)
    }

    // MARK: - Actions

    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()

        if let pngData = latestDiagramPNGData, let image = NSImage(data: pngData) {
            pb.writeObjects([image])
        } else if !latestDiagramSVG.isEmpty, let data = latestDiagramSVG.data(using: .utf8) {
            pb.setData(data, forType: .init("public.svg-image"))
        } else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) { showCopied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) { showCopied = false }
        }
    }

    private func openDiagram() {
        let url = latestDiagramPNGURL ?? latestDiagramURL ?? {
            guard !latestDiagramSVG.isEmpty else { return nil }
            let u = writeTempFile(latestDiagramSVG.data(using: .utf8), ext: "svg")
            latestDiagramURL = u
            return u
        }()
        if let url { NSWorkspace.shared.open(url) }
    }

    private func saveDiagram() {
        guard hasRendered else { return }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "diagram.png"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if let pngData = latestDiagramPNGData {
                try pngData.write(to: url, options: .atomic)
            } else if let svgData = latestDiagramSVG.data(using: .utf8) {
                // Fallback: save as SVG if PNG not ready
                let svgUrl = url.deletingPathExtension().appendingPathExtension("svg")
                try svgData.write(to: svgUrl, options: .atomic)
            }
        } catch {
            assertionFailure("Failed to save diagram: \(error)")
        }
    }

    // MARK: - Helpers

    private func writeTempFile(_ data: Data?, ext: String, replacing oldURL: URL? = nil) -> URL? {
        guard let data else { return nil }
        if let oldURL { try? FileManager.default.removeItem(at: oldURL) }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mermaid-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

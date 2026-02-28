import SwiftUI
import AppKit
import WebKit
import UniformTypeIdentifiers

// MARK: - Mermaid Diagram Extraction

enum MermaidExtractor {
    /// Extract all ```mermaid code blocks from markdown content.
    static func extractMermaidBlocks(from markdown: String) -> [String] {
        var blocks: [String] = []
        let pattern = "```mermaid\\s*\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return blocks
        }
        let nsString = markdown as NSString
        let results = regex.matches(in: markdown, range: NSRange(location: 0, length: nsString.length))
        for match in results {
            if match.numberOfRanges >= 2 {
                let range = match.range(at: 1)
                let block = nsString.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
                if !block.isEmpty {
                    blocks.append(block)
                }
            }
        }
        return blocks
    }

    /// Remove mermaid code blocks from markdown, returning clean markdown.
    static func stripMermaidBlocks(from markdown: String) -> String {
        let pattern = "```mermaid\\s*\\n[\\s\\S]*?```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return markdown
        }
        let nsString = markdown as NSString
        return regex.stringByReplacingMatches(
            in: markdown,
            range: NSRange(location: 0, length: nsString.length),
            withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Mermaid WebView (renders via mermaid.js CDN)

struct MermaidWebView: NSViewRepresentable {
    let mermaidCode: String
    let accentColor: Color
    let isDarkMode: Bool
    let onImageRendered: ((String) -> Void)?
    let onImageRenderedPNG: ((Data) -> Void)?
    let onHeightChanged: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "mermaidImageBridge")
        config.userContentController = contentController
        config.preferences.setValue(true, forKey: "javaScriptEnabled")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        loadMermaid(webView: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastRenderedCode != mermaidCode {
            context.coordinator.lastRenderedCode = mermaidCode
            loadMermaid(webView: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onImageRendered: onImageRendered,
            onImageRenderedPNG: onImageRenderedPNG,
            onHeightChanged: onHeightChanged
        )
    }

    private func loadMermaid(webView: WKWebView) {
        let escapedCode = mermaidCode.htmlEscapedForMermaid
        let palette = isDarkMode ? MermaidPalette.dark : MermaidPalette.light

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body {
                    background: transparent;
                    overflow: hidden;
                    width: 100%;
                    height: auto;
                }
                body {
                    display: flex;
                    justify-content: center;
                    align-items: flex-start;
                    padding: 16px;
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", system-ui, sans-serif;
                    -webkit-font-smoothing: antialiased;
                }
                #mermaid-container {
                    width: 100%;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 60px;
                }
                #mermaid-container svg {
                    width: 100%;
                    height: auto;
                    max-width: 100%;
                    display: block;
                }
                .error {
                    color: \(palette.errorColor);
                    font-size: 12px;
                    padding: 12px 16px;
                    text-align: center;
                    font-weight: 500;
                    background: \(palette.errorBg);
                    border-radius: 8px;
                    border: 1px solid \(palette.errorBorder);
                }
                /* Mermaid overrides for cleaner look */
                .node rect, .node circle, .node polygon, .node ellipse {
                    transition: filter 0.15s ease;
                }
                .edgeLabel {
                    font-size: 12px !important;
                }
                .label {
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif !important;
                }
            </style>
        </head>
        <body>
            <div id="mermaid-container">
                <pre class="mermaid">\(escapedCode)</pre>
            </div>
            <script type="module">
                import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';

                const postToHost = (type, payload = '') => {
                    try {
                        window.webkit?.messageHandlers?.mermaidImageBridge?.postMessage({ type, payload });
                    } catch (e) {}
                };

                mermaid.initialize({
                    startOnLoad: true,
                    theme: 'base',
                    themeVariables: {
                        primaryColor: '\(palette.primaryColor)',
                        fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Display", system-ui, sans-serif',
                        fontSize: '13px',
                        textColor: '\(palette.textColor)',
                        primaryTextColor: '\(palette.primaryTextColor)',
                        primaryBorderColor: '\(palette.primaryBorderColor)',
                        lineColor: '\(palette.lineColor)',
                        secondaryColor: '\(palette.secondaryColor)',
                        tertiaryColor: '\(palette.tertiaryColor)',
                        mainBkg: '\(palette.nodeBg)',
                        nodeBorder: '\(palette.nodeBorder)',
                        clusterBkg: '\(palette.clusterBkg)',
                        clusterBorder: '\(palette.clusterBorder)',
                        titleColor: '\(palette.titleColor)',
                        edgeLabelBackground: '\(palette.edgeLabelBg)',
                        nodeTextColor: '\(palette.nodeTextColor)',
                        background: '\(palette.canvasBg)',
                        secondaryBorderColor: '\(palette.secondaryBorderColor)',
                        noteBkgColor: '\(palette.noteBg)',
                        noteTextColor: '\(palette.noteTextColor)',
                        noteBorderColor: '\(palette.noteBorderColor)',
                        actorBkg: '\(palette.nodeBg)',
                        actorTextColor: '\(palette.nodeTextColor)',
                        actorBorder: '\(palette.nodeBorder)',
                        actorLineColor: '\(palette.lineColor)',
                        signalColor: '\(palette.lineColor)',
                        signalTextColor: '\(palette.textColor)',
                        labelBoxBkgColor: '\(palette.edgeLabelBg)',
                        labelBoxBorderColor: '\(palette.primaryBorderColor)',
                        labelTextColor: '\(palette.textColor)',
                        loopTextColor: '\(palette.textColor)',
                        activationBkgColor: '\(palette.activationBg)',
                        activationBorderColor: '\(palette.primaryBorderColor)',
                        sequenceNumberColor: '\(palette.sequenceNumberColor)'
                    },
                    flowchart: {
                        useMaxWidth: true,
                        htmlLabels: true,
                        curve: 'basis',
                        nodeSpacing: 50,
                        rankSpacing: 55,
                        padding: 16,
                        defaultRenderer: 'dagre-wrapper'
                    },
                    sequence: {
                        actorMargin: 50,
                        width: 180,
                        diagramMarginX: 20,
                        diagramMarginY: 20,
                        noteMargin: 10,
                        messageMargin: 40,
                        mirrorActors: true,
                        showSequenceNumbers: false
                    },
                    class: {
                        titleTopMargin: 16,
                        useMaxWidth: true
                    },
                    er: {
                        useMaxWidth: true,
                        fontSize: 12
                    },
                    gantt: {
                        useMaxWidth: true,
                        fontSize: 12,
                        barHeight: 24,
                        barGap: 6,
                        topPadding: 40,
                        sectionFontSize: 13
                    },
                    pie: {
                        useMaxWidth: true,
                        textPosition: 0.75
                    },
                    state: {
                        useMaxWidth: true
                    },
                    securityLevel: 'loose',
                    fontFamily: '-apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif'
                });

                const ensureDiagramReady = (attempt = 0) => {
                    const svg = document.querySelector('#mermaid-container svg');
                    if (!svg) {
                        if (attempt < 100) {
                            requestAnimationFrame(() => ensureDiagramReady(attempt + 1));
                        }
                        return;
                    }

                    // Clean up SVG for proper sizing
                    svg.removeAttribute('height');
                    svg.style.maxWidth = '100%';
                    svg.style.height = 'auto';

                    // Report content height to host
                    requestAnimationFrame(() => {
                        const rect = svg.getBoundingClientRect();
                        const totalHeight = Math.ceil(rect.height) + 32; // +padding
                        postToHost('height', String(totalHeight));
                    });

                    // Generate export SVG
                    const generateExportSVG = () => {
                        const clone = svg.cloneNode(true);
                        const bounds = svg.getBBox();
                        const pad = 32;
                        const w = Math.max(1, Math.ceil((bounds.width || svg.getBoundingClientRect().width) + pad * 2));
                        const h = Math.max(1, Math.ceil((bounds.height || svg.getBoundingClientRect().height) + pad * 2));
                        const ox = Math.floor((bounds.x || 0) - pad);
                        const oy = Math.floor((bounds.y || 0) - pad);

                        clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
                        clone.setAttribute('xmlns:xlink', 'http://www.w3.org/1999/xlink');
                        clone.setAttribute('width', String(w));
                        clone.setAttribute('height', String(h));
                        clone.setAttribute('viewBox', `${ox} ${oy} ${w} ${h}`);
                        clone.removeAttribute('style');

                        // Add background
                        const bg = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
                        bg.setAttribute('x', String(ox));
                        bg.setAttribute('y', String(oy));
                        bg.setAttribute('width', String(w));
                        bg.setAttribute('height', String(h));
                        bg.setAttribute('fill', '\(palette.exportBg)');
                        clone.insertBefore(bg, clone.firstChild);

                        return new XMLSerializer().serializeToString(clone);
                    };

                    const exportedSVG = generateExportSVG();
                    postToHost('rendered', exportedSVG);

                    // High quality PNG
                    const scale = 4;
                    const img = new Image();
                    const blob = new Blob([exportedSVG], { type: 'image/svg+xml;charset=utf-8' });
                    const blobURL = URL.createObjectURL(blob);
                    img.onload = () => {
                        const rect = svg.getBoundingClientRect();
                        const cw = Math.max(1, Math.ceil(rect.width * scale));
                        const ch = Math.max(1, Math.ceil(rect.height * scale));
                        const canvas = document.createElement('canvas');
                        canvas.width = cw;
                        canvas.height = ch;
                        const ctx = canvas.getContext('2d');
                        if (!ctx) { URL.revokeObjectURL(blobURL); return; }
                        ctx.setTransform(scale, 0, 0, scale, 0, 0);
                        ctx.imageSmoothingEnabled = true;
                        ctx.imageSmoothingQuality = 'high';
                        ctx.drawImage(img, 0, 0, Math.ceil(rect.width), Math.ceil(rect.height));
                        postToHost('renderedPNG', canvas.toDataURL('image/png'));
                        URL.revokeObjectURL(blobURL);
                    };
                    img.onerror = () => URL.revokeObjectURL(blobURL);
                    img.src = blobURL;
                };

                requestAnimationFrame(ensureDiagramReady);
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastRenderedCode: String?
        private let onImageRendered: ((String) -> Void)?
        private let onImageRenderedPNG: ((Data) -> Void)?
        private let onHeightChanged: ((CGFloat) -> Void)?

        init(
            onImageRendered: ((String) -> Void)?,
            onImageRenderedPNG: ((Data) -> Void)?,
            onHeightChanged: ((CGFloat) -> Void)?
        ) {
            self.onImageRendered = onImageRendered
            self.onImageRenderedPNG = onImageRenderedPNG
            self.onHeightChanged = onHeightChanged
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "mermaidImageBridge", let body = message.body as? [String: Any] else { return }
            guard let type = body["type"] as? String else { return }
            let payload = body["payload"] as? String

            switch type {
            case "rendered":
                if let payload = payload {
                    Task { @MainActor in self.onImageRendered?(payload) }
                }
            case "renderedPNG":
                if let payload = payload, payload.hasPrefix("data:image/png;base64,") {
                    let base64 = String(payload.dropFirst("data:image/png;base64,".count))
                    if let pngData = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
                        Task { @MainActor in self.onImageRenderedPNG?(pngData) }
                    }
                }
            case "height":
                if let payload = payload, let h = Double(payload) {
                    Task { @MainActor in self.onHeightChanged?(CGFloat(h)) }
                }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

// MARK: - Theme Palette

private struct MermaidPalette {
    // Node colors
    let primaryColor: String
    let primaryTextColor: String
    let primaryBorderColor: String
    let lineColor: String
    let secondaryColor: String
    let tertiaryColor: String
    let nodeBg: String
    let nodeBorder: String
    let nodeTextColor: String
    let clusterBkg: String
    let clusterBorder: String
    let titleColor: String
    let edgeLabelBg: String
    let textColor: String
    let canvasBg: String
    let secondaryBorderColor: String

    // Sequence diagram
    let noteBg: String
    let noteTextColor: String
    let noteBorderColor: String
    let activationBg: String
    let sequenceNumberColor: String

    // Export
    let exportBg: String

    // Card UI
    let cardBg: String
    let cardBorder: String
    let headerBg: String
    let toolbarBg: String
    let toolbarBorder: String
    let toolbarIconColor: String
    let toolbarIconHover: String
    let labelColor: String
    let labelSecondary: String

    // Error
    let errorColor: String
    let errorBg: String
    let errorBorder: String

    // MARK: - Light

    static let light = MermaidPalette(
        primaryColor: "#4F8FF7",
        primaryTextColor: "#1a1a2e",
        primaryBorderColor: "#B8C9E0",
        lineColor: "#8B99AD",
        secondaryColor: "#F5F7FA",
        tertiaryColor: "#EDF0F5",
        nodeBg: "#FFFFFF",
        nodeBorder: "#D0D7E2",
        nodeTextColor: "#1a1a2e",
        clusterBkg: "#F7F9FC",
        clusterBorder: "#D0D7E2",
        titleColor: "#1a1a2e",
        edgeLabelBg: "#FFFFFF",
        textColor: "#374151",
        canvasBg: "#FFFFFF",
        secondaryBorderColor: "#D0D7E2",
        noteBg: "#FEF9E7",
        noteTextColor: "#5D4E37",
        noteBorderColor: "#E8DCC8",
        activationBg: "#E8F0FE",
        sequenceNumberColor: "#FFFFFF",
        exportBg: "#FFFFFF",
        cardBg: "transparent",
        cardBorder: "#E5E7EB",
        headerBg: "transparent",
        toolbarBg: "#F3F4F6",
        toolbarBorder: "#E5E7EB",
        toolbarIconColor: "#6B7280",
        toolbarIconHover: "#374151",
        labelColor: "#374151",
        labelSecondary: "#9CA3AF",
        errorColor: "#DC2626",
        errorBg: "#FEF2F2",
        errorBorder: "#FECACA"
    )

    // MARK: - Dark

    static let dark = MermaidPalette(
        primaryColor: "#6BA1F7",
        primaryTextColor: "#E5E7EB",
        primaryBorderColor: "#3D4F66",
        lineColor: "#6B7A8D",
        secondaryColor: "#1A2233",
        tertiaryColor: "#243044",
        nodeBg: "#1C2537",
        nodeBorder: "#334155",
        nodeTextColor: "#E5E7EB",
        clusterBkg: "#141D2E",
        clusterBorder: "#2D3B50",
        titleColor: "#F3F4F6",
        edgeLabelBg: "#1C2537",
        textColor: "#D1D5DB",
        canvasBg: "#0F1724",
        secondaryBorderColor: "#334155",
        noteBg: "#2A2520",
        noteTextColor: "#E5D9C3",
        noteBorderColor: "#4A4030",
        activationBg: "#1E2D47",
        sequenceNumberColor: "#E5E7EB",
        exportBg: "#0F1724",
        cardBg: "transparent",
        cardBorder: "#1F2937",
        headerBg: "transparent",
        toolbarBg: "#1F2937",
        toolbarBorder: "#374151",
        toolbarIconColor: "#9CA3AF",
        toolbarIconHover: "#E5E7EB",
        labelColor: "#E5E7EB",
        labelSecondary: "#6B7280",
        errorColor: "#F87171",
        errorBg: "#1C1517",
        errorBorder: "#7F1D1D"
    )
}

private extension String {
    var htmlEscapedForMermaid: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

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

            MermaidWebView(
                mermaidCode: mermaidCode,
                accentColor: accentColor,
                isDarkMode: colorScheme == .dark,
                onImageRendered: { svg in
                    latestDiagramSVG = svg
                    latestDiagramURL = writeTempFile(svg.data(using: .utf8), ext: "svg")
                },
                onImageRenderedPNG: { png in
                    latestDiagramPNGData = png
                    latestDiagramPNGURL = writeTempFile(png, ext: "png")
                },
                onHeightChanged: { h in
                    withAnimation(.easeOut(duration: 0.15)) {
                        diagramHeight = min(max(h, 100), 800)
                    }
                }
            )
            .frame(height: diagramHeight)
        }
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

        if latestDiagramPNGData != nil {
            panel.allowedContentTypes = [.png, .svg]
            panel.nameFieldStringValue = "diagram.png"
        } else {
            panel.allowedContentTypes = [.svg]
            panel.nameFieldStringValue = "diagram.svg"
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if url.pathExtension.lowercased() == "png", let pngData = latestDiagramPNGData {
                try pngData.write(to: url, options: .atomic)
            } else if let svgData = latestDiagramSVG.data(using: .utf8) {
                try svgData.write(to: url, options: .atomic)
            }
        } catch {}
    }

    // MARK: - Helpers

    private func writeTempFile(_ data: Data?, ext: String) -> URL? {
        guard let data else { return nil }
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

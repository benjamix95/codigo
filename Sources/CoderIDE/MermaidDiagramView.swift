import SwiftUI
import WebKit

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

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
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
        Coordinator()
    }

    private func loadMermaid(webView: WKWebView) {
        let escapedCode = mermaidCode.htmlEscapedForMermaid

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    background: transparent;
                    display: flex;
                    justify-content: center;
                    align-items: flex-start;
                    padding: 8px;
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    overflow: hidden;
                }
                #mermaid-container {
                    width: 100%;
                    display: flex;
                    justify-content: center;
                }
                #mermaid-container svg {
                    max-width: 100%;
                    height: auto;
                }
                .error {
                    color: #ef4444;
                    font-size: 12px;
                    padding: 8px;
                    text-align: center;
                }
            </style>
        </head>
        <body>
            <div id="mermaid-container">
                <pre class="mermaid">\(escapedCode)</pre>
            </div>
            <script type="module">
                import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
                mermaid.initialize({
                    startOnLoad: true,
                    theme: 'base',
                    themeVariables: {
                        primaryColor: '#cfd3da',
                        primaryTextColor: '#1f2937',
                        primaryBorderColor: '#94a3b8',
                        lineColor: '#64748b',
                        secondaryColor: '#f8fafc',
                        tertiaryColor: '#e2e8f0',
                        mainBkg: '#ffffff',
                        nodeBorder: '#94a3b8',
                        clusterBkg: '#f1f5f9',
                        titleColor: '#1f2937',
                        edgeLabelBackground: '#f8fafc',
                        nodeTextColor: '#1f2937',
                        background: '#ffffff',
                        textColor: '#1f2937'
                    },
                    flowchart: {
                        useMaxWidth: true,
                        htmlLabels: true,
                        curve: 'linear'
                    },
                    securityLevel: 'loose',
                    fontFamily: '-apple-system, BlinkMacSystemFont, sans-serif'
                });

                // After render, resize body to content
                requestAnimationFrame(() => {
                    const svg = document.querySelector('#mermaid-container svg');
                    if (svg) {
                        const rect = svg.getBoundingClientRect();
                        document.body.style.height = rect.height + 16 + 'px';
                    }
                });
            </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var lastRenderedCode: String?

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

private extension String {
    var htmlEscapedForMermaid: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

// MARK: - Mermaid Diagram Card View (used in Plan Panel)

struct MermaidDiagramView: View {
    let mermaidCode: String
    let accentColor: Color

    @State private var isExpanded = true
    @State private var diagramHeight: CGFloat = 250

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentColor)

                    Text("Flow Diagram")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Rectangle()
                    .fill(accentColor.opacity(0.15))
                    .frame(height: 0.5)

                MermaidWebView(
                    mermaidCode: mermaidCode,
                    accentColor: accentColor
                )
                .frame(height: diagramHeight)
                .clipShape(RoundedRectangle(cornerRadius: 0))
            }
        }
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.25),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(accentColor.opacity(0.2), lineWidth: 0.5)
        )
    }
}

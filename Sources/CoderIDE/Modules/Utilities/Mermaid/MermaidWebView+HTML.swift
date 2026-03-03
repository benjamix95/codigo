import Foundation

extension MermaidWebView {
    static func renderingHTML(for escapedCode: String, isDarkMode: Bool) -> String {
        let palette = isDarkMode ? MermaidPalette.dark : MermaidPalette.light

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset=\"utf-8\">
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
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
                .node rect {
                    rx: 10 !important;
                    ry: 10 !important;
                }
                .cluster rect {
                    rx: 12 !important;
                    ry: 12 !important;
                }
                .edgeLabel {
                    font-size: 12px !important;
                }
                .edgeLabel rect {
                    rx: 6 !important;
                    ry: 6 !important;
                }
                .label {
                    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif !important;
                }
            </style>
        </head>
        <body>
            <div id=\"mermaid-container\">
                <pre class=\"mermaid\">\(escapedCode)</pre>
            </div>
            <script type=\"module\">
                const postToHost = (type, payload = '') => {
                    try {
                        window.webkit?.messageHandlers?.mermaidImageBridge?.postMessage({ type, payload });
                    } catch (e) {}
                };

                const setError = (message) => {
                    const container = document.getElementById('mermaid-container');
                    if (container) {
                        container.innerHTML = `<div class=\"error\">${message}</div>`;
                    }
                    postToHost('height', '120');
                    postToHost('error', message);
                };

                const loadMermaid = async () => {
                    const sources = [
                        'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs',
                        'https://unpkg.com/mermaid@11/dist/mermaid.esm.min.mjs'
                    ];
                    let lastError = null;
                    for (const source of sources) {
                        try {
                            const mod = await import(source);
                            return mod.default ?? mod;
                        } catch (error) {
                            lastError = error;
                        }
                    }
                    throw lastError ?? new Error('Unable to load mermaid runtime');
                };

                const mermaidConfig = {
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
                        diagramPadding: 12,
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
                };

                const ensureDiagramReady = (attempt = 0) => {
                    const svg = document.querySelector('#mermaid-container svg');
                    if (!svg) {
                        if (attempt < 100) {
                            requestAnimationFrame(() => ensureDiagramReady(attempt + 1));
                        } else {
                            setError('Unable to render Mermaid diagram. Check syntax/runtime.');
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

                    try {
                        const exportedSVG = generateExportSVG();
                        postToHost('rendered', exportedSVG);

                        // High quality PNG from the export SVG (which includes background)
                        const scale = 4;
                        const img = new Image();
                        const blob = new Blob([exportedSVG], { type: 'image/svg+xml;charset=utf-8' });
                        const blobURL = URL.createObjectURL(blob);
                        img.onload = () => {
                            // Use the image's natural dimensions (from the export SVG viewBox)
                            const naturalW = img.naturalWidth || img.width;
                            const naturalH = img.naturalHeight || img.height;
                            const cw = Math.max(1, Math.ceil(naturalW * scale));
                            const ch = Math.max(1, Math.ceil(naturalH * scale));
                            const canvas = document.createElement('canvas');
                            canvas.width = cw;
                            canvas.height = ch;
                            const ctx = canvas.getContext('2d');
                            if (!ctx) { URL.revokeObjectURL(blobURL); return; }
                            ctx.imageSmoothingEnabled = true;
                            ctx.imageSmoothingQuality = 'high';
                            ctx.drawImage(img, 0, 0, cw, ch);
                            postToHost('renderedPNG', canvas.toDataURL('image/png'));
                            URL.revokeObjectURL(blobURL);
                        };
                        img.onerror = () => URL.revokeObjectURL(blobURL);
                        img.src = blobURL;
                    } catch (error) {
                        setError('Failed to export Mermaid diagram.');
                    }
                };

                (async () => {
                    try {
                        const mermaid = await loadMermaid();
                        mermaid.initialize(mermaidConfig);
                        requestAnimationFrame(ensureDiagramReady);
                    } catch (error) {
                        setError('Mermaid runtime unavailable (offline/CDN blocked).');
                    }
                })();
            </script>
        </body>
        </html>
        """
    }
}

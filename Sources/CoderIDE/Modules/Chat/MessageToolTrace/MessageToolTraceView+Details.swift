import SwiftUI

extension MessageToolTraceView {
    // MARK: - Expanded Details

    @ViewBuilder
    func expandedDetails(for event: ToolTraceEvent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let command = event.payload["command"], !command.isEmpty {
                codeBlock(label: "Command", value: command)
            }
            if let query = event.payload["query"], !query.isEmpty {
                detailPill(label: "Query", value: query)
            }
            if let path = event.payload["path"] ?? event.payload["file"], !path.isEmpty {
                HStack(spacing: 4) {
                    Text("Path")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Button {
                        onOpenFile(path)
                    } label: {
                        Text(path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.info)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let tool = event.payload["tool"], !tool.isEmpty {
                detailPill(label: "Tool", value: tool)
            }
            if let server = event.payload["mcp_server"] ?? event.payload["server_id"], !server.isEmpty {
                detailPill(label: "MCP Server", value: server)
            }
            if let mcpTool = event.payload["mcp_tool"], !mcpTool.isEmpty {
                detailPill(label: "MCP Tool", value: mcpTool)
            }
            if let latency = event.payload["mcp_latency_ms"], !latency.isEmpty {
                detailPill(label: "Latency", value: "\(latency)ms")
            }
            if let uri = event.payload["uri"], !uri.isEmpty {
                detailPill(label: "URI", value: uri)
            }
            if let promptName = event.payload["prompt_name"], !promptName.isEmpty {
                detailPill(label: "Prompt", value: promptName)
            }
            if let output = event.payload["output"], !output.isEmpty {
                if output.hasPrefix("data:image/png;base64,") {
                    browserScreenshotBlock(base64: String(output.dropFirst("data:image/png;base64,".count)))
                } else {
                    codeBlock(label: "Output", value: String(output.prefix(4000)))
                }
            }
            if let diffPreview = nonEmpty(
                event.payload["diffPreview"]
                    ?? event.payload["diff"]
                    ?? event.payload["patch"]
                    ?? event.payload["unified_diff"]
                    ?? event.payload["changes_preview"]
            ) {
                diffBlock(diffPreview)
            }
            if let status = event.payload["status"], !status.isEmpty, status.lowercased() != "completed" {
                detailPill(label: "Status", value: status)
            }
            if let notes = event.payload["notes"], !notes.isEmpty {
                detailPill(label: "Notes", value: notes)
            }
        }
    }

    // MARK: - UI Components

    @ViewBuilder
    func browserScreenshotBlock(base64: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.browserColor)
                Text("Browser Screenshot")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            if let data = Data(base64Encoded: base64),
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 480, maxHeight: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            } else {
                Text("(screenshot data unavailable)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
        }
    }

    func detailPill(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textSelection(.enabled)
                .lineLimit(3)
        }
    }

    func codeBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textSelection(.enabled)
                .lineLimit(nil)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.5))
                )
        }
    }

    @ViewBuilder
    func diffBlock(_ diff: String) -> some View {
        Text(buildDiffAttributed(diff))
            .font(.system(size: 10, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.5))
            )
    }
}

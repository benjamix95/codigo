import SwiftUI

// MARK: - Inline Terminal View

/// Embedded terminal view for bash/command trace cards.
/// Shows command prompt, live output with auto-scroll, and exit code badge.
struct InlineTerminalView: View {
    let command: String
    let output: String?
    let stderr: String?
    let exitCode: String?
    let cwd: String?
    let isRunning: Bool

    private let terminalBg = Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1.0))
    private let promptColor = Color(nsColor: NSColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 1.0))
    private let cwdColor = Color(nsColor: NSColor(red: 0.45, green: 0.65, blue: 0.95, alpha: 1.0))
    private let outputColor = Color(nsColor: NSColor(red: 0.82, green: 0.82, blue: 0.84, alpha: 1.0))
    private let stderrColor = Color(nsColor: NSColor(red: 0.95, green: 0.40, blue: 0.38, alpha: 1.0))
    private let termFont = Font.system(size: 10.5, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Title bar
            titleBar
            // Terminal content
            terminalContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 6) {
            // Traffic light dots
            HStack(spacing: 4) {
                Circle().fill(Color.red.opacity(0.7)).frame(width: 7, height: 7)
                Circle().fill(Color.yellow.opacity(0.7)).frame(width: 7, height: 7)
                Circle().fill(Color.green.opacity(0.7)).frame(width: 7, height: 7)
            }

            Spacer()

            if let cwd, !cwd.isEmpty {
                Text(shortenPath(cwd))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }

            Spacer()

            exitCodeBadge
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: NSColor(red: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)))
    }

    // MARK: - Exit Code Badge

    @ViewBuilder
    private var exitCodeBadge: some View {
        if isRunning {
            HStack(spacing: 3) {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.55)
                    .frame(width: 10, height: 10)
                Text("RUNNING")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.orange.opacity(0.7)))
        } else if let code = exitCode {
            let isSuccess = code == "0"
            Text("EXIT \(code)")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(isSuccess ? Color.green.opacity(0.65) : Color.red.opacity(0.7))
                )
        } else {
            Text("DONE")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.green.opacity(0.65)))
        }
    }

    // MARK: - Terminal Content

    private var terminalContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 2) {
                    // Command prompt line
                    promptLine

                    // Stdout
                    if let output, !output.isEmpty {
                        Text(String(output.prefix(8000)))
                            .font(termFont)
                            .foregroundStyle(outputColor)
                            .textSelection(.enabled)
                    }

                    // Stderr
                    if let stderr, !stderr.isEmpty {
                        Text(String(stderr.prefix(4000)))
                            .font(termFont)
                            .foregroundStyle(stderrColor)
                            .textSelection(.enabled)
                    }

                    // Running indicator
                    if isRunning, (output ?? "").isEmpty {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.5)
                                .frame(width: 8, height: 8)
                            Text("executing...")
                                .font(termFont)
                                .foregroundStyle(Color.white.opacity(0.35))
                        }
                    }

                    // Scroll anchor
                    Color.clear.frame(height: 1).id("terminal_bottom")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 250)
            .background(terminalBg)
            .onAppear {
                proxy.scrollTo("terminal_bottom", anchor: .bottom)
            }
            .onChange(of: output) { _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("terminal_bottom", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Prompt Line

    private var promptLine: some View {
        HStack(spacing: 0) {
            Text("$ ")
                .font(termFont)
                .foregroundStyle(promptColor)
            Text(command)
                .font(termFont)
                .foregroundStyle(Color.white.opacity(0.9))
                .textSelection(.enabled)
        }
    }

    // MARK: - Helpers

    private func shortenPath(_ path: String) -> String {
        let components = path.split(separator: "/")
        guard components.count > 2 else { return path }
        return ".../" + components.suffix(2).joined(separator: "/")
    }
}

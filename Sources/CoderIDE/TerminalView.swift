import SwiftUI
import AppKit
import SwiftTerm

struct TerminalPanelView: View {
    let workingDirectory: String?

    init(workingDirectory: String? = nil) {
        self.workingDirectory = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    var body: some View {
        VStack(spacing: 10) {
            terminalHeader
            TerminalContainerView(workingDirectory: workingDirectory)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(terminalBorder, lineWidth: 0.8)
                )
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(terminalPanelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(terminalBorder.opacity(0.85), lineWidth: 0.7)
        )
    }

    private var terminalHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(terminalAccent)
                Text("Terminale")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            Text(liveBadgeText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(terminalAccent)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(terminalAccent.opacity(0.16), in: Capsule())
            if let path = workingDirectory {
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text(workingDirectoryDisplay(path))
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(terminalBorder.opacity(0.2), in: Capsule())
            }
            Spacer()
            Text(shellDisplay)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(terminalBorder.opacity(0.18), in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(terminalHeaderFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(terminalBorder.opacity(0.75), lineWidth: 0.6)
        )
    }

    private func workingDirectoryDisplay(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }

    private var shellDisplay: String {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        return (shell as NSString).lastPathComponent
    }

    private var liveBadgeText: String { "LIVE" }

    private var terminalPanelFill: SwiftUI.Color {
        SwiftUI.Color(red: 0.07, green: 0.08, blue: 0.11).opacity(0.97)
    }

    private var terminalHeaderFill: SwiftUI.Color {
        SwiftUI.Color(red: 0.10, green: 0.12, blue: 0.16).opacity(0.88)
    }

    private var terminalBorder: SwiftUI.Color {
        SwiftUI.Color(red: 0.29, green: 0.35, blue: 0.43).opacity(0.78)
    }

    private var terminalAccent: SwiftUI.Color {
        SwiftUI.Color(red: 0.31, green: 0.76, blue: 0.99)
    }
}

struct TerminalContainerView: NSViewRepresentable {
    let workingDirectory: String?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        context.coordinator.terminal = view
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1).cgColor
        view.layer?.cornerCurve = .continuous
        view.layer?.cornerRadius = 10
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = "-" + (shell as NSString).lastPathComponent
        view.startProcess(executable: shell, execName: shellName, currentDirectory: workingDirectory)
        view.getTerminal().silentLog = true
        view.font = NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var terminal: LocalProcessTerminalView?
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {}
    }
}

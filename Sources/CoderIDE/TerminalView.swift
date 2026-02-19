import SwiftUI
import AppKit
import SwiftTerm

struct TerminalPanelView: View {
    let workingDirectory: String?

    init(workingDirectory: String? = nil) {
        self.workingDirectory = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            Rectangle().fill(DesignSystem.Colors.border).frame(height: 0.5)
            TerminalContainerView(workingDirectory: workingDirectory)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DesignSystem.Colors.backgroundPrimary)
    }

    private var terminalHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.agentColor)
                Text("Terminale")
                    .font(.system(size: 12, weight: .semibold))
            }
            if let path = workingDirectory {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text(workingDirectoryDisplay(path))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(DesignSystem.Colors.backgroundSecondary.opacity(0.5))
    }

    private func workingDirectoryDisplay(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) { return "~" + path.dropFirst(home.count) }
        return path
    }
}

struct TerminalContainerView: NSViewRepresentable {
    let workingDirectory: String?

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        context.coordinator.terminal = view
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = "-" + (shell as NSString).lastPathComponent
        view.startProcess(executable: shell, execName: shellName, currentDirectory: workingDirectory)
        view.getTerminal().silentLog = true
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
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

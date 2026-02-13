import SwiftUI
import AppKit
import SwiftTerm

struct TerminalPanelView: View {
    let workingDirectory: String?
    @State private var terminalHeight: CGFloat = 0
    
    init(workingDirectory: String? = nil) {
        self.workingDirectory = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Terminal header
            terminalHeader
            
            Divider()
            
            // Terminal content
            TerminalContainerView(workingDirectory: workingDirectory)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private var terminalHeader: some View {
        HStack {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "terminal.fill")
                    .font(.body.bold())
                    .foregroundStyle(DesignSystem.Colors.primary)
                
                Text("Terminale")
                    .font(DesignSystem.Typography.headline)
                
                if let path = workingDirectory {
                    Text("•")
                        .foregroundStyle(DesignSystem.Colors.secondary)
                    Text(workingDirectoryDisplay(path))
                        .font(DesignSystem.Typography.caption.monospaced())
                        .foregroundStyle(DesignSystem.Colors.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            
            Spacer()
            
            // Quick actions
            HStack(spacing: DesignSystem.Spacing.sm) {
                terminalAction("plus", "Nuova scheda") {
                    // Future: new tab
                }
                terminalAction("trash", "Pulisci") {
                    // Future: clear
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
    }
    
    private func workingDirectoryDisplay(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
    
    private func terminalAction(_ icon: String, _ tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
        }
        .buttonStyle(.borderless)
        .help(tooltip)
    }
}

// MARK: - Terminal Container (wrapper for SwiftTerm)
struct TerminalContainerView: NSViewRepresentable {
    let workingDirectory: String?
    
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        context.coordinator.terminal = view
        
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = "-" + (shell as NSString).lastPathComponent
        
        view.startProcess(
            executable: shell,
            execName: shellName,
            currentDirectory: workingDirectory
        )
        view.getTerminal().silentLog = true
        
        // Apply terminal font
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        
        return view
    }
    
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var terminal: LocalProcessTerminalView?
        
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        
        func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {}
    }
}

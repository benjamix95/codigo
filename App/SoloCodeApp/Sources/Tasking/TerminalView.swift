import SwiftUI
import AppKit
import SwiftTerm

final class AutoFollowLocalProcessTerminalView: LocalProcessTerminalView {
    var isAutoFollowEnabled = true
    var sessionId: UUID?
    weak var sessionStore: TerminalSessionStore?

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)

        if let sid = sessionId, let text = String(bytes: slice, encoding: .utf8) {
            DispatchQueue.main.async { [weak self] in
                self?.sessionStore?.appendOutput(sessionId: sid, text: text)
            }
        }

        guard isAutoFollowEnabled else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scroll(toPosition: 1.0)
        }
    }
}

struct TerminalPanelView: View {
    let workingDirectory: String?
    @EnvironmentObject var terminalSessionStore: TerminalSessionStore
    @AppStorage("terminal_auto_follow_output") private var autoFollowOutput = true
    @AppStorage("ui_code_font_family") private var uiCodeFontFamily = FontPreferences.defaultCodeFamily
    @AppStorage("ui_code_font_size") private var uiCodeFontSize = FontPreferences.defaultCodeSize

    init(workingDirectory: String? = nil) {
        self.workingDirectory = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path
    }

    var body: some View {
        VStack(spacing: 0) {
            terminalTabBar
            Divider().opacity(0.15)

            if let session = terminalSessionStore.activeSession {
                TerminalContainerView(
                    sessionId: session.id,
                    workingDirectory: session.workingDirectory ?? workingDirectory,
                    autoFollowOutput: autoFollowOutput,
                    codeFontFamily: uiCodeFontFamily,
                    codeFontSize: FontPreferences.sanitizeSize(uiCodeFontSize, kind: .code)
                )
                .environmentObject(terminalSessionStore)
                .id(session.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("No terminal session")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(terminalPanelFill)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(terminalBorder.opacity(0.5), lineWidth: 0.5)
        )
        .onAppear {
            terminalSessionStore.ensureDefaultSession(cwd: workingDirectory)
        }
    }

    // MARK: - Tab Bar

    private var terminalTabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(terminalSessionStore.sessions) { session in
                        sessionTab(session)
                    }
                }
            }

            Spacer()

            addToChatButton

            Button {
                terminalSessionStore.createSession(
                    label: "Shell \(terminalSessionStore.sessions.count + 1)",
                    cwd: workingDirectory,
                    isAgent: false
                )
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(terminalAccent)
                    .padding(5)
            }
            .buttonStyle(.plain)
            .help("New terminal")
            .padding(.trailing, 8)
        }
        .frame(height: 32)
        .background(terminalHeaderFill)
    }

    private func sessionTab(_ session: TerminalSession) -> some View {
        let isActive = terminalSessionStore.activeSessionId == session.id

        return HStack(spacing: 5) {
            Circle()
                .fill(session.isAgentOwned ? Color.orange : terminalAccent)
                .frame(width: 6, height: 6)

            Image(systemName: session.isAgentOwned ? "cpu" : "terminal")
                .font(.system(size: 9))
                .foregroundStyle(isActive ? .primary : .secondary)

            Text(session.label)
                .font(.system(size: 10.5, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
                .lineLimit(1)

            if terminalSessionStore.sessions.count > 1 {
                Button {
                    terminalSessionStore.closeSession(id: session.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .opacity(isActive ? 1 : 0)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isActive ? terminalPanelFill : .clear)
        .overlay(alignment: .bottom) {
            if isActive {
                Rectangle()
                    .fill(session.isAgentOwned ? Color.orange : terminalAccent)
                    .frame(height: 1.5)
            }
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(terminalBorder.opacity(0.2)).frame(width: 0.5)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            terminalSessionStore.activeSessionId = session.id
        }
    }

    private var addToChatButton: some View {
        Button {
            let output = terminalSessionStore.readOutput(lastN: 4_000)
            NotificationCenter.default.post(
                name: .terminalAddToChat,
                object: nil,
                userInfo: ["content": output]
            )
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 9, weight: .semibold))
                Text("Add to Chat")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(terminalAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(terminalAccent.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Add terminal output to chat context")
        .padding(.trailing, 4)
    }

    // MARK: - Style

    private var terminalPanelFill: SwiftUI.Color {
        SwiftUI.Color(red: 0.067, green: 0.067, blue: 0.075).opacity(0.97)
    }

    private var terminalHeaderFill: SwiftUI.Color {
        SwiftUI.Color(red: 0.098, green: 0.098, blue: 0.106).opacity(0.92)
    }

    private var terminalBorder: SwiftUI.Color {
        SwiftUI.Color(red: 0.196, green: 0.196, blue: 0.208).opacity(0.78)
    }

    private var terminalAccent: SwiftUI.Color {
        SwiftUI.Color(red: 0.31, green: 0.76, blue: 0.99)
    }
}

extension Notification.Name {
    static let terminalAddToChat = Notification.Name("CoderIDE.TerminalAddToChat")
}

struct TerminalContainerView: NSViewRepresentable {
    let sessionId: UUID
    let workingDirectory: String?
    let autoFollowOutput: Bool
    let codeFontFamily: String
    let codeFontSize: CGFloat
    @EnvironmentObject var terminalSessionStore: TerminalSessionStore

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = AutoFollowLocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        context.coordinator.terminal = view
        view.isAutoFollowEnabled = autoFollowOutput
        view.sessionId = sessionId
        view.sessionStore = terminalSessionStore
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(red: 0.067, green: 0.067, blue: 0.075, alpha: 1).cgColor
        view.layer?.cornerCurve = .continuous
        view.layer?.cornerRadius = 6
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = "-" + (shell as NSString).lastPathComponent
        view.startProcess(executable: shell, execName: shellName, currentDirectory: workingDirectory)
        view.getTerminal().silentLog = true
        view.font = FontPreferences.resolveNSMonoFont(size: codeFontSize, family: codeFontFamily)
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        (nsView as? AutoFollowLocalProcessTerminalView)?.isAutoFollowEnabled = autoFollowOutput
    }

    func makeCoordinator() -> Coordinator { Coordinator(sessionId: sessionId) }

    class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var terminal: LocalProcessTerminalView?
        let sessionId: UUID

        init(sessionId: UUID) {
            self.sessionId = sessionId
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {}
    }
}

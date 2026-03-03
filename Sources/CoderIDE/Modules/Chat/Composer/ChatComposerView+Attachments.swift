import AppKit
import SwiftUI

extension ChatComposerView {
    @ViewBuilder
    internal func composerImagePreview(for item: ComposerAttachment) -> some View {
        Group {
            if let img = NSImage(contentsOf: item.url) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 56, height: 38)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .onTapGesture {
            let url = item.url
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: URL(fileURLWithPath: "/System/Applications/Preview.app"),
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
        .contextMenu {
            Button {
                let url = item.url
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                NSWorkspace.shared.open(
                    [url],
                    withApplicationAt: URL(fileURLWithPath: "/System/Applications/Preview.app"),
                    configuration: NSWorkspace.OpenConfiguration()
                )
            } label: {
                Label("Open in Preview", systemImage: "eye")
            }
            Button {
                let panel = NSSavePanel()
                panel.nameFieldStringValue = item.originalName
                panel.canCreateDirectories = true
                panel.begin { result in
                    guard result == .OK, let dest = panel.url else { return }
                    try? FileManager.default.copyItem(at: item.url, to: dest)
                }
            } label: {
                Label("Save As…", systemImage: "square.and.arrow.down")
            }
        }
    }

    @ViewBuilder
    internal func attachmentPreview(for item: ComposerAttachment) -> some View {
        if item.kind == .image {
            composerImagePreview(for: item)
        } else {
            Image(systemName: iconForAttachment(item.kind))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }

    internal var imageAttachButton: some View {
        Button {
            isSelectingImage = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .help("Attach file or image (⌘V to incollare)")
    }

    internal var microphoneButton: some View {
        Button {
            onVoiceAction()
        } label: {
            Group {
                switch voiceState {
                case .transcribing, .requestingPermission:
                    ProgressView()
                        .controlSize(.small)
                case .listening:
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black.opacity(0.9))
                default:
                    Image(systemName: "mic")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .background(
                voiceState == .listening
                    ? Color(red: 1, green: 0.94, blue: 0.94)
                    : Color.clear,
                in: Circle()
            )
            .overlay(
                Circle().strokeBorder(
                    voiceState == .listening
                        ? Color.red.opacity(0.45)
                        : Color.clear,
                    lineWidth: 1
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(voiceState == .requestingPermission || voiceState == .transcribing)
        .help(voiceState == .listening ? "Stop recording" : "Voice dictation")
    }

    internal var optimizePromptButton: some View {
        let hasText = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canOptimize = hasText && !isLoading && isProviderReady && !isOptimizingPrompt

        return Button {
            onOptimizePrompt()
        } label: {
            Group {
                if isOptimizingPrompt {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(canOptimize ? .yellow : .secondary.opacity(0.5))
                }
            }
            .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .disabled(!canOptimize)
        .help("Ottimizza prompt con AI")
    }

    internal var sendButton: some View {
        let awaitingChoice = if case .awaitingChoice = planningState { true } else { false }
        let canSend =
            (!inputText.isEmpty || !attachedAttachments.isEmpty)
            && !isLoading
            && !awaitingChoice
            && isProviderReady

        return Button(action: onSend) {
            Image(systemName: "arrow.up")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(canSend ? .black.opacity(0.9) : .secondary)
                .frame(width: 38, height: 38)
                .background(
                    Circle().fill(
                        canSend ? Color.white : Color.white.opacity(0.24)
                    )
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .animation(.easeOut(duration: 0.15), value: canSend)
    }

    internal func formatElapsed(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}

import CoderEngine
import SwiftUI

/// Sheet for creating and editing custom review commands.
struct ReviewPanelCustomCommands: View {
    @ObservedObject var store: CodeReviewPanelStore
    @Environment(\.dismiss) private var dismiss
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider().opacity(0.2)

            if store.settings.customCommands.isEmpty {
                emptyState
            } else {
                commandList
            }
        }
        .frame(width: 380, height: 400)
        .background(DesignSystem.Colors.chatPanelSolidBackground)
        .sheet(isPresented: $showAddSheet) {
            ReviewPanelCommandEditor(
                store: store,
                command: nil,
                onSave: { store.addCustomCommand($0) }
            )
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            Text("Custom Commands")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button { showAddSheet = true } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text("Add")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(store.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    store.accent.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            }
            .buttonStyle(.plain)

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "terminal")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No custom commands")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Text("Create commands with custom prompts for your workflow")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Command List

    private var commandList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 4) {
                ForEach(store.settings.customCommands) { cmd in
                    commandRow(cmd)
                }
            }
            .padding(8)
        }
    }

    private func commandRow(
        _ cmd: ReviewPanelCustomCommand
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: cmd.icon)
                .font(.system(size: 10))
                .foregroundStyle(store.accent)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(cmd.displayCommand)
                        .font(.system(size: 10, weight: .semibold,
                                      design: .monospaced))
                        .foregroundStyle(.primary)
                    Text(cmd.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Text(cmd.prompt)
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                store.removeCustomCommand(id: cmd.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.error.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    DesignSystem.Colors.border.opacity(0.3),
                    lineWidth: 0.5
                )
        )
    }
}

// MARK: - Command Editor Sheet

struct ReviewPanelCommandEditor: View {
    @ObservedObject var store: CodeReviewPanelStore
    let command: ReviewPanelCustomCommand?
    let onSave: (ReviewPanelCustomCommand) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var slash: String = ""
    @State private var prompt: String = ""
    @State private var icon: String = "terminal"

    private let iconOptions = [
        "terminal", "magnifyingglass", "lock.shield",
        "ladybug", "hammer", "wrench.and.screwdriver",
        "doc.text", "bolt", "cpu", "network",
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text(command == nil ? "New Command" : "Edit Command")
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                fieldRow("Name") {
                    TextField("My Command", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }

                fieldRow("Command") {
                    TextField("mycommand", text: $slash)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }

                fieldRow("Icon") {
                    iconPicker
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $prompt)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(minHeight: 80)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor)
                                    .opacity(0.4))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    DesignSystem.Colors.border.opacity(0.3),
                                    lineWidth: 0.5
                                )
                        )
                }
            }

            HStack {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
                Button("Save") { saveAndDismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(store.accent)
                    .controlSize(.small)
                    .disabled(name.isEmpty || prompt.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(DesignSystem.Colors.chatPanelSolidBackground)
        .onAppear {
            if let c = command {
                name = c.name
                slash = c.displayCommand
                prompt = c.prompt
                icon = c.icon
            }
        }
    }

    private var iconPicker: some View {
        HStack(spacing: 4) {
            ForEach(iconOptions, id: \.self) { opt in
                Button {
                    icon = opt
                } label: {
                    Image(systemName: opt)
                        .font(.system(size: 10))
                        .foregroundStyle(icon == opt ? store.accent : .secondary)
                        .frame(width: 22, height: 22)
                        .background(
                            icon == opt
                                ? store.accent.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(
                                cornerRadius: 4, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func fieldRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func saveAndDismiss() {
        let cmd = ReviewPanelCustomCommand(
            id: command?.id ?? UUID().uuidString,
            name: name,
            slash: slash,
            prompt: prompt,
            icon: icon
        )
        onSave(cmd)
        dismiss()
    }
}

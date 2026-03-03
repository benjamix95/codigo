import SwiftUI

extension CLIAccountLoginSheet {
    // MARK: - Polling
    private func pollingView(message: String) -> some View {
        VStack(spacing: 12) {
            ScrollView {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.regular)
                        .opacity(isLoginRunning ? 1 : 0.35)

                    Text(coordinator.statusByAccount[account.id] ?? message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Text("Complete the login in your browser...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    if let authURL = coordinator.authURLByAccount[account.id] {
                        loginLinkSection(authURL: authURL)
                    }

                    if let deviceCode = coordinator.deviceCodeByAccount[account.id] {
                        deviceCodeSection(code: deviceCode)
                    }

                    if let output = coordinator.lastOutputByAccount[account.id], !output.isEmpty {
                        Text(output)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if shouldShowAuthCodeInput {
                        authCodeSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 8)
            }

            pollingFooter
        }
    }

    private var pollingFooter: some View {
        HStack(spacing: 8) {
            if isLoginRunning {
                Button("Cancel") {
                    coordinator.cancelLogin(accountId: account.id)
                    phase = .options
                }
                .buttonStyle(.bordered)
            } else {
                Button("Back") {
                    phase = .options
                }
                .buttonStyle(.bordered)

                Button(isLoginSuccess ? "OK, Close" : "Close") {
                    dismiss()
                    onDismiss?()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    private func loginLinkSection(authURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Login link")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: true) {
                Text(authURL.absoluteString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                if availableBrowsers.isEmpty {
                    Link(destination: authURL) {
                        Label("Open link", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Menu {
                        ForEach(availableBrowsers) { browser in
                            Button {
                                open(authURL, with: browser.url)
                            } label: {
                                if browser.isDefault {
                                    Text("\(browser.name) (default)")
                                } else {
                                    Text(browser.name)
                                }
                            }
                        }
                    } label: {
                        Label("Open in browser", systemImage: "globe")
                    }
                    .menuStyle(.borderlessButton)
                    .controlSize(.small)
                }

                Button {
                    copyToClipboard(value: authURL.absoluteString)
                    copiedURLHint = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        copiedURLHint = false
                    }
                } label: {
                    Label("Copy link", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if copiedURLHint {
                    Text("Copied")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    private func deviceCodeSection(code: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your device code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack {
                Text(code)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button {
                    copyToClipboard(value: code)
                    deviceCodeCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                        deviceCodeCopied = false
                    }
                } label: {
                    Label(deviceCodeCopied ? "Copied" : "Copy code", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text("Enter this code in the browser page above")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var authCodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Authentication code")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Paste the code from browser or terminal", text: $authCodeInput)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))
            HStack(spacing: 8) {
                Button {
                    let pasted = NSPasteboard.general.string(forType: .string)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !pasted.isEmpty else {
                        authCodeHint = "Clipboard is empty"
                        return
                    }
                    authCodeInput = pasted
                    authCodeHint = "Code pasted"
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    guard coordinator.submitInteractiveInput(
                        accountId: account.id,
                        text: authCodeInput
                    ) else {
                        authCodeHint = "Unable to submit code"
                        return
                    }
                    authCodeHint = "Code submitted"
                    authCodeInput = ""
                } label: {
                    Label("Submit code", systemImage: "paperplane")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(authCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !authCodeHint.isEmpty {
                    Text(authCodeHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

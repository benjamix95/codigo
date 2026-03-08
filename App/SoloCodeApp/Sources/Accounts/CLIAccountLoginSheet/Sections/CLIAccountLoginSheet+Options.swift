import SwiftUI

extension CLIAccountLoginSheet {
    // MARK: - Options
    var optionsView: some View {
        VStack(spacing: 16) {
            if availableBrowsers.count > 1 {
                Menu {
                    ForEach(availableBrowsers) { browser in
                        Button {
                            loginWithBrowser(browserAppURL: browser.url)
                        } label: {
                            Text(browser.isDefault ? "\(browser.name) (default)" : browser.name)
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "safari")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign in with Browser")
                                .font(.subheadline.weight(.medium))
                            Text(browserSubtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "chevron.down")
                    }
                    .padding(12)
                    .foregroundColor(.white)
                    .background(providerColor, in: RoundedRectangle(cornerRadius: 10))
                }
                .menuStyle(.borderlessButton)
            } else {
                Button(action: { loginWithBrowser() }) {
                    HStack(spacing: 12) {
                        Image(systemName: "safari")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign in with Browser")
                                .font(.subheadline.weight(.medium))
                            Text(browserSubtitle)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .padding(12)
                    .foregroundColor(.white)
                    .background(providerColor, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }

            if supportsDeviceCode {
                dividerLine
                Button(action: loginWithDeviceCode) {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.title3)
                            .foregroundStyle(providerColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Device code")
                                .font(.subheadline.weight(.medium))
                            Text("Authenticate via terminal")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Or use API Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                SecureField(apiKeyPlaceholder, text: $apiKey)
                    .textFieldStyle(.roundedBorder)

                Button("Sign in with API Key") { loginWithAPIKey() }
                    .buttonStyle(.borderedProminent)
                    .tint(providerColor)
                    .disabled(apiKey.isEmpty)
            }

            Button("Cancel", role: .cancel) {
                coordinator.cancelLogin(accountId: account.id)
                dismiss()
                onDismiss?()
            }
            .padding(.top, 4)
        }
        .padding(24)
    }
}

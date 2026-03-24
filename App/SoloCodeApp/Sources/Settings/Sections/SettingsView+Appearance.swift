import SwiftUI

// MARK: - AppearanceSettingsSection

struct AppearanceSettingsSection: View {
    @State var appearanceConfig = SettingsAppearanceConfig()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSectionHeader(title: "Appearance", subtitle: "Theme and interface appearance", icon: "paintbrush.fill")

            themeGroup
            chatPanelPositionGroup
            chatBackgroundGroup
            sansFontGroup
            codeFontGroup
        }
        .onChange(of: appearanceConfig.uiSansFontSize) { newValue in
            let sanitized = Double(FontPreferences.sanitizeSize(newValue, kind: .sans))
            guard sanitized != newValue else { return }
            DispatchQueue.main.async { appearanceConfig.uiSansFontSize = sanitized }
        }
        .onChange(of: appearanceConfig.uiCodeFontSize) { newValue in
            let sanitized = Double(FontPreferences.sanitizeSize(newValue, kind: .code))
            guard sanitized != newValue else { return }
            DispatchQueue.main.async { appearanceConfig.uiCodeFontSize = sanitized }
        }
    }

    // MARK: - Computed Properties

    var availableSansFontFamilies: [String] {
        FontPreferences.availableSansFamilies()
    }

    var availableMonoFontFamilies: [String] {
        FontPreferences.availableMonoFamilies()
    }
}

// MARK: - Subviews

private extension AppearanceSettingsSection {
    var themeGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingsFieldLabel("Theme")
                Picker("", selection: $appearanceConfig.appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }.labelsHidden().pickerStyle(.segmented)
            }
        }
    }

    var chatPanelPositionGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingsFieldLabel("Chat panel position")
                Picker("", selection: $appearanceConfig.chatPanelPosition) {
                    Text("Left").tag("left")
                    Text("Right").tag("right")
                }.labelsHidden()
                    .pickerStyle(.segmented)
            }
        }
    }

    var chatBackgroundGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingsFieldLabel("Chat background")
                Picker("", selection: $appearanceConfig.chatBackgroundStyle) {
                    ForEach(ChatBackgroundStyle.allCases) { (style: ChatBackgroundStyle) in
                        Text(style.label).tag(style.rawValue)
                    }
                }.labelsHidden()
            }
        }
    }

    var sansFontGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingsFieldLabel("Sans font family")
                HStack(spacing: 12) {
                    Stepper(
                        value: Binding(
                            get: { Int(FontPreferences.sanitizeSize(appearanceConfig.uiSansFontSize, kind: .sans)) },
                            set: { appearanceConfig.uiSansFontSize = Double($0) }
                        ),
                        in: Int(FontPreferences.sansSizeRange.lowerBound)...Int(FontPreferences.sansSizeRange.upperBound)
                    ) {
                        Text("\(Int(FontPreferences.sanitizeSize(appearanceConfig.uiSansFontSize, kind: .sans))) px")
                            .frame(width: 58, alignment: .leading)
                    }
                    Picker("Sans family", selection: $appearanceConfig.uiSansFontFamily) {
                        Text("System Default").tag(FontPreferences.systemSansToken)
                        ForEach(availableSansFontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .labelsHidden()
                }
                Text("Adjust the font used for the app UI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var codeFontGroup: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                settingsFieldLabel("Code font")
                HStack(spacing: 12) {
                    Stepper(
                        value: Binding(
                            get: { Int(FontPreferences.sanitizeSize(appearanceConfig.uiCodeFontSize, kind: .code)) },
                            set: { appearanceConfig.uiCodeFontSize = Double($0) }
                        ),
                        in: Int(FontPreferences.codeSizeRange.lowerBound)...Int(FontPreferences.codeSizeRange.upperBound)
                    ) {
                        Text("\(Int(FontPreferences.sanitizeSize(appearanceConfig.uiCodeFontSize, kind: .code))) px")
                            .frame(width: 58, alignment: .leading)
                    }
                    Picker("Code family", selection: $appearanceConfig.uiCodeFontFamily) {
                        Text("System Monospace").tag(FontPreferences.systemMonoToken)
                        ForEach(availableMonoFontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    .labelsHidden()
                }
                Text("Adjust font and size used for code across chats and technical panels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

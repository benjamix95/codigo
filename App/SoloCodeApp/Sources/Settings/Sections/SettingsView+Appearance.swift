import SwiftUI

extension SettingsView {
    var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Appearance", subtitle: "Theme and interface appearance", icon: "paintbrush.fill")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Theme")
                    Picker("", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }.labelsHidden().pickerStyle(.segmented)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Chat panel position")
                    Picker("", selection: $chatPanelPosition) {
                        Text("Left").tag("left")
                        Text("Right").tag("right")
                    }.labelsHidden()
                        .pickerStyle(.segmented)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Chat background")
                    Picker("", selection: $chatBackgroundStyle) {
                        ForEach(ChatBackgroundStyle.allCases) { (style: ChatBackgroundStyle) in
                            Text(style.label).tag(style.rawValue)
                        }
                    }.labelsHidden()
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Sans font family")
                    HStack(spacing: 12) {
                        Stepper(
                            value: Binding(
                                get: { Int(FontPreferences.sanitizeSize(uiSansFontSize, kind: .sans)) },
                                set: { uiSansFontSize = Double($0) }
                            ),
                            in: Int(FontPreferences.sansSizeRange.lowerBound)...Int(FontPreferences.sansSizeRange.upperBound)
                        ) {
                            Text("\(Int(FontPreferences.sanitizeSize(uiSansFontSize, kind: .sans))) px")
                                .frame(width: 58, alignment: .leading)
                        }
                        Picker("Sans family", selection: $uiSansFontFamily) {
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

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Code font")
                    HStack(spacing: 12) {
                        Stepper(
                            value: Binding(
                                get: { Int(FontPreferences.sanitizeSize(uiCodeFontSize, kind: .code)) },
                                set: { uiCodeFontSize = Double($0) }
                            ),
                            in: Int(FontPreferences.codeSizeRange.lowerBound)...Int(FontPreferences.codeSizeRange.upperBound)
                        ) {
                            Text("\(Int(FontPreferences.sanitizeSize(uiCodeFontSize, kind: .code))) px")
                                .frame(width: 58, alignment: .leading)
                        }
                        Picker("Code family", selection: $uiCodeFontFamily) {
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
}

import SwiftUI

extension ChatComposerView {
    /// Inner content of the composer box — no background, border, or shadow.
    /// The fused container in `ChatComposerView.body` provides those.
    internal var composerBoxContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if voiceState != .idle {
                voiceStatusView
            }

            if !attachedAttachments.isEmpty {
                attachedAttachmentsRow
            }

            if isIDEStyle {
                ideComposerContent
            } else {
                standardComposerContent
            }
        }
    }

    /// Legacy standalone composer box (kept for any external callers).
    internal var composerBox: some View {
        composerBoxContent
            .padding(.horizontal, isIDEStyle ? 12 : 14)
            .padding(.vertical, isIDEStyle ? 8 : 10)
            .background(
                RoundedRectangle(cornerRadius: isIDEStyle ? 16 : 20, style: .continuous)
                    .fill(composerSurfaceGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: isIDEStyle ? 16 : 20, style: .continuous)
                    .strokeBorder(
                        isComposerDropTargeted
                            ? Color.white.opacity(0.35)
                            : (isInputFocused
                                ? Color.white.opacity(0.22)
                                : Color.white.opacity(0.12)),
                        lineWidth: isComposerDropTargeted ? 1.2 : 0.8
                    )
            )
            .shadow(color: Color.black.opacity(isIDEStyle ? 0.14 : 0.25), radius: isIDEStyle ? 6 : 12, y: isIDEStyle ? 1 : 3)
            .animation(.easeOut(duration: 0.2), value: isInputFocused)
            .onDrop(
                of: [.item, .fileURL, .image, .png, .jpeg, .gif, .pdf],
                isTargeted: $isComposerDropTargeted
            ) { providers in
                Task {
                    var incoming: [ComposerAttachment] = []
                    for provider in providers {
                        if let attachment = await AttachmentIntakeService.attachmentFromDropProvider(provider) {
                            incoming.append(attachment)
                        }
                    }
                    await MainActor.run {
                        appendAttachments(incoming)
                    }
                }
                return true
            }
            .overlay {
                if isConvertingHeic {
                    RoundedRectangle(cornerRadius: isIDEStyle ? 18 : 26, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            VStack(spacing: 8) {
                                ProgressView().controlSize(.regular)
                                Text("Converting HEIC image...")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
    }

    internal var standardComposerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            inputEditorArea(
                minHeight: 22,
                maxHeight: 140,
                placeholderFontSize: 13
            )
            bottomControlsRow
        }
    }

    internal var ideComposerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                imageAttachButton
                    .frame(width: 28, height: 28)

                inputEditorArea(
                    minHeight: 18,
                    maxHeight: 72,
                    placeholderFontSize: 12
                )
                .frame(maxWidth: .infinity)

                if isLoading {
                    runtimeControls
                } else {
                    HStack(spacing: 4) {
                        optimizePromptButton
                        microphoneButton
                        sendButton
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.08))

            HStack(spacing: 8) {
                controlsRow
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !isLoading {
                    if frozenTimerText != nil {
                        runtimeTimerLabel
                    }
                    if showPlanRequestIndicator {
                        planRequestBadge
                    }
                }
            }
        }
    }

    internal func inputEditorArea(
        minHeight: CGFloat,
        maxHeight: CGFloat,
        placeholderFontSize: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(inputHint)
                    .font(.system(size: placeholderFontSize))
                    .foregroundStyle(.secondary.opacity(0.9))
                    .padding(.top, 2)
            }

            ComposerTextView(
                text: $inputText,
                isFocused: $isInputFocused,
                minHeight: minHeight,
                maxHeight: maxHeight,
                onSubmit: onSend
            )
        }
        .onChange(of: inputText) { newValue in
            onInputTextChanged(newValue)
        }
    }

    internal var bottomControlsRow: some View {
        HStack(spacing: isIDEStyle ? 6 : 8) {
            imageAttachButton

            controlsRow
                .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading {
                runtimeControls
            } else {
                idleTrailingControls
            }
        }
    }

    @ViewBuilder
    internal var idleTrailingControls: some View {
        HStack(spacing: 6) {
            if frozenTimerText != nil {
                runtimeTimerLabel
            }
            if showPlanRequestIndicator {
                planRequestBadge
            }
            optimizePromptButton
            microphoneButton
            sendButton
        }
    }

    @ViewBuilder
    internal var runtimeControls: some View {
        HStack(spacing: 6) {
            runtimeTimerLabel

            Button {
                onPauseResume()
            } label: {
                Image(systemName: runtimeRunState == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help(runtimeRunState == .paused ? "Resume" : "Pause")

            Button {
                onStop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.black.opacity(0.9))
                    .frame(width: 34, height: 34)
                    .background(Color.white, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Stop")
        }
    }

    @ViewBuilder
    internal var runtimeTimerLabel: some View {
        if let startDate = runtimeTaskStartDate {
            ElapsedTimerView(startDate: startDate) { elapsed in
                Text(formatElapsed(elapsed))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .trailing)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        } else if let frozenTimerText {
            if frozenTimerDismissible {
                Button {
                    onDismissFrozenTimer()
                } label: {
                    Text(frozenTimerText)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Hide timer")
            } else {
                Text(frozenTimerText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        }
    }

    @ViewBuilder
    internal var voiceStatusView: some View {
        switch voiceState {
        case .idle:
            EmptyView()
        case .requestingPermission:
            voiceStatusBadge(icon: "lock.open.fill", text: "Requesting microphone/speech permissions...", color: .secondary)
        case .listening:
            let trimmed = voiceTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                voiceStatusBadge(icon: "waveform", text: "Listening... click the microphone to stop", color: DesignSystem.Colors.info)
            } else {
                voiceStatusBadge(icon: "waveform", text: "Listening... \"\(trimmed.suffix(60))\"", color: DesignSystem.Colors.info)
            }
        case .transcribing:
            voiceStatusBadge(icon: "waveform.badge.magnifyingglass", text: "Transcribing...", color: .secondary)
        case .failed:
            EmptyView()
        }
    }

    internal func voiceStatusBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.14), in: Capsule())
    }

    internal var planRequestBadge: some View {
        Text("PLAN")
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .foregroundStyle(activeModeColor.opacity(0.95))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(activeModeColor.opacity(0.16), in: Capsule())
            .accessibilityLabel("Plan request attiva")
    }
}

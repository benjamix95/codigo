import SwiftUI

struct PlanOptionsView: View {
    let options: [PlanOption]
    let selectedOptionId: Int?
    let onSelectOption: (PlanOption) -> Void
    let onCustomResponse: (String) -> Void
    let planColor: Color

    @State private var customText = ""
    @State private var tappedOptionId: Int?
    @State private var showCustomField = false
    @FocusState private var isCustomFocused: Bool

    init(
        options: [PlanOption],
        selectedOptionId: Int? = nil,
        planColor: Color = .blue,
        onSelectOption: @escaping (PlanOption) -> Void,
        onCustomResponse: @escaping (String) -> Void
    ) {
        self.options = options
        self.selectedOptionId = selectedOptionId
        self.planColor = planColor
        self.onSelectOption = onSelectOption
        self.onCustomResponse = onCustomResponse
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose an option or add a custom response")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(options) { opt in
                let isSelected = selectedOptionId == opt.id
                let isTapped = tappedOptionId == opt.id
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        tappedOptionId = opt.id
                    }
                    onSelectOption(opt)
                    // Reset tap visual state after brief feedback.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        if tappedOptionId == opt.id {
                            withAnimation(.easeOut(duration: 0.15)) {
                                tappedOptionId = nil
                            }
                        }
                    }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(opt.id)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(planColor, in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(opt.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            if opt.fullText != opt.title, opt.fullText.count > opt.title.count + 20 {
                                Text(opt.fullText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: isSelected ? "checkmark.circle.fill" : "arrow.right.circle")
                            .font(.subheadline)
                            .foregroundStyle(isSelected ? planColor : planColor.opacity(0.7))
                    }
                    .padding(10)
                    .background(
                        ((isSelected || isTapped) ? planColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor)),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                (isSelected || isTapped) ? planColor.opacity(0.65) : Color(nsColor: .separatorColor),
                                lineWidth: (isSelected || isTapped) ? 1.0 : 0.5
                            )
                    )
                    .opacity(isTapped ? 0.85 : 1.0)
                    .scaleEffect(isTapped ? 0.98 : 1.0)
                }
                .buttonStyle(.plain)
            }

            // Collapsible custom response
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    showCustomField.toggle()
                }
                if showCustomField {
                    isCustomFocused = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 11, weight: .medium))
                    Text("Custom response")
                        .font(.caption.weight(.medium))
                    Spacer()
                    Image(systemName: showCustomField ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showCustomField {
                HStack(alignment: .bottom, spacing: 6) {
                    TextField("Write your response...", text: $customText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .focused($isCustomFocused)

                    let trimmedCustom = customText.trimmingCharacters(in: .whitespacesAndNewlines)
                    Button {
                        guard !trimmedCustom.isEmpty else { return }
                        onCustomResponse(trimmedCustom)
                        customText = ""
                        showCustomField = false
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(trimmedCustom.isEmpty ? Color.secondary : planColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(trimmedCustom.isEmpty)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

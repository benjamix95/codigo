import SwiftUI

struct PlanOptionsView: View {
    let options: [PlanOption]
    let onSelectOption: (PlanOption) -> Void
    let onCustomResponse: (String) -> Void
    let planColor: Color

    @State private var customText = ""
    @FocusState private var isCustomFocused: Bool

    init(
        options: [PlanOption],
        planColor: Color = .blue,
        onSelectOption: @escaping (PlanOption) -> Void,
        onCustomResponse: @escaping (String) -> Void
    ) {
        self.options = options
        self.planColor = planColor
        self.onSelectOption = onSelectOption
        self.onCustomResponse = onCustomResponse
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scegli un'opzione o aggiungi una risposta")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(options) { opt in
                Button { onSelectOption(opt) } label: {
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

                        Image(systemName: "arrow.right.circle")
                            .font(.subheadline)
                            .foregroundStyle(planColor.opacity(0.7))
                    }
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Altra risposta")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .bottom, spacing: 6) {
                    TextField("Scrivi la tua risposta...", text: $customText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .focused($isCustomFocused)

                    Button {
                        let t = customText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { onCustomResponse(t) }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(customText.isEmpty ? Color.secondary : planColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(customText.isEmpty)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

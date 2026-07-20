import SwiftUI

struct StyleView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pick how GroqFlow formats text in each kind of app. Style changes only capitalization, punctuation, and spacing, never your wording.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(StyleCategory.allCases, id: \.self) { category in
                    StyleCard(title: category.displayName,
                              preset: presetBinding(for: category))
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Style")
    }

    private func presetBinding(for category: StyleCategory) -> Binding<StylePreset> {
        Binding(
            get: { settings.stylePresets[category] ?? .formal },
            set: { settings.stylePresets[category] = $0 })
    }
}

private struct StyleCard: View {
    let title: String
    @Binding var preset: StylePreset

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Picker("", selection: $preset) {
                    ForEach(StylePreset.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            Text(StyleCard.preview(for: preset))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }

    // Hardcoded, illustrative renderings of one sample utterance per preset.
    static func preview(for preset: StylePreset) -> String {
        switch preset {
        case .veryCasual:
            return "hey i just finished the report and i think it looks great can you take a look"
        case .casual:
            return "Hey I just finished the report and I think it looks great, can you take a look"
        case .excited:
            return "Hey! I just finished the report and I think it looks great! Can you take a look!"
        case .formal:
            return "Hey, I just finished the report, and I think it looks great. Can you take a look?"
        }
    }
}

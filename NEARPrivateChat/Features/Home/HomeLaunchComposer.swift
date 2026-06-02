import SwiftUI

struct HomePromptCaptureCard: View {
    let subtitle: String
    @Binding var draft: String
    let suggestions: [EmptyChatStarterSuggestion]
    let selectedSuggestionID: String?
    let selectedProjectName: String?
    let actionTitle: String
    let actionSymbolName: String
    let actionEnabled: Bool
    let onSelectSuggestion: (EmptyChatStarterSuggestion) -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Start from one prompt")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let selectedProjectName = selectedProjectName?.nilIfBlank {
                Label("\(selectedProjectName) context is active", systemImage: "folder.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color.actionTint, in: Capsule())
            }

            TextField(
                "Paste a task, source, file question, tracker idea, or handoff brief",
                text: $draft,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(3...6)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }

            if !suggestions.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        promptIntentChips(fillsWidth: false)
                    }

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 132), spacing: 8)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        promptIntentChips(fillsWidth: true)
                    }
                }
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Nothing sends until you review it in chat.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                Button(action: onSubmit) {
                    Label(actionTitle, systemImage: actionSymbolName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(
                            actionEnabled ? Color.actionPrimary : Color.textTertiary,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!actionEnabled)
            }
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func promptIntentChips(fillsWidth: Bool) -> some View {
        ForEach(suggestions) { suggestion in
            HomePromptIntentChip(
                suggestion: suggestion,
                isSelected: suggestion.id == selectedSuggestionID,
                fillsWidth: fillsWidth,
                action: { onSelectSuggestion(suggestion) }
            )
        }
    }
}

private struct HomePromptIntentChip: View {
    let suggestion: EmptyChatStarterSuggestion
    let isSelected: Bool
    var fillsWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: suggestion.symbolName)
                    .font(.caption.weight(.bold))
                Text(suggestion.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.actionPrimary : Color.textSecondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 40)
            .background(
                isSelected ? Color.actionTint : Color.appSecondaryBackground,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.actionPrimary.opacity(0.24) : Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}


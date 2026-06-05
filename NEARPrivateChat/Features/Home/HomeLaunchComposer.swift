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
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Start from one prompt")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                projectContextPill
            }

            TextField(
                "Paste a task, source, file, or handoff",
                text: $draft,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.body)
            .lineLimit(3...6)
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(minHeight: 72, alignment: .topLeading)
            .focused($isPromptFocused)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isPromptFocused ? Color.actionPrimary.opacity(0.34) : Color.appBorder, lineWidth: 1)
            }

            if !suggestions.isEmpty {
                LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                    promptIntentChips()
                }
            }

            Button(action: onSubmit) {
                Label(actionEnabled ? actionTitle : "Add prompt first", systemImage: actionSymbolName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(actionEnabled ? Color.appPanelBackground : Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        actionEnabled ? Color.actionPrimary : Color.appSecondaryBackground,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(actionEnabled ? Color.clear : Color.appBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!actionEnabled)
            .accessibilityHint("Stages the draft in chat for review.")
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var projectContextPill: some View {
        if let selectedProjectName = selectedProjectName?.nilIfBlank {
            Label(selectedProjectName, systemImage: "folder.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.actionPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .padding(.horizontal, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 26)
                .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("\(selectedProjectName) context active")
        }
    }

    @ViewBuilder
    private func promptIntentChips() -> some View {
        ForEach(suggestions) { suggestion in
            HomePromptIntentChip(
                suggestion: suggestion,
                isSelected: suggestion.id == selectedSuggestionID,
                action: { onSelectSuggestion(suggestion) }
            )
        }
    }

    private var chipColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 0), spacing: 8),
            GridItem(.flexible(minimum: 0), spacing: 8)
        ]
    }
}

private struct HomePromptIntentChip: View {
    let suggestion: EmptyChatStarterSuggestion
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: suggestion.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? Color.actionPrimary : Color.textSecondary)

                Text(suggestion.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.9)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(isSelected ? Color.actionPrimary : Color.textSecondary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
            .background(
                isSelected ? Color.actionTint : Color.appSecondaryBackground,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.actionPrimary.opacity(0.24) : Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI

enum HomeComposerRouteBadgeText {
    static func visibleText(routeTitle: String, routeDetail: String) -> String {
        let title = routeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = routeDetail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else { return title.isEmpty ? "Route" : title }

        if title.localizedCaseInsensitiveContains("private") {
            if detail.localizedCaseInsensitiveContains("private") {
                return detail
            }
            if detail.localizedCaseInsensitiveContains("web") {
                let model = detail
                    .components(separatedBy: "·")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .first { !$0.localizedCaseInsensitiveContains("web") }
                return "Private + Web · \(model?.nilIfBlank ?? detail)"
            }
            return "Private · \(detail)"
        }

        return detail
    }
}

struct HomePromptCaptureCard: View {
    let subtitle: String
    @Binding var draft: String
    let suggestions: [EmptyChatStarterSuggestion]
    let selectedSuggestionID: String?
    let selectedProjectName: String?
    let routeTitle: String
    let routeDetail: String
    let actionTitle: String
    let actionSymbolName: String
    let actionEnabled: Bool
    let onSelectSuggestion: (EmptyChatStarterSuggestion) -> Void
    let onSubmit: () -> Void
    @FocusState private var isPromptFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                routeBadge
                if let selectedProjectName = selectedProjectName?.nilIfBlank {
                    projectContextPill(selectedProjectName)
                }
                Spacer(minLength: 0)
            }

            if let visibleSubtitle {
                Text(visibleSubtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !suggestions.isEmpty {
                LazyVGrid(columns: chipColumns, spacing: 8) {
                    ForEach(suggestions) { suggestion in
                        HomePromptIntentChip(
                            suggestion: suggestion,
                            isSelected: suggestion.id == selectedSuggestionID,
                            action: { onSelectSuggestion(suggestion) }
                        )
                    }
                }
                .padding(.top, 4)
            }

            composerRow
        }
        .padding(10)
        .background(Color.appBackground.opacity(0.94), in: RoundedRectangle.app(AppRadius.card))
        .overlay {
            RoundedRectangle.app(AppRadius.card)
                .stroke(Color.appBorder.opacity(0.76), lineWidth: 1)
        }
        .shadow(color: Color.brandBlack.opacity(0.10), radius: 22, y: 10)
    }

    private var composerRow: some View {
        HStack(spacing: 9) {
            TextField("Ask privately.", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(1...4)
                .tokenInputTraits()
                .focused($isPromptFocused)
                .submitLabel(.send)
                .onSubmit {
                    if actionEnabled {
                        onSubmit()
                    }
                }

            Button(action: onSubmit) {
                Image(systemName: actionSymbolName)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(actionEnabled ? Color.white : Color.actionPrimary.opacity(0.72))
                    .frame(width: 34, height: 34)
                    .background(actionEnabled ? Color.actionPrimary : Color.actionFill, in: Circle())
            }
            .buttonStyle(.plain)
            .minimumTouchTarget()
            .disabled(!actionEnabled)
            .accessibilityLabel(actionTitle)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .frame(minHeight: 46)
        .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.pill))
        .overlay {
            RoundedRectangle.app(AppRadius.pill)
                .stroke(isPromptFocused ? Color.actionPrimary.opacity(0.32) : Color.actionPrimary.opacity(0.08), lineWidth: 1)
        }
    }

    private func projectContextPill(_ selectedProjectName: String) -> some View {
        Label(selectedProjectName, systemImage: "folder")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Color.appSecondaryBackground.opacity(0.82), in: RoundedRectangle.app(AppRadius.pill))
            .overlay {
                RoundedRectangle.app(AppRadius.pill)
                    .stroke(Color.appBorder.opacity(0.75), lineWidth: 1)
            }
            .accessibilityLabel("\(selectedProjectName) context active")
    }

    private var routeSymbolName: String {
        if routeTitle == "Council" {
            return "person.3.sequence.fill"
        }
        if routeDetail.localizedCaseInsensitiveContains("web") {
            return "globe"
        }
        return "checkmark.shield.fill"
    }

    private var routeBadge: some View {
        Label(visibleRouteText, systemImage: routeSymbolName)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Color.appPanelBackground.opacity(0.92), in: RoundedRectangle.app(AppRadius.pill))
            .overlay {
                RoundedRectangle.app(AppRadius.pill)
                    .stroke(Color.appBorder.opacity(0.75), lineWidth: 1)
            }
            .accessibilityLabel("\(routeTitle), \(routeDetail)")
    }

    private var visibleRouteText: String {
        HomeComposerRouteBadgeText.visibleText(routeTitle: routeTitle, routeDetail: routeDetail)
    }

    private var visibleSubtitle: String? {
        subtitle.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
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
                    .font(.subheadline.weight(.semibold))
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
                in: RoundedRectangle.app(AppRadius.control)
            )
            .overlay {
                RoundedRectangle.app(AppRadius.control)
                    .stroke(isSelected ? Color.actionPrimary.opacity(0.24) : Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .minimumTouchTarget()
        .accessibilityElement(children: .combine)
    }
}

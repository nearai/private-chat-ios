import SwiftUI

struct WidgetActionRow: View {
    let action: WidgetActionItem
    var onFollowUp: ((String) -> Void)? = nil
    var onPreview: ((WidgetActionItem) -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(action.title.isEmpty ? "Action" : action.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                let metadata = metadataText
                if !metadata.isEmpty {
                    Text(metadata)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(tint)
                        .lineLimit(2)
                }

                if let detail = widgetNonBlank(action.detail) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !action.missingFields.isEmpty {
                    Text("Needs: \(action.missingFields.prefix(3).joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(2)
                }
            }

            if widgetNonBlank(action.command) != nil, onFollowUp != nil {
                Spacer(minLength: 6)
                Button {
                    onPreview?(action)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color.actionPrimary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stage action")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onPreview?(action)
        }
        .accessibilityAction(named: "Preview") {
            onPreview?(action)
        }
    }

    private var normalizedType: String {
        (action.type ?? "")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var metadataText: String {
        [
            widgetNonBlank(action.type),
            widgetNonBlank(action.schedule),
            widgetNonBlank(action.recurrence),
            widgetNonBlank(action.time),
            widgetNonBlank(action.source)
        ]
        .compactMap { $0 }
        .prefix(4)
        .joined(separator: " · ")
    }

    private var symbolName: String {
        if normalizedType.contains("calendar") || normalizedType.contains("invite") {
            return "calendar.badge.plus"
        }
        if normalizedType.contains("reminder") {
            return "bell.badge"
        }
        if normalizedType.contains("tracker") || normalizedType.contains("brief") || normalizedType.contains("watch") {
            return "dot.radiowaves.left.and.right"
        }
        if normalizedType.contains("decision") {
            return "checkmark.seal"
        }
        if normalizedType.contains("risk") {
            return "exclamationmark.triangle"
        }
        if normalizedType.contains("question") {
            return "questionmark.circle"
        }
        if normalizedType.contains("interest") {
            return "sparkles"
        }
        return "checklist"
    }

    private var tint: Color {
        widgetToneColor(action.tone)
    }
}


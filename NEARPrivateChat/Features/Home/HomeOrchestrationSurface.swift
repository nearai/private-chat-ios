import SwiftUI

struct HomeOrchestrationSurface: View {
    let plan: HomeOrchestrationPlan
    let onAction: (HomeOrchestrationAction) -> Void
    @State private var showsAllItems = false

    private var displayedItems: [HomeOrchestrationItem] {
        showsAllItems ? plan.liveItems : Array(plan.liveItems.prefix(2))
    }

    @ViewBuilder
    var body: some View {
        if plan.hasContent {
            VStack(alignment: .leading, spacing: 12) {
                header
                liveList
                scheduledSection
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.card))
            .overlay {
                RoundedRectangle.app(AppRadius.card)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Continue")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(plan.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private var liveList: some View {
        if !plan.liveItems.isEmpty {
            VStack(spacing: 8) {
                ForEach(displayedItems) { item in
                    HomeOrchestrationRow(item: item) {
                        onAction(item.action)
                    }
                }
                if plan.liveItems.count > displayedItems.count {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                            showsAllItems = true
                        }
                    } label: {
                        Label("Show \(plan.liveItems.count - displayedItems.count) more", systemImage: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(Color.appPanelBackground, in: RoundedRectangle.app(AppRadius.pill))
                            .overlay {
                                RoundedRectangle.app(AppRadius.pill)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var scheduledSection: some View {
        if !plan.scheduledItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Automations")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.textSecondary)
                    Spacer(minLength: 8)
                    Text("\(plan.scheduledItems.count) active")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }

                VStack(spacing: 0) {
                    ForEach(Array(plan.scheduledItems.prefix(1).enumerated()), id: \.element.id) { _, item in
                        HomeOrchestrationScheduleRow(item: item) {
                            onAction(item.action)
                        }
                    }
                    if plan.scheduledItems.count > 1 {
                        Divider()
                            .overlay(Color.appHairline)
                            .padding(.leading, 48)
                        Text("+ \(plan.scheduledItems.count - 1) more automations")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                    }
                }
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }
            }
        }
    }
}

private struct HomeOrchestrationRow: View {
    let item: HomeOrchestrationItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: item.symbolName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.tone.tintColor)
                    .frame(width: 34, height: 34)
                    .background(item.tone.tintColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(item.statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.tone.tintColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityHint: String {
        switch item.kind {
        case .briefing, .project, .chat:
            return "Opens this item."
        case .council, .agent, .setup:
            return "Stages this action without sending."
        }
    }
}

private struct HomeOrchestrationScheduleRow: View {
    let item: HomeOrchestrationScheduleItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: item.symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(item.tone.tintColor)
                    .frame(width: 30, height: 30)
                    .background(item.tone.tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(item.scheduleLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

import SwiftUI

struct HomeOrchestrationSurface: View {
    let plan: HomeOrchestrationPlan
    let onAction: (HomeOrchestrationAction) -> Void
    @State private var selectedFilter: HomeOrchestrationFilter = .all
    @State private var showsAllItems = false

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: 10)
    ]

    private var visibleItems: [HomeOrchestrationItem] {
        plan.liveItems.filter { $0.matches(selectedFilter) }
    }

    private var displayedItems: [HomeOrchestrationItem] {
        showsAllItems ? visibleItems : Array(visibleItems.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            filterStrip
            liveGrid
            scheduledSection
        }
        .padding(14)
        .background(Color.appBackground)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Next up")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(plan.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button {
                onAction(.newBriefing)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appPanelBackground)
                    .frame(width: 32, height: 32)
                    .background(Color.actionPrimary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New workflow")
        }
    }

    private var commandStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(plan.commands) { command in
                    Button {
                        onAction(command.action)
                    } label: {
                        Label(command.title, systemImage: command.symbolName)
                            .font(.caption.weight(.semibold))
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(Color.appPanelBackground, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(Color.appBorder, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
    }

    private var filterStrip: some View {
        HStack(spacing: 6) {
            ForEach(HomeOrchestrationFilter.allCases) { filter in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                        selectedFilter = filter
                    }
                } label: {
                    Label(filter.title, systemImage: filter.symbolName)
                        .font(.caption2.weight(.bold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(selectedFilter == filter ? Color.actionPrimary : Color.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            selectedFilter == filter ? Color.actionTint : Color.appPanelBackground,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(filter.title)")
                .accessibilityValue(selectedFilter == filter ? "Selected" : "")
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var liveGrid: some View {
        if visibleItems.isEmpty {
            Text("No next actions in this view.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(displayedItems) { item in
                    HomeOrchestrationCard(item: item) {
                        onAction(item.action)
                    }
                }
            }
            if visibleItems.count > displayedItems.count {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
                        showsAllItems = true
                    }
                } label: {
                    Label("View \(visibleItems.count - displayedItems.count) more", systemImage: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.appBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
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

private struct HomeOrchestrationCard: View {
    let item: HomeOrchestrationItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.symbolName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(item.tone.tintColor)
                        .frame(width: 30, height: 30)
                        .background(item.tone.tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Spacer(minLength: 6)

                    Text(item.statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(item.tone.tintColor)
                        .lineLimit(1)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(item.tone.tintColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
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

import SwiftUI

struct SetupInfoCard: View {
    let title: String
    let detail: String
    let symbolName: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbolName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.brandAccent)
                .frame(width: 36, height: 36)
                .background(Color.appSymbolBlueBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        }
    }
}

struct SetupCapabilityDisclosureLabel: View {
    let title: String
    let detail: String
    let sourceStyle: String
    let webEnabled: Bool
    let wantsIronclaw: Bool
    let wantsCouncil: Bool
    let experienceMode: UserSetupExperienceMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: experienceMode == .power ? "bolt.circle.fill" : "slider.horizontal.3")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.brandAccent)
                    .frame(width: 36, height: 36)
                    .background(Color.appSymbolBlueBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ForEach(summaryPills, id: \.title) { pill in
                        SetupSummaryPill(title: pill.title, isActive: pill.isActive)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summaryPills, id: \.title) { pill in
                        SetupSummaryPill(title: pill.title, isActive: pill.isActive)
                    }
                }
            }
        }
    }

    private var summaryPills: [SetupCapabilitySummaryItem] {
        var pills = [
            SetupCapabilitySummaryItem(title: sourceStyle, isActive: true),
            SetupCapabilitySummaryItem(title: webEnabled ? "Web on" : "Web off", isActive: webEnabled)
        ]

        if wantsIronclaw {
            pills.append(SetupCapabilitySummaryItem(title: "Agent", isActive: true))
        }
        if wantsCouncil {
            pills.append(SetupCapabilitySummaryItem(title: "Council", isActive: true))
        }
        if experienceMode == .power && !wantsIronclaw && !wantsCouncil {
            pills.append(SetupCapabilitySummaryItem(title: "Power", isActive: true))
        }

        return pills
    }
}

private struct SetupCapabilitySummaryItem: Hashable {
    let title: String
    let isActive: Bool
}

private struct SetupSummaryPill: View {
    let title: String
    let isActive: Bool

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isActive ? Color.primaryAction : Color.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(isActive ? Color.selectionSubtle : Color.secondarySurface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(isActive ? Color.primaryAction.opacity(0.16) : Color.appBorder, lineWidth: 1)
            }
    }
}

struct SetupGoalField: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Default goal or workflow", systemImage: "text.badge.plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            TextField("Research, build agents, write code, manage projects…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...4)
                .tokenInputTraits()
                .padding(12)
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.appBorder : Color.brandAccent.opacity(0.14), lineWidth: 1)
                }
                .onChange(of: text) { _, value in
                    if value.count > 280 {
                        text = String(value.prefix(280))
                    }
                }
        }
    }
}

struct SetupHeroMetric: View {
    let title: String
    let symbolName: String

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Color.brandSky)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct SetupExampleChip: View {
    let preset: UserSetupStarterPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(preset.title, systemImage: preset.symbolName)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isSelected ? Color.primaryAction : Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(isSelected ? Color.selectionSubtle : Color.panel, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(isSelected ? Color.primaryAction.opacity(0.16) : Color.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

struct SetupQuietWebToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isOn ? "globe" : "globe.slash")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isOn ? Color.primaryAction : Color.textSecondary)
                .frame(width: 34, height: 34)
                .background(isOn ? Color.selectionSubtle : Color.secondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Use the web")
                    .font(.subheadline.weight(.semibold))
                Text(isOn ? "Current-source search can leave the private route." : "Off by default. Turn on only when current sources matter.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Toggle("Use the web", isOn: $isOn)
                .labelsHidden()
                .tint(.primaryAction)
        }
        .padding(12)
        .background(Color.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.border, lineWidth: 1)
        }
    }
}

struct SetupChoiceRow: View {
    enum SelectionStyle {
        case single
        case multi
    }

    let title: String
    let subtitle: String
    let symbolName: String
    let isSelected: Bool
    var selectionStyle: SelectionStyle = .single
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbolName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected ? Color.brandAccent : .secondary)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? Color.appSymbolBlueBackground : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: selectionSymbolName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.brandAccent : Color.secondary.opacity(0.35))
            }
            .padding(12)
            .background(isSelected ? Color.appSelection : Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.brandAccent.opacity(0.14) : Color.appBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var selectionSymbolName: String {
        switch selectionStyle {
        case .single:
            return isSelected ? "checkmark.circle.fill" : "circle"
        case .multi:
            return isSelected ? "checkmark.square.fill" : "square"
        }
    }
}

struct SetupReadinessLine: View {
    let plan: AppSetupPlan

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: plan.modelRoute.symbolName)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 26, height: 26)
                .background(Color.secondarySurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.readinessStatus)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Text(plan.focusBehavior)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
    }
}

struct SetupToggleRow: View {
    let title: String
    let subtitle: String
    let symbolName: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: symbolName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isOn ? Color.brandAccent : .secondary)
                    .frame(width: 40, height: 40)
                    .background(isOn ? Color.appSymbolBlueBackground : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(.actionPrimary)
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }
}

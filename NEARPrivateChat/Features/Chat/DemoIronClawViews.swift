import SwiftUI

#if DEBUG
struct DemoIronClawThinkingView: View {
    private let sources = [
        ("reborn-project-plan.md", "Attached plan"),
        ("#4066 lifecycle registry", "GitHub PR"),
        ("#4065 SSE replay fallback", "GitHub PR"),
        ("#4064 GitHub WASM install", "GitHub PR")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Thinking")
                        .font(.largeTitle.weight(.medium))
                        .foregroundStyle(.secondary)

                    DemoAgentTimelineStep(
                        symbolName: "folder",
                        title: "Reading attached project plan",
                        detail: "IronClaw is loading reborn-project-plan.md and the project instruction to update the plan from live GitHub evidence.",
                        chips: sources
                    )

                    DemoAgentTimelineStep(
                        symbolName: "magnifyingglass",
                        title: "Fetching latest IronClaw PRs",
                        detail: "Checking nearai/ironclaw open PRs and grouping the work into lifecycle, SSE replay, and first-party GitHub WASM milestones.",
                        chips: [
                            ("#4066", "Lifecycle"),
                            ("#4065", "SSE replay"),
                            ("#4064", "GitHub WASM")
                        ]
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Updating project plan", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.title3.weight(.semibold))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("markdown")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                            Text("""
                            ## Release train
                            1. Lifecycle registry (#4066)
                            2. SSE replay fallback (#4065)
                            3. GitHub WASM install (#4064)
                            4. Integration QA across activate -> replay
                            """)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                        }
                        .padding(12)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .padding(.leading, 36)

                    DemoAgentTimelineStep(
                        symbolName: "checkmark.seal",
                        title: "Preparing completed output",
                        detail: "The final answer returns what changed, why it changed, PR links, risks, and the updated plan inside the chat.",
                        chips: []
                    )
                }
                .padding(22)
            }
            .background(Color.appBackground)
            .navigationTitle("IronClaw")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {}
                }
            }
        }
    }
}

private struct DemoAgentTimelineStep: View {
    let symbolName: String
    let title: String
    let detail: String
    let chips: [(String, String)]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbolName)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !chips.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color.trustVerified.opacity(0.80))
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        Image(systemName: "arrow.up.right")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(chip.0)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text(chip.1)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 44)
                            .background(Color.appSecondaryBackground, in: Capsule())
                        }
                    }
                }
            }
        }
    }
}

private struct DemoCouncilLineupView: View {
    private let models = [
        ("GLM 5.1", "Private model answer", "NEAR Private · proof", "checkmark.shield.fill"),
        ("Claude Sonnet 4.6", "Cloud model answer", "NEAR AI Cloud · privacy proxy", "list.bullet.rectangle"),
        ("Qwen 3.6", "Cloud model answer", "NEAR AI Cloud · privacy proxy", "sparkles")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Council lineup matches the synthesis", systemImage: "square.grid.2x2")
                            .font(.headline.weight(.semibold))
                        Text("The same prompt goes to the private model and independent cloud models; the next screen shows each view and the synthesis.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 10) {
                        ForEach(Array(models.enumerated()), id: \.offset) { index, model in
                            HStack(spacing: 12) {
                                Image(systemName: model.3)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(index == 0 ? Color.trustVerified : Color.actionPrimary)
                                    .frame(width: 34, height: 34)
                                    .background((index == 0 ? Color.trustVerified : Color.actionPrimary).opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.0)
                                        .font(.subheadline.weight(.bold))
                                    Text(model.1)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(model.2)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(index == 0 ? Color.trustVerified : .secondary)
                                    .padding(.horizontal, 8)
                                    .frame(height: 22)
                                    .background(Color.appSecondaryBackground, in: Capsule())
                            }
                            .padding(12)
                            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.appBorder, lineWidth: 1)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Synthesizer")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Color.actionPrimary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("The synthesizer writes the final answer")
                                    .font(.subheadline.weight(.semibold))
                                Text("The synthesis keeps the headline, mechanics, and risks visible instead of hiding disagreement.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(18)
            }
            .background(Color.appBackground)
            .navigationTitle("Council")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {}
                }
            }
        }
    }
}

struct DemoIronClawModesView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("IronClaw")
                            .font(.title2.weight(.bold))
                        Text("Mobile for local, bounded tasks. Hosted IronClaw for shell, Git, tests, and GitHub.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    DemoIronClawModeCard(
                        title: "IronClaw Mobile",
                        subtitle: "Runs on the phone",
                        bodyText: "Good for reading the attached plan, drafting lightweight edits, and checking project context without connecting Hosted IronClaw.",
                        chips: ["Attached plan", "Phone-safe", "No repo access"],
                        symbolName: "iphone",
                        tint: .trustVerified
                    )

                    DemoIronClawModeCard(
                        title: "Hosted IronClaw",
                        subtitle: "Connected Hosted IronClaw",
                        bodyText: "The hosted run can fetch live GitHub PRs, update the attached plan, inspect repo context, and return a concrete artifact while the phone stays the control surface.",
                        chips: ["GitHub", "Shell", "Plan update", "Repo context", "Web"],
                        symbolName: "terminal",
                        tint: .actionPrimary
                    )
                }
                .padding(18)
            }
            .background(Color.appBackground)
            .navigationTitle("Agent")
            .platformInlineNavigationTitle()
            // The screen previously had no primary action and a large empty
            // lower half. Pin one dominant CTA plus a secondary so the route
            // choice is an action, not just two descriptive cards.
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {} label: {
                        Label("Use Hosted IronClaw", systemImage: "terminal")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(Color.actionPrimary, in: RoundedRectangle.app(AppRadius.control))
                    .accessibilityIdentifier("agent.primary.hosted")

                    Button {} label: {
                        Text("Use IronClaw Mobile instead")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.actionPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("agent.secondary.mobile")
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .background(Color.appBackground)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.appHairline).frame(height: 0.5)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {}
                }
            }
        }
    }
}

private struct DemoIronClawModeCard: View {
    let title: String
    let subtitle: String
    let bodyText: String
    let chips: [String]
    let symbolName: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: symbolName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ChipFlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(tint.opacity(0.09), in: Capsule())
                }
            }
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
    }
}
#endif

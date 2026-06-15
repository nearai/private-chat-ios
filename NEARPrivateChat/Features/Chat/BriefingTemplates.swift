import SwiftUI

// MARK: - One-tap templates for the named use cases

struct BriefingTemplate: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let kind: BriefingKind
    let schedule: BriefingSchedule
    let prompt: String
    let needsAccount: Bool

    static let suggested: [BriefingTemplate] = [
        BriefingTemplate(
            title: "Daily news brief",
            subtitle: "Top headlines, every weekday morning",
            symbol: "newspaper.fill",
            tint: .actionPrimary,
            kind: .dailyNews,
            schedule: .weekdays(hour: 8, minute: 0),
            prompt: "Today's top news",
            needsAccount: false
        ),
        BriefingTemplate(
            title: "Project digest",
            subtitle: "Open questions, risks, and next steps",
            symbol: "folder.badge.gearshape",
            tint: .proofVerified,
            kind: .customPrompt,
            schedule: .daily(hour: 9, minute: 0),
            prompt: "Review my active project context and summarize open questions, risks, and next steps.",
            needsAccount: false
        ),
        BriefingTemplate(
            title: "Research brief",
            subtitle: "New developments on a topic you care about",
            symbol: "doc.text.magnifyingglass",
            tint: .actionPrimary,
            kind: .customPrompt,
            schedule: .daily(hour: 8, minute: 0),
            prompt: "Research the latest credible developments on my saved topic and turn them into a short briefing with sources and follow-ups.",
            needsAccount: false
        )
    ]

    /// A single daily digest of everything you track — the proactive routine
    /// that drives recurring engagement.
    static let dailyBriefTemplate = BriefingTemplate(
        title: "Daily Brief",
        subtitle: "One digest of everything you track",
        symbol: "tray.full.fill",
        tint: .actionPrimary,
        kind: .dailyBrief,
        schedule: .daily(hour: 8, minute: 0),
        prompt: "Brief me",
        needsAccount: false
    )

    /// Suggestions tailored to what the user already tracks. Once a couple of
    /// things are tracked, the top suggestion becomes a single Daily Brief (the
    /// retention routine); market trackers without news get a news brief; and we
    /// never re-suggest a kind already tracked. Falls back to the default set
    /// when nothing is tracked yet.
    static func contextual(for trackers: [Briefing]) -> [BriefingTemplate] {
        let kinds = Set(trackers.map { $0.kind })
        var result: [BriefingTemplate] = []
        if trackers.count >= 2, !kinds.contains(.dailyBrief) {
            result.append(dailyBriefTemplate)
        }
        let tracksMarket = !kinds.isDisjoint(with: [.cryptoPrice, .ethPrice, .stockPrice, .commodityPrice, .watchlist])
        if tracksMarket, !kinds.contains(.dailyNews), let news = suggested.first(where: { $0.kind == .dailyNews }) {
            result.append(news)
        }
        for template in suggested
        where !result.contains(where: { $0.title == template.title }) &&
            (template.kind == .customPrompt || !kinds.contains(template.kind)) {
            result.append(template)
        }
        return Array(result.prefix(3))
    }

    func makeBriefing(account: String? = nil) -> Briefing {
        Briefing(title: title, prompt: prompt, schedule: schedule, kind: kind, accountID: account)
    }
}

/// Tappable suggestions that create (and immediately run) a briefing for each
/// named use case. NEAR account asks for the account id first.
struct SuggestedBriefingsView: View {
    @ObservedObject var store: BriefingStore
    var onOpen: (Briefing) -> Void = { _ in }

    @State private var pendingAccountTemplate: BriefingTemplate?
    @State private var accountInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(Color.textSecondary)

            let templates = BriefingTemplate.contextual(for: store.briefings)
            VStack(spacing: 0) {
                ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                    Button { tap(template) } label: { row(template) }
                        .buttonStyle(.plain)
                    if index < templates.count - 1 {
                        Divider().overlay(Color.appHairline).padding(.leading, 52)
                    }
                }
            }
            .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.appBorder, lineWidth: 1)
            }
        }
        .alert("Track a NEAR account", isPresented: Binding(
            get: { pendingAccountTemplate != nil },
            set: { if !$0 { pendingAccountTemplate = nil } }
        )) {
            TextField("yourname.near", text: $accountInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Track") { confirmAccount() }
            Button("Cancel", role: .cancel) { pendingAccountTemplate = nil }
        } message: {
            Text("Enter a NEAR mainnet account to track its balance and holdings.")
        }
    }

    private func row(_ template: BriefingTemplate) -> some View {
        HStack(spacing: 12) {
            BriefingIconChip(symbolName: template.symbol, tint: template.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(template.subtitle)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(Color.actionPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func tap(_ template: BriefingTemplate) {
        if template.needsAccount {
            accountInput = ""
            pendingAccountTemplate = template
        } else {
            create(template.makeBriefing())
        }
    }

    private func confirmAccount() {
        guard let template = pendingAccountTemplate else { return }
        let account = accountInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        pendingAccountTemplate = nil
        guard !account.isEmpty else { return }
        create(template.makeBriefing(account: account))
    }

    private func create(_ briefing: Briefing) {
        store.add(briefing)
        AppHaptics.lightImpact()
        Task {
            await store.run(briefing)
            // Open the post-run briefing so the thread shows the saved result,
            // not the pre-run "No delivery yet" state.
            let updated = store.briefings.first(where: { $0.id == briefing.id }) ?? briefing
            onOpen(updated)
        }
    }
}

import SwiftUI

// Threaded follow-ups (Paradigm 1).
// A briefing's deliveries rendered as a Slack-style thread: each daily delivery
// is a NEAR message; follow-ups branch into an inline side-thread anchored to
// that delivery, so questions don't pollute the main feed. Mirrors Threaded.jsx.

// MARK: - Model

/// Result of a briefing-thread follow-up: prose, a rendered widget (e.g. a real
/// historical price chart), or both.
typealias BriefingFollowUpResult = (text: String?, widget: MessageWidget?)

struct BriefingSourceTag: Identifiable, Hashable {
    let id = UUID()
    var letter: String
    var colorHex: String
}

struct ThreadReply: Identifiable, Hashable {
    enum Role { case user, assistant }
    let id = UUID()
    var role: Role
    var text: String
    var citations: [BriefingSourceTag] = []
    var verifiedModel: String? = nil
    var verifiedSources: Int = 0
    var ago: String? = nil
    /// An assistant reply can carry a rendered widget (e.g. a real historical
    /// price chart) instead of, or alongside, text.
    var widget: MessageWidget? = nil
}

struct DeliveryThread: Identifiable, Hashable {
    let id = UUID()
    var label: String
    var replies: [ThreadReply]
}

struct BriefingDelivery: Identifiable, Hashable {
    let id = UUID()
    var dayLabel: String          // "Yesterday" / "Today"
    var time: String              // "8:02"
    var title: String             // "Thu 28 May · briefing"
    var headline: String? = nil   // bold lead
    var summary: String? = nil    // subtext under the headline
    var body: String? = nil       // plain body (collapsed deliveries)
    var extra: String? = nil      // "+ Israel strikes Beirut · 2 more"
    var sources: [BriefingSourceTag] = []
    var replyCount: Int = 0
    var unread: Bool = false
    var collapsed: Bool = false
    var widget: MessageWidget? = nil
    var thread: DeliveryThread? = nil
}

// MARK: - Screen

struct ThreadedBriefingView: View {
    let title: String
    let schedule: String
    var onClose: () -> Void = {}
    private let store: BriefingStore?
    private let briefingID: UUID?
    /// Sends a follow-up `(question, context)` to the chat backend and returns
    /// the assistant's reply (text and/or a rendered widget). Injected by the
    /// parent (which holds ChatStore). Nil in previews → replies recorded locally.
    private let onAskFollowUp: ((String, String) async -> BriefingFollowUpResult)?

    @State private var deliveries: [BriefingDelivery]
    @State private var replyText = ""
    @State private var isRunning = false
    @State private var isReplying = false
    @State private var showingAccountEditor = false
    @State private var accountInput = ""

    init(
        title: String,
        schedule: String,
        deliveries: [BriefingDelivery],
        store: BriefingStore? = nil,
        briefingID: UUID? = nil,
        onAskFollowUp: ((String, String) async -> BriefingFollowUpResult)? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.title = title
        self.schedule = schedule
        self.store = store
        self.briefingID = briefingID
        self.onAskFollowUp = onAskFollowUp
        self.onClose = onClose
        _deliveries = State(initialValue: deliveries)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.appHairline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(deliveries) { delivery in
                        ThreadDayDivider(label: delivery.dayLabel)
                        BotDeliveryRow(delivery: delivery)
                        if let thread = delivery.thread {
                            ThreadInlineView(thread: thread)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            if isReplying {
                HStack(spacing: 8) {
                    NearMark(size: 18)
                    Text("NEAR is thinking…")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .transition(.opacity)
            }
            replyComposer
        }
        .background(Color.appBackground)
        .alert("Change NEAR account", isPresented: $showingAccountEditor) {
            TextField("yourname.near", text: $accountInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Update") { changeAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Track a different NEAR mainnet account in this briefing.")
        }
    }

    private var liveBriefing: Briefing? {
        guard let store, let briefingID else { return nil }
        return store.briefings.first(where: { $0.id == briefingID })
    }

    private func changeAccount() {
        guard let store, var briefing = liveBriefing else { return }
        let account = accountInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !account.isEmpty else { return }
        briefing.accountID = account
        store.update(briefing)
        runNow()
    }

    /// Re-arms a fired one-shot alert (un-pauses it) so it starts watching again.
    private func reArm() {
        guard let store, let briefing = liveBriefing else { return }
        store.setPaused(briefing, false)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 44, height: 44)
            }
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(schedule)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: 0)
            Menu {
                if store != nil, briefingID != nil {
                    Button { runNow() } label: { Label("Run now", systemImage: "arrow.clockwise") }
                    // A one-shot alert auto-pauses after firing; let the user re-arm it.
                    if let briefing = liveBriefing, briefing.isConditional, briefing.isPaused {
                        Button { reArm() } label: { Label("Re-arm alert", systemImage: "bell.badge") }
                    }
                    if liveBriefing?.kind == .nearAccount {
                        Button {
                            accountInput = liveBriefing?.accountID ?? ""
                            showingAccountEditor = true
                        } label: { Label("Change account", systemImage: "at") }
                    }
                    Button(role: .destructive) { deleteBriefing() } label: { Label("Delete briefing", systemImage: "trash") }
                } else {
                    Button("Mark all read") {}
                }
            } label: {
                Group {
                    if isRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold))
                    }
                }
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44, height: 44)
            }
            .disabled(isRunning)
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
    }

    private var replyComposer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                TextField("Reply in thread…", text: $replyText, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.appPanelBackground, in: Capsule())
            .overlay(Capsule().stroke(Color.appBorder, lineWidth: 1))

            Button(action: sendReply) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(replyTrimmed.isEmpty || isReplying ? Color.textTertiary : Color.actionPrimary)
            }
            .disabled(replyTrimmed.isEmpty || isReplying)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var replyTrimmed: String {
        replyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runNow() {
        guard let store, let briefingID,
              let briefing = store.briefings.first(where: { $0.id == briefingID }) else { return }
        isRunning = true
        Task {
            await store.run(briefing)
            if let updated = store.briefings.first(where: { $0.id == briefingID }) {
                deliveries = ThreadedBriefingView.deliveries(for: updated)
            }
            isRunning = false
        }
    }

    private func deleteBriefing() {
        guard let store, let briefingID,
              let briefing = store.briefings.first(where: { $0.id == briefingID }) else { return }
        store.remove(briefing)
        onClose()
    }

    private func sendReply() {
        let text = replyTrimmed
        guard !text.isEmpty, !isReplying, let index = deliveries.indices.last else { return }
        // Capture the conversation so far BEFORE appending the new question, so
        // follow-ups are multi-turn (the model remembers what we already discussed).
        let priorReplies = deliveries[index].thread?.replies ?? []
        appendReply(ThreadReply(role: .user, text: text), at: index, bumpCount: true)
        replyText = ""
        AppHaptics.lightImpact()

        // No backend wired (previews) → the user reply is recorded locally only.
        guard let onAskFollowUp else { return }
        let context = [
            ThreadedBriefingView.replyContext(for: deliveries[index]),
            ThreadedBriefingView.transcript(of: priorReplies)
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
        isReplying = true
        Task {
            let answer = await onAskFollowUp(text, context)
            await MainActor.run {
                let succeeded = answer.text != nil || answer.widget != nil
                let body = answer.text ?? (answer.widget == nil
                    ? "I couldn’t reach the model just now — try again in a moment."
                    : "")
                let reply = ThreadReply(
                    role: .assistant,
                    text: body,
                    verifiedModel: succeeded ? "GLM 5.1" : nil,
                    ago: "just now",
                    widget: answer.widget
                )
                if let target = deliveries.indices.last {
                    appendReply(reply, at: target, bumpCount: false)
                }
                isReplying = false
            }
        }
    }

    /// Appends a reply to the last delivery's inline thread (creating the thread
    /// on first use), keeping `replyCount` in sync for user turns.
    private func appendReply(_ reply: ThreadReply, at index: Int, bumpCount: Bool) {
        guard deliveries.indices.contains(index) else { return }
        var delivery = deliveries[index]
        var thread = delivery.thread ?? DeliveryThread(label: delivery.headline ?? delivery.title, replies: [])
        thread.replies.append(reply)
        delivery.thread = thread
        if bumpCount { delivery.replyCount += 1 }
        deliveries[index] = delivery
    }

    /// The prior thread turns as a compact transcript, so a follow-up is
    /// multi-turn (the model sees what we already discussed). Skips widget-only
    /// replies (no text) and caps at the last 8 turns to bound the prompt.
    static func transcript(of replies: [ThreadReply]) -> String {
        let lines = replies.suffix(8).compactMap { reply -> String? in
            let body = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            return "\(reply.role == .user ? "Me" : "NEAR"): \(body)"
        }
        return lines.isEmpty ? "" : "Conversation so far:\n" + lines.joined(separator: "\n")
    }

    /// The text a follow-up is grounded in: the delivery's widget note/summary
    /// or its body, so the model can answer questions about this specific result.
    static func replyContext(for delivery: BriefingDelivery) -> String {
        if let widget = delivery.widget {
            if let note = widget.note, !note.isEmpty { return note }
            return summary(for: widget)
        }
        return [delivery.headline, delivery.summary, delivery.body, delivery.extra]
            .compactMap { $0 }
            .joined(separator: "\n")
    }
}

// MARK: - Subviews

private struct ThreadDayDivider: View {
    let label: String
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.appHairline).frame(height: 0.5)
            Text(label.uppercased())
                .font(.system(size: 11, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(Color.textTertiary)
            Rectangle().fill(Color.appHairline).frame(height: 0.5)
        }
    }
}

private struct BotDeliveryRow: View {
    let delivery: BriefingDelivery

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NearMark(size: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("NEAR")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(delivery.time)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                    if delivery.unread {
                        HStack(spacing: 4) {
                            Circle().fill(Color.proofVerified).frame(width: 6, height: 6)
                            Text("new")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.proofVerified)
                        }
                    }
                }

                Text(delivery.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                if let widget = delivery.widget {
                    // A live briefing (price/account/news) renders its real
                    // widget card here, not just a text summary.
                    MessageWidgetCard(widget: widget)
                        .padding(.top, 4)
                } else if let headline = delivery.headline {
                    Text(headline)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let summary = delivery.summary {
                        Text(summary)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let extra = delivery.extra {
                        Text(extra)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textTertiary)
                            .padding(.top, 2)
                    }
                } else if let body = delivery.body {
                    Text(body)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !delivery.sources.isEmpty || delivery.replyCount > 0 {
                    HStack(spacing: 8) {
                        if !delivery.sources.isEmpty {
                            HStack(spacing: 3) {
                                ForEach(delivery.sources) { FaviconChip(source: $0, size: 14) }
                            }
                        }
                        if delivery.replyCount > 0 {
                            HStack(spacing: 6) {
                                Image(systemName: "bubble.left.fill").font(.system(size: 10))
                                Text("\(delivery.replyCount) replies").font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Color.actionPress)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .opacity(delivery.collapsed ? 0.5 : 1)
    }
}

private struct ThreadInlineView: View {
    let thread: DeliveryThread

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 1).fill(Color.actionFill).frame(width: 2)
            VStack(alignment: .leading, spacing: 12) {
                Text("Thread · \(thread.label)".uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Color.textTertiary)

                ForEach(thread.replies) { reply in
                    if reply.role == .user {
                        HStack {
                            Spacer(minLength: 40)
                            Text(reply.text)
                                .font(.system(size: 14))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            NearMark(size: 20)
                            VStack(alignment: .leading, spacing: 6) {
                                if let widget = reply.widget {
                                    MessageWidgetCard(widget: widget)
                                }
                                if !reply.text.isEmpty {
                                    MarkdownMessageText(text: reply.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if !reply.citations.isEmpty {
                                    HStack(spacing: 4) {
                                        ForEach(Array(reply.citations.enumerated()), id: \.offset) { index, _ in
                                            CitePill(n: index + 1)
                                        }
                                    }
                                }
                                if let model = reply.verifiedModel {
                                    ThreadVerifiedFooter(model: model, sources: reply.verifiedSources, ago: reply.ago ?? "just now")
                                }
                            }
                        }
                    }
                }
            }
            .padding(.leading, 14)
        }
        .padding(.leading, 32)
    }
}

private struct CitePill: View {
    let n: Int
    var body: some View {
        Text("\(n)")
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.actionPrimary)
            .frame(width: 16, height: 16)
            .background(Color.actionTint, in: Circle())
    }
}

private struct ThreadVerifiedFooter: View {
    let model: String
    let sources: Int
    let ago: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.proofVerified)
            Text(footerText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.top, 2)
    }
    private var footerText: String {
        var parts = ["Verified", model]
        if sources > 0 { parts.append("\(sources) sources") }
        parts.append(ago)
        return parts.joined(separator: " · ")
    }
}

private struct FaviconChip: View {
    let source: BriefingSourceTag
    var size: CGFloat = 14
    var body: some View {
        Text(source.letter.prefix(1))
            .font(.system(size: size * 0.6, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(threadHexColor(source.colorHex), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

private func threadHexColor(_ hex: String) -> Color {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return .actionPrimary }
    return Color(
        red: Double((v >> 16) & 0xFF) / 255,
        green: Double((v >> 8) & 0xFF) / 255,
        blue: Double(v & 0xFF) / 255
    )
}

// MARK: - Mapping a live Briefing into deliveries

extension ThreadedBriefingView {
    init(
        briefing: Briefing,
        store: BriefingStore? = nil,
        onAskFollowUp: ((String, String) async -> BriefingFollowUpResult)? = nil,
        onClose: @escaping () -> Void = {}
    ) {
        self.init(
            title: briefing.title,
            schedule: briefing.schedule.scheduleLabel,
            deliveries: ThreadedBriefingView.deliveries(for: briefing),
            store: store,
            briefingID: briefing.id,
            onAskFollowUp: onAskFollowUp,
            onClose: onClose
        )
    }

    static func deliveries(for briefing: Briefing) -> [BriefingDelivery] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        let runDate = briefing.lastRunAt ?? Date()
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mma"
        let body = briefing.latestResult.map(summary(for:))
            ?? "No delivery yet — it will appear here after the next scheduled run."
        return [
            BriefingDelivery(
                dayLabel: Calendar.current.isDateInToday(runDate) ? "Today" : formatter.string(from: runDate),
                time: briefing.lastRunAt == nil ? "—" : timeFormatter.string(from: runDate).lowercased(),
                title: "\(formatter.string(from: runDate)) · briefing",
                body: body,
                unread: briefing.lastRunAt != nil,
                widget: briefing.latestResult
            )
        ]
    }

    private static func summary(for widget: MessageWidget) -> String {
        if let chart = widget.chart, let value = chart.value {
            return [chart.label, value, chart.delta].compactMap { $0 }.joined(separator: " · ")
        }
        if let metric = widget.metric {
            return [metric.label, metric.value, metric.delta].compactMap { $0 }.joined(separator: " · ")
        }
        if let brief = widget.newsBrief, !brief.stories.isEmpty {
            return brief.stories.prefix(3).map(\.title).joined(separator: " · ")
        }
        if let comparison = widget.comparison, let subtitle = comparison.subtitle {
            return subtitle
        }
        return widget.note ?? widget.title ?? "Briefing delivered."
    }
}

#if DEBUG
extension ThreadedBriefingView {
    static var demoDeliveries: [BriefingDelivery] {
        [
            BriefingDelivery(
                dayLabel: "Yesterday",
                time: "8:02",
                title: "Wed 27 May · briefing",
                body: "Markets steady on Fed pause. UN brokers Lebanon talks. SpaceX Starship 14 launches.",
                replyCount: 5,
                collapsed: true
            ),
            BriefingDelivery(
                dayLabel: "Today",
                time: "8:02",
                title: "Thu 28 May · briefing",
                headline: "US–Iran ceasefire under strain",
                summary: "US strikes Iranian drone sites near Hormuz. 60-day extension under discussion.",
                extra: "+ Israel strikes Beirut · ETH down 2.3% · 2 more",
                sources: [
                    BriefingSourceTag(letter: "W", colorHex: "#ff7e1c"),
                    BriefingSourceTag(letter: "N", colorHex: "#0091FD"),
                    BriefingSourceTag(letter: "a", colorHex: "#000000")
                ],
                replyCount: 2,
                unread: true,
                thread: DeliveryThread(
                    label: "US–Iran ceasefire",
                    replies: [
                        ThreadReply(role: .user, text: "what's the impact on oil?"),
                        ThreadReply(
                            role: .assistant,
                            text: "Brent fell 3.1% on talks of reopening Hormuz; futures pricing in a 60% chance of an extension this week.",
                            citations: [
                                BriefingSourceTag(letter: "r", colorHex: "#FF6B35"),
                                BriefingSourceTag(letter: "B", colorHex: "#000000")
                            ],
                            verifiedModel: "GLM 5.1",
                            verifiedSources: 2,
                            ago: "just now"
                        )
                    ]
                )
            )
        ]
    }
}

#Preview("Threaded briefing") {
    ThreadedBriefingView(
        title: "Daily briefing",
        schedule: "Every weekday · 8:00am",
        deliveries: ThreadedBriefingView.demoDeliveries
    )
}
#endif

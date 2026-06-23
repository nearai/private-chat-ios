import SwiftUI

// Threaded follow-ups (Paradigm 1).
// A briefing's deliveries rendered as a Slack-style thread: each daily delivery
// is a NEAR message; follow-ups branch into an inline side-thread anchored to
// that delivery, so questions don't pollute the main feed. Mirrors Threaded.jsx.

// MARK: - Model

/// Result of a briefing-thread follow-up: prose, a rendered widget (e.g. a real
/// historical price chart), or an explicit failure that should not look verified.
struct BriefingFollowUpResult {
    var text: String?
    var widget: MessageWidget?
    var error: String?
    /// Restricted private-route failures can carry a proxy model for a
    /// disclosed one-tap retry. Model/account failures leave this nil.
    var proxyModelID: String?

    var succeeded: Bool {
        text != nil || widget != nil
    }

    static func success(text: String? = nil, widget: MessageWidget? = nil) -> BriefingFollowUpResult {
        BriefingFollowUpResult(text: text, widget: widget, error: nil)
    }

    static func failure(_ message: String?) -> BriefingFollowUpResult {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return BriefingFollowUpResult(
            text: nil,
            widget: nil,
            error: trimmed.isEmpty ? "I couldn’t reach the model just now — try again in a moment." : trimmed
        )
    }
}

struct BriefingSourceTag: Identifiable, Hashable {
    let id = UUID()
    var letter: String
    var colorHex: String
    var faviconDomain: String? = nil
    var allowsNetworkFavicon: Bool = false
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
    /// Failed replies that can be retried via the privacy proxy carry the
    /// proxy model + the original question, so the row offers one tap.
    var proxyModelID: String? = nil
    var proxyRetryQuestion: String? = nil
}

struct DeliveryThread: Identifiable, Hashable {
    let id = UUID()
    var label: String
    var replies: [ThreadReply]
}

enum BriefingDeliveryKind: String, Hashable {
    case briefing
    case watcher
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
    var sourceStatusText: String? = nil
    var verifiedModel: String? = nil
    var replyCount: Int = 0
    var unread: Bool = false
    var collapsed: Bool = false
    var isFailure: Bool = false   // failed run — render error styling + retry
    var isPending: Bool = false
    var itemKind: BriefingDeliveryKind = .briefing
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
    private let onAskFollowUp: ((String, String, String?) async -> BriefingFollowUpResult)?

    @State private var deliveries: [BriefingDelivery]
    @State private var replyText = ""
    @State private var isRunning = false
    @State private var isReplying = false
    @State private var showingAccountEditor = false
    @State private var showingActions = false
    @State private var accountInput = ""

    init(
        title: String,
        schedule: String,
        deliveries: [BriefingDelivery],
        store: BriefingStore? = nil,
        briefingID: UUID? = nil,
        onAskFollowUp: ((String, String, String?) async -> BriefingFollowUpResult)? = nil,
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
                        BotDeliveryRow(
                            delivery: delivery,
                            onRetry: delivery.isFailure && store != nil && briefingID != nil && !isRunning
                                ? { runNow() }
                                : nil
                        )
                        if let thread = delivery.thread {
                            ThreadInlineView(thread: thread, onUseProxy: { reply in
                                retryReplyViaProxy(reply)
                            })
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
                        .font(.caption2)
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
        .confirmationDialog("Briefing actions", isPresented: $showingActions, titleVisibility: .visible) {
            briefingActionButtons
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
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 44, height: 44)
            }
            Spacer(minLength: 0)
            VStack(spacing: 1) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(schedule)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer(minLength: 0)
            Button {
                showingActions = true
            } label: {
                Group {
                    if isRunning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.title3.weight(.semibold))
                    }
                }
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            }
            .disabled(isRunning)
            .accessibilityLabel("More briefing actions")
            .accessibilityIdentifier("threadedBriefing.moreActions")
        }
        .padding(.horizontal, 8)
        .frame(height: 52)
    }

    @ViewBuilder
    private var briefingActionButtons: some View {
        if store != nil, briefingID != nil {
            Button("Run now") { runNow() }
                .accessibilityIdentifier("tracker.runNow")
            // A one-shot alert auto-pauses after firing; let the user re-arm it.
            if let briefing = liveBriefing, briefing.isConditional, briefing.isPaused {
                Button("Re-arm alert") { reArm() }
            }
            if liveBriefing?.kind == .nearAccount {
                Button("Change account") {
                    accountInput = liveBriefing?.accountID ?? ""
                    showingAccountEditor = true
                }
            }
            Button("Delete briefing", role: .destructive) { deleteBriefing() }
        } else {
            Button("Mark all read") {}
        }
    }

    private var replyComposer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textTertiary)
                TextField("Reply in thread…", text: $replyText, axis: .vertical)
                    .font(.subheadline)
                    .lineLimit(1...4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.appPanelBackground, in: Capsule())
            .overlay(Capsule().stroke(Color.appBorder, lineWidth: 1))

            Button(action: sendReply) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(replyTrimmed.isEmpty || isReplying ? Color.textTertiary : Color.actionPrimary)
                    .frame(width: 44, height: 44)
            }
            .disabled(replyTrimmed.isEmpty || isReplying)
            .accessibilityLabel("Send thread reply")
            .accessibilityIdentifier("threadedBriefing.sendReply")
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
        guard onAskFollowUp != nil else { return }
        let context = [
            ThreadedBriefingView.replyContext(for: deliveries[index]),
            ThreadedBriefingView.transcript(of: priorReplies)
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
        isReplying = true
        runFollowUp(question: text, context: context, viaProxyModelID: nil, verifiedLabel: "NEAR Private")
    }

    /// Runs a follow-up (optionally through the privacy proxy) and appends the
    /// reply. Only restricted private-route failures carry a proxy retry offer.
    private func runFollowUp(question: String, context: String, viaProxyModelID: String?, verifiedLabel: String) {
        guard let onAskFollowUp else { isReplying = false; return }
        Task {
            let answer = await onAskFollowUp(question, context, viaProxyModelID)
            await MainActor.run {
                let body = answer.text ?? (answer.widget == nil ? answer.error ?? BriefingFollowUpResult.failure(nil).error ?? "" : "")
                let reply = ThreadReply(
                    role: .assistant,
                    text: body,
                    verifiedModel: answer.succeeded ? verifiedLabel : nil,
                    ago: "just now",
                    widget: answer.widget,
                    proxyModelID: answer.succeeded ? nil : answer.proxyModelID,
                    proxyRetryQuestion: answer.succeeded ? nil : question
                )
                if let target = deliveries.indices.last {
                    appendReply(reply, at: target, bumpCount: false)
                }
                isReplying = false
            }
        }
    }

    /// One-tap retry of a failed thread reply through the privacy proxy.
    private func retryReplyViaProxy(_ reply: ThreadReply) {
        guard let proxyModelID = reply.proxyModelID,
              let question = reply.proxyRetryQuestion,
              let index = deliveries.indices.last else { return }
        let priorReplies = deliveries[index].thread?.replies ?? []
        let context = [
            ThreadedBriefingView.replyContext(for: deliveries[index]),
            ThreadedBriefingView.transcript(of: priorReplies)
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
        isReplying = true
        runFollowUp(question: question, context: context, viaProxyModelID: proxyModelID, verifiedLabel: "Privacy proxy")
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

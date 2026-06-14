import SwiftUI

struct CouncilResponseGroup: View {
    let messages: [ChatMessage]
    let chatStore: ChatStore
    @State private var selectedMessageID: String?
    @State private var showingRoom = false

    private var selectedMessage: ChatMessage? {
        let currentID = selectedMessageID ?? preferredMessage?.id
        return messages.first(where: { $0.id == currentID }) ?? messages.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandAccent)
                    .frame(width: 28, height: 28)
                    .background(Color.brandSky.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text("LLM Council")
                        .font(.caption.weight(.semibold))
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if hasRunningModels {
                    Button {
                        if canStopWaiting {
                            chatStore.stopWaitingForCouncil(batchID: batchID)
                        } else {
                            chatStore.cancelStream()
                        }
                    } label: {
                        Label(canStopWaiting ? "Stop waiting" : "Cancel", systemImage: canStopWaiting ? "forward.end.fill" : "xmark")
                            .font(.caption2.weight(.bold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(canStopWaiting ? Color.brandAccent : .secondary)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 44)
                    .background((canStopWaiting ? Color.brandAccent : Color.secondary).opacity(0.09), in: Capsule())
                    .accessibilityHint(canStopWaiting ? "Synthesize from completed Council answers now" : "Cancel the Council run")
                }

                if messages.contains(where: \.hasUsableCouncilAnswer) {
                    Button { showingRoom = true } label: {
                        Label("Room", systemImage: "person.3.fill")
                            .accessibilityIdentifier("council.room")
                            .font(.caption2.weight(.bold))
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.brandAccent)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 44)
                    .background(Color.brandAccent.opacity(0.09), in: Capsule())
                    .accessibilityHint("Open the Council room view")
                }
            }

            if hasRunningModels {
                TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                    progressRows(now: timeline.date)
                }

                if let selectedMessage {
                    CouncilSelectedMessageView(
                        message: selectedMessage,
                        chatStore: chatStore,
                        preferLightweightPreview: true
                    )
                }
            } else {
                CouncilAnswerTabs(
                    messages: messages,
                    chatStore: chatStore
                )
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandAccent.opacity(0.13), lineWidth: 1)
        }
        .onAppear {
            selectedMessageID = selectedMessageID ?? messages.first?.id
        }
        .onChange(of: messageIDs) { _, _ in
            guard let selectedMessageID,
                  messages.contains(where: { $0.id == selectedMessageID }) else {
                self.selectedMessageID = messages.first?.id
                return
            }
        }
        .sheet(isPresented: $showingRoom) {
            CouncilRoomView(
                model: CouncilRoomModel.from(councilMessages: messages),
                supportsTargetedSend: true,
                synthesizeTitle: synthesizeTitle,
                onSend: { text, target in
                    chatStore.sendCouncilRoomFollowUp(text, batchID: batchID, target: target)
                    showingRoom = false
                },
                onSynthesize: {
                    chatStore.synthesizeCouncilBatch(batchID: batchID)
                    showingRoom = false
                }
            )
        }
        .accessibilityIdentifier("council.group")
    }

    @ViewBuilder
    private func progressRows(now: Date) -> some View {
        VStack(spacing: 6) {
            ForEach(messages) { message in
                CouncilModelProgressRow(
                    message: message,
                    now: now,
                    isSelected: message.id == selectedMessage?.id
                ) {
                    selectedMessageID = message.id
                }
            }
        }
    }

    private var batchID: String? {
        messages.first?.councilBatchID
    }

    private var messageIDs: [String] {
        messages.map(\.id)
    }

    private var preferredMessage: ChatMessage? {
        messages.first(where: \.hasUsableCouncilAnswer) ?? messages.first
    }

    private var statusText: String {
        CouncilResponseGroupStatusText.text(for: messages)
    }

    private var hasRunningModels: Bool {
        messages.contains(where: \.isStreaming)
    }

    private var canStopWaiting: Bool {
        hasRunningModels && messages.contains(where: \.hasUsableCouncilAnswer)
    }

    private var synthesizeTitle: String? {
        let usableCount = messages.filter(\.hasUsableCouncilAnswer).count
        guard usableCount > 1 else { return nil }
        return hasRunningModels ? "Synthesize now" : "Synthesize again"
    }
}

enum CouncilResponseGroupStatusText {
    static func text(for messages: [ChatMessage]) -> String {
        let memberMessages = nonSynthesisMessages(in: messages)
        let ready = memberMessages.filter(\.hasUsableCouncilAnswer).count
        let running = memberMessages.filter(\.isStreaming).count
        let failed = memberMessages.filter { $0.status == "failed" }.count

        if running > 0 {
            return ready > 0 ? "\(ready) ready · \(running) still running" : "\(running) models thinking"
        }
        if failed > 0, ready > 0 {
            return "\(ready) ready · \(failed) failed"
        }
        if failed > 0 {
            return "\(failed) failed"
        }

        return ready == memberMessages.count
            ? "\(ready) \(answerNoun(for: ready)) ready"
            : "\(ready) usable \(answerNoun(for: ready))"
    }

    private static func nonSynthesisMessages(in messages: [ChatMessage]) -> [ChatMessage] {
        let members = messages.filter { !isSynthesisMessage($0) }
        return members.isEmpty ? messages : members
    }

    private static func isSynthesisMessage(_ message: ChatMessage) -> Bool {
        guard let modelID = message.model?.trimmingCharacters(in: .whitespacesAndNewlines),
              !modelID.isEmpty else {
            return false
        }
        return modelID == ModelOption.llmCouncilSynthesisModelID ||
            modelID.localizedCaseInsensitiveContains("council/synthesis") ||
            modelID.localizedCaseInsensitiveContains("synthesis")
    }

    private static func answerNoun(for count: Int) -> String {
        count == 1 ? "answer" : "answers"
    }
}

private struct CouncilSelectedMessageView: View {
    let message: ChatMessage
    let chatStore: ChatStore
    let preferLightweightPreview: Bool

    var body: some View {
        if message.isStreaming {
            StreamingMessageText(message: message)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else if preferLightweightPreview {
            CouncilAnswerPreview(message: message)
        } else {
            MessageBubble(message: message, chatStore: chatStore)
        }
    }
}

private struct CouncilAnswerPreview: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: statusSymbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusTint)
                Text(message.modelDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(statusText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusTint)
            }

            if previewText.isEmpty {
                Text("Waiting for an answer.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text(MarkdownStreamSanitizer.strippedInline(previewText))
                    .font(.callout)
                    .lineSpacing(2)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var previewText: String {
        StreamingPreviewHelper.preview(from: message.text, emptyPlaceholder: "")
    }

    private var statusText: String {
        if message.status == "failed" {
            return CouncilStreamService.statusText(
                for: CouncilStreamService.errorKind(forFailureSummary: message.text)
            )
        }
        return message.hasUsableCouncilAnswer ? "Ready" : "Pending"
    }

    private var statusSymbolName: String {
        if message.status == "failed" {
            return "exclamationmark.triangle.fill"
        }
        return message.hasUsableCouncilAnswer ? "checkmark.circle.fill" : "circle"
    }

    private var statusTint: Color {
        if message.status == "failed" {
            return .red
        }
        return message.hasUsableCouncilAnswer ? Color.verifiedGreen : .secondary
    }
}

private struct CouncilModelProgressRow: View {
    let message: ChatMessage
    let now: Date
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 9) {
                Image(systemName: symbolName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tintColor)
                    .frame(width: 24, height: 24)
                    .background(tintColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(message.modelDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(progressText)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.brandAccent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isSelected ? Color.brandAccent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(message.modelDisplayName), \(progressText)")
    }

    private var symbolName: String {
        if message.status == "failed" {
            return "exclamationmark.triangle.fill"
        }
        if message.isStreaming, message.firstTokenAt != nil {
            return "waveform"
        }
        if message.isStreaming {
            return "hourglass"
        }
        if message.hasUsableCouncilAnswer {
            return "checkmark.circle.fill"
        }
        return "circle"
    }

    private var tintColor: Color {
        if message.status == "failed" {
            return .red
        }
        if message.isStreaming {
            return Color.brandAccent
        }
        if message.hasUsableCouncilAnswer {
            return Color.verifiedGreen
        }
        return .secondary
    }

    private var progressText: String {
        if message.status == "failed" {
            return CouncilStreamService.statusText(
                for: CouncilStreamService.errorKind(forFailureSummary: message.text)
            )
        }
        if message.isStreaming {
            if let latency = message.firstTokenLatency {
                return "Writing · first token \(formatSeconds(latency))"
            }
            return "Waiting · \(formatSeconds(now.timeIntervalSince(message.createdAt)))"
        }
        if message.hasUsableCouncilAnswer {
            if let latency = message.firstTokenLatency {
                return "Done · first token \(formatSeconds(latency))"
            }
            return "Done"
        }
        return "No answer"
    }

    private func formatSeconds(_ value: TimeInterval) -> String {
        let clamped = max(0, value)
        if clamped < 10 {
            return String(format: "%.1fs", clamped)
        }
        return "\(Int(clamped.rounded()))s"
    }
}

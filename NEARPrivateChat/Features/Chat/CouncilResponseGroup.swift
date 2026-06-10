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
                    .foregroundStyle(Color.brandBlue)
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
                    .foregroundStyle(canStopWaiting ? Color.brandBlue : .secondary)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background((canStopWaiting ? Color.brandBlue : Color.secondary).opacity(0.09), in: Capsule())
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
                    .foregroundStyle(Color.brandBlue)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(Color.brandBlue.opacity(0.09), in: Capsule())
                    .accessibilityHint("Open the Council room view")
                }
            }

            if hasRunningModels {
                TimelineView(.periodic(from: Date(), by: 1)) { timeline in
                    progressRows(now: timeline.date)
                }
            } else {
                progressRows(now: Date())
            }

            if let selectedMessage {
                CouncilSelectedMessageView(
                    message: selectedMessage,
                    chatStore: chatStore,
                    preferLightweightPreview: hasRunningModels
                )
            }
        }
        .padding(12)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.13), lineWidth: 1)
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
        let ready = messages.filter(\.hasUsableCouncilAnswer).count
        let running = messages.filter(\.isStreaming).count
        let failed = messages.filter { $0.status == "failed" }.count
        if running > 0 {
            return ready > 0 ? "\(ready) ready · \(running) still running" : "\(running) models thinking"
        }
        if failed > 0, ready > 0 {
            return "\(ready) ready · \(failed) failed"
        }
        if failed > 0 {
            return "\(failed) failed"
        }
        return ready == messages.count ? "\(messages.count) answers ready" : "\(ready) usable answers"
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
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let cappedText: String
        let isCapped: Bool
        if trimmed.utf8.count > 4_000 {
            cappedText = String(trimmed.suffix(4_000))
            isCapped = true
        } else {
            cappedText = trimmed
            isCapped = false
        }
        let lines = cappedText
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let preview = lines.isEmpty ? cappedText : lines.suffix(12).joined(separator: "\n")
        return isCapped ? "...\n\(preview)" : preview
    }

    private var statusText: String {
        if message.status == "failed" {
            return "Failed"
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
                        .foregroundStyle(Color.brandBlue)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(isSelected ? Color.brandBlue.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            return Color.brandBlue
        }
        if message.hasUsableCouncilAnswer {
            return Color.verifiedGreen
        }
        return .secondary
    }

    private var progressText: String {
        if message.status == "failed" {
            return "Failed"
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

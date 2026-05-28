import Foundation
import SwiftUI

/**
 INTEGRATION

 Present `CouncilRoomView` from `ChatScreenView` by adding an "Open Council Room"
 affordance to a council response group or to any message with a non-empty
 `councilBatchID`. Build the room with:

 `CouncilRoomModel.from(councilMessages: messages.filter { $0.councilBatchID == batchID })`

 Wire `onSend` to the existing targeted send path in `ChatStore`: `.room` should
 send a follow-up to the whole council, while `.model(id:)` should address only
 the selected model id. Wire `onSynthesize` to the existing council synthesis
 path so the app re-runs synthesis for that batch.

 Stance and synthesis chips here are honest best-effort heuristics over existing
 text. If product needs non-heuristic agreement, disagreement, or next-step
 data, steer the synthesis prompt to emit that structure explicitly, analogous
 to the existing near-widget steering, then map those fields into
 `CouncilSynthesisVM` and `CouncilStance`.
 */

enum CouncilStance {
    case agrees
    case dissents
    case reasoning
    case neutral
}

struct CouncilParticipant: Identifiable {
    let id: String
    let modelID: String
    let displayName: String
    let color: Color
    let stance: CouncilStance
}

struct CouncilMessageVM: Identifiable {
    let id: String
    let participant: CouncilParticipant
    let text: String
    let isStreaming: Bool
}

struct CouncilSynthesisVM {
    let agreement: String?
    let disagreement: String?
    let nextStep: String?
    let fullText: String
}

enum CouncilTarget: Hashable {
    case room
    case model(id: String)
}

struct CouncilRoomModel {
    let title: String
    let subtitle: String
    let participants: [CouncilParticipant]
    let messages: [CouncilMessageVM]
    let synthesis: CouncilSynthesisVM?

    static func from(councilMessages: [ChatMessage]) -> CouncilRoomModel {
        let batchID = councilMessages
            .compactMap { $0.councilBatchID?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        let scopedMessages: [ChatMessage]
        if let batchID {
            scopedMessages = councilMessages.filter { $0.councilBatchID == batchID }
        } else {
            scopedMessages = councilMessages
        }

        let assistantMessages = scopedMessages.filter { $0.role == .assistant }
        let synthesisMessage = assistantMessages.first(where: isSynthesisMessage)
        var participantByModel = [String: CouncilParticipant]()
        var participants = [CouncilParticipant]()
        var rows = [CouncilMessageVM]()

        for message in assistantMessages where message.id != synthesisMessage?.id {
            let modelID = normalizedModelID(for: message)
            let participant: CouncilParticipant
            if let existing = participantByModel[modelID] {
                participant = existing
            } else {
                let newParticipant = CouncilParticipant(
                    id: modelID,
                    modelID: modelID,
                    displayName: displayName(for: modelID),
                    color: stableColor(for: modelID),
                    stance: stance(for: message)
                )
                participantByModel[modelID] = newParticipant
                participants.append(newParticipant)
                participant = newParticipant
            }

            rows.append(
                CouncilMessageVM(
                    id: message.id,
                    participant: participant,
                    text: message.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    isStreaming: message.isStreaming
                )
            )
        }

        let subtitle = subtitle(for: participants, messages: rows)
        let synthesis = synthesisMessage.flatMap { synthesisModel(from: $0.text) }

        return CouncilRoomModel(
            title: "Council",
            subtitle: subtitle,
            participants: participants,
            messages: rows,
            synthesis: synthesis
        )
    }

    private static func normalizedModelID(for message: ChatMessage) -> String {
        let trimmed = message.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "assistant-\(message.id)" : trimmed
    }

    private static func displayName(for modelID: String) -> String {
        if modelID.hasPrefix("assistant-") {
            return "Assistant"
        }
        if isSynthesisModel(modelID) {
            return "Council Synthesis"
        }
        return ModelOption.humanize(modelID: modelID)
            .replacingOccurrences(of: "Glm", with: "GLM")
    }

    private static func stableColor(for modelID: String) -> Color {
        let palette: [Color] = [
            .brandBlue,
            .proofVerified,
            .proofStale,
            .proofMismatch,
            .actionPrimary,
            .textSecondary
        ]
        var hash: UInt64 = 1_469_598_103_934_665_603
        for scalar in modelID.unicodeScalars {
            hash ^= UInt64(scalar.value)
            hash &*= 1_099_511_628_211
        }
        return palette[Int(hash % UInt64(palette.count))]
    }

    private static func stance(for message: ChatMessage) -> CouncilStance {
        if message.isStreaming {
            return .reasoning
        }

        let text = message.text
        if containsAny(text, patterns: [
            #"\bagree(s|d|ing)?\b"#,
            #"\bconcur(s|red|ring)?\b"#
        ]) {
            return .agrees
        }
        if containsAny(text, patterns: [
            #"\bdisagree(s|d|ing)?\b"#,
            #"\bdissent(s|ed|ing)?\b"#,
            #"\bhowever\b"#
        ]) {
            return .dissents
        }
        return .neutral
    }

    private static func containsAny(_ text: String, patterns: [String]) -> Bool {
        patterns.contains { pattern in
            text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func isSynthesisMessage(_ message: ChatMessage) -> Bool {
        guard let modelID = message.model?.trimmingCharacters(in: .whitespacesAndNewlines),
              !modelID.isEmpty else {
            return false
        }
        return isSynthesisModel(modelID)
    }

    private static func isSynthesisModel(_ modelID: String) -> Bool {
        modelID == "llm-council/synthesis" ||
            modelID.localizedCaseInsensitiveContains("council/synthesis") ||
            modelID.localizedCaseInsensitiveContains("synthesis")
    }

    private static func subtitle(for participants: [CouncilParticipant], messages: [CouncilMessageVM]) -> String {
        var parts = participants.map(\.displayName)
        let reasoningCount = messages.filter(\.isStreaming).count
        if reasoningCount > 0 {
            parts.append("\(reasoningCount) reasoning")
        }
        return parts.isEmpty ? "No council answers yet" : parts.joined(separator: " · ")
    }

    private static func synthesisModel(from text: String) -> CouncilSynthesisVM? {
        let fullText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fullText.isEmpty else { return nil }

        return CouncilSynthesisVM(
            agreement: section(
                in: fullText,
                labels: ["agreement", "what the council agrees on", "consensus"]
            ),
            disagreement: section(
                in: fullText,
                labels: ["disagreement", "where they differ", "dissent"]
            ),
            nextStep: section(
                in: fullText,
                labels: ["recommended next step", "next step", "recommendation"]
            ),
            fullText: fullText
        )
    }

    private static func section(in text: String, labels: [String]) -> String? {
        let lines = text.components(separatedBy: .newlines)
        var capturing = false
        var captured = [String]()

        for line in lines {
            let normalized = normalizedHeading(line)
            if labels.contains(normalized) {
                capturing = true
                let remainder = headingRemainder(line)
                if !remainder.isEmpty {
                    captured.append(remainder)
                }
                continue
            }
            if capturing, isAnyHeading(line) {
                break
            }
            if capturing {
                captured.append(line)
            }
        }

        let value = captured
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalizedHeading(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let heading = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "#*- "))
            .components(separatedBy: ":")
            .first ?? trimmed
        return heading.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func headingRemainder(_ line: String) -> String {
        guard let colonIndex = line.firstIndex(of: ":") else { return "" }
        let remainder = line[line.index(after: colonIndex)...]
        return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isAnyHeading(_ line: String) -> Bool {
        let normalized = normalizedHeading(line)
        return [
            "agreement",
            "what the council agrees on",
            "consensus",
            "disagreement",
            "where they differ",
            "dissent",
            "recommended next step",
            "next step",
            "recommendation",
            "synthesis"
        ].contains(normalized)
    }
}

struct CouncilRoomView: View {
    let model: CouncilRoomModel
    let onSend: (String, CouncilTarget) -> Void
    let onSynthesize: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            CouncilRosterStrip(participants: model.participants)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(model.messages) { message in
                        CouncilMessageRow(message: message)
                    }

                    if let synthesis = model.synthesis {
                        CouncilSynthesisCard(synthesis: synthesis)
                            .padding(.top, 2)
                    }
                }
                .padding(16)
            }
            .background(Color.appSecondaryBackground)

            CouncilComposerBar(
                participants: model.participants,
                onSend: onSend,
                onSynthesize: onSynthesize
            )
        }
        .background(Color.appSecondaryBackground)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.actionPrimary)
                .frame(width: 36, height: 36)
                .background(Color.actionPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(model.title)
                    .font(.headline.weight(.semibold))
                Text(model.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.appPanelBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appHairline)
                .frame(height: 1)
        }
    }
}

struct CouncilMessageRow: View {
    let message: CouncilMessageVM

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ModelAvatarDot(participant: message.participant)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(message.participant.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    CouncilStanceBadge(stance: message.participant.stance)

                    Spacer(minLength: 0)
                }

                Group {
                    if message.text.isEmpty && message.isStreaming {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("reasoning...")
                                .foregroundStyle(Color.textSecondary)
                        }
                    } else {
                        Text(message.text.isEmpty ? "No answer yet." : message.text)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
                .font(.body)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(cardBorderColor, lineWidth: 1)
            }
        }
    }

    // Dissenting answers get a subtle red-tinted card, per the Council mockup.
    private var cardBackground: Color {
        message.participant.stance == .dissents ? Color.proofMismatch.opacity(0.06) : Color.appPanelBackground
    }

    private var cardBorderColor: Color {
        message.participant.stance == .dissents ? Color.proofMismatch.opacity(0.22) : Color.appBorder
    }
}

struct CouncilRosterStrip: View {
    let participants: [CouncilParticipant]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(participants) { participant in
                HStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        ModelAvatarDot(participant: participant)
                        Circle()
                            .fill(stateColor(participant.stance))
                            .frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.appPanelBackground, lineWidth: 2))
                            .offset(x: 1, y: 1)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(participant.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(stateLabel(participant.stance))
                            .font(.system(size: 10))
                            .foregroundStyle(stateColor(participant.stance))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.appPanelBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.appHairline).frame(height: 0.5)
        }
    }

    private func stateColor(_ stance: CouncilStance) -> Color {
        switch stance {
        case .reasoning: return .proofStale
        case .dissents: return .proofMismatch
        case .agrees, .neutral: return .proofVerified
        }
    }

    private func stateLabel(_ stance: CouncilStance) -> String {
        switch stance {
        case .reasoning: return "thinking"
        case .dissents: return "dissents"
        case .agrees, .neutral: return "ready"
        }
    }
}

struct CouncilStanceBadge: View {
    let stance: CouncilStance

    var body: some View {
        if let label {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(tint.opacity(0.10), in: Capsule())
                .accessibilityLabel(label)
        }
    }

    private var label: String? {
        switch stance {
        case .agrees:
            return "Agrees"
        case .dissents:
            return "Dissents"
        case .reasoning:
            return "reasoning..."
        case .neutral:
            return nil
        }
    }

    private var tint: Color {
        switch stance {
        case .agrees:
            return .proofVerified
        case .dissents:
            return .proofMismatch
        case .reasoning, .neutral:
            return .textSecondary
        }
    }
}

struct CouncilSynthesisCard: View {
    let synthesis: CouncilSynthesisVM
    @State private var expandedChip: SynthesisChip?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.actionPrimary)
                Text("Synthesis")
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 0)
            }

            Text(synthesis.fullText)
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .lineSpacing(3)
                .textSelection(.enabled)

            if !chips.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(chips) { chip in
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                expandedChip = expandedChip == chip ? nil : chip
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: chip.symbolName)
                                    .font(.caption.weight(.bold))
                                Text(chip.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: expandedChip == chip ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(chip.tint)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(chip.tint.opacity(expandedChip == chip ? 0.16 : 0.09), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let expandedChip, let detail = detail(for: expandedChip) {
                    Text(detail)
                        .font(.callout)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.appHairline, lineWidth: 1)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var chips: [SynthesisChip] {
        SynthesisChip.allCases.filter { detail(for: $0) != nil }
    }

    private func detail(for chip: SynthesisChip) -> String? {
        switch chip {
        case .agreement:
            return synthesis.agreement
        case .disagreement:
            return synthesis.disagreement
        case .nextStep:
            return synthesis.nextStep
        }
    }
}

struct CouncilComposerBar: View {
    let participants: [CouncilParticipant]
    let onSend: (String, CouncilTarget) -> Void
    let onSynthesize: () -> Void

    @State private var target: CouncilTarget = .room
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                targetMenu

                TextField("Ask the council", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.appHairline, lineWidth: 1)
                    }

                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .font(.body.weight(.bold))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSend ? Color.appPanelBackground : Color.textSecondary)
                .background(canSend ? Color.actionPrimary : Color.appSecondaryBackground, in: Circle())
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }

            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "person.3.fill").font(.caption2.weight(.bold))
                    Text("\(participants.count) models").font(.caption.weight(.semibold))
                }
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.appSecondaryBackground, in: Capsule())

                Button(action: onSynthesize) {
                    Label("Synthesize", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.actionPrimary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.actionPrimary.opacity(0.10), in: Capsule())

                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(Color.appPanelBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.appHairline)
                .frame(height: 1)
        }
    }

    private var targetMenu: some View {
        Menu {
            Button {
                target = .room
            } label: {
                Label("room", systemImage: target == .room ? "checkmark" : "person.3")
            }

            ForEach(participants) { participant in
                Button {
                    target = .model(id: participant.modelID)
                } label: {
                    Label("@\(participant.displayName)", systemImage: target == .model(id: participant.modelID) ? "checkmark" : "at")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("To: \(targetLabel)")
                    .font(.caption.weight(.bold))
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(Color.actionPrimary)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Color.actionPrimary.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var targetLabel: String {
        switch target {
        case .room:
            return "room"
        case let .model(id):
            return "@\(participants.first { $0.modelID == id }?.displayName ?? "model")"
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSend(text, target)
        draft = ""
    }
}

struct ModelAvatarDot: View {
    let participant: CouncilParticipant

    var body: some View {
        ZStack {
            Circle()
                .fill(participant.color.opacity(0.16))
            Circle()
                .fill(participant.color)
                .frame(width: 13, height: 13)
        }
        .frame(width: 30, height: 30)
        .overlay {
            Circle()
                .stroke(Color.appBorder, lineWidth: 1)
        }
        .accessibilityLabel(participant.displayName)
    }
}

private enum SynthesisChip: String, CaseIterable, Identifiable {
    case agreement
    case disagreement
    case nextStep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agreement:
            return "Agreement"
        case .disagreement:
            return "Disagreement"
        case .nextStep:
            return "Recommended next step"
        }
    }

    var symbolName: String {
        switch self {
        case .agreement:
            return "checkmark.circle.fill"
        case .disagreement:
            return "exclamationmark.triangle.fill"
        case .nextStep:
            return "arrow.right.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .agreement:
            return .proofVerified
        case .disagreement:
            return .proofMismatch
        case .nextStep:
            return .brandBlue
        }
    }
}

#Preview("Council Room") {
    let glm = CouncilParticipant(
        id: "zai-org/GLM-5.1-FP8",
        modelID: "zai-org/GLM-5.1-FP8",
        displayName: "GLM",
        color: .brandBlue,
        stance: .agrees
    )
    let claude = CouncilParticipant(
        id: "near-cloud/anthropic/claude-opus-4-7",
        modelID: "near-cloud/anthropic/claude-opus-4-7",
        displayName: "Claude",
        color: .proofVerified,
        stance: .agrees
    )
    let gemini = CouncilParticipant(
        id: "google/gemini-2.5-pro",
        modelID: "google/gemini-2.5-pro",
        displayName: "Gemini",
        color: .proofMismatch,
        stance: .dissents
    )

    return CouncilRoomView(
        model: CouncilRoomModel(
            title: "Council",
            subtitle: "GLM · Claude · Gemini",
            participants: [glm, claude, gemini],
            messages: [
                CouncilMessageVM(
                    id: "glm",
                    participant: glm,
                    text: "I agree with the low-risk path: ship the UI as a separate affordance and keep the existing council stack untouched.",
                    isStreaming: false
                ),
                CouncilMessageVM(
                    id: "claude",
                    participant: claude,
                    text: "I agree with caveats. The room should avoid inventing vote counts until synthesis emits structured evidence.",
                    isStreaming: false
                ),
                CouncilMessageVM(
                    id: "gemini",
                    participant: gemini,
                    text: "I dissent on making it the default. However, an opt-in room is useful for comparing answer quality and tone.",
                    isStreaming: false
                )
            ],
            synthesis: CouncilSynthesisVM(
                agreement: "All models support a separate room that preserves the current council transcript and does not call store APIs directly.",
                disagreement: "Gemini would not make the room the default presentation until usage proves it is clearer than the compact stack.",
                nextStep: "Add an Open Council Room affordance, map the selected batch through `CouncilRoomModel.from`, then wire send and synthesize callbacks.",
                fullText: "The council broadly supports a separate room UI while keeping the existing stacked rendering stable. The main disagreement is default placement versus opt-in access."
            )
        ),
        onSend: { _, _ in },
        onSynthesize: {}
    )
}

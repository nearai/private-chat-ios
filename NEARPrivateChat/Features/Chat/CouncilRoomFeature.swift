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
        let synthesisMessage = assistantMessages
            .filter(isSynthesisMessage)
            .sorted { $0.createdAt < $1.createdAt }
            .last
        var participantByModel = [String: CouncilParticipant]()
        var participants = [CouncilParticipant]()
        var rows = [CouncilMessageVM]()

        for message in assistantMessages where !isSynthesisMessage(message) {
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
                labels: ["disagreement", "disagreements or uncertainty", "where they differ", "dissent", "uncertainty"]
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
            "disagreements or uncertainty",
            "where they differ",
            "dissent",
            "uncertainty",
            "recommended next step",
            "next step",
            "recommendation",
            "synthesis"
        ].contains(normalized)
    }
}

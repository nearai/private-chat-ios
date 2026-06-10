import Foundation

struct CouncilStreamService {
    static let defaultConcurrentStreamLimit = 2

    struct StreamResult {
        let modelID: String
        let messageID: String
        let didComplete: Bool
        let failureSummary: String?
        var isStopSignal: Bool = false

        static func stopSignal(batchID: String) -> StreamResult {
            StreamResult(
                modelID: batchID,
                messageID: batchID,
                didComplete: false,
                failureSummary: nil,
                isStopSignal: true
            )
        }
    }

    struct RunOutcome {
        let results: [StreamResult]
        let stoppedEarly: Bool
    }

    static func batchModelIDs(from messages: [ChatMessage], batchID: String?) -> [String] {
        uniqueCouncilModelIDs(
            from: messages.filter { message in
                (batchID == nil || message.councilBatchID == batchID) &&
                    message.role == .assistant &&
                    !isSynthesisModelID(message.model)
            }
        )
    }

    static func batchPrompt(from messages: [ChatMessage]) -> String? {
        let prompt = messages
            .filter { $0.role == .user }
            .sorted { $0.createdAt < $1.createdAt }
            .first?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt?.isEmpty == false ? prompt : nil
    }

    static func targetedPrompt(
        text: String,
        modelDisplayName: String,
        previousAnswer: String? = nil
    ) -> String {
        let previousAnswerBlock: String
        if let previousAnswer = previousAnswer?.trimmingCharacters(in: .whitespacesAndNewlines),
           !previousAnswer.isEmpty {
            let clippedPreviousAnswer = previousAnswer.count > 4_000
                ? "\(previousAnswer.prefix(4_000))..."
                : previousAnswer
            previousAnswerBlock = """

            Your previous Council answer:
            \(clippedPreviousAnswer)
            """
        } else {
            previousAnswerBlock = ""
        }
        return """
        You are \(modelDisplayName) responding as a single selected member of an LLM Council.
        Answer the user's follow-up directly from your own perspective. Do not claim to speak for the whole council unless the user asks you to compare against prior answers.
        \(previousAnswerBlock)

        User follow-up:
        \(text)
        """
    }

    static func streamResults(from messages: [ChatMessage], batchID: String) -> [StreamResult] {
        messages
            .filter { message in
                message.councilBatchID == batchID &&
                    message.hasUsableCouncilAnswer &&
                    !isSynthesisModelID(message.model)
            }
            .compactMap { message -> StreamResult? in
                guard let modelID = message.model?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !modelID.isEmpty else {
                    return nil
                }
                return StreamResult(
                    modelID: modelID,
                    messageID: message.id,
                    didComplete: true,
                    failureSummary: nil
                )
            }
    }

    static func latestCouncilResponseID(in messages: [ChatMessage]) -> String? {
        latestResponseID(
            in: messages.filter { !isSynthesisModelID($0.model) }
        )
    }

    static func latestResponseID(in messages: [ChatMessage], modelID: String) -> String? {
        latestResponseID(
            in: messages.filter { message in
                message.model?.trimmingCharacters(in: .whitespacesAndNewlines) == modelID
            }
        )
    }

    static func latestAnswerText(in messages: [ChatMessage], modelID: String) -> String? {
        let answer = messages
            .filter { message in
                message.role == .assistant &&
                    message.model?.trimmingCharacters(in: .whitespacesAndNewlines) == modelID &&
                    !isSynthesisModelID(message.model)
            }
            .sorted { $0.createdAt < $1.createdAt }
            .last?
            .text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return answer?.isEmpty == false ? answer : nil
    }

    static func isSynthesisModelID(_ modelID: String?) -> Bool {
        guard let modelID = modelID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !modelID.isEmpty else {
            return false
        }
        return modelID == ModelOption.llmCouncilSynthesisModelID ||
            modelID.localizedCaseInsensitiveContains("council/synthesis") ||
            modelID.localizedCaseInsensitiveContains("synthesis")
    }

    /// Per-member response clip and a TOTAL budget across all members — large
    /// synthesis prompts were timing out / dropping the connection after long
    /// council runs.
    static let maxPerResponseChars = 5_000
    static let maxTotalSynthesisResponseChars = 12_000

    static func synthesisPrompt(
        originalPrompt: String,
        routedPrompt: String,
        responses: [(String, String)]
    ) -> String {
        let perResponseBudget = min(
            maxPerResponseChars,
            maxTotalSynthesisResponseChars / max(responses.count, 1)
        )
        let councilResponses = responses.map { modelName, text in
            """
            ## \(modelName)
            \(clipped(text, maxCharacters: perResponseBudget))
            """
        }.joined(separator: "\n\n")
        let routeNote = originalPrompt == routedPrompt ? "" : "\n\nRouted prompt actually sent:\n\(clipped(routedPrompt, maxCharacters: 2_000))"
        return """
        You are synthesizing an LLM Council run. Compare the model answers, choose the strongest claims, and call out meaningful disagreements. Do not average weak claims; prefer correctness, recency, and evidence.

        If the user asked for exact wording, a one-word answer, code-only output, JSON-only output, or any other constrained format, obey that requested output shape exactly. Do not add sections, commentary, or meta-analysis in those cases.

        Do not ask the user a follow-up question. If there is no useful next step, write "None." for the next step.

        User prompt:
        \(clipped(originalPrompt, maxCharacters: 2_000))\(routeNote)

        Council responses:
        \(councilResponses)

        Return a polished final answer using Markdown headings exactly like this:
        ## Direct answer
        ## What the council agrees on
        ## Disagreements or uncertainty
        ## Recommended next step

        Preserve source citations where they are useful. If the model answers cite sources with bracket markers like [1], keep those markers in the synthesized answer.

        Do not include a "Why synthesis is better" section.
        """
    }

    private static func latestResponseID(in messages: [ChatMessage]) -> String? {
        messages
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap(\.responseID)
            .last
    }

    private static func uniqueCouncilModelIDs(from messages: [ChatMessage]) -> [String] {
        var seen = Set<String>()
        var ids: [String] = []
        for message in messages.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard let modelID = message.model?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !modelID.isEmpty,
                  !seen.contains(modelID) else {
                continue
            }
            seen.insert(modelID)
            ids.append(modelID)
        }
        return ids
    }

    private static func clipped(_ value: String, maxCharacters: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxCharacters else { return trimmed }
        return "\(trimmed.prefix(maxCharacters))..."
    }
}

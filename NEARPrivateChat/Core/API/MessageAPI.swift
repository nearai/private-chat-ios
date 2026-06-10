import Foundation

protocol MessageAPI: AnyObject {
    func streamResponse(
        model: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        webSearchEnabled: Bool,
        systemPrompt: String,
        advancedParams: AdvancedModelParams,
        initiator: String,
        visibleOutputTimeout: TimeInterval?,
        onEvent: @escaping (ResponseStreamEvent) async -> Void
    ) async throws
}

private actor ResponseStreamVisibility {
    private var sawVisibleOutput = false

    func markVisibleOutput() {
        sawVisibleOutput = true
    }

    func hasVisibleOutput() -> Bool {
        sawVisibleOutput
    }
}

final class PrivateChatMessageAPI: MessageAPI {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func streamResponse(
        model: String,
        text: String,
        attachments: [ChatAttachment],
        conversationID: String,
        previousResponseID: String?,
        webSearchEnabled: Bool,
        systemPrompt: String,
        advancedParams: AdvancedModelParams = .defaults,
        initiator: String = "new_message",
        visibleOutputTimeout: TimeInterval? = nil,
        onEvent: @escaping (ResponseStreamEvent) async -> Void
    ) async throws {
        let promptText = text.isEmpty && !attachments.isEmpty
            ? "Review the attached file context. Lead with the most useful summary, then call out decisions, risks, and next actions."
            : text
        let content = Self.responseContent(promptText: promptText, attachments: attachments)
        let payload = ResponsePayload(
            model: model,
            input: [
                ResponseInput(role: "user", content: content)
            ],
            conversation: conversationID,
            stream: true,
            tools: webSearchEnabled ? [ResponseTool(type: "web_search")] : nil,
            include: webSearchEnabled ? ["web_search_call.action.sources"] : nil,
            instructions: Self.responseInstructions(webSearchEnabled: webSearchEnabled, systemPrompt: systemPrompt),
            signingAlgo: "ecdsa",
            previousResponseID: previousResponseID,
            initiator: initiator,
            temperature: advancedParams.sanitized.temperature,
            topP: advancedParams.sanitized.topP,
            maxTokens: advancedParams.sanitized.maxTokens
        )

        let body = try client.encoder.encode(payload)
        var request = try client.makeRequest(path: "/v1/responses", method: "POST", body: body, authenticated: true)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = APIClient.streamTimeout

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try await client.validateStreamingResponse(response, bytes: bytes)

        let visibility = ResponseStreamVisibility()
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard line.hasPrefix("data:") else { continue }
                    let dataLine = line.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !dataLine.isEmpty, dataLine != "[DONE]" else { continue }
                    guard let eventData = dataLine.data(using: .utf8),
                          let event = self.parseStreamEvent(eventData) else { continue }
                    if event.hasVisibleOutput {
                        await visibility.markVisibleOutput()
                    }
                    await onEvent(event)
                    switch event {
                    case let .failed(message):
                        throw APIError.status(403, message)
                    case .completed:
                        return
                    default:
                        break
                    }
                }
                throw APIError.status(502, "The response stream ended early.")
            }

            if let visibleOutputTimeout {
                group.addTask {
                    let nanoseconds = UInt64(max(0.1, visibleOutputTimeout) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: nanoseconds)
                    if await !visibility.hasVisibleOutput() {
                        throw APIError.status(408, "The selected model is still reasoning without visible output.")
                    }

                    while !Task.isCancelled {
                        try await Task.sleep(nanoseconds: 60_000_000_000)
                    }
                }
            }

            do {
                _ = try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    func parseStreamEvent(_ data: Data) -> ResponseStreamEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return nil
        }

        switch type {
        case "error", "response.error":
            return .failed(Self.firstErrorMessage(in: object) ?? "The model request failed.")
        case "response.web_search_call.in_progress", "response.web_search_call.searching":
            return .webSearchStarted(query: nil)
        case "response.web_search_call.completed":
            return .webSearchCompleted(query: nil, sources: [])
        case "response.created":
            let response = object["response"] as? [String: Any]
            return .created(responseID: response?["id"] as? String ?? "")
        case "response.reasoning.delta", "response.reasoning.done":
            return .reasoningStarted
        case "response.output_item.added":
            let item = object["item"] as? [String: Any]
            switch item?["type"] as? String {
            case "reasoning":
                return .reasoningStarted
            case "web_search_call":
                let action = item?["action"] as? [String: Any]
                return .webSearchStarted(query: action?["query"] as? String)
            default:
                return nil
            }
        case "response.output_text.delta":
            let delta = object["delta"] as? String ?? ""
            if let failedMessage = Self.streamFailureMessage(from: delta) {
                return .failed(failedMessage)
            }
            return .textDelta(delta)
        case "response.output_text.done":
            let text = object["text"] as? String
            if let failedMessage = Self.streamFailureMessage(from: text) {
                return .failed(failedMessage)
            }
            return .itemDone(text: text)
        case "response.content_part.done":
            let part = object["part"] as? [String: Any]
            let text = part?["text"] as? String
            if let failedMessage = Self.streamFailureMessage(from: text) {
                return .failed(failedMessage)
            }
            return .itemDone(text: text)
        case "response.output_item.done":
            let item = object["item"] as? [String: Any]
            if item?["type"] as? String == "web_search_call" {
                let action = item?["action"] as? [String: Any]
                return .webSearchCompleted(
                    query: action?["query"] as? String,
                    sources: Self.webSearchSources(from: action)
                )
            }
            let content = item?["content"] as? [[String: Any]]
            let text = content?.compactMap { $0["text"] as? String }.joined()
            if let failedMessage = Self.streamFailureMessage(from: text) {
                return .failed(failedMessage)
            }
            return .itemDone(text: text)
        case "conversation.title.updated":
            return .titleUpdated(object["conversation_title"] as? String ?? "")
        case "response.completed":
            let response = object["response"] as? [String: Any]
            return .completed(responseID: response?["id"] as? String)
        case "response.failed":
            let text = object["text"] as? String
            let response = object["response"] as? [String: Any]
            let error = response?["error"] as? [String: Any]
            return .failed(
                Self.streamFailureMessage(from: text) ??
                    text ??
                    Self.firstErrorMessage(in: response) ??
                    error?["message"] as? String ??
                    "The model is currently unavailable."
            )
        default:
            #if DEBUG
            // Live probe support: if the private route DOES run web search
            // under event names we don't parse, this is where they surface.
            if let type = object["type"] as? String, type.contains("search") || type.contains("tool") {
                print("[MessageAPI] unrecognized SSE event type: \(type)")
            }
            #endif
            return nil
        }
    }

    static var widgetInstructionForTesting: String { widgetInstruction }

    static func responseInstructionsForTesting(webSearchEnabled: Bool, systemPrompt: String = "") -> String {
        responseInstructions(webSearchEnabled: webSearchEnabled, systemPrompt: systemPrompt)
    }

    static func responseContentDescriptorsForTesting(attachments: [ChatAttachment]) -> [(type: String, fileID: String?)] {
        responseContent(promptText: "Test prompt", attachments: attachments).map { ($0.type, $0.fileID) }
    }

    private static func firstErrorMessage(in object: [String: Any]?) -> String? {
        guard let object else { return nil }
        for key in ["error", "message", "detail"] {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
            if let nested = object[key] as? [String: Any] {
                if let message = firstErrorMessage(in: nested) {
                    return message
                }
            }
        }
        return nil
    }

    private static func streamFailureMessage(from text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        for key in ["error", "message", "detail"] {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
            if let nested = object[key] as? [String: Any],
               let message = nested["message"] as? String,
               !message.isEmpty {
                return message
            }
        }
        return nil
    }

    private static func responseContent(promptText: String, attachments: [ChatAttachment]) -> [ResponseContent] {
        [ResponseContent(type: "input_text", text: promptText, fileID: nil)] +
            attachments.map { attachment in
                ResponseContent(
                    type: attachment.isNativeVisionImage ? "input_image" : "input_file",
                    text: nil,
                    fileID: attachment.id
                )
            }
    }

    private static let widgetInstruction = """


    Generative widgets:
    - When the answer is naturally a trend over time, a head-to-head comparison, a multi-item news digest, a preview of proposed actions, or a key tracked metric that benefits from emphasis, ALSO append exactly one fenced code block tagged near-widget containing a compact JSON object. This is the only place raw JSON is allowed.
    - Use kind action_plan when the user asks to turn context/files/tables into actions, trackers, reminders, calendar-worthy items, tasks, decisions, risks, or things they should care about. Stage commands only; do not claim a tracker, reminder, or calendar event was created unless the app confirms it.
    - For action_plan actions, include structured candidate fields when known: source, date, time, duration, recurrence, timezone, location, attendees, missing_fields, and confidence. Put fuzzy values like "upon waking" in schedule/time and list the concrete field that still needs confirmation in missing_fields.
    - Do NOT emit a widget for a simple one-off number, a short factual reply, or a plain explanatory answer - only when a native card materially helps. Put the prose answer first; the near-widget block goes last; never emit more than one.
    - Schema (include only the keys that apply):
      {"kind":"chart|metric|comparison|news_brief|action_plan","title":"short source label","time":"e.g. 1h ago","freshness":"fresh|stale","follow_up":"a natural follow-up question","chart":{"label":"Project progress","value":"42% complete","delta":"+3 items","trend":"up|down|flat","points":[20,28,35,42],"caption":"context line","timeframe":"past week"},"metric":{"label":"Open risks","value":"4","delta":"+1","trend":"up|down|flat","caption":"..."},"comparison":{"subtitle":"A vs B","columns":["A","B"],"rows":[{"label":"Row","cells":[{"text":"yes","tone":"good"},{"text":"no","tone":"off"}]}]},"news_brief":{"heading":"Today · 3 stories","stories":[{"title":"...","tag":"Research","sources":[{"label":"Source","domain":"example.com"}]}]},"action_plan":{"heading":"Top actions","summary":"why these matter","actions":[{"title":"...","type":"tracker|briefing|reminder|calendar|task|decision|risk|question|interest","detail":"why or missing details","schedule":"optional cadence/time","source":"file.xlsx · Supplements row 12","date":"YYYY-MM-DD if known","time":"8:00 AM or upon waking","duration":"30m","recurrence":"daily","timezone":"America/Toronto","location":"optional","attendees":["optional email/name"],"missing_fields":["exact bedtime"],"confidence":0.84,"command":"Create a tracker for ... every ...","tone":"good|warn|bad|neutral"}]}}
    """

    private static func responseInstructions(webSearchEnabled: Bool, systemPrompt: String) -> String {
        let date = Date.now.formatted(date: .complete, time: .omitted)
        let trimmedSystemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let userInstruction = trimmedSystemPrompt.isEmpty ? "" : "\n\nUser system preference:\n\(trimmedSystemPrompt)"
        if webSearchEnabled {
            return """
            You are NEAR Private Chat. The current date is \(date). For current, recent, time-sensitive, or specific public factual questions, call web_search before answering.

            Answer contract:
            - Lead with the direct answer in 1-3 tight sentences.
            - Use the app-supported Markdown subset: headings, ordered and unordered lists, nested lists, GitHub-flavored tables, fenced code blocks with language tags, links, bold, italic, and blockquotes.
            - Keep tables compact enough to read on a phone; prefer a list when a table would be too wide.
            - Prefer concrete dates, names, numbers, and named sources.
            - Separate facts, inference, and recommended next actions when the topic is ambiguous.
            - Avoid generic caveats, fake tool calls, XML, HTML, Mermaid, LaTeX/math-only markup, raw JSON outside the sanctioned near-widget block, and emoji headings.
            - Treat attached files as user-provided project context and cite filenames when helpful.\(Self.widgetInstruction)\(userInstruction)
            """
        }

        return """
        You are NEAR Private Chat. The current date is \(date).

        Answer contract:
        - Lead with the direct answer in 1-3 tight sentences.
        - Use the app-supported Markdown subset: headings, ordered and unordered lists, nested lists, GitHub-flavored tables, fenced code blocks with language tags, links, bold, italic, and blockquotes.
        - Keep tables compact enough to read on a phone; prefer a list when a table would be too wide.
        - Prefer concrete dates, names, and numbers.
        - Separate facts, inference, and recommended next actions when the topic is ambiguous.
        - Avoid generic caveats, fake tool calls, XML, HTML, Mermaid, LaTeX/math-only markup, raw JSON outside the sanctioned near-widget block, and emoji headings.
        - Treat attached files as user-provided project context and cite filenames when helpful.
        - Be explicit when an answer may require current information.\(Self.widgetInstruction)\(userInstruction)
        """
    }

    private static func webSearchSources(from rawSources: [[String: Any]]) -> [WebSearchSource] {
        rawSources.compactMap { source in
            guard let rawURL = source["url"] as? String,
                  let url = WebSearchSource.sanitizedURLString(rawURL) else { return nil }
            return WebSearchSource(
                type: firstSourceString(in: source, keys: ["type", "source_type", "kind"]),
                url: url,
                title: firstSourceString(in: source, keys: ["title", "name", "display_title"]),
                publishedAt: firstSourceString(in: source, keys: ["published_at", "publishedAt", "date", "published"]),
                snippet: firstSourceString(in: source, keys: ["snippet", "description", "summary", "text"])
            )
        }
    }

    private static func webSearchSources(from rawObject: Any?) -> [WebSearchSource] {
        guard let rawObject else { return [] }
        if let sources = rawObject as? [[String: Any]] {
            return webSearchSources(from: sources)
        }
        if let dictionary = rawObject as? [String: Any] {
            var collected: [WebSearchSource] = []
            if let rawURL = dictionary["url"] as? String,
               let url = WebSearchSource.sanitizedURLString(rawURL) {
                collected.append(
                    WebSearchSource(
                        type: firstSourceString(in: dictionary, keys: ["type", "source_type", "kind"]),
                        url: url,
                        title: firstSourceString(in: dictionary, keys: ["title", "name", "display_title"]),
                        publishedAt: firstSourceString(in: dictionary, keys: ["published_at", "publishedAt", "date", "published"]),
                        snippet: firstSourceString(in: dictionary, keys: ["snippet", "description", "summary", "text"])
                    )
                )
            }
            for key in ["sources", "results", "items", "documents", "citations"] {
                collected += webSearchSources(from: dictionary[key])
            }
            return collected
        }
        if let array = rawObject as? [Any] {
            return array.flatMap { webSearchSources(from: $0) }
        }
        return []
    }

    private static func firstSourceString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String,
               WebSearchSource.cleanedMetadata(value, maxLength: 600) != nil {
                return value
            }
        }
        return nil
    }
}

private struct ResponsePayload: Encodable {
    let model: String
    let input: [ResponseInput]
    let conversation: String
    let stream: Bool
    let tools: [ResponseTool]?
    let include: [String]?
    let instructions: String?
    let signingAlgo: String
    let previousResponseID: String?
    let initiator: String?
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case conversation
        case stream
        case tools
        case include
        case instructions
        case signingAlgo = "signing_algo"
        case previousResponseID = "previous_response_id"
        case initiator
        case temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
    }
}

private struct ResponseTool: Encodable {
    let type: String
}

private struct ResponseInput: Encodable {
    let role: String
    let content: [ResponseContent]
}

private struct ResponseContent: Encodable {
    let type: String
    let text: String?
    let fileID: String?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case fileID = "file_id"
    }
}

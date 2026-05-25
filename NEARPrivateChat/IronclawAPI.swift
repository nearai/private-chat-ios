import Foundation

final class IronclawAPI {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func testConnection(settings: IronclawSettings, authToken: String?) async throws -> String {
        let baseURL = try validatedBaseURL(settings.baseURL)
        var request = URLRequest(url: baseURL.appending(path: "api/chat/thread/new"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.status(0, "IronClaw endpoint did not return HTTP.")
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Status \(http.statusCode)"
                if [401, 403].contains(http.statusCode) {
                    throw APIError.status(http.statusCode, "Endpoint is reachable, but the chat route needs a valid IronClaw token.")
                }
                throw APIError.status(http.statusCode, body)
            }
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = object["id"] as? String,
               !id.isEmpty {
                return "IronClaw chat route is ready."
            }
            throw APIError.status(0, "IronClaw chat route responded without a thread id.")
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.status(0, error.localizedDescription)
        }
    }

    func fetchToolNames(settings: IronclawSettings, authToken: String?) async throws -> [String] {
        let baseURL = try validatedBaseURL(settings.baseURL)
        var request = URLRequest(url: baseURL.appending(path: "api/extensions/tools"))
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let response: IronclawToolsResponse = try await perform(request)
        return response.tools
            .map(\.name)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func testWorkstationCapability(settings: IronclawSettings, authToken: String?) async throws -> String {
        var probeSettings = settings
        probeSettings.threadID = ""
        let prompt = """
        Workstation preflight from NEAR Private Chat iOS.
        Please run the minimal local workstation command now.
        Use only built-in local workstation tools. Prefer shell.
        When calling shell, pass the JSON parameter named command, singular.
        Do not use set -euo pipefail; the hosted shell may execute commands through /bin/sh.
        Do not call http, GitHub, tool_install, package installers, or any external network.
        Run a minimal local command equivalent to: pwd; git --version; printf '\\nIRONCLAW_WORKSTATION_OK\\n'.
        Then answer with one short sentence containing IRONCLAW_WORKSTATION_OK and whether shell/git worked.
        If shell is unavailable, use echo if available and say which local tool was unavailable.
        """

        var output = ""
        var failure: String?
        var pendingGate: IronclawPendingGate?

        try await streamPrompt(
            prompt: prompt,
            attachments: [],
            settings: probeSettings,
            authToken: authToken
        ) { event in
            switch event {
            case let .textDelta(delta):
                output += delta
            case let .itemDone(text):
                output += text ?? ""
            case let .approvalNeeded(gate):
                pendingGate = gate
            case let .failed(message):
                failure = message
            default:
                break
            }
        }

        if let pendingGate {
            return "Workstation reached, waiting for \(pendingGate.toolName) approval."
        }

        let normalized = output
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.localizedCaseInsensitiveContains("IRONCLAW_WORKSTATION_OK") {
            return "Workstation tools verified: shell/git sandbox responded."
        }
        if let failure, !failure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw APIError.status(0, failure)
        }
        if !normalized.isEmpty {
            return "Workstation answered, but shell/git were not verified: \(Self.shortDiagnostic(normalized))"
        }
        throw APIError.status(0, "Workstation preflight returned no visible output.")
    }

    func sendPrompt(
        prompt: String,
        attachments: [ChatAttachment],
        settings: IronclawSettings,
        authToken: String?
    ) async throws -> IronclawSendResult {
        let baseURL = try validatedBaseURL(settings.baseURL)
        let threadID = try await resolveThreadID(baseURL: baseURL, settings: settings, authToken: authToken)
        var content = prompt
        if !attachments.isEmpty {
            let names = attachments.map(\.name).joined(separator: ", ")
            content += "\n\nNEAR Private Chat file context attached by name only: \(names)."
        }

        let payload = IronclawSendPayload(
            content: content,
            threadID: threadID,
            timezone: TimeZone.current.identifier
        )

        var request = URLRequest(url: baseURL.appending(path: "api/chat/send"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(payload)

        let response: IronclawSendResponse = try await perform(request)
        return IronclawSendResult(messageID: response.messageID, status: response.status, threadID: threadID)
    }

    func streamPrompt(
        prompt: String,
        attachments: [ChatAttachment],
        settings: IronclawSettings,
        authToken: String?,
        onResolvedThreadID: ((String) async -> Void)? = nil,
        onEvent: @escaping (ResponseStreamEvent) async -> Void
    ) async throws {
        let requiresToolUse = Self.promptRequiresWorkstationTools(prompt)
        let result = try await sendPrompt(
            prompt: prompt,
            attachments: attachments,
            settings: settings,
            authToken: authToken
        )
        if let threadID = result.threadID, let onResolvedThreadID {
            await onResolvedThreadID(threadID)
        }
        if let threadID = result.threadID {
            var shouldComplete = true
            for attempt in 0...1 {
                await onEvent(.reasoningStarted)
                let outcome = await pollHistoryUntilFinished(
                    settings: settings,
                    authToken: authToken,
                    threadID: threadID,
                    requiresToolUse: requiresToolUse,
                    onEvent: onEvent
                )

                switch outcome {
                case .completed:
                    shouldComplete = true
                    break
                case .approvalNeeded, .failed:
                    shouldComplete = false
                    break
                case let .needsContinuation(diagnostic):
                    guard attempt == 0 else {
                        await onEvent(.failed(Self.emptyFinalAnswerFailure(diagnostic)))
                        shouldComplete = false
                        break
                    }
                    var retrySettings = settings
                    retrySettings.threadID = threadID
                    _ = try await sendPrompt(
                        prompt: Self.continuationPrompt(originalPrompt: prompt, diagnostic: diagnostic),
                        attachments: [],
                        settings: retrySettings,
                        authToken: authToken
                    )
                    continue
                }

                break
            }
            guard shouldComplete else { return }
        }
        await onEvent(.completed(responseID: nil))
    }

    func resolveGate(
        settings: IronclawSettings,
        authToken: String?,
        approval: IronclawPendingGate,
        action: IronclawApprovalAction
    ) async throws {
        let baseURL = try validatedBaseURL(settings.baseURL)
        let resolution: String
        if action == .deny && approval.isAuthenticationGate {
            resolution = "cancelled"
        } else if action == .deny {
            resolution = "denied"
        } else {
            resolution = "approved"
        }
        let payload = IronclawGateResolvePayload(
            requestID: approval.requestID,
            threadID: approval.threadID,
            resolution: resolution,
            always: action == .always && approval.locallyAllowsAlways ? true : nil,
            token: nil
        )

        var request = URLRequest(url: baseURL.appending(path: "api/chat/gate/resolve"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(payload)

        let _: IronclawActionResponse = try await perform(request)
    }

    func submitGateCredential(
        settings: IronclawSettings,
        authToken: String?,
        approval: IronclawPendingGate,
        token: String
    ) async throws {
        let baseURL = try validatedBaseURL(settings.baseURL)
        let payload = IronclawGateResolvePayload(
            requestID: approval.requestID,
            threadID: approval.threadID,
            resolution: "credential_provided",
            always: nil,
            token: token
        )

        var request = URLRequest(url: baseURL.appending(path: "api/chat/gate/resolve"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(payload)

        let _: IronclawActionResponse = try await perform(request)
    }

    func waitForThread(
        settings: IronclawSettings,
        authToken: String?,
        threadID: String,
        onEvent: @escaping (ResponseStreamEvent) async -> Void
    ) async {
        _ = await pollHistoryUntilFinished(
            settings: settings,
            authToken: authToken,
            threadID: threadID,
            requiresToolUse: false,
            onEvent: onEvent
        )
        await onEvent(.completed(responseID: nil))
    }

    private func validatedBaseURL(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.invalidURL
        }
        let normalized = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              let host = url.host()?.lowercased(),
              !host.isEmpty else {
            throw APIError.invalidURL
        }
        let insecureOrLocal = scheme != "https" || !URLSecurity.isPublicHost(host)
        #if DEBUG
        let allowInsecureDevEndpoint = ProcessInfo.processInfo.environment["IRONCLAW_ALLOW_INSECURE_ENDPOINT"] == "1"
        if insecureOrLocal && !allowInsecureDevEndpoint {
            throw APIError.status(0, "IronClaw requires a hosted HTTPS endpoint. Set IRONCLAW_ALLOW_INSECURE_ENDPOINT=1 only for local debug builds.")
        }
        #else
        if insecureOrLocal {
            throw APIError.status(0, "IronClaw requires a hosted HTTPS endpoint.")
        }
        #endif
        return url
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.emptyResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? ""
            throw APIError.status(http.statusCode, message)
        }
        guard !data.isEmpty else {
            throw APIError.emptyResponse
        }
        return try decoder.decode(T.self, from: data)
    }

    private static func shortDiagnostic(_ text: String) -> String {
        let limit = 180
        guard text.count > limit else { return text }
        return String(text.prefix(limit)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }

    private func resolveThreadID(
        baseURL: URL,
        settings: IronclawSettings,
        authToken: String?
    ) async throws -> String? {
        let configuredThreadID = settings.threadID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configuredThreadID.isEmpty {
            return configuredThreadID
        }

        var request = URLRequest(url: baseURL.appending(path: "api/chat/thread/new"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let thread: IronclawThreadInfo = try await perform(request)
        return thread.id
    }

    func fetchLatestResponse(
        settings: IronclawSettings,
        authToken: String?,
        threadID: String
    ) async throws -> String? {
        try await fetchLatestTurn(settings: settings, authToken: authToken, threadID: threadID)?.response
    }

    private func fetchLatestTurn(
        settings: IronclawSettings,
        authToken: String?,
        threadID: String
    ) async throws -> IronclawTurn? {
        try await fetchHistory(settings: settings, authToken: authToken, threadID: threadID).turns.last
    }

    private func fetchHistory(
        settings: IronclawSettings,
        authToken: String?,
        threadID: String
    ) async throws -> IronclawHistoryResponse {
        let baseURL = try validatedBaseURL(settings.baseURL)
        guard var components = URLComponents(url: baseURL.appending(path: "api/chat/history"), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "thread_id", value: threadID),
            URLQueryItem(name: "limit", value: "5")
        ]
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let authToken, !authToken.isEmpty {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        return try await perform(request)
    }

    private func pollHistoryUntilFinished(
        settings: IronclawSettings,
        authToken: String?,
        threadID: String,
        requiresToolUse: Bool,
        onEvent: @escaping (ResponseStreamEvent) async -> Void
    ) async -> IronclawPollOutcome {
        let maxAttempts = 180
        let failedStateGraceAttempts = 35
        let emptyCompletedGraceAttempts = 3
        var failedStateAttempts = 0
        var emptyCompletedAttempts = 0

        for attempt in 0..<maxAttempts {
            try? await Task.sleep(nanoseconds: attempt == 0 ? 800_000_000 : 2_000_000_000)
            if Task.isCancelled { return .failed }

            guard let history = try? await fetchHistory(settings: settings, authToken: authToken, threadID: threadID) else {
                continue
            }

            if let pendingGate = history.pendingGate {
                await onEvent(.approvalNeeded(pendingGate))
                return .approvalNeeded
            }

            guard let turn = history.turns.last else {
                continue
            }

            let state = turn.state.lowercased()
            if state == "completed" {
                let response = Self.presentationText(from: turn.response ?? "")
                if Self.isEmptyFallbackText(response) {
                    if requiresToolUse || !turn.toolCalls.isEmpty {
                        return .needsContinuation(Self.toolCallDiagnostic(from: turn))
                    }
                    await onEvent(.failed("IronClaw produced an empty final answer. Retry the turn or check the hosted gateway logs."))
                    return .failed
                }
                if let toolFailure = Self.toolFailureMessage(from: response) {
                    await onEvent(.failed(toolFailure))
                    return .failed
                }
                if response.isEmpty || Self.isTransportOnlyText(response) {
                    emptyCompletedAttempts += 1
                    if emptyCompletedAttempts < emptyCompletedGraceAttempts {
                        await onEvent(.reasoningStarted)
                        continue
                    }
                    await onEvent(.failed("IronClaw completed the turn, but the endpoint did not return final answer text. Check the bridge logs, then retry."))
                    return .failed
                } else {
                    await onEvent(.itemDone(text: response))
                }
                return .completed
            }
            emptyCompletedAttempts = 0

            if state == "failed" {
                let response = Self.presentationText(from: turn.response ?? "")
                if !response.isEmpty {
                    if Self.isEmptyFallbackText(response), requiresToolUse || !turn.toolCalls.isEmpty {
                        return .needsContinuation(Self.toolCallDiagnostic(from: turn))
                    }
                    let message = Self.toolFailureMessage(from: response) ??
                        "IronClaw failed while running this turn: \(response)"
                    await onEvent(.failed(message))
                    return .failed
                }
                failedStateAttempts += 1
                if requiresToolUse, !turn.toolCalls.isEmpty {
                    if turn.completedAt != nil || failedStateAttempts >= failedStateGraceAttempts {
                        return .needsContinuation(Self.toolCallDiagnostic(from: turn))
                    }
                    await onEvent(.reasoningStarted)
                    continue
                }
                if turn.completedAt == nil || failedStateAttempts < failedStateGraceAttempts {
                    await onEvent(.reasoningStarted)
                    continue
                }
                await onEvent(.failed("IronClaw failed while running this turn. Check the hosted IronClaw endpoint logs and model credentials, then retry."))
                return .failed
            }
            failedStateAttempts = 0

            await onEvent(.reasoningStarted)
        }

        await onEvent(.failed("IronClaw is still running and did not return output within six minutes. Check the hosted endpoint, then retry the turn."))
        return .failed
    }

    private static func presentationText(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.keys.contains("stdout"),
              object.keys.contains("stderr"),
              object.keys.contains("exit_code") else {
            return trimmed
        }

        let stdout = (object["stdout"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = (object["stderr"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let exitCode = object["exit_code"] as? Int

        if stderr.isEmpty {
            if stdout.contains("\n") {
                return "```text\n\(stdout)\n```"
            }
            if !stdout.isEmpty { return stdout }
            return "Command completed with exit code \(exitCode ?? 0)."
        }

        let statusLine = exitCode.map { "Command exited with code \($0)." } ?? "Command returned stderr."
        if stdout.isEmpty {
            return "\(statusLine)\n\n```text\n\(stderr)\n```"
        }
        return "\(statusLine)\n\nstdout\n```text\n\(stdout)\n```\n\nstderr\n```text\n\(stderr)\n```"
    }

    private static func promptRequiresWorkstationTools(_ prompt: String) -> Bool {
        let normalized = prompt.lowercased()
        return normalized.contains("ironclaw ios coding-agent task") ||
            normalized.contains("workstation preflight") ||
            normalized.contains("local workstation") ||
            normalized.contains("call shell") ||
            normalized.contains("use shell") ||
            normalized.contains("nearai_web_search") ||
            normalized.contains("web search") ||
            normalized.contains("search the web")
    }

    private static func isEmptyFallbackText(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
        return normalized == "i'm not sure how to respond to that." ||
            normalized == "i am not sure how to respond to that."
    }

    private static func continuationPrompt(originalPrompt: String, diagnostic: String) -> String {
        """
        Continue the same IronClaw iOS tool-assisted task.
        Your previous final answer was empty after tool execution, so it cannot be shown to the phone user.
        Please run the remaining hosted tool task now and then produce a visible final answer.

        Tool trace so far:
        \(diagnostic)

        Rules:
        - Use the requested hosted tools before answering.
        - If native tool calls do not work, emit one standalone XML tool call outside markdown, for example:
        <tool_call>{"name":"shell","arguments":{"command":"pwd && git --version"}}</tool_call>
        - Put raw command output in a fenced text block.
        - Finish with a concise summary of what changed and what passed.

        Original request:
        \(originalPrompt)
        """
    }

    private static func emptyFinalAnswerFailure(_ diagnostic: String) -> String {
        """
        IronClaw ran workstation tools, but the hosted runtime did not produce a visible final answer after retrying.

        Tool trace:
        \(diagnostic)

        Retry with a smaller task or check the hosted IronClaw logs for the empty-response fallback.
        """
    }

    private static func toolCallDiagnostic(from turn: IronclawTurn) -> String {
        guard !turn.toolCalls.isEmpty else {
            return "No tool calls were recorded for this turn."
        }
        return turn.toolCalls.prefix(6).enumerated().map { index, call in
            let status: String
            if call.hasError {
                status = "error"
            } else if call.hasResult {
                status = "ok"
            } else {
                status = "pending"
            }
            let preview = (call.resultPreview ?? call.result ?? call.error ?? "")
                .replacingOccurrences(of: "\n", with: "\\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if preview.isEmpty {
                return "\(index + 1). \(call.name): \(status)"
            }
            return "\(index + 1). \(call.name): \(status) - \(shortDiagnostic(preview))"
        }.joined(separator: "\n")
    }

    private static func isTransportOnlyText(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        return normalized == "accepted" ||
            normalized == "running" ||
            normalized == "queued" ||
            normalized.contains("accepted") && normalized.contains("gateway") ||
            normalized.contains("running") && normalized.contains("configured gateway")
    }

    private static func toolFailureMessage(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let rawMessage: String
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            rawMessage = (object["error"] as? String) ??
                (object["message"] as? String) ??
                (object["detail"] as? String) ??
                trimmed
        } else {
            rawMessage = trimmed
        }

        let lowercased = rawMessage.lowercased()
        guard lowercased.contains("tool '") || lowercased.contains("tool \"") || lowercased.contains("tool error") else {
            return nil
        }
        return rawMessage
    }

    private static func isFatalGatewayError(_ text: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("unauthorized") ||
            normalized.contains("not authenticated") ||
            normalized.contains("invalid token") ||
            normalized.contains("valid ironclaw token") ||
            normalized.contains("not available in your plan") ||
            toolFailureMessage(from: text) != nil
    }
}

private enum IronclawPollOutcome {
    case completed
    case approvalNeeded
    case needsContinuation(String)
    case failed
}

struct IronclawSendResult: Hashable {
    let messageID: String
    let status: String
    let threadID: String?
}

private struct IronclawThreadInfo: Decodable {
    let id: String
}

private struct IronclawToolsResponse: Decodable {
    let tools: [IronclawToolInfo]
}

private struct IronclawToolInfo: Decodable {
    let name: String
}

private struct IronclawHistoryResponse: Decodable {
    let turns: [IronclawTurn]
    let pendingGate: IronclawPendingGate?

    enum CodingKeys: String, CodingKey {
        case turns
        case pendingGate = "pending_gate"
    }
}

private struct IronclawTurn: Decodable {
    let response: String?
    let state: String
    let userInput: String?
    let completedAt: String?
    let toolCalls: [IronclawToolCall]

    enum CodingKeys: String, CodingKey {
        case response
        case state
        case userInput = "user_input"
        case completedAt = "completed_at"
        case toolCalls = "tool_calls"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        response = try container.decodeIfPresent(String.self, forKey: .response)
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        userInput = try container.decodeIfPresent(String.self, forKey: .userInput)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        toolCalls = try container.decodeIfPresent([IronclawToolCall].self, forKey: .toolCalls) ?? []
    }
}

private struct IronclawToolCall: Decodable {
    let name: String
    let hasResult: Bool
    let hasError: Bool
    let callID: String?
    let result: String?
    let resultPreview: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case name
        case hasResult = "has_result"
        case hasError = "has_error"
        case callID = "call_id"
        case result
        case resultPreview = "result_preview"
        case error
    }
}

private struct IronclawSendPayload: Encodable {
    let content: String
    let threadID: String?
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case content
        case threadID = "thread_id"
        case timezone
    }
}

private struct IronclawSendResponse: Decodable {
    let messageID: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case status
    }
}

private struct IronclawGateResolvePayload: Encodable {
    let requestID: String
    let threadID: String
    let resolution: String
    let always: Bool?
    let token: String?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case threadID = "thread_id"
        case resolution
        case always
        case token
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(threadID, forKey: .threadID)
        try container.encode(resolution, forKey: .resolution)
        try container.encodeIfPresent(always, forKey: .always)
        try container.encodeIfPresent(token, forKey: .token)
    }
}

private struct IronclawActionResponse: Decodable {
    let success: Bool?
    let message: String?
}

import Foundation
import SwiftUI

// MARK: - Reborn DTOs

struct IronclawCreateThreadPayload: Encodable {
    let clientActionID: String
    enum CodingKeys: String, CodingKey { case clientActionID = "client_action_id" }
}

struct IronclawCreateThreadResponse: Decodable {
    struct Thread: Decodable {
        let threadID: String
        enum CodingKeys: String, CodingKey { case threadID = "thread_id" }
    }
    let thread: Thread
}

struct IronclawSendPayload: Encodable {
    let clientActionID: String
    let content: String
    enum CodingKeys: String, CodingKey {
        case clientActionID = "client_action_id"
        case content
    }
}

/// `send_message` is an internally-tagged enum keyed on `outcome`; every variant
/// carries a run id (`run_id`, or `active_run_id` for `deferred_busy`).
struct IronclawSubmitResponse: Decodable {
    let outcome: String?
    let status: String?
    let runID: String?
    let activeRunID: String?

    enum CodingKeys: String, CodingKey {
        case outcome
        case status
        case runID = "run_id"
        case activeRunID = "active_run_id"
    }

    var resolvedRunID: String? {
        runID ?? activeRunID
    }
}

/// One frame of the run's SSE projection stream (`GET …/threads/{id}/events`).
/// The reborn server emits an event-sourced projection: a `projection_snapshot`
/// then incremental `projection_update` frames, interleaved with `keep_alive`.
/// Live run progress rides on `state.items[].run_status`; gate details, when a
/// run blocks, ride alongside on the same item. We decode only the fields this
/// client acts on and ignore the rest of the projection.
struct IronclawProjectionFrame: Decodable {
    let type: String
    let state: ProjectionState?

    struct ProjectionState: Decodable {
        let items: [ProjectionItem]?
    }

    struct ProjectionItem: Decodable {
        let runStatus: RunStatusItem?
        let gate: IronclawRunState.GateDetail?

        enum CodingKeys: String, CodingKey {
            case runStatus = "run_status"
            case gate
            case pendingGate = "pending_gate"
            case pendingApproval = "pending_approval"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            runStatus = try container.decodeIfPresent(RunStatusItem.self, forKey: .runStatus)
            gate = (try? container.decode(IronclawRunState.GateDetail.self, forKey: .gate))
                ?? (try? container.decode(IronclawRunState.GateDetail.self, forKey: .pendingGate))
                ?? (try? container.decode(IronclawRunState.GateDetail.self, forKey: .pendingApproval))
        }
    }

    struct RunStatusItem: Decodable {
        let runID: String?
        let status: String?
        let gateRef: String?
        let failure: IronclawRunState.Failure?

        enum CodingKeys: String, CodingKey {
            case runID = "run_id"
            case status
            case gateRef = "gate_ref"
            case failure
        }
    }
}

struct IronclawRunState: Decodable {
    struct Failure: Decodable {
        let category: String?
    }

    struct GateDetail: Decodable {
        let requestID: String?
        let gateName: String?
        let toolName: String?
        let description: String?
        let headline: String?
        let body: String?
        let reason: String?
        let parameters: String?
        let allowsAlways: Bool?
        let gateKind: IronclawGateKind?
        let credentialName: String?
        let authURL: String?
        let setupURL: String?
        let instructions: String?
        let displayName: String?
        let extensionName: String?

        enum CodingKeys: String, CodingKey {
            case requestID = "request_id"
            case ref
            case gateRef = "gate_ref"
            case gateName = "gate_name"
            case name
            case toolName = "tool_name"
            case tool
            case description
            case message
            case headline
            case title
            case body
            case reason
            case parameters
            case allowsAlways = "allows_always"
            case allowAlways = "allow_always"
            case gateKind = "gate_kind"
            case kind
            case credentialName = "credential_name"
            case authURL = "auth_url"
            case setupURL = "setup_url"
            case instructions
            case displayName = "display_name"
            case extensionName = "extension_name"
            case `extension`
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            requestID = Self.firstDecodedString(in: container, keys: [.requestID, .gateRef, .ref])
            gateName = Self.firstDecodedString(in: container, keys: [.gateName, .name, .kind])
            toolName = Self.firstDecodedString(in: container, keys: [.toolName, .tool, .displayName, .extensionName, .`extension`])
            description = Self.firstDecodedString(in: container, keys: [.description, .message])
            headline = Self.firstDecodedString(in: container, keys: [.headline, .title])
            body = Self.firstDecodedString(in: container, keys: [.body])
            reason = Self.firstDecodedString(in: container, keys: [.reason])
            parameters = Self.decodedParameters(in: container)
            allowsAlways = Self.firstDecodedBool(in: container, keys: [.allowsAlways, .allowAlways])
            gateKind = Self.firstDecodedGateKind(in: container, keys: [.gateKind, .kind])
            credentialName = Self.firstDecodedString(in: container, keys: [.credentialName])
            authURL = Self.firstDecodedString(in: container, keys: [.authURL])
            setupURL = Self.firstDecodedString(in: container, keys: [.setupURL])
            instructions = Self.firstDecodedString(in: container, keys: [.instructions])
            displayName = Self.firstDecodedString(in: container, keys: [.displayName])
            extensionName = Self.firstDecodedString(in: container, keys: [.extensionName, .`extension`])
        }

        private static func firstDecodedString(
            in container: KeyedDecodingContainer<CodingKeys>,
            keys: [CodingKeys]
        ) -> String? {
            for key in keys {
                if let value = try? container.decode(String.self, forKey: key),
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
            return nil
        }

        private static func firstDecodedBool(
            in container: KeyedDecodingContainer<CodingKeys>,
            keys: [CodingKeys]
        ) -> Bool? {
            for key in keys {
                if let value = try? container.decode(Bool.self, forKey: key) {
                    return value
                }
            }
            return nil
        }

        private static func firstDecodedGateKind(
            in container: KeyedDecodingContainer<CodingKeys>,
            keys: [CodingKeys]
        ) -> IronclawGateKind? {
            for key in keys {
                if let value = try? container.decode(IronclawGateKind.self, forKey: key) {
                    return value
                }
                if let rawValue = try? container.decode(String.self, forKey: key) {
                    let normalized = rawValue.lowercased()
                    if normalized.contains("oauth") { return .oauth }
                    if normalized.contains("auth") { return .authentication }
                    if normalized.contains("external") { return .external }
                    if normalized.contains("approval") { return .approval }
                }
            }
            return nil
        }

        private static func decodedParameters(in container: KeyedDecodingContainer<CodingKeys>) -> String? {
            if let value = try? container.decode(String.self, forKey: .parameters) {
                return value
            }
            if let object = try? container.decode([String: LossyJSONValue].self, forKey: .parameters) {
                let plain = object.mapValues(\.value)
                if JSONSerialization.isValidJSONObject(plain),
                   let data = try? JSONSerialization.data(withJSONObject: plain, options: [.prettyPrinted]) {
                    return String(data: data, encoding: .utf8)
                }
            }
            return nil
        }
    }

    let status: String
    let gateRef: String?
    let failure: Failure?
    let gate: GateDetail?

    enum CodingKeys: String, CodingKey {
        case status
        case gateRef = "gate_ref"
        case failure
        case gate
        case pendingGate = "pending_gate"
        case pendingApproval = "pending_approval"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        gateRef = try container.decodeIfPresent(String.self, forKey: .gateRef)
        failure = try container.decodeIfPresent(Failure.self, forKey: .failure)
        gate = (try? container.decode(GateDetail.self, forKey: .gate)) ??
            (try? container.decode(GateDetail.self, forKey: .pendingGate)) ??
            (try? container.decode(GateDetail.self, forKey: .pendingApproval))
    }
}

struct LossyJSONValue: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([LossyJSONValue].self) {
            value = array.map(\.value)
        } else if let object = try? container.decode([String: LossyJSONValue].self) {
            value = object.mapValues(\.value)
        } else {
            value = ""
        }
    }
}

struct IronclawTimelineResponse: Decodable {
    let messages: [IronclawTimelineMessage]
}

struct IronclawTimelineMessage: Decodable {
    let kind: String
    let content: String?
    let turnRunID: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case content
        case turnRunID = "turn_run_id"
    }
}

struct IronclawGateResolvePayload: Encodable {
    let clientActionID: String
    let resolution: String
    let always: Bool?
    let credentialRef: String?

    enum CodingKeys: String, CodingKey {
        case clientActionID = "client_action_id"
        case resolution
        case always
        case credentialRef = "credential_ref"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientActionID, forKey: .clientActionID)
        try container.encode(resolution, forKey: .resolution)
        try container.encodeIfPresent(always, forKey: .always)
        try container.encodeIfPresent(credentialRef, forKey: .credentialRef)
    }
}

struct IronclawResolveGateResponse: Decodable {
    let outcome: String?
    let status: String?
}

// MARK: - Project File DTOs (webchat v2 /threads/{id}/files)

struct IronclawProjectFile: Codable, Identifiable, Hashable {
    let path: String
    let size: Int?

    var id: String { path }

    var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    enum CodingKeys: String, CodingKey {
        case path
        case size
    }
}

struct IronclawProjectFilesResponse: Codable {
    let files: [IronclawProjectFile]
}

// MARK: - Extensions DTOs (webchat v2 /extensions)

struct IronclawExtension: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String?
    let description: String?
    let isActive: Bool?
    let version: String?
    let category: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, version, category
        case displayName = "display_name"
        case isActive = "is_active"
    }

    var title: String { displayName ?? name }
    var isInstalled: Bool { isActive ?? false }
}

struct IronclawExtensionsResponse: Codable {
    let extensions: [IronclawExtension]?
    let items: [IronclawExtension]?
    var all: [IronclawExtension] { extensions ?? items ?? [] }
}

// MARK: - Automations DTOs (webchat v2 /automations)

struct IronclawAutomation: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let description: String?
    let trigger: String?
    let schedule: String?
    let status: String?
    let lastRunAt: Date?
    let nextRunAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, description, trigger, schedule, status
        case lastRunAt = "last_run_at"
        case nextRunAt = "next_run_at"
    }

    var title: String { name ?? "Automation \(id.prefix(8))" }
    var isRunning: Bool { status == "running" }
    var statusColor: Color {
        switch status {
        case "active": return .green
        case "failed": return .red
        default: return .orange
        }
    }
}

struct IronclawAutomationsResponse: Codable {
    let automations: [IronclawAutomation]?
    let items: [IronclawAutomation]?
    var all: [IronclawAutomation] { automations ?? items ?? [] }
}

// MARK: - LLM Provider DTOs

struct IronclawLLMProvider: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let baseURL: String?
    let modelName: String?
    let isActive: Bool?
    let providerType: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case baseURL = "base_url"
        case modelName = "model_name"
        case isActive = "is_active"
        case providerType = "provider_type"
    }

    var displayName: String { name.isEmpty ? (providerType ?? "Provider") : name }
    var icon: String {
        let t = (providerType ?? name).lowercased()
        if t.contains("openai") { return "sparkles" }
        if t.contains("anthropic") { return "a.circle.fill" }
        if t.contains("nearai") || t.contains("near") { return "n.circle.fill" }
        return "cpu.fill"
    }
}

struct IronclawLLMProvidersResponse: Codable {
    let providers: [IronclawLLMProvider]?
    let items: [IronclawLLMProvider]?
    var all: [IronclawLLMProvider] { providers ?? items ?? [] }
}

// MARK: - Skills DTOs (webchat v2 /skills)

struct IronclawSkill: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String?
    let version: String?
    let isInstalled: Bool?
    let author: String?
    let category: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, version, author, category
        case isInstalled = "is_installed"
    }

    var title: String { name }
    var icon: String {
        let c = (category ?? "").lowercased()
        if c.contains("review") || c.contains("code") { return "chevron.left.forwardslash.chevron.right" }
        if c.contains("research") || c.contains("web") { return "magnifyingglass.circle.fill" }
        if c.contains("plan") || c.contains("design") { return "square.and.pencil" }
        if c.contains("security") { return "lock.shield.fill" }
        return "wand.and.stars"
    }
}

struct IronclawSkillsResponse: Codable {
    let skills: [IronclawSkill]?
    let items: [IronclawSkill]?
    var all: [IronclawSkill] { skills ?? items ?? [] }
}

// MARK: - Connectable Channels DTOs (webchat v2 /channels/connectable)

struct IronclawConnectableChannel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String?
    let isConnected: Bool?
    let description: String?
    let channelType: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case displayName = "display_name"
        case isConnected = "is_connected"
        case channelType = "channel_type"
    }

    var title: String { displayName ?? name }
    var icon: String {
        let t = (channelType ?? name).lowercased()
        if t.contains("slack") { return "number.square.fill" }
        if t.contains("discord") { return "gamecontroller.fill" }
        if t.contains("telegram") { return "paperplane.fill" }
        if t.contains("email") || t.contains("mail") { return "envelope.fill" }
        if t.contains("webhook") { return "bolt.fill" }
        return "antenna.radiowaves.left.and.right"
    }
    var accentColor: Color {
        let t = (channelType ?? name).lowercased()
        if t.contains("slack") { return Color(red: 0.25, green: 0.56, blue: 0.21) }
        if t.contains("discord") { return Color(red: 0.34, green: 0.39, blue: 0.85) }
        if t.contains("telegram") { return Color(red: 0.0, green: 0.58, blue: 0.93) }
        return Color.brandAccent
    }
}

struct IronclawChannelsResponse: Codable {
    let channels: [IronclawConnectableChannel]?
    let items: [IronclawConnectableChannel]?
    var all: [IronclawConnectableChannel] { channels ?? items ?? [] }
}

// MARK: - Outbound Targets DTOs (webchat v2 /outbound/targets)

struct IronclawOutboundTarget: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let targetType: String?
    let address: String?
    let isActive: Bool?
    let triggerKind: String?

    enum CodingKeys: String, CodingKey {
        case id, name, address
        case targetType = "target_type"
        case isActive = "is_active"
        case triggerKind = "trigger_kind"
    }

    var displayType: String { targetType?.capitalized ?? "Target" }
    var displayAddress: String { address ?? "" }
    var icon: String {
        let t = (targetType ?? "").lowercased()
        if t.contains("email") || t.contains("mail") { return "envelope.fill" }
        if t.contains("slack") { return "number.square.fill" }
        if t.contains("telegram") { return "paperplane.fill" }
        if t.contains("discord") { return "gamecontroller.fill" }
        if t.contains("webhook") { return "bolt.fill" }
        if t.contains("sms") || t.contains("phone") { return "phone.fill" }
        return "arrow.up.forward.circle.fill"
    }
}

struct IronclawOutboundTargetsResponse: Codable {
    let targets: [IronclawOutboundTarget]?
    let items: [IronclawOutboundTarget]?
    var all: [IronclawOutboundTarget] { targets ?? items ?? [] }
}

// MARK: - Trace Commons DTOs (webchat v2 /traces/credit, /traces/holds/{id}/authorize)
// Mirrors the hosted IronClaw web UI Trace Commons tab: a per-account credit
// ledger for contributed redacted traces plus manual-review holds the user
// authorizes before submission. All fields optional — the server view is a
// snapshot and a not-enrolled account returns a sparse object.

struct IronclawTraceHold: Codable, Identifiable, Hashable {
    let submissionID: String
    let reason: String?

    var id: String { submissionID }
    var displayReason: String { reason?.nilIfBlank ?? "Held for review" }

    enum CodingKeys: String, CodingKey {
        case submissionID = "submission_id"
        case reason
    }
}

struct IronclawTraceCredits: Codable, Hashable {
    let enrolled: Bool?
    let pendingCredit: Double?
    let finalCredit: Double?
    let delayedCreditDelta: Double?
    let submissionsSubmitted: Int?
    let submissionsAccepted: Int?
    let submissionsTotal: Int?
    let lastSubmissionAt: String?
    let lastCreditSyncAt: String?
    let recentExplanations: [String]?
    let holds: [IronclawTraceHold]?

    enum CodingKeys: String, CodingKey {
        case enrolled, holds
        case pendingCredit = "pending_credit"
        case finalCredit = "final_credit"
        case delayedCreditDelta = "delayed_credit_delta"
        case submissionsSubmitted = "submissions_submitted"
        case submissionsAccepted = "submissions_accepted"
        case submissionsTotal = "submissions_total"
        case lastSubmissionAt = "last_submission_at"
        case lastCreditSyncAt = "last_credit_sync_at"
        case recentExplanations = "recent_explanations"
    }

    // Tolerant decode (mirrors the web UI's `Number(value) || 0` coercion): a
    // single field arriving with an unexpected JSON type must NOT discard the
    // whole ledger. Each field decodes independently; numbers accept number or
    // numeric-string; arrays/holds drop to nil rather than throw.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enrolled = (try? c.decodeIfPresent(Bool.self, forKey: .enrolled)) ?? nil
        pendingCredit = Self.lenientDouble(c, .pendingCredit)
        finalCredit = Self.lenientDouble(c, .finalCredit)
        delayedCreditDelta = Self.lenientDouble(c, .delayedCreditDelta)
        submissionsSubmitted = Self.lenientInt(c, .submissionsSubmitted)
        submissionsAccepted = Self.lenientInt(c, .submissionsAccepted)
        submissionsTotal = Self.lenientInt(c, .submissionsTotal)
        lastSubmissionAt = (try? c.decodeIfPresent(String.self, forKey: .lastSubmissionAt)) ?? nil
        lastCreditSyncAt = (try? c.decodeIfPresent(String.self, forKey: .lastCreditSyncAt)) ?? nil
        recentExplanations = (try? c.decodeIfPresent([String].self, forKey: .recentExplanations)) ?? nil
        holds = (try? c.decodeIfPresent([IronclawTraceHold].self, forKey: .holds)) ?? nil
    }

    private static func lenientDouble(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value }
        if let text = try? c.decodeIfPresent(String.self, forKey: key) { return Double(text) }
        return nil
    }

    private static func lenientInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let value = try? c.decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let text = try? c.decodeIfPresent(String.self, forKey: key) { return Int(text) ?? Double(text).map(Int.init) }
        return nil
    }

    var isEnrolled: Bool { enrolled ?? false }
    // Desktop empty-state parity: show stats once enrolled OR any submission exists.
    var hasActivity: Bool { isEnrolled || (submissionsTotal ?? 0) > 0 }
    // Drop malformed holds with no submission id (cannot be authorized).
    var activeHolds: [IronclawTraceHold] { (holds ?? []).filter { !$0.submissionID.isEmpty } }
    var explanations: [String] { recentExplanations ?? [] }
}

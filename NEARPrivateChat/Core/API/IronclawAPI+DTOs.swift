import Foundation

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

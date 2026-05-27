import Foundation

enum TelemetrySetupGoal: String, Codable, CaseIterable, Sendable {
    case privateChat = "private_chat"
    case research
    case agentWork = "agent_work"
    case verifiedMode = "verified_mode"
    case unsure
}

enum TelemetrySetupOutcome: String, Codable, CaseIterable, Sendable {
    case completed
    case skipped
}

enum TelemetryFocusMode: String, Codable, CaseIterable, Sendable {
    case ask
    case search
    case agent
    case context
}

enum TelemetryPromptChip: String, Codable, CaseIterable, Sendable {
    case ask
    case search
    case agent
    case research
    case sourceQA = "source_qa"
}

enum TelemetryOutcome: String, Codable, CaseIterable, Sendable {
    case succeeded
    case failed
}

enum TelemetryModelPickerTab: String, Codable, CaseIterable, Sendable {
    case frontier
    case privateModels = "private"
    case openWeight = "open_weight"
    case archived
}

enum TelemetryErrorCategory: String, Codable, CaseIterable, Sendable {
    case auth
    case network
    case streaming
    case upload
    case sharing
    case attestation
    case ironclaw
    case unknown
}

enum TelemetryProfileBucket: String, Codable, CaseIterable, Sendable {
    case unspecified
    case privateChat = "private_chat"
    case research
    case agentWork = "agent_work"
    case mixed
}

enum TelemetryForbiddenContentField: String, CaseIterable, Sendable {
    case prompt
    case response
    case fileName = "file_name"
    case sourceURL = "source_url"
    case accountID = "account_id"
    case conversationID = "conversation_id"
    case transcriptID = "transcript_id"
    case modelOutput = "model_output"
    case rawEventStream = "raw_event_stream"
    case rawErrorBody = "raw_error_body"
}

enum TelemetryEvent: Equatable, Hashable, Codable, Sendable {
    case setupGoalSelected(TelemetrySetupGoal)
    case setupCompletedOrSkipped(TelemetrySetupOutcome)
    case focusModeChanged(TelemetryFocusMode)
    case promptChipUsed(TelemetryPromptChip)
    case attestationChipTapped
    case attestationRefreshSucceededOrFailed(TelemetryOutcome)
    case modelPickerTabOpened(TelemetryModelPickerTab)
    case sharePreviewOpened
    case streamReconnected
    case genericError(TelemetryErrorCategory)

    enum CodingKeys: String, CodingKey {
        case name
        case variant
        case outcome
        case category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        switch name {
        case "setup_goal_selected":
            self = .setupGoalSelected(try container.decode(TelemetrySetupGoal.self, forKey: .variant))
        case "setup_completed_or_skipped":
            self = .setupCompletedOrSkipped(try container.decode(TelemetrySetupOutcome.self, forKey: .outcome))
        case "focus_mode_changed":
            self = .focusModeChanged(try container.decode(TelemetryFocusMode.self, forKey: .variant))
        case "prompt_chip_used":
            self = .promptChipUsed(try container.decode(TelemetryPromptChip.self, forKey: .variant))
        case "attestation_chip_tapped":
            self = .attestationChipTapped
        case "attestation_refresh_succeeded_or_failed":
            self = .attestationRefreshSucceededOrFailed(try container.decode(TelemetryOutcome.self, forKey: .outcome))
        case "model_picker_tab_opened":
            self = .modelPickerTabOpened(try container.decode(TelemetryModelPickerTab.self, forKey: .variant))
        case "share_preview_opened":
            self = .sharePreviewOpened
        case "stream_reconnected":
            self = .streamReconnected
        case "generic_error":
            self = .genericError(try container.decode(TelemetryErrorCategory.self, forKey: .category))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .name,
                in: container,
                debugDescription: "Unknown telemetry event: \(name)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        switch self {
        case let .setupGoalSelected(value):
            try container.encode(value, forKey: .variant)
        case let .setupCompletedOrSkipped(value):
            try container.encode(value, forKey: .outcome)
        case let .focusModeChanged(value):
            try container.encode(value, forKey: .variant)
        case let .promptChipUsed(value):
            try container.encode(value, forKey: .variant)
        case .attestationChipTapped:
            break
        case let .attestationRefreshSucceededOrFailed(value):
            try container.encode(value, forKey: .outcome)
        case let .modelPickerTabOpened(value):
            try container.encode(value, forKey: .variant)
        case .sharePreviewOpened, .streamReconnected:
            break
        case let .genericError(value):
            try container.encode(value, forKey: .category)
        }
    }

    var name: String {
        switch self {
        case .setupGoalSelected:
            return "setup_goal_selected"
        case .setupCompletedOrSkipped:
            return "setup_completed_or_skipped"
        case .focusModeChanged:
            return "focus_mode_changed"
        case .promptChipUsed:
            return "prompt_chip_used"
        case .attestationChipTapped:
            return "attestation_chip_tapped"
        case .attestationRefreshSucceededOrFailed:
            return "attestation_refresh_succeeded_or_failed"
        case .modelPickerTabOpened:
            return "model_picker_tab_opened"
        case .sharePreviewOpened:
            return "share_preview_opened"
        case .streamReconnected:
            return "stream_reconnected"
        case .genericError:
            return "generic_error"
        }
    }

    var counterKey: String {
        switch self {
        case let .setupGoalSelected(value):
            return "\(name).\(value.rawValue)"
        case let .setupCompletedOrSkipped(value):
            return "\(name).\(value.rawValue)"
        case let .focusModeChanged(value):
            return "\(name).\(value.rawValue)"
        case let .promptChipUsed(value):
            return "\(name).\(value.rawValue)"
        case .attestationChipTapped:
            return name
        case let .attestationRefreshSucceededOrFailed(value):
            return "\(name).\(value.rawValue)"
        case let .modelPickerTabOpened(value):
            return "\(name).\(value.rawValue)"
        case .sharePreviewOpened:
            return name
        case .streamReconnected:
            return name
        case let .genericError(value):
            return "\(name).\(value.rawValue)"
        }
    }
}

struct TelemetryContext: Codable, Equatable, Sendable {
    let appVersion: String
    let profileBucket: TelemetryProfileBucket

    init(appVersion: String = "local", profileBucket: TelemetryProfileBucket = .unspecified) {
        self.appVersion = Self.sanitizedVersion(appVersion)
        self.profileBucket = profileBucket
    }

    static func sanitizedVersion(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return sanitized.isEmpty ? "local" : sanitized
    }
}

struct TelemetryAggregateKey: Codable, Equatable, Hashable, Sendable {
    let day: String
    let appVersion: String
    let profileBucket: TelemetryProfileBucket
}

struct TelemetryDailyAggregate: Codable, Equatable, Sendable {
    var key: TelemetryAggregateKey
    var counters: [String: Int]
}

struct TelemetryDiagnosticsExport: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let generatedAt: Date
    let uploadEnabled: Bool
    let aggregates: [TelemetryDailyAggregate]
}

struct PrivateTelemetrySettings: Codable, Equatable, Sendable {
    static let userDefaultsKey = "PrivateTelemetry.shareUsageStatistics"

    var sharePrivateUsageStatistics: Bool

    static let disabledByDefault = PrivateTelemetrySettings(sharePrivateUsageStatistics: false)
}

final class PrivateTelemetryStore {
    static let schemaVersion = 1

    private let storageURL: URL
    private let fileManager: FileManager
    private var aggregates: [TelemetryAggregateKey: TelemetryDailyAggregate]

    init(storageURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.storageURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)
        self.aggregates = (try? Self.loadAggregates(from: self.storageURL)) ?? [:]
    }

    func record(
        _ event: TelemetryEvent,
        at date: Date = Date(),
        context: TelemetryContext = TelemetryContext()
    ) throws {
        let key = TelemetryAggregateKey(
            day: Self.dayString(for: date),
            appVersion: context.appVersion,
            profileBucket: context.profileBucket
        )
        var aggregate = aggregates[key] ?? TelemetryDailyAggregate(key: key, counters: [:])
        aggregate.counters[event.counterKey, default: 0] += 1
        aggregates[key] = aggregate
        try persist()
    }

    func diagnosticsExport(generatedAt: Date = Date()) -> TelemetryDiagnosticsExport {
        TelemetryDiagnosticsExport(
            schemaVersion: Self.schemaVersion,
            generatedAt: generatedAt,
            uploadEnabled: false,
            aggregates: aggregates.values.sorted {
                if $0.key.day != $1.key.day {
                    return $0.key.day < $1.key.day
                }
                if $0.key.appVersion != $1.key.appVersion {
                    return $0.key.appVersion < $1.key.appVersion
                }
                return $0.key.profileBucket.rawValue < $1.key.profileBucket.rawValue
            }
        )
    }

    func diagnosticsExportData(generatedAt: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(diagnosticsExport(generatedAt: generatedAt))
    }

    private func persist() throws {
        let directory = storageURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = Array(aggregates.values)
        let data = try encoder.encode(payload)
        try data.write(to: storageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private static func loadAggregates(from url: URL) throws -> [TelemetryAggregateKey: TelemetryDailyAggregate] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let values = try decoder.decode([TelemetryDailyAggregate].self, from: data)
        return Dictionary(uniqueKeysWithValues: values.map { ($0.key, $0) })
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL
            .appendingPathComponent("NEARPrivateChat", isDirectory: true)
            .appendingPathComponent("PrivateTelemetryCounters.json")
    }

    static func dayString(for date: Date, calendar: Calendar = .telemetryUTC) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1970,
            components.month ?? 1,
            components.day ?? 1
        )
    }
}

private extension Calendar {
    static var telemetryUTC: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}

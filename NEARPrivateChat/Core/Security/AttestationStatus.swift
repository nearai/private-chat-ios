import Foundation
import SwiftUI

enum AttestationFreshness: String, Codable, Equatable, Sendable {
    case underTwoMinutes = "under_2m"
    case underOneHour = "under_1h"
    case stale

    static func classify(attestedAt: Date?, now: Date = Date()) -> AttestationFreshness {
        guard let attestedAt else { return .stale }
        let age = max(0, now.timeIntervalSince(attestedAt))
        if age < 120 {
            return .underTwoMinutes
        }
        if age < 3_600 {
            return .underOneHour
        }
        return .stale
    }

    var shortLabel: String {
        switch self {
        case .underTwoMinutes:
            return "<2m"
        case .underOneHour:
            return "<1h"
        case .stale:
            return "stale"
        }
    }
}

enum AttestationState: String, Codable, Equatable, Sendable {
    case unknown
    case valid
    case stale
    case unavailable
    case mismatch
}

enum ProofState: String, Codable, Equatable, Sendable {
    case unknown
    case verifying
    case verified
    case stale
    case mismatch
    case private_
    case proxied
    case unverified
}

enum AttestationModelCoverage: String, Codable, Equatable, Sendable {
    case covered
    case stale
    case notCovered = "not_covered"
    case unknown
}

struct AttestationEvidence: Codable, Equatable, Sendable {
    var verifiedAt: Date
    var coveredModelIDs: [String]
    var routeName: String?
    var nonce: String?
    var signingAlgorithm: String?

    init(
        verifiedAt: Date,
        coveredModelIDs: [String],
        routeName: String? = nil,
        nonce: String? = nil,
        signingAlgorithm: String? = nil
    ) {
        self.verifiedAt = verifiedAt
        self.coveredModelIDs = coveredModelIDs
        self.routeName = routeName
        self.nonce = nonce
        self.signingAlgorithm = signingAlgorithm
    }

    func covers(modelID: String) -> Bool {
        let normalizedModel = Self.normalizedModelID(modelID)
        return coveredModelIDs.contains { Self.normalizedModelID($0) == normalizedModel }
    }

    static func normalizedModelID(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct AttestationStatusCopy: Codable, Equatable, Sendable {
    let title: String
    let detail: String
    let badge: String
}

struct ProofCapsuleViewModel: Codable, Equatable, Sendable {
    let state: ProofState
    let title: String
    let detail: String
    let badge: String
    let symbolName: String

    init(
        status: AttestationStatus,
        isLoading: Bool = false,
        modelID: String? = nil,
        now: Date = Date()
    ) {
        if isLoading {
            state = .verifying
            title = "Checking proof"
            detail = "Fetching signed proof for this private route."
            badge = "Checking"
            symbolName = "arrow.triangle.2.circlepath"
            return
        }

        let copy = status.userFacingCopy(at: now)
        title = copy.title
        detail = copy.detail
        badge = copy.badge
        symbolName = status.symbolName

        switch status.effectiveState(at: now) {
        case .valid:
            state = status.coverage(for: modelID, at: now) == .covered ? .verified : .verified
        case .stale:
            state = .stale
        case .mismatch:
            state = .mismatch
        case .unavailable:
            state = .unverified
        case .unknown:
            state = .unknown
        }
    }

    init(state: ProofState, title: String, detail: String, badge: String, symbolName: String) {
        self.state = state
        self.title = title
        self.detail = detail
        self.badge = badge
        self.symbolName = symbolName
    }

    var tintColor: Color {
        switch state {
        case .unknown, .private_, .proxied, .unverified:
            return .secondary
        case .verifying:
            return .proofStale
        case .verified:
            return .proofVerified
        case .stale:
            return .proofStale
        case .mismatch:
            return .proofMismatch
        }
    }
}

enum AttestationUnavailableReason: String, Codable, Equatable, Sendable {
    case notFetched = "not_fetched"
    case routeNotSupported = "route_not_supported"
    case serviceUnavailable = "service_unavailable"
    case modelCoverageUnavailable = "model_coverage_unavailable"
}

enum AttestationStatus: Codable, Equatable, Sendable {
    case unknown
    case valid(AttestationEvidence)
    case stale(AttestationEvidence)
    case unavailable(reason: AttestationUnavailableReason)
    case mismatch(expectedModelID: String, evidence: AttestationEvidence?)

    init(snapshot: AttestationSnapshot?, selectedModelID: String?) {
        guard let snapshot else {
            self = .unknown
            return
        }

        let coveredModelIDs = snapshot.coveredModelIDs.isEmpty
            ? snapshot.model.map { [$0] } ?? []
            : snapshot.coveredModelIDs
        guard !coveredModelIDs.isEmpty else {
            self = .unavailable(reason: .modelCoverageUnavailable)
            return
        }
        let evidence = AttestationEvidence(
            verifiedAt: snapshot.fetchedAt,
            coveredModelIDs: coveredModelIDs,
            routeName: "NEAR Private",
            nonce: snapshot.nonce,
            signingAlgorithm: snapshot.signingAlgorithm
        )

        if let selectedModelID, !evidence.covers(modelID: selectedModelID) {
            self = .mismatch(expectedModelID: selectedModelID, evidence: evidence)
        } else if AttestationFreshness.classify(attestedAt: snapshot.fetchedAt) == .stale {
            self = .stale(evidence)
        } else {
            self = .valid(evidence)
        }
    }

    var state: AttestationState {
        switch self {
        case .unknown:
            return .unknown
        case .valid:
            return .valid
        case .stale:
            return .stale
        case .unavailable:
            return .unavailable
        case .mismatch:
            return .mismatch
        }
    }

    func effectiveState(at now: Date = Date()) -> AttestationState {
        switch self {
        case let .valid(evidence):
            return AttestationFreshness.classify(attestedAt: evidence.verifiedAt, now: now) == .stale ? .stale : .valid
        case .stale:
            return .stale
        default:
            return state
        }
    }

    func freshness(at now: Date = Date()) -> AttestationFreshness? {
        evidence.map { AttestationFreshness.classify(attestedAt: $0.verifiedAt, now: now) }
    }

    func coverage(for modelID: String?, at now: Date = Date()) -> AttestationModelCoverage {
        guard let modelID, !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .unknown
        }
        guard let evidence else {
            return .unknown
        }
        guard evidence.covers(modelID: modelID) else {
            return .notCovered
        }
        return effectiveState(at: now) == .valid ? .covered : .stale
    }

    func covers(modelID: String, at now: Date = Date()) -> Bool {
        coverage(for: modelID, at: now) == .covered
    }

    var evidence: AttestationEvidence? {
        switch self {
        case let .valid(evidence), let .stale(evidence):
            return evidence
        case let .mismatch(_, evidence):
            return evidence
        case .unknown, .unavailable:
            return nil
        }
    }

    func userFacingCopy(at now: Date = Date()) -> AttestationStatusCopy {
        switch effectiveState(at: now) {
        case .valid:
            let freshnessText = freshness(at: now)?.shortLabel ?? "fresh"
            return AttestationStatusCopy(
                title: "Verified",
                detail: "Checked on this device against signed proof from TEE-supported infrastructure. Verification does not judge answer quality or truth.",
                badge: "Verified \(freshnessText)"
            )
        case .stale:
            return AttestationStatusCopy(
                title: "Proof stale",
                detail: "The last proof is old. Refresh before relying on route or model coverage.",
                badge: "Stale proof"
            )
        case .unavailable:
            return unavailableCopy
        case .mismatch:
            return AttestationStatusCopy(
                title: "Model not covered",
                detail: "The current proof is for a different model or route. Refresh attestation after changing models.",
                badge: "Not covered"
            )
        case .unknown:
            return AttestationStatusCopy(
                title: "Verification pending",
                detail: "No signed verification report has been checked on this device yet.",
                badge: "Pending"
            )
        }
    }

    private var unavailableCopy: AttestationStatusCopy {
        switch self {
        case let .unavailable(reason):
            switch reason {
            case .routeNotSupported:
                return AttestationStatusCopy(
                    title: "Unverified route",
                    detail: "This route does not carry NEAR Private verification. Use a private model when verification matters.",
                    badge: "Unverified"
                )
            case .serviceUnavailable:
                return AttestationStatusCopy(
                    title: "Proof service down",
                    detail: "Could not fetch attestation right now. This is a network or service issue, not a model failure.",
                    badge: "Service down"
                )
            case .modelCoverageUnavailable:
                return AttestationStatusCopy(
                    title: "Model proof unavailable",
                    detail: "The report did not include model coverage metadata. The model can still run.",
                    badge: "No model proof"
                )
            case .notFetched:
                return AttestationStatusCopy(
                    title: "Verification pending",
                    detail: "Fetch verification on a NEAR Private model to inspect route and model proof.",
                    badge: "Pending"
                )
            }
        default:
            return AttestationStatusCopy(
                title: "Verification pending",
                detail: "No local verification report is available for this route.",
                badge: "Pending"
            )
        }
    }

    func accessibilityLabel(at now: Date = Date()) -> String {
        let copy = userFacingCopy(at: now)
        return "Verification state: \(copy.badge). \(copy.title)"
    }

    func accessibilityHint(at now: Date = Date()) -> String {
        userFacingCopy(at: now).detail
    }

    var symbolName: String {
        switch state {
        case .valid:
            return "checkmark.shield.fill"
        case .stale:
            return "clock.badge.exclamationmark"
        case .mismatch:
            return "exclamationmark.shield.fill"
        case .unavailable:
            return "shield.slash"
        case .unknown:
            return "shield"
        }
    }

    var tintColor: Color {
        switch state {
        case .valid:
            return .proofVerified
        case .stale:
            return .proofStale
        case .mismatch:
            return .proofMismatch
        case .unavailable:
            return .secondary
        case .unknown:
            return .brandGrey
        }
    }
}

struct AttestationEducationSection: Codable, Equatable, Sendable, Identifiable {
    var id: String { title }
    let title: String
    let body: String
}

struct AttestationEducation: Codable, Equatable, Sendable {
    let headline: String
    let summary: String
    let sections: [AttestationEducationSection]

    static let standard = AttestationEducation(
        headline: "Proof, not a promise.",
        summary: "Checked on this device against signed proof from TEE-supported infrastructure.",
        sections: [
            AttestationEducationSection(
                title: "What is verified",
                body: "The app verifies signed evidence for the private route, runtime, signing details, freshness, and whether the selected model is covered by the current proof."
            ),
            AttestationEducationSection(
                title: "What is not verified",
                body: "Verification does not judge the truthfulness, safety, reasoning quality, or completeness of the model's answer."
            ),
            AttestationEducationSection(
                title: "Stale or unavailable",
                body: "Stale means the proof is old and should be refreshed. Unavailable means this route or model has no current proof in the app."
            ),
            AttestationEducationSection(
                title: "Different routes",
                body: "External, NEAR Cloud, and IronClaw routes may show different states because they are not necessarily covered by the same hardware-rooted proof."
            )
        ]
    )
}

struct AttestationStatusBadge: View {
    let status: AttestationStatus
    let modelID: String?
    var now: Date = Date()

    var body: some View {
        ProofCapsule(viewModel: ProofCapsuleViewModel(status: status, modelID: modelID, now: now))
    }
}

struct ProofCapsule: View {
    let viewModel: ProofCapsuleViewModel

    var body: some View {
        HStack(spacing: 6) {
            if viewModel.state == .verifying {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: viewModel.symbolName)
                    .font(.caption.weight(.bold))
            }
            Text(viewModel.badge)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(viewModel.tintColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(viewModel.tintColor.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.badge). \(viewModel.title)")
        .accessibilityHint(viewModel.detail)
    }
}

extension Color {
    static let verifiedGreen = Color.proofVerified
}

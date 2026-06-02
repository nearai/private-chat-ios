import CryptoKit
import Foundation

@MainActor
final class SecurityStore: ObservableObject {
    @Published private(set) var attestationSnapshot: AttestationSnapshot?
    @Published private(set) var attestationFetchErrorMessage: String?
    @Published private(set) var isLoadingAttestation = false

    var bannerHandler: ((String) -> Void)?

    private let attestationAPI: AttestationAPI

    init(attestationAPI: AttestationAPI) {
        self.attestationAPI = attestationAPI
    }

    func clearAttestationState() {
        attestationSnapshot = nil
        attestationFetchErrorMessage = nil
    }

    func replaceAttestationSnapshot(_ snapshot: AttestationSnapshot?, errorMessage: String? = nil) {
        attestationSnapshot = snapshot
        attestationFetchErrorMessage = errorMessage
        isLoadingAttestation = false
    }

    func currentAttestationStatus(
        selectedModelID: String,
        selectedRouteKind: ChatRouteKind,
        isCouncilModeEnabled: Bool,
        activeCouncilHasExternalRoutes: Bool
    ) -> AttestationStatus {
        if isCouncilModeEnabled {
            guard !activeCouncilHasExternalRoutes else {
                return .unavailable(reason: .routeNotSupported)
            }
            return privateRouteAttestationStatus(selectedModelID: selectedModelID)
        }
        guard selectedRouteKind == .nearPrivate else {
            return .unavailable(reason: .routeNotSupported)
        }
        return privateRouteAttestationStatus(selectedModelID: selectedModelID)
    }

    func refreshAttestationReport(
        selectedModelID: String,
        selectedRouteKind: ChatRouteKind,
        isCouncilModeEnabled: Bool,
        activeCouncilHasExternalRoutes: Bool
    ) async {
        if isCouncilModeEnabled, activeCouncilHasExternalRoutes {
            showBanner("Proof is available for all-private Council lineups. Remove NEAR AI Cloud models to fetch proof.")
            return
        }
        guard selectedRouteKind == .nearPrivate else {
            showBanner("Proof is available for NEAR Private models.")
            return
        }

        isLoadingAttestation = true
        defer { isLoadingAttestation = false }
        attestationFetchErrorMessage = nil

        do {
            attestationSnapshot = try await attestationAPI.fetchAttestationReport(
                nonce: Self.makeNonce(),
                signingAlgorithm: "ecdsa",
                model: selectedModelID
            )
            attestationFetchErrorMessage = nil
            showBanner("Attestation refreshed.")
        } catch {
            attestationFetchErrorMessage = error.localizedDescription
            showBanner(error.localizedDescription)
        }
    }

    func signedTranscriptExportContext(
        provider: String,
        privacyRoute: String,
        sourceMode: String,
        webSearchEnabled: Bool,
        projectID: String?
    ) -> SignedTranscriptExportContext {
        SignedTranscriptExportContext(
            provider: provider,
            privacyRoute: privacyRoute,
            sourceMode: sourceMode,
            webSearchEnabled: webSearchEnabled,
            projectID: projectID,
            ownerHash: nil,
            attestationSnapshot: attestationSnapshot
        )
    }

    func signedTranscriptExportContext(
        selectedProviderDisplayName: String,
        selectedRouteUsesNearCloud: Bool,
        selectedModelIsIronclawMobileRuntime: Bool,
        sourceRoutingSemantics semantics: ChatSourceRoutingSemantics,
        projectID: String?
    ) -> SignedTranscriptExportContext {
        let provider = switch selectedProviderDisplayName {
        case "NEAR AI Cloud":
            "near-cloud"
        case "IronClaw":
            selectedModelIsIronclawMobileRuntime ? "ironclaw-mobile" : "ironclaw-hosted"
        case "LLM Council":
            "llm-council"
        default:
            "near-private"
        }
        let privacyRoute = if selectedRouteUsesNearCloud {
            "external-cloud"
        } else if selectedProviderDisplayName == "IronClaw" {
            selectedModelIsIronclawMobileRuntime ? "phone-agent" : "hosted-agent"
        } else {
            "tee-private"
        }
        return signedTranscriptExportContext(
            provider: provider,
            privacyRoute: privacyRoute,
            sourceMode: semantics.focus.rawValue,
            webSearchEnabled: semantics.modelNativeWebToolEnabledByDefault || semantics.appWebGroundingPolicy.isEnabledByDefault,
            projectID: projectID
        )
    }

    func assistantTrustMetadata(
        for modelID: String?,
        routeKind: ChatRouteKind,
        sourceMode: ChatSourceMode,
        webSearchUsed: Bool?,
        defaultWebSearchEnabled: Bool,
        researchModeEnabled: Bool,
        projectContextIncluded: Bool,
        capturedAt: Date
    ) -> MessageTrustMetadata {
        let route = MessageRouteMetadata(
            modelID: modelID,
            routeKind: routeKind,
            sourceMode: sourceMode,
            webSearchEnabled: webSearchUsed ?? defaultWebSearchEnabled,
            researchModeEnabled: researchModeEnabled,
            projectContextIncluded: projectContextIncluded,
            capturedAt: capturedAt
        )
        return MessageTrustMetadata(
            route: route,
            proof: assistantProofMetadata(
                for: modelID,
                routeKind: routeKind,
                capturedAt: capturedAt
            ),
            capturedAt: capturedAt
        )
    }

    private func privateRouteAttestationStatus(selectedModelID: String?) -> AttestationStatus {
        if attestationSnapshot == nil, attestationFetchErrorMessage != nil {
            return .unavailable(reason: .serviceUnavailable)
        }
        return AttestationStatus(snapshot: attestationSnapshot, selectedModelID: selectedModelID)
    }

    private func assistantProofMetadata(
        for modelID: String?,
        routeKind: ChatRouteKind,
        capturedAt: Date
    ) -> MessageProofMetadata {
        switch routeKind {
        case .nearPrivate:
            let status = AttestationStatus(snapshot: attestationSnapshot, selectedModelID: modelID)
            let viewModel = ProofCapsuleViewModel(status: status, modelID: modelID, now: capturedAt)
            let evidence = status.evidence
            return MessageProofMetadata(
                state: viewModel.state,
                title: viewModel.state == .verified ? "Proof captured with answer" : viewModel.title,
                detail: viewModel.state == .verified
                    ? "A fresh proof report covering this route/model was available on this device when the answer was generated."
                    : viewModel.detail,
                badge: viewModel.badge,
                symbolName: viewModel.symbolName,
                freshness: status.freshness(at: capturedAt)?.shortLabel,
                reportHash: attestationSnapshot.map { Self.sha256Digest($0.prettyJSON) },
                coveredModelCount: evidence?.coveredModelIDs.count ?? 0,
                coversSelectedModel: modelID.map { status.covers(modelID: $0, at: capturedAt) },
                capturedAt: capturedAt
            )
        case .nearCloud:
            return MessageProofMetadata(
                state: .proxied,
                title: "Privacy proxy",
                detail: "This answer used NEAR AI Cloud privacy proxy routing. Cloud answers do not carry NEAR Private proof.",
                badge: "Privacy proxy",
                symbolName: "eye.slash",
                freshness: nil,
                reportHash: nil,
                coveredModelCount: 0,
                coversSelectedModel: nil,
                capturedAt: capturedAt
            )
        case .ironclawMobile, .ironclawHosted:
            return MessageProofMetadata(
                state: .unverified,
                title: "Agent route",
                detail: "This answer used Agent tooling. NEAR Private proof applies only when the underlying model route supplies it.",
                badge: "Agent",
                symbolName: "terminal",
                freshness: nil,
                reportHash: nil,
                coveredModelCount: 0,
                coversSelectedModel: nil,
                capturedAt: capturedAt
            )
        }
    }

    private func showBanner(_ message: String) {
        bannerHandler?(message)
    }

    private static func makeNonce() -> String {
        (0..<32)
            .map { _ in String(format: "%02x", UInt8.random(in: UInt8.min ... UInt8.max)) }
            .joined()
    }

    private static func sha256Digest(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

private final class FakeSecurityAttestationAPI: AttestationAPI {
    var snapshot: AttestationSnapshot?
    var error: Error?
    private(set) var requestedModels: [String?] = []

    func fetchAttestationReport(
        nonce: String,
        signingAlgorithm: String,
        model: String?
    ) async throws -> AttestationSnapshot {
        requestedModels.append(model)
        if let error {
            throw error
        }
        return snapshot ?? AttestationSnapshot(
            nonce: nonce,
            signingAlgorithm: signingAlgorithm,
            model: model,
            coveredModelIDs: model.map { [$0] } ?? [],
            fetchedAt: Date(),
            chatGatewayAddress: "0xchat",
            cloudGatewayAddress: nil,
            modelAttestationCount: model == nil ? 0 : 1,
            prettyJSON: #"{"proof":"ok"}"#
        )
    }
}

extension PrivateChatCoreTests {
    func testLegacyChatMessageDecodesWithoutTrustMetadata() throws {
        let payload = Data("""
        {
          "id": "msg-legacy-1",
          "role": "assistant",
          "text": "Legacy answer.",
          "model": "zai-org/GLM-latest",
          "createdAt": 0,
          "status": "completed",
          "responseID": "resp-legacy-1",
          "isStreaming": false,
          "sources": [],
          "attachments": []
        }
        """.utf8)

        let message = try JSONDecoder().decode(ChatMessage.self, from: payload)

        XCTAssertEqual(message.id, "msg-legacy-1")
        XCTAssertNil(message.trustMetadata)
    }

    func testTrustSurfaceColorsMeetWCAGAA() {
        let textTokens = [
            Color.brandBlueToken,
            Color.proofVerifiedToken,
            Color.proofStaleToken
        ]

        for token in textTokens {
            XCTAssertGreaterThanOrEqual(token.contrastRatioAgainstWhite(), 4.5)
            XCTAssertGreaterThanOrEqual(token.contrastRatio(against: Color.appBackgroundDarkToken), 3.0)
            XCTAssertGreaterThanOrEqual(token.contrastRatio(against: Color.appPanelBackgroundDarkToken), 3.0)
            XCTAssertGreaterThanOrEqual(token.contrastRatio(against: Color.appSecondaryBackgroundDarkToken), 3.0)
        }
    }

    @MainActor
    func testSecurityStoreRefreshesProofAndDerivesCurrentStatus() async {
        let now = Date()
        let api = FakeSecurityAttestationAPI()
        api.snapshot = AttestationSnapshot(
            nonce: "nonce-1",
            signingAlgorithm: "ecdsa",
            model: "zai-org/GLM-5.1-FP8",
            coveredModelIDs: ["zai-org/GLM-5.1-FP8"],
            fetchedAt: now,
            chatGatewayAddress: "0xchat",
            cloudGatewayAddress: nil,
            modelAttestationCount: 1,
            prettyJSON: #"{"covered":"zai-org/GLM-5.1-FP8"}"#
        )
        let store = SecurityStore(attestationAPI: api)
        var banners: [String] = []
        store.bannerHandler = { banners.append($0) }

        await store.refreshAttestationReport(
            selectedModelID: "zai-org/GLM-5.1-FP8",
            selectedRouteKind: .nearPrivate,
            isCouncilModeEnabled: false,
            activeCouncilHasExternalRoutes: false
        )

        XCTAssertEqual(api.requestedModels, ["zai-org/GLM-5.1-FP8"])
        XCTAssertNotNil(store.attestationSnapshot)
        XCTAssertNil(store.attestationFetchErrorMessage)
        XCTAssertFalse(store.isLoadingAttestation)
        XCTAssertEqual(banners.last, "Attestation refreshed.")
        XCTAssertEqual(
            store.currentAttestationStatus(
                selectedModelID: "zai-org/GLM-5.1-FP8",
                selectedRouteKind: .nearPrivate,
                isCouncilModeEnabled: false,
                activeCouncilHasExternalRoutes: false
            ).state,
            .valid
        )
    }

    @MainActor
    func testSecurityStoreFailureAndExternalRoutesDoNotRenderVerified() async {
        let api = FakeSecurityAttestationAPI()
        api.error = NSError(domain: "proof", code: 401, userInfo: [NSLocalizedDescriptionKey: "Proof service unavailable"])
        let store = SecurityStore(attestationAPI: api)

        await store.refreshAttestationReport(
            selectedModelID: "private-model",
            selectedRouteKind: .nearPrivate,
            isCouncilModeEnabled: false,
            activeCouncilHasExternalRoutes: false
        )

        XCTAssertEqual(store.attestationFetchErrorMessage, "Proof service unavailable")
        XCTAssertEqual(
            store.currentAttestationStatus(
                selectedModelID: "private-model",
                selectedRouteKind: .nearPrivate,
                isCouncilModeEnabled: false,
                activeCouncilHasExternalRoutes: false
            ).effectiveState(),
            .unavailable
        )
        XCTAssertEqual(
            store.currentAttestationStatus(
                selectedModelID: "private-model",
                selectedRouteKind: .nearCloud,
                isCouncilModeEnabled: false,
                activeCouncilHasExternalRoutes: false
            ).effectiveState(),
            .unavailable
        )
    }

    @MainActor
    func testSecurityStoreBuildsAssistantTrustMetadataFromCapturedProof() {
        let now = Date()
        let store = SecurityStore(attestationAPI: FakeSecurityAttestationAPI())
        store.replaceAttestationSnapshot(AttestationSnapshot(
            nonce: "nonce-1",
            signingAlgorithm: "ecdsa",
            model: "zai-org/GLM-5.1-FP8",
            coveredModelIDs: ["zai-org/GLM-5.1-FP8"],
            fetchedAt: now,
            chatGatewayAddress: "0xchat",
            cloudGatewayAddress: nil,
            modelAttestationCount: 1,
            prettyJSON: #"{"proof":"captured"}"#
        ))

        let trust = store.assistantTrustMetadata(
            for: "zai-org/GLM-5.1-FP8",
            routeKind: .nearPrivate,
            sourceMode: .auto,
            webSearchUsed: nil,
            defaultWebSearchEnabled: false,
            researchModeEnabled: false,
            projectContextIncluded: true,
            capturedAt: now
        )

        XCTAssertEqual(trust.route.routeKind, ChatRouteKind.nearPrivate.rawValue)
        XCTAssertTrue(trust.route.projectContextIncluded)
        XCTAssertEqual(trust.proof?.state, .verified)
        XCTAssertEqual(trust.proof?.title, "Proof captured with answer")
        XCTAssertEqual(trust.proof?.coversSelectedModel, true)
        XCTAssertEqual(trust.proof?.coveredModelCount, 1)
        XCTAssertTrue(trust.proof?.reportHash?.hasPrefix("sha256:") == true)
    }

    @MainActor
    func testSecurityStoreBuildsSignedTranscriptContextFromRouteSemantics() {
        let store = SecurityStore(attestationAPI: FakeSecurityAttestationAPI())
        let semantics = ChatSourceRoutingSemantics.evaluate(
            sourceMode: .web,
            researchModeEnabled: false,
            webSearchEnabled: true,
            route: .nearCloud
        )

        let context = store.signedTranscriptExportContext(
            selectedProviderDisplayName: "NEAR AI Cloud",
            selectedRouteUsesNearCloud: true,
            selectedModelIsIronclawMobileRuntime: false,
            sourceRoutingSemantics: semantics,
            projectID: "project-1"
        )

        XCTAssertEqual(context.provider, "near-cloud")
        XCTAssertEqual(context.privacyRoute, "external-cloud")
        XCTAssertEqual(context.sourceMode, "web")
        XCTAssertTrue(context.webSearchEnabled)
        XCTAssertEqual(context.projectID, "project-1")
    }

    func testStarterPresetPreviewPlanFallsBackToPrivateRouteWhenIronclawIsUnavailable() {
        let routeDefaults = SetupRouteDefaults(
            privateModelID: "private-model",
            councilModelIDs: ["council-a", "council-b"],
            ironclawMobileModelID: ModelOption.ironclawMobileModelID
        )
        let readiness = AppSetupReadinessSnapshot(
            modelCatalogLoaded: true,
            privateModelAvailable: true,
            defaultCouncilModelCount: 3,
            ironclawMobileAvailable: false,
            hostedIronclawAvailable: false,
            nearCloudKeyConfigured: false
        )

        let plan = UserSetupStarterPreset.agentMission.previewPlan(
            readiness: readiness,
            routeDefaults: routeDefaults
        )

        XCTAssertEqual(plan.modelRoute, .privateModel)
        XCTAssertEqual(plan.expectedFirstAction, "Start private chat while Agent tools load")
        XCTAssertEqual(plan.expectedRouteModelIDs, ["private-model"])
        XCTAssertEqual(plan.routeDetailContent?.title, "NEAR Private route")
        XCTAssertEqual(plan.routeDetailContent?.summary, "Private Model · attested when proof is fresh.")
        XCTAssertEqual(plan.routeDetailContent?.symbolName, "lock.shield")
        XCTAssertEqual(plan.readinessStatus, "IronClaw Mobile is still loading; private chat is ready first.")
    }


    @MainActor
    func testSoulMarkdownIdentityAndRulesArePrivateRouteOnly() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.soulMarkdown = """
        # soul.md

        ## Identity -- who you are
        Call me Sam Example. My account email is sam@example.com.

        ## Intent -- what I use this for
        Legal memos and contract review.

        ## Voice & Format -- how to talk and respond
        Lead with the answer. No filler.

        ## Rules -- conditional
        <important if="legal">Flag uncertainty before drafting final language.</important>
        """

        let privatePrompt = store.activeSystemPromptForTesting(model: ModelOption.nearPrivateDefaultModelID)
        XCTAssertTrue(privatePrompt.contains("About the user / Response preferences"))
        XCTAssertTrue(privatePrompt.contains("Identity (private route only):"))
        XCTAssertTrue(privatePrompt.contains("Sam Example"))
        XCTAssertTrue(privatePrompt.contains("sam@example.com"))
        XCTAssertTrue(privatePrompt.contains("Legal memos and contract review."))
        XCTAssertTrue(privatePrompt.contains("Rules (private route only):"))
        XCTAssertTrue(privatePrompt.contains("Flag uncertainty"))
        XCTAssertTrue(privatePrompt.contains("Format contract:"))

        let cloudPrompt = store.activeSystemPromptForTesting(model: ModelOption.nearCloudModelID(for: "provider/current-model"))
        XCTAssertFalse(cloudPrompt.contains("Sam Example"))
        XCTAssertFalse(cloudPrompt.contains("sam@example.com"))
        XCTAssertFalse(cloudPrompt.contains("Identity (private route only):"))
        XCTAssertFalse(cloudPrompt.contains("Rules (private route only):"))
        XCTAssertFalse(cloudPrompt.contains("Flag uncertainty"))
        XCTAssertTrue(cloudPrompt.contains("Legal memos and contract review."))
        XCTAssertTrue(cloudPrompt.contains("Lead with the answer. No filler."))

        let mobilePrompt = store.activeSystemPromptForTesting(model: ModelOption.ironclawMobileModelID)
        XCTAssertFalse(mobilePrompt.contains("Sam Example"))
        XCTAssertFalse(mobilePrompt.contains("sam@example.com"))
        XCTAssertFalse(mobilePrompt.contains("Flag uncertainty"))
        XCTAssertTrue(mobilePrompt.contains("Legal memos and contract review."))
    }

    func testAttestationFreshnessClassification() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertEqual(
            AttestationFreshness.classify(attestedAt: now.addingTimeInterval(-119), now: now),
            .underTwoMinutes
        )
        XCTAssertEqual(
            AttestationFreshness.classify(attestedAt: now.addingTimeInterval(-3_599), now: now),
            .underOneHour
        )
        XCTAssertEqual(
            AttestationFreshness.classify(attestedAt: now.addingTimeInterval(-3_600), now: now),
            .stale
        )
        XCTAssertEqual(AttestationFreshness.classify(attestedAt: nil, now: now), .stale)
    }

    func testAttestationModelCoverageRequiresFreshValidProof() {
        let now = Date(timeIntervalSince1970: 20_000)
        let evidence = AttestationEvidence(
            verifiedAt: now.addingTimeInterval(-30),
            coveredModelIDs: ["zai-org/GLM-5.1-FP8"],
            routeName: "NEAR Private"
        )
        let status = AttestationStatus.valid(evidence)

        XCTAssertEqual(status.coverage(for: "ZAI-ORG/glm-5.1-fp8", at: now), .covered)
        XCTAssertTrue(status.covers(modelID: "zai-org/GLM-5.1-FP8", at: now))
        XCTAssertEqual(status.coverage(for: "qwen/qwen3.7-max", at: now), .notCovered)
        XCTAssertFalse(status.covers(modelID: "zai-org/GLM-5.1-FP8", at: now.addingTimeInterval(3_700)))
        XCTAssertEqual(status.coverage(for: "zai-org/GLM-5.1-FP8", at: now.addingTimeInterval(3_700)), .stale)
    }

    func testAttestationSnapshotDoesNotInferCoverageFromSelectedModel() {
        let now = Date()
        let snapshot = AttestationSnapshot(
            nonce: "nonce-1",
            signingAlgorithm: "ecdsa",
            model: nil,
            fetchedAt: now,
            chatGatewayAddress: "0xchat",
            cloudGatewayAddress: nil,
            modelAttestationCount: 12,
            prettyJSON: "{}"
        )
        let status = AttestationStatus(snapshot: snapshot, selectedModelID: "zai-org/GLM-5.1-FP8")

        XCTAssertEqual(status.coverage(for: "zai-org/GLM-5.1-FP8", at: now), .unknown)
        XCTAssertEqual(status.state, .unavailable)
    }

    func testAttestationSnapshotUsesAllReportedCoveredModels() {
        let now = Date()
        let snapshot = AttestationSnapshot(
            nonce: "nonce-1",
            signingAlgorithm: "ecdsa",
            model: "qwen/qwen3.7-max",
            coveredModelIDs: [
                "qwen/qwen3.7-max",
                "zai-org/GLM-5.1-FP8",
                "moonshotai/kimi-k2.6"
            ],
            fetchedAt: now,
            chatGatewayAddress: "0xchat",
            cloudGatewayAddress: nil,
            modelAttestationCount: 3,
            prettyJSON: "{}"
        )

        let status = AttestationStatus(snapshot: snapshot, selectedModelID: "zai-org/GLM-5.1-FP8")

        XCTAssertEqual(status.coverage(for: "zai-org/GLM-5.1-FP8", at: now), .covered)
        XCTAssertEqual(status.state, .valid)
    }

    func testProofCapsuleUsesVerifiedConsumerCopy() {
        let now = Date()
        let snapshot = AttestationSnapshot(
            nonce: "nonce-1",
            signingAlgorithm: "ecdsa",
            model: "zai-org/GLM-5.1-FP8",
            coveredModelIDs: ["zai-org/GLM-5.1-FP8"],
            fetchedAt: now,
            chatGatewayAddress: "0xchat",
            cloudGatewayAddress: nil,
            modelAttestationCount: 1,
            prettyJSON: "{}"
        )
        let status = AttestationStatus(snapshot: snapshot, selectedModelID: "zai-org/GLM-5.1-FP8")
        let proof = ProofCapsuleViewModel(status: status, modelID: "zai-org/GLM-5.1-FP8", now: now)

        XCTAssertEqual(proof.state, .verified)
        XCTAssertEqual(proof.title, "Proof report checked")
        XCTAssertTrue(proof.badge.localizedCaseInsensitiveContains("proof"))
        XCTAssertTrue(proof.title.localizedCaseInsensitiveContains("proof"))
    }

    func testProofCapsuleDoesNotRenderUncoveredModelAsVerified() {
        let now = Date()
        let evidence = AttestationEvidence(
            verifiedAt: now,
            coveredModelIDs: ["private-covered-model"],
            routeName: "NEAR Private"
        )
        let status = AttestationStatus.valid(evidence)
        let proof = ProofCapsuleViewModel(status: status, modelID: "different-selected-model", now: now)

        XCTAssertEqual(proof.state, .mismatch)
        XCTAssertEqual(proof.title, "Model not covered")
        XCTAssertEqual(proof.badge, "Not covered")
        XCTAssertFalse(proof.title.localizedCaseInsensitiveContains("checked"))
    }

    func testProofIntegrityAdversarialMatrixOnlyCoveredFreshReportIsVerified() {
        let now = Date(timeIntervalSince1970: 1_750_000_000)
        let selectedModel = ModelOption.nearPrivateDefaultModelID
        let coveredEvidence = AttestationEvidence(
            verifiedAt: now.addingTimeInterval(-30),
            coveredModelIDs: [selectedModel],
            routeName: "NEAR Private",
            nonce: "nonce-covered",
            signingAlgorithm: "ed25519"
        )
        let staleEvidence = AttestationEvidence(
            verifiedAt: now.addingTimeInterval(-3_700),
            coveredModelIDs: [selectedModel],
            routeName: "NEAR Private"
        )
        let futureEvidence = AttestationEvidence(
            verifiedAt: now.addingTimeInterval(3_700),
            coveredModelIDs: [selectedModel],
            routeName: "NEAR Private"
        )
        let partialEvidence = AttestationEvidence(
            verifiedAt: now.addingTimeInterval(-30),
            coveredModelIDs: ["other-private-model", "backup-private-model"],
            routeName: "NEAR Private"
        )
        let variants: [(name: String, status: AttestationStatus, modelID: String?, shouldVerify: Bool)] = [
            ("valid-covered", .valid(coveredEvidence), selectedModel, true),
            ("model-not-covered", .valid(partialEvidence), selectedModel, false),
            ("stale-expired", .valid(staleEvidence), selectedModel, false),
            ("future-dated", .valid(futureEvidence), selectedModel, false),
            ("partial-coverage", .valid(partialEvidence), selectedModel, false),
            ("empty-coverage", .unavailable(reason: .modelCoverageUnavailable), selectedModel, false),
            ("nonce-mismatch", .mismatch(expectedModelID: selectedModel, evidence: coveredEvidence), selectedModel, false),
            ("missing-fields", .unknown, selectedModel, false),
            ("blank-selected-model", .valid(coveredEvidence), "", false)
        ]

        for variant in variants {
            let proof = ProofCapsuleViewModel(status: variant.status, modelID: variant.modelID, now: now)
            let copy = "\(proof.title) \(proof.badge) \(proof.detail)".lowercased()
            if variant.shouldVerify {
                XCTAssertEqual(proof.state, .verified, variant.name)
                XCTAssertTrue(copy.contains("proof"), variant.name)
            } else {
                XCTAssertNotEqual(proof.state, .verified, variant.name)
                XCTAssertFalse(copy.contains("checked"), variant.name)
                XCTAssertFalse(copy.contains("verified"), variant.name)
            }
        }
    }

    func testUnknownAttestationUsesNoLocalProofReportCopy() {
        let copy = AttestationStatus.unknown.userFacingCopy()
        let proof = ProofCapsuleViewModel(status: .unknown, modelID: "zai-org/GLM-5.1-FP8")

        XCTAssertEqual(copy.title, "No proof report on this device")
        XCTAssertEqual(copy.badge, "No report")
        XCTAssertEqual(proof.state, .unknown)
        XCTAssertEqual(proof.badge, "No report")
    }

    func testAttestationCopyExplainsExternalRoutes() {
        let copy = AttestationStatus.unavailable(reason: .routeNotSupported).userFacingCopy()

        XCTAssertEqual(copy.title, "Privacy proxy route")
        XCTAssertTrue(copy.detail.contains("NEAR Private proof report"))
        XCTAssertEqual(copy.badge, "Privacy proxy")
    }

    @MainActor
    func testAttestationCopySeparatesAgentRoutesFromPrivacyProxy() {
        let store = SecurityStore(attestationAPI: FakeSecurityAttestationAPI())

        let mobileStatus = store.currentAttestationStatus(
            selectedModelID: ModelOption.ironclawMobileModelID,
            selectedRouteKind: ChatRouteKind.ironclawMobile,
            isCouncilModeEnabled: false,
            activeCouncilHasExternalRoutes: false
        )
        let mobileCopy = mobileStatus.userFacingCopy()

        XCTAssertEqual(mobileCopy.title, "Agent route outside proof")
        XCTAssertTrue(mobileCopy.detail.contains("Agent trust boundary"))
        XCTAssertEqual(mobileCopy.badge, "Outside proof")

        let cloudCopy = store.currentAttestationStatus(
            selectedModelID: "zai-org/GLM-5.1-FP8",
            selectedRouteKind: ChatRouteKind.nearCloud,
            isCouncilModeEnabled: false,
            activeCouncilHasExternalRoutes: false
        ).userFacingCopy()

        XCTAssertEqual(cloudCopy.title, "Privacy proxy route")
        XCTAssertEqual(cloudCopy.badge, "Privacy proxy")
    }

    func testAttestationCopySeparatesServiceFailureFromMissingModelCoverage() {
        let serviceCopy = AttestationStatus.unavailable(reason: .serviceUnavailable).userFacingCopy()

        XCTAssertEqual(serviceCopy.title, "Proof service down")
        XCTAssertTrue(serviceCopy.detail.contains("network"))
        XCTAssertEqual(serviceCopy.badge, "Service down")

        let snapshot = AttestationSnapshot(
            nonce: "nonce-1",
            signingAlgorithm: "ecdsa",
            model: nil,
            fetchedAt: Date(),
            chatGatewayAddress: "0xchat",
            cloudGatewayAddress: nil,
            modelAttestationCount: 1,
            prettyJSON: "{}"
        )
        let missingCoverageCopy = AttestationStatus(
            snapshot: snapshot,
            selectedModelID: "zai-org/GLM-5.1-FP8"
        ).userFacingCopy()

        XCTAssertEqual(missingCoverageCopy.title, "Model proof unavailable")
        XCTAssertEqual(missingCoverageCopy.badge, "No model proof")
    }

    func testAttestationEducationDoesNotOverclaimTruthfulness() {
        let education = AttestationEducation.standard
        let allCopy = ([education.headline, education.summary] + education.sections.flatMap { [$0.title, $0.body] })
            .joined(separator: " ")
            .lowercased()

        XCTAssertTrue(allCopy.contains("how proof works"))
        XCTAssertTrue(allCopy.contains("can't confirm"))
        XCTAssertTrue(allCopy.contains("answer is true"))
        XCTAssertFalse(allCopy.contains("guarantees truth"))
        XCTAssertFalse(allCopy.contains("verifies truth"))
    }

    func testSignedTranscriptExportUsesMessageCapturedTrustMetadataOverCurrentContext() throws {
        let createdAt = Date(timeIntervalSince1970: 1_770_000_010)
        let capturedRoute = MessageRouteMetadata(
            modelID: ModelOption.nearCloudModelID(for: "qwen/qwen3.5-122b-a10b"),
            routeKind: .nearCloud,
            sourceMode: .web,
            webSearchEnabled: true,
            researchModeEnabled: false,
            projectContextIncluded: false,
            capturedAt: createdAt
        )
        let message = ChatMessage(
            id: "msg_captured_route",
            role: .assistant,
            text: "This answer was generated on the cloud route.",
            model: ChatStore.defaultModelID,
            createdAt: createdAt,
            status: "completed",
            responseID: "resp_captured_route",
            isStreaming: false,
            trustMetadata: MessageTrustMetadata(route: capturedRoute, proof: nil, capturedAt: createdAt)
        )
        let currentPrivateContext = SignedTranscriptExportContext(
            provider: "near-private",
            privacyRoute: "tee-private",
            sourceMode: "auto",
            webSearchEnabled: false,
            projectID: "current-project",
            ownerHash: nil,
            attestationSnapshot: nil
        )

        let data = try ConversationExportBuilder.signedTranscriptData(
            conversation: nil,
            messages: [message],
            context: currentPrivateContext,
            exportedAt: createdAt
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exportedMessages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let route = try XCTUnwrap(exportedMessages.first?["route"] as? [String: Any])
        let trust = try XCTUnwrap(exportedMessages.first?["trust"] as? [String: Any])
        let trustRoute = try XCTUnwrap(trust["route"] as? [String: Any])

        XCTAssertEqual(route["scope"] as? String, "message_captured")
        XCTAssertEqual(route["provider"] as? String, "near-cloud")
        XCTAssertEqual(route["privacy_route"] as? String, "external-cloud")
        XCTAssertEqual(route["source_mode"] as? String, "web")
        XCTAssertEqual(route["derived_from_model_id"] as? String, "near-cloud/qwen/qwen3.5-122b-a10b")
        XCTAssertNil(route["project_id_hash"])
        XCTAssertEqual(trustRoute["provider"] as? String, "near-cloud")
        XCTAssertEqual(trustRoute["web_search"] as? Bool, true)
    }

    func testURLSecurityRejectsLocalAndObfuscatedHosts() {
        XCTAssertTrue(URLSecurity.isPublicHost("private.near.ai"))
        XCTAssertFalse(URLSecurity.isPublicHost("localhost"))
        XCTAssertFalse(URLSecurity.isPublicHost("192.168.1.20"))
        XCTAssertFalse(URLSecurity.isPublicHost("0x7f000001"))
        XCTAssertFalse(URLSecurity.isPublicHost("0177.0.0.1"))
        XCTAssertFalse(URLSecurity.isPublicHost("::ffff:127.0.0.1"))

        XCTAssertNotNil(URLSecurity.normalizedPublicHTTPSURL(from: "github.com/nearai/ironclaw"))
        XCTAssertNil(URLSecurity.normalizedPublicHTTPSURL(from: "http://localhost:3000/status"))
    }

    func testURLSecurityRequiresPublicHTTPSForImportedAndSavedTargets() {
        XCTAssertTrue(URLSecurity.isPublicHTTPSURL(URL(string: "https://example.com/image.png")!))
        XCTAssertFalse(URLSecurity.isPublicHTTPSURL(URL(string: "http://example.com/image.png")!))
        XCTAssertFalse(URLSecurity.isPublicHTTPSURL(URL(string: "https://127.0.0.1/image.png")!))
        XCTAssertFalse(URLSecurity.isPublicHTTPSURL(URL(string: "https://[::ffff:127.0.0.1]/image.png")!))

        let normalized = URLSecurity.normalizedPublicHTTPSURL(from: "Example.com/path?q=1")
        XCTAssertEqual(normalized?.scheme, "https")
        XCTAssertEqual(normalized?.host, "Example.com")
        XCTAssertEqual(normalized?.path, "/path")
    }

    func testQuickIntentParsesDocumentPrivacy() {
        XCTAssertEqual(QuickIntentParser.parse("keep documents on device"), .setDocumentPrivacy(onDevice: true))
        XCTAssertEqual(QuickIntentParser.parse("don't upload my documents"), .setDocumentPrivacy(onDevice: true))
        XCTAssertEqual(QuickIntentParser.parse("upload documents normally"), .setDocumentPrivacy(onDevice: false))
    }


    @MainActor
    func testDocumentPrivacyToggleFlipsFlag() {
        let chatStore = ChatStore(api: PrivateChatAPI(configuration: .production))
        chatStore.keepDocumentsOnDevice = false
        chatStore.draft = "keep documents on device"
        chatStore.sendDraft()
        XCTAssertTrue(chatStore.keepDocumentsOnDevice)
        chatStore.draft = "upload documents normally"
        chatStore.sendDraft()
        XCTAssertFalse(chatStore.keepDocumentsOnDevice)
    }

    func testLocalDocExcerptsAllowedOnlyOnPrivateRoute() {
        // The privacy promise, as a pure predicate: on-device document text may
        // be inlined ONLY when every destination is the private near.ai route.
        let priv = ChatStore.defaultModelID                 // "zai-org/GLM-5.1-FP8"
        let priv2 = "deepseek-ai/DeepSeek-V3"
        let cloud = ModelOption.nearCloudModelID(for: "provider/current-model")
        let hosted = ModelOption.ironclawModelID
        // Single model.
        XCTAssertTrue(DocumentTextExtractor.localDocsAllowedForRoute(councilModelIDs: [], singleModelID: priv))
        XCTAssertFalse(DocumentTextExtractor.localDocsAllowedForRoute(councilModelIDs: [], singleModelID: cloud))
        XCTAssertFalse(DocumentTextExtractor.localDocsAllowedForRoute(councilModelIDs: [], singleModelID: hosted))
        // Council: all-private allowed; ANY cloud/hosted leg blocks.
        XCTAssertTrue(DocumentTextExtractor.localDocsAllowedForRoute(councilModelIDs: [priv, priv2], singleModelID: priv))
        XCTAssertFalse(DocumentTextExtractor.localDocsAllowedForRoute(councilModelIDs: [priv, cloud], singleModelID: priv))
        XCTAssertFalse(DocumentTextExtractor.localDocsAllowedForRoute(councilModelIDs: [priv, hosted], singleModelID: priv))
    }

    func testPrivacyBoundaryFuzzHonorsNoWebAndPrivateRouteOverrides() {
        let privateModel = ChatStore.defaultModelID
        let hostedPrompt = "please inspect the repo, run tests, and use the terminal"
        let privateHostedPrompt = "keep this private and do not use hosted; please inspect the repo and run tests"
        let privateHostedPromptWithObject = "Do not send this to hosted or cloud; inspect the repo and run tests."
        let noWebPrompts = [
            "Deep research the latest FDA recalls, no web, only this file.",
            "Use only this spreadsheet and do not browse.",
            "No internet: turn the attached file into actions.",
            "Do not go online; use only the attached file.",
            "Do not look up current FDA recalls; use this file only."
        ]

        for prompt in noWebPrompts {
            let override = RoutePlanner.promptSourcePrivacyOverride(for: prompt, hasAttachments: true)
            XCTAssertTrue(override.blocksWeb, prompt)
            XCTAssertTrue(override.prefersFileOnly || prompt.localizedCaseInsensitiveContains("no internet"), prompt)
            XCTAssertFalse(RoutePlanner.promptNeedsLiveWeb(prompt), prompt)
        }

        XCTAssertEqual(
            RoutePlanner.modelAfterHostedAutoRoute(
                selectedModelID: privateModel,
                text: hostedPrompt,
                hostedIronclawAvailable: true
            ),
            ModelOption.ironclawModelID
        )
        XCTAssertEqual(
            RoutePlanner.modelAfterHostedAutoRoute(
                selectedModelID: privateModel,
                text: privateHostedPrompt,
                hostedIronclawAvailable: true
            ),
            privateModel
        )
        XCTAssertEqual(
            RoutePlanner.modelAfterHostedAutoRoute(
                selectedModelID: privateModel,
                text: privateHostedPromptWithObject,
                hostedIronclawAvailable: true
            ),
            privateModel
        )
        XCTAssertTrue(RoutePlanner.promptSourcePrivacyOverride(for: privateHostedPrompt).requiresPrivateRoute)
        XCTAssertTrue(RoutePlanner.promptSourcePrivacyOverride(for: privateHostedPromptWithObject).requiresPrivateRoute)
    }
}

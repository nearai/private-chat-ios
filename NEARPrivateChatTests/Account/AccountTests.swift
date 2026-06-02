import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testSettingsPersistenceKeepsAccountScopedSettingsSeparate() throws {
        let defaults = try makeIsolatedDefaults()
        let first = SettingsPersistence(accountID: "acct-one", defaults: defaults)
        let second = SettingsPersistence(accountID: "acct-two", defaults: defaults)

        first.saveSelectedModelID("model-one")
        first.saveCouncilModelIDs(["model-one", "model-two"])
        first.savePinnedModelIDs(["model-two"])
        first.saveWebSearchEnabled(true)
        first.saveSourceMode(.web)
        first.saveResearchModeEnabled(true)
        first.saveLargeTextAsFileEnabled(false)

        XCTAssertEqual(first.loadSelectedModelID(), "model-one")
        XCTAssertEqual(first.loadCouncilModelIDs(), ["model-one", "model-two"])
        XCTAssertEqual(first.loadPinnedModelIDs(maxCount: 8), ["model-two"])
        XCTAssertTrue(first.loadWebSearchEnabled(default: false))
        XCTAssertEqual(first.loadSourceMode(default: .auto), .web)
        XCTAssertTrue(first.loadResearchModeEnabled())
        XCTAssertFalse(first.loadLargeTextAsFileEnabled(default: true))

        XCTAssertNil(second.loadSelectedModelID())
        XCTAssertTrue(second.loadCouncilModelIDs().isEmpty)
        XCTAssertFalse(second.loadWebSearchEnabled(default: false))
        XCTAssertEqual(second.loadSourceMode(default: .auto), .auto)
        XCTAssertTrue(second.loadLargeTextAsFileEnabled(default: true))
    }

    func testNearCloudModelListRequiresNonBlankAPIKeyBeforeNetwork() async {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)

        do {
            _ = try await api.fetchNearCloudModels(apiKey: "   \n\t")
            XCTFail("Expected whitespace-only Cloud keys to be rejected before a request is sent.")
        } catch APIError.status(let code, let message) {
            XCTAssertEqual(code, 401)
            XCTAssertTrue(message.contains("Connect NEAR AI Cloud"), message)
            XCTAssertFalse(message.contains("Missing Authorization header"), message)
        } catch {
            XCTFail("Expected Cloud auth status error, got \(error).")
        }
    }

    func testNearCloudChatCompletionRequiresNonBlankAPIKeyBeforeNetwork() async {
        let api = PrivateChatAPI(configuration: AppConfiguration.production)

        do {
            _ = try await api.fetchNearCloudChatCompletion(
                apiKey: "   \n\t",
                model: "qwen/qwen3.5-122b-a10b",
                prompt: "hello",
                systemPrompt: ""
            )
            XCTFail("Expected whitespace-only Cloud keys to be rejected before a request is sent.")
        } catch APIError.status(let code, let message) {
            XCTAssertEqual(code, 401)
            XCTAssertTrue(message.contains("Connect NEAR AI Cloud"), message)
            XCTAssertFalse(message.contains("Missing Authorization header"), message)
        } catch {
            XCTFail("Expected Cloud auth status error, got \(error).")
        }
    }

    func testNearCloudAPIKeyNormalizerAcceptsCopiedBearerHeader() {
        XCTAssertEqual(
            PrivateChatAPI.normalizedNearCloudAPIKey("Authorization: Bearer near-cloud-key-123 \n"),
            "near-cloud-key-123"
        )
        XCTAssertEqual(
            PrivateChatAPI.normalizedNearCloudAPIKey("Bearer near-cloud-key-123"),
            "near-cloud-key-123"
        )
    }

    func testStatusErrorsDoNotExposeRawAuthorizationHeaderFailures() {
        let missingHeader = APIError.status(401, "HTTP 401 — Missing authorization header").errorDescription ?? ""
        XCTAssertFalse(missingHeader.localizedCaseInsensitiveContains("Missing authorization header"))
        XCTAssertTrue(missingHeader.contains("Authentication is missing or expired"), missingHeader)

        let expired = APIError.status(401, "HTTP 401 — Invalid or expired authentication token").errorDescription ?? ""
        XCTAssertFalse(expired.localizedCaseInsensitiveContains("Invalid or expired authentication token"))
        XCTAssertTrue(expired.contains("Authentication is missing or expired"), expired)
    }

    func testCapabilityNextStepTreatsHostedIronclawAsSatisfiedAgentRoute() {
        let plan = AppSetupPlan(
            profile: UserSetupProfile(
                useCase: .buildAgents,
                contextStyle: .project,
                wantsWeb: false,
                wantsIronclaw: true,
                wantsCouncil: false,
                useCases: [.buildAgents],
                experienceMode: .power
            ),
            readiness: AppSetupReadinessSnapshot(
                modelCatalogLoaded: true,
                privateModelAvailable: true,
                defaultCouncilModelCount: 3,
                ironclawMobileAvailable: false,
                hostedIronclawAvailable: true,
                nearCloudKeyConfigured: false
            )
        )

        let recommendation = CapabilityNextStepPlanner.recommend(
            routeBlock: nil,
            setupPlan: plan,
            currentRoute: .ironclawHosted,
            hasFreshPrivateProof: true,
            hostedIronclawAvailable: true,
            autoCouncilReady: true
        )

        XCTAssertEqual(recommendation?.kind, .rerunSetup)
    }

    func testRouteReadinessBlocksNearCloudWithoutAPIKey() {
        let issue = RoutePlanner.routeReadinessIssue(
            selectedModelID: ModelOption.nearCloudModelID(for: "openai/gpt-5.5"),
            requestedCouncilModelIDs: [],
            isCouncilRequested: false,
            nearCloudKeyConfigured: false,
            hostedIronclawEndpointUsable: true
        )

        XCTAssertEqual(issue?.route, .nearCloud)
        XCTAssertEqual(issue?.recoveryAction, .addNearCloudKey)
        XCTAssertTrue(issue?.message.contains("draft and attachments are kept") == true)
    }

    func testCapabilityNextStepPrioritizesBlockedCloudRoute() {
        let nextStep = CapabilityNextStepPlanner.recommend(
            routeBlock: .nearCloudKeyRequired,
            setupPlan: AppSetupPlan(profile: .defaults, readiness: .optimistic),
            currentRoute: .nearCloud,
            hasFreshPrivateProof: false,
            hostedIronclawAvailable: false,
            autoCouncilReady: true
        )

        XCTAssertEqual(nextStep?.kind, .openCloud)
        XCTAssertEqual(nextStep?.actionTitle, "Connect Cloud")
    }

    func testCapabilityNextStepKeepsHostedAgentOutOfDefaultPhoneFlow() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .buildAgents
        profile.useCases = [.buildAgents]
        profile.wantsIronclaw = true
        profile.wantsCouncil = false
        let plan = AppSetupPlan(profile: profile, readiness: .optimistic)

        let nextStep = CapabilityNextStepPlanner.recommend(
            routeBlock: nil,
            setupPlan: plan,
            currentRoute: .ironclawMobile,
            hasFreshPrivateProof: false,
            hostedIronclawAvailable: false,
            autoCouncilReady: true
        )

        XCTAssertEqual(nextStep?.kind, .rerunSetup)
        XCTAssertEqual(nextStep?.actionTitle, "Rerun Setup")
    }

    func testCapabilityNextStepSuggestsAutoCouncilForResearchDefaults() {
        var profile = UserSetupProfile.defaults
        profile.useCase = .research
        profile.useCases = [.research]
        profile.wantsCouncil = true
        profile.wantsIronclaw = false
        let plan = AppSetupPlan(profile: profile, readiness: .optimistic)

        let nextStep = CapabilityNextStepPlanner.recommend(
            routeBlock: nil,
            setupPlan: plan,
            currentRoute: .nearPrivate,
            hasFreshPrivateProof: true,
            hostedIronclawAvailable: true,
            autoCouncilReady: true
        )

        XCTAssertEqual(nextStep?.kind, .useAutoCouncil)
        XCTAssertEqual(nextStep?.actionTitle, "Use recommended Council")
    }

    func testCapabilityNextStepSuggestsProofReportWhenPrivateProofIsMissing() {
        let nextStep = CapabilityNextStepPlanner.recommend(
            routeBlock: nil,
            setupPlan: AppSetupPlan(profile: .defaults, readiness: .optimistic),
            currentRoute: .nearPrivate,
            hasFreshPrivateProof: false,
            hostedIronclawAvailable: true,
            autoCouncilReady: false
        )

        XCTAssertEqual(nextStep?.kind, .openSecurity)
        XCTAssertEqual(nextStep?.actionTitle, "Open Proof report")
    }

    func testAccountSettingsDeepLinkMapsCapabilityRecommendations() {
        XCTAssertEqual(AccountSettingsDeepLink(capabilityNextStepKind: .openCloud), .nearCloudKeys)
        XCTAssertEqual(AccountSettingsDeepLink(capabilityNextStepKind: .openAgent), .ironclawAgent)
        XCTAssertNil(AccountSettingsDeepLink(capabilityNextStepKind: .useAutoCouncil))
        XCTAssertNil(AccountSettingsDeepLink(capabilityNextStepKind: .openSecurity))
    }

    func testUserSetupStorageIsAccountScoped() throws {
        let defaults = try makeIsolatedDefaults()
        let accountA = "user:account-a"
        let accountB = "user:account-b"
        var researchProfile = UserSetupProfile.defaults
        researchProfile.useCase = .research
        researchProfile.contextStyle = .project
        researchProfile.wantsCouncil = true

        UserSetupStorage.save(researchProfile, for: accountA, defaults: defaults)

        XCTAssertTrue(UserSetupStorage.isCompleted(for: accountA, defaults: defaults))
        XCTAssertFalse(UserSetupStorage.isCompleted(for: accountB, defaults: defaults))
        XCTAssertEqual(UserSetupStorage.load(for: accountA, defaults: defaults), researchProfile)
        XCTAssertNil(UserSetupStorage.load(for: accountB, defaults: defaults))
        XCTAssertTrue(UserSetupStorage.hasPendingLaunchCard(for: accountA, defaults: defaults))
        XCTAssertFalse(UserSetupStorage.hasPendingLaunchCard(for: accountB, defaults: defaults))
    }

    func testUserSetupNeedsFirstRunSetupOnlyForBrandNewAccounts() throws {
        let defaults = try makeIsolatedDefaults()
        let accountID = "user:first-run-setup"

        XCTAssertTrue(UserSetupStorage.needsFirstRunSetup(for: accountID, defaults: defaults))

        UserSetupStorage.saveWithoutPendingLaunchCard(.defaults, for: accountID, defaults: defaults)
        XCTAssertFalse(UserSetupStorage.needsFirstRunSetup(for: accountID, defaults: defaults))

        UserSetupStorage.clearCompletion(for: accountID, defaults: defaults)
        XCTAssertFalse(UserSetupStorage.needsFirstRunSetup(for: accountID, defaults: defaults))
    }

    func testFirstRunCapabilityRecommendationPromptsHostedAgentSetupWhenAgentPresetFallsBack() {
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
            routeDefaults: SetupRouteDefaults(
                privateModelID: "private-model",
                councilModelIDs: ["council-a", "council-b"],
                ironclawMobileModelID: ModelOption.ironclawMobileModelID
            )
        )

        let recommendation = plan.firstRunCapabilityRecommendation(readiness: readiness)

        XCTAssertEqual(recommendation?.title, "Finish Agent setup")
        XCTAssertEqual(recommendation?.actionTitle, "Connect Agent")
        XCTAssertEqual(recommendation?.kind, .openAgent)
    }

    func testFirstRunCapabilityRecommendationPromptsCloudSetupWhenResearchPresetLacksCouncilModels() {
        let readiness = AppSetupReadinessSnapshot(
            modelCatalogLoaded: true,
            privateModelAvailable: true,
            defaultCouncilModelCount: 1,
            ironclawMobileAvailable: true,
            hostedIronclawAvailable: false,
            nearCloudKeyConfigured: false
        )
        let plan = UserSetupStarterPreset.researchBrief.previewPlan(
            readiness: readiness,
            routeDefaults: SetupRouteDefaults(
                privateModelID: "private-model",
                councilModelIDs: ["council-a"],
                ironclawMobileModelID: ModelOption.ironclawMobileModelID
            )
        )

        let recommendation = plan.firstRunCapabilityRecommendation(readiness: readiness)

        XCTAssertEqual(plan.modelRoute, .privateModel)
        XCTAssertEqual(recommendation?.title, "Unlock a fuller council")
        XCTAssertEqual(recommendation?.actionTitle, "Connect Cloud")
        XCTAssertEqual(recommendation?.kind, .openCloud)
    }

    func testFirstRunCapabilityRecommendationStaysQuietWhenResearchPresetAlreadyHasCloudButNeedsMoreModels() {
        let readiness = AppSetupReadinessSnapshot(
            modelCatalogLoaded: true,
            privateModelAvailable: true,
            defaultCouncilModelCount: 1,
            ironclawMobileAvailable: true,
            hostedIronclawAvailable: false,
            nearCloudKeyConfigured: true
        )
        let plan = UserSetupStarterPreset.researchBrief.previewPlan(
            readiness: readiness,
            routeDefaults: SetupRouteDefaults(
                privateModelID: "private-model",
                councilModelIDs: ["council-a"],
                ironclawMobileModelID: ModelOption.ironclawMobileModelID
            )
        )

        XCTAssertNil(plan.firstRunCapabilityRecommendation(readiness: readiness))
    }

    func testFirstRunCapabilityRecommendationPointsToHostedAgentWhenAvailable() {
        let readiness = AppSetupReadinessSnapshot(
            modelCatalogLoaded: true,
            privateModelAvailable: true,
            defaultCouncilModelCount: 3,
            ironclawMobileAvailable: false,
            hostedIronclawAvailable: true,
            nearCloudKeyConfigured: false
        )
        let plan = UserSetupStarterPreset.agentMission.previewPlan(
            readiness: readiness,
            routeDefaults: SetupRouteDefaults(
                privateModelID: "private-model",
                councilModelIDs: ["council-a", "council-b"],
                ironclawMobileModelID: ModelOption.ironclawMobileModelID
            )
        )

        let recommendation = plan.firstRunCapabilityRecommendation(readiness: readiness)

        XCTAssertEqual(recommendation?.title, "Hosted agent is available")
        XCTAssertEqual(recommendation?.actionTitle, "Open Agent")
        XCTAssertEqual(recommendation?.kind, .openAgent)
    }

    func testFirstRunCapabilityRecommendationStaysQuietWhenPresetRouteIsReady() {
        let plan = UserSetupStarterPreset.researchBrief.previewPlan(
            readiness: .optimistic,
            routeDefaults: SetupRouteDefaults(
                privateModelID: "private-model",
                councilModelIDs: ["council-a", "council-b"],
                ironclawMobileModelID: ModelOption.ironclawMobileModelID
            )
        )

        XCTAssertNil(plan.firstRunCapabilityRecommendation(readiness: .optimistic))
    }

    func testUserSetupStorageMigratesFallbackToUserAccount() throws {
        let defaults = try makeIsolatedDefaults()
        let fallbackAccount = UserSetupStorage.accountID(userID: nil, sessionID: "session-1", token: nil)!
        let userAccount = UserSetupStorage.accountID(userID: "user-1", sessionID: "session-1", token: nil)!
        var agentProfile = UserSetupProfile.defaults
        agentProfile.useCase = .buildAgents
        agentProfile.wantsIronclaw = true

        UserSetupStorage.save(agentProfile, for: fallbackAccount, defaults: defaults)
        UserSetupStorage.migrate(from: fallbackAccount, to: userAccount, defaults: defaults)

        XCTAssertTrue(UserSetupStorage.isCompleted(for: userAccount, defaults: defaults))
        XCTAssertEqual(UserSetupStorage.load(for: userAccount, defaults: defaults), agentProfile)
        XCTAssertTrue(UserSetupStorage.hasPendingLaunchCard(for: userAccount, defaults: defaults))
        XCTAssertFalse(UserSetupStorage.hasPendingLaunchCard(for: fallbackAccount, defaults: defaults))
    }

    func testLegalTermsAcceptanceIsPendingThenAccountScoped() throws {
        let defaults = try makeIsolatedDefaults()
        let accountA = "user:account-a"
        let accountB = "user:account-b"

        XCTAssertFalse(LegalTermsAcceptanceStore.hasPendingCurrentVersion(defaults: defaults))
        XCTAssertFalse(LegalTermsAcceptanceStore.hasAcceptedCurrentVersion(for: accountA, defaults: defaults))

        LegalTermsAcceptanceStore.recordPendingAcceptance(defaults: defaults, now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertTrue(LegalTermsAcceptanceStore.hasPendingCurrentVersion(defaults: defaults))
        XCTAssertTrue(LegalTermsAcceptanceStore.consumePendingAcceptance(for: accountA, defaults: defaults))
        XCTAssertFalse(LegalTermsAcceptanceStore.hasPendingCurrentVersion(defaults: defaults))
        XCTAssertTrue(LegalTermsAcceptanceStore.hasAcceptedCurrentVersion(for: accountA, defaults: defaults))
        XCTAssertFalse(LegalTermsAcceptanceStore.hasAcceptedCurrentVersion(for: accountB, defaults: defaults))
    }

    func testLegalTermsAcceptanceMigratesFallbackAccount() throws {
        let defaults = try makeIsolatedDefaults()
        let fallbackAccount = "token:fallback"
        let userAccount = "user:account-a"

        LegalTermsAcceptanceStore.acceptCurrentVersion(for: fallbackAccount, defaults: defaults, now: Date(timeIntervalSince1970: 1_700_000_000))
        LegalTermsAcceptanceStore.migrate(from: fallbackAccount, to: userAccount, defaults: defaults)

        XCTAssertTrue(LegalTermsAcceptanceStore.hasAcceptedCurrentVersion(for: userAccount, defaults: defaults))
    }

    func testModelOptionCapabilitySignalsDrivePickerFilters() {
        let coderVision = ModelOption(
            modelID: "Qwen/Qwen3-VL-Coder",
            publicModel: true,
            metadata: ModelOption.Metadata(
                verifiable: true,
                contextLength: 1_000_000,
                modelDisplayName: "Qwen Coder Vision",
                modelDescription: "A multimodal coding model for repo and image work.",
                modelIcon: nil,
                aliases: ["vision", "coder"]
            )
        )

        XCTAssertTrue(coderVision.isCodeModel)
        XCTAssertTrue(coderVision.isVisionModel)
        XCTAssertTrue(coderVision.isLongContextModel)
        XCTAssertTrue(coderVision.capabilityBadges.contains("Code"))
        XCTAssertTrue(coderVision.capabilityBadges.contains("Vision"))
        XCTAssertTrue(coderVision.capabilityBadges.contains("1M ctx"))
    }

    func testNearCloudFallbackModelsStayDiscoverableForModelPicker() {
        let qwen = ModelOption(modelID: ModelOption.nearCloudModelID(for: "qwen/qwen3.7-max"), publicModel: true, metadata: nil)
        let opus = ModelOption(modelID: ModelOption.nearCloudModelID(for: "anthropic/claude-opus-4-7"), publicModel: true, metadata: nil)
        let gpt = ModelOption(modelID: ModelOption.nearCloudModelID(for: "openai/gpt-5.5"), publicModel: true, metadata: nil)
        let flash = ModelOption(modelID: ModelOption.nearCloudModelID(for: "google/gemini-3.5-flash"), publicModel: true, metadata: nil)
        let oss = ModelOption(modelID: ModelOption.nearCloudModelID(for: "openai/gpt-oss-120b"), publicModel: true, metadata: nil)

        XCTAssertEqual(qwen.nearCloudUnderlyingModelID, "qwen/qwen3.7-max")
        XCTAssertEqual(opus.nearCloudUnderlyingModelID, "anthropic/claude-opus-4-7")
        XCTAssertEqual(gpt.nearCloudUnderlyingModelID, "openai/gpt-5.5")
        XCTAssertEqual(flash.nearCloudUnderlyingModelID, "google/gemini-3.5-flash")
        XCTAssertEqual(oss.nearCloudUnderlyingModelID, "openai/gpt-oss-120b")
        XCTAssertTrue([qwen, opus, gpt, flash, oss].allSatisfy(\.isNearCloudModel))
    }

    func testNearCloudFallbackCopyUsesGenericDisplayNames() {
        let fallback = ModelCatalogStore.fallbackNearCloudModels()

        XCTAssertTrue(fallback.isEmpty)
    }

    func testSourceRoutingSemanticsNearCloudUsesAppGroundingWithoutNativeTools() {
        let cloudAuto = RoutePlanner.sourceRoutingSemantics(
            sourceMode: .auto,
            researchModeEnabled: false,
            webSearchEnabled: false,
            route: .nearCloud
        )
        XCTAssertEqual(cloudAuto.modelNativeWebToolPolicy, .never)
        XCTAssertEqual(cloudAuto.appWebGroundingPolicy, .never)
        XCTAssertTrue(cloudAuto.attachesSavedLinkSourcePack)
        XCTAssertTrue(cloudAuto.attachesProjectFileSourcePack)

        let cloudWeb = RoutePlanner.sourceRoutingSemantics(
            sourceMode: .web,
            researchModeEnabled: false,
            webSearchEnabled: true,
            route: .nearCloud
        )
        XCTAssertEqual(cloudWeb.modelNativeWebToolPolicy, .never)
        XCTAssertEqual(cloudWeb.appWebGroundingPolicy, .always)
        XCTAssertFalse(cloudWeb.attachesSavedLinkSourcePack)
        XCTAssertFalse(cloudWeb.attachesProjectFileSourcePack)
        XCTAssertTrue(cloudWeb.attachesPromptFiles)

        let cloudLinks = RoutePlanner.sourceRoutingSemantics(
            sourceMode: .links,
            researchModeEnabled: false,
            webSearchEnabled: true,
            route: .nearCloud
        )
        XCTAssertEqual(cloudLinks.modelNativeWebToolPolicy, .never)
        XCTAssertEqual(cloudLinks.appWebGroundingPolicy, .whenFreshRequested)
        XCTAssertTrue(cloudLinks.attachesSavedLinkSourcePack)
        XCTAssertFalse(cloudLinks.attachesProjectFileSourcePack)

        let cloudFilesWithoutWeb = RoutePlanner.sourceRoutingSemantics(
            sourceMode: .files,
            researchModeEnabled: false,
            webSearchEnabled: false,
            route: .nearCloud
        )
        XCTAssertEqual(cloudFilesWithoutWeb.modelNativeWebToolPolicy, .never)
        XCTAssertEqual(cloudFilesWithoutWeb.appWebGroundingPolicy, .never)
    }

    func testAskOrchestratorKeepsNearCloudWithProjectAndWebContextWhenKeyExists() {
        let decision = AskOrchestrator.decide(
            AskOrchestrator.Input(
                prompt: "Use the project files and latest web context to compare options",
                selectedRoute: .nearCloud,
                hasProjectContext: true,
                hasPromptAttachments: false,
                nearCloudKeyConfigured: true,
                hostedAgentAvailable: false,
                councilAvailable: false,
                councilActive: false
            )
        )

        XCTAssertEqual(decision.route, .nearCloud)
        XCTAssertEqual(decision.proofState, .proxied)
        XCTAssertTrue(decision.tools.contains(.projectFiles))
        XCTAssertTrue(decision.tools.contains(.web))
        XCTAssertEqual(decision.failurePlan, .none)
    }

    func testNearCloudModelIDsPreserveUnderlyingCloudModel() {
        let model = ModelOption(
            modelID: ModelOption.nearCloudModelID(for: "moonshotai/kimi-k2.6"),
            publicModel: true,
            metadata: ModelOption.Metadata(
                verifiable: false,
                contextLength: 200_000,
                modelDisplayName: "Kimi K2.6",
                modelDescription: "Cloud model",
                modelIcon: nil,
                aliases: ["kimi-k2.6"]
            )
        )

        XCTAssertTrue(model.isNearCloudModel)
        XCTAssertEqual(model.nearCloudUnderlyingModelID, "moonshotai/kimi-k2.6")
        XCTAssertEqual(model.displayName, "Kimi K2.6")
        XCTAssertFalse(model.isVerifiable)
    }

    func testNearCloudModelIDsCoverExpectedFrontierDefaults() {
        let expectedCloudIDs = [
            "anthropic/claude-opus-4-7",
            "openai/gpt-5.5",
            "qwen/qwen3.7-max",
            "moonshotai/kimi-k2.6",
            "google/gemini-3.5-flash",
            "openai/gpt-oss-120b"
        ]
        let routeIDs = expectedCloudIDs.map(ModelOption.nearCloudModelID)

        XCTAssertEqual(routeIDs, [
            "near-cloud/anthropic/claude-opus-4-7",
            "near-cloud/openai/gpt-5.5",
            "near-cloud/qwen/qwen3.7-max",
            "near-cloud/moonshotai/kimi-k2.6",
            "near-cloud/google/gemini-3.5-flash",
            "near-cloud/openai/gpt-oss-120b"
        ])
        XCTAssertEqual(
            ModelOption(modelID: ModelOption.nearCloudModelID(for: "provider/current-model"), publicModel: true, metadata: nil).nearCloudUnderlyingModelID,
            "provider/current-model"
        )
        XCTAssertEqual(ModelOption.nearCloudModelID(for: " openai/gpt-5.5 "), "near-cloud/openai/gpt-5.5")
    }

    func testSignedTranscriptExportDerivesNearCloudRouteFromMessageModel() throws {
        let createdAt = Date(timeIntervalSince1970: 1_770_000_020)
        let conversation = ConversationSummary(
            id: "conv_signed_cloud_test",
            createdAt: createdAt.timeIntervalSince1970,
            metadata: ConversationMetadata(title: "Signed Cloud Test")
        )
        let messages = [
            makeMessage(id: "msg_user_cloud", role: .user, text: "Use cloud.", createdAt: createdAt),
            makeMessage(
                id: "msg_assistant_cloud",
                role: .assistant,
                text: "This came from cloud.",
                model: "near-cloud/anthropic/claude-opus-4-7",
                createdAt: createdAt.addingTimeInterval(1)
            )
        ]
        let currentPrivateContext = SignedTranscriptExportContext(
            provider: "near-private",
            privacyRoute: "tee-private",
            sourceMode: "auto",
            webSearchEnabled: false,
            projectID: nil,
            ownerHash: nil,
            attestationSnapshot: nil
        )

        let data = try ConversationExportBuilder.signedTranscriptData(
            conversation: conversation,
            messages: messages,
            context: currentPrivateContext,
            exportedAt: createdAt
        )
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exportedMessages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let assistantRoute = try XCTUnwrap(exportedMessages[1]["route"] as? [String: Any])

        XCTAssertEqual(assistantRoute["provider"] as? String, "near-cloud")
        XCTAssertEqual(assistantRoute["privacy_route"] as? String, "external-cloud")
        XCTAssertEqual(assistantRoute["derived_from_model_id"] as? String, "near-cloud/anthropic/claude-opus-4-7")
    }

    func testBriefingRoundTripsKindAndAccount() throws {
        let original = Briefing(
            title: "My NEAR",
            prompt: "How is my NEAR account doing?",
            schedule: .daily(hour: 8, minute: 0),
            kind: .nearAccount,
            accountID: "abhishek.near"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Briefing.self, from: data)
        XCTAssertEqual(decoded.kind, .nearAccount)
        XCTAssertEqual(decoded.accountID, "abhishek.near")
        XCTAssertEqual(decoded.id, original.id)
    }

    func testQuickIntentParsesAccountAndNews() {
        XCTAssertEqual(
            QuickIntentParser.parse("how is my near.com account doing"),
            .nearAccount(account: nil)
        )
        XCTAssertEqual(
            QuickIntentParser.parse("how is abhishek.near doing"),
            .nearAccount(account: "abhishek.near")
        )
        XCTAssertEqual(QuickIntentParser.parse("pull the daily news"), .news)
    }

    func testQuickIntentParsesCapabilities() {
        XCTAssertEqual(QuickIntentParser.parse("what can you do"), .capabilities)
        XCTAssertEqual(QuickIntentParser.parse("What can you do?"), .capabilities)
        XCTAssertEqual(QuickIntentParser.parse("help"), .capabilities)
        XCTAssertEqual(QuickIntentParser.parse("what are your features"), .capabilities)
        // Exact-match only: requests for help with a task stay model questions.
        XCTAssertNil(QuickIntentParser.parse("help me write an email"))
        XCTAssertNil(QuickIntentParser.parse("what can you help me with my taxes"))
        let text = QuickIntentParser.capabilitiesText()
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("Chat about anything"))
        XCTAssertTrue(text.contains("Write a concise client follow-up email"))
        XCTAssertTrue(text.contains("Summarize this PDF"))
        XCTAssertTrue(text.contains("Model-routed live questions"))
        XCTAssertFalse(text.contains("What’s trending in crypto"))
        XCTAssertLessThan(
            text.range(of: "Write a concise")?.lowerBound ?? text.endIndex,
            text.range(of: "ETH")?.lowerBound ?? text.endIndex
        )
        // Card stays accurate as features land.
        XCTAssertTrue(text.contains("Remind"))
        XCTAssertTrue(text.contains("18%"))         // calculator
        XCTAssertTrue(text.contains("days until"))  // date math
    }

    func testBriefingBuilderPlannerAsksForNearAccountThenCompletesDraft() {
        let first = BriefingBuilderPlanner.plan(
            from: "set up a daily briefing for my near account every weekday at 7am"
        )

        XCTAssertEqual(first.draft.kind, .nearAccount)
        XCTAssertNil(first.draft.accountID)
        XCTAssertEqual(first.draft.schedule, .weekdays(hour: 7, minute: 0))
        XCTAssertTrue(first.reply.lowercased().contains("account id"))

        let completed = BriefingBuilderPlanner.plan(from: "abhishek.near", current: first.draft)

        XCTAssertEqual(completed.draft.kind, .customPrompt)
        XCTAssertNil(completed.draft.accountID)
        XCTAssertTrue(completed.draft.prompt.contains("Track NEAR account abhishek.near."))
        XCTAssertTrue(completed.draft.prompt.contains("Run this recurring workflow through chat"))
        XCTAssertTrue(completed.reply.contains("Weekdays"))
    }

    func testQuickIntentCreatesAccountTrackerWithExplicitID() throws {
        let intent = QuickIntentParser.parse(
            "set up a daily tracker for abhishek.near every weekday at 7am"
        )
        guard case let .createTracker(spec) = intent else {
            return XCTFail("Expected a createTracker intent, got \(String(describing: intent)).")
        }
        XCTAssertEqual(spec.kind, .nearAccount)
        XCTAssertEqual(spec.subject, "abhishek.near")
        XCTAssertEqual(spec.schedule, .weekdays(hour: 7, minute: 0))
    }

    func testAccountIntentIsMainnetOnly() {
        // .testnet ids can't be served by the mainnet-only widget → don't capture
        // them (avoids a misleading "not found on mainnet"); let the model field it.
        XCTAssertNil(QuickIntentParser.extractAccount(from: "how is alice.testnet doing"))
        XCTAssertNil(QuickIntentParser.parse("how is alice.testnet doing"))
        XCTAssertEqual(QuickIntentParser.extractAccount(from: "how is abhishek.near doing"), "abhishek.near")
        XCTAssertEqual(QuickIntentParser.parse("how is abhishek.near doing"), .nearAccount(account: "abhishek.near"))
    }

    func testTestnetWithAccountKeywordsFallsThroughToModel() {
        // Regression: a .testnet id plus account keywords must NOT ask for a
        // .near account — the mainnet-only widget can't serve it.
        XCTAssertNil(QuickIntentParser.parse("check alice.testnet near account balance"))
        // A mainnet id with keywords still resolves.
        XCTAssertEqual(QuickIntentParser.parse("how is my near account doing root.near"), .nearAccount(account: "root.near"))
    }

    func testQuickIntentIgnoresLooseAccountAndPricePhrases() {
        // "my account" alone and a bare "?" used to swallow these.
        XCTAssertNil(QuickIntentParser.parse("how do I delete my account?"))
        XCTAssertNil(QuickIntentParser.parse("can you explain ethereum?"))
    }


    @MainActor
    func testSendDraftNearAccountWithoutIDAsksForAccount() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        store.draft = "how is my near account doing"

        store.sendDraft()

        XCTAssertEqual(store.draft, "")
        XCTAssertFalse(store.isStreaming)
        XCTAssertEqual(store.messages.count, 2)
        XCTAssertEqual(store.messages.last?.role, .assistant)
        XCTAssertTrue(store.messages.last?.text.lowercased().contains("near account") == true)
    }


    @MainActor
    func testSendDraftCompletesPendingNearAccountTracker() throws {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        var created: Briefing?
        store.onCreateTracker = { created = $0 }

        store.draft = "set up a daily briefing for my near account every weekday at 7am"
        store.sendDraft()

        XCTAssertNil(created)
        XCTAssertFalse(store.isStreaming)
        XCTAssertTrue(store.messages.last?.text.lowercased().contains("which near account") == true)

        store.draft = "root.near"
        store.sendDraft()

        let briefing = try XCTUnwrap(created)
        XCTAssertEqual(briefing.kind, .nearAccount)
        XCTAssertEqual(briefing.accountID, "root.near")
        XCTAssertEqual(briefing.schedule, .weekdays(hour: 7, minute: 0))
        XCTAssertTrue(store.messages.last?.text.contains("Created a tracker") == true)
    }


    @MainActor
    func testSendDraftClearsPendingNearAccountTrackerOnUnrelatedTurn() {
        let store = ChatStore(api: PrivateChatAPI(configuration: .production))
        var created: Briefing?
        store.onCreateTracker = { created = $0 }

        store.draft = "set up a daily briefing for my near account every weekday at 7am"
        store.sendDraft()
        XCTAssertNil(created)

        store.draft = "write me a haiku about the sea"
        store.sendDraft()
        XCTAssertNil(created)

        store.draft = "root.near"
        store.sendDraft()

        XCTAssertNil(created)
        XCTAssertFalse(store.messages.contains { $0.text.contains("Created a tracker") })
    }

    func testEmptyChatStarterPlannerCoversHostileTrialCapabilities() {
        let suggestions = EmptyChatStarterPlanner.suggestions(
            projectName: nil,
            isCouncilModeEnabled: false,
            councilAvailable: true,
            routeKind: .nearPrivate,
            agentAvailable: true
        )

        XCTAssertEqual(
            suggestions.map(\.title),
            [
                "Next actions",
                "Draft trackers",
                "Web research",
                "Files to actions",
                "Sources & proof",
                "Handoff to Agent"
            ]
        )
        XCTAssertEqual(suggestions.last?.action, .agent)
        XCTAssertTrue(suggestions[4].prompt.contains("NEAR Private route can prove"))
    }

    func testEmptyChatStarterPlannerAdaptsTrustCopyForNearCloudProjects() {
        let suggestions = EmptyChatStarterPlanner.suggestions(
            projectName: "Alpha",
            isCouncilModeEnabled: false,
            councilAvailable: true,
            routeKind: .nearCloud,
            agentAvailable: false
        )

        XCTAssertEqual(
            suggestions.map(\.title),
            [
                "Brief project",
                "Context to actions",
                "Draft trackers",
                "Sources & proof",
                "Review with Council"
            ]
        )
        XCTAssertEqual(suggestions[3].action, .trust)
        XCTAssertTrue(suggestions[3].prompt.contains("carries no NEAR Private proof"))
        XCTAssertTrue(suggestions[3].prompt.contains("Alpha"))
    }
}

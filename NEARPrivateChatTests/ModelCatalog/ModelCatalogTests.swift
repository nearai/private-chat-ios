import XCTest
import SwiftUI
import UserNotifications
import CoreSpotlight
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testModelCatalogStoreBuildsPickerAndPinnedModelsWithoutChatStore() {
        let glm = ModelOption(modelID: ModelOption.nearPrivateDefaultModelID, publicModel: true, metadata: nil)
        let qwen = ModelOption(modelID: "Qwen/Qwen3.5-122B-A10B", publicModel: true, metadata: nil)
        let utility = ModelOption(modelID: "embedding-model", publicModel: true, metadata: nil)
        let cloud = ModelOption(
            modelID: ModelOption.nearCloudModelID(for: "provider/current-model"),
            publicModel: true,
            metadata: ModelOption.Metadata(
                verifiable: false,
                contextLength: nil,
                modelDisplayName: "Provider model",
                modelDescription: "Catalog-returned cloud route.",
                modelIcon: nil,
                aliases: []
            )
        )
        let catalog = ModelCatalogStore(
            models: [utility, qwen, glm],
            nearCloudModels: [cloud],
            allowedModelIDs: nil,
            preferredModelIDs: [ModelOption.nearPrivateDefaultModelID, "Qwen/Qwen3.5-122B-A10B"],
            nearCloudPreferredModelIDs: [cloud.id]
        )

        let rankedPrivateModels = catalog.rankedModels(from: catalog.pickerModels.filter { !$0.isExternalModel })
        XCTAssertEqual(rankedPrivateModels.first?.id, ModelOption.nearPrivateDefaultModelID)
        XCTAssertFalse(catalog.pickerModels.contains { $0.id == "embedding-model" })
        XCTAssertTrue(catalog.cloudRouteModels.contains { $0.id == cloud.id })
        XCTAssertEqual(catalog.pinnedPickerModels(from: ["Qwen/Qwen3.5-122B-A10B"]).map(\.id), ["Qwen/Qwen3.5-122B-A10B"])
    }

    func testModelCatalogStoreOwnsSelectionPinningAndCouncilLineupWithoutChatStore() {
        let catalog = ModelCatalogStore(
            models: [
                ModelOption(modelID: ModelOption.nearPrivateDefaultModelID, publicModel: true, metadata: nil),
                ModelOption(modelID: "Qwen/Qwen3.5-122B-A10B", publicModel: true, metadata: nil),
                ModelOption(modelID: "moonshotai/Kimi-K2-Instruct", publicModel: true, metadata: nil)
            ],
            preferredModelIDs: [
                ModelOption.nearPrivateDefaultModelID,
                "Qwen/Qwen3.5-122B-A10B",
                "moonshotai/Kimi-K2-Instruct"
            ]
        )

        XCTAssertTrue(catalog.selectModel("Qwen/Qwen3.5-122B-A10B"))
        XCTAssertEqual(catalog.selectedModel, "Qwen/Qwen3.5-122B-A10B")
        XCTAssertEqual(catalog.councilModelIDs, ["Qwen/Qwen3.5-122B-A10B"])

        catalog.togglePinnedModel("moonshotai/Kimi-K2-Instruct")
        XCTAssertEqual(catalog.pinnedModelIDs, ["moonshotai/Kimi-K2-Instruct"])

        catalog.useDefaultCouncilLineup()
        XCTAssertTrue(catalog.isCouncilModeEnabled)
        XCTAssertEqual(Array(catalog.activeCouncilModels.map(\.id).prefix(2)), [
            ModelOption.nearPrivateDefaultModelID,
            "Qwen/Qwen3.5-122B-A10B"
        ])
    }

    func testModelCatalogStoreRefreshOwnsPrivateAndCloudCatalogApplication() async throws {
        let privateModel = ModelOption(modelID: ModelOption.nearPrivateDefaultModelID, publicModel: true, metadata: nil)
        let cloudModel = ModelOption(
            modelID: "provider/current-model",
            publicModel: true,
            metadata: ModelOption.Metadata(
                verifiable: false,
                contextLength: 128_000,
                modelDisplayName: "Current Cloud Model",
                modelDescription: "Current account model.",
                modelIcon: nil,
                aliases: []
            )
        )
        let api = ModelCatalogFakeAPI(privateModels: [privateModel], cloudModels: [cloudModel])
        let catalog = ModelCatalogStore()

        try await catalog.refreshModels(
            modelAPI: api,
            loadCloudCatalog: true,
            nearCloudAPIKey: "near-cloud-key"
        )

        XCTAssertEqual(catalog.models.map(\.id), [ModelOption.nearPrivateDefaultModelID])
        XCTAssertEqual(catalog.cloudRouteModels.map(\.id), [ModelOption.nearCloudModelID(for: "provider/current-model")])
        XCTAssertEqual(api.lastCloudAPIKey, "near-cloud-key")
    }

    func testGLM51IsCanonicalPrivateDefaultAndSurvivesNarrowCatalogs() {
        let qwenOnlyCatalog = ModelCatalogStore(
            models: [
                ModelOption(modelID: "Qwen/Qwen3.5-122B-A10B", publicModel: true, metadata: nil)
            ],
            allowedModelIDs: ["qwen/qwen3.5-122b-a10b"]
        )

        XCTAssertEqual(ModelOption.nearPrivateDefaultModelID, "zai-org/GLM-5.1-FP8")
        XCTAssertEqual(ModelCatalogStore.defaultModelID, "zai-org/GLM-5.1-FP8")
        XCTAssertEqual(qwenOnlyCatalog.selectedModel, "zai-org/GLM-5.1-FP8")
        XCTAssertTrue(qwenOnlyCatalog.pickerModels.contains { $0.id == "zai-org/GLM-5.1-FP8" })
        XCTAssertTrue(qwenOnlyCatalog.pickerModels.contains { $0.id == "Qwen/Qwen3.5-122B-A10B" })
        XCTAssertEqual(qwenOnlyCatalog.modelDisplayName(for: "zai-org/GLM-5.1-FP8"), "GLM 5.1")
    }

    func testFallbackPrivateCatalogIncludesSelectableAlternatives() {
        let catalog = ModelCatalogStore()
        let pickerIDs = Set(catalog.pickerModels.map(\.id))

        XCTAssertTrue(pickerIDs.contains(ModelOption.nearPrivateDefaultModelID))
        XCTAssertTrue(pickerIDs.contains("Qwen/Qwen3.5-122B-A10B"))
        XCTAssertTrue(pickerIDs.contains("Qwen/Qwen3.6-35B-A3B-FP8"))
        XCTAssertTrue(pickerIDs.contains("moonshotai/kimi-k2.6"))

        XCTAssertTrue(catalog.selectModel("Qwen/Qwen3.5-122B-A10B"))
        XCTAssertEqual(catalog.selectedModel, "Qwen/Qwen3.5-122B-A10B")
        XCTAssertEqual(catalog.selectedRouteKind, .nearPrivate)

        XCTAssertTrue(catalog.selectModel("moonshotai/kimi-k2.6"))
        XCTAssertEqual(catalog.selectedModel, "moonshotai/kimi-k2.6")
        XCTAssertEqual(catalog.selectedRouteKind, .nearPrivate)
    }

    func testModelSelectionSurfaceIncludesPrivateAgentAndCloudRoutes() {
        let qwen = ModelOption(modelID: "Qwen/Qwen3.5-122B-A10B", publicModel: true, metadata: nil)
        let kimi = ModelOption(modelID: "moonshotai/Kimi-K2-Instruct", publicModel: true, metadata: nil)
        let cloudID = ModelOption.nearCloudModelID(for: "anthropic/claude-sonnet-4-6")
        let cloud = ModelOption(
            modelID: cloudID,
            publicModel: true,
            metadata: ModelOption.Metadata(
                verifiable: false,
                contextLength: 200_000,
                modelDisplayName: "Claude Sonnet 4.6",
                modelDescription: "Connected account cloud route.",
                modelIcon: nil,
                aliases: []
            )
        )
        let catalog = ModelCatalogStore(models: [qwen, kimi], nearCloudModels: [cloud])
        let pickerIDs = Set(catalog.pickerModels.map(\.id))

        XCTAssertTrue(pickerIDs.contains(ModelOption.nearPrivateDefaultModelID))
        XCTAssertTrue(pickerIDs.contains(qwen.id))
        XCTAssertTrue(pickerIDs.contains(kimi.id))
        XCTAssertTrue(pickerIDs.contains(ModelOption.ironclawMobileModelID))
        XCTAssertTrue(pickerIDs.contains(ModelOption.ironclawModelID))
        XCTAssertEqual(catalog.cloudModels.map(\.id), [cloudID])

        XCTAssertTrue(catalog.selectModel(cloudID))
        XCTAssertEqual(catalog.selectedRouteKind, .nearCloud)

        XCTAssertTrue(catalog.selectModel(ModelOption.ironclawMobileModelID))
        XCTAssertEqual(catalog.selectedRouteKind, .ironclawMobile)

        XCTAssertTrue(catalog.selectModel(ModelOption.nearPrivateDefaultModelID))
        XCTAssertEqual(catalog.selectedRouteKind, .nearPrivate)
        XCTAssertEqual(catalog.selectedModelDisplayName, "GLM 5.1")
    }

    func testCurrentCloudCatalogModelsRemainIndividuallySelectable() {
        let currentCloudModels = [
            ModelOption(
                modelID: "anthropic/claude-opus-4-7",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: false,
                    contextLength: 1_000_000,
                    modelDisplayName: "Claude Opus 4.7",
                    modelDescription: "Current Cloud catalog model.",
                    modelIcon: nil,
                    aliases: ["opus-4-7"]
                )
            ),
            ModelOption(
                modelID: "google/gemini-2.5-flash",
                publicModel: true,
                metadata: ModelOption.Metadata(
                    verifiable: false,
                    contextLength: 1_000_000,
                    modelDisplayName: "Gemini 2.5 Flash",
                    modelDescription: "Current Cloud catalog model.",
                    modelIcon: nil,
                    aliases: ["gemini-2.5-flash"]
                )
            )
        ]
        let cloudRoutes = ModelCatalogStore.nearCloudRouteModels(from: currentCloudModels)
        let catalog = ModelCatalogStore(nearCloudModels: cloudRoutes)
        let pickerIDs = Set(catalog.pickerModels.map(\.id))

        for route in cloudRoutes {
            XCTAssertTrue(pickerIDs.contains(route.id), "\(route.id) should be visible and selectable in the picker")
            XCTAssertTrue(catalog.selectModel(route.id), "\(route.id) should select from the picker")
            XCTAssertEqual(catalog.selectedModel, route.id)
            XCTAssertEqual(catalog.selectedRouteKind, .nearCloud)
        }
    }

    func testProjectIdentityCatalogSupportsSearchablePhoneChoices() {
        XCTAssertGreaterThanOrEqual(ProjectPalette.allCases.count, 8)
        XCTAssertGreaterThanOrEqual(ProjectIcon.allCases.count, 30)
        XCTAssertTrue(ProjectIcon.pullRequest.matches("pull"))
        XCTAssertTrue(ProjectIcon.brain.matches("thinking"))
        XCTAssertTrue(ProjectIcon.shield.matches("verified"))
        XCTAssertFalse(ProjectIcon.folder.matches("nonexistent-symbol"))
    }

    func testIronclawSkillCatalogBlankStatePrefersPhoneFirstAgentSkills() {
        let skills = IronclawSkillCatalog.suggestedSkills(for: "", limit: 3)

        XCTAssertEqual(skills.map(\.id), ["coding", "local-test", "github-workflow"])
    }

    func testIronclawSkillCatalogIncludesUpstreamSetupSkillsUsedByOnboarding() {
        let skills = IronclawSkillCatalog.profiles(
            for: ["developer-setup", "new-project", "plan-mode", "review-readiness"]
        )

        XCTAssertEqual(skills.map(\.id), ["developer-setup", "new-project", "plan-mode", "review-readiness"])
    }

    func testIronclawSkillCatalogIncludesUpstreamSkillsReferencedByRouting() {
        let skills = IronclawSkillCatalog.profiles(
            for: ["github", "delegation", "review-checklist", "idea-parking", "tech-debt-tracker", "web-ui-test"]
        )

        XCTAssertEqual(
            skills.map(\.id),
            ["github", "delegation", "review-checklist", "idea-parking", "tech-debt-tracker", "web-ui-test"]
        )
    }

    func testIronclawSkillCatalogMatchingSkillsOnlyReturnsExactKeywordMatches() {
        let skills = IronclawSkillCatalog.matchingSkills(
            for: "Run a security audit with a manual test plan before merge.",
            limit: 4
        )

        XCTAssertEqual(skills.map(\.id), ["qa-review", "security-review", "review-readiness"])
    }

    func testModelCatalogContainsNoSpeculativeFallbackIdentifiers() {
        let banned = [
            "gpt-5.5",
            "qwen3.7-max",
            "kimi-k2.6",
            "gemini-3.5-flash",
            "claude-opus-4-7",
            "Qwen 3.7 Max",
            "Claude Opus 4.7"
        ]
        let fallbackSurface = (ModelCatalogStore.fallbackNearCloudModels() + ModelCatalogStore.fallbackPrivateModels())
            .flatMap { model in
                [
                    model.id,
                    model.displayName,
                    model.metadata?.modelDescription ?? "",
                    model.metadata?.aliases?.joined(separator: " ") ?? ""
                ]
            }
            .joined(separator: " ")

        for identifier in banned {
            XCTAssertFalse(
                fallbackSurface.localizedCaseInsensitiveContains(identifier),
                "Fallback model surface should not include \(identifier)."
            )
        }
    }

    func testProductSourcesDoNotShipSpeculativeModelNames() throws {
        let banned = [
            "gpt-5.5",
            "qwen3.7-max",
            "kimi-k2.6",
            "gemini-3.5-flash",
            "claude-opus-4-7",
            "Qwen 3.7 Max",
            "Claude Opus 4.7"
        ]
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let roots = [
            repoRoot.appendingPathComponent("NEARPrivateChat"),
            repoRoot.appendingPathComponent("Preview")
        ]
        var leaks: [String] = []

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for case let fileURL as URL in enumerator {
                if fileURL.pathComponents.contains(where: { $0.hasSuffix(".xcassets") }) {
                    enumerator.skipDescendants()
                    continue
                }
                let fileExtension = fileURL.pathExtension.lowercased()
                guard ["swift", "html", "md", "plist"].contains(fileExtension) else { continue }
                let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
                for identifier in banned where text.localizedCaseInsensitiveContains(identifier) {
                    leaks.append("\(fileURL.path): \(identifier)")
                }
            }
        }

        XCTAssertTrue(leaks.isEmpty, leaks.joined(separator: "\n"))
    }
}

private final class ModelCatalogFakeAPI: ModelAPI {
    let privateModels: [ModelOption]
    let cloudModels: [ModelOption]
    private(set) var lastCloudAPIKey: String?

    init(privateModels: [ModelOption], cloudModels: [ModelOption]) {
        self.privateModels = privateModels
        self.cloudModels = cloudModels
    }

    func fetchModels() async throws -> [ModelOption] {
        privateModels
    }

    func connectNearCloudAccount() async throws -> NearCloudConnectResponse {
        throw APIError.emptyResponse
    }

    func fetchNearCloudModels(apiKey: String?) async throws -> [ModelOption] {
        lastCloudAPIKey = apiKey
        return cloudModels
    }

    func fetchNearCloudChatCompletion(
        apiKey: String,
        model: String,
        prompt: String,
        systemPrompt: String,
        advancedParams: AdvancedModelParams
    ) async throws -> String {
        throw APIError.emptyResponse
    }
}

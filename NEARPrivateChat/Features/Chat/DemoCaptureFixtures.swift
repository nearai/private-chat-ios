import Foundation

#if DEBUG
@MainActor
extension ChatStore {
    /// One successful answer (proof footer + actions) followed by a failed turn
    /// (red Failed + Retry only) -- the canonical trust-surface contrast.
    static func demoFailureMessages(now: Date) -> [ChatMessage] {
        [
            ChatMessage(
                id: "df-u1",
                role: .user,
                text: "Summarize this term sheet and extract the obligations.",
                model: nil,
                createdAt: now.addingTimeInterval(-300),
                status: "completed",
                responseID: nil,
                isStreaming: false
            ),
            ChatMessage(
                id: "df-a1",
                role: .assistant,
                text: "Short version: a $4M raise on a $40M cap, 1x non-participating preference, monthly reporting, and a 60-day exclusivity window. The binding obligations sit in sections 4 and 7.",
                model: Self.defaultModelID,
                createdAt: now.addingTimeInterval(-295),
                status: "completed",
                responseID: "df-a1-r",
                isStreaming: false
            ),
            ChatMessage(
                id: "df-u2",
                role: .user,
                text: "Turn those obligations into a checklist with owners.",
                model: nil,
                createdAt: now.addingTimeInterval(-60),
                status: "completed",
                responseID: nil,
                isStreaming: false
            ),
            ChatMessage(
                id: "df-a2",
                role: .assistant,
                text: "Private route is rate-limited for this session. Retry private; if it keeps failing, sign out and back in. Use the privacy proxy only for this turn.",
                model: Self.defaultModelID,
                createdAt: now.addingTimeInterval(-55),
                status: "failed",
                responseID: nil,
                isStreaming: false
            )
        ]
    }

    static func demoWidgetMessages(now: Date) -> [ChatMessage] {
        func user(_ id: String, _ text: String, _ offset: TimeInterval) -> ChatMessage {
            ChatMessage(id: id, role: .user, text: text, model: nil, createdAt: now.addingTimeInterval(offset), status: "completed", responseID: nil, isStreaming: false)
        }
        func assistant(_ id: String, _ text: String, _ offset: TimeInterval, widget: MessageWidget) -> ChatMessage {
            ChatMessage(id: id, role: .assistant, text: text, model: Self.defaultModelID, createdAt: now.addingTimeInterval(offset), status: "completed", responseID: "\(id)-r", isStreaming: false, widget: widget)
        }
        let actionPlanWidget = MessageWidget(
            kind: .actionPlan,
            title: "Actions from PDF + supplement table",
            freshness: .fresh,
            time: "8:08am",
            followUp: "Review the next action",
            actionPlan: WidgetActionPlan(
                heading: "Review before creating",
                summary: "Concrete phone actions are separated from fuzzy rows that need one more detail.",
                actions: [
                    WidgetActionItem(
                        title: "Services agreement review",
                        type: "calendar invite",
                        detail: "Review the draft services agreement with counsel before sending.",
                        schedule: nil,
                        command: "Add services agreement review to calendar on 2026-07-02 at 11:00 AM",
                        source: "PDF template instructions page 2",
                        date: "2026-07-02",
                        time: "11:00 AM",
                        duration: "1 hour",
                        recurrence: nil,
                        timezone: "America/New_York",
                        location: "Zoom",
                        attendees: ["legal@example.com"],
                        missingFields: [],
                        confidence: 0.92,
                        tone: .good
                    ),
                    WidgetActionItem(
                        title: "Bedtime magnesium",
                        type: "tracker",
                        detail: "The supplement table says bedtime, but does not provide an exact time.",
                        schedule: "before bed",
                        command: "Create a tracker for bedtime magnesium daily",
                        source: "Supplement table row 11",
                        date: nil,
                        time: "before bed",
                        duration: nil,
                        recurrence: "daily",
                        timezone: nil,
                        location: nil,
                        attendees: [],
                        missingFields: [],
                        confidence: 0.75,
                        tone: .warn
                    )
                ]
            )
        )

        return [
            user("dw-u1", "What's in today's news?", -600),
            assistant("dw-a1", "Three stories leading today, weighted to what you track.", -595, widget: .demoNewsBrief),
            user("dw-u2", "Compare SEV-SNP and TDX for our TEE.", -420),
            assistant("dw-a2", "Both give you memory encryption and attestation; they differ on isolation and live migration.", -415, widget: .demoComparison),
            user("dw-u3", "How's ETH doing right now?", -300),
            assistant("dw-a3", "ETH slipped below your $3,180 threshold in the last hour.", -295, widget: .demoChart),
            user("dw-u4", "Turn this PDF template and supplement table into actions.", -120),
            assistant("dw-a4", "I separated phone-ready actions from rows that need one more detail.", -115, widget: actionPlanWidget)
        ]
    }

    struct DemoCaptureData {
        let project: ChatProject
        let conversations: [ConversationSummary]
        let glmConversation: ConversationSummary
        let primaryConversation: ConversationSummary
        let agentConversation: ConversationSummary
        let glmMessages: [ChatMessage]
        let messages: [ChatMessage]
        let agentMessages: [ChatMessage]
        let models: [ModelOption]
        let nearCloudModels: [ModelOption]
        let attestation: AttestationSnapshot
    }

    static func demoCaptureData(now: Date) -> DemoCaptureData {
        let projectID = "demo-project-ironclaw-pr-plan"
        let conversationID = "demo-conversation-iran-council"
        let glmConversationID = "demo-conversation-glm-private"
        let councilBatchID = "demo-council-iran-status"
        let demoCloudClaudeSonnet46 = ModelOption.nearCloudModelID(for: "anthropic/claude-sonnet-4-6")
        let demoCloudClaudeOpus46 = ModelOption.nearCloudModelID(for: "anthropic/claude-opus-4-6")
        let demoCloudQwen3635 = ModelOption.nearCloudModelID(for: "Qwen/Qwen3.6-35B-A3B-FP8")
        let demoCloudQwen3627 = ModelOption.nearCloudModelID(for: "Qwen/Qwen3.6-27B-FP8")
        let created = now.addingTimeInterval(-11 * 60)
        let project = ChatProject(
            id: projectID,
            name: "IronClaw Reborn Plan",
            createdAt: created.addingTimeInterval(-3600),
            conversationIDs: [glmConversationID, conversationID],
            attachments: [
                ChatAttachment(id: "demo-file-reborn-project-plan", name: "reborn-project-plan.md", kind: "txt", bytes: 42_000),
                ChatAttachment(id: "demo-file-pr-snapshot", name: "latest-ironclaw-prs.json", kind: "json", bytes: 19_000)
            ],
            instructions: "Update plans from live GitHub evidence. Group work by lifecycle, SSE/replay, and first-party GitHub WASM extension.",
            memorySummary: "The plan tracks IronClaw Reborn lifecycle work, SSE replay reliability, and first-party GitHub extension installability.",
            links: [
                ProjectLink(
                    id: "demo-link-ironclaw-prs",
                    title: "nearai/ironclaw pull requests",
                    urlString: "https://github.com/nearai/ironclaw/pulls",
                    createdAt: created.addingTimeInterval(60)
                )
            ],
            notes: [
                ProjectNote(
                    id: "demo-note-reborn-plan",
                    title: "Reborn plan update",
                    text: "Fold #4066, #4065, and #4064 into the project plan before the next release review.",
                    createdAt: created.addingTimeInterval(120)
                )
            ],
            iconName: ProjectIcon.folder.symbolName,
            paletteName: ProjectPalette.sky.rawValue
        )

        let glmConversation = ConversationSummary(
            id: glmConversationID,
            createdAt: created.addingTimeInterval(120).timeIntervalSince1970,
            metadata: ConversationMetadata(title: "Iran war status today")
        )
        let primaryConversation = ConversationSummary(
            id: conversationID,
            createdAt: created.timeIntervalSince1970,
            metadata: ConversationMetadata(title: "Iran war Council view")
        )
        let agentConversation = ConversationSummary(
            id: "demo-conversation-ironclaw-run",
            createdAt: created.addingTimeInterval(-300).timeIntervalSince1970,
            metadata: ConversationMetadata(title: "IronClaw PR plan update")
        )
        let earlierConversation = ConversationSummary(
            id: "demo-conversation-council-pricing",
            createdAt: created.addingTimeInterval(-86_400).timeIntervalSince1970,
            metadata: ConversationMetadata(title: "Model routing comparison")
        )
        let apExplainerSource = WebSearchSource(type: "web", url: "https://apnews.com/article/b1659232611edc10808612e30647c17d", title: "AP: What we know about the emerging deal to end the Iran war", publishedAt: "May 25, 2026")
        let pbsExplainerSource = WebSearchSource(type: "web", url: "https://www.pbs.org/newshour/world/what-we-know-and-dont-know-about-the-emerging-deal-to-end-the-iran-war", title: "PBS/AP: Emerging deal to end the Iran war", publishedAt: "May 25, 2026")
        let bostonAPSource = WebSearchSource(type: "web", url: "https://www.boston.com/news/politics/2026/05/24/trump-says-a-deal-with-iran-and-opening-of-strait-of-hormuz-are-largely-negotiated/", title: "Boston.com/AP: Deal and Hormuz reopening largely negotiated", publishedAt: "May 24, 2026")
        let apDealSource = WebSearchSource(type: "web", url: "https://apnews.com/article/1c283f26d037102cc5e6f798546d0e59", title: "AP: Trump says Iran deal is largely negotiated", publishedAt: "May 23, 2026")
        let apStrikesSource = WebSearchSource(type: "web", url: "https://apnews.com/article/01a13e9a63ece786a0a7fa4933dbf09b", title: "AP: U.S. military reports self-defense strikes in Iran", publishedAt: "May 25, 2026")
        let apHezbollahSource = WebSearchSource(type: "web", url: "https://apnews.com/article/9e3ba96982cd082f030a1a556cd57785", title: "AP: Israel strikes Hezbollah sites as ceasefire pressure continues", publishedAt: "May 25, 2026")
        let iranSources = [
            apExplainerSource,
            pbsExplainerSource,
            bostonAPSource,
            apDealSource,
            apStrikesSource,
            apHezbollahSource
        ]
        let glmCouncilSources = [apExplainerSource, pbsExplainerSource]
        let qwenCouncilSources = [bostonAPSource, apDealSource]
        let opusCouncilSources = [apStrikesSource, apHezbollahSource]
        let prSources = [
            WebSearchSource(type: "project_file", url: "https://near.ai/demo/reborn-project-plan.md", title: "reborn-project-plan.md"),
            WebSearchSource(type: "web", url: "https://github.com/nearai/ironclaw/pull/4066", title: "#4066 Wire Reborn extension lifecycle registry"),
            WebSearchSource(type: "web", url: "https://github.com/nearai/ironclaw/pull/4065", title: "#4065 Fix Reborn SSE replay fallback"),
            WebSearchSource(type: "web", url: "https://github.com/nearai/ironclaw/pull/4064", title: "#4064 Install GitHub WASM extension through Reborn lifecycle")
        ]
        let glmUserMessage = ChatMessage(
            id: "demo-user-glm-private",
            role: .user,
            text: "Is the war in Iran ending as of today?",
            model: nil,
            createdAt: created.addingTimeInterval(122),
            status: "completed",
            responseID: nil,
            isStreaming: false,
            attachments: []
        )
        let glmPrivateAnswer = ChatMessage(
            id: "demo-assistant-glm-private-answer",
            role: .assistant,
            text: """
            The ceasefire is holding into its third day, but I would not call the war over yet.

            Monitors report two minor violations near Hormuz, while negotiators continue a 60-day extension in Geneva [1][2]. Oil has eased on lower escalation risk, but the deal still needs signed sequencing, Strait reopening steps, and a sustained pause in related regional strikes [3][4].

            My read: this is an endgame phase, not finished peace.
            """,
            model: Self.defaultModelID,
            createdAt: created.addingTimeInterval(130),
            firstTokenAt: created.addingTimeInterval(131.1),
            status: "completed",
            responseID: "demo-response-glm-private",
            isStreaming: false,
            searchQuery: "Is the war in Iran ending as of today?",
            sources: iranSources,
            attachments: []
        )
        let userMessage = ChatMessage(
            id: "demo-user-risk-summary",
            role: .user,
            text: "Is the war in Iran ending as of today?",
            model: nil,
            createdAt: created,
            status: "completed",
            responseID: nil,
            isStreaming: false,
            attachments: []
        )
        let synthesisMessage = ChatMessage(
            id: "demo-assistant-council-synthesis",
            role: .assistant,
            text: """
            ## Direct answer
            The best answer is: not over, but closer to an off-ramp. GLM 5.1 reads the AP/PBS overview as evidence that a deal is emerging [1][2]. Claude Sonnet 4.6 focuses on whether the reported framework and Strait of Hormuz terms actually get implemented [3][4]. Qwen 3.6 keeps the caution high because fresh military activity and the Israel-Hezbollah front can still break the diplomatic track [5][6].

            ## What the council agrees on
            Nobody should say the war is already over. The supported statement is narrower: talks appear close to an agreement, but the outcome still depends on a signed/finalized deal, implementation of the Hormuz reopening, and containment of related military fronts [1][3][5][6].

            ## How the models vary
            - GLM 5.1: weighs the broad AP/PBS explainer coverage and calls this a possible endgame, not a settled peace [1][2].
            - Claude Sonnet 4.6: reads the deal-specific reporting as an implementation checklist: final text, Hormuz reopening, and follow-on negotiations [3][4].
            - Qwen 3.6: reads the security reporting as a warning that diplomacy is still exposed to military and regional shocks [5][6].

            ## Disagreements or uncertainty
            The disagreement is about confidence. GLM 5.1 is the most optimistic because the overview reporting points to a possible deal. Claude Sonnet 4.6 is conditional because a framework is not the same as implementation. Qwen 3.6 is the least willing to call it ending while strike reports and spillover risks remain live.
            """,
            model: ModelOption.llmCouncilSynthesisModelID,
            createdAt: created.addingTimeInterval(18),
            firstTokenAt: created.addingTimeInterval(19.2),
            status: "completed",
            responseID: "demo-response-synthesis",
            councilBatchID: councilBatchID,
            isStreaming: false,
            searchQuery: "Is the war in Iran ending as of today?",
            sources: iranSources
        )
        let glmMessage = ChatMessage(
            id: "demo-assistant-glm",
            role: .assistant,
            text: """
            ## GLM 5.1
            The AP/PBS overview supports "possible endgame," not "ended" [1][2]. I would answer that the war appears closer to a diplomatic off-ramp, but the claim should stay bounded until there is a final agreement and visible implementation.
            """,
            model: Self.defaultModelID,
            createdAt: created.addingTimeInterval(19),
            firstTokenAt: created.addingTimeInterval(20.2),
            status: "completed",
            responseID: "demo-response-glm",
            councilBatchID: councilBatchID,
            isStreaming: false,
            searchQuery: "Is the war in Iran ending as of today?",
            sources: glmCouncilSources
        )
        let qwenLargeMessage = ChatMessage(
            id: "demo-assistant-qwen-large",
            role: .assistant,
            text: """
            ## Claude Sonnet 4.6
            The deal-specific reporting makes this an implementation question [1][2]. If the framework is finalized and the Strait of Hormuz reopening actually starts, then "ending" becomes plausible. If those milestones slip, the headline is only diplomatic momentum.
            """,
            model: demoCloudClaudeSonnet46,
            createdAt: created.addingTimeInterval(20),
            firstTokenAt: created.addingTimeInterval(21.7),
            status: "completed",
            responseID: "demo-response-qwen-large",
            councilBatchID: councilBatchID,
            isStreaming: false,
            searchQuery: "Is the war in Iran ending as of today?",
            sources: qwenCouncilSources
        )
        let opusMessage = ChatMessage(
            id: "demo-assistant-opus",
            role: .assistant,
            text: """
            ## Qwen 3.6
            I would be careful with the word "ending." Diplomatic signals can coexist with active coercion. Fresh strike reporting and the Israel-Hezbollah front mean the safer answer is: negotiations may be near an off-ramp, but the conflict is not reliably settled yet [1][2].
            """,
            model: demoCloudQwen3635,
            createdAt: created.addingTimeInterval(21),
            firstTokenAt: created.addingTimeInterval(22.4),
            status: "completed",
            responseID: "demo-response-opus",
            councilBatchID: councilBatchID,
            isStreaming: false,
            searchQuery: "Is the war in Iran ending as of today?",
            sources: opusCouncilSources
        )
        let agentUserMessage = ChatMessage(
            id: "demo-user-ironclaw",
            role: .user,
            text: "Use this attached project plan and the latest nearai/ironclaw PRs to update the plan. Show what changed and why.",
            model: nil,
            createdAt: created.addingTimeInterval(280),
            status: "completed",
            responseID: nil,
            isStreaming: false,
            attachments: project.attachments
        )
        let agentRunMessage = ChatMessage(
            id: "demo-assistant-ironclaw-result",
            role: .assistant,
            text: """
            IronClaw output

            Inputs
            - Attached plan: reborn-project-plan.md [1]
            - Latest open PRs checked: #4066, #4065, #4064 [2][3][4]

            What changed in the plan
            1. Added a new "Extension lifecycle registry" milestone from #4066. It covers search, install, activate, remove, shared active-extension registry, host-internal filtering, and dynamic WASM credentials [2].
            2. Moved "SSE replay reliability" from polish to release-blocker because #4065 fixes replay_unavailable behavior, projection rebases, and lifecycle event replay ordering [3].
            3. Added "First-party GitHub WASM installability" as a dependent milestone from #4064. It brings the GitHub extension catalog, manifest/schema/prompt assets, host-internal github.comment_issue, and first-party WASM build support [4].

            Updated project plan
            - Phase 1: Land generic Reborn lifecycle registry (#4066).
            - Phase 2: Stabilize SSE replay fallback and runtime-event replay (#4065).
            - Phase 3: Install and activate the first-party GitHub WASM extension through the new lifecycle (#4064).
            - Phase 4: Run integration QA: search -> install -> activate -> hidden host-internal tools -> dynamic credentials -> SSE replay after reconnect.

            Risks found
            - #4064 stacks on #4066, so GitHub extension QA should wait until the generic lifecycle registry is stable.
            - #4065 touches replay semantics across event projections and streams, so reconnect testing needs to be explicit.
            - Host-internal capability filtering appears in both #4066 and #4064; duplicate assumptions should be reviewed before merge.

            Final recommendation
            Treat the three PRs as one release train: lifecycle registry first, replay reliability second, GitHub extension installability third. The updated plan is ready for review.
            """,
            model: ModelOption.ironclawModelID,
            createdAt: Date().addingTimeInterval(-34),
            firstTokenAt: Date().addingTimeInterval(-31),
            status: "completed",
            responseID: "demo-response-ironclaw-result",
            isStreaming: false,
            searchQuery: "nearai/ironclaw latest open PRs project plan update",
            sources: prSources,
            attachments: project.attachments
        )

        let models = [
            demoModel(Self.defaultModelID, displayName: "GLM 5.1", description: "Default NEAR Private model with proof support.", verifiable: true),
            demoModel(demoCloudClaudeSonnet46, displayName: "Claude Sonnet 4.6", description: "Anthropic long-context model through the NEAR AI Cloud privacy proxy.", verifiable: false),
            demoModel(demoCloudClaudeOpus46, displayName: "Claude Opus 4.6", description: "Anthropic coding and agent model through the NEAR AI Cloud privacy proxy.", verifiable: false),
            demoModel(demoCloudQwen3635, displayName: "Qwen 3.6 35B A3B FP8", description: "Qwen reasoning model through the NEAR AI Cloud privacy proxy.", verifiable: false),
            demoModel(demoCloudQwen3627, displayName: "Qwen 3.6 27B FP8", description: "Qwen dense model through the NEAR AI Cloud privacy proxy.", verifiable: false),
            demoModel(ModelOption.ironclawMobileModelID, displayName: "IronClaw Mobile", description: "Phone-safe agent runtime.", verifiable: false),
            demoModel(ModelOption.ironclawModelID, displayName: "Hosted IronClaw", description: "Connected Hosted IronClaw.", verifiable: false)
        ]
        let nearCloudModels = models.filter { $0.isNearCloudModel }
        let attestation = AttestationSnapshot(
            nonce: "demo-\(Int(now.timeIntervalSince1970))",
            signingAlgorithm: "ed25519 + Intel TDX quote",
            model: "NEAR Private default",
            coveredModelIDs: [Self.defaultModelID],
            fetchedAt: now.addingTimeInterval(-45),
            chatGatewayAddress: "tee-gateway.near.ai",
            cloudGatewayAddress: nil,
            modelAttestationCount: 1,
            prettyJSON: """
            {
              "nonce": "demo-\(Int(now.timeIntervalSince1970))",
              "gateway": "tee-gateway.near.ai",
              "model": "NEAR Private default",
              "covered_models": [
                "\(Self.defaultModelID)"
              ],
              "quote": "demo-intel-tdx-quote",
              "signature": "demo-ed25519-signature"
            }
            """
        )
        return DemoCaptureData(
            project: project,
            conversations: [glmConversation, primaryConversation, agentConversation, earlierConversation],
            glmConversation: glmConversation,
            primaryConversation: primaryConversation,
            agentConversation: agentConversation,
            glmMessages: [glmUserMessage, glmPrivateAnswer],
            messages: [userMessage, synthesisMessage, glmMessage, qwenLargeMessage, opusMessage],
            agentMessages: [agentUserMessage, agentRunMessage],
            models: models,
            nearCloudModels: nearCloudModels,
            attestation: attestation
        )
    }

    private static func demoModel(
        _ id: String,
        displayName: String,
        description: String,
        verifiable: Bool
    ) -> ModelOption {
        ModelOption(
            modelID: id,
            publicModel: !verifiable,
            metadata: ModelOption.Metadata(
                verifiable: verifiable,
                contextLength: 131_072,
                modelDisplayName: displayName,
                modelDescription: description,
                modelIcon: nil,
                aliases: [displayName]
            )
        )
    }
}
#endif

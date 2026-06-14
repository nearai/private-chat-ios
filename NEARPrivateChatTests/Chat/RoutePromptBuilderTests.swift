import XCTest
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testHostedPromptContextIncludesUploadedExcerptAndOmitsLocalOnlyText() {
        let projectAttachment = ChatAttachment(id: "project-file", name: "roadmap.pdf", kind: "pdf_text", bytes: 512)
        let uploadedAttachment = ChatAttachment(id: "uploaded-doc", name: "services \"template\".pdf", kind: "pdf_text", bytes: 1_024)
        let tableAttachment = ChatAttachment(id: "uploaded-table", name: "supplements.csv", kind: "table_text", bytes: 2_048)
        let uploadedBinaryAttachment = ChatAttachment(id: "uploaded-binary", name: "diagram.png", kind: "image", bytes: 4_096)
        let localOnlyAttachment = ChatAttachment(
            id: "local-doc-hidden",
            name: "private-notes.pdf",
            kind: ChatAttachment.localDocumentKind,
            bytes: 256
        )
        let project = ChatProject(
            id: "project-hosted-context",
            name: "Services Agreement",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            conversationIDs: [],
            attachments: [projectAttachment],
            instructions: "Draft like a careful commercial lawyer.",
            memorySummary: "Counterparty prefers monthly invoices.",
            links: [
                ProjectLink(title: "MSA reference", urlString: "https://example.com/msa"),
                ProjectLink(title: "Internal link", urlString: "http://localhost:3000/secret")
            ],
            notes: [
                ProjectNote(title: "Public note", text: "Acme prefers Ontario governing law.", isLocalOnly: false),
                ProjectNote(title: "Local note", text: "Local-only sentinel must stay on device.", isLocalOnly: true)
            ]
        )
        let documentTexts = [
            uploadedAttachment.id: "Uploaded document sentinel: the services term is twelve months.",
            tableAttachment.id: String(repeating: "TABLE_SENTINEL ", count: 220) + "SHOULD_BE_CLIPPED_AFTER_CAP",
            uploadedBinaryAttachment.id: "BINARY_ATTACHMENT_STAGED_TEXT_MUST_NOT_REACH_HOSTED",
            localOnlyAttachment.id: "Local only sentinel that hosted routes must not receive."
        ]

        let context = ChatPromptContextBuilder.hostedIronclawContextSection(
            selectedProject: project,
            promptAttachments: [uploadedAttachment, tableAttachment, uploadedBinaryAttachment, localOnlyAttachment],
            sourceModeDetail: "Web + Files",
            documentText: { documentTexts[$0] }
        )

        XCTAssertTrue(context.contains("Project: Services Agreement"))
        XCTAssertTrue(context.contains("Draft like a careful commercial lawyer."))
        XCTAssertTrue(context.contains("Public note: Acme prefers Ontario governing law."))
        XCTAssertTrue(context.contains("Local-only project notes omitted for Hosted IronClaw: 1"))
        XCTAssertTrue(context.contains("https://example.com/msa"))
        XCTAssertFalse(context.contains("localhost"))
        XCTAssertTrue(context.contains(#""services \"template\".pdf""#))
        XCTAssertTrue(context.contains(#""supplements.csv""#))
        XCTAssertTrue(context.contains(#""diagram.png""#))
        XCTAssertFalse(context.contains(#""private-notes.pdf""#))
        XCTAssertTrue(context.contains("Uploaded document sentinel"))
        XCTAssertTrue(context.contains("TABLE_SENTINEL"))
        XCTAssertFalse(context.contains("BINARY_ATTACHMENT_STAGED_TEXT_MUST_NOT_REACH_HOSTED"))
        XCTAssertFalse(context.contains("SHOULD_BE_CLIPPED_AFTER_CAP"))
        XCTAssertLessThanOrEqual(context.count, 3_800)
        XCTAssertFalse(context.contains("Local only sentinel"))
        XCTAssertFalse(context.contains("Local note:"))
        XCTAssertTrue(context.contains("Local-only prompt files omitted for Hosted IronClaw: 1"))
        XCTAssertTrue(context.contains("Focus: Web + Files"))
    }

    @MainActor
    func testNearCloudPromptBuilderCarriesTranscriptAttachmentsWebAndDocumentExcerpt() {
        let attachment = ChatAttachment(id: "cloud-doc", name: "board-pack-pdf-text.txt", kind: "pdf_text", bytes: 2_048)
        let store = AttachmentStagingStore()
        store.stageDocumentText(
            "Board pack sentinel: runway is eighteen months after the bridge round.",
            for: attachment.id
        )
        let webContext = WebGroundingContext(
            query: "Acme bridge round latest",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            results: [
                WebGroundingResult(
                    title: "Acme closes bridge round",
                    urlString: "https://example.com/acme-bridge",
                    sourceName: "example.com",
                    snippet: "Acme announced financing terms.",
                    publishedAt: "June 1, 2026",
                    kind: "web"
                )
            ]
        )
        let messages = [
            makeMessage(
                id: "previous-user",
                role: .user,
                text: "Use the board pack and current sources.",
                createdAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            makeMessage(
                id: "previous-assistant",
                role: .assistant,
                text: "I will compare both.",
                createdAt: Date(timeIntervalSince1970: 1_700_000_010)
            ),
            makeMessage(
                id: "current-user-placeholder",
                role: .user,
                text: "Summarize runway.",
                createdAt: Date(timeIntervalSince1970: 1_700_000_020)
            )
        ]

        let basePrompt = ChatPromptContextBuilder.nearCloudPrompt(
            text: "Summarize runway.",
            attachments: [attachment],
            webContext: webContext,
            messages: messages
        )
        let finalPrompt = store.documentAugmentedPrompt(
            basePrompt,
            question: "What is the runway in the board pack?",
            attachments: [attachment]
        )

        XCTAssertTrue(finalPrompt.contains("Recent conversation:"))
        XCTAssertTrue(finalPrompt.contains("Use the board pack and current sources."))
        XCTAssertTrue(finalPrompt.contains("Attachment context: The user attached board-pack-pdf-text.txt."))
        XCTAssertTrue(finalPrompt.contains("Live web context supplied by the iOS app"))
        XCTAssertTrue(finalPrompt.contains("https://example.com/acme-bridge"))
        XCTAssertTrue(finalPrompt.contains("Board pack sentinel"))
    }

    @MainActor
    func testDocumentSentinelReachesEveryRoutedPromptWithoutLeakingLocalOnlyToCloudOrHosted() {
        let uploaded = ChatAttachment(
            id: "uploaded-services-doc",
            name: "services-schedule-pdf-text.txt",
            kind: "pdf_text",
            bytes: 2_048
        )
        let localOnly = ChatAttachment(
            id: "local-only-services-doc",
            name: "private-notes.pdf",
            kind: ChatAttachment.localDocumentKind,
            bytes: 512
        )
        let uploadedSentinel = "FOUR_ROUTE_SENTINEL uploaded schedule says magnesium at 8 PM."
        let localOnlySentinel = "LOCAL_ONLY_SENTINEL private notes say yoga at noon."
        let question = "Use FOUR_ROUTE_SENTINEL and LOCAL_ONLY_SENTINEL schedule details."
        let store = AttachmentStagingStore()
        store.stageDocumentText(uploadedSentinel, for: uploaded.id)
        store.stageDocumentText(localOnlySentinel, for: localOnly.id)
        let webContext = WebGroundingContext(
            query: "services schedule tracker",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            results: [
                WebGroundingResult(
                    title: "Tracker setup reference",
                    urlString: "https://example.com/tracker",
                    sourceName: "example.com",
                    snippet: "Schedule tracker setup reference.",
                    publishedAt: "June 1, 2026",
                    kind: "web"
                )
            ]
        )

        let privatePrompt = store.documentAugmentedPrompt(
            "Private route base prompt.",
            question: question,
            attachments: [uploaded, localOnly]
        )
        let nearCloudPrompt = store.documentAugmentedPrompt(
            ChatPromptContextBuilder.nearCloudPrompt(
                text: question,
                attachments: [uploaded, localOnly],
                webContext: nil,
                messages: []
            ),
            question: question,
            attachments: [uploaded]
        )
        let briefingPrompt = store.documentAugmentedPrompt(
            ChatPromptContextBuilder.cloudBriefingPrompt(prompt: question, webContext: webContext),
            question: question,
            attachments: [uploaded]
        )
        let mobilePrompt = store.documentAugmentedPrompt(
            AgentStore.normalizedIronclawPrompt(question),
            question: question,
            attachments: [uploaded]
        )
        let hostedContext = ChatPromptContextBuilder.hostedIronclawContextSection(
            selectedProject: nil,
            promptAttachments: [uploaded, localOnly],
            sourceModeDetail: "Files",
            documentText: { store.documentText(for: $0) }
        )

        XCTAssertTrue(privatePrompt.contains(uploadedSentinel))
        XCTAssertTrue(privatePrompt.contains(localOnlySentinel))
        for prompt in [nearCloudPrompt, briefingPrompt, mobilePrompt] {
            XCTAssertTrue(prompt.contains(uploadedSentinel))
            XCTAssertFalse(prompt.contains(localOnlySentinel))
            XCTAssertFalse(prompt.contains(localOnly.id))
            XCTAssertFalse(prompt.contains(localOnly.name))
        }
        XCTAssertTrue(briefingPrompt.contains("Live web context supplied by the iOS app"))
        XCTAssertTrue(briefingPrompt.contains("https://example.com/tracker"))
        XCTAssertTrue(hostedContext.contains(uploadedSentinel))
        XCTAssertFalse(hostedContext.contains(localOnlySentinel))
        XCTAssertFalse(hostedContext.contains(localOnly.id))
        XCTAssertFalse(hostedContext.contains(localOnly.name))
        XCTAssertTrue(hostedContext.contains("Local-only prompt files omitted for Hosted IronClaw: 1"))
        XCTAssertTrue(hostedContext.contains("Prompt files attached as untrusted filename labels"))
    }

    func testMobileProjectContextKeepsProjectAndPromptFilesDistinct() {
        let projectAttachment = ChatAttachment(id: "project-file", name: "roadmap.pdf", kind: "pdf_text", bytes: 512)
        let promptAttachment = ChatAttachment(id: "prompt-file", name: "fresh-notes.pdf", kind: "pdf_text", bytes: 256)
        let project = ChatProject(
            id: "project-mobile-context",
            name: "Launch Room",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            conversationIDs: ["conv-1"],
            attachments: [projectAttachment],
            instructions: "Prefer concise launch plans.",
            memorySummary: "The launch audience is developers.",
            links: [
                ProjectLink(title: "Public docs", urlString: "https://docs.example.com"),
                ProjectLink(title: "Local admin", urlString: "http://127.0.0.1:9999")
            ],
            notes: [ProjectNote(title: "Risk", text: "Keep the beta narrow.")]
        )

        let context = ChatPromptContextBuilder.mobileProjectContext(
            selectedProject: project,
            selectedProjectAttachments: [projectAttachment],
            promptAttachments: [projectAttachment, promptAttachment]
        )

        XCTAssertEqual(context.projectName, "Launch Room")
        XCTAssertEqual(context.projectFiles, ["roadmap.pdf"])
        XCTAssertEqual(context.promptFiles, ["fresh-notes.pdf"])
        XCTAssertEqual(context.projectLinks, ["Public docs: https://docs.example.com"])
        XCTAssertEqual(context.projectNotes, ["Risk: Keep the beta narrow."])
    }
}

import XCTest
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testHostedPromptContextIncludesUploadedExcerptAndOmitsLocalOnlyText() {
        let projectAttachment = ChatAttachment(id: "project-file", name: "roadmap.pdf", kind: "pdf_text", bytes: 512)
        let uploadedAttachment = ChatAttachment(id: "uploaded-doc", name: "services \"template\".pdf", kind: "pdf_text", bytes: 1_024)
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
            localOnlyAttachment.id: "Local only sentinel that hosted routes must not receive."
        ]

        let context = ChatPromptContextBuilder.hostedIronclawContextSection(
            selectedProject: project,
            promptAttachments: [uploadedAttachment, localOnlyAttachment],
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
        XCTAssertTrue(context.contains("Uploaded document sentinel"))
        XCTAssertFalse(context.contains("Local only sentinel"))
        XCTAssertFalse(context.contains("Local note:"))
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

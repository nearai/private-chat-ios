import Foundation
import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
#if canImport(UIKit)
import UIKit
#endif

enum ConversationExportFormat {
    case text
    case markdown
    case json
    case signedJSON
    case pdf
    case docx

    var contentType: UTType {
        switch self {
        case .text: .plainText
        case .markdown: UTType(filenameExtension: "md") ?? .plainText
        case .json, .signedJSON: .json
        case .pdf: .pdf
        case .docx: UTType(filenameExtension: "docx") ?? UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
        }
    }

    var fileExtension: String {
        switch self {
        case .text: "txt"
        case .markdown: "md"
        case .json: "json"
        case .signedJSON: "signed.json"
        case .pdf: "pdf"
        case .docx: "docx"
        }
    }
}

struct ConversationExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [
            .plainText,
            UTType(filenameExtension: "md") ?? .plainText,
            .json,
            .pdf,
            UTType(filenameExtension: "docx") ?? UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
        ]
    }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum ConversationExportBuilder {
    static let signedTranscriptSchema = "near-private-chat-transcript-v1"
    private static let signedTranscriptCanonicalization = "near-private-chat-jcs-v1"
    private static let hashPrefix = "sha256:"

    static func filename(for conversation: ConversationSummary?, format: ConversationExportFormat) -> String {
        let rawTitle = conversation?.title ?? "NEAR Private Chat"
        let cleaned = rawTitle
            .replacingOccurrences(of: #"[^A-Za-z0-9._ -]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "near-private-chat" : cleaned
        return "\(String(base.prefix(64))).\(format.fileExtension)"
    }

    static func document(
        for conversation: ConversationSummary?,
        messages: [ChatMessage],
        format: ConversationExportFormat,
        signedContext: SignedTranscriptExportContext = .defaults
    ) throws -> ConversationExportDocument {
        switch format {
        case .text, .markdown:
            return ConversationExportDocument(data: Data(transcriptText(conversation: conversation, messages: messages).utf8))
        case .json:
            let payload = ConversationExportPayload(conversation: conversation, messages: messages)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return ConversationExportDocument(data: try encoder.encode(payload))
        case .signedJSON:
            return ConversationExportDocument(
                data: try signedTranscriptData(
                    conversation: conversation,
                    messages: messages,
                    context: signedContext
                )
            )
        case .pdf:
            #if canImport(UIKit)
            return ConversationExportDocument(data: pdfData(conversation: conversation, messages: messages))
            #else
            return ConversationExportDocument(data: Data(transcriptText(conversation: conversation, messages: messages).utf8))
            #endif
        case .docx:
            return ConversationExportDocument(data: try docxData(markdown: transcriptText(conversation: conversation, messages: messages)))
        }
    }

    static func selectedAnswerDocument(
        for conversation: ConversationSummary?,
        messages: [ChatMessage],
        answerID: String,
        format: ConversationExportFormat
    ) throws -> ConversationExportDocument {
        let answer = try selectedAnswer(in: messages, answerID: answerID)

        switch format {
        case .text, .markdown:
            return ConversationExportDocument(data: Data(selectedAnswerMarkdown(conversation: conversation, answer: answer).utf8))
        case .pdf:
            #if canImport(UIKit)
            return ConversationExportDocument(data: pdfData(markdown: selectedAnswerMarkdown(conversation: conversation, answer: answer)))
            #else
            return ConversationExportDocument(data: Data(selectedAnswerMarkdown(conversation: conversation, answer: answer).utf8))
            #endif
        case .docx:
            return ConversationExportDocument(data: try docxData(markdown: selectedAnswerMarkdown(conversation: conversation, answer: answer)))
        case .json, .signedJSON:
            throw ConversationExportError.unsupportedSelectedAnswerFormat(format.fileExtension)
        }
    }

    static func selectedAnswerMarkdown(
        conversation: ConversationSummary?,
        messages: [ChatMessage],
        answerID: String
    ) throws -> String {
        try selectedAnswerMarkdown(conversation: conversation, answer: selectedAnswer(in: messages, answerID: answerID))
    }

    static func transcriptText(conversation: ConversationSummary?, messages: [ChatMessage]) -> String {
        var lines: [String] = [
            "# \(conversation?.title ?? "NEAR Private Chat")",
            "",
            "Exported: \(ISO8601DateFormatter().string(from: Date()))"
        ]

        if let conversation {
            lines.append("Conversation: \(conversation.id)")
        }

        for message in messages {
            lines.append("")
            lines.append("## \(speaker(for: message))")
            lines.append(message.createdAt.formatted(date: .abbreviated, time: .standard))
            if let model = message.model, message.role == .assistant {
                lines.append("Model: \(model)")
            }
            if let trust = message.trustMetadata, message.role == .assistant {
                lines.append("Route: \(trust.route.provider) · \(trust.route.privacyRoute) · \(trust.route.sourceModeTitle)")
                if let proof = trust.proof {
                    lines.append("Proof: \(proof.badge)")
                }
            }
            if !message.attachments.isEmpty {
                lines.append("Files: \(message.attachments.map(\.name).joined(separator: ", "))")
            }
            if !message.sources.isEmpty {
                lines.append("Sources: \(message.sources.map(\.url).joined(separator: ", "))")
            }
            lines.append("")
            lines.append(message.text)
        }

        return lines.joined(separator: "\n")
    }

    private static func selectedAnswerMarkdown(conversation: ConversationSummary?, answer: ChatMessage) -> String {
        var lines: [String] = [
            "# \(conversation?.title ?? "NEAR Private Chat")",
            "",
            "Exported: \(ISO8601DateFormatter().string(from: Date()))"
        ]

        if let conversation {
            lines.append("Conversation: \(conversation.id)")
        }

        lines.append("")
        lines.append("## Answer")
        lines.append(answer.createdAt.formatted(date: .abbreviated, time: .standard))
        if let model = answer.model {
            lines.append("Model: \(model)")
        }
        if let trust = answer.trustMetadata {
            lines.append("Route: \(trust.route.provider) · \(trust.route.privacyRoute) · \(trust.route.sourceModeTitle)")
            if let proof = trust.proof {
                lines.append("Proof: \(proof.badge)")
            }
        }
        if !answer.attachments.isEmpty {
            lines.append("Files: \(answer.attachments.map(\.name).joined(separator: ", "))")
        }
        if !answer.sources.isEmpty {
            lines.append("Sources: \(answer.sources.map(\.url).joined(separator: ", "))")
        }
        lines.append("")
        lines.append(answer.text)
        return lines.joined(separator: "\n")
    }

    private static func selectedAnswer(in messages: [ChatMessage], answerID: String) throws -> ChatMessage {
        guard let answer = messages.first(where: { $0.id == answerID }) else {
            throw ConversationExportError.answerNotFound
        }
        guard answer.role == .assistant else {
            throw ConversationExportError.selectedMessageIsNotAnswer
        }
        return answer
    }

    static func signedTranscriptData(
        conversation: ConversationSummary?,
        messages: [ChatMessage],
        context: SignedTranscriptExportContext = .defaults,
        exportedAt: Date = Date()
    ) throws -> Data {
        let route = signedRoute(context: context)
        let messagePayloads = messages.map { signedMessage($0, fallbackRoute: route, context: context) }
        let messagesWithHashes = messagePayloads.map { message -> CanonicalJSON in
            let hash = sha256Digest(message.removingKey("hash").stableString)
            return message.setting("hash", to: .string(hash))
        }

        let hashesWithoutTranscriptHash: CanonicalJSON = .object([
            "canonicalization": .string(signedTranscriptCanonicalization),
            "message_hash_algorithm": .string("sha256"),
            "transcript_hash_algorithm": .string("sha256")
        ])
        var unsignedTranscript = signedTranscriptBase(
            conversation: conversation,
            route: route,
            context: context,
            messages: messagesWithHashes,
            hashes: hashesWithoutTranscriptHash,
            exportedAt: exportedAt
        )

        let transcriptHash = sha256Digest(unsignedTranscript.removingTranscriptHash().stableString)
        let hashes = hashesWithoutTranscriptHash.setting("transcript_hash", to: .string(transcriptHash))
        unsignedTranscript = signedTranscriptBase(
            conversation: conversation,
            route: route,
            context: context,
            messages: messagesWithHashes,
            hashes: hashes,
            exportedAt: exportedAt
        )

        let signingIdentity = try SignedTranscriptSigningIdentity.loadOrCreate()
        let publicKeyPEM = pemEncodedEd25519PublicKey(signingIdentity.publicKey.rawRepresentation)
        let signature = try signingIdentity.privateKey.signature(
            for: Data("\(signedTranscriptSchema)\n\(transcriptHash)".utf8)
        )
        let keyID = "device-ed25519:\(sha256Digest(publicKeyPEM).dropFirst(hashPrefix.count).prefix(24))"

        let signatureObject: CanonicalJSON = .object([
            "algorithm": .string("ed25519"),
            "key_id": .string(String(keyID)),
            "key_scope": .string("device-keychain"),
            "public_key_pem": .string(publicKeyPEM),
            "signed_payload": .string("schema-and-transcript-hash"),
            "signature": .string(signature.base64EncodedString())
        ])

        let signedTranscript = unsignedTranscript.setting("signature", to: signatureObject)
        return try JSONSerialization.data(
            withJSONObject: signedTranscript.foundationObject,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func speaker(for message: ChatMessage) -> String {
        switch message.role {
        case .user: "You"
        case .assistant: message.model?.split(separator: "/").last.map(String.init) ?? "Assistant"
        case .system: "System"
        }
    }

    private static func signedTranscriptBase(
        conversation: ConversationSummary?,
        route: CanonicalJSON,
        context: SignedTranscriptExportContext,
        messages: [CanonicalJSON],
        hashes: CanonicalJSON,
        exportedAt: Date
    ) -> CanonicalJSON {
        .object([
            "schema": .string(signedTranscriptSchema),
            "schema_version": .number(1),
            "exported_at": .string(isoString(exportedAt)),
            "exporter": .object([
                "app": .string("NEAR Private Chat iOS"),
                "platform": .string("ios"),
                "version": .string(appVersionString())
            ]),
            "conversation": signedConversation(conversation, ownerHash: context.ownerHash),
            "route": route,
            "attestation": signedAttestation(context.attestationSnapshot),
            "messages": .array(messages),
            "hashes": hashes
        ])
    }

    private static func signedConversation(_ conversation: ConversationSummary?, ownerHash: String?) -> CanonicalJSON {
        var values: [String: CanonicalJSON] = [
            "id": .string(conversation?.id ?? "local-\(UUID().uuidString)"),
            "title": .string(conversation?.title ?? "NEAR Private Chat")
        ]
        if let createdAt = conversation?.createdAt {
            values["created_at"] = .string(isoString(Date(timeIntervalSince1970: createdAt)))
        }
        if let ownerHash {
            values["owner_hash"] = .string(ownerHash)
        }
        return .object(values)
    }

    private static func signedRoute(context: SignedTranscriptExportContext) -> CanonicalJSON {
        var values: [String: CanonicalJSON] = [
            "provider": .string(context.provider),
            "privacy_route": .string(context.privacyRoute),
            "source_mode": .string(context.sourceMode),
            "web_search": .bool(context.webSearchEnabled),
            "scope": .string("export_context_default")
        ]
        if let projectID = context.projectID {
            values["project_id_hash"] = .string(sha256Digest(projectID))
        }
        return .object(values)
    }

    private static func signedAttestation(_ snapshot: AttestationSnapshot?) -> CanonicalJSON {
        guard let snapshot else {
            return .object([
                "status": .string("unavailable"),
                "freshness": .string("unavailable"),
                "warning": .string("No attestation snapshot was available when this transcript was exported.")
            ])
        }

        var values: [String: CanonicalJSON] = [
            "status": .string("available"),
            "nonce": .string(snapshot.nonce),
            "report_hash": .string(sha256Digest(snapshot.prettyJSON)),
            "fetched_at": .string(isoString(snapshot.fetchedAt)),
            "freshness": .string(AttestationFreshness.classify(attestedAt: snapshot.fetchedAt).shortLabel)
        ]
        if !snapshot.coveredModelIDs.isEmpty {
            values["covered_model_count"] = .number(snapshot.coveredModelIDs.count)
            values["covered_models_hash"] = .string(sha256Digest(snapshot.coveredModelIDs.joined(separator: "\n")))
        }
        if let model = snapshot.model, snapshot.modelAttestationCount > 0 {
            let coveredModels = snapshot.coveredModelIDs.isEmpty ? model : snapshot.coveredModelIDs.joined(separator: ",")
            values["model_attestation_hash"] = .string(sha256Digest("\(coveredModels):\(snapshot.modelAttestationCount):\(snapshot.prettyJSON)"))
        }
        if let address = snapshot.chatGatewayAddress ?? snapshot.cloudGatewayAddress {
            values["gateway_signing_address"] = .string(address)
        }
        return .object(values)
    }

    private static func signedMessage(_ message: ChatMessage, fallbackRoute: CanonicalJSON, context: SignedTranscriptExportContext) -> CanonicalJSON {
        .object([
            "id": .string(message.id),
            "role": .string(message.role.rawValue),
            "created_at": .string(isoString(message.createdAt)),
            "content": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(message.text)
                ])
            ]),
            "model_id": message.model.map(CanonicalJSON.string) ?? .null,
            "response_id": message.responseID.map(CanonicalJSON.string) ?? .null,
            "route": signedRoute(for: message, fallbackRoute: fallbackRoute, context: context),
            "trust": signedTrust(message.trustMetadata),
            "sources": .array(message.sources.map(signedSource)),
            "attachments": .array(message.attachments.map(signedAttachment))
        ])
    }

    private static func signedRoute(for message: ChatMessage, fallbackRoute: CanonicalJSON, context: SignedTranscriptExportContext) -> CanonicalJSON {
        if let route = message.trustMetadata?.route {
            return signedRoute(route, context: context)
        }

        guard message.role == .assistant,
              let modelID = message.model?.trimmingCharacters(in: .whitespacesAndNewlines),
              !modelID.isEmpty else {
            return fallbackRoute.setting("scope", to: .string("message_default"))
        }

        var provider: String
        var privacyRoute: String
        if modelID == ModelOption.llmCouncilSynthesisModelID {
            provider = "llm-council"
            privacyRoute = "multi-model-synthesis"
        } else {
            switch RoutePlanner.routeKind(forModelID: modelID) {
            case .nearPrivate:
                provider = "near-private"
                privacyRoute = "tee-private"
            case .nearCloud:
                provider = "near-cloud"
                privacyRoute = "external-cloud"
            case .ironclawMobile:
                provider = "ironclaw-mobile"
                privacyRoute = "phone-agent"
            case .ironclawHosted:
                provider = "ironclaw-hosted"
                privacyRoute = "hosted-agent"
            }
        }

        var values: [String: CanonicalJSON] = [
            "provider": .string(provider),
            "privacy_route": .string(privacyRoute),
            "source_mode": .string(context.sourceMode),
            "web_search": .bool(!message.sources.isEmpty || context.webSearchEnabled),
            "scope": .string("message_model"),
            "derived_from_model_id": .string(modelID)
        ]
        if let projectID = context.projectID {
            values["project_id_hash"] = .string(sha256Digest(projectID))
        }
        return .object(values)
    }

    private static func signedRoute(_ route: MessageRouteMetadata, context: SignedTranscriptExportContext) -> CanonicalJSON {
        var values: [String: CanonicalJSON] = [
            "provider": .string(route.provider),
            "privacy_route": .string(route.privacyRoute),
            "source_mode": .string(route.sourceMode),
            "source_mode_title": .string(route.sourceModeTitle),
            "web_search": .bool(route.webSearchEnabled),
            "research_mode": .bool(route.researchModeEnabled),
            "project_context_included": .bool(route.projectContextIncluded),
            "scope": .string("message_captured"),
            "captured_at": .string(isoString(route.capturedAt))
        ]
        if let modelID = route.modelID {
            values["derived_from_model_id"] = .string(modelID)
        }
        if let projectID = context.projectID, route.projectContextIncluded {
            values["project_id_hash"] = .string(sha256Digest(projectID))
        }
        return .object(values)
    }

    private static func signedTrust(_ trust: MessageTrustMetadata?) -> CanonicalJSON {
        guard let trust else { return .null }
        var values: [String: CanonicalJSON] = [
            "captured_at": .string(isoString(trust.capturedAt)),
            "route": .object([
                "provider": .string(trust.route.provider),
                "privacy_route": .string(trust.route.privacyRoute),
                "route_kind": .string(trust.route.routeKind),
                "source_mode": .string(trust.route.sourceMode),
                "web_search": .bool(trust.route.webSearchEnabled),
                "research_mode": .bool(trust.route.researchModeEnabled),
                "project_context_included": .bool(trust.route.projectContextIncluded)
            ])
        ]
        if let proof = trust.proof {
            var proofValues: [String: CanonicalJSON] = [
                "state": .string(proof.state.rawValue),
                "title": .string(proof.title),
                "badge": .string(proof.badge),
                "captured_at": .string(isoString(proof.capturedAt)),
                "covered_model_count": .number(proof.coveredModelCount)
            ]
            if let freshness = proof.freshness {
                proofValues["freshness"] = .string(freshness)
            }
            if let reportHash = proof.reportHash {
                proofValues["report_hash"] = .string(reportHash)
            }
            if let coversSelectedModel = proof.coversSelectedModel {
                proofValues["covers_selected_model"] = .bool(coversSelectedModel)
            }
            values["proof"] = .object(proofValues)
        }
        return .object(values)
    }

    private static func signedSource(_ source: WebSearchSource) -> CanonicalJSON {
        var values: [String: CanonicalJSON] = [
            "url": .string(source.url)
        ]
        if let title = source.title {
            values["title"] = .string(title)
        }
        if let publishedAt = source.publishedAt {
            values["published_at"] = .string(publishedAt)
        }
        return .object(values)
    }

    private static func signedAttachment(_ attachment: ChatAttachment) -> CanonicalJSON {
        var values: [String: CanonicalJSON] = [
            "id": .string(attachment.id),
            "name": .string(attachment.name),
            "kind": .string(attachment.kind)
        ]
        if let bytes = attachment.bytes {
            values["bytes"] = .number(bytes)
        }
        return .object(values)
    }

    private static func sha256Digest(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return hashPrefix + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func pemEncodedEd25519PublicKey(_ rawPublicKey: Data) -> String {
        let spkiPrefix = Data([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00])
        let der = spkiPrefix + rawPublicKey
        let wrapped = der.base64EncodedString()
            .chunked(every: 64)
            .joined(separator: "\n")
        return """
        -----BEGIN PUBLIC KEY-----
        \(wrapped)
        -----END PUBLIC KEY-----

        """
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func appVersionString() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (.some(version), .some(build)):
            return "\(version) (\(build))"
        case let (.some(version), .none):
            return version
        case let (.none, .some(build)):
            return build
        case (.none, .none):
            return "local"
        }
    }

    #if canImport(UIKit)
    private static func pdfData(conversation: ConversationSummary?, messages: [ChatMessage]) -> Data {
        pdfData(markdown: transcriptText(conversation: conversation, messages: messages))
    }

    private static func pdfData(markdown text: String) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 44
        let contentWidth = pageRect.width - margin * 2
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let blocks = MarkdownBlock.parse(text)

        return renderer.pdfData { context in
            context.beginPage()
            var y = margin

            for block in blocks {
                drawPDFBlock(
                    block,
                    context: context,
                    pageRect: pageRect,
                    margin: margin,
                    contentWidth: contentWidth,
                    y: &y
                )
            }
        }
    }

    private static func drawPDFBlock(
        _ block: MarkdownBlock,
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        margin: CGFloat,
        contentWidth: CGFloat,
        y: inout CGFloat
    ) {
        switch block.kind {
        case let .paragraph(text):
            drawPDFInlineText(
                text,
                baseFont: .systemFont(ofSize: 10.5),
                color: .black,
                context: context,
                pageRect: pageRect,
                margin: margin,
                x: margin,
                width: contentWidth,
                y: &y,
                spacingAfter: 6
            )
        case let .heading(text, level):
            let fontSize: CGFloat = level == 1 ? 22 : (level == 2 ? 15 : 12.5)
            let color = level == 1 ? UIColor.black : UIColor(red: 0.0, green: 0.42, blue: 0.75, alpha: 1.0)
            drawPDFInlineText(
                text,
                baseFont: .systemFont(ofSize: fontSize, weight: .bold),
                color: color,
                context: context,
                pageRect: pageRect,
                margin: margin,
                x: margin,
                width: contentWidth,
                y: &y,
                spacingAfter: level == 1 ? 14 : 8
            )
        case let .list(items):
            for item in items {
                let indent = CGFloat(item.level) * 18
                let marker: String
                switch item.marker {
                case .unordered:
                    marker = "•"
                case let .ordered(number):
                    marker = "\(number)."
                }
                let markerFont = UIFont.systemFont(ofSize: 10.5, weight: .medium)
                let markerText = NSAttributedString(
                    string: marker,
                    attributes: pdfAttributes(font: markerFont, color: .darkGray)
                )
                let markerWidth: CGFloat = 24
                let itemWidth = contentWidth - indent - markerWidth
                let itemText = pdfInlineAttributedString(item.text, baseFont: .systemFont(ofSize: 10.5), color: .black)
                let textHeight = pdfHeight(for: itemText, width: itemWidth)
                let height = max(textHeight, 13)
                ensurePDFSpace(height, context: context, pageRect: pageRect, margin: margin, y: &y)
                markerText.draw(
                    with: CGRect(x: margin + indent, y: y, width: markerWidth - 4, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                itemText.draw(
                    with: CGRect(x: margin + indent + markerWidth, y: y, width: itemWidth, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                y += height + 4
            }
            y += 2
        case let .quote(text):
            let quoteX = margin + 12
            let barRect = CGRect(x: margin, y: y, width: 3, height: 1)
            let attributed = pdfInlineAttributedString(
                text,
                baseFont: .italicSystemFont(ofSize: 10.5),
                color: .darkGray
            )
            let height = max(pdfHeight(for: attributed, width: contentWidth - 18), 14)
            ensurePDFSpace(height, context: context, pageRect: pageRect, margin: margin, y: &y)
            UIColor(red: 0.0, green: 0.42, blue: 0.75, alpha: 0.65).setFill()
            UIBezierPath(rect: CGRect(x: barRect.minX, y: y, width: barRect.width, height: height)).fill()
            attributed.draw(
                with: CGRect(x: quoteX, y: y, width: contentWidth - 18, height: height),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
            y += height + 8
        case let .code(code, _):
            drawPDFCodeBlock(
                code,
                context: context,
                pageRect: pageRect,
                margin: margin,
                contentWidth: contentWidth,
                y: &y
            )
        case let .math(formula):
            drawPDFCodeBlock(
                mathBlockSource(formula),
                context: context,
                pageRect: pageRect,
                margin: margin,
                contentWidth: contentWidth,
                y: &y
            )
        case .divider:
            ensurePDFSpace(12, context: context, pageRect: pageRect, margin: margin, y: &y)
            UIColor.lightGray.setStroke()
            UIBezierPath(rect: CGRect(x: margin, y: y + 5, width: contentWidth, height: 1)).stroke()
            y += 14
        case let .table(rows):
            drawPDFTable(
                rows,
                context: context,
                pageRect: pageRect,
                margin: margin,
                contentWidth: contentWidth,
                y: &y
            )
        }
    }

    private static func drawPDFInlineText(
        _ text: String,
        baseFont: UIFont,
        color: UIColor,
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        margin: CGFloat,
        x: CGFloat,
        width: CGFloat,
        y: inout CGFloat,
        spacingAfter: CGFloat
    ) {
        let attributed = pdfInlineAttributedString(text.isEmpty ? " " : text, baseFont: baseFont, color: color)
        let height = max(pdfHeight(for: attributed, width: width), 12)
        ensurePDFSpace(height, context: context, pageRect: pageRect, margin: margin, y: &y)
        attributed.draw(
            with: CGRect(x: x, y: y, width: width, height: height),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        y += height + spacingAfter
    }

    private static func drawPDFCodeBlock(
        _ code: String,
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        margin: CGFloat,
        contentWidth: CGFloat,
        y: inout CGFloat
    ) {
        let font = UIFont(name: "Menlo-Regular", size: 9.5) ?? .monospacedSystemFont(ofSize: 9.5, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2
        let attributed = NSAttributedString(
            string: code.isEmpty ? " " : code,
            attributes: [
                .font: font,
                .foregroundColor: UIColor.black,
                .paragraphStyle: paragraph
            ]
        )
        let inset: CGFloat = 8
        let height = max(pdfHeight(for: attributed, width: contentWidth - inset * 2) + inset * 2, 28)
        ensurePDFSpace(height, context: context, pageRect: pageRect, margin: margin, y: &y)
        UIColor(white: 0.96, alpha: 1.0).setFill()
        UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: contentWidth, height: height), cornerRadius: 6).fill()
        attributed.draw(
            with: CGRect(x: margin + inset, y: y + inset, width: contentWidth - inset * 2, height: height - inset * 2),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        y += height + 8
    }

    private static func drawPDFTable(
        _ rows: [[String]],
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        margin: CGFloat,
        contentWidth: CGFloat,
        y: inout CGFloat
    ) {
        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return }
        let columnWidths = pdfTableColumnWidths(rows: rows, columnCount: columnCount, contentWidth: contentWidth)
        let cellPadding: CGFloat = 6

        for (rowIndex, row) in rows.enumerated() {
            let cellTexts = (0..<columnCount).map { columnIndex -> NSAttributedString in
                let text = row.indices.contains(columnIndex) ? row[columnIndex] : ""
                let font = rowIndex == 0 ? UIFont.systemFont(ofSize: 9.5, weight: .semibold) : UIFont.systemFont(ofSize: 9.5)
                return pdfInlineAttributedString(text, baseFont: font, color: .black)
            }
            let rowHeight = max(
                cellTexts.enumerated().map { index, value in
                    pdfHeight(for: value, width: columnWidths[index] - cellPadding * 2) + cellPadding * 2
                }.max() ?? 24,
                24
            )
            ensurePDFSpace(rowHeight, context: context, pageRect: pageRect, margin: margin, y: &y)

            var x = margin
            for columnIndex in 0..<columnCount {
                let rect = CGRect(x: x, y: y, width: columnWidths[columnIndex], height: rowHeight)
                (rowIndex == 0 ? UIColor(red: 0.92, green: 0.96, blue: 1.0, alpha: 1.0) : UIColor.white).setFill()
                UIBezierPath(rect: rect).fill()
                UIColor(white: 0.78, alpha: 1.0).setStroke()
                UIBezierPath(rect: rect).stroke()
                cellTexts[columnIndex].draw(
                    with: rect.insetBy(dx: cellPadding, dy: cellPadding),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                x += columnWidths[columnIndex]
            }
            y += rowHeight
        }
        y += 10
    }

    private static func pdfTableColumnWidths(rows: [[String]], columnCount: Int, contentWidth: CGFloat) -> [CGFloat] {
        let font = UIFont.systemFont(ofSize: 9.5)
        let rawWidths = (0..<columnCount).map { columnIndex -> CGFloat in
            let measured = rows.map { row -> CGFloat in
                guard row.indices.contains(columnIndex) else { return 48 }
                return ceil((row[columnIndex] as NSString).size(withAttributes: [.font: font]).width) + 18
            }.max() ?? 64
            return min(max(measured, 64), 190)
        }
        let total = rawWidths.reduce(0, +)
        guard total > contentWidth else { return rawWidths }
        return rawWidths.map { max(48, $0 / total * contentWidth) }
    }

    private static func ensurePDFSpace(
        _ height: CGFloat,
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        margin: CGFloat,
        y: inout CGFloat
    ) {
        if y + height > pageRect.height - margin {
            context.beginPage()
            y = margin
        }
    }

    private static func pdfHeight(for attributed: NSAttributedString, width: CGFloat) -> CGFloat {
        attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).integral.height
    }

    private static func pdfInlineAttributedString(_ text: String, baseFont: UIFont, color: UIColor) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for segment in inlineExportSegments(in: text) {
            let font = pdfFont(baseFont: baseFont, segment: segment)
            var attributes = pdfAttributes(font: font, color: segment.url == nil ? color : UIColor.systemBlue)
            if segment.url != nil {
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            if segment.isCode {
                attributes[.backgroundColor] = UIColor(white: 0.94, alpha: 1.0)
            }
            output.append(NSAttributedString(string: segment.text, attributes: attributes))
        }
        return output
    }

    private static func pdfFont(baseFont: UIFont, segment: InlineExportSegment) -> UIFont {
        if segment.isCode {
            return UIFont(name: "Menlo-Regular", size: baseFont.pointSize) ??
                .monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular)
        }

        var traits: UIFontDescriptor.SymbolicTraits = []
        if segment.isBold { traits.insert(.traitBold) }
        if segment.isItalic { traits.insert(.traitItalic) }
        guard !traits.isEmpty,
              let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) else {
            return baseFont
        }
        return UIFont(descriptor: descriptor, size: baseFont.pointSize)
    }

    private static func pdfAttributes(font: UIFont, color: UIColor) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2

        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    }
    #endif

    private static func docxData(markdown: String) throws -> Data {
        try MinimalZIPArchive(entries: [
            MinimalZIPArchive.Entry(path: "[Content_Types].xml", data: Data(docxContentTypesXML.utf8)),
            MinimalZIPArchive.Entry(path: "_rels/.rels", data: Data(docxPackageRelationshipsXML.utf8)),
            MinimalZIPArchive.Entry(path: "word/_rels/document.xml.rels", data: Data(docxDocumentRelationshipsXML.utf8)),
            MinimalZIPArchive.Entry(path: "word/document.xml", data: Data(docxDocumentXML(markdown: markdown).utf8)),
            MinimalZIPArchive.Entry(path: "word/numbering.xml", data: Data(docxNumberingXML.utf8))
        ]).data()
    }

    private static let docxContentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/></Types>
    """

    private static let docxPackageRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
    """

    private static let docxDocumentRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdNumbering" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/></Relationships>
    """

    private static var docxNumberingXML: String {
        let bulletGlyphs = ["•", "◦", "▪"]
        let bullets = (0...8).map { level in
            let left = 720 + level * 360
            let glyph = bulletGlyphs[level % bulletGlyphs.count]
            return """
            <w:lvl w:ilvl="\(level)"><w:numFmt w:val="bullet"/><w:lvlText w:val="\(glyph)"/><w:pPr><w:ind w:left="\(left)" w:hanging="360"/></w:pPr></w:lvl>
            """
        }.joined()
        let orderedFormats = ["decimal", "lowerLetter", "lowerRoman"]
        let ordered = (0...8).map { level in
            let left = 720 + level * 360
            return """
            <w:lvl w:ilvl="\(level)"><w:numFmt w:val="\(orderedFormats[level % orderedFormats.count])"/><w:lvlText w:val="%\(level + 1)."/><w:pPr><w:ind w:left="\(left)" w:hanging="360"/></w:pPr></w:lvl>
            """
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="hybridMultilevel"/>\(bullets)</w:abstractNum><w:abstractNum w:abstractNumId="2"><w:multiLevelType w:val="hybridMultilevel"/>\(ordered)</w:abstractNum><w:num w:numId="1"><w:abstractNumId w:val="1"/></w:num><w:num w:numId="2"><w:abstractNumId w:val="2"/></w:num></w:numbering>
        """
    }

    private static func docxDocumentXML(markdown: String) -> String {
        let body = MarkdownBlock.parse(markdown)
            .map(docxBlockXML)
            .joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body>\(body)<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body></w:document>
        """
    }

    private static func docxBlockXML(_ block: MarkdownBlock) -> String {
        switch block.kind {
        case let .paragraph(text):
            return docxInlineParagraphXML(text, paragraphProperties: "<w:pPr><w:spacing w:after=\"100\"/></w:pPr>")
        case let .heading(text, level):
            let style = min(max(level, 1), 3)
            let size = style == 1 ? "32" : (style == 2 ? "26" : "23")
            return docxInlineParagraphXML(
                text,
                paragraphProperties: "<w:pPr><w:pStyle w:val=\"Heading\(style)\"/><w:spacing w:before=\"160\" w:after=\"120\"/></w:pPr>",
                forcedRunProperties: "<w:b/><w:sz w:val=\"\(size)\"/>"
            )
        case let .list(items):
            return items.map(docxListItemXML).joined()
        case let .quote(text):
            return docxInlineParagraphXML(
                text,
                paragraphProperties: "<w:pPr><w:ind w:left=\"360\"/><w:pBdr><w:left w:val=\"single\" w:sz=\"12\" w:space=\"8\" w:color=\"006ABF\"/></w:pBdr></w:pPr>",
                forcedRunProperties: "<w:i/><w:color w:val=\"555555\"/>"
            )
        case let .code(code, _):
            return docxCodeParagraphXML(code)
        case let .math(formula):
            return docxCodeParagraphXML(mathBlockSource(formula))
        case .divider:
            return "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"CCCCCC\"/></w:pBdr></w:pPr></w:p>"
        case let .table(rows):
            return docxTableXML(rows)
        }
    }

    private static func docxInlineParagraphXML(
        _ text: String,
        paragraphProperties: String = "",
        forcedRunProperties: String = ""
    ) -> String {
        "<w:p>\(paragraphProperties)\(docxInlineRunsXML(text, forcedRunProperties: forcedRunProperties))</w:p>"
    }

    private static func docxListItemXML(_ item: MarkdownListItem) -> String {
        let numID: Int
        switch item.marker {
        case .unordered:
            numID = 1
        case .ordered:
            numID = 2
        }
        let level = min(item.level, 8)
        let left = 720 + level * 360
        let paragraphProperties = """
        <w:pPr><w:numPr><w:ilvl w:val="\(level)"/><w:numId w:val="\(numID)"/></w:numPr><w:ind w:left="\(left)" w:hanging="360"/></w:pPr>
        """
        return docxInlineParagraphXML(item.text, paragraphProperties: paragraphProperties)
    }

    private static func docxTableXML(_ rows: [[String]]) -> String {
        let columnCount = rows.map(\.count).max() ?? 0
        guard columnCount > 0 else { return "" }
        let grid = (0..<columnCount)
            .map { _ in "<w:gridCol w:w=\"2400\"/>" }
            .joined()
        let rowXML = rows.enumerated().map { rowIndex, row in
            let cells = (0..<columnCount).map { columnIndex -> String in
                let value = row.indices.contains(columnIndex) ? row[columnIndex] : ""
                let shading = rowIndex == 0 ? "<w:shd w:fill=\"EAF4FF\"/>" : ""
                let runProperties = rowIndex == 0 ? "<w:b/>" : ""
                return """
                <w:tc><w:tcPr><w:tcW w:w="2400" w:type="dxa"/>\(shading)</w:tcPr>\(docxInlineParagraphXML(value, forcedRunProperties: runProperties))</w:tc>
                """
            }.joined()
            return "<w:tr>\(cells)</w:tr>"
        }.joined()
        return """
        <w:tbl><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:color="CCCCCC"/><w:left w:val="single" w:sz="4" w:color="CCCCCC"/><w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/><w:right w:val="single" w:sz="4" w:color="CCCCCC"/><w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/><w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/></w:tblBorders></w:tblPr><w:tblGrid>\(grid)</w:tblGrid>\(rowXML)</w:tbl>
        """
    }

    private static func docxCodeParagraphXML(_ code: String) -> String {
        let lines = (code.isEmpty ? " " : code).components(separatedBy: .newlines)
        let runs = lines.enumerated().map { index, line in
            let lineBreak = index == lines.count - 1 ? "" : "<w:br/>"
            return """
            <w:r><w:rPr><w:rFonts w:ascii="Courier New" w:hAnsi="Courier New"/><w:sz w:val="19"/></w:rPr><w:t xml:space="preserve">\(xmlEscaped(line))</w:t>\(lineBreak)</w:r>
            """
        }.joined()
        return "<w:p><w:pPr><w:shd w:fill=\"F3F4F6\"/><w:spacing w:before=\"100\" w:after=\"120\"/></w:pPr>\(runs)</w:p>"
    }

    private static func docxInlineRunsXML(_ text: String, forcedRunProperties: String = "") -> String {
        let segments = inlineExportSegments(in: text.isEmpty ? " " : text)
        return segments.map { segment in
            let properties = docxRunPropertiesXML(for: segment, forcedRunProperties: forcedRunProperties)
            return "<w:r>\(properties)<w:t xml:space=\"preserve\">\(xmlEscaped(segment.text))</w:t></w:r>"
        }.joined()
    }

    private static func docxRunPropertiesXML(for segment: InlineExportSegment, forcedRunProperties: String) -> String {
        var properties = forcedRunProperties
        if segment.isBold {
            properties += "<w:b/>"
        }
        if segment.isItalic {
            properties += "<w:i/>"
        }
        if segment.isCode {
            properties += "<w:rFonts w:ascii=\"Courier New\" w:hAnsi=\"Courier New\"/><w:shd w:fill=\"F3F4F6\"/>"
        }
        if segment.url != nil {
            properties += "<w:color w:val=\"0563C1\"/><w:u w:val=\"single\"/>"
        }
        return properties.isEmpty ? "" : "<w:rPr>\(properties)</w:rPr>"
    }

    private static func inlineExportSegments(in text: String) -> [InlineExportSegment] {
        var segments: [InlineExportSegment] = []
        var plain = ""
        var index = text.startIndex

        func flushPlain() {
            guard !plain.isEmpty else { return }
            segments.append(InlineExportSegment(text: plain))
            plain = ""
        }

        while index < text.endIndex {
            if text[index] == "`",
               let closing = text[text.index(after: index)...].firstIndex(of: "`") {
                flushPlain()
                let contentStart = text.index(after: index)
                segments.append(InlineExportSegment(text: String(text[contentStart..<closing]), isCode: true))
                index = text.index(after: closing)
                continue
            }

            if text[index...].hasPrefix("**"),
               let closing = text.range(of: "**", range: text.index(index, offsetBy: 2)..<text.endIndex) {
                flushPlain()
                let contentStart = text.index(index, offsetBy: 2)
                segments.append(InlineExportSegment(text: String(text[contentStart..<closing.lowerBound]), isBold: true))
                index = closing.upperBound
                continue
            }

            if text[index] == "*",
               let closing = text[text.index(after: index)...].firstIndex(of: "*") {
                flushPlain()
                let contentStart = text.index(after: index)
                segments.append(InlineExportSegment(text: String(text[contentStart..<closing]), isItalic: true))
                index = text.index(after: closing)
                continue
            }

            if let link = markdownLink(at: index, in: text) {
                flushPlain()
                segments.append(InlineExportSegment(text: "\(link.label) (\(link.url))", url: link.url))
                index = link.end
                continue
            }

            plain.append(text[index])
            index = text.index(after: index)
        }

        flushPlain()
        return segments.isEmpty ? [InlineExportSegment(text: text)] : segments
    }

    private static func markdownLink(
        at index: String.Index,
        in text: String
    ) -> (label: String, url: String, end: String.Index)? {
        guard text[index] == "[" else { return nil }
        guard let labelEnd = text[text.index(after: index)...].firstIndex(of: "]") else { return nil }
        let openParen = text.index(after: labelEnd)
        guard openParen < text.endIndex, text[openParen] == "(" else { return nil }
        guard let closeParen = text[text.index(after: openParen)...].firstIndex(of: ")") else { return nil }
        let label = String(text[text.index(after: index)..<labelEnd])
        let url = String(text[text.index(after: openParen)..<closeParen])
        guard !label.isEmpty, !url.isEmpty else { return nil }
        return (label, url, text.index(after: closeParen))
    }

    private static func mathBlockSource(_ formula: String) -> String {
        formula.contains("\n") ? "$$\n\(formula)\n$$" : "$$\(formula)$$"
    }

    static func xmlEscaped(_ value: String) -> String {
        // Drop scalars XML 1.0 forbids even as entities (C0 controls except
        // tab/newline/CR, plus U+FFFE/U+FFFF). A literal control char from
        // model output or a pasted attachment otherwise produces a .docx Word
        // refuses to open ("unreadable content").
        let cleaned = String(String.UnicodeScalarView(value.unicodeScalars.filter { scalar in
            let v = scalar.value
            if v == 0x9 || v == 0xA || v == 0xD { return true }
            if v < 0x20 { return false }
            if v == 0xFFFE || v == 0xFFFF { return false }
            return true
        }))
        return cleaned
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

private struct InlineExportSegment {
    var text: String
    var isBold: Bool = false
    var isItalic: Bool = false
    var isCode: Bool = false
    var url: String?
}

enum ConversationExportError: LocalizedError, Equatable {
    case answerNotFound
    case selectedMessageIsNotAnswer
    case unsupportedSelectedAnswerFormat(String)

    var errorDescription: String? {
        switch self {
        case .answerNotFound:
            return "Selected answer not found."
        case .selectedMessageIsNotAnswer:
            return "Only assistant answers can be exported this way."
        case let .unsupportedSelectedAnswerFormat(fileExtension):
            return "Selected-answer export is not available as .\(fileExtension)."
        }
    }
}

private struct MinimalZIPArchive {
    struct Entry {
        var path: String
        var data: Data
    }

    var entries: [Entry]

    func data() throws -> Data {
        var archive = Data()
        var centralDirectory = Data()

        for entry in entries {
            let localHeaderOffset = UInt32(archive.count)
            let pathData = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)

            archive.appendLittleEndianUInt32(0x04034b50)
            archive.appendLittleEndianUInt16(20)
            archive.appendLittleEndianUInt16(0)
            archive.appendLittleEndianUInt16(0)
            archive.appendLittleEndianUInt16(0)
            archive.appendLittleEndianUInt16(0)
            archive.appendLittleEndianUInt32(crc)
            archive.appendLittleEndianUInt32(size)
            archive.appendLittleEndianUInt32(size)
            archive.appendLittleEndianUInt16(UInt16(pathData.count))
            archive.appendLittleEndianUInt16(0)
            archive.append(pathData)
            archive.append(entry.data)

            centralDirectory.appendLittleEndianUInt32(0x02014b50)
            centralDirectory.appendLittleEndianUInt16(20)
            centralDirectory.appendLittleEndianUInt16(20)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt32(crc)
            centralDirectory.appendLittleEndianUInt32(size)
            centralDirectory.appendLittleEndianUInt32(size)
            centralDirectory.appendLittleEndianUInt16(UInt16(pathData.count))
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt16(0)
            centralDirectory.appendLittleEndianUInt32(0)
            centralDirectory.appendLittleEndianUInt32(localHeaderOffset)
            centralDirectory.append(pathData)
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.appendLittleEndianUInt32(0x06054b50)
        archive.appendLittleEndianUInt16(0)
        archive.appendLittleEndianUInt16(0)
        archive.appendLittleEndianUInt16(UInt16(entries.count))
        archive.appendLittleEndianUInt16(UInt16(entries.count))
        archive.appendLittleEndianUInt32(UInt32(centralDirectory.count))
        archive.appendLittleEndianUInt32(centralDirectoryOffset)
        archive.appendLittleEndianUInt16(0)
        return archive
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                let mask = 0 &- (crc & 1)
                crc = (crc >> 1) ^ (0xedb8_8320 & mask)
            }
        }
        return ~crc
    }
}

private extension Data {
    mutating func appendLittleEndianUInt16(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendLittleEndianUInt32(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}

struct SignedTranscriptExportContext: Hashable {
    var provider: String
    var privacyRoute: String
    var sourceMode: String
    var webSearchEnabled: Bool
    var projectID: String?
    var ownerHash: String?
    var attestationSnapshot: AttestationSnapshot?

    static let defaults = SignedTranscriptExportContext(
        provider: "near-private",
        privacyRoute: "unknown",
        sourceMode: "auto",
        webSearchEnabled: false,
        projectID: nil,
        ownerHash: nil,
        attestationSnapshot: nil
    )
}

private struct SignedTranscriptSigningIdentity {
    private static let keychainAccount = "signedTranscript.identity.v1"

    let privateKey: Curve25519.Signing.PrivateKey

    var publicKey: Curve25519.Signing.PublicKey {
        privateKey.publicKey
    }

    static func loadOrCreate() throws -> SignedTranscriptSigningIdentity {
        if let storedKeyData = try? KeychainStore.read(Data.self, account: keychainAccount),
           let storedKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: storedKeyData) {
            return SignedTranscriptSigningIdentity(privateKey: storedKey)
        }

        let newKey = Curve25519.Signing.PrivateKey()
        try KeychainStore.save(newKey.rawRepresentation, account: keychainAccount)
        return SignedTranscriptSigningIdentity(privateKey: newKey)
    }
}

private enum CanonicalJSON: Equatable {
    case object([String: CanonicalJSON])
    case array([CanonicalJSON])
    case string(String)
    case number(Int)
    case bool(Bool)
    case null

    var stableString: String {
        switch self {
        case let .object(values):
            let entries = values
                .sorted { $0.key < $1.key }
                .map { "\(Self.quote($0.key)):\($0.value.stableString)" }
                .joined(separator: ",")
            return "{\(entries)}"
        case let .array(values):
            return "[\(values.map(\.stableString).joined(separator: ","))]"
        case let .string(value):
            return Self.quote(value)
        case let .number(value):
            return String(value)
        case let .bool(value):
            return value ? "true" : "false"
        case .null:
            return "null"
        }
    }

    var foundationObject: Any {
        switch self {
        case let .object(values):
            return values.mapValues(\.foundationObject)
        case let .array(values):
            return values.map(\.foundationObject)
        case let .string(value):
            return value
        case let .number(value):
            return value
        case let .bool(value):
            return value
        case .null:
            return NSNull()
        }
    }

    func setting(_ key: String, to value: CanonicalJSON) -> CanonicalJSON {
        guard case var .object(values) = self else { return self }
        values[key] = value
        return .object(values)
    }

    func removingKey(_ key: String) -> CanonicalJSON {
        switch self {
        case let .object(values):
            return .object(
                Dictionary(
                    uniqueKeysWithValues: values
                        .filter { $0.key != key }
                        .map { ($0.key, $0.value.removingKey(key)) }
                )
            )
        case let .array(values):
            return .array(values.map { $0.removingKey(key) })
        case .string, .number, .bool, .null:
            return self
        }
    }

    func removingTranscriptHash() -> CanonicalJSON {
        guard case var .object(values) = self else { return self }
        values.removeValue(forKey: "signature")
        if case var .object(hashes)? = values["hashes"] {
            hashes.removeValue(forKey: "transcript_hash")
            values["hashes"] = .object(hashes)
        }
        return .object(values)
    }

    private static func quote(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value], options: [.withoutEscapingSlashes]),
              let raw = String(data: data, encoding: .utf8),
              raw.count >= 2 else {
            return "\"\""
        }
        return String(raw.dropFirst().dropLast())
    }
}

private extension String {
    func chunked(every size: Int) -> [String] {
        guard size > 0 else { return [self] }
        var chunks: [String] = []
        var index = startIndex
        while index < endIndex {
            let next = self.index(index, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(String(self[index..<next]))
            index = next
        }
        return chunks
    }
}

private struct ConversationExportPayload: Encodable {
    let exportedAt: String
    let conversation: ExportConversation?
    let messages: [ExportMessage]

    init(conversation: ConversationSummary?, messages: [ChatMessage]) {
        exportedAt = ISO8601DateFormatter().string(from: Date())
        self.conversation = conversation.map(ExportConversation.init)
        self.messages = messages.map(ExportMessage.init)
    }
}

private struct ExportConversation: Encodable {
    let id: String
    let title: String
    let createdAt: TimeInterval?

    init(_ conversation: ConversationSummary) {
        id = conversation.id
        title = conversation.title
        createdAt = conversation.createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAt = "created_at"
    }
}

private struct ExportMessage: Encodable {
    let id: String
    let role: String
    let text: String
    let model: String?
    let createdAt: String
    let status: String
    let responseID: String?
    let searchQuery: String?
    let sources: [ExportSource]
    let attachments: [ExportAttachment]
    let trustMetadata: MessageTrustMetadata?

    init(_ message: ChatMessage) {
        id = message.id
        role = message.role.rawValue
        text = message.text
        model = message.model
        createdAt = ISO8601DateFormatter().string(from: message.createdAt)
        status = message.status
        responseID = message.responseID
        searchQuery = message.searchQuery
        sources = message.sources.map(ExportSource.init)
        attachments = message.attachments.map(ExportAttachment.init)
        trustMetadata = message.trustMetadata
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case model
        case createdAt = "created_at"
        case status
        case responseID = "response_id"
        case searchQuery = "search_query"
        case sources
        case attachments
        case trustMetadata = "trust_metadata"
    }
}

private struct ExportSource: Encodable {
    let url: String
    let title: String?
    let publishedAt: String?

    init(_ source: WebSearchSource) {
        url = source.url
        title = source.title
        publishedAt = source.publishedAt
    }

    enum CodingKeys: String, CodingKey {
        case url
        case title
        case publishedAt = "published_at"
    }
}

private struct ExportAttachment: Encodable {
    let id: String
    let name: String
    let kind: String
    let bytes: Int?

    init(_ attachment: ChatAttachment) {
        id = attachment.id
        name = attachment.name
        kind = attachment.kind
        bytes = attachment.bytes
    }
}

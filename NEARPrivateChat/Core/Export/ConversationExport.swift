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

        return renderer.pdfData { context in
            context.beginPage()
            var y = margin

            for rawLine in text.components(separatedBy: .newlines) {
                let line = pdfLineText(rawLine)
                let attributes = pdfAttributes(for: rawLine)
                let drawString = line.isEmpty ? " " : line
                let textRect = (drawString as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                ).integral
                let height = max(textRect.height, rawLine.isEmpty ? 8 : 12)
                if y + height > pageRect.height - margin {
                    context.beginPage()
                    y = margin
                }
                (drawString as NSString).draw(
                    with: CGRect(x: margin, y: y, width: contentWidth, height: height),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attributes,
                    context: nil
                )
                y += height + pdfSpacing(after: rawLine)
            }
        }
    }

    private static func pdfLineText(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^##\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^#\s+"#, with: "", options: .regularExpression)
    }

    private static func pdfAttributes(for line: String) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 2

        let font: UIFont
        let color: UIColor
        if line.hasPrefix("# ") {
            font = .systemFont(ofSize: 22, weight: .bold)
            color = .black
        } else if line.hasPrefix("## ") {
            font = .systemFont(ofSize: 14, weight: .semibold)
            color = UIColor(red: 0.0, green: 0.42, blue: 0.75, alpha: 1.0)
        } else if line.hasPrefix("Exported:") || line.hasPrefix("Conversation:") || line.hasPrefix("Model:") || line.hasPrefix("Files:") || line.hasPrefix("Sources:") {
            font = .systemFont(ofSize: 9.5, weight: .medium)
            color = .darkGray
        } else {
            font = .systemFont(ofSize: 10.5, weight: .regular)
            color = .black
        }

        return [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
    }

    private static func pdfSpacing(after line: String) -> CGFloat {
        if line.hasPrefix("# ") { return 14 }
        if line.hasPrefix("## ") { return 8 }
        return line.isEmpty ? 7 : 4
    }
    #endif

    private static func docxData(markdown: String) throws -> Data {
        try MinimalZIPArchive(entries: [
            MinimalZIPArchive.Entry(path: "[Content_Types].xml", data: Data(docxContentTypesXML.utf8)),
            MinimalZIPArchive.Entry(path: "_rels/.rels", data: Data(docxPackageRelationshipsXML.utf8)),
            MinimalZIPArchive.Entry(path: "word/document.xml", data: Data(docxDocumentXML(markdown: markdown).utf8))
        ]).data()
    }

    private static let docxContentTypesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>
    """

    private static let docxPackageRelationshipsXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>
    """

    private static func docxDocumentXML(markdown: String) -> String {
        let body = markdown
            .components(separatedBy: .newlines)
            .map(docxParagraphXML)
            .joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>\(body)<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body></w:document>
        """
    }

    private static func docxParagraphXML(_ markdownLine: String) -> String {
        let text = docxLineText(markdownLine)
        let escaped = xmlEscaped(text.isEmpty ? " " : text)
        let paragraphProperties = docxParagraphProperties(for: markdownLine)
        let runProperties = docxRunProperties(for: markdownLine)
        return "<w:p>\(paragraphProperties)<w:r>\(runProperties)<w:t xml:space=\"preserve\">\(escaped)</w:t></w:r></w:p>"
    }

    private static func docxLineText(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"^##\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^#\s+"#, with: "", options: .regularExpression)
    }

    private static func docxParagraphProperties(for line: String) -> String {
        if line.hasPrefix("# ") {
            return "<w:pPr><w:spacing w:after=\"280\"/></w:pPr>"
        }
        if line.hasPrefix("## ") {
            return "<w:pPr><w:spacing w:before=\"160\" w:after=\"120\"/></w:pPr>"
        }
        return ""
    }

    private static func docxRunProperties(for line: String) -> String {
        if line.hasPrefix("# ") {
            return "<w:rPr><w:b/><w:sz w:val=\"32\"/></w:rPr>"
        }
        if line.hasPrefix("## ") {
            return "<w:rPr><w:b/><w:color w:val=\"006ABF\"/><w:sz w:val=\"24\"/></w:rPr>"
        }
        return ""
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
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

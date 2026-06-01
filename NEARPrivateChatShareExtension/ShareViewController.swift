import UIKit
import Social
import UniformTypeIdentifiers
import MobileCoreServices

/// "Add to NEAR Private Chat" share extension. Presents the system compose
/// sheet (a free editable preview of the shared text), then writes the text or
/// URL the user shared to a small file in the App Group container. The main app
/// drains that file on its next activation and stages it into the composer - it
/// is never auto-sent.
///
/// The extension intentionally does no networking and links none of the app's
/// model graph beyond the shared `PendingShareStore` / `PendingSharedItem`
/// types it compiles directly.
final class ShareViewController: SLComposeServiceViewController {

    /// Text resolved from the shared attachments (URL or plain text). The
    /// compose sheet seeds its editable field from this; the user can edit
    /// before adding it to the app.
    private var resolvedSharedText: String = ""
    private var resolvedSharedAttachments: [PendingSharedAttachment] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        placeholder = "Add a note before opening NEAR Private Chat..."
        applyAddOpenCopy()
        loadSharedContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyAddOpenCopy()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyAddOpenCopy()
    }

    /// Always allow posting; an empty draft is still a valid "open the app"
    /// gesture, and we fall back to the resolved attachment text.
    override func isContentValid() -> Bool {
        true
    }

    override func didSelectPost() {
        let finalText = stagedText()
        let attachments = resolvedSharedAttachments

        if !finalText.isEmpty || !attachments.isEmpty {
            let item = PendingSharedItem(text: finalText, attachments: attachments)
            PendingShareStore.write(item, to: PendingShareStore.defaultFileURL())
        }

        // Best-effort: bring the host app forward so the staged draft appears
        // immediately. If the responder-chain open is unavailable the app still
        // picks the file up on its next launch/activation.
        openHostApp()

        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        []
    }

    // MARK: - Attachment extraction

    /// Walks the input items and resolves the first URL or text attachment into
    /// `resolvedSharedText`, then seeds the editable compose field with it.
    private func loadSharedContent() {
        let inputItems = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        let attachments = inputItems
            .compactMap { $0.attachments }
            .flatMap { $0 }

        loadSharedAttachments(from: attachments)

        let urlType = UTType.url.identifier
        let textType = UTType.plainText.identifier

        // Prefer a URL provider, then a plain-text provider.
        if let urlProvider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(urlType) }) {
            urlProvider.loadItem(forTypeIdentifier: urlType, options: nil) { [weak self] value, _ in
                let text: String?
                if let url = value as? URL {
                    text = url.absoluteString
                } else if let string = value as? String {
                    text = string
                } else if let data = value as? Data {
                    text = String(data: data, encoding: .utf8)
                } else {
                    text = nil
                }
                self?.applyResolvedText(text)
            }
            return
        }

        if let textProvider = attachments.first(where: { $0.hasItemConformingToTypeIdentifier(textType) }) {
            textProvider.loadItem(forTypeIdentifier: textType, options: nil) { [weak self] value, _ in
                let text = (value as? String) ?? (value as? NSAttributedString)?.string
                self?.applyResolvedText(text)
            }
            return
        }

        // Some hosts expose useful text only via item-level attributedContentText.
        applyResolvedText(Self.fallbackText(from: inputItems))
    }

    private func loadSharedAttachments(from providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] value, _ in
                    guard let self,
                          let fileURL = (value as? URL),
                          fileURL.isFileURL else { return }
                    self.persistSharedAttachment(
                        from: fileURL,
                        suggestedName: provider.suggestedName,
                        typeIdentifier: UTType.fileURL.identifier
                    )
                }
                continue
            }

            guard let typeIdentifier = Self.preferredAttachmentTypeIdentifier(for: provider) else {
                continue
            }
            provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { [weak self] fileURL, _ in
                guard let self else { return }
                if let fileURL {
                    self.persistSharedAttachment(
                        from: fileURL,
                        suggestedName: provider.suggestedName,
                        typeIdentifier: typeIdentifier
                    )
                    return
                }
                provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
                    guard let data else { return }
                    self.persistSharedAttachmentData(
                        data,
                        suggestedName: provider.suggestedName,
                        typeIdentifier: typeIdentifier
                    )
                }
            }
        }
    }

    private func applyAddOpenCopy() {
        title = "Add to NEAR Private Chat"
        navigationItem.rightBarButtonItem?.title = "Add"
    }

    private func stagedText() -> String {
        let typed = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let attachment = resolvedSharedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !typed.isEmpty else { return attachment }
        guard !attachment.isEmpty else { return typed }
        guard !typed.contains(attachment) else { return typed }

        return "\(typed)\n\n\(attachment)"
    }

    private static func fallbackText(from inputItems: [NSExtensionItem]) -> String? {
        inputItems
            .compactMap { $0.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func applyResolvedText(_ text: String?) {
        let resolved = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.resolvedSharedText = resolved
            if (self.contentText ?? "").isEmpty, !resolved.isEmpty {
                self.textView.text = resolved
                self.validateContent()
            }
        }
    }

    private static func preferredAttachmentTypeIdentifier(for provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            if type.conforms(to: .url) || type.conforms(to: .plainText) {
                return false
            }
            return type.conforms(to: .image) ||
                type.conforms(to: .pdf) ||
                type.conforms(to: .data) ||
                type.conforms(to: .content)
        }
    }

    private func persistSharedAttachment(
        from sourceURL: URL,
        suggestedName: String?,
        typeIdentifier: String?
    ) {
        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        let fileName = Self.sanitizedFileName(
            suggestedName: suggestedName,
            fallbackName: sourceURL.lastPathComponent,
            typeIdentifier: typeIdentifier
        )
        guard let destination = Self.destinationURL(for: fileName) else { return }
        do {
            try FileManager.default.createDirectory(
                at: destination.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? FileManager.default.removeItem(at: destination.url)
            try FileManager.default.copyItem(at: sourceURL, to: destination.url)
            let byteCount = (try? destination.url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
            guard byteCount ?? 0 <= PendingShareStore.maxPendingAttachmentBytes else {
                try? FileManager.default.removeItem(at: destination.url)
                return
            }
            appendResolvedAttachment(
                fileName: fileName,
                typeIdentifier: typeIdentifier,
                relativePath: destination.relativePath,
                byteCount: byteCount
            )
        } catch {
            return
        }
    }

    private func persistSharedAttachmentData(
        _ data: Data,
        suggestedName: String?,
        typeIdentifier: String?
    ) {
        guard data.count <= PendingShareStore.maxPendingAttachmentBytes else { return }
        let fileName = Self.sanitizedFileName(
            suggestedName: suggestedName,
            fallbackName: "shared-file",
            typeIdentifier: typeIdentifier
        )
        guard let destination = Self.destinationURL(for: fileName) else { return }
        do {
            try FileManager.default.createDirectory(
                at: destination.url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination.url, options: .atomic)
            appendResolvedAttachment(
                fileName: fileName,
                typeIdentifier: typeIdentifier,
                relativePath: destination.relativePath,
                byteCount: data.count
            )
        } catch {
            return
        }
    }

    private func appendResolvedAttachment(
        fileName: String,
        typeIdentifier: String?,
        relativePath: String,
        byteCount: Int?
    ) {
        let attachment = PendingSharedAttachment(
            fileName: fileName,
            typeIdentifier: typeIdentifier,
            relativePath: relativePath,
            byteCount: byteCount
        )
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  !self.resolvedSharedAttachments.contains(where: { $0.relativePath == relativePath }) else {
                return
            }
            self.resolvedSharedAttachments.append(attachment)
            self.validateContent()
        }
    }

    private static func destinationURL(for fileName: String) -> (url: URL, relativePath: String)? {
        guard let sharedDirectory = PendingShareStore.sharedDirectoryURL() else { return nil }
        let relativePath = PendingShareStore.relativeAttachmentPath(for: fileName)
        return (sharedDirectory.appendingPathComponent(relativePath), relativePath)
    }

    private static func sanitizedFileName(
        suggestedName: String?,
        fallbackName: String,
        typeIdentifier: String?
    ) -> String {
        let rawName = (suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? fallbackName
        let collapsed = rawName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var name = collapsed.isEmpty ? "shared-file" : collapsed
        if (name as NSString).pathExtension.isEmpty,
           let typeIdentifier,
           let ext = UTType(typeIdentifier)?.preferredFilenameExtension {
            name += ".\(ext)"
        }
        return name
    }

    // MARK: - Open host app

    /// Opens the host app via its registered URL scheme using the responder
    /// chain (`openURL:` is unavailable to extensions directly). No-op if the
    /// selector can't be reached.
    private func openHostApp() {
        guard let url = URL(string: "nearprivatechat://share") else { return }
        var responder: UIResponder? = self
        let selector = sel_registerName("openURL:")
        while let current = responder {
            if current.responds(to: selector) {
                current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }
}

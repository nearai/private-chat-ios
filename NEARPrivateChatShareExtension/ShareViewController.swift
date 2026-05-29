import UIKit
import Social
import UniformTypeIdentifiers
import MobileCoreServices

/// "Send to Private Chat" share extension. Presents the system compose sheet
/// (a free editable preview of the shared text), then on Post writes the text
/// or URL the user shared to a small file in the App Group container. The main
/// app drains that file on its next activation and stages it into the composer
/// — it is never auto-sent.
///
/// The extension intentionally does no networking and links none of the app's
/// model graph beyond the shared `PendingShareStore` / `PendingSharedItem`
/// types it compiles directly.
final class ShareViewController: SLComposeServiceViewController {

    /// Text resolved from the shared attachments (URL or plain text). The
    /// compose sheet seeds its editable field from this; the user can edit
    /// before posting.
    private var resolvedSharedText: String = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        placeholder = "Add a note, or just send to Private Chat…"
        title = "Private Chat"
        loadSharedContent()
    }

    /// Always allow posting; an empty draft is still a valid "open the app"
    /// gesture, and we fall back to the resolved attachment text.
    override func isContentValid() -> Bool {
        true
    }

    override func didSelectPost() {
        let typed = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = resolvedSharedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalText = typed.isEmpty ? fallback : typed

        if !finalText.isEmpty {
            let item = PendingSharedItem(text: finalText)
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
        let attachments = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap { $0.attachments }
            .flatMap { $0 } ?? []

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

        // Some hosts expose a URL only via the item-level attributedContentText
        // / userInfo; fall back to whatever the sheet already shows.
        applyResolvedText(nil)
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

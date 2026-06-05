import Foundation
import PhotosUI
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension InputBar {
    @ViewBuilder
    var attachmentOptionsDialog: some View {
        Button("Files") {
            AppHaptics.selection()
            showingFileImporter = true
        }

        Button("Photos") {
            AppHaptics.selection()
            showingPhotoPicker = true
        }

        Button("Camera") {
            AppHaptics.selection()
            openCamera()
        }

        Button("Paste") {
            AppHaptics.selection()
            attachPasteboard()
        }
    }

    func attachPhotoItems(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            for (index, item) in items.prefix(5).enumerated() {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        continue
                    }
                    await attachImageData(data, preferredName: "photo-\(index + 1).jpg")
                } catch {
                    await MainActor.run {
                        chatStore.bannerMessage = "Could not attach one of those photos."
                    }
                }
            }
            await MainActor.run {
                selectedPhotoItems = []
            }
        }
    }

    func attachImageData(_ data: Data, preferredName: String) async {
        guard data.count <= ChatStore.maxAttachmentUploadBytes else {
            await MainActor.run {
                chatStore.bannerMessage = "Images must be 10 MB or smaller."
            }
            return
        }
        let safeName = preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "image.jpg" : preferredName
        let pathExtension = (safeName as NSString).pathExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension.isEmpty ? "jpg" : pathExtension)
        do {
            try data.write(to: url, options: [.atomic])
            await chatStore.addAttachment(from: url, displayName: safeName)
        } catch {
            await MainActor.run {
                chatStore.bannerMessage = "Could not prepare that image."
            }
        }
    }

    func openCamera() {
        #if canImport(UIKit)
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showingCamera = true
        } else {
            chatStore.bannerMessage = "Camera is not available here. Choose Photos or Files."
        }
        #else
        chatStore.bannerMessage = "Camera is not available here. Choose Photos or Files."
        #endif
    }

    func attachPasteboard() {
        #if canImport(UIKit)
        let pasteboard = UIPasteboard.general
        if let text = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            chatStore.stageTextAttachment(text, suggestedName: "clipboard.txt")
            return
        }
        if let image = pasteboard.image,
           let data = image.jpegData(compressionQuality: 0.9) {
            Task { await attachImageData(data, preferredName: "clipboard-image.jpg") }
            return
        }
        chatStore.bannerMessage = "Clipboard has no text or image to attach."
        #else
        chatStore.bannerMessage = "Paste attachments are not available on this platform."
        #endif
    }

    #if canImport(UIKit)
    func attachCapturedImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            chatStore.bannerMessage = "Could not read that photo."
            return
        }
        Task { await attachImageData(data, preferredName: "camera-photo.jpg") }
    }
    #endif
}

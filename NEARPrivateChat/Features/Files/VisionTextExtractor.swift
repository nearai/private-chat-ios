import Foundation
#if canImport(Vision) && canImport(ImageIO)
import ImageIO
import Vision
#endif

enum VisionTextExtractor {
    nonisolated static let supportedImageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "webp"
    ]

    nonisolated static func extractedImageTextIfAvailable(from url: URL, fileExtension: String) async -> String? {
        #if canImport(Vision) && canImport(ImageIO)
        guard supportedImageExtensions.contains(fileExtension.lowercased()) else { return nil }
        return await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return nil
            }
            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }.value
        #else
        return nil
        #endif
    }
}

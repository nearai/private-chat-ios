import Foundation
#if canImport(UIKit)
import UIKit
#endif

protocol FileAPI: AnyObject {
    func uploadFile(from url: URL) async throws -> ChatAttachment
    func uploadTextFile(filename: String, text: String) async throws -> ChatAttachment
    func fetchFiles() async throws -> RemoteFilesResponse
    func fetchFile(_ fileID: String) async throws -> RemoteFileInfo
    func fetchFileContent(_ fileID: String) async throws -> Data
    func fetchFilePreviewContent(_ fileID: String, maxBytes: Int) async throws -> Data
    func deleteFile(_ fileID: String) async throws
}

final class PrivateChatFileAPI: FileAPI {
    private let client: APIClient

    init(client: APIClient) {
        self.client = client
    }

    func uploadFile(from url: URL) async throws -> ChatAttachment {
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let (data, filename, mimeType) = try await Task.detached(priority: .userInitiated) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = values.fileSize, fileSize > APIClient.maxUploadBytes {
                throw APIError.status(413, "Files must be 10 MB or smaller.")
            }
            let data = try Data(contentsOf: url)
            guard data.count <= APIClient.maxUploadBytes else {
                throw APIError.status(413, "Files must be 10 MB or smaller.")
            }
            let filename = APIClient.sanitizedMultipartFilename(url.lastPathComponent.isEmpty ? "Attachment" : url.lastPathComponent)
            return (data, filename, Self.mimeType(for: url))
        }.value
        let upload = try Self.normalizedVisionUpload(data: data, filename: filename, mimeType: mimeType)
        return try await uploadFileData(
            upload.data,
            filename: upload.filename,
            mimeType: upload.mimeType
        )
    }

    func uploadTextFile(filename: String, text: String) async throws -> ChatAttachment {
        guard let data = text.data(using: .utf8) else {
            throw APIError.emptyResponse
        }
        return try await uploadFileData(data, filename: APIClient.sanitizedMultipartFilename(filename), mimeType: "text/plain")
    }

    func fetchFiles() async throws -> RemoteFilesResponse {
        try await client.request("/v1/files", method: "GET", authenticated: true)
    }

    func fetchFile(_ fileID: String) async throws -> RemoteFileInfo {
        try await client.request("/v1/files/\(try APIClient.safePathSegment(fileID))", method: "GET", authenticated: true)
    }

    func fetchFileContent(_ fileID: String) async throws -> Data {
        let request = try client.makeRequest(path: "/v1/files/\(try APIClient.safePathSegment(fileID))/content", method: "GET", body: nil, authenticated: true)
        return try await client.performRaw(request)
    }

    func fetchFilePreviewContent(_ fileID: String, maxBytes: Int = APIClient.maxFilePreviewBytes) async throws -> Data {
        let byteLimit = max(1, min(maxBytes, APIClient.maxUploadBytes))
        var request = try client.makeRequest(path: "/v1/files/\(try APIClient.safePathSegment(fileID))/content", method: "GET", body: nil, authenticated: true)
        request.setValue("bytes=0-\(byteLimit - 1)", forHTTPHeaderField: "Range")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.emptyResponse
        }

        var data = Data()
        data.reserveCapacity(byteLimit)
        for try await byte in bytes {
            if data.count >= byteLimit { break }
            data.append(byte)
        }

        guard (200..<300).contains(http.statusCode) else {
            throw APIError.status(http.statusCode, client.decodeErrorMessage(from: data))
        }
        return data
    }

    func deleteFile(_ fileID: String) async throws {
        let _: EmptyResponse = try await client.request(
            "/v1/files/\(try APIClient.safePathSegment(fileID))",
            method: "DELETE",
            authenticated: true
        )
    }

    private func uploadFileData(_ data: Data, filename: String, mimeType: String) async throws -> ChatAttachment {
        guard data.count <= APIClient.maxUploadBytes else {
            throw APIError.status(413, "Files must be 10 MB or smaller.")
        }
        let safeFilename = APIClient.sanitizedMultipartFilename(filename)
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.appendMultipartField(name: "purpose", value: Self.uploadPurpose(filename: safeFilename, mimeType: mimeType), boundary: boundary)
        body.appendMultipartField(name: "expires_after[anchor]", value: "created_at", boundary: boundary)
        body.appendMultipartField(name: "expires_after[seconds]", value: "36000", boundary: boundary)
        body.appendMultipartFile(
            name: "file",
            filename: safeFilename,
            mimeType: mimeType,
            data: data,
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")

        var request = try client.makeRequest(path: "/v1/files", method: "POST", body: body, authenticated: true)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let response: FileUploadResponse = try await client.perform(request)
        return ChatAttachment(
            id: response.id,
            name: response.filename,
            kind: response.purpose,
            bytes: response.bytes
        )
    }

    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return "application/pdf"
        case "csv":
            return "text/csv"
        case "tsv":
            return "text/tab-separated-values"
        case "xlsx":
            return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls":
            return "application/vnd.ms-excel"
        case "json":
            return "application/json"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        case "heic":
            return "image/heic"
        case "heif":
            return "image/heif"
        case "tif", "tiff":
            return "image/tiff"
        case "txt", "md", "log", "swift", "js", "ts", "tsx", "py", "html", "css":
            return "text/plain"
        default:
            return "application/octet-stream"
        }
    }

    static func uploadPurpose(filename: String, mimeType: String) -> String {
        ChatAttachment.isNativeVisionImage(filename: filename, mimeTypeOrKind: mimeType) ? "vision" : "user_data"
    }

    static func needsVisionTranscode(filename: String, mimeType: String) -> Bool {
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        if ["heic", "heif", "tif", "tiff"].contains(fileExtension) {
            return true
        }
        return ["image/heic", "image/heif", "image/tiff"].contains(mimeType.lowercased())
    }

    static func normalizedVisionFilename(filename: String, mimeType: String) -> String {
        guard needsVisionTranscode(filename: filename, mimeType: mimeType) else {
            return APIClient.sanitizedMultipartFilename(filename)
        }
        let safeFilename = APIClient.sanitizedMultipartFilename(filename)
        let base = (safeFilename as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\((base.isEmpty ? "image" : base)).jpg"
    }

    static func normalizedVisionUpload(data: Data, filename: String, mimeType: String) throws -> (data: Data, filename: String, mimeType: String) {
        guard needsVisionTranscode(filename: filename, mimeType: mimeType) else {
            return (data, APIClient.sanitizedMultipartFilename(filename), mimeType)
        }
        #if canImport(UIKit)
        guard let image = UIImage(data: data),
              let jpegData = image.jpegData(compressionQuality: 0.92) else {
            throw APIError.status(415, "Could not convert this HEIC/TIFF image to JPEG.")
        }
        return (
            jpegData,
            normalizedVisionFilename(filename: filename, mimeType: mimeType),
            "image/jpeg"
        )
        #else
        throw APIError.status(415, "HEIC/TIFF images must be converted to JPEG before native vision upload.")
        #endif
    }
}

private struct FileUploadResponse: Decodable {
    let id: String
    let bytes: Int
    let filename: String
    let purpose: String
}

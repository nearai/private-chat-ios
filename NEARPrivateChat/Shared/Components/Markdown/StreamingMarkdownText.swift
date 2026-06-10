import SwiftUI

/// Strips inline markdown markers from in-flight text so streaming previews
/// never show raw `**bold**` / `## Heading` to the user. Tolerant of markers
/// split across the stream cut point (a dangling `**` is removed, not shown).
enum MarkdownStreamSanitizer {
    static func strippedInline(_ text: String) -> String {
        var result = text
        // Bold/underline markers — remove even when unpaired mid-stream.
        result = result.replacingOccurrences(of: "**", with: "")
        result = result.replacingOccurrences(of: "__", with: "")
        // Heading hashes at line starts.
        result = result.replacingOccurrences(
            of: #"(?m)^#{1,6}\s+"#,
            with: "",
            options: .regularExpression
        )
        // Paired single-character emphasis around non-empty runs. Dangling
        // singles are left alone (could be math or a multiply sign).
        result = result.replacingOccurrences(
            of: #"\*([^*\n]+)\*"#,
            with: "$1",
            options: .regularExpression
        )
        // Inline code backticks.
        result = result.replacingOccurrences(of: "`", with: "")
        return result
    }
}

/// Streaming-safe markdown: completed blocks (up to the last blank line)
/// render through the real markdown pipeline — its block cache makes repeated
/// renders cheap — while the still-growing tail renders as sanitized plain
/// text. The user never sees raw markers mid-stream.
struct StreamingMarkdownText: View {
    let text: String

    var body: some View {
        let split = Self.splitStableTail(text)
        VStack(alignment: .leading, spacing: 8) {
            if !split.stable.isEmpty {
                MarkdownMessageText(text: split.stable)
            }
            if !split.tail.isEmpty {
                Text(MarkdownStreamSanitizer.strippedInline(split.tail))
                    .font(.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Splits at the LAST blank line: everything before it is structurally
    /// complete markdown; the remainder is the live tail.
    static func splitStableTail(_ text: String) -> (stable: String, tail: String) {
        guard let range = text.range(of: "\n\n", options: .backwards) else {
            return ("", text)
        }
        let stable = String(text[..<range.lowerBound])
        let tail = String(text[range.upperBound...])
        return (stable, tail)
    }
}

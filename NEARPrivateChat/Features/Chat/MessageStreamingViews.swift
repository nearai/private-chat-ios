import SwiftUI

struct AgentThinkingShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerPhase: CGFloat = 0
    let statusText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 24, height: 24)
                    .background(Color.brandBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 7) {
                shimmerBar(widthFraction: 0.92)
                shimmerBar(widthFraction: 0.68)
            }
            .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandBlue.opacity(0.14), lineWidth: 1)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                shimmerPhase = 1
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusText)
    }

    private func shimmerBar(widthFraction: CGFloat) -> some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.appBorder.opacity(0.45))
                .overlay {
                    if !reduceMotion {
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.white.opacity(0.58),
                                Color.clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: proxy.size.width * 0.46)
                        .offset(x: (shimmerPhase * proxy.size.width * 1.65) - proxy.size.width * 0.55)
                    }
                }
                .mask(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .frame(height: 9)
        .frame(maxWidth: widthFraction == 1 ? .infinity : 420 * widthFraction)
    }
}

struct StreamingMessageText: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(message.streamingStatusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(Self.streamingLengthText(from: message.text))
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(Self.streamingPreview(from: message.text))
                .lineSpacing(2)
                .lineLimit(12)
                .textSelection(.enabled)
        }
    }

    private static func streamingPreview(from rawText: String) -> String {
        let text = MessageWidget.strippedStreamingPreview(rawText)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return " " }
        let cappedText: String
        let isCapped: Bool
        if trimmed.utf8.count > 4_000 {
            cappedText = String(trimmed.suffix(4_000))
            isCapped = true
        } else {
            cappedText = trimmed
            isCapped = false
        }
        let lines = cappedText
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let preview = lines.isEmpty ? cappedText : lines.suffix(12).joined(separator: "\n")
        return isCapped ? "...\n\(preview)" : preview
    }

    private static func streamingLengthText(from text: String) -> String {
        let byteCount = text.utf8.count
        guard byteCount >= 10_000 else {
            return "\(text.count) chars"
        }
        return "~\(byteCount / 1_000)k chars"
    }
}

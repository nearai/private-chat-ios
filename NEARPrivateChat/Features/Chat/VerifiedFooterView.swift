import SwiftUI

// MARK: - Claude Design Proof Footer

struct VerifiedFooterViewModel {
    let state: ProofState
    let badge: String
    let model: String
    let sourceCount: Int
    let ago: String
    let symbolName: String
    let tintColor: Color
    let detail: String
}

struct VerifiedFooterButton: View {
    let viewModel: VerifiedFooterViewModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: footerSymbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(footerTint)
                Text(footerText)
                    .font(.footnote)
                    .foregroundStyle(footerTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open proof details")
        .accessibilityValue(viewModel.detail)
    }

    private var footerSymbol: String {
        switch viewModel.state {
        case .verified:
            return "checkmark.seal.fill"
        case .stale:
            return "clock.badge.exclamationmark"
        case .mismatch:
            return "exclamationmark.shield.fill"
        case .verifying:
            return "arrow.triangle.2.circlepath"
        default:
            return viewModel.symbolName
        }
    }

    private var footerTint: Color {
        switch viewModel.state {
        case .verified:
            return Color.proofVerifiedText
        case .stale:
            return Color.proofStaleText
        case .mismatch:
            return Color.proofMismatch
        default:
            return viewModel.tintColor
        }
    }

    private var footerText: String {
        // For route/model proof and non-answer-bound states keep the badge so users see
        // "Proof report" / "Stale" / "Privacy proxy" without answer-level overclaiming.
        var pieces: [String] = []
        switch viewModel.state {
        case .verified:
            pieces.append("Proof checked")
        case .stale:
            pieces.append("Proof stale")
        case .mismatch:
            pieces.append("Not covered")
        case .verifying:
            pieces.append("Checking proof")
        default:
            pieces.append(normalizedBadge)
        }
        pieces.append(viewModel.model)
        if viewModel.sourceCount > 0 {
            pieces.append("\(viewModel.sourceCount) web source\(viewModel.sourceCount == 1 ? "" : "s")")
        }
        pieces.append(Self.relativeSuffix(viewModel.ago))
        return pieces.joined(separator: " · ")
    }

    // "No model proof" next to a known model name reads as a contradiction;
    // the proof state it describes is simply "no proof for this answer".
    private var normalizedBadge: String {
        let trimmed = viewModel.badge.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.localizedCaseInsensitiveCompare("No model proof") == .orderedSame {
            return "No proof"
        }
        return trimmed
    }

    static func relativeSuffix(_ ago: String) -> String {
        ago == "now" ? "just now" : "\(ago) ago"
    }
}

enum ChatTimeFormatter {
    static func relativeShort(from date: Date, now: Date = Date()) -> String {
        let delta = max(0, now.timeIntervalSince(date))
        if delta < 5 { return "now" }
        if delta < 60 { return "\(Int(delta))s" }
        let minutes = Int(delta / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 7 { return "\(days)d" }
        let weeks = days / 7
        if weeks < 5 { return "\(weeks)w" }
        let months = days / 30
        if months < 12 { return "\(months)mo" }
        return "\(days / 365)y"
    }
}

// Lightweight `view.if(cond) { ... }` modifier so we can branch the user
// bubble styling without an Either-view explosion.
extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition { transform(self) } else { self }
    }
}

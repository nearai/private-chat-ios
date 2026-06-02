import SwiftUI

struct CouncilSynthesisCard: View {
    let synthesis: CouncilSynthesisVM
    @State private var expandedChip: SynthesisChip?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.actionPrimary)
                Text("Synthesis")
                    .font(.headline.weight(.semibold))
                Spacer(minLength: 0)
            }

            Text(synthesis.fullText)
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .lineSpacing(3)
                .textSelection(.enabled)

            if !chips.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(chips) { chip in
                        Button {
                            withAnimation(.snappy(duration: 0.18)) {
                                expandedChip = expandedChip == chip ? nil : chip
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: chip.symbolName)
                                    .font(.caption.weight(.bold))
                                Text(chip.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Image(systemName: expandedChip == chip ? "chevron.up" : "chevron.down")
                                    .font(.caption2.weight(.bold))
                            }
                            .foregroundStyle(chip.tint)
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                            .background(chip.tint.opacity(expandedChip == chip ? 0.16 : 0.09), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if let expandedChip, let detail = detail(for: expandedChip) {
                    Text(detail)
                        .font(.callout)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.appHairline, lineWidth: 1)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private var chips: [SynthesisChip] {
        SynthesisChip.allCases.filter { detail(for: $0) != nil }
    }

    private func detail(for chip: SynthesisChip) -> String? {
        switch chip {
        case .agreement:
            return synthesis.agreement
        case .disagreement:
            return synthesis.disagreement
        case .nextStep:
            return synthesis.nextStep
        }
    }
}

private enum SynthesisChip: String, CaseIterable, Identifiable {
    case agreement
    case disagreement
    case nextStep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agreement:
            return "Agreement"
        case .disagreement:
            return "Disagreement"
        case .nextStep:
            return "Recommended next step"
        }
    }

    var symbolName: String {
        switch self {
        case .agreement:
            return "checkmark.circle.fill"
        case .disagreement:
            return "exclamationmark.triangle.fill"
        case .nextStep:
            return "arrow.right.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .agreement:
            return .proofVerified
        case .disagreement:
            return .proofMismatch
        case .nextStep:
            return .brandBlue
        }
    }
}

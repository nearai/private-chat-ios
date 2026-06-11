import SwiftUI

struct HomeTrustReadinessCard: View {
    let viewModel: ProofCapsuleViewModel
    let routeLabel: String
    let modelLabel: String
    let actionTitle: String
    let actionSymbolName: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: viewModel.symbolName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(viewModel.tintColor)
                    .frame(width: 38, height: 38)
                    .background(viewModel.tintColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Trust check")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.primaryAction)
                    Text(viewModel.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(viewModel.detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .center, spacing: 10) {
                ProofCapsule(viewModel: viewModel)
                VStack(alignment: .leading, spacing: 3) {
                    Text(routeLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(modelLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Button(action: action) {
                Label(actionTitle, systemImage: actionSymbolName)
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Color.primaryAction, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(14)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(viewModel.tintColor.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: Color.brandAccent.opacity(0.04), radius: 12, y: 6)
    }
}


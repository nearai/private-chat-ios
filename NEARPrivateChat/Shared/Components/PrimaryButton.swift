import SwiftUI

struct PrimaryButton<Label: View>: View {
    enum Size {
        case regular
        case compact

        var height: CGFloat {
            switch self {
            case .regular:
                return 52
            case .compact:
                return 44
            }
        }
    }

    let size: Size
    let action: () -> Void
    let label: () -> Label
    @Environment(\.isEnabled) private var isEnabled

    init(
        size: Size = .regular,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.size = size
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            label()
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: size.height)
                .background(Color.actionPrimary, in: RoundedRectangle.app(AppRadius.control))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityAddTraits(.isButton)
    }
}

extension PrimaryButton where Label == PrimaryButtonTitleLabel {
    init(
        _ title: String,
        systemImage: String? = nil,
        size: Size = .regular,
        action: @escaping () -> Void
    ) {
        self.init(size: size, action: action) {
            PrimaryButtonTitleLabel(title: title, systemImage: systemImage)
        }
    }
}

struct PrimaryButtonTitleLabel: View {
    let title: String
    let systemImage: String?

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
            }
            Text(title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

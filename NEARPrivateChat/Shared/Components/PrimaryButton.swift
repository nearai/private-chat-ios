import SwiftUI

struct PrimaryButton<Label: View>: View {
    enum Size {
        case regular
        case compact

        var height: CGFloat {
            switch self {
            case .regular:
                return AppTouchTarget.primaryRegular
            case .compact:
                return AppTouchTarget.primaryCompact
            }
        }
    }

    let size: Size
    let action: () -> Void
    let label: () -> Label
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var scaledRegularHeight = AppTouchTarget.primaryRegular
    @ScaledMetric(relativeTo: .body) private var scaledCompactHeight = AppTouchTarget.primaryCompact

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
                .foregroundStyle(buttonForeground)
                .frame(maxWidth: .infinity)
                .frame(height: scaledHeight)
                .minimumTouchTarget()
                .background(buttonBackground, in: RoundedRectangle.app(AppRadius.control))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isEnabled)
        .accessibilityAddTraits(.isButton)
    }

    private var buttonBackground: Color {
        isEnabled ? .actionPrimary : .disabledControlBackground
    }

    private var buttonForeground: Color {
        isEnabled ? .white : .disabledControlText
    }

    private var scaledHeight: CGFloat {
        switch size {
        case .regular:
            return max(size.height, scaledRegularHeight)
        case .compact:
            return max(size.height, scaledCompactHeight)
        }
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
                    .font(.body.weight(.semibold))
            }
            Text(title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

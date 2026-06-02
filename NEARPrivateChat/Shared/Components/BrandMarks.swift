import SwiftUI

// MARK: - Wordmark (text-based NEAR Private Chat lockup)

struct ProductWordmark: View {
    var alignment: HorizontalAlignment = .leading
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text("NEAR")
                .font(.largeTitle.weight(.heavy))
                .foregroundStyle(Color.textPrimary)
            Text("Private Chat")
                .font(.title2.weight(.heavy))
                .foregroundStyle(Color.brandBlue)
        }
        .scaleEffect(scale)
        .accessibilityLabel("NEAR Private Chat")
    }
}

// MARK: - NEAR N glyph (official artwork)

/// Free-standing NEAR "N" letterform — official artwork from NEAR AI Brand
/// Guidelines v01. Renders the canonical slanted-N with chamfered tops as a
/// tintable template. Used inline in text contexts and inside PrivacySeal.
struct NearMark: View {
    var size: CGFloat = 44
    var color: Color = .actionPrimary

    var body: some View {
        Image("NearGlyph")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .accessibilityLabel("NEAR")
    }
}

/// App-icon style NEAR mark — official artwork from NEAR AI Brand Guidelines v01.
/// Renders the canonical blue rounded square with the white slanted-N letterform.
/// Asset is a vector SVG, scales cleanly at any size.
struct NearAppIconMark: View {
    var size: CGFloat = 64

    var body: some View {
        Image("NearMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityLabel("NEAR")
    }
}

// MARK: - Privacy seal (NEAR mark on tinted square with brand-blue glow)

struct PrivacySeal: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: max(8, size * 0.22), style: .continuous)
                .fill(Color.actionTint)

            NearMark(size: size * 0.64)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.brandBlue.opacity(0.22), radius: 22, y: 10)
        .accessibilityLabel("NEAR Private Chat")
    }
}

// MARK: - Preview

#if DEBUG
struct BrandMarks_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 32) {
            NearMark(size: 56)
            NearAppIconMark(size: 96)
            NearAppIconMark(size: 64)
            NearAppIconMark(size: 44)
            PrivacySeal(size: 72)
            ProductWordmark()
        }
        .padding(40)
        .previewLayout(.sizeThatFits)
    }
}
#endif

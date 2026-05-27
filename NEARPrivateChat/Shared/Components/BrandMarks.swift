import SwiftUI

// MARK: - Wordmark (text-based NEAR AI Private Chat lockup)

struct ProductWordmark: View {
    var alignment: HorizontalAlignment = .leading
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: alignment, spacing: -2 * scale) {
            Text("NEAR AI")
                .font(.system(size: 44 * scale, weight: .heavy, design: .default))
                .foregroundStyle(Color.brandBlack)
            Text("private chat")
                .font(.system(size: 30 * scale, weight: .heavy, design: .default))
                .foregroundStyle(Color.brandBlue)
        }
        .accessibilityLabel("NEAR AI Private Chat")
    }
}

// MARK: - NEAR N glyph

/// The NEAR Protocol "N" letterform — two parallel verticals connected by a
/// diagonal sloping from bottom-left to top-right. Drawn as a single open path
/// with rounded line caps so the four endpoints read as four rounded bullets.
///
/// Path order (normalised 0–1 coords inside the bounding square):
///   1. Top-left vertical start    (0.31, 0.28)
///   2. Bottom-left vertical end   (0.31, 0.74)
///   3. Top-right vertical start   (0.69, 0.28)  — diagonal up to here
///   4. Bottom-right vertical end  (0.69, 0.74)
struct NearGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + side * x, y: origin.y + side * y)
        }

        var path = Path()
        path.move(to: point(0.31, 0.28))
        path.addLine(to: point(0.31, 0.74))
        path.addLine(to: point(0.69, 0.28))
        path.addLine(to: point(0.69, 0.74))
        return path
    }
}

/// Free-standing NEAR glyph (no background) — used inline in text contexts.
struct NearMark: View {
    var size: CGFloat = 44
    var color: Color = .actionPrimary

    var body: some View {
        NearGlyphShape()
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: max(2, size * 0.135),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: size, height: size)
            .accessibilityLabel("NEAR")
    }
}

/// App-icon style NEAR mark — white N on a brand-blue rounded square.
/// Matches the NEAR Protocol app icon (no extra inner strokes).
struct NearAppIconMark: View {
    var size: CGFloat = 64
    var cornerScale: CGFloat = 0.22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * cornerScale, style: .continuous)
                .fill(Color.actionPrimary)

            NearGlyphShape()
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: max(2, size * 0.135),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: size, height: size)
        }
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

// MARK: - Backwards-compat alias

/// Codex called the shape `NearInfinityGlyphShape` mid-implementation; the
/// real shape is an N letterform, not a lemniscate. Keep the old name pointing
/// at the new shape so any leftover call sites don't break compile until they
/// get migrated.
typealias NearInfinityGlyphShape = NearGlyphShape

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

import SwiftUI

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

struct NearMark: View {
    var size: CGFloat = 44
    var color: Color = .actionPrimary

    var body: some View {
        NearInfinityGlyphShape()
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

struct NearAppIconMark: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.20, style: .continuous)
                .fill(Color.actionPrimary)
                .shadow(color: Color.actionPrimary.opacity(0.18), radius: 2, y: 1)

            NearInfinityGlyphShape()
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: max(2, size * 0.135),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: size, height: size)

            Path { path in
                path.move(to: CGPoint(x: size * 0.42, y: size * 0.66))
                path.addLine(to: CGPoint(x: size * 0.57, y: size * 0.51))
            }
            .stroke(
                Color.actionPrimary,
                style: StrokeStyle(
                    lineWidth: max(1.5, size * 0.055),
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

struct NearInfinityGlyphShape: Shape {
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

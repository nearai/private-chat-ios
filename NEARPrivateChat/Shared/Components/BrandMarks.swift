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
        NearLemniscateShape()
            .stroke(
                color,
                style: StrokeStyle(
                    lineWidth: max(2, size * 0.105),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            .frame(width: size, height: size)
            .accessibilityLabel("NEAR")
    }
}

private struct NearLemniscateShape: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let left = CGPoint(x: rect.midX - side * 0.30, y: rect.midY)
        let right = CGPoint(x: rect.midX + side * 0.30, y: rect.midY)
        let upper = rect.midY - side * 0.18
        let lower = rect.midY + side * 0.18

        var path = Path()
        path.move(to: center)
        path.addCurve(
            to: left,
            control1: CGPoint(x: rect.midX - side * 0.12, y: upper),
            control2: CGPoint(x: rect.midX - side * 0.30, y: upper)
        )
        path.addCurve(
            to: center,
            control1: CGPoint(x: rect.midX - side * 0.30, y: lower),
            control2: CGPoint(x: rect.midX - side * 0.12, y: lower)
        )
        path.addCurve(
            to: right,
            control1: CGPoint(x: rect.midX + side * 0.12, y: upper),
            control2: CGPoint(x: rect.midX + side * 0.30, y: upper)
        )
        path.addCurve(
            to: center,
            control1: CGPoint(x: rect.midX + side * 0.30, y: lower),
            control2: CGPoint(x: rect.midX + side * 0.12, y: lower)
        )
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

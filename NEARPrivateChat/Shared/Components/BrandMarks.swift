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

struct PrivacySeal: View {
    var size: CGFloat = 72

    var body: some View {
        Image("PrivateChatIcon")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: Color.brandBlue.opacity(0.22), radius: 22, y: 10)
    }
}

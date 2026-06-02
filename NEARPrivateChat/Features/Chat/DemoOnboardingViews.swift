import SwiftUI

#if DEBUG
struct DemoOnboardingPreviewView: View {
    private let signInRows: [(title: String, symbol: String)] = [
        ("Continue with NEAR", "sparkles"),
        ("Continue with Google", "g.circle"),
        ("Continue with GitHub", "chevron.left.forwardslash.chevron.right")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                AuthHeroCard()

                VStack(alignment: .leading, spacing: 12) {
                    Label("Terms & Conditions", systemImage: "doc.text.magnifyingglass")
                        .font(.headline.weight(.semibold))
                    Text("Review terms once, then sign in with NEAR, Google, or GitHub.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: 360, alignment: .leading)
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }

                VStack(spacing: 10) {
                    ForEach(signInRows, id: \.title) { row in
                        HStack(spacing: 10) {
                            Image(systemName: row.symbol)
                                .font(.subheadline.weight(.bold))
                                .frame(width: 24)
                            Text(row.title)
                                .font(.subheadline.weight(.bold))
                            Spacer()
                        }
                        .foregroundStyle(row.title.contains("NEAR") ? Color.white : Color.primary)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(row.title.contains("NEAR") ? Color.actionPrimary : Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(row.title.contains("NEAR") ? Color.clear : Color.appBorder, lineWidth: 1)
                        }
                    }

                    HStack {
                        Label("Open shared link", systemImage: "link")
                        Spacer()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .padding(.horizontal, 2)

                    HStack {
                        Label("More sign-in options", systemImage: "ellipsis.circle")
                        Spacer()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
                }
                .frame(maxWidth: 360)

                Text("https://private.near.ai")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
        .background { HomeSurfaceBackground().ignoresSafeArea() }
    }
}

struct DemoMockLoginView: View {
    @State private var passwordCount = 0
    @State private var isVerifying = false
    @State private var isComplete = false

    private let passwordLength = 12

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                googleWordmark

                VStack(alignment: .leading, spacing: 7) {
                    Text("Sign in")
                        .font(.largeTitle.weight(.regular))
                    Text("to continue to NEAR Private Chat")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.actionPrimary.opacity(0.12))
                        .frame(width: 24, height: 24)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.actionPrimary)
                        }
                    Text("maya.launch@example.com")
                        .font(.subheadline.weight(.medium))
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .overlay {
                    Capsule()
                        .stroke(Color.appBorder, lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Enter your password")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.actionPrimary)
                    HStack {
                        Text(String(repeating: "•", count: max(passwordCount, 1)))
                            .font(.title3.monospaced().weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 54)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.actionPrimary, lineWidth: 1.5)
                    }
                }

                HStack {
                    Button("Forgot password?") {}
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.actionPrimary)
                    Spacer()
                    Button {} label: {
                        HStack(spacing: 7) {
                            if isVerifying {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white)
                            }
                            Text(isComplete ? "Continue" : "Next")
                        }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .frame(height: 42)
                        .background(Color.actionPrimary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(true)
                }

                if isComplete {
                    Label("Google account connected", systemImage: "checkmark.shield.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.trustVerified)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(26)
            .frame(maxWidth: 430, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 76)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            for count in 1...passwordLength {
                try? await Task.sleep(nanoseconds: 95_000_000)
                await MainActor.run {
                    passwordCount = count
                }
            }
            try? await Task.sleep(nanoseconds: 380_000_000)
            await MainActor.run {
                isVerifying = true
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    isVerifying = false
                    isComplete = true
                }
            }
        }
    }

    private var googleWordmark: some View {
        HStack(spacing: 0) {
            Text("G").foregroundStyle(Color.googleBlue)
            Text("o").foregroundStyle(Color.googleRed)
            Text("o").foregroundStyle(Color.googleYellow)
            Text("g").foregroundStyle(Color.googleBlue)
            Text("l").foregroundStyle(Color.googleGreen)
            Text("e").foregroundStyle(Color.googleRed)
        }
        .font(.title2.weight(.medium))
        .accessibilityLabel("Google")
    }
}

#endif

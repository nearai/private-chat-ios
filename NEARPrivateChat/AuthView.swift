import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var chatStore: ChatStore
    @State private var showingTokenLogin = false
    @State private var showingSharedLink = false
    @State private var showingMoreSignInOptions = false
    @State private var token = ""

    var body: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 22)

            AuthHeroCard()

            VStack(spacing: 12) {
                ProviderButton(provider: .near, isLoading: sessionStore.isAuthenticating) {
                    sessionStore.signIn(with: .near)
                }
                ProviderButton(provider: .google, isLoading: sessionStore.isAuthenticating) {
                    sessionStore.signIn(with: .google)
                }
                ProviderButton(provider: .github, isLoading: sessionStore.isAuthenticating) {
                    sessionStore.signIn(with: .github)
                }

                Button {
                    showingSharedLink = true
                } label: {
                    AuthUtilityButtonLabel(title: "Open shared link", systemImage: "link")
                }
                .buttonStyle(.plain)

                #if DEBUG || targetEnvironment(simulator)
                DisclosureGroup(isExpanded: $showingMoreSignInOptions) {
                    Button {
                        showingTokenLogin = true
                    } label: {
                        AuthUtilityButtonLabel(title: "Developer session token", systemImage: "key")
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                } label: {
                    Label("More sign-in options", systemImage: "ellipsis.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tint(.secondary)
                .padding(.top, 2)
                #endif
            }
            .frame(maxWidth: 360)

            Spacer()

            Text("https://private.near.ai")
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .background { HomeSurfaceBackground().ignoresSafeArea() }
        #if DEBUG || targetEnvironment(simulator)
        .sheet(isPresented: $showingTokenLogin) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Session Token")
                        .font(.headline)
                    SecureField("Paste token", text: $token)
                        .tokenInputTraits()
                        .padding(12)
                        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }
                .padding()
                .navigationTitle("Developer Sign In")
                .platformInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingTokenLogin = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sign In") {
                            sessionStore.signInWithToken(token)
                            showingTokenLogin = false
                        }
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .platformMediumDetent()
        }
        #endif
        .sheet(isPresented: $showingSharedLink) {
            SharedConversationSheet()
                .environmentObject(chatStore)
        }
    }
}

private struct AuthHeroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                PrivacySeal(size: 56)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text("NEAR Private Chat")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Text("Private AI chat with cryptographic proof, shared links, projects, and agent power when you need it.")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.64))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                AuthHeroMetric(title: "Proof", symbolName: "checkmark.shield")
                AuthHeroMetric(title: "Private", symbolName: "lock.shield")
                AuthHeroMetric(title: "Shareable", symbolName: "link")
            }
        }
        .padding(18)
        .frame(maxWidth: 390, alignment: .leading)
        .background { CommandCardBackground(cornerRadius: 8) }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
        .shadow(color: Color.brandBlue.opacity(0.14), radius: 18, y: 8)
    }
}

private struct AuthHeroMetric: View {
    let title: String
    let symbolName: String

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Color.brandSky)
            .lineLimit(1)
            .minimumScaleFactor(0.86)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AuthUtilityButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.headline)
                .frame(width: 22)
            Text(title)
                .fontWeight(.medium)
            Spacer()
        }
        .foregroundStyle(Color.brandBlue)
        .padding(.horizontal, 16)
        .frame(height: 54)
        .frame(maxWidth: .infinity)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProviderButton: View {
    let provider: OAuthProvider
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: provider.symbolName)
                    .font(.headline)
                    .frame(width: 22)
                Text(provider.title)
                    .fontWeight(.medium)
                Spacer()
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.forward")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(provider == .near ? .white.opacity(0.72) : Color.brandBlue.opacity(0.72))
                }
            }
            .foregroundStyle(provider == .near ? .white : Color.brandBlue)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .frame(maxWidth: .infinity)
            .background(provider == .near ? Color.brandBlue : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

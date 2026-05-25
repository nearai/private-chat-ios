import SwiftUI

struct AuthView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @EnvironmentObject private var chatStore: ChatStore
    @State private var showingTokenLogin = false
    @State private var showingSharedLink = false
    @State private var showingMoreSignInOptions = false
    @State private var showingLegalTerms = false
    @State private var hasAcceptedLegalTerms = LegalTermsAcceptanceStore.hasPendingCurrentVersion()
    @State private var token = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                AuthHeroCard()

                LegalTermsAcceptanceCard(
                    isAccepted: Binding(
                        get: { hasAcceptedLegalTerms },
                        set: updateLegalTermsAcceptance
                    ),
                    showingTerms: $showingLegalTerms
                )
                .frame(maxWidth: 360)

                VStack(spacing: 12) {
                    ProviderButton(provider: .near, isLoading: sessionStore.isAuthenticating, isEnabled: canStartSignIn) {
                        sessionStore.signIn(with: .near)
                    }
                    ProviderButton(provider: .google, isLoading: sessionStore.isAuthenticating, isEnabled: canStartSignIn) {
                        sessionStore.signIn(with: .google)
                    }
                    ProviderButton(provider: .github, isLoading: sessionStore.isAuthenticating, isEnabled: canStartSignIn) {
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
                        .disabled(!hasAcceptedLegalTerms)
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

                Text("https://private.near.ai")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
        }
        .scrollDismissesKeyboard(.interactively)
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
                        .disabled(!hasAcceptedLegalTerms || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .platformMediumDetent()
        }
        #endif
        .sheet(isPresented: $showingLegalTerms) {
            LegalTermsSheet()
        }
        .sheet(isPresented: $showingSharedLink) {
            SharedConversationSheet()
                .environmentObject(chatStore)
        }
    }

    private var canStartSignIn: Bool {
        hasAcceptedLegalTerms && !sessionStore.isAuthenticating
    }

    private func updateLegalTermsAcceptance(_ accepted: Bool) {
        hasAcceptedLegalTerms = accepted
        if accepted {
            LegalTermsAcceptanceStore.recordPendingAcceptance()
        } else {
            LegalTermsAcceptanceStore.clearPendingAcceptance()
        }
    }
}

struct AuthHeroCard: View {
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
    let isEnabled: Bool
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
            .opacity(isEnabled ? 1 : 0.48)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
    }
}

private struct LegalTermsAcceptanceCard: View {
    @Binding var isAccepted: Bool
    @Binding var showingTerms: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    isAccepted.toggle()
                } label: {
                    Image(systemName: isAccepted ? "checkmark.square.fill" : "square")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(isAccepted ? Color.brandBlue : .secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isAccepted ? "Terms accepted" : "Accept terms")

                VStack(alignment: .leading, spacing: 5) {
                    Text("Legal attestation required")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(LegalTerms.acceptanceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button {
                    showingTerms = true
                } label: {
                    Label("Review terms", systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brandBlue)
                .background(Color.brandBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text("v\(LegalTerms.version)")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isAccepted ? Color.brandBlue.opacity(0.28) : Color.gray.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 12, y: 5)
    }
}

struct LegalTermsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NEAR Private Chat iOS Terms")
                            .font(.title2.weight(.bold))
                        Text("Effective \(LegalTerms.effectiveDate) - Version \(LegalTerms.version)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("Full draft: \(LegalTerms.appTermsDocumentName)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(LegalTerms.signupSummary, id: \.self) { item in
                            Label(item, systemImage: "checkmark.circle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(LegalTerms.sections) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title)
                                    .font(.headline)
                                Text(section.body)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Divider()
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Link("NEAR AI Services Terms", destination: LegalTerms.nearAIServicesTermsURL)
                        Link("NEAR AI Cloud Terms", destination: LegalTerms.nearAICloudTermsURL)
                        Link("NEAR AI Acceptable Use Policy", destination: LegalTerms.nearAIAcceptableUseURL)
                        Link("NEAR AI Privacy Policy", destination: LegalTerms.nearAIPrivacyPolicyURL)
                        Link("IronClaw repository and licenses", destination: LegalTerms.ironclawRepositoryURL)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                }
                .padding()
            }
            .navigationTitle("Terms")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .platformMediumDetent()
    }
}

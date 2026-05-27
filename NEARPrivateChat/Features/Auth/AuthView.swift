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
            VStack(spacing: 18) {
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
                    ProviderButton(provider: .near, isLoading: sessionStore.isAuthenticating, isEnabled: canStartSignIn, onBlocked: promptForTerms) {
                        sessionStore.signIn(with: .near)
                    }
                    ProviderButton(provider: .google, isLoading: sessionStore.isAuthenticating, isEnabled: canStartSignIn, onBlocked: promptForTerms) {
                        sessionStore.signIn(with: .google)
                    }
                    ProviderButton(provider: .github, isLoading: sessionStore.isAuthenticating, isEnabled: canStartSignIn, onBlocked: promptForTerms) {
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
                            DebugSessionTokenLabel()
                        }
                        .buttonStyle(.plain)
                        .disabled(!hasAcceptedLegalTerms)
                        .padding(.top, 8)
                    } label: {
                        Label("More sign-in options", systemImage: "ellipsis.circle")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
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
            .padding(.horizontal, 28)
            .padding(.top, 102)
            .padding(.bottom, 28)
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

    private func promptForTerms() {
        guard !hasAcceptedLegalTerms else { return }
        showingLegalTerms = true
    }
}

struct AuthHeroCard: View {
    var body: some View {
        VStack(spacing: 28) {
            PrivacySeal(size: 48)
                .accessibilityHidden(true)

            Text("Private AI with verifiable answers.")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: 360)
        .padding(.bottom, 112)
    }
}

private struct AuthUtilityButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
            Text(title)
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(Color.textSecondary)
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .contentShape(Rectangle())
    }
}

private struct DebugSessionTokenLabel: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.actionPrimary)
                .frame(width: 28, height: 28)
                .background(Color.actionTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Developer session token")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text("DEBUG · paste a session JWT")
                    .font(.caption2.monospaced())
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 14)
        .frame(height: 58)
        .frame(maxWidth: .infinity)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Color.appBorder)
        }
    }
}

private struct ProviderButton: View {
    let provider: OAuthProvider
    let isLoading: Bool
    let isEnabled: Bool
    let onBlocked: () -> Void
    let action: () -> Void

    var body: some View {
        Button {
            if isEnabled {
                action()
            } else {
                onBlocked()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: provider.symbolName)
                    .font(.headline)
                    .frame(width: 22)
                Text(provider.title)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                if isLoading {
                    ProgressView()
                        .tint(isEnabled ? .white : Color.textTertiary)
                } else {
                    Color.clear
                        .frame(width: 22, height: 22)
                }
            }
            .foregroundStyle(isEnabled ? .white : Color.textTertiary)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(isEnabled ? Color.actionPrimary : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

private struct LegalTermsAcceptanceCard: View {
    @Binding var isAccepted: Bool
    @Binding var showingTerms: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                isAccepted.toggle()
            } label: {
                Image(systemName: isAccepted ? "checkmark.square.fill" : "square")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isAccepted ? Color.actionPrimary : Color.textTertiary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAccepted ? "Terms accepted" : "Accept terms")

            Text("I agree to the Terms and Privacy")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showingTerms = true
            } label: {
                Text("Read terms")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.actionPrimary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isAccepted ? Color.actionPrimary.opacity(0.22) : Color.appBorder, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.03), radius: 10, y: 4)
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

import SwiftUI

/// Native NEAR account sign-in (no web view): the user authorizes this device's
/// public key on their NEAR account once, then signs in by NEP-413-signing the
/// challenge locally. For users who prefer a fully native flow over the in-app
/// web sign-in.
struct NearAccountSignInView: View {
    @EnvironmentObject private var sessionStore: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var accountID = ""
    @State private var didCopyKey = false

    private var devicePublicKey: String { sessionStore.nearDevicePublicKey }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Use this when you do not want the web sign-in flow. You will add this device key to your NEAR wallet once, then this app signs a local NEP-413 request. The account ID and signature are sent to private.near.ai; your private key stays on this device.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("NEAR ACCOUNT")
                            .font(.caption2.weight(.semibold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                        TextField("yourname.near", text: $accountID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.pill))
                            .accessibilityLabel("NEAR account ID")
                            .accessibilityHint("Enter the account that has authorized this device key.")
                            .accessibilityIdentifier("auth.nearAccountID")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("STEP 1 — AUTHORIZE THIS DEVICE KEY")
                            .font(.caption2.weight(.semibold))
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                        Text("Add this key as a Full Access key to your account in your NEAR wallet, then return here.")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Only continue if you understand that a Full Access key can act for the account until you remove it in the wallet.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(devicePublicKey)
                            .font(.footnote.monospaced())
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.appSecondaryBackground, in: RoundedRectangle.app(AppRadius.pill))
                            .accessibilityLabel("Device public key")
                            .accessibilityIdentifier("auth.nearDevicePublicKey")
                        Button {
                            UIPasteboard.general.string = devicePublicKey
                            didCopyKey = true
                        } label: {
                            Label(didCopyKey ? "Copied" : "Copy key", systemImage: didCopyKey ? "checkmark" : "doc.on.clipboard")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.actionPrimary)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 14)
                                .minimumTouchTarget()
                                .background(Color.actionTint, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Copies the device public key so you can add it in your NEAR wallet.")
                        .accessibilityIdentifier("auth.copyNearDeviceKey")
                    }

                    if accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Enter your account ID after the wallet shows this key is authorized.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("auth.nearAccountRequiredHint")
                    }

                    Button {
                        sessionStore.signInWithNearAccount(accountID)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            if sessionStore.isAuthenticating {
                                ProgressView().controlSize(.small)
                            }
                            Text("Step 2 — Sign in")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.actionPrimary, in: RoundedRectangle.app(AppRadius.control))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .disabled(accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sessionStore.isAuthenticating)
                    .accessibilityHint(accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Enter your NEAR account ID before signing in." : "Signs a local NEP-413 request with this device key.")
                    .accessibilityIdentifier("auth.confirmNearAccountSignIn")
                }
                .padding(18)
                .frame(maxWidth: 640, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Sign in with NEAR account")
            .platformInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .platformLargeDetent()
    }
}

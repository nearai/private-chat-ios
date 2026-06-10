import SwiftUI

/// Shows the REAL outcome of recent route requests — HTTP status, the server's
/// own message, model, and time — so a failing private route can be diagnosed
/// instead of being laundered into "temporarily busy" copy. Pushed from the
/// Capabilities sheet; relies on `ConnectionDiagnostics` + `ChatStore` from the
/// environment.
struct ConnectionDiagnosticsView: View {
    @EnvironmentObject private var diagnostics: ConnectionDiagnostics
    @EnvironmentObject private var chatStore: ChatStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if diagnostics.privateLooksUnauthenticated {
                    unauthenticatedBanner
                }

                routeCard(
                    title: "Private route",
                    systemImage: "lock.shield",
                    outcome: diagnostics.lastPrivateOutcome,
                    untestedHint: "Run the probe below or send a private message to test."
                )
                routeCard(
                    title: "NEAR AI Cloud",
                    systemImage: "cloud.fill",
                    outcome: diagnostics.lastCloudOutcome,
                    untestedHint: "Send a message with a Cloud model to test."
                )
                routeCard(
                    title: "Agent",
                    systemImage: "terminal.fill",
                    outcome: diagnostics.lastAgentOutcome,
                    untestedHint: "Run an Agent task to test."
                )

                probeButton
                resetButton
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .background(HomeSurfaceBackground().ignoresSafeArea())
        .navigationTitle("Connection diagnostics")
        .platformInlineNavigationTitle()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("The exact status and server message from the last request on each route. No translation — this is the raw truth used to diagnose connection problems.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unauthenticatedBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Private session isn't authenticating", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.proofStale)
            Text(unauthenticatedBannerMessage)
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.proofStale.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.proofStale.opacity(0.4), lineWidth: 1)
        }
    }

    /// "While Cloud worked" only when Cloud actually succeeded — the banner
    /// must not claim a comparison that was never run.
    private var unauthenticatedBannerMessage: String {
        let rejection = diagnostics.lastCloudOutcome?.succeeded == true
            ? "The private route rejected your session token while Cloud worked."
            : "The private route rejected your session token."
        return rejection + " This usually means the session expired or the wallet login didn't return a private.near.ai session. Sign out and sign back in; if it persists, the session token isn't valid for the private route."
    }

    private func routeCard(
        title: String,
        systemImage: String,
        outcome: ConnectionDiagnostics.Outcome?,
        untestedHint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if let outcome {
                    statusPill(outcome)
                }
            }

            if let outcome {
                VStack(alignment: .leading, spacing: 6) {
                    detailRow(label: "Message", value: Text(outcome.message))
                    detailRow(label: "Model", value: Text(outcome.modelID))
                    // .relative keeps ticking; a formatted string would freeze
                    // at whatever it said when the view was built.
                    detailRow(label: "When", value: Text(outcome.at, style: .relative) + Text(" ago"))
                }
            } else {
                Text(untestedHint)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.appBorder, lineWidth: 1)
        }
    }

    private func statusPill(_ outcome: ConnectionDiagnostics.Outcome) -> some View {
        Text(outcome.statusLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(outcome.succeeded ? Color.proofVerified : Color.proofStale)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                (outcome.succeeded ? Color.proofVerified : Color.proofStale).opacity(0.14),
                in: Capsule()
            )
    }

    private func detailRow(label: String, value: Text) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            value
                .font(.footnote)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var probeButton: some View {
        Button {
            Task { await chatStore.probePrivateSession() }
        } label: {
            HStack(spacing: 8) {
                if chatStore.isProbingSession {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                }
                Text(chatStore.isProbingSession ? "Probing private session…" : "Run private probe now")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(chatStore.isProbingSession)
        .accessibilityIdentifier("diagnostics.probe")
    }

    private var resetButton: some View {
        Button {
            diagnostics.reset()
        } label: {
            Text("Clear diagnostics")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

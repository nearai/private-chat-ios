import SwiftUI

struct BriefingDetailView: View {
    @ObservedObject var store: BriefingStore
    let briefing: Briefing
    var onFollowUp: (String) -> Void = { _ in }

    @State private var isRunning = false

    private var currentBriefing: Briefing {
        store.briefings.first(where: { $0.id == briefing.id }) ?? briefing
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        BriefingIconChip(briefing: currentBriefing, widget: currentBriefing.latestResult)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(currentBriefing.title)
                                .font(.title3.weight(.semibold))
                            Text(currentBriefing.schedule.scheduleLabel)
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }

                    Text(lastRunText)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(14)
                .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.appBorder, lineWidth: 1)
                }

                Button {
                    Task {
                        isRunning = true
                        await store.run(currentBriefing)
                        isRunning = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isRunning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(isRunning ? "Running" : "Run now")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Color.appPanelBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.actionPrimary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isRunning)

                if let widget = currentBriefing.latestResult {
                    MessageWidgetCard(widget: widget, onFollowUp: onFollowUp)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No result yet")
                            .font(.headline)
                        Text("Run this tracker to generate its first result.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.appBorder, lineWidth: 1)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.appBackground)
        .navigationTitle("Briefing")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lastRunText: String {
        guard let lastRunAt = currentBriefing.lastRunAt else {
            return "Last run: never"
        }
        return "Last run: \(lastRunAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

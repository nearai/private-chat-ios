import SwiftUI

struct HomeSurfaceBackground: View {
    var body: some View {
        ZStack {
            Color.appBackground
            LinearGradient(
                colors: [
                    Color.actionFill.opacity(0.48),
                    Color.proofVerified.opacity(0.08),
                    Color.clear,
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .center
            )
            LinearGradient(
                colors: [
                    Color(red: 0.49, green: 0.36, blue: 0.86).opacity(0.13),
                    Color.brandSky.opacity(0.08),
                    Color.clear
                ],
                startPoint: .topTrailing,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }
}

struct ConversationRow: View {
    let conversation: ConversationSummary
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            SidebarSymbol(
                symbolName: conversation.isPinned ? "pin.fill" : "bubble.left",
                isSelected: isSelected || conversation.isPinned,
                isAction: false
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(conversation.title)
                    .font(.body.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let createdAt = conversation.createdAt {
                    Text(Self.timestampText(for: Date(timeIntervalSince1970: createdAt)))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
            Spacer(minLength: 0)

            if isSelected {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.brandAccent)
                    .frame(width: 4, height: 28)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(isSelected ? Color.brandAccent.opacity(0.07) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.brandAccent.opacity(0.10), lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }

    private static func timestampText(for date: Date) -> String {
        let elapsed = max(0, Date().timeIntervalSince(date))
        if elapsed < 60 {
            return "Just now"
        }
        if elapsed < 3600 {
            return "\(Int(elapsed / 60))m ago"
        }
        if elapsed < 86_400 {
            return "\(Int(elapsed / 3600))h ago"
        }
        if elapsed < 604_800 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

struct SidebarSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .tokenInputTraits()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color.appPanelBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.brandAccent.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: Color.brandAccent.opacity(0.05), radius: 12, y: 6)
    }
}

struct HomeSectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var actionSymbolName: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        if let actionSymbolName {
                            Image(systemName: actionSymbolName)
                                .font(.caption.weight(.bold))
                        }
                        Text(actionTitle)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.primaryAction)
                }
                .buttonStyle(.plain)
                .minimumTouchTarget()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 6)
        .padding(.trailing, 6)
    }
}

struct HomeToolbarIconButton: View {
    let symbolName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbolName)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .minimumTouchTarget()
    }
}

struct ClaudeHomeTopBar: View {
    let displayName: String
    let isSearchVisible: Bool
    let onAccount: () -> Void
    let onSearch: () -> Void
    let onNewChat: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onAccount) {
                Text(avatarLetter)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.actionPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.actionFill, in: Circle())
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44, alignment: .leading)
            .accessibilityLabel("Account")

            Spacer(minLength: 0)

            HStack(spacing: 0) {
                Button(action: onSearch) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3.weight(.regular))
                        .foregroundStyle(isSearchVisible ? Color.actionPrimary : Color.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSearchVisible ? "Hide search" : "Search")

                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil")
                        .font(.title3.weight(.regular))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New chat")
                .accessibilityIdentifier("home.newChat")
            }
        }
        .overlay {
            VStack(spacing: 1) {
                Text("Today")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(Self.dateSubtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .background(Color.appBackground.opacity(0.96))
    }

    private var avatarLetter: String {
        String(displayName.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "A").uppercased()
    }

    private static var dateSubtitle: String {
        Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

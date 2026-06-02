import SwiftUI

struct MetadataPill: View {
    let title: String
    let symbolName: String
    let isPrimary: Bool

    var body: some View {
        Label(title, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isPrimary ? Color.brandBlue : .secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isPrimary ? Color.brandBlue.opacity(0.08) : Color.appSecondaryBackground, in: Capsule())
    }
}

struct ToolbarIcon: View {
    let symbolName: String
    var isPrimary = false

    var body: some View {
        Image(systemName: symbolName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isPrimary ? Color.brandBlue : .secondary)
            .frame(width: 34, height: 34)
            .background(isPrimary ? Color.brandBlue.opacity(0.08) : Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

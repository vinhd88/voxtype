import SwiftUI

/// Card component for selecting a WhisperKit speech model.
struct ModelCardView: View {
    let model: WhisperModel
    let isSelected: Bool
    let isDownloaded: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Image(systemName: model.iconName)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)

                Text(model.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(model.sizeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(model.description)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if isDownloaded {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.gray.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

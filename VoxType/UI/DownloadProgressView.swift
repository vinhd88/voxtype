import SwiftUI

/// Progress bar for model download with percentage and status.
struct DownloadProgressView: View {
    let progress: Double
    let status: TranscriptionService.ModelStatus

    private var displayProgress: Int { Int(progress * 100) }

    var body: some View {
        switch status {
        case .notLoaded:
            EmptyView()

        case .downloading:
            VStack(spacing: 6) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)

                Text("Downloading... \(displayProgress)%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .loading:
            VStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing model...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .ready:
            Label("Model ready!", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(.green)

        case .failed(let msg):
            VStack(spacing: 4) {
                Label("Download failed", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

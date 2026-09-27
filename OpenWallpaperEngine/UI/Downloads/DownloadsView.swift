import SwiftUI

struct DownloadsView: View {
    @ObservedObject var steamCmd: SteamCmdService

    private var downloadIds: [String] {
        let failedIds = steamCmd.downloadProgress.compactMap { workshopId, state in
            if case .failed = state { return workshopId }
            return nil
        }
        let completedIds = steamCmd.downloadProgress.compactMap { workshopId, state in
            if case .completed = state { return workshopId }
            return nil
        }
        return Array(Set((steamCmd.activeDownloadId.map { [$0] } ?? [])
            + steamCmd.queuedDownloadIds
            + failedIds
            + completedIds))
        .sorted { left, right in
            let leftIndex = steamCmd.queuedDownloadIds.firstIndex(of: left) ?? Int.max
            let rightIndex = steamCmd.queuedDownloadIds.firstIndex(of: right) ?? Int.max
            return leftIndex < rightIndex
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Downloads")
                .font(.title2)
                .fontWeight(.semibold)

            if downloadIds.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Workshop downloads and failed retries appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(downloadIds, id: \.self) { workshopId in
                            DownloadRow(workshopId: workshopId, steamCmd: steamCmd)
                        }
                    }
                }
            }
        }
        .padding()
    }
}

private struct DownloadRow: View {
    let workshopId: String
    @ObservedObject var steamCmd: SteamCmdService

    private var item: SteamCmdService.DownloadItem? {
        steamCmd.downloadItems[workshopId]
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                AsyncImage(url: item?.previewURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Rectangle().fill(Color(nsColor: .separatorColor))
                    }
                }
                .frame(width: 112, height: 72)
                .clipped()

                VStack(alignment: .leading, spacing: 6) {
                    Text(item?.title ?? steamCmd.downloadTitles[workshopId] ?? "Workshop item \(workshopId)")
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 12) {
                        if let creatorId = item?.creatorId {
                            Label(
                                SteamPlayerStore.shared.player(for: creatorId)?.personaName ?? creatorId,
                                systemImage: "person"
                            )
                        }
                        if let subscriptions = item?.subscriptions, subscriptions > 0 {
                            Label(formatCount(subscriptions), systemImage: "heart")
                        }
                        if let fileSize = item?.fileSize, fileSize > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if case .failed = steamCmd.downloadProgress[workshopId] {
                    Button {
                        steamCmd.downloadWorkshopItem(
                            workshopId: workshopId,
                            title: item?.title ?? steamCmd.downloadTitles[workshopId],
                            previewURL: item?.previewURL,
                            creatorId: item?.creatorId,
                            subscriptions: item?.subscriptions ?? 0,
                            fileSize: item?.fileSize ?? 0
                        )
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help(failureMessage)
                }
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    ProgressView(value: progress(at: context.date))
                        .tint(progressColor)
                    if let percentage = steamCmd.downloadPercentages[workshopId],
                       isDownloading {
                        Text("\(Int((percentage * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }

            HStack {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(workshopId)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private var statusText: String {
        guard let state = steamCmd.downloadProgress[workshopId] else { return "Queued" }
        switch state {
        case .downloading(let status): return status
        case .completed: return "Downloaded"
        case .failed(let message): return message
        }
    }

    private var progressColor: Color {
        guard let state = steamCmd.downloadProgress[workshopId] else { return .accentColor }
        switch state {
        case .completed: return .green
        case .failed: return .red
        case .downloading: return .accentColor
        }
    }

    private var isDownloading: Bool {
        if case .downloading = steamCmd.downloadProgress[workshopId] {
            return true
        }
        return false
    }

    private func progress(at date: Date) -> Double {
        guard let state = steamCmd.downloadProgress[workshopId] else { return 0.05 }
        switch state {
        case .completed, .failed:
            return 1
        case .downloading(let status):
            if status == "Queued" { return 0.05 }
            if status.contains("Copying") { return 0.92 }
            if let percentage = steamCmd.downloadPercentages[workshopId], percentage > 0 {
                return percentage
            }
            let startedAt = steamCmd.downloadStartedAt[workshopId] ?? date
            return min(0.88, 0.18 + date.timeIntervalSince(startedAt) / 180 * 0.7)
        }
    }

    private var failureMessage: String {
        guard case let .failed(message) = steamCmd.downloadProgress[workshopId] else { return "Retry download" }
        return message
    }

    private func formatCount(_ count: Int) -> String {
        count >= 1_000 ? String(format: "%.1fK", Double(count) / 1_000) : "\(count)"
    }
}

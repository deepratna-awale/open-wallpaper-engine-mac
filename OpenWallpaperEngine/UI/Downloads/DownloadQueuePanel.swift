import SwiftUI

struct DownloadQueuePanel: View {
    @ObservedObject var steamCmd: SteamCmdService
    @State private var isExpanded = true

    private var failedDownloadIds: [String] {
        steamCmd.downloadProgress.compactMap { workshopId, state in
            if case .failed = state {
                return workshopId
            }
            return nil
        }
        .sorted()
    }

    private var queuedDownloadIds: [String] {
        steamCmd.queuedDownloadIds.filter { $0 != steamCmd.activeDownloadId }
    }

    private var hasDownloads: Bool {
        steamCmd.activeDownloadId != nil || !queuedDownloadIds.isEmpty || !failedDownloadIds.isEmpty
    }

    var body: some View {
        if hasDownloads {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    if let activeId = steamCmd.activeDownloadId {
                        statusRow(workshopId: activeId, label: "Downloading")
                    }

                    ForEach(queuedDownloadIds, id: \.self) { workshopId in
                        statusRow(workshopId: workshopId, label: "Queued")
                    }

                    ForEach(failedDownloadIds, id: \.self) { workshopId in
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(downloadTitle(for: workshopId))
                                .lineLimit(1)
                            Spacer()
                            Button {
                                steamCmd.downloadWorkshopItem(
                                    workshopId: workshopId,
                                    title: steamCmd.downloadTitles[workshopId]
                                )
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .help(failureMessage(for: workshopId))
                        }
                        .font(.caption)
                    }
                }
                .padding(.top, 6)
            } label: {
                Label(panelTitle, systemImage: "arrow.down.circle")
                    .font(.callout.weight(.medium))
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .frame(maxWidth: 480, alignment: .leading)
        }
    }

    private var panelTitle: String {
        if !failedDownloadIds.isEmpty {
            return String(localized: "Downloads: \(failedDownloadIds.count) failed")
        }
        return String(localized: "Downloads: \(steamCmd.queuedDownloadIds.count)")
    }

    private func statusRow(workshopId: String, label: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(downloadTitle(for: workshopId))
                .lineLimit(1)
            Spacer()
            Text(label)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private func downloadTitle(for workshopId: String) -> String {
        steamCmd.downloadTitles[workshopId]
            ?? String(localized: "Workshop item \(workshopId)", comment: "Download title before the item's name is known; %@ is its Workshop ID")
    }

    private func failureMessage(for workshopId: String) -> String {
        guard case let .failed(message) = steamCmd.downloadProgress[workshopId] else { return String(localized: "Retry download") }
        return message
    }
}

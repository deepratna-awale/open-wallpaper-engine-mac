import Foundation
import OWEControlProtocol

/// "Export for Android…" for the control channel: the same plan, queue and exporter as the
/// library's sheet, with the wallpapers' own values (what the sheet's preview starts from).
extension AppSystemControlService {
    func exportAndroid(_ request: SystemAndroidRequest) async throws -> AndroidExportBatch {
        guard !isExporting else {
            throw ControlError(.unavailable, "Another export from an MCP client is running. Wait for it to finish, then try again.")
        }
        isExporting = true
        defer { isExporting = false }
        let wallpapers = try request.wallpapers.map(found)
        let options = request.options
        let plan = AndroidExportPlan.make(wallpapers, options: { _ in options }, properties: wallpaperValues)
        let folder = request.outputFolder ?? AndroidExporter.cacheDirectory.appending(path: "Packages", directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw ControlError(.failed, "The folder \(folder.path(percentEncoded: false)) can't be made: \(error.localizedDescription)")
        }
        OWELog.info(.app, "MCP: exporting \(plan.items.count) wallpapers for Android")
        let queue = AndroidExportQueue(items: plan.items, skipped: plan.skipped, folder: folder, worker: AndroidExporter())
        return await withTaskCancellationHandler {
            await queue.run()
        } onCancel: {
            Task { @MainActor in queue.cancel() }
        }
    }
}

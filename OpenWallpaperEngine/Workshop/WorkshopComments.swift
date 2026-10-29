import Foundation
import SwiftUI

/// One comment on a Workshop item, from Community.GetCommentThread through the Steam login.
struct WorkshopComment: Identifiable, Equatable, Sendable {
    let id: String
    let authorId: String
    let date: Date
    let text: String
    let upvotes: Int

    struct Page: Equatable, Sendable {
        let comments: [WorkshopComment]
        /// How many comments the thread has.
        let total: Int
    }

    /// The comments in a GetCommentThread `{"response": …}`, without hidden or deleted ones, and
    /// the thread's total.
    static func page(from data: Data) throws -> Page {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let response = json["response"] as? [String: Any] else { return Page(comments: [], total: 0) }
        let comments = (response["comments"] as? [[String: Any]] ?? []).compactMap { comment -> WorkshopComment? in
            guard comment["hidden"] as? Bool != true, comment["deleted"] as? Bool != true,
                  let id = comment["gidcomment"] as? String,
                  let author = comment["steamid"] as? String,
                  let timestamp = (comment["timestamp"] as? NSNumber)?.doubleValue,
                  let text = comment["text"] as? String else { return nil }
            return WorkshopComment(id: id, authorId: author, date: Date(timeIntervalSince1970: timestamp),
                                   text: plainText(text), upvotes: (comment["upvotes"] as? NSNumber)?.intValue ?? 0)
        }
        return Page(comments: comments, total: (response["total_count"] as? NSNumber)?.intValue ?? comments.count)
    }

    /// Steam's comment markup as plain text: BBCode tags and `<br>` dropped (line breaks kept),
    /// HTML entities decoded.
    static func plainText(_ text: String) -> String {
        var plain = text.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        plain = plain.replacingOccurrences(of: #"\[/?[a-zA-Z*]+(=[^\]]*)?\]"#, with: "", options: .regularExpression)
        for (entity, character) in ["&quot;": "\"", "&#39;": "'", "&lt;": "<", "&gt;": ">", "&amp;": "&"] {
            plain = plain.replacingOccurrences(of: entity, with: character)
        }
        return plain.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A Workshop wallpaper's comments for its details panel, a page at a time, with their authors'
/// names (`SteamPlayerStore`).
@MainActor
final class WorkshopCommentsModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    typealias Creator = (_ workshopId: String) async throws -> String?
    typealias LoadPage = (_ workshopId: String, _ creatorId: String, _ start: Int, _ count: Int) async throws -> WorkshopComment.Page
    typealias Name = (_ steamId: String) async throws -> String?

    nonisolated static let pageSize = 20

    @Published private(set) var comments: [WorkshopComment] = []
    @Published private(set) var total = 0
    @Published private(set) var phase: Phase = .loading
    /// The authors' persona names, as they come in.
    @Published private(set) var names: [String: String] = [:]

    let workshopId: String
    private let creator: Creator
    private let loadPage: LoadPage
    private let name: Name
    private var creatorId: String?
    private var isLoading = false

    init(workshopId: String, creator: @escaping Creator, loadPage: @escaping LoadPage, name: @escaping Name) {
        self.workshopId = workshopId
        self.creator = creator
        self.loadPage = loadPage
        self.name = name
    }

    /// The app's own: through the Steam login's connection.
    convenience init(workshopId: String, steam: SteamHelperClient) {
        let api = WorkshopAPIService(steam: steam)
        self.init(workshopId: workshopId,
                  creator: { id in
                      if let creator = WorkshopMetadataStore.shared.item(for: id)?.creatorId { return creator }
                      return try await api.getItemDetails(workshopIds: [id]).first?.creatorId
                  },
                  loadPage: { try await api.comments(on: $0, creatorId: $1, start: $2, count: $3) },
                  name: { id in
                      if let player = SteamPlayerStore.shared.player(for: id) { return player.personaName }
                      return try await api.getPlayerSummary(steamId: id)?.personaName
                  })
    }

    var hasMore: Bool { phase == .loaded && comments.count < total }

    /// The next page (the first, the first time).
    func loadMore() async {
        guard !isLoading, phase != .loaded || hasMore else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if creatorId == nil { creatorId = try await creator(workshopId) }
            guard let creatorId else { throw WorkshopAPIError.invalidURL }
            let page = try await loadPage(workshopId, creatorId, comments.count, Self.pageSize)
            let known = Set(comments.map(\.id))
            comments += page.comments.filter { !known.contains($0.id) }
            // A page Steam answered with nothing new ends the thread here.
            total = page.comments.isEmpty ? comments.count : page.total
            phase = .loaded
            await loadNames(of: page.comments)
        } catch {
            OWELog.error(.workshop, "Can't read the comments on Workshop item \(workshopId): \(error)")
            if comments.isEmpty { phase = .failed(error.localizedDescription) }
        }
    }

    private func loadNames(of comments: [WorkshopComment]) async {
        var seen = Set(names.keys)
        for comment in comments where seen.insert(comment.authorId).inserted {
            do {
                if let found = try await name(comment.authorId) { names[comment.authorId] = found }
            } catch {
                OWELog.debug(.workshop, "No name for Steam user \(comment.authorId): \(error)")
            }
        }
    }
}

/// The Comments section of a Workshop wallpaper's details panel.
struct WorkshopCommentsView: View {
    @StateObject private var model: WorkshopCommentsModel

    init(workshopId: String, steam: SteamHelperClient) {
        _model = StateObject(wrappedValue: WorkshopCommentsModel(workshopId: workshopId, steam: steam))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch model.phase {
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .failed(let message):
                Text(verbatim: message)
                    .foregroundStyle(.secondary)
            case .loaded where model.comments.isEmpty:
                Text("No Comments")
                    .foregroundStyle(.secondary)
            case .loaded:
                ForEach(model.comments) { comment in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: model.names[comment.authorId] ?? "…")
                                .fontWeight(.semibold)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(comment.date, format: .dateTime.day().month().year())
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        Text(verbatim: comment.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if model.hasMore {
                    Button("Show More Comments") {
                        Task { await model.loadMore() }
                    }
                }
            }
        }
        .task { await model.loadMore() }
    }
}

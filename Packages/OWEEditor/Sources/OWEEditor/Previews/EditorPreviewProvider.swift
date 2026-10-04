import Foundation
import OWESceneEditing

/// One preview to render: what it shows, and where its file goes (without its extension, which
/// the renderer picks: `.heic` for a still, `.mov` for a loop).
public struct EditorPreviewRenderItem: Hashable, Sendable {
    public let subject: EditorPreviewSubject
    public let outputBase: URL

    public init(subject: EditorPreviewSubject, outputBase: URL) {
        self.subject = subject
        self.outputBase = outputBase
    }
}

/// The previews of the effect and particle browsers: each one is read from the cache
/// (`EditorPreviewCache`), else rendered the first time a tile asks for it, off the main thread
/// (the app renders them in its helper process, one batch at a time), then cached for the
/// assets' build. A tile shows a spinner meanwhile.
@MainActor
public final class EditorPreviewProvider: ObservableObject {
    public enum State: Equatable, Sendable {
        case generating
        case ready(URL)
        /// It couldn't be rendered; the tile shows its symbol. Tried again in the next window.
        case failed
    }

    /// Renders `items` in order, calling `finished` for each one as its file is written or it
    /// failed; returns when all are done (or the task is cancelled).
    public typealias Renderer = @Sendable (_ items: [EditorPreviewRenderItem],
                                           _ finished: @escaping @Sendable (EditorPreviewSubject) -> Void) async -> Void

    @Published public private(set) var states: [EditorPreviewSubject: State] = [:]
    public let cache: EditorPreviewCache
    private let renderer: Renderer
    /// Asked for and not yet in a batch, in the order they were asked for.
    private var queue: [EditorPreviewSubject] = []
    private var worker: Task<Void, Never>?

    public init(cache: EditorPreviewCache, renderer: @escaping Renderer) {
        self.cache = cache
        self.renderer = renderer
    }

    public func state(of subject: EditorPreviewSubject) -> State? {
        states[subject]
    }

    /// Shows the subject's preview: at once when it is cached, else once it is rendered.
    public func request(_ subject: EditorPreviewSubject) {
        guard states[subject] == nil else { return }
        states[subject] = .generating
        let cache = cache
        Task {
            let cached = await Task.detached(priority: .userInitiated) { cache.cachedPreview(for: subject) }.value
            if let cached {
                states[subject] = .ready(cached)
            } else {
                queue.append(subject)
                startWorker()
            }
        }
    }

    private func startWorker() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, !Task.isCancelled {
                let batch = self.takeQueue()
                guard !batch.isEmpty else { break }
                await self.render(batch)
            }
            self?.worker = nil
        }
    }

    private func takeQueue() -> [EditorPreviewSubject] {
        defer { queue.removeAll() }
        return queue
    }

    private func render(_ batch: [EditorPreviewSubject]) async {
        let cache = cache
        let items = batch.map { EditorPreviewRenderItem(subject: $0, outputBase: cache.outputBase(for: $0)) }
        await renderer(items) { [weak self] subject in
            Task { @MainActor in self?.resolve(subject) }
        }
        // Whatever the renderer didn't report (it stopped early) is resolved from the disk too.
        for subject in batch where states[subject] == .generating { resolve(subject) }
    }

    private func resolve(_ subject: EditorPreviewSubject) {
        let cache = cache
        Task {
            let cached = await Task.detached(priority: .userInitiated) { cache.cachedPreview(for: subject) }.value
            states[subject] = cached.map(State.ready) ?? .failed
        }
    }
}

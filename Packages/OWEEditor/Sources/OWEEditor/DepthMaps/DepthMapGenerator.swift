import Combine
import CoreGraphics
import Darwin
import Foundation
import os

/// Generates depth maps for depth parallax (`SceneDepthParallax`): one shared service per process,
/// used by both editors. Inference runs off the main thread with Core ML on every compute unit
/// (`CoreMLDepthEstimator`), reports its progress and can be cancelled.
///
/// The model is loaded only to generate: it is released `idleGrace` after the last generation
/// finished or was cancelled (a new generation restarts the wait, so a run of layers loads it
/// once), and is never resident while wallpapers just play. A depth map that was made is a plain
/// texture of the overlay, which needs no model to play. Results are cached by the source's
/// pixels (`DepthMapCache`), so the same layer texture never runs through the model twice.
@MainActor
public final class DepthMapGenerator: ObservableObject {
    /// How long the model stays loaded after a generation, for the next one of a batch.
    public static let idleGrace: TimeInterval = 300
    /// Sources larger than this on their long side are processed at this size: the effect samples
    /// the depth map in the layer's UV space, so its resolution is free, and a bigger one only
    /// costs time and memory.
    public static let maximumSide = 4096

    public enum Phase: Equatable, Sendable {
        case idle
        case preparing
        case loadingModel
        case estimating
        case refining
        case finished
        case cancelled
        case failed(String)
    }

    public enum Failure: LocalizedError, Equatable {
        case notInstalled
        case busy
        case unreadableSource

        public var errorDescription: String? {
            switch self {
            case .notInstalled: return DL("Depth Map Generation isn’t installed. Install it in Settings › Plugins.")
            case .busy: return DL("A depth map is already being generated.")
            case .unreadableSource: return DL("The layer’s picture can’t be read.")
            }
        }
    }

    public struct Result: Sendable {
        /// At the source's resolution (up to `maximumSide`), 0…1, near white.
        public var depth: DepthMapBuffer
        /// The depth map's file: an 8-bit grey PNG.
        public var png: Data
        /// Read from the cache: the model didn't run.
        public var fromCache: Bool
    }

    @Published public private(set) var phase: Phase = .idle
    /// 0…1 over the whole generation.
    @Published public private(set) var progress: Double = 0
    @Published public private(set) var isBusy = false

    /// Whether the model is in memory now (it is only while generating, and for `idleGrace` after).
    public var isModelLoaded: Bool { estimator != nil }

    /// Whether the plugin is installed (read from disk each time: another process may install it).
    public var isInstalled: Bool { locateModel() != nil }

    private let locateModel: () -> DepthMapPluginLayout.ActiveModel?
    private let loadModel: @Sendable (URL) throws -> DepthEstimating
    private let cache: DepthMapCache?
    private let scheduler: DepthMapIdleScheduler
    private let log: @Sendable (String) -> Void
    private var estimator: DepthEstimating?
    private var loadedVersion: String?
    private var footprintBeforeLoad: UInt64?
    private var releaseTimer: DepthMapIdleTimer?
    private var current: Task<Result, Error>?

    /// `locateModel`: the installed model (`DepthMapPluginLayout.activeModel`); `loadModel` loads
    /// it (Core ML; a fake in tests); `scheduler` runs the idle release (a manual clock in tests).
    public init(locateModel: @escaping () -> DepthMapPluginLayout.ActiveModel?,
                loadModel: @escaping @Sendable (URL) throws -> DepthEstimating = { try CoreMLDepthEstimator(contentsOf: $0) },
                cache: DepthMapCache?,
                scheduler: DepthMapIdleScheduler = DispatchDepthMapIdleScheduler(),
                log: @escaping @Sendable (String) -> Void = DepthMapGenerator.defaultLog) {
        self.locateModel = locateModel
        self.loadModel = loadModel
        self.cache = cache
        self.scheduler = scheduler
        self.log = log
    }

    nonisolated public static let defaultLog: @Sendable (String) -> Void = { message in
        Logger(subsystem: "com.winddog.wallpaper-engine", category: "DepthMaps").info("\(message, privacy: .public)")
    }

    // MARK: Generating

    /// The depth map of `source`, smoothed by `smoothing` (0…1). Throws `CancellationError` when
    /// cancelled (`cancel()`, or the calling task's cancellation).
    public func generate(from source: CGImage, smoothing: Double) async throws -> Result {
        guard !isBusy else { throw Failure.busy }
        guard let model = locateModel() else { throw Failure.notInstalled }
        isBusy = true
        phase = .preparing
        progress = 0
        releaseTimer?.cancel()
        releaseTimer = nil
        let work = Task { @MainActor [weak self] () throws -> Result in
            guard let self else { throw CancellationError() }
            return try await self.run(source: source, smoothing: smoothing, model: model)
        }
        current = work
        do {
            let result = try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
            finish(.finished)
            return result
        } catch {
            finish(error is CancellationError ? .cancelled : .failed(error.localizedDescription))
            throw error
        }
    }

    /// Stops the generation in progress (between its steps: a model prediction runs to its end).
    public func cancel() {
        current?.cancel()
    }

    private func finish(_ phase: Phase) {
        current = nil
        isBusy = false
        self.phase = phase
        if phase == .finished { progress = 1 }
        scheduleRelease()
    }

    private func run(source: CGImage, smoothing: Double, model: DepthMapPluginLayout.ActiveModel) async throws -> Result {
        let cache = self.cache
        let prepared = try await Task.detached(priority: .userInitiated) { () throws -> (CGImage, DepthMapBuffer, String?, DepthMapBuffer?) in
            let image = Self.fitted(source)
            guard let guide = DepthMapBuffer.luminance(of: image) else { throw Failure.unreadableSource }
            let key = DepthMapCache.key(for: image, modelVersion: model.version)
            let cached = key.flatMap { cache?.depth(for: $0) }
            return (image, guide, key, cached?.width == guide.width && cached?.height == guide.height ? cached : nil)
        }.value
        try Task.checkCancellation()
        let (image, guide, key, cached) = prepared
        progress = 0.1

        let depth: DepthMapBuffer
        if let cached {
            depth = cached
        } else {
            let estimator = try await loadedEstimator(for: model)
            try Task.checkCancellation()
            phase = .estimating
            progress = 0.3
            let raw = try await Task.detached(priority: .userInitiated) { try estimator.estimate(image) }.value
            try Task.checkCancellation()
            phase = .refining
            progress = 0.7
            depth = await Task.detached(priority: .userInitiated) { () -> DepthMapBuffer in
                let normalized = DepthMapProcessing.normalized(raw, inverseDepth: estimator.outputIsInverseDepth)
                let upscaled = DepthMapProcessing.upscaled(normalized, guide: guide)
                if let key { try? cache?.store(upscaled, for: key) } // A cache: failing to keep it costs a later run.
                return upscaled
            }.value
            try Task.checkCancellation()
        }
        phase = .refining
        progress = 0.85
        let result = try await Task.detached(priority: .userInitiated) { () throws -> Result in
            let smoothed = DepthMapProcessing.smoothed(depth, guide: guide, smoothing: smoothing)
            guard let png = smoothed.pngData() else { throw Failure.unreadableSource }
            return Result(depth: smoothed, png: png, fromCache: cached != nil)
        }.value
        try Task.checkCancellation()
        return result
    }

    /// The model, loaded off the main thread unless it is in memory.
    private func loadedEstimator(for model: DepthMapPluginLayout.ActiveModel) async throws -> DepthEstimating {
        if let estimator, loadedVersion == model.version { return estimator }
        releaseModel()
        phase = .loadingModel
        progress = 0.15
        let before = ResidentMemory.footprint()
        let load = loadModel
        let started = Date()
        let estimator = try await Task.detached(priority: .userInitiated) { try load(model.url) }.value
        let after = ResidentMemory.footprint()
        self.estimator = estimator
        loadedVersion = model.version
        footprintBeforeLoad = before
        log("Depth model \(model.version) loaded in \(String(format: "%.2f", Date().timeIntervalSince(started))) s; resident memory \(ResidentMemory.describeDelta(from: before, to: after))")
        return estimator
    }

    // MARK: Releasing the model

    /// Releases the model `idleGrace` from now, unless a generation starts first.
    private func scheduleRelease() {
        releaseTimer?.cancel()
        guard estimator != nil else {
            releaseTimer = nil
            return
        }
        releaseTimer = scheduler.schedule(after: Self.idleGrace) { [weak self] in
            self?.releaseModel()
        }
    }

    /// Lets go of the model and everything Core ML loaded for it.
    public func releaseModel() {
        releaseTimer?.cancel()
        releaseTimer = nil
        guard estimator != nil else { return }
        let before = ResidentMemory.footprint()
        estimator = nil
        loadedVersion = nil
        let after = ResidentMemory.footprint()
        log("Depth model released; resident memory \(ResidentMemory.describeDelta(from: before, to: after))"
            + (footprintBeforeLoad.map { ", \(ResidentMemory.describeDelta(from: $0, to: after)) against before it loaded" } ?? ""))
        footprintBeforeLoad = nil
    }

    /// `source` scaled down to `maximumSide` when larger.
    nonisolated static func fitted(_ source: CGImage) -> CGImage {
        let longSide = max(source.width, source.height)
        guard longSide > maximumSide else { return source }
        let scale = Double(maximumSide) / Double(longSide)
        let width = max(1, Int((Double(source.width) * scale).rounded()))
        let height = max(1, Int((Double(source.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return source }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? source
    }
}

// MARK: - The idle clock

/// A pending idle release.
@MainActor
public protocol DepthMapIdleTimer: AnyObject {
    func cancel()
}

/// Runs the idle release later on the main actor; a manual clock in tests.
@MainActor
public protocol DepthMapIdleScheduler: AnyObject {
    func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> DepthMapIdleTimer
}

/// The real clock: the main queue.
@MainActor
public final class DispatchDepthMapIdleScheduler: DepthMapIdleScheduler {
    public init() {}

    private final class Pending: DepthMapIdleTimer {
        let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }

    public func schedule(after seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) -> DepthMapIdleTimer {
        let item = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return Pending(item)
    }
}

// MARK: - Memory

/// The process's physical footprint (what Activity Monitor calls Memory), to log what loading and
/// releasing the model costs.
enum ResidentMemory {
    static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    static func describeDelta(from before: UInt64?, to after: UInt64?) -> String {
        guard let before, let after else { return "unknown" }
        let delta = Int64(bitPattern: after) - Int64(bitPattern: before)
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        let sign = delta >= 0 ? "+" : "−"
        return "\(sign)\(formatter.string(fromByteCount: abs(delta))) (now \(formatter.string(fromByteCount: Int64(after))))"
    }
}

import AppKit
import SwiftUI
import OWEInspectorKit
import OWESceneEditing

/// The state of one depth map section: the depth map made for the layer (or the scene) but not
/// applied yet, its preview, and what went wrong. Applied depth maps live in the overlay
/// (`SceneDepthParallax`); this only holds a generation until it is applied.
@MainActor
public final class DepthMapSectionModel: ObservableObject {
    public let session: SceneEditSession
    /// Nil: the whole scene.
    public let layerID: Int?
    public let services: DepthMapEditorServices

    /// The newest depth map made here (`depth/editor_…`), applied or not.
    @Published public private(set) var generatedTexture: String?
    @Published public private(set) var depthPreview: CGImage?
    @Published public private(set) var isOneFrame = false
    @Published public var showsDepthPreview = true
    @Published public var smoothing = 0.25
    /// The strength a new depth parallax starts with.
    @Published public var pendingStrength = SceneDepthParallax.defaultStrength
    @Published public var problem: String?

    public init(session: SceneEditSession, layerID: Int?, services: DepthMapEditorServices) {
        self.session = session
        self.layerID = layerID
        self.services = services
        if let texture = appliedTexture {
            depthPreview = services.texture(texture)
        }
    }

    // MARK: What is applied

    /// The layer the effect is on: the layer itself, or the fullscreen layer above it (a particle
    /// system, the scene).
    public var effectLayer: Int? {
        guard let layerID else { return session.depthParallaxLayer(above: nil) }
        guard let layer = session.outline.layer(layerID) else { return nil }
        switch SceneDepthParallax.placement(for: layer) {
        case .onLayer: return session.depthParallaxEffect(of: layerID) != nil ? layerID : nil
        case .layerAbove: return session.depthParallaxLayer(above: layerID)
        case nil: return nil
        }
    }

    public var isApplied: Bool { effectLayer != nil }

    public var appliedTexture: String? { effectLayer.flatMap(session.depthParallaxTexture) }

    /// Whether the layer can take depth parallax at all.
    public var isSupported: Bool {
        guard let layerID else { return true }
        return session.outline.layer(layerID).flatMap(SceneDepthParallax.placement) != nil
    }

    /// Before generating: whether the picture will come from one rendered frame.
    public var comesFromOneFrame: Bool {
        guard let layerID, let layer = session.outline.layer(layerID) else { return true }
        return layer.kind == .particle || layer.fillsScene
    }

    public var strength: Double {
        get { effectLayer.flatMap(session.depthParallaxStrength) ?? pendingStrength }
        set {
            pendingStrength = newValue
            if let effectLayer {
                session.setDepthParallaxStrength(newValue, of: effectLayer, actionName: DL("Change Depth Parallax Strength"))
            }
        }
    }

    // MARK: Generating

    /// Generates the depth map; when depth parallax is applied already, binds it to the new one.
    public func generate() async {
        problem = nil
        let generator = services.generator
        do {
            let source = try await services.source(session.depthMapRequest(for: layerID))
            try Task.checkCancellation()
            let result = try await generator.generate(from: source.image, smoothing: smoothing)
            let title = layerID.flatMap { session.outline.layer($0)?.name } ?? "scene"
            let texture = try services.assetStore.saveDepthMap(result.png, title: title.isEmpty ? "layer" : title)
            generatedTexture = texture
            depthPreview = result.depth.grayImage()
            isOneFrame = source.isOneFrame
            showsDepthPreview = true
            if let effectLayer, session.depthParallaxTexture(of: effectLayer) != texture {
                session.setDepthParallaxTexture(texture, of: effectLayer, actionName: DL("Update Depth Map"))
            }
        } catch is CancellationError {
            return
        } catch {
            problem = error.localizedDescription
        }
    }

    public func cancel() {
        services.generator.cancel()
    }

    // MARK: Applying

    /// Adds WE's depth parallax effect bound to the generated depth map: on the layer, or on a
    /// fullscreen layer above it (a particle system) or on top of the scene. One undo step.
    public func apply() {
        guard let texture = generatedTexture ?? appliedTexture else { return }
        problem = nil
        do {
            try services.prepareEffect()
        } catch {
            problem = error.localizedDescription
            return
        }
        let action = DL("Apply Depth Parallax")
        guard let layerID else {
            session.addDepthParallaxLayer(texture: texture, strength: pendingStrength, above: nil,
                                          name: DL("Scene Depth Parallax"), actionName: action)
            return
        }
        guard let layer = session.outline.layer(layerID) else { return }
        switch SceneDepthParallax.placement(for: layer) {
        case .onLayer:
            session.applyDepthParallax(texture: texture, strength: pendingStrength, to: layerID, actionName: action)
        case .layerAbove:
            session.addDepthParallaxLayer(texture: texture, strength: pendingStrength, above: layerID,
                                          name: DL("Depth Parallax"), actionName: action)
        case nil:
            break
        }
    }

    /// Removes the effect (and the fullscreen layer that carried it). One undo step.
    public func remove() {
        guard let effectLayer else { return }
        let action = DL("Remove Depth Parallax")
        if effectLayer != layerID, session.outline.layer(effectLayer)?.fillsScene == true {
            session.delete([effectLayer], actionName: action)
        } else {
            session.removeDepthParallax(of: effectLayer, actionName: action)
        }
    }
}

/// The Depth Map controls, the same in both editors: Generate, a preview of the depth map,
/// smoothing and strength, Apply Depth Parallax and Remove; or, without the plugin, the way to
/// install it.
public struct DepthMapControls: View {
    @ObservedObject var model: DepthMapSectionModel
    @ObservedObject var session: SceneEditSession
    @ObservedObject var generator: DepthMapGenerator
    @State private var work: Task<Void, Never>?

    public init(model: DepthMapSectionModel) {
        self.model = model
        session = model.session
        generator = model.services.generator
    }

    public var body: some View {
        if !generator.isInstalled {
            VStack(alignment: .leading, spacing: 6) {
                Text(DL("Generate a depth map with on-device machine learning to give this depth parallax that follows the pointer."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(DL("Install Depth Map Generation")) { model.services.openPlugins() }
                    .help(DL("Opens Settings › Plugins, where Depth Map Generation can be installed."))
            }
        } else if !model.isSupported {
            Text(DL("This kind of layer can’t have depth parallax."))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            controls
        }
    }

    @ViewBuilder private var controls: some View {
        if model.comesFromOneFrame || model.isOneFrame {
            Label(DL("The depth comes from one frame of the scene."), systemImage: "film")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let preview = model.depthPreview, model.showsDepthPreview {
            Image(decorative: preview, scale: 1)
                .resizable()
                .interpolation(.medium)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel(DL("Depth map preview"))
        }
        Toggle(DL("Preview Depth Map"), isOn: $model.showsDepthPreview)
            .disabled(model.depthPreview == nil)
            .help(DL("Shows the depth map: white is near, black is far."))
        LabeledContent(DL("Smoothing")) {
            NumericSliderInput<Double>(value: $model.smoothing, range: 0...1, defaultValue: 0.25, step: 0.05,
                                       displayScale: 100, suffix: "%", fractionDigits: 0, fieldWidth: 44)
        }
        .help(DL("Evens out the depth map’s flat areas while keeping the picture’s edges. Applies to the next generation."))
        HStack {
            if generator.isBusy {
                ProgressView(value: generator.progress) {
                    Text(phaseTitle)
                }
                Button(DL("Cancel")) { model.cancel() }
            } else {
                Button(model.generatedTexture == nil && !model.isApplied ? DL("Generate") : DL("Generate Again")) {
                    work = Task { await model.generate() }
                }
                .help(DL("Estimates the depth of the picture on this Mac. Nothing is uploaded."))
            }
            Spacer()
        }
        LabeledContent(DL("Strength")) {
            NumericSliderInput<Double>(value: Binding(get: { model.strength }, set: { model.strength = $0 }),
                                       range: SceneDepthParallax.strengthRange, defaultValue: SceneDepthParallax.defaultStrength,
                                       step: 0.01, fractionDigits: 2, fieldWidth: 52)
        }
        .help(DL("How far the picture shifts with the pointer."))
        HStack {
            if model.isApplied {
                Button(DL("Remove Depth Parallax"), role: .destructive) { model.remove() }
            } else {
                Button(DL("Apply Depth Parallax")) { model.apply() }
                    .disabled(model.generatedTexture == nil || generator.isBusy)
                    .help(DL("Adds Wallpaper Engine’s Depth Parallax effect, bound to this depth map."))
            }
            Spacer()
        }
        if let problem = model.problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        }
    }

    private var phaseTitle: String {
        switch generator.phase {
        case .loadingModel: return DL("Loading the model…")
        case .estimating: return DL("Estimating depth…")
        case .refining: return DL("Refining edges…")
        default: return DL("Preparing…")
        }
    }
}

/// The Depth Map section of the Wallpaper Editor's inspector (a layer) or of its scene form.
struct DepthMapSection: View {
    @StateObject private var model: DepthMapSectionModel

    init(session: SceneEditSession, layerID: Int?, services: DepthMapEditorServices) {
        _model = StateObject(wrappedValue: DepthMapSectionModel(session: session, layerID: layerID, services: services))
    }

    var body: some View {
        Section(model.layerID == nil ? DL("Scene Depth Parallax") : DL("Depth Map")) {
            DepthMapControls(model: model)
        }
    }
}

/// The same controls in a box, for a scrolling column (the Wallpaper Editor's scene form, the
/// Scene Editor's object detail).
public struct DepthMapBox: View {
    @StateObject private var model: DepthMapSectionModel

    public init(session: SceneEditSession, layerID: Int?, services: DepthMapEditorServices) {
        _model = StateObject(wrappedValue: DepthMapSectionModel(session: session, layerID: layerID, services: services))
    }

    public var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                DepthMapControls(model: model)
            }
            .padding(4)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(model.layerID == nil ? DL("Scene Depth Parallax") : DL("Depth Map")).font(.headline)
        }
    }
}

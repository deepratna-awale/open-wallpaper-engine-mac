import OWESceneEditing
import SwiftUI

extension PuppetWorkspace.Tool {
    var title: String {
        switch self {
        case .mesh: return PL("Mesh")
        case .skeleton: return PL("Skeleton")
        case .weights: return PL("Weights")
        case .animate: return PL("Animate")
        case .physics: return PL("Physics")
        }
    }

    var symbol: String {
        switch self {
        case .mesh: return "triangle"
        case .skeleton: return "figure.stand"
        case .weights: return "paintbrush.pointed"
        case .animate: return "film.stack"
        case .physics: return "wind"
        }
    }

    var hint: String {
        switch self {
        case .mesh: return PL("Click a vertex to select it, drag to move. Shift adds to the selection; Delete removes it.")
        case .skeleton: return PL("Drag a joint to move a bone (Option leaves its children), the end handle to turn it.")
        case .weights: return PL("Click a joint to pick its bone, then paint. Option paints the other way.")
        case .animate: return PL("Pose bones at the current frame: each change sets a key.")
        case .physics: return PL("Drag the canvas to shake the puppet and watch its physics bones.")
        }
    }
}

/// Puppet Warp (WE's editor: mesh, skeleton, weights, animations, bone physics) for one image
/// layer, over the editor window in a sheet: tools on top, the canvas, the tool's panel on the
/// right, the timeline below while animating.
struct PuppetWorkspaceView: View {
    @StateObject private var workspace: PuppetWorkspace
    @ObservedObject private var session: SceneEditSession
    private let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingDiscard = false

    init(session: SceneEditSession, layer: SceneLayer, assets: PuppetEditorAssets) {
        _workspace = StateObject(wrappedValue: PuppetWorkspace(session: session, layerID: layer.id,
                                                               source: PuppetSource.load(layer: layer, assets: assets)))
        self.session = session
        title = layer.title
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if workspace.document == nil {
                emptyState
            } else {
                HSplitView {
                    VStack(spacing: 0) {
                        PuppetCanvasView(workspace: workspace)
                            .overlay(alignment: .topLeading) { hint }
                        if workspace.tool == .animate || workspace.tool == .physics {
                            Divider()
                            PuppetTimelineView(workspace: workspace)
                        }
                    }
                    .frame(minWidth: 520)
                    PuppetSidePanel(workspace: workspace)
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
                }
            }
        }
        .frame(minWidth: 1000, idealWidth: 1280, minHeight: 680, idealHeight: 820)
        .onDisappear { workspace.stop() }
        .alert(PL("Discard the Puppet Edits?"), isPresented: $isConfirmingDiscard) {
            Button(PL("Discard"), role: .destructive) { workspace.discardEdits() }
            Button(PL("Cancel"), role: .cancel) {}
        } message: {
            Text(PL("The layer’s puppet goes back to how the wallpaper has it. You can undo this."))
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { session.undo() } label: { Label(PL("Undo"), systemImage: "arrow.uturn.backward") }
                .help(session.undoManager.undoMenuItemTitle)
                .disabled(!session.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            Button { session.redo() } label: { Label(PL("Redo"), systemImage: "arrow.uturn.forward") }
                .help(session.undoManager.redoMenuItemTitle)
                .disabled(!session.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Divider().frame(height: 18)
            Picker(PL("Tool"), selection: $workspace.tool) {
                ForEach(PuppetWorkspace.Tool.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbol).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(workspace.document == nil)
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(title).font(.headline)
                Text(PL("Puppet Warp")).font(.caption).foregroundStyle(.secondary)
            }
            if workspace.hasEdits {
                Button(PL("Discard Edits…")) { isConfirmingDiscard = true }
                    .help(PL("Go back to the puppet as the wallpaper has it"))
            }
            Button(PL("Done")) { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var hint: some View {
        Text(workspace.tool.hint)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .editorGlass(in: Capsule())
            .padding(10)
            .allowsHitTesting(false)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.wave").font(.system(size: 44)).foregroundStyle(.secondary)
            Text(PL("This layer has no puppet yet")).font(.title3)
            Text(PL("A puppet bends the image with a mesh and bones. The mesh is fitted to the image’s opaque pixels."))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            if let error = workspace.source?.error {
                Label(PL("The puppet can’t be read: \(error)"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
            Button(PL("Create Puppet")) { workspace.createPuppet() }
                .buttonStyle(.borderedProminent)
                .disabled(workspace.source == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The Animate and Physics tools' timeline: the clip, playback and the frames with keys.
struct PuppetTimelineView: View {
    @ObservedObject var workspace: PuppetWorkspace

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button { workspace.togglePlayback() } label: {
                    Label(workspace.isPlaying ? PL("Pause") : PL("Play"), systemImage: workspace.isPlaying ? "pause.fill" : "play.fill")
                        .labelStyle(.iconOnly)
                }
                .help(workspace.isPlaying ? PL("Pause") : PL("Play"))
                Picker(PL("Animation"), selection: Binding(get: { workspace.clipIndex ?? -1 },
                                                          set: { workspace.clipIndex = $0 < 0 ? nil : $0; workspace.frame = 0 })) {
                    if workspace.document?.clips.isEmpty ?? true { Text(PL("No Animation")).tag(-1) }
                    ForEach(Array((workspace.document?.clips ?? []).enumerated()), id: \.offset) { index, clip in
                        Text(clip.name).tag(index)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
                Button { workspace.addClip() } label: { Label(PL("New Animation"), systemImage: "plus").labelStyle(.iconOnly) }
                    .help(PL("New Animation"))
                Toggle(PL("Play Layers"), isOn: $workspace.previewsLayers)
                    .toggleStyle(.checkbox)
                    .help(PL("Play the image’s animation layers, as the wallpaper will"))
                Spacer()
                if workspace.tool == .animate {
                    Toggle(PL("Onion Skin"), isOn: $workspace.showsOnionSkin).toggleStyle(.checkbox)
                    Stepper(value: $workspace.onionFrames, in: 1...5) {
                        Text(onionLabel).monospacedDigit()
                    }
                    .disabled(!workspace.showsOnionSkin)
                    Button(PL("Add Key")) { workspace.addKey() }
                        .disabled(workspace.clip == nil)
                        .help(PL("Key the selected bone (every bone without a selection) at this frame"))
                    Button(PL("Delete Key")) { workspace.deleteKey() }
                        .disabled(!workspace.keyFrames.contains(Int(workspace.frame.rounded())))
                }
                Text(verbatim: "\(Int(workspace.frame.rounded())) / \(workspace.clip?.frames ?? 0)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 60, alignment: .trailing)
            }
            PuppetFrameRuler(workspace: workspace)
                .frame(height: 30)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

extension PuppetTimelineView {
    private var onionLabel: String {
        let number = workspace.onionFrames
        return PL("\(number) frames")
    }
}

/// The clip's frames: ticks, key diamonds and the playhead; drag to scrub.
struct PuppetFrameRuler: View {
    @ObservedObject var workspace: PuppetWorkspace

    var body: some View {
        GeometryReader { proxy in
            let frames = max(workspace.clip?.frames ?? 1, 1)
            let width = Double(proxy.size.width)
            let x = { (frame: Double) -> Double in 8 + (width - 16) * frame / Double(frames) }
            Canvas { context, size in
                context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6),
                             with: .color(.secondary.opacity(0.12)))
                let step = max(1, Int((Double(frames) / max((width - 16) / 8, 1)).rounded(.up)))
                for frame in stride(from: 0, through: frames, by: step) {
                    var tick = Path()
                    let major = frame % (step * 5) == 0
                    tick.move(to: CGPoint(x: x(Double(frame)), y: size.height))
                    tick.addLine(to: CGPoint(x: x(Double(frame)), y: size.height - (major ? 10 : 5)))
                    context.stroke(tick, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
                }
                for key in workspace.keyFrames where key <= frames {
                    let centre = CGPoint(x: x(Double(key)), y: size.height / 2 - 3)
                    var diamond = Path()
                    diamond.move(to: CGPoint(x: centre.x, y: centre.y - 5))
                    diamond.addLine(to: CGPoint(x: centre.x + 5, y: centre.y))
                    diamond.addLine(to: CGPoint(x: centre.x, y: centre.y + 5))
                    diamond.addLine(to: CGPoint(x: centre.x - 5, y: centre.y))
                    diamond.closeSubpath()
                    context.fill(diamond, with: .color(.yellow))
                    context.stroke(diamond, with: .color(.black.opacity(0.6)), lineWidth: 0.75)
                }
                var head = Path()
                let px = x(Double(workspace.frame))
                head.move(to: CGPoint(x: px, y: 0))
                head.addLine(to: CGPoint(x: px, y: size.height))
                context.stroke(head, with: .color(.accentColor), lineWidth: 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard workspace.clip != nil else { return }
                let frame = (Double(value.location.x) - 8) / max(width - 16, 1) * Double(frames)
                workspace.frame = Float(min(max(frame, 0), Double(frames)).rounded())
            })
        }
    }
}

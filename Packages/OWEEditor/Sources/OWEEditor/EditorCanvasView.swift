import AppKit
import SwiftUI
import OWESceneEditing

/// The canvas: the live wallpaper at the viewport's zoom and pan, with the selection's gizmo over
/// it. Click picks the topmost layer under the pointer, dragging moves it (snapping to the scene
/// and the other layers; ⌘ while dragging moves freely); the corners scale (Shift: each side on its
/// own) and the handle above the top edge rotates (Shift: 15° steps). Double-click a text layer to
/// edit its text. Scroll or Space-drag pans, pinch or ⌘-scroll zooms, the arrow keys nudge, Delete
/// deletes. Files dropped on it are imported (images become layers where they are dropped). While
/// a mask is being painted, dragging over its layer paints.
struct EditorCanvasView: View {
    @ObservedObject var session: SceneEditSession
    @ObservedObject var tools: EditorTools
    let services: WallpaperEditorServices
    @State private var viewport: CanvasViewport
    @State private var canvas: AnyView?
    @State private var hovered: Int?
    @State private var pointer: SIMD2<Double>?
    @State private var gesture: CanvasGesture?
    @State private var isDropTargeted = false
    private let makeCanvas: () -> AnyView
    /// The particle systems' handles (`ParticleCanvasInteraction`); nil without the particle editor.
    private let particles: ParticleEditorServices?

    private enum CanvasGesture {
        case pan(startPan: SIMD2<Double>, startPoint: SIMD2<Double>)
        case transform(layer: Int, drag: LayerGizmo.Drag, startPoint: SIMD2<Double>, moved: Bool)
        case paint
        case particle(ParticleCanvasDrag)
    }

    /// A press moves this far (points) before it drags, so a click never nudges a layer.
    private static let dragThreshold: Double = 3

    init(session: SceneEditSession, tools: EditorTools, services: WallpaperEditorServices) {
        self.session = session
        self.tools = tools
        self.services = services
        makeCanvas = services.makeCanvas
        particles = services.particles
        // A 3D scene has no 2D size: its view is framed 16:9 and has no gizmo.
        _viewport = State(initialValue: CanvasViewport(sceneSize: session.outline.size ?? SIMD2(1920, 1080),
                                                       canvasSize: SIMD2(800, 600)))
    }

    private var actions: LayerActions { LayerActions(session: session, services: services, tools: tools) }

    var body: some View {
        GeometryReader { proxy in
            let rect = viewport.sceneRect
            ZStack(alignment: .topLeading) {
                Color(nsColor: .underPageBackgroundColor)
                canvas
                    .frame(width: max(rect.size.x, 1), height: max(rect.size.y, 1))
                    .clipped()
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .position(x: rect.origin.x + rect.size.x / 2, y: rect.origin.y + rect.size.y / 2)
                    .allowsHitTesting(false)
                GizmoOverlay(session: session, tools: tools, viewport: viewport, hovered: hovered, pointer: pointer)
                    .allowsHitTesting(false)
                if let particles {
                    ParticleCanvasOverlay(services: particles, viewport: viewport)
                        .allowsHitTesting(false)
                }
                CanvasEventView(handlers: handlers)
                if let editing = session.editingText {
                    CanvasTextEditor(session: session, layerID: editing, viewport: viewport)
                }
                if isDropTargeted {
                    Rectangle()
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .dropDestination(for: URL.self) { urls, location in
                let point = viewport.scenePoint(SIMD2(Double(location.x), Double(location.y)))
                actions.importDropped(urls, at: session.outline.size == nil ? nil : point)
                return !urls.isEmpty
            } isTargeted: { isDropTargeted = $0 && services.assetStore != nil }
            .onAppear {
                if canvas == nil { canvas = makeCanvas() }
                viewport.backingScale = Double(NSScreen.main?.backingScaleFactor ?? 2)
                viewport.resize(canvas: SIMD2(Double(proxy.size.width), Double(proxy.size.height)))
                viewport.fit()
            }
            .onChange(of: proxy.size) { _, size in
                viewport.resize(canvas: SIMD2(Double(size.width), Double(size.height)))
            }
        }
        .overlay(alignment: .bottom) { zoomControls }
        .overlay(alignment: .top) {
            if let painting = tools.maskPainting {
                MaskPaintingHUD(painting: painting, session: session, tools: tools, services: services)
                    .padding(.top, 12)
            }
        }
        .overlay(alignment: .topLeading) {
            if session.outline.size == nil {
                Label(L("Layers of a 3D scene are edited in the inspector."), systemImage: "cube")
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .editorGlass(in: Capsule())
                    .padding(12)
            }
        }
    }

    // MARK: Zoom

    private var zoomControls: some View {
        HStack(spacing: 4) {
            Button { withAnimation(.snappy) { viewport.zoomOut() } } label: {
                Label(L("Zoom Out"), systemImage: "minus.magnifyingglass").labelStyle(.iconOnly)
            }
            .keyboardShortcut("-", modifiers: .command)
            .help(L("Zoom Out"))
            Menu {
                Button(L("Zoom to Fit")) { withAnimation(.snappy) { viewport.fit() } }
                    .keyboardShortcut("0", modifiers: .command)
                Button(L("Actual Size")) { withAnimation(.snappy) { viewport.actualSize() } }
                Divider()
                ForEach([0.25, 0.5, 1, 2, 4], id: \.self) { factor in
                    Button(factor.formatted(.percent)) {
                        withAnimation(.snappy) { viewport.zoom(to: factor / max(viewport.backingScale, 1)) }
                    }
                }
            } label: {
                Text(viewport.zoomFactor.formatted(.percent.precision(.fractionLength(0))))
                    .monospacedDigit()
                    .frame(minWidth: 52)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(L("Zoom"))
            Button { withAnimation(.snappy) { viewport.zoomIn() } } label: {
                Label(L("Zoom In"), systemImage: "plus.magnifyingglass").labelStyle(.iconOnly)
            }
            .keyboardShortcut("=", modifiers: .command)
            .help(L("Zoom In"))
            Divider().frame(height: 16)
            Toggle(isOn: $tools.snapping) {
                Label(L("Snapping"), systemImage: "squareshape.split.2x2.dotted").labelStyle(.iconOnly)
            }
            .toggleStyle(.button)
            .help(L("Snap layers to the scene and to each other while dragging"))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .editorGlass(in: Capsule())
        .padding(.bottom, 14)
    }

    // MARK: Input

    private var handlers: CanvasEventView.Handlers {
        var handlers = CanvasEventView.Handlers()
        handlers.mouseDown = { point, event, pans in mouseDown(point, event: event, pans: pans) }
        handlers.mouseDragged = { point, event in mouseDragged(point, event: event) }
        handlers.mouseUp = { _, _ in mouseUp() }
        handlers.mouseMoved = { point in
            if pointer != point { pointer = point }
            let layer = point.flatMap { session.layer(at: viewport.scenePoint($0)) }
            if hovered != layer { hovered = layer }
        }
        handlers.scroll = { delta, point, event in
            if event.modifierFlags.contains(.command) {
                viewport.zoom(to: viewport.scale * (1 + delta.y / 200), anchor: point)
            } else {
                viewport.pan += delta
            }
        }
        handlers.magnify = { factor, point in viewport.zoom(to: viewport.scale * factor, anchor: point) }
        handlers.key = { event in key(event) }
        handlers.cursor = { point in cursor(at: point) }
        return handlers
    }

    private func mouseDown(_ point: SIMD2<Double>, event: NSEvent, pans: Bool) {
        if pans {
            gesture = .pan(startPan: viewport.pan, startPoint: point)
            NSCursor.closedHand.set()
            return
        }
        if let particles, let drag = ParticleCanvasInteraction.press(at: point, viewport: viewport, services: particles) {
            gesture = .particle(drag)
            return
        }
        let scenePoint = viewport.scenePoint(point)
        if let painting = tools.maskPainting {
            if let local = maskPoint(scenePoint, painting: painting) {
                painting.begin(at: local)
                gesture = .paint
            }
            return
        }
        // Double-click a text layer: edit its text where it is.
        if event.clickCount == 2, let picked = session.layer(at: scenePoint),
           session.outline.layer(picked)?.kind == .text, session.textScript(of: picked) == nil,
           session.isEditable("text", of: picked) {
            session.selection = picked
            session.editingText = picked
            gesture = nil
            return
        }
        // The selection's handles first, so a corner over another layer still scales.
        if let selected = session.selection, !session.isLocked(selected), let geometry = session.geometry(of: selected),
           let handle = LayerGizmo.handle(at: point, geometry: geometry, viewport: viewport) {
            gesture = .transform(layer: selected, drag: LayerGizmo.Drag(handle: handle, start: geometry, startPoint: scenePoint),
                                 startPoint: point, moved: false)
            return
        }
        let picked = session.layer(at: scenePoint)
        session.selection = picked
        if session.editingText != nil, session.editingText != picked { session.editingText = nil }
        if let picked, let geometry = session.geometry(of: picked) {
            gesture = .transform(layer: picked, drag: LayerGizmo.Drag(handle: .body, start: geometry, startPoint: scenePoint),
                                 startPoint: point, moved: false)
        } else {
            gesture = nil
        }
    }

    private func mouseDragged(_ point: SIMD2<Double>, event: NSEvent) {
        if pointer != point { pointer = point }
        switch gesture {
        case .pan(let startPan, let startPoint):
            viewport.pan = startPan + (point - startPoint)
        case .transform(let layer, let drag, let startPoint, let moved):
            let distance = ((point - startPoint) * (point - startPoint)).sum().squareRoot()
            guard moved || distance >= Self.dragThreshold else { return }
            if !moved { gesture = .transform(layer: layer, drag: drag, startPoint: startPoint, moved: true) }
            let shift = event.modifierFlags.contains(.shift)
            let scenePoint = viewport.scenePoint(point)
            if drag.handle == .body, tools.snapping, !event.modifierFlags.contains(.command), session.outline.size != nil {
                let snapped = session.snappedMove(drag, layer: layer, to: scenePoint,
                                                  threshold: EditorTools.snapDistance / max(viewport.scale, 1e-6))
                session.dragPreview = (layer, snapped.transform)
                tools.guides = snapped.guides
            } else {
                session.dragPreview = (layer, drag.transform(at: scenePoint, free: shift, snap: shift))
                if !tools.guides.isEmpty { tools.guides = [] }
            }
        case .paint:
            if let painting = tools.maskPainting, let local = maskPoint(viewport.scenePoint(point), painting: painting, clamped: true) {
                painting.dab(to: local)
            }
        case .particle(var drag):
            guard let particles else { return }
            ParticleCanvasInteraction.drag(&drag, to: point, viewport: viewport,
                                           free: event.modifierFlags.contains(.shift), services: particles)
            gesture = .particle(drag)
        case nil:
            break
        }
    }

    private func mouseUp() {
        defer { gesture = nil }
        if !tools.guides.isEmpty { tools.guides = [] }
        if case .particle(let drag)? = gesture, let particles {
            ParticleCanvasInteraction.end(drag, services: particles)
            return
        }
        if case .paint? = gesture {
            tools.maskPainting?.end()
            return
        }
        guard case .transform(_, let drag, _, let moved)? = gesture else { return }
        guard moved else { session.dragPreview = nil; return }
        switch drag.handle {
        case .body: session.endDrag(actionName: L("Move Layer"))
        case .corner: session.endDrag(actionName: L("Scale Layer"))
        case .rotate: session.endDrag(actionName: L("Rotate Layer"))
        }
    }

    /// The point on the painted layer, in its own units (origin at its centre, y up); nil off it
    /// unless `clamped` (a stroke leaving the layer keeps painting its edge).
    private func maskPoint(_ scenePoint: SIMD2<Double>, painting: MaskPainting, clamped: Bool = false) -> SIMD2<Double>? {
        guard let geometry = session.geometry(of: painting.layer), let inverse = geometry.world.inverted else { return nil }
        let local = inverse.apply(scenePoint) - geometry.anchorOffset
        let half = geometry.size / 2
        if clamped { return local }
        return abs(local.x) <= half.x && abs(local.y) <= half.y ? local : nil
    }

    /// Arrow keys nudge the selection as the Scene Inspector's do: 10 units, Shift 50, Control 1.
    /// Escape clears the selection (or ends text editing); Delete deletes the selected layer.
    private func key(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 {
            if session.editingText != nil { session.editingText = nil } else { session.selection = nil }
            return true
        }
        if event.keyCode == 51 || event.keyCode == 117, let selected = session.selection, tools.maskPainting == nil {
            actions.delete(selected)
            return true
        }
        guard let selected = session.selection, !session.isLocked(selected),
              let scalars = event.charactersIgnoringModifiers?.unicodeScalars.first else { return false }
        let step: Double = event.modifierFlags.contains(.shift) ? 50 : event.modifierFlags.contains(.control) ? 1 : 10
        var delta = SIMD2<Double>.zero
        switch Int(scalars.value) {
        case NSUpArrowFunctionKey: delta.y = step
        case NSDownArrowFunctionKey: delta.y = -step
        case NSLeftArrowFunctionKey: delta.x = -step
        case NSRightArrowFunctionKey: delta.x = step
        default: return false
        }
        var transform = session.transform(of: selected)
        transform.origin.x += delta.x
        transform.origin.y += delta.y
        session.setTransform(transform, of: selected, actionName: L("Move Layer"), coalescing: true)
        return true
    }

    private func cursor(at point: SIMD2<Double>) -> NSCursor {
        if tools.maskPainting != nil { return .crosshair }
        if let particles, let cursor = ParticleCanvasInteraction.cursor(at: point, viewport: viewport, services: particles) {
            return cursor
        }
        guard let selected = session.selection, !session.isLocked(selected),
              let geometry = session.geometry(of: selected),
              let handle = LayerGizmo.handle(at: point, geometry: geometry, viewport: viewport) else { return .arrow }
        switch handle {
        case .body: return .openHand
        case .corner: return .crosshair
        case .rotate: return .pointingHand
        }
    }
}

/// The hovered layer's outline, the selection's gizmo, snapping guides and a mask being painted,
/// drawn over the live canvas.
private struct GizmoOverlay: View {
    @ObservedObject var session: SceneEditSession
    @ObservedObject var tools: EditorTools
    let viewport: CanvasViewport
    let hovered: Int?
    let pointer: SIMD2<Double>?

    var body: some View {
        Canvas { context, _ in
            if let painting = tools.maskPainting {
                drawMask(painting, in: &context)
                return
            }
            if let hovered, hovered != session.selection, let geometry = session.geometry(of: hovered) {
                context.stroke(outline(geometry), with: .color(.accentColor.opacity(0.6)), lineWidth: 1)
            }
            drawGuides(in: &context)
            guard let selected = session.selection, session.editingText != selected,
                  let geometry = session.geometry(of: selected) else { return }
            let locked = session.isLocked(selected)
            context.stroke(outline(geometry), with: .color(.accentColor),
                           style: StrokeStyle(lineWidth: 1.5, dash: locked ? [4, 3] : []))
            guard !locked else { return }
            let corners = geometry.corners.map(viewport.canvasPoint)
            let top = (corners[2] + corners[3]) / 2
            let rotate = LayerGizmo.rotateHandle(geometry, in: viewport)
            var stem = Path()
            stem.move(to: CGPoint(top))
            stem.addLine(to: CGPoint(rotate))
            context.stroke(stem, with: .color(.accentColor), lineWidth: 1)
            for point in corners + [rotate] {
                let isRotate = point == rotate
                let size: Double = 8
                let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
                let shape = isRotate ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                context.fill(shape, with: .color(.white))
                context.stroke(shape, with: .color(.accentColor), lineWidth: 1.5)
            }
            let pivot = viewport.canvasPoint(geometry.pivot)
            var cross = Path()
            cross.move(to: CGPoint(x: pivot.x - 4, y: pivot.y))
            cross.addLine(to: CGPoint(x: pivot.x + 4, y: pivot.y))
            cross.move(to: CGPoint(x: pivot.x, y: pivot.y - 4))
            cross.addLine(to: CGPoint(x: pivot.x, y: pivot.y + 4))
            context.stroke(cross, with: .color(.accentColor), lineWidth: 1)
        }
    }

    /// Snapping guides: magenta lines, as design tools draw them.
    private func drawGuides(in context: inout GraphicsContext) {
        for guide in tools.guides {
            var path = Path()
            if guide.axis == 0 {
                path.move(to: CGPoint(viewport.canvasPoint(SIMD2(guide.position, guide.from))))
                path.addLine(to: CGPoint(viewport.canvasPoint(SIMD2(guide.position, guide.to))))
            } else {
                path.move(to: CGPoint(viewport.canvasPoint(SIMD2(guide.from, guide.position))))
                path.addLine(to: CGPoint(viewport.canvasPoint(SIMD2(guide.to, guide.position))))
            }
            context.stroke(path, with: .color(Color(red: 1, green: 0.2, blue: 0.75)), lineWidth: 1)
        }
    }

    /// The mask over its layer (white: the effect shows), and the brush at the pointer.
    private func drawMask(_ painting: MaskPainting, in context: inout GraphicsContext) {
        _ = painting.revision
        guard let geometry = session.geometry(of: painting.layer), let image = painting.image else { return }
        let half = geometry.size / 2
        // Image space (y down, pixels) to canvas: its top-left, top-right and bottom-left corners.
        let topLeft = viewport.canvasPoint(geometry.world.apply(SIMD2(-half.x, half.y) + geometry.anchorOffset))
        let topRight = viewport.canvasPoint(geometry.world.apply(SIMD2(half.x, half.y) + geometry.anchorOffset))
        let bottomLeft = viewport.canvasPoint(geometry.world.apply(SIMD2(-half.x, -half.y) + geometry.anchorOffset))
        let width = Double(image.width), height = Double(image.height)
        let transform = CGAffineTransform(a: (topRight.x - topLeft.x) / width, b: (topRight.y - topLeft.y) / width,
                                          c: (bottomLeft.x - topLeft.x) / height, d: (bottomLeft.y - topLeft.y) / height,
                                          tx: topLeft.x, ty: topLeft.y)
        var layer = context
        layer.concatenate(transform)
        layer.opacity = 0.55
        layer.draw(Image(decorative: image, scale: 1), in: CGRect(x: 0, y: 0, width: width, height: height))
        context.stroke(outline(geometry), with: .color(.accentColor), lineWidth: 1.5)
        if let pointer {
            let radius = painting.brushSize / 2 * viewport.scale * abs(geometry.world.determinant).squareRoot()
            let rect = CGRect(x: pointer.x - radius, y: pointer.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(.white), lineWidth: 1.5)
            context.stroke(Path(ellipseIn: rect.insetBy(dx: -1, dy: -1)), with: .color(.black.opacity(0.6)), lineWidth: 1)
        }
    }

    private func outline(_ geometry: LayerGeometry) -> Path {
        var path = Path()
        path.addLines(geometry.corners.map { CGPoint(viewport.canvasPoint($0)) })
        path.closeSubpath()
        return path
    }
}

extension CGPoint {
    init(_ point: SIMD2<Double>) { self.init(x: point.x, y: point.y) }
}

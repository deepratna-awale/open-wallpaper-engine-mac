import Foundation

/// The move/scale/rotate gizmo: what a press on the canvas grabs, and what dragging it does.
public enum LayerGizmo {
    public enum Handle: Hashable, Sendable {
        case body
        /// A corner, indexed as `LayerGeometry.corners`.
        case corner(Int)
        case rotate
    }

    /// Canvas points from the rectangle's top edge to the rotation handle.
    public static let rotateHandleDistance: Double = 28
    /// How near (canvas points) a press must be to a handle to grab it.
    public static let handleRadius: Double = 7

    /// The rotation handle's position in canvas points: above the middle of the layer's top edge,
    /// on the side away from its centre.
    public static func rotateHandle(_ geometry: LayerGeometry, in viewport: CanvasViewport) -> SIMD2<Double> {
        let corners = geometry.corners.map(viewport.canvasPoint)
        let topMiddle = (corners[2] + corners[3]) / 2
        let centre = (corners[0] + corners[2]) / 2
        var direction = topMiddle - centre
        let length = (direction * direction).sum().squareRoot()
        direction = length > 1e-9 ? direction / length : SIMD2(0, -1)
        return topMiddle + direction * rotateHandleDistance
    }

    /// The handle under `canvasPoint`: the rotation handle, then a corner, then the body.
    public static func handle(at canvasPoint: SIMD2<Double>, geometry: LayerGeometry,
                              viewport: CanvasViewport) -> Handle? {
        func near(_ point: SIMD2<Double>) -> Bool {
            let delta = point - canvasPoint
            return (delta * delta).sum() <= handleRadius * handleRadius
        }
        if near(rotateHandle(geometry, in: viewport)) { return .rotate }
        if let corner = geometry.corners.map(viewport.canvasPoint).firstIndex(where: near) { return .corner(corner) }
        return geometry.contains(viewport.scenePoint(canvasPoint)) ? .body : nil
    }

    /// What a drag needs to remember from its start.
    public struct Drag: Hashable, Sendable {
        public var handle: Handle
        public var start: LayerGeometry
        /// Where the press was, in scene space.
        public var startPoint: SIMD2<Double>

        public init(handle: Handle, start: LayerGeometry, startPoint: SIMD2<Double>) {
            self.handle = handle
            self.start = start
            self.startPoint = startPoint
        }

        /// The layer's transform with the pointer at `scenePoint`. `free` scales each axis on its
        /// own (Shift; proportional otherwise); `snap` turns in 15° steps (Shift).
        public func transform(at scenePoint: SIMD2<Double>, free: Bool = false, snap: Bool = false) -> LayerTransform {
            var result = start.transform
            // The drag works in the parent's space, where the layer's own values live.
            guard let toParent = start.parent.inverted else { return result }
            let from = toParent.apply(startPoint), to = toParent.apply(scenePoint)
            let origin = SIMD2(result.origin.x, result.origin.y)
            switch handle {
            case .body:
                let delta = to - from
                result.origin.x += delta.x
                result.origin.y += delta.y
            case .rotate:
                let before = atan2(from.y - origin.y, from.x - origin.x)
                let after = atan2(to.y - origin.y, to.x - origin.x)
                var angle = start.transform.angles.z + LayerGizmo.wrap(after - before)
                if snap {
                    let step = Double.pi / 12
                    angle = (angle / step).rounded() * step
                }
                result.angles.z = angle
            case .corner:
                // In the layer's unrotated frame, about its origin.
                let angle = start.transform.angles.z
                func unrotated(_ point: SIMD2<Double>) -> SIMD2<Double> {
                    let delta = point - origin
                    return SIMD2(cos(-angle) * delta.x - sin(-angle) * delta.y, sin(-angle) * delta.x + cos(-angle) * delta.y)
                }
                let u0 = unrotated(from), u1 = unrotated(to)
                if free {
                    if abs(u0.x) > 1e-9 { result.scale.x = LayerGizmo.clampScale(start.transform.scale.x * u1.x / u0.x) }
                    if abs(u0.y) > 1e-9 { result.scale.y = LayerGizmo.clampScale(start.transform.scale.y * u1.y / u0.y) }
                } else {
                    let length = (u0 * u0).sum()
                    guard length > 1e-12 else { return result }
                    // The pointer projected on the line through the origin and the grabbed corner.
                    let factor = (u0 * u1).sum() / length
                    result.scale.x = LayerGizmo.clampScale(start.transform.scale.x * factor)
                    result.scale.y = LayerGizmo.clampScale(start.transform.scale.y * factor)
                }
            }
            return result
        }
    }

    /// The angle in -π...π.
    static func wrap(_ angle: Double) -> Double {
        var value = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if value > .pi { value -= 2 * .pi } else if value < -.pi { value += 2 * .pi }
        return value
    }

    /// A scale never reaches zero, which would make the layer impossible to grab again; flipping
    /// through zero keeps its sign.
    static func clampScale(_ value: Double) -> Double {
        let minimum = 0.01
        if abs(value) >= minimum { return value }
        return value < 0 ? -minimum : minimum
    }
}

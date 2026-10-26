import XCTest
import Metal
import simd
@testable import OpenWallpaperEngine

/// WE simulates a particle system in its object's space unless it is `worldspace` (flag 1), and
/// draws it through the object's model matrix (`ParticleFrameInputs`): a scaled system's
/// velocities, gravity, operator distances and collision shapes are in its own units, so its
/// particles land where the unscaled system's would, through the scale. A `worldspace` system
/// simulates in the scene.
final class ParticleSystemScaleTests: XCTestCase {
    private var gpu: ParticleGPUStepper!
    private var texture: MTLTexture!
    private let origin = SIMD2<Float>(400, 300)
    /// Non-uniform, so neither a uniform factor nor the area scale can stand in for it.
    private let scale = SIMD2<Float>(3, 0.5)

    override func setUpWithError() throws {
        gpu = try ParticleGPUStepper()
        texture = try gpu.texture()
    }

    private func emitter(_ scale: SIMD2<Float>) -> SceneAffineTransform {
        SceneAffineTransform(SceneLocalTransform(origin: origin, scale: scale, angle: 0))
    }

    /// `system`'s live particles by serial after `frames` steps under an emitter of `scale`.
    private func run(_ system: ParticleTestSystem, scale: SIMD2<Float>, frames: Int = 60) -> [UInt32: ParticleGPUState] {
        var system = system
        system.origin = origin
        let runtime = ParticleSystemRuntime(texture: texture, configuration: system.configuration, seed: 7)
        for _ in 0..<frames {
            gpu.step(runtime, inputs: ParticleFrameInputs.advance(runtime, deltaTime: 1 / 60, cursor: .zero, emitter: emitter(scale)))
        }
        return Dictionary(gpu.particles(runtime).map { ($0.serial, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func collision(_ shape: ParticleCollision) -> ParticleOperator {
        var op = ParticleOperator(.collision)
        op.collision = shape
        return op
    }

    /// Velocity, gravity, drag, a control point's pull and a vortex's distances: all in the
    /// system's units.
    private var movingSystem: ParticleTestSystem {
        var system = ParticleTestSystem()
        system.lifetime = 3...4
        system.emissionRate = 200
        system.gravity = SIMD2(0, -120)
        system.drag = 0.3
        system.controlPoints[1] = ParticleTestSystem.point(SIMD2(60, 20))
        system.operators = [ParticleOperator(.controlPointAttract, controlPoints: 1, b: SIMD4(300, 400, 5, 0)),
                            ParticleOperator(.vortex, b: SIMD4(0, 0, 1, 0), c: SIMD4(0, 300, 200, 50))]
        return system
    }

    private func assertScaled(_ scaled: [UInt32: ParticleGPUState], _ unscaled: [UInt32: ParticleGPUState],
                              file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertGreaterThan(unscaled.count, 50, file: file, line: line)
        XCTAssertEqual(Set(scaled.keys), Set(unscaled.keys), "the same particles live", file: file, line: line)
        for (serial, own) in unscaled {
            let particle = try XCTUnwrap(scaled[serial], file: file, line: line)
            let expected: SIMD2<Float> = origin + scale * (own.position - origin)
            let tolerance: Float = 0.05 + 1e-4 * simd_length(expected - origin)
            XCTAssertLessThan(simd_distance(particle.position, expected), tolerance,
                              "particle \(serial) at \(particle.position), expected \(expected)", file: file, line: line)
            let velocity: SIMD2<Float> = scale * own.velocity
            XCTAssertLessThan(simd_distance(particle.velocity, velocity), 0.05 + 1e-4 * simd_length(velocity),
                              "particle \(serial)'s velocity", file: file, line: line)
        }
    }

    func testAScaledSystemSimulatesInItsOwnUnits() throws {
        let system = movingSystem
        try assertScaled(run(system, scale: scale), run(system, scale: SIMD2(1, 1)))
    }

    /// Collision shapes are authored in the system's space: under a non-uniform scale a sphere is
    /// an ellipse in the scene and a slanted plane's bounce follows its scaled normal.
    func testCollisionsAreInTheSystemsSpace() throws {
        var system = ParticleTestSystem()
        system.lifetime = 3...4
        system.emissionRate = 200
        system.gravity = SIMD2(0, -400)
        system.operators = [
            collision(ParticleCollision(shape: .sphere(origin: SIMD3(30, -60, 0), radius: 40), behavior: .slide)),
            collision(ParticleCollision(shape: .plane(normal: SIMD3(0.4, 1, 0), distance: -120), bounceFactor: 0.6)),
            collision(ParticleCollision(shape: .quad(origin: SIMD3(-80, -40, 0), normal: SIMD3(0, 1, 0), forward: SIMD3(0, 0, 1),
                                                     size: SIMD2(80, 80)), behavior: .stop)),
        ]
        try assertScaled(run(system, scale: scale), run(system, scale: SIMD2(1, 1)))
    }

    /// A shape on a control point sits on the point in the system's space.
    func testACollisionOnAControlPointFollowsThePoint() throws {
        var system = ParticleTestSystem()
        system.lifetime = 3...4
        system.emissionRate = 200
        system.gravity = SIMD2(0, -400)
        system.controlPoints[2] = ParticleTestSystem.point(SIMD2(10, -70))
        system.operators = [collision(ParticleCollision(shape: .sphere(origin: .zero, radius: 30), controlPoint: 2))]
        try assertScaled(run(system, scale: scale), run(system, scale: SIMD2(1, 1)))
    }

    /// A `worldspace` system simulates in the scene: the object's scale doesn't reach its gravity,
    /// drag, operators or collisions.
    func testAWorldSpaceSystemIgnoresTheScale() throws {
        var system = movingSystem
        system.worldSpace = true
        // From one point, still at first: what moves them is the simulation alone.
        system.spawnExtent = .zero
        system.minimumVelocity = .zero
        system.maximumVelocity = .zero
        // Not the control point's pull: an offset point of a `worldspace` system still sits at its
        // offset in the emitter's space (`testControlPointsUnderTheScale`).
        system.operators = [ParticleOperator(.vortex, b: SIMD4(0, 0, 1, 0), c: SIMD4(0, 300, 200, 50)),
                            collision(ParticleCollision(shape: .plane(normal: SIMD3(0.4, 1, 0), distance: 200)))]
        let scaled = run(system, scale: scale), unscaled = run(system, scale: SIMD2(1, 1))
        XCTAssertGreaterThan(unscaled.count, 50)
        for (serial, own) in unscaled {
            let particle = try XCTUnwrap(scaled[serial])
            XCTAssertLessThan(simd_distance(particle.position, own.position), 1e-2, "particle \(serial)")
        }
    }

    /// Control points: an offset is in the system's units; the cursor's (flag 1) and a scene
    /// position's (flag 2) stay where they are in the scene.
    func testControlPointsUnderTheScale() throws {
        var system = ParticleTestSystem()
        system.origin = origin
        system.controlPoints[1] = ParticleTestSystem.point(SIMD2(20, 10))
        system.controlPoints[2] = ParticleTestSystem.point(.zero, cursor: true)
        system.controlPoints[3] = ParticleControlPoint(offset: SIMD3(150, 250, 0), worldSpace: true)
        let runtime = ParticleSystemRuntime(texture: texture, configuration: system.configuration, seed: 7)
        let cursor = SIMD2<Float>(700, 100)
        let inputs = ParticleFrameInputs.advance(runtime, deltaTime: 1 / 60, cursor: cursor, emitter: emitter(scale))
        let offset = inputs.sceneControlPoint(1), onCursor = inputs.sceneControlPoint(2), placed = inputs.sceneControlPoint(3)
        XCTAssertEqual(offset.x, origin.x + 60, accuracy: 1e-3)
        XCTAssertEqual(offset.y, origin.y + 5, accuracy: 1e-3)
        XCTAssertEqual(onCursor.x, cursor.x, accuracy: 1e-3)
        XCTAssertEqual(onCursor.y, cursor.y, accuracy: 1e-3)
        XCTAssertEqual(placed.x, 150, accuracy: 1e-3)
        XCTAssertEqual(placed.y, 250, accuracy: 1e-3)
    }
}

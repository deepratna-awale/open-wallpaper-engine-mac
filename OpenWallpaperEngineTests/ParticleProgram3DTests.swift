import XCTest
import AppKit
import Metal
import simd
@testable import OpenWallpaperEngine

/// The particle program in 3D (test-risks PG1; `wallpaper64.exe`'s VM keeps position and velocity
/// as x, y, z, system+0x2b0…0x2d8): each operator and initializer against WE's 3D formula, control
/// point orientation from `controlpointangle<n>`, and the GPU against the CPU.
final class ParticleProgram3DTests: XCTestCase {
    // MARK: - Control points

    /// R(x, y, z) of 0x14022bf53…0x14022c069: x first, then y, then z; an axis a becomes a·R.
    func testTheControlPointRotationIsWEs() {
        let angles = SIMD3<Float>(0.3, -1.1, 2.0)
        let axes = ParticleProgramCPU.controlPointRotation(angles)
        let rx = simd_float3x3(simd_quatf(angle: angles.x, axis: SIMD3(1, 0, 0)))
        let ry = simd_float3x3(simd_quatf(angle: angles.y, axis: SIMD3(0, 1, 0)))
        let rz = simd_float3x3(simd_quatf(angle: angles.z, axis: SIMD3(0, 0, 1)))
        let expected = rz * ry * rx
        for column in 0..<3 {
            XCTAssertLessThan(simd_distance(axes[column], expected[column]), 1e-5)
        }
        // "0 0 1" becomes row 2 of WE's matrix: (cx·sy·cz + sx·sz, cx·sy·sz − sx·cz, cx·cy).
        let cx = cos(angles.x), sx = sin(angles.x), cy = cos(angles.y), sy = sin(angles.y)
        let cz = cos(angles.z), sz = sin(angles.z)
        XCTAssertLessThan(simd_distance(axes * SIMD3(0, 0, 1),
                                        SIMD3(cx * sy * cz + sx * sz, cx * sy * sz - sx * cz, cx * cy)), 1e-5)
    }

    /// `controlpointangle<n>` turns its point (not one on the cursor); in a `worldspace` system the
    /// emitter's rotation composes with it; offsets keep their z (0x14022cdc0, 0x14022a070).
    func testTheAngleOverrideTurnsItsPointAndOffsetsKeepTheirDepth() throws {
        var system = ParticleTestSystem()
        system.controlPoints[1] = ParticleTestSystem.point(SIMD2(10, 20), z: 30)
        system.controlPoints[2] = ParticleTestSystem.point(.zero, cursor: true)
        var configuration = system.configuration
        configuration.overrides.controlPointAngles = [1: SIMD3(0, 0, .pi / 2), 2: SIMD3(1, 1, 1)]
        let runtime = ParticleSystemRuntime(texture: try texture(), configuration: configuration, seed: 1)
        let inputs = ParticleFrameInputs.advance(runtime, deltaTime: 1 / 60, cursor: .zero)
        XCTAssertEqual(inputs.controlPoints[1], SIMD3(10, 20, 30))
        XCTAssertLessThan(simd_distance(inputs.controlPointAxes[1] * SIMD3(1, 0, 0), SIMD3(0, 1, 0)), 1e-6,
                          "a quarter turn about z")
        XCTAssertEqual(inputs.controlPointAxes[2], matrix_identity_float3x3, "the override skips a cursor point")

        var world = ParticleTestSystem()
        world.worldSpace = true
        world.emitterLinear = simd_float2x2(simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)).act(SIMD3(1, 0, 0)).xy2,
                                            simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)).act(SIMD3(0, 1, 0)).xy2)
        var worldConfiguration = world.configuration
        worldConfiguration.overrides.controlPointAngles = [0: SIMD3(.pi / 2, 0, 0)]
        let worldRuntime = ParticleSystemRuntime(texture: try texture(), configuration: worldConfiguration, seed: 1)
        let worldInputs = ParticleFrameInputs.advance(worldRuntime, deltaTime: 1 / 60, cursor: .zero)
        // Row vectors: a·(R·model): y turns to z by R, z stays z under the emitter's turn about z.
        let turned = worldInputs.controlPointAxes[0] * SIMD3(0, 1, 0)
        XCTAssertLessThan(simd_distance(turned, SIMD3(0, 0, 1)), 1e-5)
        let x = worldInputs.controlPointAxes[0] * SIMD3(1, 0, 0)
        XCTAssertLessThan(simd_distance(x, SIMD3(0, 1, 0)), 1e-5, "x turns with the emitter")
    }

    // MARK: - Operators and initializers against WE's 3D formulas

    private func state(_ position: SIMD3<Float>, velocity: SIMD3<Float> = .zero) -> ParticleProgramState {
        var p = ParticleProgramState()
        p.position = position
        p.velocity = velocity
        p.lifetime = 10
        p.age = 1
        return p
    }

    private func context(dt: Float = 0.5) -> ParticleProgramContext {
        var c = ParticleProgramContext()
        c.deltaTime = dt
        c.dragDeltaTime = dt
        return c
    }

    private func run(_ op: ParticleOperator, _ p: inout ParticleProgramState, _ c: ParticleProgramContext) {
        _ = ParticleProgramCPU.runOperators([op.record], on: &p, context: c, index: 0, neighbors: .init())
    }

    func testTheVortexSpinsInDepthAboutAnAxisInThePlane() {
        // DNA's vortex about y: a particle on +x is pushed along +z (cross(n, a) = x × y).
        // Flag 1 takes the offset's part along the axis out: (10, 3, 0) − 3y, so n = x.
        let vortex = ParticleOperator(.vortex, flags: 1, a: SIMD4(0, 0, 5, 0), b: SIMD4(0, 1, 0, 0), c: SIMD4(0, 100, 40, 40))
        var p = state(SIMD3(10, 3, 5))
        run(vortex, &p, context())
        XCTAssertLessThan(simd_distance(p.velocity, SIMD3(0, 0, 40 * 0.5)), 1e-4, "the offset's z counts (the offset has z 5)")
    }

    func testVortexV2TurnsItsAxisWithTheControlPoint() {
        // Axis "0 0 1" through a point turned a quarter about x: the axis becomes −y (row 2 of R(π/2, 0, 0)).
        let v2 = ParticleOperator(.vortexV2, controlPoints: 1, a: SIMD4(0, 0, 1, 0), b: SIMD4(0, 100, 10, 10))
        var c = context()
        c.controlPointAxes[1] = ParticleProgramCPU.controlPointRotation(SIMD3(.pi / 2, 0, 0))
        var p = state(SIMD3(20, 0, 0))
        run(v2, &p, c)
        // n = x, axis = (0, −1, 0): cross = (0, 0, −1) · 10 · 0.5.
        XCTAssertLessThan(simd_distance(p.velocity, SIMD3(0, 0, -5)), 1e-4)
    }

    func testTurbulenceOscillationAndFieldsMoveTheDepth() {
        let turbulence = ParticleOperator(.turbulence, a: SIMD4(0, 0, 1, 0), b: SIMD4(0.01, 100, 100, 1),
                                          c: SIMD4(0, 0, 0, 0))
        var p = state(SIMD3(30, -20, 70))
        run(turbulence, &p, context())
        let point = SIMD3<Float>(30, -20, 70) * 0.01
        XCTAssertEqual(p.velocity.z, ParticleNoise.simplex3(point.y, point.z, point.x) * 100 * 0.5, accuracy: 1e-4,
                       "z samples (Y, Z, X) at the position's own z")
        XCTAssertEqual(SIMD2(p.velocity.x, p.velocity.y), .zero, "the mask's x and y are 0")

        let oscillate = ParticleOperator(.oscillatePosition, a: SIMD4(1, 0, 2, 0), b: SIMD4(2, 2, 0, 0),
                                         c: SIMD4(3, 3, 0, 0))
        var q = state(.zero)
        run(oscillate, &q, context())
        XCTAssertEqual(q.position.z, 2 * q.position.x, accuracy: 1e-5, "z follows x's phase, by its mask")

        let attract = ParticleOperator(.controlPointAttract, controlPoints: 1, b: SIMD4(10, 100, 0, 0))
        var c = context()
        c.controlPoints[1] = SIMD3(0, 0, 50)
        var r = state(.zero)
        run(attract, &r, c)
        XCTAssertLessThan(simd_distance(r.velocity, SIMD3(0, 0, 0.5 * 10 * 0.5)), 1e-5, "pulled along z")

        let keep = ParticleOperator(.maintainDistanceToControlPoint, controlPoints: 1, a: SIMD4(100, 0, 0, 0))
        var k = state(SIMD3(0, 0, 25))
        c.controlPoints[1] = .zero
        c.previousControlPoints[1] = .zero
        run(keep, &k, c)
        XCTAssertLessThan(simd_distance(k.position, SIMD3(0, 0, 100)), 1e-4, "the distance is 3D")

        // Distance 10 of 0…100 (in 3D): reduction 1 − 0.1, damping 1 − 0.9·0.5; z is damped too.
        let reduce = ParticleOperator(.reduceMovementNearControlPoint, controlPoints: 1, a: SIMD4(0, 100, 1, 0))
        var m = state(SIMD3(0, 0, 10), velocity: SIMD3(0, 0, 8))
        run(reduce, &m, c)
        XCTAssertEqual(m.velocity.z, 8 * 0.55, accuracy: 1e-5)

        let cap = ParticleOperator(.capVelocity, a: SIMD4(5, 0, 0, 0))
        var n = state(.zero, velocity: SIMD3(3, 0, 8))
        run(cap, &n, c)
        XCTAssertEqual(simd_length(n.velocity), 5, accuracy: 1e-4, "the 3D speed is capped")
    }

    func testInitializersWorkInDepthThroughTheEmittersPoint() {
        // `mapsequencearoundcontrolpoint` about y: the radius is measured in 3D and the placement
        // is in the xz plane.
        let sequence = ParticleInitializer(.mapSequenceAroundControlPoint, a: SIMD4(0.25, 0, 1, 0),
                                           d: SIMD4(0, 1, 0, 0))
        var p = state(SIMD3(0, 7, 32))
        var c = context()
        c.sequenceIndex = 1
        ParticleProgramCPU.runInitializers([sequence.record], on: &p, context: c)
        XCTAssertEqual(p.position.y, 7, accuracy: 1e-4, "the height along the axis is kept")
        XCTAssertEqual(simd_length(SIMD2(p.position.x, p.position.z)), 32, accuracy: 1e-3, "the radius is the 3D one")

        // `velocityrandom` through the emitter's point's orientation.
        let velocity = ParticleInitializer(.velocityRandom, a: SIMD4(0, 10, 0, 1), b: SIMD4(0, 10, 0, 0))
        var v = state(.zero)
        var turned = context()
        turned.emitterAxes = ParticleProgramCPU.controlPointRotation(SIMD3(.pi / 2, 0, 0))
        ParticleProgramCPU.runInitializers([velocity.record], on: &v, context: turned)
        XCTAssertLessThan(simd_distance(v.velocity, SIMD3(0, 0, 10)), 1e-4, "y turned to z")

        // `positionoffsetrandom` moves z by fBm of (z·scale, −time).
        let offset = ParticleInitializer(.positionOffsetRandom, a: SIMD4(0, 0, 1, 0), c: SIMD4(0.01, 50, 1, 1))
        var o = state(SIMD3(0, 0, 40))
        var timed = context()
        timed.engineTime = 3
        ParticleProgramCPU.runInitializers([offset.record], on: &o, context: timed)
        XCTAssertEqual(o.position.z, 40 + ParticleNoise.simplex2(40 * 0.01, -3) * 50, accuracy: 1e-4)
    }

    // MARK: - GPU against CPU

    func testTheGPURunsThe3DProgramAsTheCPUDoes() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice()), queue = try XCTUnwrap(device.makeCommandQueue())
        let simulator = try ParticleGPUSimulator(device: device)
        var cases: [(String, ParticleTestSystem, (inout SceneMetalParticleSystem) -> Void)] = []
        var vortices = ParticleTestSystem()
        vortices.operators = [ParticleOperator(.vortex, a: SIMD4(0, 0, 10, 0), b: SIMD4(0, 1, 0, 0), c: SIMD4(0, 300, 200, 50)),
                              ParticleOperator(.vortexV2, flags: 1, controlPoints: 1, a: SIMD4(0, 0, 1, 0), b: SIMD4(0, 300, 150, 0)),
                              ParticleOperator(.turbulence, a: SIMD4(1, 1, 1, 0), b: SIMD4(0.01, 100, 200, 0.5)),
                              ParticleOperator(.oscillatePosition, a: SIMD4(1, 1, 1, 0), b: SIMD4(1, 3, 0, 1), c: SIMD4(0, 5, 0, 0))]
        vortices.controlPoints[1] = ParticleTestSystem.point(SIMD2(40, 0), z: 20)
        cases.append(("vortices, turbulence and oscillation", vortices, { configuration in
            configuration.emitter.directions.z = 1
            configuration.overrides.controlPointAngles = [1: SIMD3(0.7, 0.2, -0.4)]
        }))
        var fields = ParticleTestSystem()
        fields.operators = [ParticleOperator(.controlPointAttract, controlPoints: 1, b: SIMD4(300, 400, 5, 0)),
                            ParticleOperator(.maintainDistanceToControlPoint, controlPoints: 2, a: SIMD4(60, 0.5, 0, 0)),
                            ParticleOperator(.reduceMovementNearControlPoint, controlPoints: 1, a: SIMD4(10, 200, 1, 0)),
                            ParticleOperator(.capVelocity, a: SIMD4(90, 0, 0, 0))]
        fields.controlPoints[1] = ParticleTestSystem.point(SIMD2(-30, 10), z: -40)
        fields.controlPoints[2] = ParticleTestSystem.point(SIMD2(20, 0), z: 30)
        cases.append(("control point fields", fields, { configuration in
            configuration.emitter.directions.z = 1
            configuration.overrides.controlPointAngles = [2: SIMD3(0, 0.5, 0)]
        }))
        var spawns = ParticleTestSystem()
        spawns.initializers = [ParticleInitializer(.mapSequenceAroundControlPoint, controlPoints: 1, a: SIMD4(0.05, 0, 1, 0),
                                                   b: SIMD4(10, 0, 5, 0), c: SIMD4(20, 0, 5, 0), d: SIMD4(0, 1, 0, 0)),
                               ParticleInitializer(.positionOffsetRandom, a: SIMD4(1, 1, 1, 0), c: SIMD4(0.01, 20, 1, 2)),
                               ParticleInitializer(.velocityRandom, a: SIMD4(-20, -20, -20, 1), b: SIMD4(20, 20, 20, 0))]
        spawns.controlPoints[1] = ParticleTestSystem.point(SIMD2(0, 30), z: 10)
        spawns.emitterControlPoint = 1
        cases.append(("3D spawns through a turned emitter point", spawns, { configuration in
            configuration.emitter.directions.z = 1
            configuration.overrides.controlPointAngles = [1: SIMD3(0.4, 1.2, 0.3)]
        }))
        let texture = try self.texture()
        for (label, system, configure) in cases {
            var configuration = system.configuration
            configure(&configuration)
            let cpu = ParticleSystemRuntime(texture: texture, configuration: configuration, seed: 11)
            let gpu = ParticleSystemRuntime(texture: texture, configuration: configuration, seed: 11)
            var last: MTLCommandBuffer?
            for _ in 0..<90 {
                ParticleCPUSimulation.step(cpu, inputs: ParticleFrameInputs.advance(cpu, deltaTime: 1 / 60, cursor: .zero))
                let inputs = ParticleFrameInputs.advance(gpu, deltaTime: 1 / 60, cursor: .zero)
                let buffer = try XCTUnwrap(queue.makeCommandBuffer())
                simulator.encode([.init(system: gpu, inputs: inputs, kind: .sprite, materialVertexCount: 6)],
                                 sceneSize: SIMD2(1280, 720), targetSize: SIMD2(1280, 720), commandBuffer: buffer)
                buffer.commit()
                last = buffer
            }
            last?.waitUntilCompleted()
            XCTAssertNil(last?.error)
            let states = simulator.snapshot(gpu, queue: queue)
            XCTAssertGreaterThan(cpu.particles.count, 50, label)
            let cpuCount = Double(cpu.particles.count)
            let allowed: Double = max(2, cpuCount * 0.01)
            XCTAssertEqual(Double(states.count), cpuCount, accuracy: allowed, label)
            func mean(_ values: [SIMD4<Float>]) -> SIMD4<Float> {
                let total: SIMD4<Float> = values.reduce(SIMD4<Float>.zero, +)
                return total / Float(max(values.count, 1))
            }
            let expected = mean(cpu.particles.map { (p: Particle) -> SIMD4<Float> in
                SIMD4<Float>(p.position.x, p.position.y, p.z, p.zVelocity)
            })
            let actual = mean(states.map { (s: ParticleGPUState) -> SIMD4<Float> in
                SIMD4<Float>(s.positionVelocity.x, s.positionVelocity.y, s.depth.x, s.depth.y)
            })
            XCTAssertLessThan(simd_distance(actual, expected), 1, "\(label): \(actual) vs \(expected)")
            let spread: Float = cpu.particles.map { abs($0.z) }.reduce(0, +) / Float(max(cpu.particles.count, 1))
            XCTAssertGreaterThan(spread, 1, "\(label): the particles have depth")
        }
    }

    private func texture() throws -> MTLTexture {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return try XCTUnwrap(device.makeTexture(descriptor: .texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1,
                                                                                mipmapped: false)))
    }
}

private extension SIMD3 where Scalar == Float {
    var xy2: SIMD2<Float> { SIMD2(x, y) }
}

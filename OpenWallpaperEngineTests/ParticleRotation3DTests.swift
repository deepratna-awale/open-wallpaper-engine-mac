import XCTest
import Metal
import simd
@testable import OpenWallpaperEngine

/// Particle rotation in 3D (test-risks PG1, we-values-audit §11): WE keeps a particle's rotation
/// and angular velocity per axis (system+0x280, +0x288, +0x290 and +0x298, +0x2a0, +0x2a8).
/// `rotationrandom` and `angularvelocityrandom` draw every axis (0x14023bf55…0x14023bffb,
/// 0x14023c3d5…0x14023c4c3), `angularmovement` spins each with its own force (0x14023ffc7), and
/// `genericparticle.vert` turns the quad by all three (`ComputeParticleTangents`). The remap
/// outputs stay on z (0x14023dd8e, 0x14023de1b).
final class ParticleRotation3DTests: XCTestCase {
    private func state() -> ParticleProgramState {
        var p = ParticleProgramState()
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

    func testTheInitializersSetEveryAxis() {
        let rotation = ParticleInitializer(.rotationRandom, a: SIMD4(0.1, 0.2, 0.3, 1), b: SIMD4(0.1, 0.2, 0.3, 0))
        var c = context()
        c.spawnScale.w = 2
        let spin = ParticleInitializer(.angularVelocityRandom, a: SIMD4(1, -2, 3, 1), b: SIMD4(1, -2, 3, 0))
        var p = state()
        ParticleProgramCPU.runInitializers([rotation.record, spin.record], on: &p, context: c)
        XCTAssertEqual(p.rotationXY, SIMD2<Float>(0.1, 0.2))
        XCTAssertEqual(p.rotation, 0.3, accuracy: 1e-6)
        XCTAssertEqual(p.angularVelocityXY, SIMD2<Float>(2, -4), "times the speed override, as z")
        XCTAssertEqual(p.angularVelocity, 6, accuracy: 1e-6)
    }

    /// `angularmovement`: per axis, ω += force·dt; rotation += ω·dt; ω ×= 1 − min(drag·dt, 1).
    func testAngularMovementSpinsEachAxis() {
        let move = ParticleOperator(.angularMovement, a: SIMD4(2, -4, 6, 0.5))
        var p = state()
        p.angularVelocityXY = SIMD2(1, 1)
        p.angularVelocity = 1
        _ = ParticleProgramCPU.runOperators([move.record], on: &p, context: context(), index: 0, neighbors: .init())
        let spin = SIMD3<Float>(1 + 2 * 0.5, 1 - 4 * 0.5, 1 + 6 * 0.5)
        XCTAssertEqual(p.rotationXY, SIMD2(spin.x, spin.y) * 0.5)
        XCTAssertEqual(p.rotation, spin.z * 0.5, accuracy: 1e-6)
        XCTAssertEqual(p.angularVelocityXY, SIMD2(spin.x, spin.y) * 0.75)
        XCTAssertEqual(p.angularVelocity, spin.z * 0.75, accuracy: 1e-6)
    }

    /// A system whose rotations have no x or y (every 2D preset) draws exactly as before: the
    /// records' rotation is (0, 0, z).
    func testAFlatSystemKeepsFlatRecords() throws {
        let texture = try self.texture()
        let runtime = ParticleSystemRuntime(texture: texture, configuration: ParticleTestSystem().configuration, seed: 3)
        for _ in 0..<30 {
            ParticleCPUSimulation.step(runtime, inputs: ParticleFrameInputs.advance(runtime, deltaTime: 1 / 60, cursor: .zero))
        }
        XCTAssertGreaterThan(runtime.particles.count, 10)
        XCTAssertTrue(runtime.particles.allSatisfy { $0.rotationXY == .zero && $0.angularVelocityXY == .zero })
        XCTAssertTrue(runtime.particles.contains { $0.rotation != 0 })
    }

    /// The GPU runs the 3D rotation as the CPU does.
    func testTheGPUSpinsEveryAxisAsTheCPUDoes() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice()), queue = try XCTUnwrap(device.makeCommandQueue())
        let simulator = try ParticleGPUSimulator(device: device)
        var system = ParticleTestSystem()
        system.spins = false
        system.initializers = [ParticleInitializer(.rotationRandom, a: SIMD4(-1, 0.5, 0, 1), b: SIMD4(1, 1.5, 0, 0)),
                               ParticleInitializer(.angularVelocityRandom, a: SIMD4(0.5, -3, 0, 1), b: SIMD4(1.5, -1, 0, 0))]
        system.operators = [ParticleOperator(.angularMovement, a: SIMD4(2, -1, 0.5, 0.2))]
        let texture = try self.texture()
        let cpu = ParticleSystemRuntime(texture: texture, configuration: system.configuration, seed: 11)
        let gpu = ParticleSystemRuntime(texture: texture, configuration: system.configuration, seed: 11)
        var last: MTLCommandBuffer?
        for _ in 0..<60 {
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
        XCTAssertGreaterThan(cpu.particles.count, 50)
        let cpuCount = Double(cpu.particles.count)
        let allowed: Double = max(2, cpuCount * 0.01)
        XCTAssertEqual(Double(states.count), cpuCount, accuracy: allowed)
        func mean(_ values: [SIMD4<Float>]) -> SIMD4<Float> {
            let total: SIMD4<Float> = values.reduce(SIMD4<Float>.zero, +)
            return total / Float(max(values.count, 1))
        }
        let expected = mean(cpu.particles.map { (p: Particle) -> SIMD4<Float> in
            SIMD4<Float>(p.rotationXY.x, p.rotationXY.y, p.angularVelocityXY.x, p.angularVelocityXY.y)
        })
        let actual = mean(states.map { (s: ParticleGPUState) -> SIMD4<Float> in s.spin })
        XCTAssertLessThan(simd_distance(actual, expected), 0.05, "\(actual) vs \(expected)")
        XCTAssertGreaterThan(abs(expected.x) + abs(expected.w), 0.5, "the particles turn about x and y")
    }

    private func texture() throws -> MTLTexture {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        return try XCTUnwrap(device.makeTexture(descriptor: .texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1,
                                                                                mipmapped: false)))
    }
}

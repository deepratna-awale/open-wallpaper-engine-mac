import XCTest
import Metal
import simd
@testable import OpenWallpaperEngine

private struct Properties: SceneValueContext {
    var values: [String: String] = [:]
    func userProperty(_ name: String) -> String? { values[name] }
    func evaluateScript(_ source: String, properties: SceneScriptProperties, current: ShaderValue) -> ShaderValue? { nil }
}

/// A particle object's `instanceoverride` scales the authored values every frame, so a user
/// property it's bound to takes effect without rebuilding the scene.
final class ParticleOverrideTests: XCTestCase {
    private var texture: MTLTexture!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        texture = try XCTUnwrap(device.makeTexture(descriptor: .texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)))
    }

    private func boundOverride() throws -> WEInstanceOverride {
        try JSONDecoder().decode(WEInstanceOverride.self, from: Data(#"""
        {"count": {"user": "amount", "value": 0.5}, "rate": {"user": "amount", "value": 0.5},
         "size": {"user": "flakesize", "value": 2}, "alpha": 0.5, "lifetime": 3, "speed": 2,
         "colorn": {"user": "tint", "value": "1 0.5 0.25"}, "brightness": 2}
        """#.utf8))
    }

    func testBoundOverridesResolveEveryFrame() throws {
        var system = ParticleTestSystem()
        system.emissionRate = 100
        system.maximum = 1000
        var configuration = system.configuration
        configuration.liveOverrides = try boundOverride()
        let runtime = ParticleSystemRuntime(texture: texture, configuration: configuration)
        let defaults = ParticleFrameInputs.advance(runtime, deltaTime: 1 / 60, cursor: .zero, values: Properties())
        // `count` scales the emitter's rate (0x1401c6e6c binds it to the count); `rate` doesn't.
        XCTAssertEqual(defaults.emissionRate, 50, accuracy: 1e-4)
        XCTAssertEqual(defaults.maximum, 500)
        XCTAssertEqual(defaults.spawnScale, SIMD4(2, 0.5, 3, 2))
        XCTAssertEqual(defaults.colorScale, SIMD3(2, 1, 0.5))
        let changed = ParticleFrameInputs.advance(runtime, deltaTime: 1 / 60, cursor: .zero, values: Properties(values: [
            "amount": "0.25", "flakesize": "4", "tint": "0 1 0"]))
        XCTAssertEqual(changed.emissionRate, 25, accuracy: 1e-4)
        XCTAssertEqual(changed.maximum, 250)
        XCTAssertEqual(changed.spawnScale.x, 4)
        XCTAssertEqual(changed.colorScale, SIMD3(0, 2, 0))
    }

    func testControlPointOverridesPlaceControlPoints() throws {
        let json = "{\"controlpoint1\": \"-3382.5 384 0\", \"controlpoint2\": {\"user\": \"spot\", \"value\": \"10 20 0\"}}"
        let override = try JSONDecoder().decode(WEInstanceOverride.self, from: Data(json.utf8))
        let defaults = SceneParticleOverrides(override, in: Properties())
        XCTAssertEqual(defaults.controlPoints, [1: SIMD3(-3382.5, 384, 0), 2: SIMD3(10, 20, 0)])
        let bound = SceneParticleOverrides(override, in: Properties(values: ["spot": "5 6 0"]))
        XCTAssertEqual(bound.controlPoints[2], SIMD3(5, 6, 0))
    }

    /// WE 2.8.0.42 (flagtests `pf_childflags_0/2`): a static child with link flags 0 and one with 2
    /// both come out in the layer's `colorn` (mean 133,12,14 and 134,12,14). Flag 2 restarts the
    /// child with its parent's periods; it doesn't keep the child's colours.
    func testAChildWithLinkFlag2TakesTheTint() throws {
        let child = try JSONDecoder().decode(WEParticleChild.self, from: Data(#"{"name": "c.json", "flags": 2}"#.utf8))
        let link = ParticleFamilyBuilder.link(child, kind: .static, parentIndex: 0, parent: nil)
        XCTAssertTrue(link.restartsWithParentPeriod)
        var configuration = ParticleTestSystem().configuration
        configuration.overrides = SceneParticleOverrides(try boundOverride(), in: Properties())
        configuration.link = link
        let runtime = ParticleSystemRuntime(texture: texture, configuration: configuration)
        let inputs = ParticleFrameInputs.advance(runtime, deltaTime: 1 / 60, cursor: .zero, values: Properties())
        XCTAssertEqual(inputs.colorScale, configuration.overrides.tint * configuration.overrides.brightness)
        XCTAssertNotEqual(inputs.colorScale, SIMD3(repeating: 1))
    }

    /// WE's particle parser binds the `rate` override to the turbulence operators' `timescale`
    /// only (0x1401c8bc5 `turbulentvelocityrandom`, 0x1401cd7ba `turbulence`); the emitters' rate
    /// is bound to `count` (0x1401c6e6c). WE's element previews with `rate` 2.33
    /// (maintaindistancetocontrolpoint, reducemovementnearcontrolpoint) emit at their authored rate.
    func testTheRateOverrideScalesTurbulenceNotEmission() throws {
        var system = ParticleTestSystem()
        system.emissionRate = 100
        system.operators = [ParticleOperator(.turbulence, b: SIMD4(0.01, 500, 1000, 20))]
        system.initializers = [ParticleInitializer(.turbulentVelocityRandom, a: SIMD4(100, 250, 0, 0.1), b: SIMD4(1, 1, 0, 0))]
        var configuration = system.configuration
        configuration.overrides.rate = 2.5
        let runtime = ParticleSystemRuntime(texture: texture, configuration: configuration)
        let inputs = ParticleFrameInputs.advance(runtime, deltaTime: 1 / 60, cursor: .zero, values: Properties())
        XCTAssertEqual(inputs.emissionRate, 100)
        XCTAssertEqual(try XCTUnwrap(inputs.operators.last).b.w, 50)
        XCTAssertEqual(try XCTUnwrap(inputs.initializers.last).b.x, 2.5)
    }

    /// WE's particle parser binds every emitter's `speedmin` and `speedmax` to the `speed`
    /// override (0x1401c6354, 0x1401c6a86, 0x1401c6f9c; not with the system's flag 0x10), so the
    /// `collisionbounds` preview's `speed` 2.9 launches its particles 2.9 × as fast.
    func testTheSpeedOverrideScalesTheEmittersSpeed() throws {
        var system = ParticleTestSystem()
        system.emissionRate = 60
        system.emitterSpeed = SIMD2(100, 100)
        system.minimumVelocity = .zero
        system.maximumVelocity = .zero
        func launchSpeeds(_ speed: Float) -> [Float] {
            var configuration = system.configuration
            configuration.overrides.speed = speed
            let runtime = ParticleSystemRuntime(texture: texture, configuration: configuration, seed: 2)
            ParticleCPUSimulation.step(runtime, inputs: ParticleFrameInputs.advance(runtime, deltaTime: 1 / 60, cursor: .zero,
                                                                                    values: Properties()))
            return runtime.particles.map { simd_length($0.velocity) }
        }
        XCTAssertEqual(launchSpeeds(1), [100])
        let fast = try XCTUnwrap(launchSpeeds(2.9).first)
        XCTAssertEqual(fast, 290, accuracy: 1e-3)
    }

    func testOverriddenSpawnsMatchOnTheGPU() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let simulator = try ParticleGPUSimulator(device: device)
        var system = ParticleTestSystem()
        system.emissionRate = 3000
        system.emitterSpeed = SIMD2(20, 80)
        var configuration = system.configuration
        configuration.overrides = SceneParticleOverrides(try boundOverride(), in: Properties())
        let cpu = ParticleSystemRuntime(texture: texture, configuration: configuration, seed: 5)
        let gpu = ParticleSystemRuntime(texture: texture, configuration: configuration, seed: 5)
        var last: MTLCommandBuffer?
        for _ in 0..<60 {
            ParticleCPUSimulation.step(cpu, inputs: ParticleFrameInputs.advance(cpu, deltaTime: 1 / 60, cursor: .zero,
                                                                                values: Properties()))
            let inputs = ParticleFrameInputs.advance(gpu, deltaTime: 1 / 60, cursor: .zero, values: Properties())
            let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
            simulator.encode([.init(system: gpu, inputs: inputs, kind: .sprite, materialVertexCount: 6)],
                             sceneSize: SIMD2(1280, 720), targetSize: SIMD2(1280, 720), commandBuffer: commandBuffer)
            commandBuffer.commit()
            last = commandBuffer
        }
        last?.waitUntilCompleted()
        let states = simulator.snapshot(gpu, queue: queue)
        XCTAssertEqual(states.count, cpu.particles.count)
        XCTAssertEqual(cpu.particles.count, 500, "the count override halves the maximum")
        for (state, particle) in zip(states, cpu.particles) {
            XCTAssertEqual(state.life.z, particle.size, accuracy: 1e-3)
            XCTAssertEqual(state.life.y, particle.lifetime, accuracy: 1e-4)
            XCTAssertLessThan(simd_distance(state.color, particle.color), 1e-4)
            XCTAssertLessThan(simd_distance(SIMD2(state.positionVelocity.z, state.positionVelocity.w), particle.velocity), 1e-2)
        }
        let sizes = cpu.particles.map(\.size)
        // WE's base size is 0.5, which `sizerandom` multiplies (wallpaper64.exe 0x14023b340).
        XCTAssertGreaterThanOrEqual(sizes.min() ?? 0, 10, "authored 10…20 on the base 0.5, doubled")
    }
}

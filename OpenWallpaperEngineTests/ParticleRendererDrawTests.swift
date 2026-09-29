import XCTest
import Metal
import AppKit
import simd
@testable import OpenWallpaperEngine

/// A particle system with several `renderers`: WE draws each one, in authored order, from the
/// system's one simulation (`SceneMetalParticleSystem.additionalRenderers`,
/// `ParticleSystemRuntime.simulation`).
final class ParticleRendererDrawTests: XCTestCase {
    private var device: MTLDevice!
    private var texture: MTLTexture!

    override func setUpWithError() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        texture = try XCTUnwrap(device.makeTexture(descriptor: .texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)))
    }

    // MARK: - Loading

    func testEveryRendererIsADrawOfTheOneSimulation() throws {
        let pairs: [(String, String)] = [("sprite", "spritetrail"), ("rope", "sprite"), ("sprite", "ropetrail")]
        for (first, second) in pairs {
            let (particles, system) = try build(#"[{"name": "\#(first)"}, {"name": "\#(second)"}]"#)
            XCTAssertEqual(particles.renderer?.count, 2)
            XCTAssertEqual(system.rendererName, first)
            XCTAssertEqual(system.additionalRenderers.map(\.name), [second])

            let simulation = ParticleSystemRuntime(texture: texture, configuration: system, seed: 1)
            let draws = ParticleSystemRuntime.addingRendererDraws([simulation])
            XCTAssertEqual(draws.count, 2, "\(first) + \(second): one draw per renderer")
            XCTAssertTrue(draws[0] === simulation)
            XCTAssertNil(simulation.simulation)
            XCTAssertTrue(draws[1].simulation === simulation, "the second renderer draws the first's particles")
            XCTAssertTrue(draws[1].configuration.additionalRenderers.isEmpty)
            for (draw, name) in zip(draws, [first, second]) {
                let material = try XCTUnwrap(draw.configuration.material, name)
                XCTAssertEqual(draw.configuration.rendererName, name)
                XCTAssertEqual(material.shader, name, "each renderer draws through the material made for it")
                XCTAssertEqual(material.format, Self.format(name))
                XCTAssertEqual(ParticleGPUDrawKind.material(material.format, rendererName: draw.configuration.rendererName),
                               Self.materialKind(name))
                XCTAssertEqual(ParticleGPUDrawKind.fallback(rendererName: draw.configuration.rendererName),
                               Self.fallbackKind(name))
            }
        }
    }

    func testTheSecondRendererTakesItsOwnFields() throws {
        let (_, system) = try build(#"""
            [{"name": "sprite", "orientation": "upright", "axis": "0 1 0"},
             {"name": "spritetrail", "length": 0.2, "maxlength": 4, "minlength": 1}]
            """#)
        let draws = ParticleSystemRuntime.addingRendererDraws([
            ParticleSystemRuntime(texture: texture, configuration: system, seed: 1)])
        let trail = draws[1].configuration
        XCTAssertEqual(trail.trailLength, 0.2)
        XCTAssertEqual(trail.trailLengthLimits, SIMD2(4, 1))
        XCTAssertEqual(trail.orientation, ParticleOrientation(), "the trail's own (default) orientation")
        XCTAssertEqual(draws[0].configuration.orientation.mode, .upright)
        // The rest is the system's.
        XCTAssertEqual(trail.maximumParticleCount, system.maximumParticleCount)
        XCTAssertEqual(trail.emissionRate, system.emissionRate)
    }

    func testASystemWithOneRendererIsUnchanged() throws {
        let (_, system) = try build(#"[{"name": "ropetrail", "segments": 6, "length": 0.5}]"#)
        XCTAssertTrue(system.additionalRenderers.isEmpty)
        XCTAssertNil(system.sharedHistory)
        XCTAssertEqual(system.trailHistory, ParticleTrailHistory(kept: true, length: 0.5, segments: 6))
        let simulation = ParticleSystemRuntime(texture: texture, configuration: system, seed: 1)
        let draws = ParticleSystemRuntime.addingRendererDraws([simulation])
        XCTAssertEqual(draws.count, 1)
        XCTAssertTrue(draws[0] === simulation)

        let (_, sprite) = try build(#"[{"name": "sprite"}]"#)
        XCTAssertFalse(sprite.trailHistory.kept)
    }

    /// A `ropetrail` after a `sprite`: the simulation keeps that renderer's history, and the
    /// trail draws the sprites' particles.
    func testALaterRopeTrailSharesTheSimulationsHistory() throws {
        let (_, system) = try build(#"[{"name": "sprite"}, {"name": "ropetrail", "segments": 6, "length": 0.5}]"#)
        XCTAssertEqual(system.rendererName, "sprite")
        XCTAssertEqual(system.trailHistory, ParticleTrailHistory(kept: true, length: 0.5, segments: 6))
        let simulation = ParticleSystemRuntime(texture: texture, configuration: system, seed: 3)
        let draws = ParticleSystemRuntime.addingRendererDraws([simulation])
        let trail = draws[1]
        XCTAssertEqual(trail.configuration.trailHistory, system.trailHistory)
        for _ in 0..<60 {
            ParticleCPUSimulation.step(simulation, inputs: ParticleFrameInputs.advance(simulation, deltaTime: 1 / 60, cursor: .zero))
            trail.followSimulation()
        }
        XCTAssertGreaterThan(simulation.particles.count, 0)
        XCTAssertEqual(trail.particles.map(\.position), simulation.particles.map(\.position))
        XCTAssertTrue(trail.particles.contains { !$0.history.isEmpty }, "the simulation samples the trail's history")
        XCTAssertTrue(trail.particles.allSatisfy { $0.history.count <= 6 })
        XCTAssertEqual(trail.elapsedTime, simulation.elapsedTime)
    }

    // MARK: - GPU

    /// One GPU step, three draws: the sprites, a sprite trail and a rope trail, each with its own
    /// records and draw arguments over the same particles.
    func testTheGPUDrawsEveryRendererFromOneStep() throws {
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let simulator = try ParticleGPUSimulator(device: device)
        var system = ParticleTestSystem()
        system.maximum = 200
        system.emissionRate = 120
        var configuration = system.configuration
        let trail = ParticleRendererDraw(name: "spritetrail", trailLength: 0.05, trailLengthLimits: SIMD2(10, 0),
                                         trailSegments: 4, ropeSubdivision: 1, fadeTrailAlpha: false, fadeTrailSize: false,
                                         orientation: ParticleOrientation(), ropeUV: ParticleRopeUV())
        var rope = trail
        rope.name = "ropetrail"
        rope.trailLength = 0.5
        configuration.additionalRenderers = [trail, rope]
        configuration.sharedHistory = ParticleTrailHistory(kept: true, length: rope.trailLength, segments: rope.trailSegments)
        let runtimes = ParticleSystemRuntime.addingRendererDraws([
            ParticleSystemRuntime(texture: texture, configuration: configuration, seed: 5)])
        XCTAssertEqual(runtimes.count, 3)
        let kinds: [ParticleGPUDrawKind] = [.fallbackSprite, .fallbackSpriteTrail, .fallbackRopeTrail]
        var last: MTLCommandBuffer?
        for _ in 0..<60 {
            let inputs = ParticleFrameInputs.advance(runtimes[0], deltaTime: 1 / 60, cursor: .zero)
            var requests: [ParticleGPUSimulator.Request] = [.init(system: runtimes[0], inputs: inputs, kind: kinds[0])]
            for (draw, kind) in zip(runtimes.dropFirst(), kinds.dropFirst()) {
                draw.followSimulation()
                var drawn = inputs
                drawn.drawSizeScale = draw.drawSizeScale
                drawn.spriteLinear = draw.spriteLinear
                requests.append(.init(system: draw, inputs: drawn, kind: kind))
            }
            let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
            simulator.encode(requests, sceneSize: SIMD2(1280, 720), targetSize: SIMD2(1280, 720), commandBuffer: commandBuffer)
            commandBuffer.commit()
            last = commandBuffer
        }
        last?.waitUntilCompleted()
        XCTAssertNil(last?.error)

        let count = runtimes[0].gpu?.completedCount ?? 0
        XCTAssertGreaterThan(count, 50)
        let sprites = simulator.records(runtimes[0], as: LayerUniform.self, queue: queue)
        let trails = simulator.records(runtimes[1], as: LayerUniform.self, queue: queue)
        let ropes = simulator.records(runtimes[2], as: LayerUniform.self, queue: queue)
        XCTAssertEqual(sprites.fallback[1], UInt32(count))
        XCTAssertEqual(trails.fallback[1], UInt32(count), "the sprite trail draws every particle of the step")
        XCTAssertEqual(trails.records.count, count)
        XCTAssertGreaterThan(ropes.fallback[1], UInt32(count / 2), "the rope trail draws the step's history")
        XCTAssertLessThanOrEqual(ropes.fallback[1], UInt32(count * rope.trailSegments))
        XCTAssertTrue(runtimes[1].gpu !== runtimes[0].gpu)
        XCTAssertTrue(runtimes[1].gpu?.records !== runtimes[0].gpu?.records, "each renderer writes records of its own")
        // Same particles: the sprites and the trails sit at the same mean position.
        func mean(_ records: [LayerUniform]) -> SIMD2<Float> {
            records.reduce(SIMD2<Float>.zero) { $0 + $1.position } / Float(max(records.count, 1))
        }
        XCTAssertLessThan(simd_distance(mean(sprites.records), mean(trails.records)), 1)
    }

    // MARK: - Helpers

    private func build(_ renderers: String) throws -> (WEParticleSystem, SceneMetalParticleSystem) {
        let particles = try JSONDecoder().decode(WEParticleSystem.self, from: Data(#"""
            {"maxcount": 100, "material": "materials/p.json", "renderer": \#(renderers),
             "emitter": [{"name": "sphererandom", "rate": 30, "distancemax": 50}],
             "initializer": [{"name": "lifetimerandom", "min": 2, "max": 2}, {"name": "sizerandom", "min": 4, "max": 8}]}
            """#.utf8))
        let object = try JSONDecoder().decode(WESceneObject.self, from: Data(#"{"id": 1, "particle": "p.json"}"#.utf8))
        let firstName = particles.renderer?.first?.name ?? "sprite"
        var system = ParticleSystemBuilder.build(
            "p.json", particleSystem: particles, object: object, world: .identity, overrides: SceneParticleOverrides(),
            sceneSize: SIMD2(1000, 1000), source: .image(NSImage()), spriteSheet: nil, material: WEMaterial(),
            materialPlan: nil)
        system.material = Self.plan(firstName)
        ParticleSystemBuilder.addRenderers(to: &system, particleSystem: particles) { Self.plan($0.name ?? "sprite") }
        return (particles, system)
    }

    /// A stand-in material for `renderer`, named after it.
    private static func plan(_ renderer: String) -> ParticleMaterialPlan {
        ParticleMaterialPlan(materialPath: "materials/p.json", shader: renderer, format: format(renderer),
                             blending: "translucent", stages: [], trailLengths: .zero, spriteSheet: nil)
    }

    private static func format(_ renderer: String) -> ParticleVertexFormat {
        renderer.hasPrefix("rope") ? .rope : .sprite
    }

    private static func materialKind(_ renderer: String) -> ParticleGPUDrawKind {
        switch renderer {
        case "rope": return .rope
        case "ropetrail": return .ropeTrail
        default: return .sprite
        }
    }

    private static func fallbackKind(_ renderer: String) -> ParticleGPUDrawKind {
        switch renderer {
        case "rope": return .fallbackRope
        case "ropetrail": return .fallbackRopeTrail
        case "spritetrail": return .fallbackSpriteTrail
        default: return .fallbackSprite
        }
    }
}

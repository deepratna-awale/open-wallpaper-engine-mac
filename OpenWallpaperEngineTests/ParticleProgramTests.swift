import XCTest
import Metal
import simd
@testable import OpenWallpaperEngine

/// WE's particle defaults and semantics, from `wallpaper64.exe` (its particle parser 0x1401c1c70,
/// initializer switch 0x14023b5c0, operator VM 0x14023fbc0).
final class ParticleProgramTests: XCTestCase {
    private var texture: MTLTexture!

    override func setUpWithError() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        texture = try XCTUnwrap(device.makeTexture(descriptor: .texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)))
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func initializer(_ json: String, pixels: Bool = true) throws -> ParticleProgramOp {
        let element: WEParticleInitializer = try decode(json)
        return try XCTUnwrap(ParticleInitializerBuilder.make(element, defaults: ParticleDefaults(pixelUnits: pixels), path: "t")).record
    }

    private func `operator`(_ json: String, pixels: Bool = true) throws -> ParticleProgramOp {
        let element: WEParticleOperator = try decode(json)
        return try XCTUnwrap(ParticleOperatorBuilder.make(element, defaults: ParticleDefaults(pixelUnits: pixels),
                                                          sceneSize: SIMD2(100, 100), path: "t")).record
    }

    // MARK: - Registry

    /// Every initializer and operator name in `wallpaper64.exe`'s particle registry (its strings;
    /// effect gallery EXTRAS.md item 6, with `vortex_v2` in full) builds, except `collisionbox`,
    /// whose VM entry does nothing in WE.
    func testEveryRegisteredInitializerAndOperatorBuilds() throws {
        let initializers = ["colorrandom", "hsvcolorrandom", "colorlist", "sizerandom", "alpharandom", "velocityrandom",
                            "lifetimerandom", "rotationrandom", "angularvelocityrandom", "positionoffsetrandom",
                            "turbulentvelocityrandom", "inheritcontrolpointvelocity", "mapsequencearoundcontrolpoint",
                            "mapsequencebetweencontrolpoints", "remapinitialvalue", "inheritinitialvaluefromevent"]
        for name in initializers {
            XCTAssertNoThrow(try initializer(#"{"name":"\#(name)"}"#), name)
        }
        let operators = ["movement", "angularmovement", "alphafade", "alphachange", "sizechange", "colorchange",
                         "oscillateposition", "oscillatealpha", "oscillatesize", "turbulence", "vortex", "vortex_v2",
                         "boids", "controlpointattract", "maintaindistancetocontrolpoint",
                         "maintaindistancebetweencontrolpoints", "reducemovementnearcontrolpoint", "capvelocity",
                         "remapvalue", "inheritvaluefromevent", "collisionsphere", "collisionbounds",
                         "collisionquad", "collisionplane", "collisionmodel"]
        for name in operators {
            XCTAssertNoThrow(try `operator`(#"{"name":"\#(name)"}"#), name)
        }
        let box: WEParticleOperator = try decode(#"{"name":"collisionbox"}"#)
        XCTAssertNil(ParticleOperatorBuilder.make(box, defaults: ParticleDefaults(pixelUnits: true),
                                                  sceneSize: SIMD2(100, 100), path: "t"), "collisionbox")
        XCTAssertEqual(ParticleSystemBuilder.supportedEmitters, ["sphererandom", "boxrandom", "layerimage"])
    }

    // MARK: - Defaults

    func testInitializerDefaultsAreWEs() throws {
        XCTAssertEqual(try initializer(#"{"name":"lifetimerandom"}"#).a, SIMD4(0, 1, 1, 0))
        XCTAssertEqual(try initializer(#"{"name":"sizerandom"}"#).a, SIMD4(5, 50, 1, 0), "pixels in a 2D scene")
        XCTAssertEqual(try initializer(#"{"name":"sizerandom"}"#, pixels: false).a, SIMD4(0.001, 1, 1, 0))
        XCTAssertEqual(try initializer(#"{"name":"alpharandom"}"#).a, SIMD4(0.05, 1, 1, 0))
        let color = try initializer(#"{"name":"colorrandom","min":"255 0 0"}"#)
        XCTAssertEqual(color.a, SIMD4(1, 0, 0, 1), "divided by 255")
        XCTAssertEqual(color.b, SIMD4(1, 1, 1, 0))
        let velocity = try initializer(#"{"name":"velocityrandom"}"#)
        XCTAssertEqual(velocity.a, SIMD4(-32, -32, 0, 1))
        XCTAssertEqual(velocity.b, SIMD4(32, 32, 0, 0))
        XCTAssertEqual(try initializer(#"{"name":"rotationrandom","max":3}"#).b, SIMD4(0, 0, 3, 0), "a number is z")
        let hsv = try initializer(#"{"name":"hsvcolorrandom"}"#)
        XCTAssertEqual(hsv.a, SIMD4(0, 1.0 / 6.0, 6, 0), "six steps round the circle")
        XCTAssertEqual(hsv.b, SIMD4(0.5, 1, 0.5, 1))
        let around = try XCTUnwrap(ParticleInitializerBuilder.make(try decode(#"{"name":"mapsequencearoundcontrolpoint"}"#),
                                                                    defaults: ParticleDefaults(pixelUnits: true), path: "t"))
        XCTAssertEqual(around.sequenceCount, 32)
        XCTAssertEqual(around.record.d, SIMD4(0, 0, 1, 0))
        let between = try initializer(#"{"name":"mapsequencebetweencontrolpoints"}"#)
        XCTAssertEqual(between.b, SIMD4(0.3, 0.9, 0, 0), "arcamount, sizereductionamount")
        XCTAssertEqual(between.controlPoint1, 1)
        let remap = try initializer(#"{"name":"remapinitialvalue"}"#)
        XCTAssertEqual(ParticleProgramCPU.RemapCode.operation(remap.header.w), 1, "multiply")
        XCTAssertEqual(ParticleProgramCPU.RemapCode.input(remap.header.w), 1, "maxlifetime")
        XCTAssertEqual(ParticleProgramCPU.RemapCode.output(remap.header.w), 2, "size")
    }

    func testOperatorDefaultsAreWEs() throws {
        XCTAssertEqual(try `operator`(#"{"name":"alphafade"}"#).a, SIMD4(0.5, 0.5, 0, 0))
        XCTAssertEqual(try `operator`(#"{"name":"sizechange"}"#).a, SIMD4(1, 0, 0, 1))
        let oscillate = try `operator`(#"{"name":"oscillateposition"}"#)
        XCTAssertEqual(oscillate.c.y, 10, "scalemax in pixels")
        XCTAssertEqual(try `operator`(#"{"name":"oscillateposition"}"#, pixels: false).c.y, 0.5)
        let turbulence = try `operator`(#"{"name":"turbulence"}"#)
        XCTAssertEqual(turbulence.b, SIMD4(0.01, 500, 1000, 20))
        XCTAssertEqual(turbulence.c, SIMD4(0, 0, 0, 0), "phasemin 0, phasemax 0")
        XCTAssertEqual(try `operator`(#"{"name":"vortex"}"#).c, SIMD4(500, 650, 2500, 0))
        let attract = try `operator`(#"{"name":"controlpointattract"}"#)
        XCTAssertEqual(attract.b, SIMD4(512, 512, 15, 0))
        XCTAssertEqual(attract.header.y, 2, "flag 2: no overshoot")
        XCTAssertEqual(try `operator`(#"{"name":"reducemovementnearcontrolpoint"}"#).a, SIMD4(100, 350, 100, 0))
        XCTAssertEqual(try `operator`(#"{"name":"capvelocity"}"#).a.x, 100)
        XCTAssertEqual(try `operator`(#"{"name":"oscillatealpha"}"#).blend, ParticleProgramOp.noBlend)
        XCTAssertNotEqual(try `operator`(#"{"name":"oscillatealpha","blendinend":0.5}"#).blend, ParticleProgramOp.noBlend)
        let remap = try `operator`(#"{"name":"remapvalue"}"#)
        XCTAssertEqual(ParticleProgramCPU.RemapCode.input(remap.header.w), 0, "lifetimefraction")
        XCTAssertEqual(ParticleProgramCPU.RemapCode.output(remap.header.w), 2, "size")
    }

    func testEmitterAndRendererDefaultsAreWEs() throws {
        let sphere = ParticleSystemBuilder.emitterShape(try decode(#"{"name":"sphererandom"}"#),
                                                         defaults: ParticleDefaults(pixelUnits: true))
        XCTAssertEqual(sphere.distanceMaximum.x, 256)
        XCTAssertEqual(sphere.directions, SIMD3(1, 1, 0))
        let box = ParticleSystemBuilder.emitterShape(try decode(#"{"name":"boxrandom"}"#),
                                                      defaults: ParticleDefaults(pixelUnits: false))
        XCTAssertEqual(box.distanceMaximum, SIMD3(1, 1, 1))
        XCTAssertEqual(box.directions, SIMD3(1, 1, 1))
        let trail = ParticleRendererDefaults(try decode(#"{"name":"spritetrail"}"#))
        XCTAssertEqual([trail.length, trail.maximumLength, trail.minimumLength], [0.05, 10, 0])
        XCTAssertEqual(ParticleRendererDefaults(try decode(#"{"name":"rope"}"#)).subdivision, 4)
        let ropeTrail = ParticleRendererDefaults(try decode(#"{"name":"ropetrail"}"#))
        XCTAssertEqual(ropeTrail.subdivision, 1)
        XCTAssertEqual(ropeTrail.length, 1)
    }

    // MARK: - Semantics

    private func state(age: Float, lifetime: Float = 1) -> ParticleProgramState {
        var state = ParticleProgramState()
        state.age = age
        state.lifetime = lifetime
        state.baseSize = 10
        state.baseAlpha = 1
        return state
    }

    func testTwoOperatorsOfAKindBothApplyInOrder() {
        let grow = ParticleOperator(.sizeChange, a: SIMD4(1, 3, 0, 1)).record
        let shrink = ParticleOperator(.sizeChange, a: SIMD4(1, 0.5, 0, 1)).record
        var particle = state(age: 0.5)
        _ = ParticleProgramCPU.runOperators([grow, shrink], on: &particle, context: ParticleProgramContext(), index: 0,
                                            neighbors: .init())
        XCTAssertEqual(particle.size, 10 * 2 * 0.75, accuracy: 1e-5, "both multiply the base size")
    }

    func testAlphaFadeUsesFractionsOfTheLife() {
        let fade = ParticleOperator(.alphaFade, a: SIMD4(0.5, 0.5, 0, 0)).record
        for (age, expected) in [(0.25, 0.5), (0.5, 1), (0.75, 0.5)] as [(Float, Float)] {
            var particle = state(age: age)
            _ = ParticleProgramCPU.runOperators([fade], on: &particle, context: ParticleProgramContext(), index: 0,
                                                neighbors: .init())
            XCTAssertEqual(particle.alpha, expected, accuracy: 1e-5)
        }
    }

    func testOscillationsDrawEachParticlesOwnRandom() {
        let oscillate = ParticleOperator(.oscillateAlpha, b: SIMD4(1, 10, 0, 6.28), c: SIMD4(0, 1, 0, 0)).record
        var values: Set<Float> = []
        for random in [0.1, 0.5, 0.9] as [Float] {
            var context = ParticleProgramContext()
            context.random = random
            var particle = state(age: 0.3)
            _ = ParticleProgramCPU.runOperators([oscillate], on: &particle, context: context, index: 0, neighbors: .init())
            XCTAssertLessThanOrEqual(particle.alpha, random + 1e-5, "the random also scales the swing")
            values.insert(particle.alpha)
        }
        XCTAssertEqual(values.count, 3, "not the middle of the range for all")
    }

    /// `colorrandom` keeps `min` and `max − min` as they are (parser 0x1401c74bb…0x1401c7778, the
    /// span from 0x14005f0a0), so a minimum above the maximum (the snowstorm fog's "220 250 255" …
    /// "149 180 255") draws between the two, from the minimum down; nothing sorts or clamps it.
    func testColorRandomWithItsMinimumAboveItsMaximumDrawsBetweenThem() throws {
        let record = try initializer(#"{"name":"colorrandom","min":"220 250 255","max":"149 180 255"}"#)
        let minimum = SIMD3<Float>(220, 250, 255) / 255
        let maximum = SIMD3<Float>(149, 180, 255) / 255
        XCTAssertEqual(record.a.x, minimum.x, accuracy: 1e-5)
        XCTAssertEqual(record.b.x, maximum.x, accuracy: 1e-5)
        var sum = SIMD3<Float>.zero
        let count: Int = 400
        for serial in 0..<count {
            var particle = state(age: 0)
            particle.baseColor = SIMD3(repeating: 1)
            var context = ParticleProgramContext()
            context.serial = UInt32(serial)
            ParticleProgramCPU.runInitializers([record], on: &particle, context: context)
            let color: SIMD3<Float> = particle.baseColor
            let red: Float = color.x, green: Float = color.y
            XCTAssertLessThanOrEqual(red, minimum.x + 1e-5)
            XCTAssertGreaterThanOrEqual(red, maximum.x - 1e-5)
            XCTAssertLessThanOrEqual(green, minimum.y + 1e-5)
            XCTAssertGreaterThanOrEqual(green, maximum.y - 1e-5)
            sum += color
        }
        let mean: SIMD3<Float> = sum / Float(count)
        let middle: SIMD3<Float> = (minimum + maximum) / 2
        XCTAssertEqual(mean.x, middle.x, accuracy: 0.02, "uniform between the two")
        XCTAssertEqual(mean.y, middle.y, accuracy: 0.02)
    }

    func testHSVColorRandomPicksHueSteps() {
        let record = ParticleInitializer(.hsvColorRandom, a: SIMD4(0, 1.0 / 6.0, 6, 0), b: SIMD4(1, 1, 1, 1)).record
        var hues: Set<[Float]> = []
        for serial in UInt32(0)..<200 {
            var particle = state(age: 0)
            particle.baseColor = SIMD3(repeating: 1)
            var context = ParticleProgramContext()
            context.serial = serial
            ParticleProgramCPU.runInitializers([record], on: &particle, context: context)
            let c = particle.baseColor
            XCTAssertEqual(max(c.x, c.y, c.z), 1, accuracy: 1e-5, "full value")
            XCTAssertEqual(min(c.x, c.y, c.z), 0, accuracy: 1e-5, "full saturation")
            hues.insert([c.x, c.y, c.z].map { ($0 * 100).rounded() })
        }
        XCTAssertEqual(hues.count, 6, "six hues, 60° apart")
    }

    /// `remapvalue`'s `flags` (VM 0x140244996…0x1402457a3): bit 1 clamps the normalised input, bit 2
    /// the output. The parser reads an absent `flags` as 0 (0x1401ce803; its filler 0x1401bfbb0 writes
    /// none), so it clamps nothing. WE 2.8.0.42's flagtests (lifetimefraction 0…0.5 → size × 0…1)
    /// agree: flags 1 and 2 hold the size once half the life has passed (clip luminance 0.64 and
    /// 0.65 of the same particles without the remap), flags 0 keeps growing to twice it (1.33).
    func testRemapValueFlagsClampTheInputAndTheOutput() throws {
        for (flags, factor) in [("", 1.5), (#", "flags": 0"#, 1.5), (#", "flags": 1"#, 1), (#", "flags": 2"#, 1)] as [(String, Float)] {
            let remap = try `operator`(#"{"name": "remapvalue", "input": "lifetimefraction", "output": "size", "#
                                       + #""operation": "multiply", "inputrangemin": 0, "inputrangemax": 0.5, "#
                                       + #""outputrangemin": 0, "outputrangemax": 1"# + flags + "}")
            var particle = state(age: 0.75)
            _ = ParticleProgramCPU.runOperators([remap], on: &particle, context: ParticleProgramContext(), index: 0,
                                                neighbors: .init())
            XCTAssertEqual(particle.size, 10 * factor, accuracy: 1e-4, "flags\(flags)")
        }
    }

    /// WE simulates particles in 3D: `movement` moves them along z by their z velocity, with the
    /// gravity's z and the drag (0x14023fc08), and an emitter spreading along z launches them
    /// radially in depth too (0x140237c14). A `perspective` system's camera shows it.
    func testMovementAndTheEmitterWorkInDepth() throws {
        let movement = try `operator`(#"{"name": "movement", "gravity": "0 0 -10", "drag": 0.5}"#)
        var particle = state(age: 0)
        particle.velocity.z = 20
        var context = ParticleProgramContext()
        context.deltaTime = 0.5
        context.dragDeltaTime = 0.5
        _ = ParticleProgramCPU.runOperators([movement], on: &particle, context: context, index: 0, neighbors: .init())
        XCTAssertEqual(particle.position.z, 7.5, accuracy: 1e-5, "(20 − 10·0.5)·0.5")
        XCTAssertEqual(particle.velocity.z, 11.25, accuracy: 1e-5, "15·(1 − 0.5·0.5)")
        var shape = ParticleEmitterShape()
        shape.directions = SIMD3(0, 0, 1)
        shape.distanceMinimum = SIMD3(repeating: 100)
        shape.distanceMaximum = SIMD3(repeating: 100)
        shape.speed = SIMD2(10, 10)
        for serial in UInt32(0)..<8 {
            var spawn = ParticleProgramContext()
            spawn.serial = serial
            let emitted = ParticleProgramCPU.emit(shape, context: spawn)
            XCTAssertEqual(SIMD2(emitted.position.x, emitted.position.y), .zero)
            XCTAssertEqual(abs(emitted.position.z), 100, accuracy: 1e-3)
            XCTAssertEqual(emitted.velocity.z, emitted.position.z > 0 ? 10 : -10, accuracy: 1e-3, "radial, along z")
        }
    }

    func testRemapInitialValueDefaultMultipliesSizeByLifetime() throws {
        let remap = try initializer(#"{"name":"remapinitialvalue"}"#)
        var particle = state(age: 0, lifetime: 0.25)
        ParticleProgramCPU.runInitializers([remap], on: &particle, context: ParticleProgramContext())
        XCTAssertEqual(particle.baseSize, 2.5, accuracy: 1e-5)
    }

    /// Without `movement` WE doesn't move particles by their velocity; with it, velocities and
    /// gravity are in the system's space, so they scale with the object.
    func testMovementIsAnOperatorInTheSystemsSpace() {
        var system = ParticleTestSystem()
        system.emissionRate = 0
        system.instantaneous = 1
        system.spawnExtent = .zero
        system.minimumVelocity = SIMD2(10, 0)
        system.maximumVelocity = SIMD2(10, 0)
        system.lifetime = 10...10
        system.spins = false
        func travel(scale: Float, movement: Bool) -> Float {
            var configuration = system.configuration
            if !movement { configuration.program.operators.removeAll { $0.kind == .movement } }
            configuration.emitterLinear = simd_float2x2(diagonal: SIMD2(repeating: scale))
            let runtime = ParticleSystemRuntime(texture: texture, configuration: configuration, seed: 1)
            for _ in 0..<60 {
                ParticleCPUSimulation.step(runtime, inputs: ParticleFrameInputs.advance(runtime, deltaTime: 1 / 60, cursor: .zero))
            }
            return runtime.particles[0].position.x - system.origin.x
        }
        XCTAssertEqual(travel(scale: 1, movement: false), 0, accuracy: 1e-4)
        XCTAssertEqual(travel(scale: 1, movement: true), 10, accuracy: 0.05)
        XCTAssertEqual(travel(scale: 2, movement: true), 20, accuracy: 0.1, "velocity in the object's units")
    }

    /// `mapsequencebetweencontrolpoints` flag 32 restarts the sequence with each period of a
    /// periodic emitter (wallpaper64.exe 0x14022f850); without it the sequence runs on.
    func testSequencesRestartWithPeriodicEmissionWhenFlagged() {
        func positions(flags: UInt32) -> [Float] {
            var system = ParticleTestSystem()
            system.emissionRate = 0
            system.instantaneous = 3
            system.spawnExtent = .zero
            system.minimumVelocity = .zero
            system.maximumVelocity = .zero
            system.lifetime = 100...100
            system.emitterTiming.periodic = true
            system.emitterTiming.periodDuration = 0.1...0.1
            system.emitterTiming.periodDelay = 0.1...0.1
            system.controlPoints[1] = ParticleTestSystem.point(SIMD2(100, 0))
            var between = ParticleInitializer(.mapSequenceBetweenControlPoints, flags: flags, controlPoints: 0 | 1 << 8,
                                              a: SIMD4(0, 0, 1, 0))
            between.sequenceCount = 5
            system.initializers = [between]
            let runtime = ParticleSystemRuntime(texture: texture, configuration: system.configuration, seed: 1)
            for _ in 0..<20 {
                ParticleCPUSimulation.step(runtime, inputs: ParticleFrameInputs.advance(runtime, deltaTime: 1 / 60, cursor: .zero))
            }
            return runtime.particles.map { ($0.position.x - system.origin.x).rounded() }
        }
        XCTAssertEqual(positions(flags: 32), [0, 25, 50, 0, 25, 50])
        XCTAssertEqual(positions(flags: 0), [0, 25, 50, 75, 100, 0])
    }

    /// `starttime` pre-simulates in WE's steps (wallpaper64.exe 0x14022f2e0).
    func testStartTimePresimulatesInWEsSteps() {
        XCTAssertEqual(ParticlePrewarm.steps(startTime: 1, maximum: 100), Array(repeating: 0.05, count: 20))
        XCTAssertEqual(ParticlePrewarm.steps(startTime: 1, maximum: 500), Array(repeating: 0.2, count: 5))
        XCTAssertEqual(ParticlePrewarm.steps(startTime: 0, maximum: 100), [])
    }

    // MARK: - Emitters

    /// WE runs every emitter of a system (wallpaper64.exe 0x1402378a0), each with its own rate,
    /// shape, control point and clock.
    func testEveryEmitterOfASystemRuns() throws {
        let json = #"""
        {"maxcount": 500, "emitter": [
            {"name": "sphererandom", "rate": 30, "distancemax": 0},
            {"name": "boxrandom", "rate": 50, "controlpoint": 1, "distancemax": "0 0 0", "instantaneous": 5}],
         "controlpoint": [{"id": 0}, {"id": 1, "offset": "300 0 0"}],
         "initializer": [{"name": "lifetimerandom", "min": 100, "max": 100}]}
        """#
        let particles: WEParticleSystem = try decode(json)
        let object: WESceneObject = try decode(#"{"id": 1, "name": "p", "particle": "p.json"}"#)
        let configuration = ParticleSystemBuilder.build(
            "p.json", particleSystem: particles, object: object, world: .identity, overrides: SceneParticleOverrides(),
            sceneSize: SIMD2(1000, 1000), source: .image(NSImage()), spriteSheet: nil, material: WEMaterial(),
            materialPlan: nil)
        XCTAssertEqual(configuration.emitters.count, 2)
        XCTAssertEqual(configuration.extraEmitters[0].rate, 50)
        XCTAssertEqual(configuration.extraEmitters[0].instantaneous, 5)
        XCTAssertEqual(configuration.extraEmitters[0].shape.kind, .box)
        XCTAssertEqual(configuration.extraEmitters[0].shape.controlPoint, 1)
        let runtime = ParticleSystemRuntime(texture: texture, configuration: configuration, seed: 3)
        for _ in 0..<60 {
            ParticleCPUSimulation.step(runtime, inputs: ParticleFrameInputs.advance(runtime, deltaTime: 1 / 60, cursor: .zero))
        }
        let atOrigin = runtime.particles.filter { simd_length($0.position) < 1 }.count
        let atPoint = runtime.particles.filter { simd_distance($0.position, SIMD2(300, 0)) < 1 }.count
        XCTAssertEqual(atOrigin, 30, "the first emitter's rate")
        // The burst comes out of the emitter's own carry (0x140237a06): 5 at once, then 45 by its rate.
        XCTAssertEqual(atPoint, 50, "the second's rate and burst, on its control point")
        XCTAssertEqual(runtime.particles.count, 80)
    }

    // MARK: - Frame rate

    /// WE damps drag (and the field operators' step) by `pow(min(0.025 / frame time, 1), 0.7)` and
    /// runs the operators in two half steps at a frame-rate limit of 1…20 (0x140237724…0x140237793).
    func testDragFollowsWEsFrameTimeAndHalfSteps() {
        var inputs = ParticleFrameInputs()
        inputs.deltaTime = 1 / 60
        inputs.frameTime = 1 / 60
        XCTAssertEqual(inputs.dragDeltaTime, 1 / 60, accuracy: 1e-7, "40 frames a second or more: the step")
        inputs.frameTime = 1 / 30
        XCTAssertEqual(inputs.dragDeltaTime, 1 / 60 * pow(0.75, 0.7), accuracy: 1e-7)
        inputs.frameTime = 0
        XCTAssertEqual(inputs.dragDeltaTime, 1 / 60, accuracy: 1e-7, "no frame yet")
        XCTAssertEqual(inputs.substeps, 1)
        inputs.frameRateLimit = 20
        XCTAssertEqual(inputs.substeps, 2)
        inputs.frameRateLimit = 21
        XCTAssertEqual(inputs.substeps, 1)

        var system = ParticleTestSystem()
        system.emissionRate = 0
        system.instantaneous = 1
        system.spawnExtent = .zero
        system.minimumVelocity = SIMD2(100, 0)
        system.maximumVelocity = SIMD2(100, 0)
        system.lifetime = 10...10
        system.spins = false
        system.drag = 2
        func velocity(frameTime: Float, limit: Int) -> Float {
            let runtime = ParticleSystemRuntime(texture: texture, configuration: system.configuration, seed: 1)
            ParticleCPUSimulation.step(runtime, inputs: ParticleFrameInputs.advance(
                runtime, deltaTime: 0.1, cursor: .zero, frameTime: frameTime, frameRateLimit: limit))
            return runtime.particles[0].velocity.x
        }
        let damped: Float = 100 * (1 - 2 * 0.1 * pow(Float(0.25), 0.7))
        XCTAssertEqual(velocity(frameTime: 0.1, limit: 60), damped, accuracy: 1e-3)
        let half: Float = 2 * 0.05 * pow(Float(0.25), 0.7)
        XCTAssertEqual(velocity(frameTime: 0.1, limit: 10), 100 * (1 - half) * (1 - half), accuracy: 1e-3,
                       "two half steps")
    }
}

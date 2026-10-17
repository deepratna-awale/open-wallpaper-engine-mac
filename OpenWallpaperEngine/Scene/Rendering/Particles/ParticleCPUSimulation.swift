import Metal
import QuartzCore
import simd

struct Particle {
    /// In the scene.
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var age: Float
    var lifetime: Float
    /// WE's size: the full width of the particle's quad.
    var size: Float
    var baseSize: Float
    var alpha: Float
    var baseAlpha: Float
    var rotation: Float
    var angularVelocity: Float
    var color: SIMD4<Float>
    var baseColor: SIMD4<Float>
    let spriteFrame: Int
    var history: [SIMD2<Float>]
    var historyStart: Int
    /// Spawn order within the system; with the system's seed it names the particle's random draws.
    var serial: UInt32 = 0
    /// The instance it belongs to, in an instanced system (`ParticleChildLink`).
    var instance: Int = 0
    /// Depth along the system's z and its velocity (`ParticleProgramState.z`).
    var z: Float = 0
    var zVelocity: Float = 0
    /// The rotation and angular velocity about x and y (`ParticleProgramState.rotationXY`); the
    /// renderer reads them as `a_TexCoordVec4.xy` (`genericparticle.vert`'s `in_ParticleRotation`).
    var rotationXY = SIMD2<Float>.zero
    var angularVelocityXY = SIMD2<Float>.zero

    /// `history` is a circular buffer; this returns it oldest-first so a trail can be walked.
    var orderedHistory: [SIMD2<Float>] {
        guard historyStart > 0, historyStart < history.count else { return history }
        return Array(history[historyStart...] + history[..<historyStart])
    }
}

/// The particle simulation on the CPU, in `wallpaper64.exe`'s order (0x140236cd0): every particle
/// ages by the step and those past their lifetime die (0x140236d91), the emitter spawns and the
/// initializers run on the new particles (0x1402378a0), then the operators run over all of them
/// (0x14023fbc0). `ParticleSimulation.metal` runs the same step on the GPU; the two must stay in
/// step (`ParticleSimulationParityTests`).
enum ParticleCPUSimulation {
    static func update(_ particleSystems: [ParticleSystemRuntime], deltaTime: Float, cursor: SIMD2<Float>) {
        let signpost = OWESignpost.begin(OWESignpost.render, "updateParticles")
        defer { signpost.end() }
        for system in particleSystems {
            step(system, inputs: ParticleFrameInputs.advance(system, deltaTime: deltaTime, cursor: cursor))
        }
    }

    /// How many particles to spawn this step, as WE counts them (0x1402379aa…0x140237b74): the
    /// burst, then the rate's whole particles (at most `rateLimit`). The burst is taken out of the
    /// carried fraction too, and a system already at its maximum takes nothing from the rate.
    /// Spawns a full system can't take are skipped, not queued.
    static func emission(liveCount: Int, maximum: Int, rate: Float, deltaTime: Float,
                         remainder: inout Float, burst: Int = 0, rateLimit: Int = .max) -> (burst: Int, rate: Int) {
        let available = max(maximum - liveCount, 0)
        let burst = max(burst, 0)
        guard liveCount < maximum else { return (min(burst, available), 0) }
        remainder += max(rate, 0) * deltaTime
        var count = 0
        if remainder >= 1 {
            count = Int(min(remainder.rounded(.down), 2_147_483_520))
            remainder -= Float(count) + Float(burst)
            count = min(count, max(rateLimit, 0))
        } else {
            remainder -= Float(burst)
        }
        let taken = min(burst, available)
        return (taken, min(count, available - taken))
    }

    static func step(_ system: ParticleSystemRuntime, inputs frame: ParticleFrameInputs) {
        let configuration = system.configuration
        let start = configuration.link?.controlPointStart
        var inputs = frame
        if let start, !configuration.isInstanced {
            inputs = frame.linked(ParticleControlPointLink.positions(for: system, slot: 0), start: start)
        }
        system.spawnedThisStep.removeAll(keepingCapacity: true)
        system.diedThisStep.removeAll(keepingCapacity: true)
        if inputs.clears {
            system.particles.removeAll(keepingCapacity: true)
            system.died = 0
            for index in system.emitterStates.indices {
                system.emitterStates[index].remainder = 0
                system.emitterStates[index].periodEmitted = 0
            }
            for index in system.instances.indices { system.instances[index] = ParticleInstance() }
            return
        }
        age(system, deltaTime: inputs.deltaTime)
        let firstSerial = system.nextSerial
        var instanceInputs: [ParticleFrameInputs] = []
        if configuration.isInstanced {
            countInstanceParticles(system)
            updateInstances(system, inputs: inputs)
            instanceInputs = system.instances.enumerated().map { slot, instance in
                let placed = inputs.placed(at: instance.translation, previous: instance.previousTranslation)
                guard let start else { return placed }
                return placed.linked(ParticleControlPointLink.positions(for: system, slot: slot), start: start)
            }
            if !configuration.worldSpace {
                for index in system.particles.indices {
                    let instance = system.instances[system.particles[index].instance]
                    followInstance(&system.particles[index], instance: instance, inputs: inputs)
                }
            }
            for (index, instance) in system.instances.enumerated() where instance.active {
                // Each emitter's spawns in turn; a period restarts the instance's sequence from there.
                var spawned = instance.spawned, periodSpawned = instance.periodSpawned
                for (emitter, state) in instance.emitterStates.enumerated() {
                    if state.startsPeriod { periodSpawned = spawned }
                    for _ in 0..<state.spawnCount {
                        system.particles.append(spawn(serial: system.nextSerial, system: system, inputs: &instanceInputs[index],
                                                      emitter: emitter, instance: index, source: instance,
                                                      sequence: SIMD2(spawned, spawned &- periodSpawned)))
                        system.nextSerial &+= 1
                        spawned &+= 1
                    }
                }
                system.instances[index].spawned = spawned
                system.instances[index].periodSpawned = periodSpawned
            }
        } else {
            if let motion = inputs.motion {
                for index in system.particles.indices { follow(&system.particles[index], motion: motion) }
            }
            // Every emitter in turn, each counting what the earlier ones spawned (0x1402378a0).
            for (index, emitter) in inputs.emitters.enumerated() where index < system.emitterStates.count {
                if emitter.startsPeriod {
                    system.emitterStates[index].periodEmitted = 0
                    system.periodSerial = system.nextSerial
                }
                let limit = ParticleEmitterClock.rateLimit(periodLimit: emitter.periodLimit,
                                                           emitted: system.emitterStates[index].periodEmitted,
                                                           onePerFrame: emitter.onePerFrame)
                let emitted = emission(liveCount: system.particles.count, maximum: inputs.maximum,
                                       rate: emitter.rate, deltaTime: inputs.deltaTime,
                                       remainder: &system.emitterStates[index].remainder, burst: emitter.burst,
                                       rateLimit: limit)
                system.emitterStates[index].periodEmitted += emitted.rate
                if emitted.burst + emitted.rate > 0 { system.emitterStates[index].spawns(layerWorld: emitter.layerWorld) }
                for _ in 0..<(emitted.burst + emitted.rate) {
                    let serial = system.nextSerial
                    system.particles.append(spawn(serial: serial, system: system, inputs: &inputs, emitter: index,
                                                  sequence: SIMD2(serial, serial &- system.periodSerial)))
                    system.nextSerial &+= 1
                }
            }
        }
        let neighbors = ParticleProgramCPU.Neighbors(positions: system.particles.map { SIMD3($0.position, $0.z) },
                                                     velocities: system.particles.map { SIMD3($0.velocity, $0.zVelocity) },
                                                     serials: system.particles.map(\.serial), frame: inputs.frameIndex)
        if configuration.program.operatorsWriteControlPoints {
            advanceOperatorMajor(system, inputs: &inputs, instanceInputs: &instanceInputs, neighbors: neighbors)
        } else {
            for index in system.particles.indices {
                let instance = system.particles[index].instance
                let own = instanceInputs.isEmpty ? inputs : instanceInputs[instance]
                let source = instanceInputs.isEmpty ? nil : system.instances[instance]
                advance(&system.particles[index], index: index, system: system, inputs: own, source: source,
                        neighbors: neighbors)
            }
        }
        for index in system.particles.indices where configuration.isInstanced {
            if system.instances[system.particles[index].instance].clearing { system.particles[index].age = .infinity }
        }
        if configuration.program.writesControlPoints, !configuration.isInstanced {
            keepWrittenControlPoints(system, inputs: inputs)
        }
        if configuration.hasEventChildren {
            for particle in system.particles where particle.serial &- firstSerial < system.nextSerial &- firstSerial {
                system.spawnedThisStep.append(particle)
            }
        }
        // A cleared instance's particles go with it.
        system.particles.removeAll { $0.age == .infinity }
        if configuration.isInstanced { countInstanceParticles(system) }
    }

    /// Ages every particle by the step; those past their lifetime die (0x140236d91).
    static func age(_ system: ParticleSystemRuntime, deltaTime: Float) {
        for index in system.particles.indices { system.particles[index].age += deltaTime }
        if system.configuration.hasEventChildren {
            system.diedThisStep = system.particles.filter { $0.lifetime < $0.age }
        }
        let count = system.particles.count
        system.particles.removeAll { $0.lifetime < $0.age }
        system.died &+= UInt32(count - system.particles.count)
    }

    /// Carries a particle that lives in its emitter's space along with the emitter's move. Its size
    /// and rotation stay the emitter's own: it is drawn through the emitter's transform
    /// (`ParticleSystemRuntime.drawLinear`).
    static func follow(_ particle: inout Particle, motion: SceneAffineTransform) {
        particle.position = motion.apply(particle.position)
        particle.velocity = motion.linear * particle.velocity
        for sample in particle.history.indices {
            particle.history[sample] = motion.apply(particle.history[sample])
        }
    }

    /// The program's view of the step for particle `serial`.
    static func context(_ system: ParticleSystemRuntime, inputs: ParticleFrameInputs, serial: UInt32,
                        source: ParticleInstance?) -> ParticleProgramContext {
        var context = ParticleProgramContext()
        context.deltaTime = inputs.deltaTime
        context.dragDeltaTime = inputs.dragDeltaTime
        context.engineTime = inputs.engineTime
        context.systemTime = inputs.elapsedTime
        context.timeOfDay = inputs.timeOfDay
        context.seed = system.seed
        context.serial = serial
        context.random = ParticleRandom.unit(seed: system.seed, serial: serial, stream: ParticleRandom.Stream.operator.rawValue)
        context.controlPoints = inputs.controlPoints
        context.controlPointAxes = inputs.controlPointAxes
        context.previousControlPoints = inputs.previousControlPoints
        context.space = inputs.space
        context.toSpace = inputs.toSpace
        context.worldSpace = system.configuration.worldSpace
        context.collisions = inputs.collisions
        context.source = source
        context.spawnScale = inputs.spawnScale
        context.layerOrigin = inputs.layerOrigin
        return context
    }

    /// A new particle: the emitter's shape, WE's base values and every initializer
    /// (0x14023b340: lifetime 1, size 0.5, the instance colour and alpha).
    /// A `remapinitialvalue` that writes a control point writes it into `inputs` for the spawns and
    /// the operators after it.
    static func spawn(serial: UInt32, system: ParticleSystemRuntime, inputs: inout ParticleFrameInputs, emitter: Int = 0,
                      instance: Int = 0, source: ParticleInstance? = nil, sequence: SIMD2<UInt32>) -> Particle {
        let configuration = system.configuration
        var context = context(system, inputs: inputs, serial: serial, source: source)
        context.sequenceIndex = sequence.x
        context.sequenceRestartIndex = sequence.y
        var state = ParticleProgramState()
        state.lifetime = 1
        state.baseSize = 0.5
        state.baseAlpha = inputs.spawnScale.y
        state.baseColor = inputs.colorScale
        let shape = emitter == 0 ? configuration.emitter : configuration.extraEmitters[emitter - 1].shape
        context.emitterAxes = ParticleProgramCPU.point(inputs.controlPointAxes, shape.controlPoint)
        if shape.kind == .image {
            let points = shape.imageIndex < system.emitterImages.count ? system.emitterImages[shape.imageIndex].points : []
            let step = emitter < inputs.emitters.count ? inputs.emitters[emitter] : ParticleEmitterStep()
            let emitterState = instance < system.instances.count && configuration.isInstanced
                ? system.instances[instance].emitterStates[safe: emitter] : system.emitterStates[safe: emitter]
            if let emitted = ParticleProgramCPU.emit(image: points, shape: shape, step: step,
                                                     lastLayerWorld: emitterState?.spawnLayerWorld, context: context) {
                state.position = ParticleProgramCPU.lift(emitted.position)
                state.velocity = ParticleProgramCPU.lift(emitted.velocity)
                state.baseColor *= emitted.color
            }
        } else {
            let emitted = ParticleProgramCPU.emit(shape, context: context)
            state.position = emitted.position
            state.velocity = emitted.velocity
        }
        ParticleProgramCPU.runInitializers(inputs.initializers, on: &state, in: &context)
        inputs.controlPoints = context.controlPoints
        // A worldspace particle leaves the emitter's space: it takes the emitter's scale and turn now.
        let size = state.baseSize * inputs.spawnSizeScale
        let color = SIMD4(state.baseColor, 1)
        return Particle(
            position: inputs.space.apply(ParticleProgramCPU.flat(state.position)),
            velocity: inputs.space.linear * ParticleProgramCPU.flat(state.velocity),
            age: 0, lifetime: state.lifetime, size: size, baseSize: size, alpha: state.baseAlpha, baseAlpha: state.baseAlpha,
            rotation: state.rotation + inputs.spawnTurn, angularVelocity: state.angularVelocity,
            color: color, baseColor: color,
            spriteFrame: ParticleRandom.index(configuration.spriteSheet?.frames ?? 1, seed: system.seed, serial: serial, .spriteFrame),
            history: [], historyStart: 0, serial: serial, instance: instance, z: state.position.z,
            zVelocity: state.velocity.z, rotationXY: state.rotationXY, angularVelocityXY: state.angularVelocityXY)

    }

    /// One step of every operator for the particle at `index`.
    static func advance(_ particle: inout Particle, index: Int, system: ParticleSystemRuntime, inputs: ParticleFrameInputs,
                        source: ParticleInstance?, neighbors: ParticleProgramCPU.Neighbors) {
        var context = context(system, inputs: inputs, serial: particle.serial, source: source)
        var state = programState(particle, inputs: inputs)
        // At a frame-rate limit of 20 or less WE runs the operators twice, in half steps
        // (`ParticleFrameInputs.substeps`); the neighbours stay the step's.
        let substeps = inputs.substeps
        context.deltaTime /= Float(substeps)
        context.dragDeltaTime /= Float(substeps)
        var dies = false
        for _ in 0..<substeps {
            if ParticleProgramCPU.runOperators(inputs.operators, on: &state, in: &context, index: index,
                                               neighbors: neighbors) { dies = true }
        }
        finish(&particle, state: state, dies: dies, system: system, inputs: inputs)
    }

    /// `particle` as the program sees it, in the system's space.
    static func programState(_ particle: Particle, inputs: ParticleFrameInputs) -> ParticleProgramState {
        var state = ParticleProgramState()
        state.position = SIMD3(inputs.toSpace * (particle.position - inputs.space.translation), particle.z)
        state.velocity = SIMD3(inputs.toSpace * particle.velocity, particle.zVelocity)
        state.age = particle.age
        state.lifetime = particle.lifetime
        state.baseSize = particle.baseSize
        state.baseAlpha = particle.baseAlpha
        state.baseColor = SIMD3(particle.baseColor.x, particle.baseColor.y, particle.baseColor.z)
        state.rotation = particle.rotation
        state.angularVelocity = particle.angularVelocity
        state.rotationXY = particle.rotationXY
        state.angularVelocityXY = particle.angularVelocityXY
        return state

    }

    /// Takes the operators' `state` back into `particle` and records its trail history.
    static func finish(_ particle: inout Particle, state: ParticleProgramState, dies: Bool, system: ParticleSystemRuntime,
                       inputs: ParticleFrameInputs) {
        let configuration = system.configuration
        particle.position = inputs.space.apply(ParticleProgramCPU.flat(state.position))
        particle.velocity = inputs.space.linear * ParticleProgramCPU.flat(state.velocity)
        particle.lifetime = state.lifetime
        particle.size = state.size
        particle.alpha = state.alpha
        particle.color = SIMD4(state.color, particle.color.w)
        particle.rotation = state.rotation
        particle.angularVelocity = state.angularVelocity
        particle.rotationXY = state.rotationXY
        particle.angularVelocityXY = state.angularVelocityXY
        particle.z = state.position.z

        particle.zVelocity = state.velocity.z
        // A deleted particle dies when it next ages (WE sets its age to its lifetime).
        if dies { particle.age = particle.lifetime }
        // Only the ropetrail renderer reads history: every particle records a sample when the
        // system's countdown runs out (`ParticleTrailHistory`), a new one at once.
        let history = configuration.trailHistory
        if history.kept {
            let historyLimit = history.limit
            if inputs.samplesTrail || particle.history.isEmpty {
                if particle.history.count < historyLimit {
                    particle.history.append(particle.position)
                } else {
                    particle.history[particle.historyStart] = particle.position
                    particle.historyStart = (particle.historyStart + 1) % historyLimit
                }
            }
        }
    }
}

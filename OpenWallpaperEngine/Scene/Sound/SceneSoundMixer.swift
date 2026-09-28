import AVFoundation

/// One wallpaper instance's audio graph: an `AVAudioEngine` whose main mixer takes every sound
/// layer's voices. It is made when a voice first plays (a muted wallpaper, or a display that
/// doesn't play the wallpaper's sound, never touches the audio hardware), starts then, and pauses
/// when the layers go silent. Offline (manual rendering) for tests. Main thread.
final class SceneSoundMixer {
    let engine = AVAudioEngine()
    private var failed = false
    private let label: String
    /// Where spatialized voices meet (`attachSpatial`), made with the first of them.
    private var spatialBus: AVAudioMixerNode?

    /// `offline` renders on demand (`AVAudioEngine.renderOffline`) instead of to the output device.
    init(label: String, offline: AVAudioFormat? = nil) {
        self.label = label
        if let offline {
            do {
                try engine.enableManualRenderingMode(.offline, format: offline, maximumFrameCount: 4096)
            } catch {
                OWELog.error(.audio, "\(label): offline sound rendering is unavailable: \(error)")
                failed = true
            }
        }
    }

    deinit {
        // Disposing an engine's output talks to coreaudiod; a stalled daemon must not stall the
        // renderer, so the engine goes on a queue of its own.
        let engine = self.engine
        DispatchQueue.global(qos: .utility).async { engine.stop() }
    }

    func attach(_ node: AVAudioPlayerNode, format: AVAudioFormat) {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
    }

    func detach(_ node: AVAudioNode) {
        engine.detach(node)
    }

    /// Attaches a voice whose left and right gains are set on their own
    /// (`SceneSoundSpatialization`): the player feeds a stage mixer, and the stage's input on a
    /// stereo bus takes the gains as a volume and a balance. That input pans the (stereo) player's
    /// signal linearly: left × min(1, 1 − pan), right × min(1, 1 + pan).
    func attachSpatial(_ node: AVAudioPlayerNode, format: AVAudioFormat) -> AVAudioMixerNode? {
        guard let stereo = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 2) else { return nil }
        let bus: AVAudioMixerNode
        if let spatialBus {
            bus = spatialBus
        } else {
            bus = AVAudioMixerNode()
            engine.attach(bus)
            engine.connect(bus, to: engine.mainMixerNode, format: stereo)
            spatialBus = bus
        }
        let stage = AVAudioMixerNode()
        engine.attach(node)
        engine.attach(stage)
        engine.connect(node, to: stage, format: format)
        engine.connect(stage, to: bus, format: stereo)
        return stage
    }

    /// A stage's left and right gains (`attachSpatial`), as its volume and balance on the bus.
    static func setGains(_ gains: SIMD2<Float>, of stage: AVAudioMixerNode) {
        let left = max(gains.x, 0), right = max(gains.y, 0)
        let level = max(left, right)
        stage.volume = level
        stage.pan = level > 0 ? (right - left) / level : 0
    }

    /// Starts the engine if it isn't running; false (logged once) when it can't.
    func run() -> Bool {
        if engine.isRunning { return true }
        guard !failed else { return false }
        do {
            engine.prepare()
            try engine.start()
            return true
        } catch {
            failed = true
            OWELog.error(.audio, "\(label): the sound engine can't start, sound layers stay silent: \(error)")
            return false
        }
    }

    /// Pauses the engine (nothing plays).
    func idle() {
        if engine.isRunning { engine.pause() }
    }
}

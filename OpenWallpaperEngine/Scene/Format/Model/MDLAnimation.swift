import Foundation

/// A clip of the `MDLA` section, versions 1–6 (docs/models-plan.md §1.4). A scene's
/// `animationlayers` name it by `id`.
struct MDLAnimation: Equatable {
    /// How the clip plays past its end (0x1401a8c71): "mirror" ping-pongs, "single" plays once,
    /// any other name loops.
    enum Mode: Equatable {
        case loop, mirror, single

        init(name: String) {
            switch name {
            case "mirror": self = .mirror
            case "single": self = .single
            default: self = .loop
            }
        }
    }

    /// A bone or link track: `frames + 1` samples of 9 floats (`MDLBonePose`).
    struct Track: Equatable {
        /// Bit 0: disabled, the bone keeps its bind pose.
        var flags: UInt32
        var samples: [Float]

        var isDisabled: Bool { flags & 1 != 0 }

        /// The pose at `frame` (0…frames).
        func pose(at frame: Int) -> MDLBonePose {
            let base = frame * MDLBonePose.floatCount
            return MDLBonePose(samples[base..<(base + MDLBonePose.floatCount)])
        }
    }

    /// One float per frame: a constraint track (`tag` is its value) or one of the scalar lists
    /// (`tag` is the u32 WE skips before it).
    struct ScalarTrack: Equatable {
        var tag: UInt32
        var samples: [Float]
    }

    /// The morph-weight tracks of one mesh (`MDLA` 4 and later).
    struct MeshTrack: Equatable {
        struct MorphTrack: Equatable {
            var morph: UInt16
            var samples: [Float]
        }

        /// Bit 0: `weight` and `morphTracks` follow.
        var flags: UInt32
        var weight: Float?
        var morphTracks: [MorphTrack]?
    }

    /// When flags & 1: the clip the model editor cut from an earlier one ("Add Clip"), with its
    /// root-motion bone (0x140264fc9…0x140265348, the 0xc0-byte record at anim+0x150: the index
    /// at +0x8, the four u32s at +0xc…+0x18). WE's editor writes one for every clip it cuts
    /// (docs/test-risks.md MG4: start 0, end 30, offset 0, bone −1 or 2 for a 30-frame clip).
    struct Reference: Equatable {
        /// The clip it was cut from (earlier in the file).
        var animation: UInt16
        /// The editor's Start frame and End frame, in the source clip; with root motion WE reads
        /// the root's start and end matrices there (unless the clip matches its loop, flag 0x400).
        var startFrame: UInt32
        var endFrame: UInt32
        /// The editor's Frame offset: where the root's previous matrix starts [I: the editor
        /// always wrote 0].
        var frameOffset: UInt32
        /// The editor's Motion root bone; −1 for None.
        var rootBone: Int32
    }

    /// The clip flags the model editor sets (docs/test-risks.md MG4; 0x14021cc0c, 0x140225900).
    enum Flag {
        /// `reference` follows.
        static let reference: UInt32 = 0x1
        /// "Match loop" (on by default): the root's start and end matrices come from this clip's
        /// first and last frames rather than the source clip's Start and End frames.
        static let matchLoop: UInt32 = 0x400
        /// Root motion on position x, y, z and rotation x, y, z; the editor offers only yaw of the
        /// rotations, and WE applies only yaw.
        static let rootPositionX: UInt32 = 0x800
        static let rootPositionY: UInt32 = 0x1000
        static let rootPositionZ: UInt32 = 0x2000
        static let rootRotationX: UInt32 = 0x4000
        static let rootRotationY: UInt32 = 0x8000
        static let rootRotationZ: UInt32 = 0x10000
        static let rootMotion: UInt32 = 0x1f800
    }

    struct Event: Equatable {
        var frame: Float
        var name: String
    }

    var id: UInt64
    var name: String
    /// The mode as written; `mode` interprets it.
    var modeName: String
    var fps: Float
    /// The last frame index: every track has `frames + 1` samples.
    var frames: UInt32
    /// `Flag`s: bit 0, `reference` follows; 0x400 Match loop; 0x1f800 the root-motion axes. WE
    /// sets 0x80000000 in its copy when a track is disabled.
    var flags: UInt32
    /// One per bone in the library.
    var boneTracks: [Track]
    /// `MDLA` 2 and later: one per skeleton link.
    var linkTracks: [Track]?
    /// `MDLA` 2 and later: one per skeleton constraint.
    var constraintTracks: [ScalarTrack]?
    /// `MDLA` 3 and later: one per Puppet Warp texture channel, its `g_BlendMap` entry (the
    /// clip's list at +0xd8, 0x1402646dc; the puppet update samples it at 0x1401fefa0…0x1401ffa2e).
    var scalarTracksA: [ScalarTrack]?
    /// `MDLA` 3 and later, when present: one per bone track.
    var scalarTracksB: [ScalarTrack]?
    /// `MDLA` 4 and later, when present: one per mesh.
    var meshTracks: [MeshTrack]?
    /// `MDLA` 5 and later: the animated model's box.
    var bounds: MDLBounds?
    /// `MDLA` 6 and later, when present: one per bone track.
    var scalarTracksC: [ScalarTrack]?
    var reference: Reference?
    var events: [Event]

    var mode: Mode { Mode(name: modeName) }
    /// `frames / fps` seconds (0x1401a8c10).
    var duration: Float { Float(frames) / fps }
}

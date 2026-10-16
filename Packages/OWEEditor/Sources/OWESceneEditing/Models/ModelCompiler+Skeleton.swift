import Foundation
import simd

extension ModelCompiler {
    /// The `MDLS` bones of a skinned model: the root ("RootNode"), every node a skin deforms
    /// with and every ancestor of one, in the source's order (parents first), as WE's importer
    /// keeps them (the library's skinned imports: PaRappa's `windows_front.mdl` keeps RootNode,
    /// the mesh's object, the armature and its bones; docs/models-plan.md §1.3, capture 509 D).
    struct Skeleton {
        struct Bone {
            var name: String
            var parent: Int?
            var local: simd_float4x4
            var isBone: Bool
            var sourceNode: Int
        }

        var nodes: [Bone]
        /// Source node index → bone index.
        var map: [Int: Int]
        let rest: [simd_float4x4]

        init(_ source: ModelSource) {
            var needed = Set<Int>()
            let used = Set(source.meshes.flatMap { mesh in
                (mesh.influences ?? []).flatMap { i in (0..<4).compactMap { i.weights[$0] > 0 ? Int(i.nodes[$0]) : nil } }
            })
            for node in source.nodes.indices where source.nodes[node].isBone || used.contains(node) {
                var current: Int? = node
                while let index = current, needed.insert(index).inserted { current = source.nodes[index].parent }
            }
            if !source.nodes.isEmpty { needed.insert(0) }
            var bones: [Bone] = []
            var map: [Int: Int] = [:]
            for (index, node) in source.nodes.enumerated() where needed.contains(index) {
                map[index] = bones.count
                let name = node.parent == nil && node.name.isEmpty ? "RootNode" : node.name
                bones.append(Bone(name: name, parent: node.parent.flatMap { map[$0] }, local: node.local,
                                  isBone: node.isBone || used.contains(index), sourceNode: index))
            }
            nodes = bones
            self.map = map
            rest = PuppetMath.worlds(locals: bones.map(\.local), parents: bones.map(\.parent))
        }

        func index(of name: String) -> Int? { nodes.firstIndex { $0.name == name } }

        /// A corner's influences by bone index.
        func remap(_ influences: ModelSource.Influences) -> ModelSource.Influences {
            var out = influences
            for slot in 0..<4 { out.nodes[slot] = influences.weights[slot] > 0 ? UInt32(map[Int(influences.nodes[slot])] ?? 0) : 0 }
            return out
        }

        /// A mesh without a skin in a skinned model moves with the root.
        var rootInfluence: ModelSource.Influences {
            ModelSource.Influences(nodes: .zero, weights: SIMD4(1, 0, 0, 0))
        }

        func children(of bone: Int) -> [Int] { nodes.indices.filter { nodes[$0].parent == bone } }

        /// The `MDLS0004` body: bones with their properties JSON (the configuration's physics,
        /// compiled as Puppet Warp's are), no links, constraints, maps or IK sets, and the bone
        /// boxes; no draw-order arrays.
        func section(meshes: [CompiledMesh], config: ModelImportConfig) -> [UInt8] {
            var out = PuppetMDLOutput()
            out.u32(UInt32(nodes.count))
            for (index, bone) in nodes.enumerated() {
                out.cstring(bone.name)
                out.u32(bone.isBone ? 1 : 0)
                out.u32(bone.parent.map { UInt32($0) } ?? 0xFFFF_FFFF)
                out.u32(64)
                out.matrix(bone.local)
                var properties = ""
                if let physics = config.constraints[bone.name] {
                    let child = children(of: index).first
                    let distance = child.map { simd_distance(origin(rest[$0]), origin(rest[index])) }
                    properties = PuppetMDLWriter.propertiesJSON(physics.properties(childDistance: distance))
                }
                out.cstring(properties)
            }
            out.u16(0) // links
            out.u8(0)  // no separate bind matrices
            out.u32(0) // constraints
            out.u16(0) // maps
            out.u16(0) // IK sets
            out.u8(1)  // the bone boxes
            for (center, half) in boxes(meshes) {
                out.f32s([half.x, half.y, half.z])
                out.matrix(simd_float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(center, 1))))
            }
            out.u8(0)  // no draw order (Puppet Warp's arrays)
            out.u8(0)
            return out.bytes
        }

        /// Per bone, the box of the vertices it moves (any weight) in its bind space: its centre
        /// and half size; zero for a bone that moves none. PaRappa's doors match this exactly.
        func boxes(_ meshes: [CompiledMesh]) -> [(SIMD3<Float>, SIMD3<Float>)] {
            var low = Array(repeating: SIMD3<Float>(repeating: .greatestFiniteMagnitude), count: nodes.count)
            var high = Array(repeating: SIMD3<Float>(repeating: -.greatestFiniteMagnitude), count: nodes.count)
            let inverses = rest.map(\.inverse)
            for mesh in meshes {
                for (p, influence) in zip(mesh.positions, mesh.influences) {
                    for slot in 0..<4 where influence.weights[slot] > 0 {
                        let bone = Int(influence.nodes[slot])
                        guard bone < nodes.count else { continue }
                        let q = inverses[bone] * SIMD4(p, 1)
                        let local = SIMD3(q.x, q.y, q.z)
                        low[bone] = simd_min(low[bone], local)
                        high[bone] = simd_max(high[bone], local)
                    }
                }
            }
            return nodes.indices.map { bone in
                low[bone].x > high[bone].x ? (.zero, .zero) : ((low[bone] + high[bone]) / 2, (high[bone] - low[bone]) / 2)
            }
        }

        func origin(_ m: simd_float4x4) -> SIMD3<Float> { SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z) }

        // MARK: Animations

        /// A sampled animation by bone: `frames + 1` local transforms per bone.
        struct Track {
            var name: String
            var fps: Float
            var frames: Int
            var samples: [[PuppetTransform]]
        }

        /// The source's animations, then each additional file's, matched to these bones by name;
        /// a bone an animation doesn't have keeps its rest pose.
        func animations(_ source: ModelSource, additional: [ModelSource]) -> [Track] {
            var tracks: [Track] = []
            for animation in source.animations {
                tracks.append(Track(name: animation.name, fps: animation.fps, frames: animation.frames,
                                    samples: nodes.map { bone in
                                        let samples = animation.samples.indices.contains(bone.sourceNode) ? animation.samples[bone.sourceNode] : []
                                        return samples.isEmpty ? [PuppetTransform(matrix: bone.local)] : samples
                                    }))
            }
            for file in additional {
                for animation in file.animations {
                    tracks.append(Track(name: animation.name, fps: animation.fps, frames: animation.frames,
                                        samples: nodes.map { bone in
                                            let index = file.nodes.firstIndex { $0.name == bone.name }
                                            let samples = index.flatMap { animation.samples.indices.contains($0) ? animation.samples[$0] : nil } ?? []
                                            return samples.isEmpty ? [PuppetTransform(matrix: bone.local)] : samples
                                        }))
                }
            }
            return tracks
        }

        /// One `MDLA` record.
        struct Record {
            var id: UInt64
            var name: String
            var mode: String
            var fps: Float
            var frames: Int
            var flags: UInt32
            var samples: [[PuppetTransform]]
            var reference: (source: Int, start: Int, end: Int, offset: Int, rootBone: Int32)?
            var events: [(Float, String)]
        }

        /// The animations (ids 1, 2, …) and then the configuration's clips cut from them.
        func records(_ tracks: [Track], config: ModelImportConfig) -> [Record] {
            var records: [Record] = tracks.enumerated().map { index, track in
                let id = ModelCompiler.animationID(index)
                return Record(id: id, name: track.name, mode: "loop", fps: track.fps, frames: max(track.frames, 1), flags: 0,
                              samples: track.samples, reference: nil, events: events(config, id))
            }
            for clip in config.clips {
                guard let sourceIndex = records.prefix(tracks.count).firstIndex(where: { $0.id == clip.animation }) else { continue }
                let source = records[sourceIndex]
                let start = min(max(clip.start, 0), source.frames)
                let end = min(max(clip.end, start), source.frames)
                let frames = max(end - start, 1)
                let samples = source.samples.map { bone in
                    (0...frames).map { frame in bone[min(start + frame, bone.count - 1)] }
                }
                var flags: UInt32 = 0x1 | UInt32(clip.motionFlags) << 8
                if clip.matchLoop { flags |= 0x400 }
                let rootBone = clip.rootMotion.isEmpty ? -1 : Int32(index(of: clip.rootMotion) ?? -1)
                records.append(Record(id: clip.id, name: clip.name, mode: clip.mode, fps: clip.fps ?? source.fps, frames: frames,
                                      flags: flags, samples: samples,
                                      reference: (sourceIndex, start, end, max(clip.frameOffset, 0), rootBone),
                                      events: events(config, clip.id)))
            }
            return records
        }

        func events(_ config: ModelImportConfig, _ animation: UInt64) -> [(Float, String)] {
            config.events.filter { $0.animation == animation }.sorted { $0.frame < $1.frame }.map { ($0.frame, $0.name) }
        }

        func animationSection(_ records: [Record], meshes: [CompiledMesh], config: ModelImportConfig) -> [UInt8] {
            var out = PuppetMDLOutput()
            out.i32(Int32(records.count))
            for record in records {
                out.u64(record.id)
                out.cstring(record.name)
                out.cstring(record.mode)
                out.f32(record.fps)
                out.u32(UInt32(record.frames))
                out.u32(record.flags)
                out.i32(Int32(nodes.count))
                for bone in nodes.indices {
                    out.u32(0)
                    var blob = PuppetMDLOutput()
                    let samples = record.samples[bone]
                    for frame in 0...record.frames {
                        blob.f32s(samples[min(frame, samples.count - 1)].samples)
                    }
                    out.blob(blob.bytes)
                }
                // MDLA 2: no link or constraint tracks (none in the skeleton).
                out.u32(0) // MDLA 3: no texture-channel tracks
                out.u8(0)  //         no per-bone opacity
                out.u8(0)  // MDLA 4: no morph weights
                let (low, high) = animatedBounds(record, meshes: meshes)
                out.f32s([low.x, low.y, low.z, high.x, high.y, high.z])  // MDLA 5
                out.u8(0)  // MDLA 6: no per-bone depth
                if let reference = record.reference {
                    out.u16(UInt16(reference.source))
                    out.u32(UInt32(reference.start))
                    out.u32(UInt32(reference.end))
                    out.u32(UInt32(reference.offset))
                    out.i32(reference.rootBone)
                }
                out.i32(Int32(record.events.count))
                for (frame, name) in record.events {
                    out.f32(frame)
                    out.cstring(name)
                }
            }
            return out.bytes
        }

        /// The skinned meshes' box over every frame (`MDLA` 5): each frame's palette
        /// (`world(pose) · world(rest)⁻¹`) applied to every vertex.
        func animatedBounds(_ record: Record, meshes: [CompiledMesh]) -> (SIMD3<Float>, SIMD3<Float>) {
            let inverses = rest.map(\.inverse)
            var low = SIMD3<Float>(repeating: .greatestFiniteMagnitude), high = -low
            for frame in 0...record.frames {
                let locals = nodes.indices.map { bone -> simd_float4x4 in
                    let samples = record.samples[bone]
                    return PuppetPoseTransform(samples[min(frame, samples.count - 1)]).matrix
                }
                let worlds = PuppetMath.worlds(locals: locals, parents: nodes.map(\.parent))
                let palette = zip(worlds, inverses).map { $0 * $1 }
                for mesh in meshes {
                    for (p, influence) in zip(mesh.positions, mesh.influences) {
                        var skinned = SIMD4<Float>.zero
                        for slot in 0..<4 where influence.weights[slot] > 0 {
                            skinned += palette[min(Int(influence.nodes[slot]), palette.count - 1)] * SIMD4(p, 1) * influence.weights[slot]
                        }
                        let q = SIMD3(skinned.x, skinned.y, skinned.z)
                        low = simd_min(low, q)
                        high = simd_max(high, q)
                    }
                }
            }
            return low.x > high.x ? (.zero, .zero) : (low, high)
        }
    }
}

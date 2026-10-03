import AppKit
import SwiftUI
import OWESceneEditing

/// Seconds to points across the timeline's width, with room at both ends for a keyframe's diamond.
struct TimelineScale: Equatable {
    var duration: Double
    var width: Double
    static let inset: Double = 12

    private var span: Double { max(width - 2 * Self.inset, 1) }

    func x(_ seconds: Double) -> Double { Self.inset + seconds / max(duration, 1e-6) * span }
    func seconds(_ x: Double) -> Double { (x - Self.inset) / span * duration }
    func x(frame: Int, fps: Double) -> Double { x(fps > 0 ? Double(frame) / fps : 0) }
    func pointsPerFrame(fps: Double) -> Double { fps > 0 ? span / max(duration, 1e-6) / fps : 1 }

    /// Ruler steps: the shortest from the list at least `minimum` points apart.
    func tickStep(minimum: Double = 64) -> Double {
        let steps: [Double] = [0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300]
        let perSecond = span / max(duration, 1e-6)
        return steps.first { $0 * perSecond >= minimum } ?? steps[steps.count - 1]
    }
}

/// One row of the timeline: a track (its keyframes on every channel together) or one of its
/// channels.
struct TimelineRow: Identifiable, Hashable {
    let target: TimelineTarget
    /// Nil for the track's own row.
    let channel: Int?

    var id: String { "\(target.layer)/\(target.effect ?? -1)/\(target.pass ?? -1)/\(target.key)/\(channel ?? -1)" }

    static let height: Double = 24
}

/// The time ruler: ticks and times, the playhead, and scrubbing (drag anywhere on it; the
/// playhead snaps to the active clip's frames).
struct TimelineRuler: View {
    @ObservedObject var timeline: SceneTimelineEditor
    static let height: Double = 24

    var body: some View {
        GeometryReader { proxy in
            let scale = TimelineScale(duration: timeline.duration, width: proxy.size.width)
            let playhead = timeline.playhead
            Canvas { context, size in
                let step = scale.tickStep()
                var tick = 0.0
                while tick <= scale.duration + 1e-9 {
                    let x = scale.x(tick)
                    context.stroke(Path { $0.move(to: CGPoint(x: x, y: size.height - 8)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                                   with: .color(.secondary), lineWidth: 1)
                    context.draw(Text(verbatim: TimelineNames.time(tick)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary),
                                 at: CGPoint(x: x + 3, y: 2), anchor: .topLeading)
                    let half = tick + step / 2
                    if half <= scale.duration {
                        let hx = scale.x(half)
                        context.stroke(Path { $0.move(to: CGPoint(x: hx, y: size.height - 4)); $0.addLine(to: CGPoint(x: hx, y: size.height)) },
                                       with: .color(.secondary.opacity(0.6)), lineWidth: 1)
                    }
                    tick += step
                }
                let x = scale.x(playhead)
                var head = Path()
                head.move(to: CGPoint(x: x - 5, y: size.height - 10))
                head.addLine(to: CGPoint(x: x + 5, y: size.height - 10))
                head.addLine(to: CGPoint(x: x, y: size.height))
                head.closeSubpath()
                context.fill(head, with: .color(.red))
                context.stroke(Path { $0.move(to: CGPoint(x: x, y: 0)); $0.addLine(to: CGPoint(x: x, y: size.height)) },
                               with: .color(.red), lineWidth: 1)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in scrub(to: drag.location.x, scale: scale) })
            .accessibilityElement()
            .accessibilityLabel(T("Playhead"))
            .accessibilityValue(TimelineNames.time(playhead))
            .accessibilityAdjustableAction { direction in
                guard let clip = timeline.activeClip else { return }
                let frame = timeline.playheadFrame(in: clip)
                timeline.setPlayhead(frame: direction == .increment ? frame + 1 : max(frame - 1, 0), in: clip)
            }
        }
        .frame(height: Self.height)
    }

    private func scrub(to x: Double, scale: TimelineScale) {
        let seconds = scale.seconds(x)
        if let clip = timeline.activeClip, clip.fps > 0 {
            timeline.setPlayhead((seconds * clip.fps).rounded() / clip.fps)
        } else {
            timeline.setPlayhead(seconds)
        }
    }
}

/// The keyframe lanes: each row's keyframes on the time axis. Click selects (Shift or ⌘ adds and
/// removes), dragging a selected keyframe moves the selection by whole frames, dragging on empty
/// space draws a selection box.
struct TimelineLanes: View {
    @ObservedObject var timeline: SceneTimelineEditor
    let rows: [TimelineRow]
    let onFocus: () -> Void

    @State private var gesture: LaneGesture?
    @State private var box: CGRect?

    init(timeline: SceneTimelineEditor, rows: [TimelineRow], onFocus: @escaping () -> Void) {
        self.timeline = timeline
        self.rows = rows
        self.onFocus = onFocus
    }

    private enum LaneGesture {
        case move(start: CGPoint, pointsPerFrame: Double)
        case box(start: CGPoint, extending: Bool)
    }

    /// One keyframe as drawn: where, which keyframes it stands for, and how.
    struct Mark {
        var point: CGPoint
        var refs: Set<TimelineKeyframeRef>
        var selected: Bool
        var hold: Bool
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = TimelineScale(duration: timeline.duration, width: proxy.size.width)
            let marks = makeMarks(scale: scale)
            let spans = makeSpans(scale: scale)
            let playheadX = scale.x(timeline.playhead)
            let focusedRows = Set(rows.indices.filter { rows[$0].target == timeline.activeTarget })
            Canvas { context, size in
                for index in rows.indices {
                    let y = Double(index) * TimelineRow.height
                    let band = CGRect(x: 0, y: y, width: size.width, height: TimelineRow.height)
                    if focusedRows.contains(index) {
                        context.fill(Path(band), with: .color(.accentColor.opacity(0.08)))
                    } else if index % 2 == 1 {
                        context.fill(Path(band), with: .color(.primary.opacity(0.03)))
                    }
                }
                for span in spans {
                    context.stroke(Path { $0.move(to: span.0); $0.addLine(to: span.1) },
                                   with: .color(.secondary.opacity(0.5)), lineWidth: 2)
                }
                for mark in marks {
                    let path = mark.hold ? Self.square(at: mark.point) : Self.diamond(at: mark.point)
                    context.fill(path, with: mark.selected ? .color(.accentColor) : .color(Color(nsColor: .controlBackgroundColor)))
                    context.stroke(path, with: mark.selected ? .color(.accentColor) : .color(.primary.opacity(0.75)), lineWidth: 1)
                }
                context.stroke(Path { $0.move(to: CGPoint(x: playheadX, y: 0)); $0.addLine(to: CGPoint(x: playheadX, y: size.height)) },
                               with: .color(.red), lineWidth: 1)
                if let box {
                    context.fill(Path(box), with: .color(.accentColor.opacity(0.12)))
                    context.stroke(Path(box), with: .color(.accentColor.opacity(0.7)), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in changed(drag, marks: marks, scale: scale) }
                .onEnded { drag in ended(drag, marks: marks) })
        }
        .frame(height: max(Double(rows.count) * TimelineRow.height, TimelineRow.height))
    }

    static func diamond(at point: CGPoint, radius: Double = 5.5) -> Path {
        Path { path in
            path.move(to: CGPoint(x: point.x, y: point.y - radius))
            path.addLine(to: CGPoint(x: point.x + radius, y: point.y))
            path.addLine(to: CGPoint(x: point.x, y: point.y + radius))
            path.addLine(to: CGPoint(x: point.x - radius, y: point.y))
            path.closeSubpath()
        }
    }

    static func square(at point: CGPoint, radius: Double = 4.5) -> Path {
        Path(CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }

    private func makeMarks(scale: TimelineScale) -> [Mark] {
        var marks: [Mark] = []
        for (index, row) in rows.enumerated() {
            guard let clip = timeline.clip(row.target) else { continue }
            let y = (Double(index) + 0.5) * TimelineRow.height
            let channels = row.channel.map { [$0] } ?? Array(clip.channels.indices)
            var byFrame: [Int: (refs: Set<TimelineKeyframeRef>, hold: Bool)] = [:]
            for channel in channels where clip.channels.indices.contains(channel) {
                for keyframe in clip.channels[channel] {
                    let ref = TimelineKeyframeRef(target: row.target, channel: channel, frame: keyframe.frame)
                    byFrame[keyframe.frame, default: ([], keyframe.step)].refs.insert(ref)
                }
            }
            for (frame, entry) in byFrame {
                marks.append(Mark(point: CGPoint(x: scale.x(frame: frame, fps: clip.fps), y: y), refs: entry.refs,
                                  selected: entry.refs.contains { timeline.isSelected($0) }, hold: entry.hold))
            }
        }
        return marks
    }

    /// Each track row's animated stretch, first keyframe to last.
    private func makeSpans(scale: TimelineScale) -> [(CGPoint, CGPoint)] {
        rows.enumerated().compactMap { index, row in
            guard let clip = timeline.clip(row.target) else { return nil }
            let frames = row.channel.map { clip.channels.indices.contains($0) ? clip.channels[$0].map(\.frame) : [] } ?? clip.keyframeFrames
            guard let first = frames.min(), let last = frames.max(), last > first else { return nil }
            let y = (Double(index) + 0.5) * TimelineRow.height
            return (CGPoint(x: scale.x(frame: first, fps: clip.fps), y: y), CGPoint(x: scale.x(frame: last, fps: clip.fps), y: y))
        }
    }

    private func hit(_ point: CGPoint, marks: [Mark]) -> Mark? {
        marks.filter { abs($0.point.y - point.y) < TimelineRow.height / 2 && abs($0.point.x - point.x) <= 7 }
            .min { abs($0.point.x - point.x) < abs($1.point.x - point.x) }
    }

    private func changed(_ drag: DragGesture.Value, marks: [Mark], scale: TimelineScale) {
        let modifiers = NSEvent.modifierFlags
        let extending = modifiers.contains(.shift) || modifiers.contains(.command)
        if gesture == nil {
            onFocus()
            if let mark = hit(drag.startLocation, marks: marks) {
                if extending {
                    timeline.toggleSelection(mark.refs)
                } else if !mark.refs.contains(where: { timeline.selection.contains($0) }) {
                    timeline.select(mark.refs)
                }
                if let target = mark.refs.first?.target { timeline.focused = target }
                let fps = mark.refs.first.flatMap { timeline.clip($0.target)?.fps } ?? 30
                gesture = .move(start: drag.startLocation, pointsPerFrame: scale.pointsPerFrame(fps: fps))
            } else {
                gesture = .box(start: drag.startLocation, extending: extending)
                let row = Int(drag.startLocation.y / TimelineRow.height)
                if rows.indices.contains(row) { timeline.focused = rows[row].target }
            }
        }
        switch gesture {
        case let .move(start, pointsPerFrame)?:
            guard !timeline.selection.isEmpty else { return }
            let frames = Int(((drag.location.x - start.x) / max(pointsPerFrame, 1e-6)).rounded())
            timeline.previewMove(byFrames: frames)
        case let .box(start, _)?:
            box = CGRect(x: min(start.x, drag.location.x), y: min(start.y, drag.location.y),
                         width: abs(drag.location.x - start.x), height: abs(drag.location.y - start.y))
        case nil:
            break
        }
    }

    private func ended(_ drag: DragGesture.Value, marks: [Mark]) {
        defer {
            gesture = nil
            box = nil
        }
        switch gesture {
        case .move?:
            timeline.commitPreview(actionName: T("Move Keyframes"))
        case let .box(_, extending)?:
            let refs = Set(marks.filter { box?.insetBy(dx: -2, dy: -2).contains($0.point) == true }.flatMap(\.refs))
            if box.map({ $0.width < 2 && $0.height < 2 }) ?? true {
                if !extending { timeline.selection = [] }
            } else {
                timeline.select(refs, extending: extending)
            }
        case nil:
            break
        }
    }
}

//
//  WorkingInProgress.swift
//  Open Wallpaper Engine
//
//  Created by Haren on 2023/8/21.
//

import SwiftUI

struct WorkingInProgress: View {
    
    @State var bigGearAngle = 0.0
    @State var smallGearAngle = 0.0
    
    var body: some View {
        VStack {
            ZStack {
                Image(systemName: "gearshape")
                    .font(.system(size: 48))
                    .rotationEffect(.degrees(bigGearAngle + 30))
                    .offset(x: -20, y: -10)
                Image(systemName: "gearshape")
                    .font(.system(size: 32, weight: .semibold))
                    .rotationEffect(.degrees(smallGearAngle))
                    .offset(x: 20, y: 10)
            }
            .padding()
            .onAppear {
                withAnimation(.linear(duration: 5).repeatForever(autoreverses: false)) {
                    bigGearAngle = 360
                    smallGearAngle = -360
                }
            }
            Text("Working on it")
        }
    }
}

struct NumericSliderInput<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    @Binding var value: Value
    let range: ClosedRange<Value>
    let defaultValue: Value
    var step: Value.Stride?
    var displayScale = 1.0
    var suffix = ""
    var fractionDigits = 2
    var sliderWidth: CGFloat? = nil
    var fieldWidth: CGFloat = 64
    /// False lets a typed value go past the slider's range, as WE's editor number field does.
    var clampsTypedValue = true

    /// `TextField(value:format:)` only writes back on commit, so typing needed a click elsewhere to
    /// take effect and dragging the slider left the field stale. The text is mirrored manually to
    /// keep both directions live.
    @State private var text = ""
    @FocusState private var isEditing: Bool

    private var displayedValue: Double { Double(value) * displayScale }

    private func formatted(_ number: Double) -> String {
        String(format: "%.\(fractionDigits)f", number)
    }

    private func commit(_ string: String) {
        guard let parsed = Double(string.trimmingCharacters(in: .whitespaces)) else { return }
        let lowerBound = Double(range.lowerBound) * displayScale
        let upperBound = Double(range.upperBound) * displayScale
        let clamped = clampsTypedValue ? min(max(parsed, lowerBound), upperBound) : parsed
        value = Value(clamped / displayScale)
    }

    /// Whether the field should show `displayed` in place of `text`. Always when the field isn't
    /// being edited; while it is, only when the value moved away from what the text says (the
    /// slider was dragged, or Reset ran, with the field still focused), so typing isn't rewritten
    /// under the cursor but the field never goes stale waiting for a click elsewhere.
    static func shouldMirror(text: String, displayed: Double, isEditing: Bool, fractionDigits: Int) -> Bool {
        guard isEditing else { return true }
        guard let typed = Double(text.trimmingCharacters(in: .whitespaces)) else { return true }
        return abs(typed - displayed) > 0.5 * pow(10, -Double(max(fractionDigits, 0)))
    }

    /// Arrow keys in the field nudge the value by the step (or one shown digit), live.
    private func nudge(_ direction: Double) {
        let increment = step.map { Double($0) } ?? pow(10, -Double(max(fractionDigits, 0))) / displayScale
        let raw = Double(value) + direction * increment
        let lower = Double(range.lowerBound), upper = Double(range.upperBound)
        let next: Double = clampsTypedValue ? min(max(raw, lower), upper) : raw
        value = Value(next)
        text = formatted(displayedValue)
    }

    /// Rounds `raw` to the nearest multiple of `step` counted from the range's lower bound,
    /// clamped to the range; without a step the value passes through.
    static func snapped(_ raw: Value, in range: ClosedRange<Value>, step: Value.Stride?) -> Value {
        guard let step, step > 0 else { return raw }
        let steps = (range.lowerBound.distance(to: raw) / step).rounded()
        return min(max(range.lowerBound.advanced(by: steps * step), range.lowerBound), range.upperBound)
    }

    var body: some View {
        HStack(spacing: 8) {
            // `Slider(value:in:step:)` draws an AppKit tick mark per step under the track, and a
            // fine step (0.1 over 0–2, 1 over 0–120) packs them into a solid line. The slider stays
            // continuous and the binding snaps instead, like WE's own sliders.
            Slider(value: Binding(
                get: { value },
                set: { value = Self.snapped($0, in: range, step: step) }
            ), in: range)
            .frame(width: sliderWidth)
            .onTapGesture(count: 2) { value = defaultValue }

            HStack(spacing: 2) {
                TextField("", text: $text)
                    .focused($isEditing)
                    .multilineTextAlignment(.trailing)
                    .frame(width: fieldWidth)
                    .onChange(of: text) { _, newText in
                        if isEditing { commit(newText) }
                    }
                    .onSubmit {
                        commit(text)
                        text = formatted(displayedValue)
                    }
                    .onKeyPress(.upArrow) { nudge(1); return .handled }
                    .onKeyPress(.downArrow) { nudge(-1); return .handled }
                if !suffix.isEmpty {
                    Text(suffix).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { text = formatted(displayedValue) }
        .onChange(of: value) { _, _ in
            if Self.shouldMirror(text: text, displayed: displayedValue, isEditing: isEditing,
                                 fractionDigits: fractionDigits) {
                text = formatted(displayedValue)
            }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { text = formatted(displayedValue) }
        }
    }
}

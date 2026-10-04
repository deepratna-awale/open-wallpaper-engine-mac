import SwiftUI

/// The Screen Saver mode's right-hand panel: the note that the screen saver is a recording, Record
/// and Set as Screen Saver, the last and next recording, the daily re-recording, the selected
/// layer's adjustments and the user properties, all of them the mode's own
/// (`ScreenSaverEditorModel`, `IsolatedSceneEditSession`).
struct ScreenSaverEditorPanel<Layer: View>: View {
    @ObservedObject var model: ScreenSaverEditorModel
    @ObservedObject var schedule: ScreenSaverDailyScheduler
    /// The selected layer's adjustments (the Scene Editor (Live)'s own controls, on the isolated store).
    @ViewBuilder let layer: () -> Layer

    init(model: ScreenSaverEditorModel, @ViewBuilder layer: @escaping () -> Layer) {
        self.model = model
        schedule = model.schedule
        self.layer = layer
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                recordingNote
                recordSection
                Divider()
                scheduleSection
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Layer Adjustments")
                        .font(.headline)
                    Text("Turn layers on or off in the list on the left. The screen saver keeps these choices for this wallpaper.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    layer()
                }
                Divider()
                Text("Only the screen saver changes. The wallpaper on your desktop keeps its properties and edits.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                SceneUserPropertiesView(wallpaper: model.wallpaper, scopes: [model.session.scope])
            }
            .padding()
        }
    }

    /// Always shown: the screen saver plays a video, so live values stand still in it.
    private var recordingNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("The screen saver is a recording", systemImage: "video.fill")
                .font(.subheadline.bold())
            Text("Open Wallpaper Engine records a video of the wallpaper for the screen saver. Dates, times, days and other live data (clocks, media info, audio-reactive parts) show their values from when it was recorded and don’t update while the screen saver runs. Hide those layers, or turn on the daily re-recording.")
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var recordSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isRecording {
                ProgressView {
                    Text("Recording the loop…")
                }
                .progressViewStyle(.linear)
            } else {
                Button {
                    model.record()
                } label: {
                    Label("Record and Set as Screen Saver", systemImage: "record.circle")
                }
                .glassButtonStyle(.prominent)
                .help("Record a seamless loop of this version of the wallpaper and make it the screen saver")
            }
            if model.preview == nil {
                Button("Preview Recording") { model.playRecording() }
                    .disabled(!model.hasRecording || model.isRecording)
                    .help("Play the last recorded loop")
            } else {
                Button("Show Live Wallpaper") { model.stopPreview() }
                    .help("Stop the recording and show the wallpaper as it plays")
            }
            if model.isScreenSaver {
                Text("This wallpaper’s recording is your screen saver.")
                    .font(.caption)
                HStack {
                    Button("Stop Using as Screen Saver") { model.stopUsingAsScreenSaver() }
                        .disabled(model.isRecording)
                        .help("Go back to making the screen saver from your desktop wallpaper")
                    Button("Open Screen Saver Settings…") { ScreenSaverInstaller.current.openSettings() }
                }
            }
            if let lastRecorded = model.lastRecorded {
                Text("Last recorded: \(lastRecorded.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Not recorded yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("Re-record Every Day at", isOn: Binding(get: { schedule.schedule.isEnabled },
                                                               set: { schedule.setEnabled($0) }))
                DatePicker("Time", selection: Binding(get: { model.scheduleTime }, set: { model.scheduleTime = $0 }),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .disabled(!schedule.schedule.isEnabled)
            }
            if schedule.schedule.isEnabled, let next = schedule.nextFire {
                Text("Next: \(next.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("Each day at this time, the screen saver is recorded again with that day’s date and time and replaces the previous video. If your Mac was asleep or Open Wallpaper Engine wasn’t open, it records at the next wake or launch. It runs in the background and waits while the battery is low.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

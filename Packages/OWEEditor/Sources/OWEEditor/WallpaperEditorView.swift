import SwiftUI
import OWESceneEditing

/// The Wallpaper Editor window (docs/editor-plan.md): the layer list on the left, the live canvas
/// in the middle, the selected layer's inspector on the right, and the document actions (undo,
/// redo, Revert, Save as Local Wallpaper) in the toolbar.
public struct WallpaperEditorView: View {
    @ObservedObject private var session: SceneEditSession
    private let services: WallpaperEditorServices
    @StateObject private var tools = EditorTools()
    @State private var isInspectorPresented = true
    @AppStorage("WallpaperEditorScriptHeight") private var scriptHeight: Double = 340
    @State private var isConfirmingRevert = false
    @State private var isSaving = false
    @State private var notice: Notice?
    @StateObject private var authoring: EditorAuthoringModel

    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    public init(session: SceneEditSession, services: WallpaperEditorServices) {
        self.session = session
        self.services = services
        _authoring = StateObject(wrappedValue: EditorAuthoringModel(session: session, projectJSON: services.projectJSON,
                                                                    console: services.scriptConsole))
    }

    public var body: some View {
        NavigationSplitView {
            LayerListView(session: session, tools: tools, services: services)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 380)
        } detail: {
            TimelineDock(timeline: services.timeline) {
                // A plain stack with its own divider, like the timeline dock: an AppKit split view
                // nested in the split view's detail and the inspector reported changing minimum
                // sizes back and forth until AppKit stopped the layout ("more Update Constraints
                // passes than there are views") and the app crashed.
                VStack(spacing: 0) {
                    EditorCanvasView(session: session, tools: tools, services: services)
                        .overlay(alignment: .top) { noticeBanner }
                        .frame(minHeight: 200)
                    // The script editor docks under the canvas, which keeps running what it applies.
                    if let draft = authoring.draft {
                        ScriptDockDivider(height: $scriptHeight)
                        ScriptEditorPanel(authoring: authoring, draft: draft)
                            .frame(height: min(max(scriptHeight, 240), 640))
                    }
                }
            }
                .inspector(isPresented: $isInspectorPresented) {
                    LayerInspectorView(session: session, tools: tools, services: services)
                        .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
                }
                .toolbar { toolbar }
        }
        .environment(\.sceneTimeline, services.timeline)
        .frame(minWidth: 960, minHeight: 600)
        .onChange(of: tools.problem) { _, problem in
            guard let problem else { return }
            tools.problem = nil
            show(Notice(text: problem, isError: true))
        }
        .environmentObject(authoring)
        .sheet(item: $authoring.bindingTarget) { target in
            BindPropertySheet(authoring: authoring, target: target)
        }
        .sheet(isPresented: $authoring.isEditingProperties) {
            UserPropertiesEditorView(authoring: authoring)
        }
        .alert(L("Revert to the Original?"), isPresented: $isConfirmingRevert) {
            Button(L("Revert"), role: .destructive) { session.revert(actionName: L("Revert")) }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Every edit made in the editor is dropped. You can undo this."))
        }
        .sheet(isPresented: $isSaving) {
            SaveAsLocalSheet(suggestedTitle: services.suggestedLocalTitle) { title in
                do {
                    let saved = try services.saveAsLocalWallpaper(title)
                    show(Notice(text: L("Saved “\(saved)” to the library."), isError: false))
                } catch {
                    show(Notice(text: L("The wallpaper couldn’t be saved: \(error.localizedDescription)"), isError: true))
                }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { session.undo() } label: {
                Label(L("Undo"), systemImage: "arrow.uturn.backward")
            }
            .help(session.undoManager.undoMenuItemTitle)
            .disabled(!session.canUndo)
            Button { session.redo() } label: {
                Label(L("Redo"), systemImage: "arrow.uturn.forward")
            }
            .help(session.undoManager.redoMenuItemTitle)
            .disabled(!session.canRedo)
        }
        ToolbarItem {
            AddLayerMenu(actions: LayerActions(session: session, services: services, tools: tools))
        }
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
        }
        authoringItems
        ToolbarItem {
            Button { isConfirmingRevert = true } label: {
                Label(L("Revert"), systemImage: "arrow.counterclockwise")
            }
            .help(L("Drop every edit made in the editor"))
            .disabled(!session.overlay.hasSceneEdits && !session.overlay.hasPuppetEdits)
        }
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        }
        ToolbarItem {
            Button { isSaving = true } label: {
                Label(L("Save as Local Wallpaper…"), systemImage: "square.and.arrow.down")
                    .labelStyle(.titleAndIcon)
            }
            .help(L("Save a copy of the wallpaper with these edits to the library"))
        }
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        }
        panelItems
    }

    /// The particle editor's Add menu and the user properties' editor.
    @ToolbarContentBuilder private var authoringItems: some ToolbarContent {
        if let particles = services.particles {
            ToolbarItem {
                ParticleAddMenu(services: particles)
            }
        }
        if services.projectJSON != nil {
            ToolbarItem {
                Button { authoring.isEditingProperties = true } label: {
                    Label(L("User Properties"), systemImage: "slider.horizontal.3")
                }
                .help(L("Add, edit and arrange the wallpaper’s user properties"))
            }
        }
    }

    /// The timeline and the inspector.
    @ToolbarContentBuilder private var panelItems: some ToolbarContent {
        if let timeline = services.timeline {
            ToolbarItem {
                TimelineToolbarButton(timeline: timeline)
            }
        }
        ToolbarItem {
            Button { withAnimation { isInspectorPresented.toggle() } } label: {
                Label(L("Inspector"), systemImage: "sidebar.right")
            }
            .help(L("Show or hide the inspector"))
        }
    }

    @ViewBuilder private var noticeBanner: some View {
        if let notice {
            Label(notice.text, systemImage: notice.isError ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .editorGlass(in: Capsule())
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(notice.id)
        }
    }

    private func show(_ notice: Notice) {
        withAnimation { self.notice = notice }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if self.notice == notice { withAnimation { self.notice = nil } }
        }
    }
}

/// Names the copy before it is saved.
private struct SaveAsLocalSheet: View {
    let suggestedTitle: String
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Save as Local Wallpaper")).font(.headline)
            Text(L("A copy of the wallpaper with your edits is added to the library. The original stays as it is."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(L("Name"), text: $title)
                .textFieldStyle(.roundedBorder)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button(L("Cancel"), role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("Save"), action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { title = suggestedTitle }
    }

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func commit() {
        guard !trimmed.isEmpty else { return }
        let title = trimmed
        dismiss()
        save(title)
    }
}

extension View {
    /// Liquid Glass on macOS 26, a material capsule before it.
    @ViewBuilder func editorGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }
}

/// The drag bar between the canvas and the script editor.
private struct ScriptDockDivider: View {
    @Binding var height: Double
    @State private var dragStartHeight: Double?

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start: Double = dragStartHeight ?? height
                    dragStartHeight = start
                    let proposed: Double = start - Double(drag.translation.height)
                    height = min(max(proposed, 240), 640)
                }
                .onEnded { _ in dragStartHeight = nil })
    }
}

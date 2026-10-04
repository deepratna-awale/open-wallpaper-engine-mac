import MetalKit
import SwiftUI

/// An isolated session's private instance (`IsolatedSceneEditSession`), drawn in a view of the
/// scene's aspect: its own registry and key, the isolated store's values, silent (a preview
/// screen, `SceneWallpaperInstance.isPreviewOnly`) and taking no loading snapshots, so nothing of
/// it reaches the desktop.
struct IsolatedSceneView: NSViewRepresentable {
    let session: IsolatedSceneEditSession
    static let screenID = SceneWallpaperInstance.previewScreenIDs.first!

    func makeCoordinator() -> SceneWallpaperPresenter { SceneWallpaperPresenter() }

    func makeNSView(context: Context) -> MTKView {
        let view = SceneRenderLoop.makeView()
        let environment = SceneWallpaperEnvironment(wallpapers: AppDelegate.shared.wallpaperViewModel,
                                                    settings: AppDelegate.shared.globalSettingsViewModel,
                                                    scriptServices: AppDelegate.shared.sceneScriptServices,
                                                    loadingSnapshots: nil)
        let key = session.instanceKey
        let wallpaper = session.wallpaper
        let lease = SceneWallpaperPresenter.Lease(session.instances, key: key) {
            SceneWallpaperInstance(wallpaper: wallpaper, environment: environment, screenID: Self.screenID,
                                   properties: key.properties)
        }
        context.coordinator.show(lease, in: view, screenID: Self.screenID)
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        context.coordinator.instance?.update()
    }

    static func dismantleNSView(_ view: MTKView, coordinator: SceneWallpaperPresenter) {
        coordinator.stop()
    }
}

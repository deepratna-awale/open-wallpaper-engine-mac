import ImageIO
import MetalKit

/// WE's media system textures (`SceneSystemTexture`): `$mediaThumbnail`, the now-playing artwork,
/// and `$mediaPreviousThumbnail`, the artwork it replaced. Fed by the process's media session; each
/// image is decoded and uploaded on the render thread the first time it is asked for after it
/// changed. Without artwork a texture is nil, and the layer shows its own image.
///
/// A renderer makes one only while its content binds a media texture, so a wallpaper without one
/// never starts the media session.
final class SceneMediaTextures {
    private typealias Artwork = (key: Int, png: Data)

    private let source: MediaSessionSource
    private var subscription: Int?
    /// Owns `current` and `previous`: the source reports on its own queue, the renderer reads on
    /// its thread.
    private let lock = NSLock()
    private var current: Artwork?
    private var previous: Artwork?
    /// Render thread only: the uploaded image of each texture and the artwork it is of.
    private var uploaded: [SceneSystemTexture: (key: Int, texture: MTLTexture?)] = [:]

    init(source: MediaSessionSource) {
        self.source = source
        subscription = source.subscribe { [weak self] state in self?.receive(state) }
    }

    deinit {
        if let subscription { source.unsubscribe(subscription) }
    }

    /// Takes a state from the source (any thread). A track without artwork clears the thumbnail;
    /// new artwork moves the old one to the previous thumbnail.
    func receive(_ state: MediaSessionState) {
        let artwork: Artwork? = state.thumbnail.artwork.flatMap { key in state.thumbnail.png.map { (key, $0) } }
        lock.withLock {
            guard artwork?.key != current?.key else { return }
            if let current { previous = current }
            current = artwork
        }
    }

    /// The texture's image now, uploaded with `loader`; nil without artwork (or when it can't be
    /// decoded, logged once per image).
    func texture(_ kind: SceneSystemTexture, loader: MTKTextureLoader, device: MTLDevice) -> MTLTexture? {
        let artwork: Artwork? = lock.withLock {
            switch kind {
            case .mediaThumbnail: return current
            case .mediaPreviousThumbnail: return previous
            }
        }
        guard let artwork else {
            uploaded[kind] = nil
            return nil
        }
        if let cached = uploaded[kind], cached.key == artwork.key { return cached.texture }
        let texture = Self.upload(artwork.png, loader: loader, device: device)
        uploaded[kind] = (artwork.key, texture)
        return texture
    }

    private static func upload(_ png: Data, loader: MTKTextureLoader, device: MTLDevice) -> MTLTexture? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            OWELog.error(.scene, "The now-playing artwork (\(png.count) bytes) can't be decoded; media thumbnails show their layers' images")
            return nil
        }
        do {
            return try SceneTextureUpload.texture(from: image, loader: loader, device: device)
        } catch {
            OWELog.error(.scene, "The now-playing artwork (\(image.width)×\(image.height)) can't be uploaded: \(error)")
            return nil
        }
    }
}

import AVFoundation
import CoreMedia
import ImageIO
import UniformTypeIdentifiers

/// What pairs a HEIC still and a QuickTime movie into one Live Photo: the same content identifier
/// in the still's Apple maker note (key "17") and in the movie's metadata
/// (`com.apple.quicktime.content.identifier`), and a timed metadata track in the movie marking
/// the still's moment (`com.apple.quicktime.still-image-time`).
enum LivePhotoMetadata {
    static let makerNoteIdentifierKey = "17"
    static let contentIdentifierKey = "com.apple.quicktime.content.identifier"
    static let stillImageTimeKey = "com.apple.quicktime.still-image-time"
    static let stillImageTimeIdentifier = "mdta/" + stillImageTimeKey
    static let stillQuality = 0.95

    enum Failure: Error { case heicDestination, heicWrite, metadataFormat }

    // MARK: Writing

    /// Writes `image` as a HEIC carrying `identifier` in its maker note.
    static func writeStill(_ image: CGImage, to url: URL, identifier: String) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
            throw Failure.heicDestination
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyMakerAppleDictionary: [makerNoteIdentifierKey: identifier],
            kCGImageDestinationLossyCompressionQuality: stillQuality,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.heicWrite }
    }

    /// The movie-level item naming the Live Photo.
    static func contentIdentifierItem(_ identifier: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .quickTimeMetadata
        item.key = contentIdentifierKey as NSString
        item.value = identifier as NSString
        item.dataType = kCMMetadataBaseDataType_UTF8 as String
        return item
    }

    /// The still-image-time track's input, added to `writer` before it starts.
    static func addStillImageTimeInput(to writer: AVAssetWriter) throws -> AVAssetWriterInputMetadataAdaptor {
        let specification: [String: Any] = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: stillImageTimeIdentifier,
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_SInt8 as String,
        ]
        var format: CMFormatDescription?
        let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: [specification] as CFArray, formatDescriptionOut: &format)
        guard status == noErr, let format else { throw Failure.metadataFormat }
        let input = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: format)
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw Failure.metadataFormat }
        writer.add(input)
        return AVAssetWriterInputMetadataAdaptor(assetWriterInput: input)
    }

    /// The group marking the still at `time`, one frame long.
    static func stillImageTimeGroup(at time: CMTime, frameRate: Int) -> AVTimedMetadataGroup {
        let item = AVMutableMetadataItem()
        item.keySpace = .quickTimeMetadata
        item.key = stillImageTimeKey as NSString
        item.value = 0 as NSNumber
        item.dataType = kCMMetadataBaseDataType_SInt8 as String
        return AVTimedMetadataGroup(items: [item],
                                    timeRange: CMTimeRange(start: time, duration: CMTime(value: 1, timescale: CMTimeScale(frameRate))))
    }

    // MARK: Reading

    /// The identifier in a still's maker note.
    static func stillIdentifier(at url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let maker = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any] else { return nil }
        return maker[makerNoteIdentifierKey] as? String
    }

    /// The identifier in a movie's metadata.
    static func movieIdentifier(at url: URL) async throws -> String? {
        let asset = AVURLAsset(url: url)
        let items = try await asset.loadMetadata(for: .quickTimeMetadata)
        for item in items where item.identifier?.rawValue == "mdta/" + contentIdentifierKey {
            return try await item.load(.stringValue)
        }
        return nil
    }

    /// The time the movie's still-image-time track marks.
    static func movieStillImageTime(at url: URL) async throws -> CMTime? {
        let asset = AVURLAsset(url: url)
        for track in try await asset.loadTracks(withMediaType: .metadata) {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output)
            let adaptor = AVAssetReaderOutputMetadataAdaptor(assetReaderTrackOutput: output)
            guard reader.startReading() else { continue }
            while let group = adaptor.nextTimedMetadataGroup() {
                if group.items.contains(where: { $0.identifier?.rawValue == stillImageTimeIdentifier }) {
                    reader.cancelReading()
                    return group.timeRange.start
                }
            }
        }
        return nil
    }
}

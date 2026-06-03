import AVFoundation
import CoreMedia
import Flutter
import Foundation
import ImageIO
import MobileCoreServices
import Photos
import UniformTypeIdentifiers

final class PrismLivePhotoSaver: NSObject {
  private static var retainedChannel: FlutterMethodChannel?
  private static var retainedSaver: PrismLivePhotoSaver?

  private let queue = DispatchQueue(label: "com.nightvibes.prism.live-photo", qos: .userInitiated)

  static func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "prism/live_photo", binaryMessenger: binaryMessenger)
    let saver = PrismLivePhotoSaver()
    retainedChannel = channel
    retainedSaver = saver
    channel.setMethodCallHandler { call, result in
      guard call.method == "save" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let videoUrl = args["videoUrl"] as? String else {
        result(["success": false, "message": "Missing Live Photo video URL"])
        return
      }
      let stillUrl = args["stillUrl"] as? String
      saver.save(videoUrl: videoUrl, stillUrl: stillUrl) { saveResult in
        result(saveResult)
      }
    }
  }

  private func save(videoUrl: String, stillUrl: String?, completion: @escaping ([String: Any]) -> Void) {
    queue.async {
      do {
        try self.ensurePhotoPermission()
        let assetId = UUID().uuidString
        let workDir = try self.makeWorkDirectory()
        let rawVideo = try self.fetchFile(urlString: videoUrl, fallbackExtension: "mp4", directory: workDir)
        let fetchedStill: URL?
        if let stillUrl = stillUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !stillUrl.isEmpty {
          fetchedStill = try? self.fetchFile(urlString: stillUrl, fallbackExtension: "jpg", directory: workDir)
        } else {
          fetchedStill = nil
        }
        let rawStill = try self.compatibleStillImage(fetchedStill, video: rawVideo, directory: workDir)
        let pairedPhoto = workDir.appendingPathComponent("live-photo.jpg")
        let pairedVideo = workDir.appendingPathComponent("live-video.mov")
        try self.writePairedPhoto(input: rawStill, output: pairedPhoto, assetId: assetId)
        try self.writePairedVideo(input: rawVideo, output: pairedVideo, assetId: assetId)
        try self.savePairedAsset(photo: pairedPhoto, video: pairedVideo)
        try? FileManager.default.removeItem(at: workDir)
        DispatchQueue.main.async { completion(["success": true]) }
      } catch {
        DispatchQueue.main.async { completion(["success": false, "message": error.localizedDescription]) }
      }
    }
  }

  private func makeWorkDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("prism-live-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func fetchFile(urlString: String, fallbackExtension: String, directory: URL) throws -> URL {
    guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
      throw LivePhotoError.invalidUrl
    }
    let data = try fetchData(url: url)
    guard !data.isEmpty else { throw LivePhotoError.emptyPayload }
    let ext = url.pathExtension.isEmpty ? fallbackExtension : url.pathExtension
    let destination = directory.appendingPathComponent("source-\(UUID().uuidString).\(ext)")
    try data.write(to: destination, options: .atomic)
    return destination
  }

  private func fetchData(url: URL) throws -> Data {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 45
    config.timeoutIntervalForResource = 90
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }

    var request = URLRequest(url: url)
    request.setValue(
      "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
      forHTTPHeaderField: "User-Agent"
    )
    request.setValue("*/*", forHTTPHeaderField: "Accept")

    let semaphore = DispatchSemaphore(value: 0)
    var fetchedData: Data?
    var fetchError: Error?
    var statusCode: Int?

    let task = session.dataTask(with: request) { data, response, error in
      fetchedData = data
      fetchError = error
      statusCode = (response as? HTTPURLResponse)?.statusCode
      semaphore.signal()
    }
    task.resume()
    semaphore.wait()

    if fetchError != nil {
      throw LivePhotoError.downloadFailed
    }
    if let statusCode = statusCode, !(200...299).contains(statusCode) {
      throw LivePhotoError.httpStatus(code: statusCode)
    }
    guard let fetchedData, !fetchedData.isEmpty else { throw LivePhotoError.emptyPayload }
    return fetchedData
  }

  private func makeStillFrame(from video: URL, directory: URL) throws -> URL {
    let asset = AVURLAsset(url: video)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)
    let durationSeconds: Double
    if asset.duration.isValid && asset.duration.seconds.isFinite {
      durationSeconds = max(asset.duration.seconds, 0)
    } else {
      durationSeconds = 0
    }
    let frameSeconds = durationSeconds > 0.02 ? min(0.15, durationSeconds * 0.5) : 0
    let frameTime = CMTime(seconds: frameSeconds, preferredTimescale: 600)
    let image = try generator.copyCGImage(at: frameTime, actualTime: nil)
    let output = directory.appendingPathComponent("generated-live-still.jpg")
    let type: CFString
    if #available(iOS 14.0, *) {
      type = UTType.jpeg.identifier as CFString
    } else {
      type = kUTTypeJPEG
    }
    guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type, 1, nil) else {
      throw LivePhotoError.imageWriteFailed
    }
    let options = [kCGImageDestinationLossyCompressionQuality as String: 0.98] as CFDictionary
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else { throw LivePhotoError.imageWriteFailed }
    return output
  }

  private func compatibleStillImage(_ still: URL?, video: URL, directory: URL) throws -> URL {
    if let still, isStillImageCompatible(still, video: video) {
      return still
    }
    return try makeStillFrame(from: video, directory: directory)
  }

  private func isStillImageCompatible(_ still: URL, video: URL) -> Bool {
    guard let stillSize = imagePixelSize(still),
          let videoSize = videoDisplaySize(video) else {
      return false
    }
    let stillWidth = max(stillSize.width, 1)
    let stillHeight = max(stillSize.height, 1)
    let videoWidth = max(videoSize.width, 1)
    let videoHeight = max(videoSize.height, 1)
    let stillRatio = stillWidth / stillHeight
    let videoRatio = videoWidth / videoHeight
    let ratioDelta = abs(stillRatio - videoRatio) / max(videoRatio, 0.01)
    let minStillSide = min(stillWidth, stillHeight)
    let minVideoSide = min(videoWidth, videoHeight)
    let minimumSide = min(max(minVideoSide * 0.72, CGFloat(960)), minVideoSide)
    return minStillSide >= minimumSide && ratioDelta <= 0.08
  }

  private func imagePixelSize(_ url: URL) -> CGSize? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
      return nil
    }
    let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue ?? 0
    let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue ?? 0
    guard width > 0 && height > 0 else { return nil }
    return CGSize(width: width, height: height)
  }

  private func videoDisplaySize(_ url: URL) -> CGSize? {
    let asset = AVURLAsset(url: url)
    guard let track = asset.tracks(withMediaType: .video).first else { return nil }
    let transformed = track.naturalSize.applying(track.preferredTransform)
    let width = abs(transformed.width)
    let height = abs(transformed.height)
    guard width > 0 && height > 0 else { return nil }
    return CGSize(width: width, height: height)
  }

  private func writePairedPhoto(input: URL, output: URL, assetId: String) throws {
    guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else { throw LivePhotoError.invalidImage }
    let type: CFString
    if #available(iOS 14.0, *) {
      type = UTType.jpeg.identifier as CFString
    } else {
      type = kUTTypeJPEG
    }
    guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type, 1, nil) else {
      throw LivePhotoError.invalidImage
    }
    var metadata = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]) ?? [:]
    var makerApple = (metadata[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any]) ?? [:]
    makerApple["17"] = assetId
    metadata[kCGImagePropertyMakerAppleDictionary as String] = makerApple
    CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw LivePhotoError.imageWriteFailed }
  }

  private func writePairedVideo(input: URL, output: URL, assetId: String) throws {
    let asset = AVURLAsset(url: input)
    try? FileManager.default.removeItem(at: output)

    let reader = try AVAssetReader(asset: asset)
    let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
    writer.shouldOptimizeForNetworkUse = false
    writer.metadata = asset.metadata + [contentIdentifierMetadataItem(assetId: assetId)]

    var trackPairs: [(AVAssetWriterInput, AVAssetReaderOutput)] = []
    var hasVideoTrack = false
    for track in asset.tracks where track.mediaType == .video || track.mediaType == .audio {
      let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
      readerOutput.alwaysCopiesSampleData = false
      guard reader.canAdd(readerOutput) else { continue }

      let writerInput = AVAssetWriterInput(mediaType: track.mediaType, outputSettings: nil)
      writerInput.expectsMediaDataInRealTime = false
      writerInput.transform = track.preferredTransform
      guard writer.canAdd(writerInput) else { continue }

      reader.add(readerOutput)
      writer.add(writerInput)
      if track.mediaType == .video {
        hasVideoTrack = true
      }
      trackPairs.append((writerInput, readerOutput))
    }

    guard hasVideoTrack else {
      throw LivePhotoError.videoTrackMissing
    }

    let metadataInput = try stillImageTimeMetadataInput()
    let metadataAdaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: metadataInput)
    metadataInput.expectsMediaDataInRealTime = false
    guard writer.canAdd(metadataInput) else { throw LivePhotoError.metadataWriteFailed }
    writer.add(metadataInput)

    guard writer.startWriting() else { throw writer.error ?? LivePhotoError.videoExportFailed }
    guard reader.startReading() else {
      writer.cancelWriting()
      throw reader.error ?? LivePhotoError.videoExportFailed
    }
    writer.startSession(atSourceTime: .zero)

    try appendStillImageTimeMetadata(adaptor: metadataAdaptor, input: metadataInput, duration: asset.duration)

    let copyQueue = DispatchQueue(label: "com.nightvibes.prism.live-photo.copy")
    let group = DispatchGroup()

    for (writerInput, readerOutput) in trackPairs {
      group.enter()
      writerInput.requestMediaDataWhenReady(on: copyQueue) {
        while writerInput.isReadyForMoreMediaData {
          if let sampleBuffer = readerOutput.copyNextSampleBuffer() {
            if !writerInput.append(sampleBuffer) {
              reader.cancelReading()
              writerInput.markAsFinished()
              group.leave()
              return
            }
          } else {
            writerInput.markAsFinished()
            group.leave()
            return
          }
        }
      }
    }

    group.wait()

    if reader.status == .failed || reader.status == .cancelled {
      writer.cancelWriting()
      throw reader.error ?? LivePhotoError.videoExportFailed
    }

    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting { semaphore.signal() }
    semaphore.wait()

    if writer.status != .completed {
      throw writer.error ?? LivePhotoError.videoExportFailed
    }
  }

  private func contentIdentifierMetadataItem(assetId: String) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    if #available(iOS 10.0, *) {
      item.identifier = .quickTimeMetadataContentIdentifier
    }
    item.keySpace = .quickTimeMetadata
    item.key = "com.apple.quicktime.content.identifier" as NSString
    item.value = assetId as NSString
    item.dataType = kCMMetadataBaseDataType_UTF8 as String
    return item
  }

  private func stillImageTimeMetadataInput() throws -> AVAssetWriterInput {
    let spec: [String: Any] = [
      kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
      kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_SInt8,
    ]
    var description: CMFormatDescription?
    let status = CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
      allocator: kCFAllocatorDefault,
      metadataType: kCMMetadataFormatType_Boxed,
      metadataSpecifications: [spec] as CFArray,
      formatDescriptionOut: &description
    )
    guard status == noErr, let description else { throw LivePhotoError.metadataWriteFailed }
    return AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: description)
  }

  private func appendStillImageTimeMetadata(
    adaptor: AVAssetWriterInputMetadataAdaptor,
    input: AVAssetWriterInput,
    duration sourceDuration: CMTime
  ) throws {
    let stillTime = AVMutableMetadataItem()
    stillTime.keySpace = .quickTimeMetadata
    stillTime.key = "com.apple.quicktime.still-image-time" as NSString
    stillTime.value = NSNumber(value: Int8(0))
    stillTime.dataType = kCMMetadataBaseDataType_SInt8 as String

    let duration = sourceDuration.isValid && sourceDuration.seconds > 0
      ? sourceDuration
      : CMTime(value: 1, timescale: 100)
    let group = AVTimedMetadataGroup(
      items: [stillTime],
      timeRange: CMTimeRange(start: .zero, duration: duration)
    )
    guard adaptor.append(group) else { throw LivePhotoError.metadataWriteFailed }
    input.markAsFinished()
  }

  private func savePairedAsset(photo: URL, video: URL) throws {
    let semaphore = DispatchSemaphore(value: 0)
    var saveError: Error?
    PHPhotoLibrary.shared().performChanges(
      {
        let request = PHAssetCreationRequest.forAsset()
        let photoOptions = PHAssetResourceCreationOptions()
        let videoOptions = PHAssetResourceCreationOptions()
        if #available(iOS 14.0, *) {
          photoOptions.uniformTypeIdentifier = UTType.jpeg.identifier
          videoOptions.uniformTypeIdentifier = UTType.quickTimeMovie.identifier
        } else {
          photoOptions.uniformTypeIdentifier = kUTTypeJPEG as String
          videoOptions.uniformTypeIdentifier = kUTTypeQuickTimeMovie as String
        }
        request.addResource(with: .photo, fileURL: photo, options: photoOptions)
        request.addResource(with: .pairedVideo, fileURL: video, options: videoOptions)
      },
      completionHandler: { success, error in
        if !success { saveError = error ?? LivePhotoError.photoSaveFailed }
        semaphore.signal()
      }
    )
    semaphore.wait()
    if let saveError { throw saveError }
  }

  private func ensurePhotoPermission() throws {
    if #available(iOS 14, *) {
      let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      switch status {
      case .authorized, .limited:
        return
      case .notDetermined:
        let semaphore = DispatchSemaphore(value: 0)
        var resolved: PHAuthorizationStatus = .notDetermined
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
          resolved = status
          semaphore.signal()
        }
        semaphore.wait()
        if resolved == .authorized || resolved == .limited { return }
        throw LivePhotoError.photoPermissionDenied
      default:
        throw LivePhotoError.photoPermissionDenied
      }
    } else {
      let status = PHPhotoLibrary.authorizationStatus()
      if status == .authorized { return }
      if status == .notDetermined {
        let semaphore = DispatchSemaphore(value: 0)
        var resolved: PHAuthorizationStatus = .notDetermined
        PHPhotoLibrary.requestAuthorization { status in
          resolved = status
          semaphore.signal()
        }
        semaphore.wait()
        if resolved == .authorized { return }
      }
      throw LivePhotoError.photoPermissionDenied
    }
  }
}

private enum LivePhotoError: LocalizedError {
  case invalidUrl
  case emptyPayload
  case downloadFailed
  case httpStatus(code: Int)
  case invalidImage
  case imageWriteFailed
  case videoExportFailed
  case videoTrackMissing
  case metadataWriteFailed
  case photoSaveFailed
  case photoPermissionDenied

  var errorDescription: String? {
    switch self {
    case .invalidUrl:
      return "Invalid Live Photo URL."
    case .emptyPayload:
      return "Downloaded Live Photo asset was empty."
    case .downloadFailed:
      return "Live Photo asset could not be downloaded."
    case .httpStatus(let code):
      return "Live Photo asset download failed with HTTP \(code)."
    case .invalidImage:
      return "Live Photo still image could not be read."
    case .imageWriteFailed:
      return "Live Photo still image could not be prepared."
    case .videoExportFailed:
      return "Live Photo video could not be prepared."
    case .videoTrackMissing:
      return "Live Photo video did not contain a playable video track."
    case .metadataWriteFailed:
      return "Live Photo pairing metadata could not be written."
    case .photoSaveFailed:
      return "Live Photo could not be saved."
    case .photoPermissionDenied:
      return "Photo Library permission was denied."
    }
  }
}

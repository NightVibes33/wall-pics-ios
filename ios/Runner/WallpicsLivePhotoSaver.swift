import AVFoundation
import Flutter
import Foundation
import ImageIO
import MobileCoreServices
import Photos
import UniformTypeIdentifiers

final class WallpicsLivePhotoSaver: NSObject {
  private static var retainedChannel: FlutterMethodChannel?
  private static var retainedSaver: WallpicsLivePhotoSaver?

  private let queue = DispatchQueue(label: "com.nightvibes.wallpics.live-photo", qos: .userInitiated)

  static func register(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "wallpics/live_photo", binaryMessenger: binaryMessenger)
    let saver = WallpicsLivePhotoSaver()
    retainedChannel = channel
    retainedSaver = saver
    channel.setMethodCallHandler { call, result in
      guard call.method == "save" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let videoUrl = args["videoUrl"] as? String,
            let stillUrl = args["stillUrl"] as? String else {
        result(["success": false, "message": "Missing Live Photo URLs"])
        return
      }
      saver.save(videoUrl: videoUrl, stillUrl: stillUrl) { saveResult in
        result(saveResult)
      }
    }
  }

  private func save(videoUrl: String, stillUrl: String, completion: @escaping ([String: Any]) -> Void) {
    queue.async {
      do {
        try self.ensurePhotoPermission()
        let assetId = UUID().uuidString
        let workDir = try self.makeWorkDirectory()
        let rawVideo = try self.fetchFile(urlString: videoUrl, fallbackExtension: "mp4", directory: workDir)
        let rawStill = try self.fetchFile(urlString: stillUrl, fallbackExtension: "jpg", directory: workDir)
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
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("wallpics-live-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func fetchFile(urlString: String, fallbackExtension: String, directory: URL) throws -> URL {
    guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
      throw LivePhotoError.invalidUrl
    }
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    guard !data.isEmpty else { throw LivePhotoError.emptyPayload }
    let ext = url.pathExtension.isEmpty ? fallbackExtension : url.pathExtension
    let destination = directory.appendingPathComponent("source-\(UUID().uuidString).\(ext)")
    try data.write(to: destination, options: .atomic)
    return destination
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
    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
      throw LivePhotoError.videoExportFailed
    }
    try? FileManager.default.removeItem(at: output)
    export.outputURL = output
    export.outputFileType = .mov

    let identifier = AVMutableMetadataItem()
    identifier.keySpace = .quickTimeMetadata
    identifier.key = "com.apple.quicktime.content.identifier" as NSString
    identifier.value = assetId as NSString
    identifier.dataType = "com.apple.metadata.datatype.UTF-8"

    let stillTime = AVMutableMetadataItem()
    stillTime.keySpace = .quickTimeMetadata
    stillTime.key = "com.apple.quicktime.still-image-time" as NSString
    stillTime.value = NSNumber(value: 0)
    stillTime.dataType = "com.apple.metadata.datatype.int8"

    export.metadata = asset.metadata + [identifier, stillTime]

    let semaphore = DispatchSemaphore(value: 0)
    export.exportAsynchronously { semaphore.signal() }
    semaphore.wait()

    if export.status != .completed {
      throw export.error ?? LivePhotoError.videoExportFailed
    }
  }

  private func savePairedAsset(photo: URL, video: URL) throws {
    let semaphore = DispatchSemaphore(value: 0)
    var saveError: Error?
    PHPhotoLibrary.shared().performChanges(
      {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, fileURL: photo, options: nil)
        request.addResource(with: .pairedVideo, fileURL: video, options: nil)
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
  case invalidImage
  case imageWriteFailed
  case videoExportFailed
  case photoSaveFailed
  case photoPermissionDenied

  var errorDescription: String? {
    switch self {
    case .invalidUrl:
      return "Invalid Live Photo URL."
    case .emptyPayload:
      return "Downloaded Live Photo asset was empty."
    case .invalidImage:
      return "Live Photo still image could not be read."
    case .imageWriteFailed:
      return "Live Photo still image could not be prepared."
    case .videoExportFailed:
      return "Live Photo video could not be prepared."
    case .photoSaveFailed:
      return "Live Photo could not be saved."
    case .photoPermissionDenied:
      return "Photo Library permission was denied."
    }
  }
}

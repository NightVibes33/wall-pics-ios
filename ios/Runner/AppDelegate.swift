import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var prismChannelsRegistered = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    appendNativeLaunchLog("didFinishLaunching start bundleVersion=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "unknown")")
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    appendNativeLaunchLog("didFinishLaunching complete launched=\(launched)")
    return launched
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    appendNativeLaunchLog("implicit Flutter engine initialized")
    appendNativeLaunchLog("generated plugins registration starting")
    registerGeneratedPluginsIfNeeded(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerPrismChannels(binaryMessenger: messenger)
  }

  private func registerGeneratedPluginsIfNeeded(with registry: FlutterPluginRegistry) {
    if registry.hasPlugin("AppLinksIosPlugin") {
      appendNativeLaunchLog("generated plugins already registered")
      return
    }
    GeneratedPluginRegistrant.register(with: registry)
    appendNativeLaunchLog("generated plugins registered on implicit engine")
  }

  private func registerPrismChannels(binaryMessenger: FlutterBinaryMessenger) {
    if prismChannelsRegistered {
      appendNativeLaunchLog("Prism channels already registered")
      return
    }
    prismChannelsRegistered = true

    PrismMediaHostApiSetup.setUp(
      binaryMessenger: binaryMessenger,
      api: PrismMediaHostApiImpl()
    )
    PrismLivePhotoSaver.register(binaryMessenger: binaryMessenger)
    appendNativeLaunchLog("Prism channels registered")
  }

  private func appendNativeLaunchLog(_ message: String) {
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
      return
    }

    let fileURL = documents.appendingPathComponent("Prism-Native-Launch.log")
    let timestamp = ISO8601DateFormatter().string(from: Date())
    guard let data = "\(timestamp) \(message)\n".data(using: .utf8) else {
      return
    }

    if FileManager.default.fileExists(atPath: fileURL.path), let handle = try? FileHandle(forWritingTo: fileURL) {
      handle.seekToEndOfFile()
      handle.write(data)
      try? handle.close()
      return
    }

    try? data.write(to: fileURL, options: .atomic)
  }
}

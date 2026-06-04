import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var prismChannelsRegistered = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    registerGeneratedPluginsIfNeeded(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      registerPrismChannels(binaryMessenger: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    registerGeneratedPluginsIfNeeded(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerPrismChannels(binaryMessenger: messenger)
  }

  private func registerGeneratedPluginsIfNeeded(with registry: FlutterPluginRegistry) {
    if registry.hasPlugin("AppLinksIosPlugin") {
      return
    }
    GeneratedPluginRegistrant.register(with: registry)
  }

  private func registerPrismChannels(binaryMessenger: FlutterBinaryMessenger) {
    if prismChannelsRegistered {
      return
    }
    prismChannelsRegistered = true

    PrismMediaHostApiSetup.setUp(
      binaryMessenger: binaryMessenger,
      api: PrismMediaHostApiImpl()
    )
    PrismLivePhotoSaver.register(binaryMessenger: binaryMessenger)
  }
}

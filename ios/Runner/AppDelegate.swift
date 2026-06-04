import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var prismChannelsRegistered = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = ensureFlutterRootViewController()
    controller.view.backgroundColor = .black

    registerGeneratedPluginsIfNeeded(with: self)
    registerPrismChannels(binaryMessenger: controller.binaryMessenger)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    registerGeneratedPluginsIfNeeded(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerPrismChannels(binaryMessenger: messenger)
  }


  private func ensureFlutterRootViewController() -> FlutterViewController {
    if let existingController = window?.rootViewController as? FlutterViewController {
      window?.backgroundColor = .black
      window?.makeKeyAndVisible()
      return existingController
    }

    let controller = FlutterViewController(project: nil, nibName: nil, bundle: nil)
    let appWindow = window ?? UIWindow(frame: UIScreen.main.bounds)
    appWindow.backgroundColor = .black
    appWindow.rootViewController = controller
    appWindow.makeKeyAndVisible()
    window = appWindow
    return controller
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

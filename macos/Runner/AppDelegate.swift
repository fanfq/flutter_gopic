import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {
  private static let launchAtLoginChannelName = "gopic/launch-at-login"
  private static let launchAgentLabel = "com.fanfq.gopic"
  // Keep the status bar controller alive for the app's lifetime.
  private var statusBarController: StatusBarController?
  private var quitRequestedFromStatusMenu = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Stay alive as a menu-bar app after the window is closed.
    return false
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if quitRequestedFromStatusMenu {
      return .terminateNow
    }
    hideMainWindow()
    return .terminateCancel
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // The main Flutter binary will own a single FlutterEngine/ViewController
    // created from the storyboard. Grab it and wire up the menu-bar controller.
    let controller = mainFlutterViewController
    statusBarController = StatusBarController(flutterViewController: controller)
    registerLaunchAtLoginChannel(flutterViewController: controller)
    controller.view.window?.delegate = self

    // Prevent the app from appearing in the Dock / Cmd+Tab by default; the user
    // can still open the window from the menu-bar item. (Keeps it feeling like
    // a background uploader, like PicGo.)
    // Comment the next line out if you prefer a normal Dock icon.
    NSApp.setActivationPolicy(.accessory)
  }

  /// Bring the main window to the front (called from the menu-bar item).
  func showMainWindow() {
    guard let window = mainFlutterViewController.view.window else { return }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    // Re-show as a regular app while focused.
    NSApp.setActivationPolicy(.regular)
    window.center()
  }

  func hideMainWindow() {
    mainFlutterViewController.view.window?.orderOut(nil)
    NSApp.setActivationPolicy(.accessory)
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    hideMainWindow()
    return false
  }

  @objc func menuOpenClicked() {
    showMainWindow()
  }

  @objc func menuQuitClicked() {
    quitRequestedFromStatusMenu = true
    NSApp.terminate(nil)
  }

  private func registerLaunchAtLoginChannel(flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: Self.launchAtLoginChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "unavailable", message: "App delegate is unavailable.", details: nil))
        return
      }
      switch call.method {
      case "isEnabled":
        result(self.isLaunchAtLoginEnabled())
      case "setEnabled":
        guard let enabled = call.arguments as? Bool else {
          result(FlutterError(code: "invalid-arguments", message: "Expected a boolean enabled value.", details: nil))
          return
        }
        do {
          try self.setLaunchAtLoginEnabled(enabled)
          result(nil)
        } catch {
          result(FlutterError(code: "launch-agent-error", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private var launchAgentURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
      .appendingPathComponent("\(Self.launchAgentLabel).plist", isDirectory: false)
  }

  private var launchAgentArguments: [String] {
    ["/usr/bin/open", Bundle.main.bundleURL.path]
  }

  private func isLaunchAtLoginEnabled() -> Bool {
    guard
      let data = try? Data(contentsOf: launchAgentURL),
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
      let dictionary = plist as? [String: Any],
      dictionary["Label"] as? String == Self.launchAgentLabel,
      let arguments = dictionary["ProgramArguments"] as? [String]
    else {
      return false
    }
    return arguments == launchAgentArguments && (dictionary["RunAtLoad"] as? Bool) == true
  }

  private func setLaunchAtLoginEnabled(_ enabled: Bool) throws {
    let fileManager = FileManager.default
    if !enabled {
      if fileManager.fileExists(atPath: launchAgentURL.path) {
        try fileManager.removeItem(at: launchAgentURL)
      }
      return
    }

    try fileManager.createDirectory(
      at: launchAgentURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let plist: [String: Any] = [
      "Label": Self.launchAgentLabel,
      "ProgramArguments": launchAgentArguments,
      "RunAtLoad": true,
    ]
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist,
      format: .xml,
      options: 0
    )
    try data.write(to: launchAgentURL, options: .atomic)
  }
}

extension AppDelegate {
  /// Resolve the main FlutterViewController whether created from storyboard
  /// or directly via MainFlutterWindow.
  var mainFlutterViewController: FlutterViewController {
    if let vc = NSApplication.shared.windows
        .compactMap({ $0.contentViewController as? FlutterViewController })
        .first {
      return vc
    }
    // Fallback: create a fresh one (used if the window wasn't instantiated).
    return FlutterViewController()
  }
}

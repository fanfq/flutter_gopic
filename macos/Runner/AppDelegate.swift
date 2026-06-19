import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate, NSWindowDelegate {
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

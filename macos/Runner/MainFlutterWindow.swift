import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let initialContentSize = NSSize(width: 1180, height: 760)

    self.backgroundColor = NSColor.windowBackgroundColor
    self.minSize = NSSize(width: 1040, height: 700)
    flutterViewController.view.wantsLayer = true
    flutterViewController.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

    self.contentViewController = flutterViewController
    self.setContentSize(initialContentSize)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

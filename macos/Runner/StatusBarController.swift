import Cocoa
import FlutterMacOS

/// Manages the menu-bar (NSStatusItem) presence for GoPic.
///
/// The status item's button hosts a transparent view that is registered as an
/// NSDraggingDestination accepting image files. Drops are forwarded to the
/// Flutter side through the `gopic/tray` method channel. Flutter owns the
/// actual upload logic and will, on success, copy the resulting URL to the
/// clipboard and update this item's icon via `setIcon`.
class StatusBarController: NSObject {
  private let statusItem: NSStatusItem
  private let channel: FlutterMethodChannel
  private let menu = NSMenu()
  private var latestUploadFileName: String?
  private var latestUploadURL: String?
  private lazy var idleStatusIcon: NSImage? = loadIdleStatusIcon()
  private weak var flutterViewController: FlutterViewController?
  private var dropPanel: TrayDropPanel?

  init(flutterViewController: FlutterViewController) {
    self.flutterViewController = flutterViewController
    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    self.channel = FlutterMethodChannel(
      name: "gopic/tray",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    super.init()

    configureButton()
    configureDropPanel()
    configureMenu()
    registerDragHandler()
    registerChannel()
    setIcon("cloud")
  }

  // MARK: - UI

  private func configureButton() {
    guard let button = statusItem.button else { return }
    button.imagePosition = .imageOnly
    button.target = self
    button.action = #selector(statusItemClicked(_:))
    button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    // Icon is assigned by setIcon below.
  }

  private func configureMenu() {
    rebuildMenu()
  }

  private func configureDropPanel() {
    dropPanel = TrayDropPanel()
    dropPanel?.onDrop = { [weak self] paths in
      self?.handleDrop(paths: paths)
    }
    dropPanel?.onDragStateChanged = { [weak self] isActive in
      self?.handlePanelDragStateChanged(isActive)
    }
  }

  private func rebuildMenu() {
    menu.removeAllItems()

    let recentTitle = latestUploadFileName == nil ? "最近上传：暂无上传记录" : "最近上传：\(latestUploadFileName!)"
    let recentItem = NSMenuItem(
      title: recentTitle,
      action: latestUploadURL == nil ? nil : #selector(copyLatestUploadURL(_:)),
      keyEquivalent: ""
    )
    recentItem.target = self
    recentItem.isEnabled = latestUploadURL != nil
    if let latestUploadURL {
      recentItem.toolTip = latestUploadURL
      recentItem.representedObject = latestUploadURL
    }
    menu.addItem(recentItem)
    menu.addItem(NSMenuItem.separator())

    let openItem = NSMenuItem(title: "打开 GoPic", action: #selector(AppDelegate.menuOpenClicked), keyEquivalent: "o")
    openItem.target = NSApp.delegate as? AppDelegate
    menu.addItem(openItem)

    menu.addItem(NSMenuItem.separator())

    let quitItem = NSMenuItem(title: "退出 GoPic", action: #selector(AppDelegate.menuQuitClicked), keyEquivalent: "q")
    quitItem.target = NSApp.delegate as? AppDelegate
    menu.addItem(quitItem)
  }

  @objc private func copyLatestUploadURL(_ sender: NSMenuItem) {
    guard let url = sender.representedObject as? String else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url, forType: .string)
    setIcon("done", tooltip: "最近上传链接已复制")
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
      self?.setIcon("cloud")
    }
  }

  @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
    handleStatusItemEvent(NSApp.currentEvent, sender: sender)
  }

  private func handleStatusItemEvent(_ event: NSEvent?, sender: NSStatusBarButton) {
    rebuildMenu()
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
  }

  // MARK: - Drag and drop

  /// Overlay view that accepts image file drops on the status-item button.
  private func registerDragHandler() {
    guard let button = statusItem.button else { return }
    let dropView = TrayDropView(frame: button.bounds)
    dropView.autoresizingMask = [.width, .height]
    dropView.onDrop = { [weak self] paths in
      self?.handleDrop(paths: paths)
    }
    dropView.onDragStateChanged = { [weak self] isActive in
      self?.handleDragStateChanged(isActive)
    }
    dropView.onClick = { [weak self, weak button] event in
      guard let button else { return }
      self?.handleStatusItemEvent(event, sender: button)
    }
    button.addSubview(dropView)
    // The button's image still shows; the overlay is transparent and just
    // captures drags.
  }

  private func handleDrop(paths: [String]) {
    // Filter to image-ish types server-side; UI handles failures.
    let imageExt = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg",
                    "tif", "tiff", "ico", "avif", "heic"]
    let filtered = paths.filter { p in
      let ext = (p as NSString).pathExtension.lowercased()
      return !ext.isEmpty && imageExt.contains(ext)
    }
    guard !filtered.isEmpty else { return }

    dropPanel?.hideNow()
    setIcon("arrow.up")
    channel.invokeMethod("onFilesDropped", arguments: filtered.joined(separator: "\n"))
  }

  private func handleDragStateChanged(_ isActive: Bool) {
    if isActive {
      setIcon("arrow.up", tooltip: "松开以上传到 GoPic")
      if let button = statusItem.button {
        dropPanel?.show(near: button)
      }
    } else {
      setIcon("cloud")
      dropPanel?.scheduleHide()
    }
  }

  private func handlePanelDragStateChanged(_ isActive: Bool) {
    if isActive {
      setIcon("arrow.up", tooltip: "松开以上传到 GoPic")
      dropPanel?.cancelScheduledHide()
    } else {
      dropPanel?.scheduleHide()
    }
  }

  // MARK: - Channel (Dart -> Swift)

  private func registerChannel() {
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setIcon":
        if let name = call.arguments as? String {
          self?.setIcon(name)
        }
        result(nil)
      case "setIconAndTooltip":
        if let args = call.arguments as? [String: String] {
          self?.setIcon(args["icon"] ?? "cloud", tooltip: args["tooltip"])
        }
        result(nil)
      case "setLatestUpload":
        if let args = call.arguments as? [String: String],
           let url = args["url"] {
          self?.latestUploadFileName = args["fileName"]?.isEmpty == false ? args["fileName"] : url
          self?.latestUploadURL = url
          self?.rebuildMenu()
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func setIcon(_ name: String, tooltip: String? = nil) {
    DispatchQueue.main.async { [weak self] in
      guard let self, let button = self.statusItem.button else { return }
      button.image = self.statusIcon(for: name)
      button.toolTip = tooltip
    }
  }

  private func statusIcon(for name: String) -> NSImage {
    if name == "cloud", let idleStatusIcon {
      return idleStatusIcon
    }
    return drawTemplateIcon(for: name)
  }

  private func loadIdleStatusIcon() -> NSImage? {
    let resourcePath = "flutter_assets/assets/icon.png"
    let bundles = [Bundle.main] + Bundle.allFrameworks + Bundle.allBundles

    for bundle in bundles {
      guard let url = bundle.resourceURL?.appendingPathComponent(resourcePath),
            FileManager.default.fileExists(atPath: url.path),
            let source = NSImage(contentsOf: url) else {
        continue
      }
      return scaledStatusImage(from: source)
    }

    return nil
  }

  private func scaledStatusImage(from source: NSImage) -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size)
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(
      in: NSRect(origin: .zero, size: size),
      from: NSRect(origin: .zero, size: source.size),
      operation: .sourceOver,
      fraction: 1
    )
    image.unlockFocus()
    image.isTemplate = false
    return image
  }

  /// Draws a simple template image (auto-tinted by the menu bar) so we stay
  /// compatible with the macOS 10.15 deployment target (SF Symbols need 11.0).
  private func drawTemplateIcon(for name: String) -> NSImage {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size)
    image.lockFocus()

    let accent: NSColor
    let path: NSBezierPath
    switch name {
    case "arrow.up":
      // Filled circle with an upward arrow.
      accent = NSColor.controlAccentColor
      let circle = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: 15, height: 15))
      circle.lineWidth = 1.5
      accent.setFill()
      circle.fill()
      // Arrow (white).
      NSColor.white.setStroke()
      let arrow = NSBezierPath()
      arrow.move(to: NSPoint(x: 9, y: 13))
      arrow.line(to: NSPoint(x: 5.5, y: 8))
      arrow.line(to: NSPoint(x: 7, y: 8))
      arrow.line(to: NSPoint(x: 7, y: 5))
      arrow.line(to: NSPoint(x: 11, y: 5))
      arrow.line(to: NSPoint(x: 11, y: 8))
      arrow.line(to: NSPoint(x: 12.5, y: 8))
      arrow.close()
      arrow.lineWidth = 1
      NSColor.white.setFill()
      arrow.fill()

    case "done", "check", "checkmark":
      accent = NSColor.systemGreen
      let circle = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: 15, height: 15))
      accent.setFill()
      circle.fill()
      let check = NSBezierPath()
      check.move(to: NSPoint(x: 5.5, y: 9))
      check.line(to: NSPoint(x: 8, y: 6))
      check.line(to: NSPoint(x: 12.5, y: 11.5))
      check.lineWidth = 1.8
      check.lineCapStyle = .round
      check.lineJoinStyle = .round
      NSColor.white.setStroke()
      check.stroke()

    case "error", "xmark":
      accent = NSColor.systemRed
      let circle = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: 15, height: 15))
      accent.setFill()
      circle.fill()
      let x1 = NSBezierPath()
      x1.move(to: NSPoint(x: 6.5, y: 6.5))
      x1.line(to: NSPoint(x: 11.5, y: 11.5))
      let x2 = NSBezierPath()
      x2.move(to: NSPoint(x: 11.5, y: 6.5))
      x2.line(to: NSPoint(x: 6.5, y: 11.5))
      x1.lineWidth = 1.8
      x2.lineWidth = 1.8
      x1.lineCapStyle = .round
      x2.lineCapStyle = .round
      NSColor.white.setStroke()
      x1.stroke()
      x2.stroke()

    default:
      // Idle: a simple cloud outline, drawn as template (auto-tinted).
      accent = NSColor.black
      path = NSBezierPath()
      path.move(to: NSPoint(x: 3, y: 8))
      path.curve(to: NSPoint(x: 5, y: 5),
                 controlPoint1: NSPoint(x: 3, y: 6.5),
                 controlPoint2: NSPoint(x: 3.8, y: 5.3))
      path.curve(to: NSPoint(x: 9, y: 5),
                 controlPoint1: NSPoint(x: 6, y: 4.8),
                 controlPoint2: NSPoint(x: 7.5, y: 4.8))
      path.curve(to: NSPoint(x: 13, y: 6),
                 controlPoint1: NSPoint(x: 11, y: 4.8),
                 controlPoint2: NSPoint(x: 12.5, y: 5.3))
      path.curve(to: NSPoint(x: 14, y: 11),
                 controlPoint1: NSPoint(x: 15, y: 7),
                 controlPoint2: NSPoint(x: 14.5, y: 10.5))
      path.curve(to: NSPoint(x: 10, y: 13),
                 controlPoint1: NSPoint(x: 14, y: 12.5),
                 controlPoint2: NSPoint(x: 12.5, y: 13))
      path.line(to: NSPoint(x: 6, y: 13))
      path.curve(to: NSPoint(x: 3, y: 11),
                 controlPoint1: NSPoint(x: 4.5, y: 13),
                 controlPoint2: NSPoint(x: 3, y: 12.5))
      path.curve(to: NSPoint(x: 3, y: 8),
                 controlPoint1: NSPoint(x: 2.5, y: 10),
                 controlPoint2: NSPoint(x: 2.5, y: 9))
      path.close()
      path.lineWidth = 1.2
      accent.setFill()
      path.fill()
    }

    image.unlockFocus()
    // For the idle cloud we want template tinting; colored states keep their color.
    image.isTemplate = (name == "cloud")
    return image
  }
}

/// Floating upload target shown near the status item while a file drag is active.
private final class TrayDropPanel: NSObject {
  var onDrop: (([String]) -> Void)?
  var onDragStateChanged: ((Bool) -> Void)?

  private let panel: NSPanel
  private let dropView: TrayDropPanelView
  private var hideWorkItem: DispatchWorkItem?

  override init() {
    let contentRect = NSRect(x: 0, y: 0, width: 280, height: 132)
    panel = NSPanel(
      contentRect: contentRect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    dropView = TrayDropPanelView(frame: contentRect)
    super.init()

    panel.isFloatingPanel = true
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.contentView = dropView

    dropView.onDrop = { [weak self] paths in
      self?.hideNow()
      self?.onDrop?(paths)
    }
    dropView.onDragStateChanged = { [weak self] isActive in
      self?.onDragStateChanged?(isActive)
    }
  }

  func show(near button: NSStatusBarButton) {
    cancelScheduledHide()

    guard let buttonWindow = button.window else { return }
    let buttonFrameInWindow = button.convert(button.bounds, to: nil)
    let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)
    let screenFrame = buttonWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    let size = panel.frame.size
    var origin = NSPoint(
      x: buttonFrameOnScreen.midX - size.width / 2,
      y: buttonFrameOnScreen.minY - size.height - 8
    )
    origin.x = min(max(origin.x, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
    origin.y = max(origin.y, screenFrame.minY + 8)

    panel.setFrame(NSRect(origin: origin, size: size), display: true)
    dropView.setActive(false)
    panel.orderFrontRegardless()
  }

  func scheduleHide() {
    cancelScheduledHide()
    let workItem = DispatchWorkItem { [weak self] in
      self?.hideNow()
    }
    hideWorkItem = workItem
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
  }

  func cancelScheduledHide() {
    hideWorkItem?.cancel()
    hideWorkItem = nil
  }

  func hideNow() {
    cancelScheduledHide()
    dropView.setActive(false)
    panel.orderOut(nil)
  }
}

private final class TrayDropPanelView: NSView {
  var onDrop: (([String]) -> Void)?
  var onDragStateChanged: ((Bool) -> Void)?

  private var isActive = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    registerForDraggedTypes([.fileURL])
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    registerForDraggedTypes([.fileURL])
  }

  func setActive(_ active: Bool) {
    guard isActive != active else { return }
    isActive = active
    needsDisplay = true
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let accepts = containsImageFiles(sender)
    if accepts {
      setActive(true)
      onDragStateChanged?(true)
    }
    return accepts ? .copy : []
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    return containsImageFiles(sender) ? .copy : []
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    setActive(false)
    onDragStateChanged?(false)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let paths = imageFilePaths(sender)
    guard !paths.isEmpty else { return false }
    onDrop?(paths)
    return true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let bounds = self.bounds.insetBy(dx: 1, dy: 1)
    let background = NSColor.windowBackgroundColor.withAlphaComponent(0.96)
    let activeBackground = NSColor.controlAccentColor.withAlphaComponent(0.16)
    let border = isActive ? NSColor.controlAccentColor : NSColor.separatorColor
    let path = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)

    (isActive ? activeBackground : background).setFill()
    path.fill()
    border.setStroke()
    path.lineWidth = isActive ? 2 : 1
    path.stroke()

    drawUploadGlyph(in: NSRect(x: 22, y: 40, width: 50, height: 50))
    drawText()
  }

  private func drawUploadGlyph(in rect: NSRect) {
    let circle = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
    NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
    circle.fill()

    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: rect.midX, y: rect.maxY - 13))
    arrow.line(to: NSPoint(x: rect.midX - 9, y: rect.midY + 1))
    arrow.move(to: NSPoint(x: rect.midX, y: rect.maxY - 13))
    arrow.line(to: NSPoint(x: rect.midX + 9, y: rect.midY + 1))
    arrow.move(to: NSPoint(x: rect.midX, y: rect.maxY - 13))
    arrow.line(to: NSPoint(x: rect.midX, y: rect.minY + 14))
    arrow.move(to: NSPoint(x: rect.midX - 12, y: rect.minY + 11))
    arrow.line(to: NSPoint(x: rect.midX + 12, y: rect.minY + 11))
    arrow.lineWidth = 2.4
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    NSColor.controlAccentColor.setStroke()
    arrow.stroke()
  }

  private func drawText() {
    let title = isActive ? "松开以上传" : "拖到这里上传"
    let subtitle = "GoPic 会上传图片并复制链接"
    let titleAttrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
      .foregroundColor: NSColor.labelColor
    ]
    let subtitleAttrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .regular),
      .foregroundColor: NSColor.secondaryLabelColor
    ]
    title.draw(in: NSRect(x: 88, y: 70, width: 170, height: 22), withAttributes: titleAttrs)
    subtitle.draw(in: NSRect(x: 88, y: 46, width: 178, height: 18), withAttributes: subtitleAttrs)
  }

  private func containsImageFiles(_ sender: NSDraggingInfo) -> Bool {
    !imageFilePaths(sender).isEmpty
  }

  private func imageFilePaths(_ sender: NSDraggingInfo) -> [String] {
    let imageExt = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg",
                    "tif", "tiff", "ico", "avif", "heic"]
    let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] else {
      return []
    }
    return items
      .map(\.path)
      .filter { path in
        let ext = (path as NSString).pathExtension.lowercased()
        return !ext.isEmpty && imageExt.contains(ext)
      }
  }
}

/// Drag destination placed over the menu-bar button.
private final class TrayDropView: NSView {
  var onDrop: (([String]) -> Void)?
  var onClick: ((NSEvent) -> Void)?
  var onDragStateChanged: ((Bool) -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    registerForDraggedTypes([.fileURL])
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    registerForDraggedTypes([.fileURL])
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    let accepts = containsImageFiles(sender)
    if accepts {
      onDragStateChanged?(true)
    }
    return accepts ? .copy : []
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    return containsImageFiles(sender) ? .copy : []
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    onDragStateChanged?(false)
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let paths = imageFilePaths(sender)
    guard !paths.isEmpty else { return false }
    onDrop?(paths)
    return true
  }

  override func mouseUp(with event: NSEvent) {
    onClick?(event)
  }

  override func rightMouseUp(with event: NSEvent) {
    onClick?(event)
  }

  private func containsImageFiles(_ sender: NSDraggingInfo) -> Bool {
    !imageFilePaths(sender).isEmpty
  }

  private func imageFilePaths(_ sender: NSDraggingInfo) -> [String] {
    let imageExt = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "svg",
                    "tif", "tiff", "ico", "avif", "heic"]
    let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
    guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: opts) as? [URL] else {
      return []
    }
    return items
      .map(\.path)
      .filter { path in
        let ext = (path as NSString).pathExtension.lowercased()
        return !ext.isEmpty && imageExt.contains(ext)
      }
  }
}

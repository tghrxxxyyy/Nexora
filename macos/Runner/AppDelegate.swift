import Cocoa
import FlutterMacOS
import WebKit

@main
class AppDelegate: FlutterAppDelegate {
  static weak var shared: AppDelegate?

  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let statusMenu = NSMenu()
  private var methodChannel: FlutterMethodChannel?
  private var appearanceChannel: FlutterMethodChannel?
  private var windowChannel: FlutterMethodChannel?
  private var pendingAppearanceColor: NSColor?
  private var recentDocuments: [(name: String, path: String)] = []

  override init() {
    super.init()
    AppDelegate.shared = self
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    super.applicationWillFinishLaunching(notification)
    configureStatusItem()
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  /// Force-terminate immediately on Quit. The Flutter engine's normal shutdown
  /// path waits on native side-channel cleanup (notably `flutter_pty`'s child
  /// kill on macOS) that doesn't always complete, which manifests to the user
  /// as the dock icon staying forever after "Quit" until force-quit.
  /// `.terminateNow` skips that wait. Session state is already persisted on
  /// every mutation, so the only thing lost is in-memory edits the user
  /// hasn't saved — and `_onExitRequested` on the Dart side already handles
  /// the dirty-documents dialog when Quit is initiated from the menu bar.
  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    return .terminateNow
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag {
      showMainWindow(nil)
    }
    return true
  }

  private func configureStatusItem() {
    if let button = statusItem.button {
      button.image = makeStatusItemImage()
      button.title = ""
      button.imagePosition = .imageOnly
      button.toolTip = "Nexora"
    }
    statusItem.menu = statusMenu
    rebuildStatusMenu()
  }

  private func makeStatusItemImage() -> NSImage {
    let image = NSImage(size: NSSize(width: 18, height: 18))
    image.lockFocus()
    let scale = 18.0 / 64.0
    let context = NSGraphicsContext.current!.cgContext
    context.translateBy(x: 0, y: 18)
    context.scaleBy(x: scale, y: -scale)

    NSColor.black.setFill()
    let mark = NSBezierPath()
    mark.move(to: NSPoint(x: 14, y: 49))
    mark.line(to: NSPoint(x: 14, y: 16))
    mark.line(to: NSPoint(x: 22, y: 11))
    mark.line(to: NSPoint(x: 42, y: 38))
    mark.line(to: NSPoint(x: 42, y: 16))
    mark.line(to: NSPoint(x: 50, y: 21))
    mark.line(to: NSPoint(x: 50, y: 49))
    mark.line(to: NSPoint(x: 42, y: 54))
    mark.line(to: NSPoint(x: 22, y: 27))
    mark.line(to: NSPoint(x: 22, y: 54))
    mark.close()
    mark.fill()

    NSColor.black.withAlphaComponent(0.42).setFill()
    let topFacet = NSBezierPath()
    topFacet.move(to: NSPoint(x: 22, y: 11))
    topFacet.line(to: NSPoint(x: 50, y: 21))
    topFacet.line(to: NSPoint(x: 42, y: 26))
    topFacet.line(to: NSPoint(x: 22, y: 16))
    topFacet.close()
    topFacet.fill()

    NSColor.black.withAlphaComponent(0.54).setFill()
    let sideFacet = NSBezierPath()
    sideFacet.move(to: NSPoint(x: 42, y: 43))
    sideFacet.line(to: NSPoint(x: 50, y: 38))
    sideFacet.line(to: NSPoint(x: 50, y: 49))
    sideFacet.line(to: NSPoint(x: 42, y: 54))
    sideFacet.close()
    sideFacet.fill()
    image.unlockFocus()
    image.isTemplate = true
    return image
  }

  func configureMethodChannel(_ flutterViewController: FlutterViewController) {
    if methodChannel != nil {
      return
    }
    let channel = FlutterMethodChannel(
      name: "com.xuyu.nexora/status_menu",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    methodChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setRecentDocuments":
        self?.setRecentDocuments(call.arguments)
        result(nil)
      case "showMainWindow":
        self?.showMainWindow(nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    channel.invokeMethod("requestRecentDocuments", arguments: nil)

    let appearance = FlutterMethodChannel(
      name: "com.xuyu.nexora/webview_appearance",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    appearanceChannel = appearance
    appearance.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch call.method {
      case "setBaseColor":
        let applied = self.setBaseColor(call.arguments)
        result(applied)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let window = FlutterMethodChannel(
      name: "com.xuyu.nexora/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    windowChannel = window
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidEnterFullScreen(_:)),
      name: NSWindow.didEnterFullScreenNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidExitFullScreen(_:)),
      name: NSWindow.didExitFullScreenNotification,
      object: nil
    )
    // Push the initial state once the window exists; configureMethodChannel
    // runs before MainFlutterWindow is guaranteed to be in NSApp.windows.
    DispatchQueue.main.async { [weak self] in
      guard let self = self,
            let main = NSApp.windows.first(where: { $0 is MainFlutterWindow }) else {
        return
      }
      self.windowChannel?.invokeMethod(
        "fullscreenChanged",
        arguments: main.styleMask.contains(.fullScreen)
      )
    }
  }

  @objc private func windowDidEnterFullScreen(_ note: Notification) {
    windowChannel?.invokeMethod("fullscreenChanged", arguments: true)
  }

  @objc private func windowDidExitFullScreen(_ note: Notification) {
    windowChannel?.invokeMethod("fullscreenChanged", arguments: false)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  /// Pushes the current theme's base color to the native side so the window
  /// background and every WKWebView's `underPageBackgroundColor` match it.
  /// This kills the 1px white seam that shows on the right edge of the
  /// markdown preview in dark theme (where the WKWebView default white
  /// bleeds through any gap between the HTML body and the WebView frame).
  @discardableResult
  private func setBaseColor(_ arguments: Any?) -> Bool {
    guard let values = arguments as? [String: Any],
          let r = values["r"] as? Double,
          let g = values["g"] as? Double,
          let b = values["b"] as? Double else {
      return false
    }
    let a = values["a"] as? Double ?? 1.0
    let color = NSColor(
      srgbRed: CGFloat(r),
      green: CGFloat(g),
      blue: CGFloat(b),
      alpha: CGFloat(a)
    )
    pendingAppearanceColor = color

    guard let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) else {
      return false
    }
    window.backgroundColor = color
    let darkAqua = NSAppearance(named: .darkAqua)
    let aqua = NSAppearance(named: .aqua)
    let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
    window.appearance = luminance < 0.5 ? darkAqua : aqua

    var found = 0
    for view in window.contentView?.subviews ?? [] {
      found += applyUnderPageBackground(to: view, color: color)
    }
    return found > 0
  }

  /// Recursively walks the view tree, repainting any WKWebView's
  /// underPageBackgroundColor. Stashes the requested color so views that
  /// mount later (Flutter platform views are created lazily) still get it.
  private func applyUnderPageBackground(to view: NSView, color: NSColor) -> Int {
    var count = 0
    if let webView = view as? WKWebView {
      if #available(macOS 12.0, *) {
        webView.underPageBackgroundColor = color
      }
      count += 1
    }
    for subview in view.subviews {
      count += applyUnderPageBackground(to: subview, color: color)
    }
    return count
  }

  /// Called from `applicationDidBecomeActive` so any WKWebView that was
  /// mounted after the Dart-side push still picks up the saved color.
  func reapplyPendingAppearanceColor() {
    guard let color = pendingAppearanceColor,
          let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) else {
      return
    }
    for view in window.contentView?.subviews ?? [] {
      _ = applyUnderPageBackground(to: view, color: color)
    }
  }

  private func setRecentDocuments(_ arguments: Any?) {
    guard let values = arguments as? [[String: Any]] else {
      recentDocuments = []
      rebuildStatusMenu()
      return
    }
    recentDocuments = values.compactMap { value in
      guard let name = value["name"] as? String,
            let path = value["path"] as? String,
            !name.isEmpty,
            !path.isEmpty else {
        return nil
      }
      return (name: name, path: path)
    }
    rebuildStatusMenu()
  }

  private func rebuildStatusMenu() {
    statusMenu.removeAllItems()
    let showItem = NSMenuItem(
      title: "显示 Nexora",
      action: #selector(showMainWindow(_:)),
      keyEquivalent: ""
    )
    showItem.target = self
    statusMenu.addItem(showItem)
    statusMenu.addItem(.separator())

    let recentLabel = NSMenuItem(title: "最近打开", action: nil, keyEquivalent: "")
    recentLabel.isEnabled = false
    statusMenu.addItem(recentLabel)

    if recentDocuments.isEmpty {
      let emptyItem = NSMenuItem(title: "暂无最近文档", action: nil, keyEquivalent: "")
      emptyItem.isEnabled = false
      statusMenu.addItem(emptyItem)
      return
    }

    for document in recentDocuments.prefix(4) {
      let item = NSMenuItem(
        title: document.name,
        action: #selector(openRecentDocument(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = document.path
      statusMenu.addItem(item)
    }
  }

  @objc private func showMainWindow(_ sender: Any?) {
    guard let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) else {
      return
    }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(sender)
  }

  @objc private func openRecentDocument(_ sender: NSMenuItem) {
    guard let path = sender.representedObject as? String else {
      return
    }
    showMainWindow(nil)
    methodChannel?.invokeMethod("openRecentDocument", arguments: path)
  }
}

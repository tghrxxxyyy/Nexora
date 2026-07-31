import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  static weak var shared: AppDelegate?

  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private let statusMenu = NSMenu()
  private var methodChannel: FlutterMethodChannel?
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

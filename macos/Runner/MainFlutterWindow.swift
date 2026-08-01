import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    title = "Nexora"
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    if #available(macOS 11.0, *) {
      titlebarSeparatorStyle = .none
    }
    styleMask.insert(.fullSizeContentView)
    isMovableByWindowBackground = true
    minSize = NSSize(width: 960, height: 640)
    // Start with white; the Dart side pushes the real theme color via the
    // `com.xuyu.nexora/webview_appearance` method channel as soon as the
    // app state restores. Without this, dark theme flashes white at the
    // edges while the WebView is still loading.
    backgroundColor = .white
    appearance = NSAppearance(named: .aqua)

    if frame.width < 1180 || frame.height < 720 {
      setContentSize(NSSize(width: 1380, height: 850))
      center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)
    AppDelegate.shared?.configureMethodChannel(flutterViewController)

    super.awakeFromNib()
  }

  override func performClose(_ sender: Any?) {
    orderOut(sender)
  }
}

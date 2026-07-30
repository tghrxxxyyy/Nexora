import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    title = "x-file"
    titleVisibility = .hidden
    titlebarAppearsTransparent = true
    if #available(macOS 11.0, *) {
      titlebarSeparatorStyle = .none
    }
    styleMask.insert(.fullSizeContentView)
    isMovableByWindowBackground = true
    minSize = NSSize(width: 960, height: 640)
    backgroundColor = NSColor(
      calibratedRed: 8.0 / 255.0,
      green: 11.0 / 255.0,
      blue: 12.0 / 255.0,
      alpha: 1
    )
    appearance = NSAppearance(named: .darkAqua)

    if frame.width < 1180 || frame.height < 720 {
      setContentSize(NSSize(width: 1380, height: 850))
      center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}

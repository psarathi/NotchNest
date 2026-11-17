import AppKit
import NotchNestCore

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: NotchNestModel?
    private var panelController: NotchPanelController?
    private var statusBarController: StatusBarController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let model = NotchNestModel()
        let panelController = NotchPanelController(model: model)
        let statusBarController = StatusBarController(model: model, panelController: panelController)

        self.model = model
        self.panelController = panelController
        self.statusBarController = statusBarController

        panelController.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.expand(makeKey: true)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.shutdown()
    }
}

import AppKit
import NotchNestCore

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let model: NotchNestModel
    private let panelController: NotchPanelController

    init(model: NotchNestModel, panelController: NotchPanelController) {
        self.model = model
        self.panelController = panelController
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            let image = Self.makeMenuBarOwlIcon()
            image.isTemplate = true
            button.image = image
            button.toolTip = "NotchNest (⌥Space to toggle)"
        }

        buildMenu()
    }

    private func buildMenu() {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Toggle Notch Drawer",
            action: #selector(toggleNotch),
            keyEquivalent: " "
        )
        toggleItem.keyEquivalentModifierMask = [.option]
        toggleItem.target = self
        menu.addItem(toggleItem)

        let pinItem = NSMenuItem(
            title: "Pin / Unpin Open",
            action: #selector(togglePin),
            keyEquivalent: "p"
        )
        pinItem.target = self
        menu.addItem(pinItem)

        menu.addItem(.separator())

        let timerItem = NSMenuItem(
            title: "Start / Pause Focus Timer",
            action: #selector(toggleTimer),
            keyEquivalent: "t"
        )
        timerItem.target = self
        menu.addItem(timerItem)

        let settingsItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit NotchNest",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleNotch() {
        panelController.toggleFromShortcutOrMenu()
    }

    @objc private func togglePin() {
        if !model.isExpanded {
            model.isPinned = true
            panelController.expand(makeKey: true)
        } else {
            model.isPinned.toggle()
        }
    }

    @objc private func toggleTimer() {
        model.toggleFocusPlayPause()
    }

    @objc private func openSettings() {
        model.isPinned = true
        panelController.expand(tab: .settings, makeKey: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private static func makeMenuBarOwlIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            let w = rect.width
            let h = rect.height
            let cx = w / 2

            let path = NSBezierPath()
            path.windingRule = .evenOdd

            // Owl head silhouette with ear tufts matching the mascot proportions
            path.move(to: NSPoint(x: w * 0.20, y: h * 0.14))
            path.line(to: NSPoint(x: w * 0.34, y: h * 0.24))
            path.curve(
                to: NSPoint(x: w * 0.66, y: h * 0.24),
                controlPoint1: NSPoint(x: w * 0.44, y: h * 0.20),
                controlPoint2: NSPoint(x: w * 0.56, y: h * 0.20)
            )
            path.line(to: NSPoint(x: w * 0.80, y: h * 0.14))
            path.curve(
                to: NSPoint(x: w * 0.86, y: h * 0.56),
                controlPoint1: NSPoint(x: w * 0.87, y: h * 0.28),
                controlPoint2: NSPoint(x: w * 0.89, y: h * 0.43)
            )
            path.curve(
                to: NSPoint(x: cx, y: h * 0.90),
                controlPoint1: NSPoint(x: w * 0.83, y: h * 0.77),
                controlPoint2: NSPoint(x: w * 0.68, y: h * 0.89)
            )
            path.curve(
                to: NSPoint(x: w * 0.14, y: h * 0.56),
                controlPoint1: NSPoint(x: w * 0.32, y: h * 0.89),
                controlPoint2: NSPoint(x: w * 0.17, y: h * 0.77)
            )
            path.curve(
                to: NSPoint(x: w * 0.20, y: h * 0.14),
                controlPoint1: NSPoint(x: w * 0.11, y: h * 0.43),
                controlPoint2: NSPoint(x: w * 0.13, y: h * 0.28)
            )
            path.close()

            // Left & right eye cutouts plus solid pupils via even-odd winding
            let eyeY = h * 0.50
            let leftEyeCenter = NSPoint(x: w * 0.36, y: eyeY)
            let rightEyeCenter = NSPoint(x: w * 0.64, y: eyeY)
            let outerEyeRadius: CGFloat = w * 0.15
            let pupilRadius: CGFloat = w * 0.062

            for center in [leftEyeCenter, rightEyeCenter] {
                path.appendOval(in: NSRect(
                    x: center.x - outerEyeRadius,
                    y: center.y - outerEyeRadius,
                    width: outerEyeRadius * 2,
                    height: outerEyeRadius * 2
                ))
                path.appendOval(in: NSRect(
                    x: center.x - pupilRadius,
                    y: center.y - pupilRadius,
                    width: pupilRadius * 2,
                    height: pupilRadius * 2
                ))
            }

            // Downward beak cutout
            path.move(to: NSPoint(x: cx - w * 0.065, y: h * 0.63))
            path.line(to: NSPoint(x: cx + w * 0.065, y: h * 0.63))
            path.line(to: NSPoint(x: cx, y: h * 0.74))
            path.close()

            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

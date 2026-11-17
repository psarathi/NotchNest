import AppKit
@preconcurrency import ApplicationServices
import Foundation
import Observation

public enum SnapError: LocalizedError, Sendable {
    case accessibilityNotGranted
    case noTargetWindow
    case cannotModifyWindow

    public var errorDescription: String? {
        switch self {
        case .accessibilityNotGranted:
            return "Grant Accessibility permission in System Settings to snap windows."
        case .noTargetWindow:
            return "No active app window found to snap."
        case .cannotModifyWindow:
            return "The focused window does not support resizing or moving."
        }
    }
}

@MainActor
@Observable
public final class WindowSnapService {
    public private(set) var isAccessibilityTrusted: Bool = false
    public private(set) var lastTargetAppName: String?
    public private(set) var lastStatusMessage: String?

    private var lastExternalPID: pid_t?
    @ObservationIgnored private nonisolated(unsafe) var activationObserver: NSObjectProtocol?
    @ObservationIgnored private nonisolated(unsafe) var dragMonitor: Any?
    private var topEdgeDragArmed: Bool = false

    public init() {
        refreshTrustStatus()
        seedExternalApp()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            let bundleID = app?.bundleIdentifier
            let name = app?.localizedName
            Task { @MainActor in
                self?.recordActivatedApp(pid: pid, bundleID: bundleID, name: name)
            }
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
        }
    }

    public func stop() {
        if let observer = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.activationObserver = nil
        }
        disableTopEdgeDragSnap()
    }

    public func refreshTrustStatus() {
        isAccessibilityTrusted = AXIsProcessTrusted()
    }

    public func requestAccessibilityPrompt() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshTrustStatus()
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func updateTopEdgeDragSnap(enabled: Bool) {
        if enabled {
            enableTopEdgeDragSnap()
        } else {
            disableTopEdgeDragSnap()
        }
    }

    private func enableTopEdgeDragSnap() {
        guard dragMonitor == nil else { return }
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let type = event.type
            let mouse = NSEvent.mouseLocation
            Task { @MainActor in
                self?.handleGlobalDragEvent(type: type, mouseLocation: mouse)
            }
        }
    }

    private func disableTopEdgeDragSnap() {
        if let dragMonitor {
            NSEvent.removeMonitor(dragMonitor)
            self.dragMonitor = nil
        }
        topEdgeDragArmed = false
    }

    private func handleGlobalDragEvent(type: NSEvent.EventType, mouseLocation: NSPoint) {
        guard AXIsProcessTrusted() else { return }
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main else {
            return
        }
        let nearTopEdge = mouseLocation.y >= screen.frame.maxY - 10
        switch type {
        case .leftMouseDragged:
            topEdgeDragArmed = nearTopEdge
        case .leftMouseUp:
            guard topEdgeDragArmed, nearTopEdge else {
                topEdgeDragArmed = false
                return
            }
            topEdgeDragArmed = false
            let relX = (mouseLocation.x - screen.frame.minX) / max(1, screen.frame.width)
            let zone: SnapZone
            if relX < 0.30 {
                zone = .leftHalf
            } else if relX > 0.70 {
                zone = .rightHalf
            } else {
                zone = .maximize
            }
            _ = snapFrontmostWindow(to: zone)
        default:
            break
        }
    }

    private func seedExternalApp() {
        let selfBundle = Bundle.main.bundleIdentifier
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != selfBundle {
            lastExternalPID = front.processIdentifier
            lastTargetAppName = front.localizedName
        }
    }

    private func recordActivatedApp(pid: pid_t?, bundleID: String?, name: String?) {
        guard let pid, bundleID != Bundle.main.bundleIdentifier else { return }
        lastExternalPID = pid
        lastTargetAppName = name
    }

    /// Computes AppKit global-coordinate target rectangle within `visibleFrame`.
    public nonisolated static func targetAppKitFrame(for zone: SnapZone, visibleFrame: CGRect) -> CGRect {
        let minX = visibleFrame.minX
        let minY = visibleFrame.minY
        let w = visibleFrame.width
        let h = visibleFrame.height
        let halfW = floor(w / 2.0)
        let halfH = floor(h / 2.0)
        let thirdW = floor(w / 3.0)

        switch zone {
        case .leftHalf:
            return CGRect(x: minX, y: minY, width: halfW, height: h)
        case .rightHalf:
            return CGRect(x: minX + halfW, y: minY, width: w - halfW, height: h)
        case .topHalf:
            return CGRect(x: minX, y: minY + halfH, width: w, height: h - halfH)
        case .bottomHalf:
            return CGRect(x: minX, y: minY, width: w, height: halfH)
        case .leftThird:
            return CGRect(x: minX, y: minY, width: thirdW, height: h)
        case .centerThird:
            return CGRect(x: minX + thirdW, y: minY, width: thirdW, height: h)
        case .rightThird:
            return CGRect(x: minX + thirdW * 2.0, y: minY, width: w - thirdW * 2.0, height: h)
        case .topLeftQuarter:
            return CGRect(x: minX, y: minY + halfH, width: halfW, height: h - halfH)
        case .topRightQuarter:
            return CGRect(x: minX + halfW, y: minY + halfH, width: w - halfW, height: h - halfH)
        case .bottomLeftQuarter:
            return CGRect(x: minX, y: minY, width: halfW, height: halfH)
        case .bottomRightQuarter:
            return CGRect(x: minX + halfW, y: minY, width: w - halfW, height: halfH)
        case .maximize:
            return visibleFrame
        case .center:
            let cw = floor(w * 0.72)
            let ch = floor(h * 0.78)
            return CGRect(
                x: minX + floor((w - cw) / 2.0),
                y: minY + floor((h - ch) / 2.0),
                width: cw,
                height: ch
            )
        }
    }

    /// Converts AppKit coordinates (bottom-left origin) into Accessibility top-left coordinates.
    public nonisolated static func accessibilityFrame(
        for zone: SnapZone,
        visibleFrame: CGRect,
        primaryScreenMaxY: CGFloat
    ) -> CGRect {
        let appKit = targetAppKitFrame(for: zone, visibleFrame: visibleFrame)
        let axY = primaryScreenMaxY - appKit.maxY
        return CGRect(x: appKit.minX, y: axY, width: appKit.width, height: appKit.height)
    }

    @discardableResult
    public func snapFrontmostWindow(to zone: SnapZone) -> Result<String, SnapError> {
        refreshTrustStatus()
        guard isAccessibilityTrusted else {
            requestAccessibilityPrompt()
            lastStatusMessage = SnapError.accessibilityNotGranted.localizedDescription
            return .failure(.accessibilityNotGranted)
        }

        let selfBundle = Bundle.main.bundleIdentifier
        let targetApp: NSRunningApplication?
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != selfBundle {
            targetApp = front
            lastExternalPID = front.processIdentifier
            lastTargetAppName = front.localizedName
        } else if let pid = lastExternalPID {
            targetApp = NSRunningApplication(processIdentifier: pid)
        } else {
            targetApp = NSWorkspace.shared.runningApplications.first {
                $0.activationPolicy == .regular && $0.bundleIdentifier != selfBundle
            }
        }

        guard let targetApp else {
            lastStatusMessage = SnapError.noTargetWindow.localizedDescription
            return .failure(.noTargetWindow)
        }

        let appElement = AXUIElementCreateApplication(targetApp.processIdentifier)
        var focusedWindowRef: CFTypeRef?
        var status = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
        if status != .success || focusedWindowRef == nil {
            status = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &focusedWindowRef)
        }
        guard status == .success, let windowCF = focusedWindowRef else {
            lastStatusMessage = SnapError.noTargetWindow.localizedDescription
            return .failure(.noTargetWindow)
        }
        let windowElement = windowCF as! AXUIElement

        let primaryScreen = NSScreen.screens.first ?? NSScreen.main
        let primaryMaxY = primaryScreen?.frame.maxY ?? 900
        let screen = targetScreen(for: windowElement, primaryMaxY: primaryMaxY) ?? NSScreen.main ?? primaryScreen
        guard let screen else {
            return .failure(.noTargetWindow)
        }

        let targetAX = Self.accessibilityFrame(
            for: zone,
            visibleFrame: screen.visibleFrame,
            primaryScreenMaxY: primaryMaxY
        )

        var pos = CGPoint(x: targetAX.origin.x, y: targetAX.origin.y)
        var size = CGSize(width: targetAX.size.width, height: targetAX.size.height)

        guard let posVal = AXValueCreate(.cgPoint, &pos),
              let sizeVal = AXValueCreate(.cgSize, &size) else {
            return .failure(.cannotModifyWindow)
        }

        let setPos = AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, posVal)
        let setSize = AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeVal)
        // Re-apply position after size because macOS constraints may shift bounds on resize.
        _ = AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, posVal)

        if setPos != .success && setSize != .success {
            lastStatusMessage = SnapError.cannotModifyWindow.localizedDescription
            return .failure(.cannotModifyWindow)
        }

        let appTitle = targetApp.localizedName ?? "Window"
        let msg = "Snapped \(appTitle) -> \(zone.title)"
        lastStatusMessage = msg
        return .success(msg)
    }

    private func targetScreen(for window: AXUIElement, primaryMaxY: CGFloat) -> NSScreen? {
        var posRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
              let posCF = posRef else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(posCF as! AXValue, .cgPoint, &point) else { return nil }
        let appKitPoint = NSPoint(x: point.x + 20, y: primaryMaxY - point.y - 20)
        return NSScreen.screens.first { NSPointInRect(appKitPoint, $0.frame) }
    }
}

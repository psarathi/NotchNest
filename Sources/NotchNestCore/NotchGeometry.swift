import CoreGraphics
import Foundation

#if canImport(AppKit)
import AppKit
#endif

/// Pure screen metrics extracted from NSScreen so notch layout math is unit-testable.
public struct ScreenMetrics: Equatable, Sendable {
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var safeAreaTop: CGFloat
    public var auxiliaryTopLeft: CGRect
    public var auxiliaryTopRight: CGRect

    public init(
        frame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat = 0,
        auxiliaryTopLeft: CGRect = .zero,
        auxiliaryTopRight: CGRect = .zero
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.auxiliaryTopLeft = auxiliaryTopLeft
        self.auxiliaryTopRight = auxiliaryTopRight
    }

    public var hasHardwareNotch: Bool {
        safeAreaTop > 0 && auxiliaryTopLeft.width > 0 && auxiliaryTopRight.width > 0
    }

    public var menuBarHeight: CGFloat {
        max(0, frame.maxY - visibleFrame.maxY)
    }

    public var hardwareNotchWidth: CGFloat {
        guard hasHardwareNotch else { return 0 }
        return max(0, frame.width - auxiliaryTopLeft.width - auxiliaryTopRight.width)
    }

    #if canImport(AppKit)
    @MainActor
    public init(screen: NSScreen) {
        self.init(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeft: screen.auxiliaryTopLeftArea ?? .zero,
            auxiliaryTopRight: screen.auxiliaryTopRightArea ?? .zero
        )
    }
    #endif
}

public struct NotchLayout: Equatable, Sendable {
    /// Fixed overlay NSPanel frame in global screen coordinates (anchored at screen.maxY).
    public var panelFrame: CGRect
    /// Visible collapsed pill size inside the top-center of panelFrame.
    public var collapsedSize: CGSize
    /// Compact Live Activity nudge pill size below the top center bezel.
    public var liveActivitySize: CGSize
    /// Visible expanded drawer size inside the top-center of panelFrame.
    public var expandedSize: CGSize
    /// Whether the display has a physical hardware notch.
    public var hasHardwareNotch: Bool
    /// Top padding reserved inside the expanded drawer to clear a hardware notch or virtual header.
    public var topSafeHeaderHeight: CGFloat

    public init(
        panelFrame: CGRect,
        collapsedSize: CGSize,
        liveActivitySize: CGSize = CGSize(width: 280, height: 64),
        expandedSize: CGSize,
        hasHardwareNotch: Bool,
        topSafeHeaderHeight: CGFloat
    ) {
        self.panelFrame = panelFrame
        self.collapsedSize = collapsedSize
        self.liveActivitySize = liveActivitySize
        self.expandedSize = expandedSize
        self.hasHardwareNotch = hasHardwareNotch
        self.topSafeHeaderHeight = topSafeHeaderHeight
    }

    /// Hit-test rect in AppKit panel coordinates (origin at bottom-left of panelFrame).
    public func activeHitRectInPanel(isExpanded: Bool, isLiveActivity: Bool = false) -> CGRect {
        let size: CGSize
        if isExpanded {
            size = expandedSize
        } else if isLiveActivity {
            size = liveActivitySize
        } else {
            size = collapsedSize
        }
        let x = (panelFrame.width - size.width) / 2
        let y = panelFrame.height - size.height
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
}

public enum NotchGeometry {
    public static let defaultExpandedWidth: CGFloat = 780
    public static let defaultExpandedHeight: CGFloat = 448
    public static let wideExpandedWidth: CGFloat = 940
    public static let wideExpandedHeight: CGFloat = 520
    public static let horizontalMargin: CGFloat = 12
    public static let shadowPaddingHorizontal: CGFloat = 24
    public static let shadowPaddingBottom: CGFloat = 28

    public static func computeLayout(
        for metrics: ScreenMetrics,
        preferredCollapsedWidth: CGFloat = 216,
        isWideDrawer: Bool = false
    ) -> NotchLayout {
        let clampedBaseWidth = min(max(preferredCollapsedWidth, 168), 320)

        let collapsedWidth: CGFloat
        let collapsedHeight: CGFloat
        let headerHeight: CGFloat

        if metrics.hasHardwareNotch {
            let minWingWidth = metrics.hardwareNotchWidth + 88
            collapsedWidth = max(clampedBaseWidth, minWingWidth)
            collapsedHeight = max(32, metrics.safeAreaTop)
            headerHeight = collapsedHeight
        } else {
            collapsedWidth = clampedBaseWidth
            let detectedMenuBar = metrics.menuBarHeight
            collapsedHeight = detectedMenuBar > 0 ? min(max(detectedMenuBar, 29), 31) : 30
            headerHeight = 32
        }

        let targetExpandedWidth = isWideDrawer ? wideExpandedWidth : defaultExpandedWidth
        let targetExpandedHeight = isWideDrawer ? wideExpandedHeight : defaultExpandedHeight
        let maxAllowedWidth = max(360, metrics.frame.width - (horizontalMargin * 2))
        let expandedWidth = min(targetExpandedWidth, maxAllowedWidth)
        let maxAllowedHeight = max(240, metrics.frame.height - 80)
        let expandedHeight = min(targetExpandedHeight, maxAllowedHeight)

        let panelWidth = min(
            metrics.frame.width,
            max(collapsedWidth, expandedWidth) + shadowPaddingHorizontal * 2
        )
        let panelHeight = min(
            metrics.frame.height,
            max(collapsedHeight, expandedHeight) + shadowPaddingBottom
        )

        let rawX = metrics.frame.midX - (panelWidth / 2)
        let clampedX = min(
            max(rawX, metrics.frame.minX),
            metrics.frame.maxX - panelWidth
        )
        let panelY = metrics.frame.maxY - panelHeight

        let liveWidth = max(collapsedWidth, 286)
        let liveHeight: CGFloat = metrics.hasHardwareNotch ? (collapsedHeight + 36) : 64

        return NotchLayout(
            panelFrame: CGRect(x: clampedX, y: panelY, width: panelWidth, height: panelHeight),
            collapsedSize: CGSize(width: collapsedWidth, height: collapsedHeight),
            liveActivitySize: CGSize(width: liveWidth, height: liveHeight),
            expandedSize: CGSize(width: expandedWidth, height: expandedHeight),
            hasHardwareNotch: metrics.hasHardwareNotch,
            topSafeHeaderHeight: headerHeight
        )
    }

    /// Returns true when the cursor sits over inline collapsed media controls or Live Activity action buttons,
    /// preventing hover-to-expand from opening the drawer while the user is interacting with those controls.
    public static func isPointInCollapsedControlExclusionZone(
        point: CGPoint,
        hitRect: CGRect,
        hasMediaControls: Bool,
        hasLiveActivity: Bool
    ) -> Bool {
        guard hitRect.contains(point) else { return false }
        if hasLiveActivity {
            let inBottomButtonRow = point.y <= hitRect.minY + 34
            let inRightDismiss = point.x >= hitRect.maxX - 44
            return inBottomButtonRow || inRightDismiss
        }
        if hasMediaControls {
            let controlsWidth = min(116, max(78, hitRect.width * 0.48))
            return point.x >= hitRect.maxX - controlsWidth
        }
        return false
    }
}

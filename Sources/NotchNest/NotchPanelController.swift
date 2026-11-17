import AppKit
import NotchNestCore
import SwiftUI

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Hosting view that forwards first-mouse clicks into SwiftUI without requiring prior panel activation.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Custom container hosting SwiftUI content that only intercepts pointer/drag events inside activeHitRect.
final class NotchContainerView: NSView {
    var activeHitRect: CGRect = .zero
    var hoverTriggerRect: CGRect = .zero {
        didSet {
            if hoverTriggerRect != oldValue {
                updateTrackingAreas()
            }
        }
    }

    var onMouseEnterNotch: (() -> Void)?
    var onMouseMovedInNotch: ((NSPoint) -> Void)?
    var onMouseExitNotch: (() -> Void)?
    var onClickInsideNotch: (() -> Void)?
    var onDragEnterNotch: (() -> Void)?
    var onDragExitNotch: (() -> Void)?
    var onDropFileURLs: (([URL]) -> Void)?

    private var activeTrackingArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard activeHitRect.contains(local) else {
            return nil
        }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let activeTrackingArea {
            removeTrackingArea(activeTrackingArea)
        }
        let rect = hoverTriggerRect.isEmpty ? (activeHitRect.isEmpty ? bounds : activeHitRect) : hoverTriggerRect
        let area = NSTrackingArea(
            rect: rect,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        activeTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseEnterNotch?()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let localPoint = convert(event.locationInWindow, from: nil)
        onMouseMovedInNotch?(localPoint)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseExitNotch?()
    }

    override func mouseDown(with event: NSEvent) {
        onClickInsideNotch?()
        super.mouseDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = extractFileURLs(from: sender.draggingPasteboard)
        guard !urls.isEmpty else { return [] }
        onDragEnterNotch?()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = extractFileURLs(from: sender.draggingPasteboard)
        return urls.isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragExitNotch?()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onDragExitNotch?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = extractFileURLs(from: sender.draggingPasteboard)
        onDragExitNotch?()
        guard !urls.isEmpty else { return false }
        onDropFileURLs?(urls)
        return true
    }

    private func extractFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }
}

@MainActor
final class NotchPanelController {
    let model: NotchNestModel
    private(set) var layout: NotchLayout

    private let panel: NotchPanel
    private let containerView: NotchContainerView
    private var hostingView: NotchHostingView<NotchRootView>?

    private var hoverExpandTask: Task<Void, Never>?
    private var hoverCollapseTask: Task<Void, Never>?
    private nonisolated(unsafe) var globalMouseMonitor: Any?
    private nonisolated(unsafe) var localMouseMonitor: Any?
    private nonisolated(unsafe) var localKeyMonitor: Any?
    private nonisolated(unsafe) var screenObserver: NSObjectProtocol?
    private nonisolated(unsafe) var menuBeginObserver: NSObjectProtocol?
    private nonisolated(unsafe) var menuEndObserver: NSObjectProtocol?
    private var lastExternalApp: NSRunningApplication?
    private var isTrackingMenu = false
    private var menuActionSelected = false

    init(model: NotchNestModel) {
        self.model = model
        let screen = Self.resolveTargetScreen(mode: model.settings.displayMode)
        self.layout = NotchGeometry.computeLayout(
            for: ScreenMetrics(screen: screen),
            preferredCollapsedWidth: model.settings.collapsedWidth,
            isWideDrawer: model.settings.isWideDrawer
        )

        self.panel = NotchPanel(
            contentRect: layout.panelFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.containerView = NotchContainerView(
            frame: CGRect(origin: .zero, size: layout.panelFrame.size)
        )

        configurePanel()
        configureContent()
        installMonitors()

        model.onRequestPanelToggle = { [weak self] in
            self?.toggleFromShortcutOrMenu()
        }
        model.onRequestPanelExpand = { [weak self] tab in
            self?.expand(tab: tab, makeKey: true)
        }
        model.onLayoutSettingsChanged = { [weak self] in
            self?.relayoutForCurrentScreen()
        }
        model.onHitRectNeedsUpdate = { [weak self] in
            self?.updateHitRect()
        }
        model.onPrivacyModeChanged = { [weak self] hidden in
            self?.applyPrivacyMode(hidden)
        }
    }

    deinit {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let menuBeginObserver {
            NotificationCenter.default.removeObserver(menuBeginObserver)
        }
        if let menuEndObserver {
            NotificationCenter.default.removeObserver(menuEndObserver)
        }
    }

    func show() {
        relayoutForCurrentScreen()
        panel.orderFrontRegardless()
    }

    func toggleFromShortcutOrMenu() {
        if model.isExpanded {
            collapse(force: true)
        } else {
            expand(makeKey: true)
        }
    }

    func expand(tab: NotchTab? = nil, makeKey: Bool = false) {
        hoverExpandTask?.cancel()
        hoverCollapseTask?.cancel()

        if !model.isExpanded {
            relayoutForCurrentScreen()
            captureExternalFrontmostApp()
        }

        if let tab {
            model.activeTab = tab
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.80)) {
            model.isExpanded = true
        }
        updateHitRect()
        model.eventKit.refreshEvents()
        model.updateMirrorActivation()

        if makeKey {
            focusPanelForTyping()
            if (tab ?? model.activeTab) == .today && model.activeUtilityOverlay == nil {
                model.requestWorkspaceInputFocus()
            }
        } else {
            panel.orderFrontRegardless()
        }
    }

    func collapse(force: Bool = false) {
        hoverExpandTask?.cancel()
        hoverCollapseTask?.cancel()
        if model.isPinned && !force {
            return
        }
        model.isPinned = false

        let wasKey = panel.isKeyWindow
        withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
            model.isExpanded = false
        }
        updateHitRect()
        model.updateMirrorActivation()

        if wasKey {
            resignPanelKeyFocus()
        }
    }

    func focusPanelForTyping() {
        captureExternalFrontmostApp()
        panel.makeKeyAndOrderFront(nil)
    }

    func relayoutForCurrentScreen() {
        let screen = Self.resolveTargetScreen(mode: model.settings.displayMode)
        let newLayout = NotchGeometry.computeLayout(
            for: ScreenMetrics(screen: screen),
            preferredCollapsedWidth: model.settings.collapsedWidth,
            isWideDrawer: model.settings.isWideDrawer
        )
        layout = newLayout
        panel.setFrame(newLayout.panelFrame, display: true)
        containerView.frame = CGRect(origin: .zero, size: newLayout.panelFrame.size)
        hostingView?.frame = containerView.bounds
        hostingView?.rootView = makeRootView()
        updateHitRect()
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = containerView
        applyPrivacyMode(model.settings.hideInScreenCapture)
    }

    private func applyPrivacyMode(_ hiddenInCapture: Bool) {
        panel.sharingType = hiddenInCapture ? .none : .readOnly
    }

    private func configureContent() {
        let rootView = makeRootView()
        let hosting = NotchHostingView(rootView: rootView)
        hosting.frame = containerView.bounds
        hosting.autoresizingMask = [.width, .height]
        containerView.addSubview(hosting)
        self.hostingView = hosting

        containerView.onMouseEnterNotch = { [weak self] in
            self?.handleMouseEntered()
        }
        containerView.onMouseMovedInNotch = { [weak self] localPoint in
            self?.handleMouseMoved(at: localPoint)
        }
        containerView.onMouseExitNotch = { [weak self] in
            self?.handleMouseExited()
        }
        containerView.onClickInsideNotch = { [weak self] in
            guard let self else { return }
            if self.model.isExpanded {
                self.focusPanelForTyping()
            } else {
                let screenPoint = NSEvent.mouseLocation
                let windowPoint = self.panel.convertPoint(fromScreen: screenPoint)
                let localPoint = self.containerView.convert(windowPoint, from: nil)
                let inControlZone = NotchGeometry.isPointInCollapsedControlExclusionZone(
                    point: localPoint,
                    hitRect: self.containerView.activeHitRect,
                    hasMediaControls: self.isCollapsedMediaVisible,
                    hasLiveActivity: self.model.showsLiveActivityPill
                )
                if !inControlZone {
                    self.expand(makeKey: true)
                }
            }
        }
        containerView.onDragEnterNotch = { [weak self] in
            self?.model.isDraggingFileOverNotch = true
            self?.expand(tab: .clips, makeKey: false)
        }
        containerView.onDragExitNotch = { [weak self] in
            self?.model.isDraggingFileOverNotch = false
        }
        containerView.onDropFileURLs = { [weak self] urls in
            self?.model.isDraggingFileOverNotch = false
            self?.model.handleDroppedFilesForActions(urls)
            self?.expand(tab: .clips, makeKey: true)
        }

        updateHitRect()
    }

    private func makeRootView() -> NotchRootView {
        NotchRootView(
            model: model,
            layout: layout,
            onExpand: { [weak self] in
                self?.expand(makeKey: true)
            },
            onToggleExpand: { [weak self] in
                guard let self else { return }
                if self.model.isExpanded {
                    self.collapse(force: true)
                } else {
                    self.expand(makeKey: true)
                }
            },
            onRequestFocus: { [weak self] in
                self?.focusPanelForTyping()
            },
            onCollapse: { [weak self] in
                self?.collapse(force: true)
            },
            onShowOwlMenu: { [weak self] in
                self?.showOwlMenu()
            }
        )
    }

    private func updateHitRect() {
        let rect = layout.activeHitRectInPanel(
            isExpanded: model.isExpanded,
            isLiveActivity: model.showsLiveActivityPill
        )
        containerView.activeHitRect = rect
        if model.isExpanded {
            containerView.hoverTriggerRect = rect
        } else if model.showsLiveActivityPill {
            containerView.hoverTriggerRect = rect.insetBy(dx: 8, dy: 4)
        } else {
            // Trim outer ear flares and bottom 3pt border so cursor must genuinely sit over the pill
            containerView.hoverTriggerRect = CGRect(
                x: rect.minX + 8,
                y: rect.minY + 3,
                width: max(40, rect.width - 16),
                height: max(20, rect.height - 3)
            )
        }
    }

    private func isPointerInsideHoverTriggerRect() -> Bool {
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = panel.convertPoint(fromScreen: screenPoint)
        let localPoint = containerView.convert(windowPoint, from: nil)
        return containerView.hoverTriggerRect.contains(localPoint)
    }

    private var isCollapsedMediaVisible: Bool {
        !model.isExpanded
            && !model.showsLiveActivityPill
            && model.settings.showMediaInNotch
            && model.mediaService.currentTrack != nil
            && !(model.settings.showTimerInNotch && model.timer.state != .idle)
    }

    private func handleMouseEntered() {
        hoverCollapseTask?.cancel()
        hoverCollapseTask = nil
        guard isPointerInsideHoverTriggerRect() else {
            model.isHoveringNotch = false
            return
        }
        model.isHoveringNotch = true
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = panel.convertPoint(fromScreen: screenPoint)
        let localPoint = containerView.convert(windowPoint, from: nil)
        scheduleOrCancelHoverExpand(for: localPoint)
    }

    private func handleMouseMoved(at localPoint: NSPoint) {
        guard !model.isExpanded else { return }
        scheduleOrCancelHoverExpand(for: localPoint)
    }

    private func scheduleOrCancelHoverExpand(for localPoint: NSPoint) {
        guard model.settings.hoverToExpand, !model.isExpanded else { return }

        let inControlZone = NotchGeometry.isPointInCollapsedControlExclusionZone(
            point: localPoint,
            hitRect: containerView.activeHitRect,
            hasMediaControls: isCollapsedMediaVisible,
            hasLiveActivity: model.showsLiveActivityPill
        )
        if inControlZone {
            hoverExpandTask?.cancel()
            hoverExpandTask = nil
            return
        }

        guard hoverExpandTask == nil else { return }
        let baseDelay = max(80, model.settings.hoverDelayMs)
        let delay: Int = (model.showsLiveActivityPill || isCollapsedMediaVisible)
            ? max(baseDelay, 850)
            : baseDelay

        hoverExpandTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self else { return }
            defer { self.hoverExpandTask = nil }
            guard self.isPointerInsideHoverTriggerRect() else {
                self.model.isHoveringNotch = false
                return
            }
            let currentScreen = NSEvent.mouseLocation
            let currentWindow = self.panel.convertPoint(fromScreen: currentScreen)
            let currentLocal = self.containerView.convert(currentWindow, from: nil)
            let nowInControlZone = NotchGeometry.isPointInCollapsedControlExclusionZone(
                point: currentLocal,
                hitRect: self.containerView.activeHitRect,
                hasMediaControls: self.isCollapsedMediaVisible,
                hasLiveActivity: self.model.showsLiveActivityPill
            )
            guard !nowInControlZone else { return }
            if self.model.isHoveringNotch && !self.model.isExpanded {
                self.expand(makeKey: false)
            }
        }
    }

    private func handleMouseExited() {
        hoverExpandTask?.cancel()
        hoverExpandTask = nil
        model.isHoveringNotch = false
        guard model.isExpanded, !model.isPinned, !isTrackingMenu else { return }

        // Keep open if user is actively typing inside the panel
        if panel.isKeyWindow, panel.firstResponder is NSTextView {
            return
        }

        hoverCollapseTask?.cancel()
        hoverCollapseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            if !self.isPointerInsideHoverTriggerRect() && !self.model.isPinned && !self.isTrackingMenu {
                self.collapse()
            }
        }
    }

    private func installMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.model.isExpanded, !self.model.isPinned, !self.isTrackingMenu else { return }
                self.collapse()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            let localPoint = self.containerView.convert(event.locationInWindow, from: nil)

            if !self.model.isExpanded {
                guard self.containerView.activeHitRect.contains(localPoint) else { return event }
                if event.type == .rightMouseDown {
                    self.showOwlMenu(atContainerPoint: localPoint)
                    return nil
                }
                let mediaPillVisible = self.model.mediaService.currentTrack != nil && self.model.settings.showMediaInNotch
                if self.model.showsLiveActivityPill || mediaPillVisible {
                    // Allow Snooze / Done / Join / Media controls to handle clicks directly
                    return event
                }
                self.expand(makeKey: true)
                return nil
            }

            if !self.panel.isKeyWindow {
                self.focusPanelForTyping()
            }
            return event
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let chars = event.charactersIgnoringModifiers?.lowercased()
            if flags == .command, chars == "q" {
                NSApp.terminate(nil)
                return nil
            }
            if flags == .option, chars == "s" {
                self.model.snoozeActiveNudge(minutes: 5)
                return nil
            }
            if flags == .command, let chars {
                let primary = NotchTab.primaryTabs
                if let digit = Int(chars), digit >= 1, digit <= primary.count {
                    self.expand(tab: primary[digit - 1], makeKey: true)
                    return nil
                }
                if chars == "," {
                    self.expand(tab: .settings, makeKey: true)
                    return nil
                }
            }
            if self.model.isExpanded, event.keyCode == 53 {
                if self.model.activeUtilityOverlay != nil {
                    self.model.activeUtilityOverlay = nil
                } else {
                    self.collapse(force: true)
                }
                return nil
            }
            if self.model.isExpanded,
               self.model.activeTab == .today,
               self.model.activeUtilityOverlay == nil,
               !(self.panel.firstResponder is NSText),
               flags.isSubset(of: [.shift, .capsLock, .numericPad]),
               let typed = event.characters,
               !typed.isEmpty,
               typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && ($0.value < 0xF700 || $0.value > 0xF8FF) }) {
                self.focusPanelForTyping()
                self.model.requestWorkspaceInputFocus(seed: typed)
                return nil
            }
            return event
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.relayoutForCurrentScreen()
            }
        }

        menuBeginObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isTrackingMenu = true
                self?.hoverCollapseTask?.cancel()
            }
        }

        menuEndObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isTrackingMenu = false
            }
        }
    }

    func showOwlMenu(atContainerPoint anchorPoint: CGPoint? = nil) {
        hoverCollapseTask?.cancel()
        hoverExpandTask?.cancel()

        let menu = NSMenu()
        menuActionSelected = false

        let expandOrCollapseTitle = model.isExpanded ? "Collapse Notch" : "Open Notch Drawer"
        menu.addItem(ClosureMenuItem(title: expandOrCollapseTitle) { [weak self] in
            guard let self else { return }
            self.menuActionSelected = true
            if self.model.isExpanded {
                self.collapse(force: true)
            } else {
                self.expand(makeKey: true)
            }
        })

        let pinTitle = model.isPinned ? "Unpin Drawer" : "Pin Drawer Open"
        menu.addItem(ClosureMenuItem(title: pinTitle) { [weak self] in
            guard let self else { return }
            self.menuActionSelected = true
            if !self.model.isExpanded {
                self.model.isPinned = true
                self.expand(makeKey: true)
            } else {
                self.model.isPinned.toggle()
            }
        })

        menu.addItem(.separator())

        for tab in NotchTab.allCases {
            let item = ClosureMenuItem(title: tab == .settings ? "Settings…" : tab.title) { [weak self] in
                guard let self else { return }
                self.menuActionSelected = true
                self.expand(tab: tab, makeKey: true)
            }
            if model.isExpanded && model.activeTab == tab {
                item.state = .on
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem(title: "Quit NotchNest", keyEquivalent: "q") { [weak self] in
            self?.menuActionSelected = true
            NSApp.terminate(nil)
        })

        let expandedRect = layout.activeHitRectInPanel(isExpanded: true)
        let defaultAnchor = CGPoint(
            x: expandedRect.minX + 28,
            y: expandedRect.maxY - 38
        )
        let popPoint = anchorPoint ?? defaultAnchor

        isTrackingMenu = true
        menu.popUp(positioning: nil, at: popPoint, in: containerView)
        isTrackingMenu = false

        guard !menuActionSelected, model.isExpanded, !model.isPinned else { return }
        let hitInWindow = containerView.convert(layout.activeHitRectInPanel(isExpanded: true), to: nil)
        let hitOnScreen = panel.convertToScreen(hitInWindow)
        if !hitOnScreen.contains(NSEvent.mouseLocation) {
            collapse()
        }
    }

    private func captureExternalFrontmostApp() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApp = front
        }
    }

    private func resignPanelKeyFocus() {
        if let app = lastExternalApp, !app.isTerminated {
            app.activate()
        } else {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    private static func resolveTargetScreen(mode: DisplaySelectionMode) -> NSScreen {
        if mode == .activeMouseScreen {
            let mouseLocation = NSEvent.mouseLocation
            if let screenWithMouse = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
                return screenWithMouse
            }
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: keyEquivalent)
        self.target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
        handler()
    }
}

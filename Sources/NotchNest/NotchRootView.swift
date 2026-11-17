import NotchNestCore
import SwiftUI

struct NotchRootView: View {
    @Bindable var model: NotchNestModel
    let layout: NotchLayout
    let onExpand: () -> Void
    let onToggleExpand: () -> Void
    let onRequestFocus: () -> Void
    let onCollapse: () -> Void
    let onShowOwlMenu: () -> Void

    @State private var isHoveringHeaderOwl = false

    private static let eventTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private var activeSize: CGSize {
        if model.isExpanded {
            return layout.expandedSize
        }
        return model.showsLiveActivityPill ? layout.liveActivitySize : layout.collapsedSize
    }

    private var earRadius: CGFloat {
        if model.isExpanded {
            return 14
        }
        return model.showsLiveActivityPill ? 10 : 8
    }

    private var bottomRadius: CGFloat {
        if model.isExpanded {
            return 24
        }
        return model.showsLiveActivityPill ? 18 : 11
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear

            ZStack(alignment: .top) {
                NotchSilhouetteShape(
                    topEarRadius: earRadius,
                    bottomCornerRadius: bottomRadius
                )
                .fill(model.isExpanded ? NotchTheme.obsidianBg : NotchTheme.notchBlack)
                .overlay(
                    NotchSilhouetteShape(
                        topEarRadius: earRadius,
                        bottomCornerRadius: bottomRadius
                    )
                    .stroke(
                        Color.white.opacity(model.isExpanded ? 0.13 : 0.11),
                        lineWidth: 1
                    )
                )
                .shadow(
                    color: .black.opacity(model.isExpanded ? 0.62 : 0.42),
                    radius: model.isExpanded ? 22 : 8,
                    x: 0,
                    y: model.isExpanded ? 12 : 3
                )

                if model.isExpanded {
                    expandedContent
                        .padding(.horizontal, earRadius + 14)
                        .padding(.top, layout.hasHardwareNotch ? max(10, layout.topSafeHeaderHeight - 22) : 11)
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                } else if model.showsLiveActivityPill {
                    liveActivityContent
                        .padding(.horizontal, earRadius + 10)
                        .padding(.vertical, 7)
                        .allowsHitTesting(!model.isExpanded)
                        .transition(.opacity)
                } else {
                    collapsedContent
                        .padding(.horizontal, earRadius + 10)
                        .allowsHitTesting(!model.isExpanded)
                        .transition(.opacity)
                }
            }
            .frame(width: activeSize.width, height: activeSize.height)
            .clipShape(
                NotchSilhouetteShape(
                    topEarRadius: earRadius,
                    bottomCornerRadius: bottomRadius
                )
            )
            .animation(.spring(response: 0.34, dampingFraction: 0.80), value: model.isExpanded)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: model.showsLiveActivityPill)
            .animation(.spring(response: 0.28, dampingFraction: 0.84), value: model.transientLiveActivity?.id)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: layout.expandedSize)
        }
        .frame(width: layout.panelFrame.width, height: layout.panelFrame.height, alignment: .top)
        .preferredColorScheme(.dark)
    }

    // MARK: - Compact Collapsed Pill

    private var collapsedContent: some View {
        let track = model.settings.showMediaInNotch ? model.mediaService.currentTrack : nil

        return HStack(spacing: 6) {
            HStack(spacing: 6) {
                if let track, let artData = track.artworkData, let nsImage = NSImage(data: artData) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    OwlBadgeView(
                        size: 18,
                        isFocusing: model.timer.state == .running,
                        isHovering: model.isHoveringNotch,
                        pulse: model.lastTaskCompletedPulse,
                        animationsEnabled: model.settings.owlAnimationEnabled
                    )
                }

                if !layout.hasHardwareNotch {
                    Text(collapsedCenterText)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                onExpand()
            }

            collapsedRightBadge(track: track)

            if model.settings.showMicIndicatorInNotch,
               model.systemService.hasAudioInputDevice,
               model.systemService.isMicMuted {
                Button {
                    model.toggleMicMuteWithHUD()
                } label: {
                    Image(systemName: "mic.slash.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(NotchTheme.coralAlert)
                        .frame(width: 20, height: 20)
                        .background(NotchTheme.coralAlert.opacity(0.20), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Microphone muted (⌥M to unmute)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var collapsedCenterText: String {
        if let activeTask = model.activeFocusTask, model.timer.state == .running {
            return activeTask.title
        }
        if model.settings.showMediaInNotch,
           let track = model.mediaService.currentTrack,
           track.isPlaying {
            return track.title
        }
        if model.settings.showNextEventInNotch,
           let nextEvent = model.eventKit.upcomingEvents.first,
           nextEvent.startDate.timeIntervalSinceNow < 3600 * 3 && nextEvent.endDate > Date() {
            return nextEvent.title
        }
        return model.isHoveringNotch ? "Open NotchNest" : "NotchNest"
    }

    @ViewBuilder
    private func collapsedRightBadge(track: NowPlayingInfo?) -> some View {
        if model.settings.showTimerInNotch && model.timer.state != .idle {
            HStack(spacing: 5) {
                Text(model.timer.formattedRemaining)
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)

                AnimatedWaveformView(
                    isActive: model.timer.state == .running,
                    barColor: model.timer.state == .running ? NotchTheme.skyWave : NotchTheme.peachAction,
                    barWidth: 2,
                    maxHeight: 10,
                    spacing: 1.8
                )
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.08), in: Capsule())
        } else if let track {
            HStack(spacing: 5) {
                if model.isHoveringNotch {
                    if layout.collapsedSize.width >= 200 {
                        Button {
                            model.mediaService.previousTrack()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.88))
                                .frame(width: 18, height: 18)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        model.mediaService.togglePlayPause()
                    } label: {
                        Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.16), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.mediaService.nextTrack()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.88))
                            .frame(width: 20, height: 20)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                AnimatedWaveformView(
                    isActive: track.isPlaying,
                    barColor: NotchTheme.peachAction,
                    barWidth: 2,
                    maxHeight: 11,
                    spacing: 1.8
                )
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .onTapGesture {}
        } else if model.settings.showNextEventInNotch,
                  let nextEvent = model.eventKit.upcomingEvents.first,
                  nextEvent.startDate.timeIntervalSinceNow < 3600 * 3 && nextEvent.endDate > Date() {
            Text(nextEvent.statusLabel(relativeTo: Date()))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(NotchTheme.peachAction)
                .lineLimit(1)
        } else if model.openTaskCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "checklist")
                    .font(.system(size: 9.5, weight: .semibold))
                Text("\(model.openTaskCount)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.75))
        }
    }

    // MARK: - Live Activity Nudge Card

    @ViewBuilder
    private var liveActivityContent: some View {
        if let transient = model.transientLiveActivity {
            transientLiveActivityCard(transient)
        } else {
            persistentLiveActivityCard
        }
    }

    private func transientLiveActivityCard(_ transient: TransientLiveActivity) -> some View {
        let accent = Color(hex: transient.accentHex)
        return HStack(spacing: 9) {
            if transient.category == .media,
               let artData = model.mediaService.currentTrack?.artworkData,
               let nsImg = NSImage(data: artData) {
                Image(nsImage: nsImg)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.22))
                        .frame(width: 32, height: 32)
                    Image(systemName: transient.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(transient.title)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let badge = transient.badgeText {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(accent, in: Capsule())
                    }
                }

                Text(transient.subtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if transient.category == .media || transient.category == .pomodoro {
                AnimatedWaveformView(
                    isActive: true,
                    barColor: accent,
                    barWidth: 2,
                    maxHeight: 12,
                    spacing: 1.8
                )
            }

            Button {
                model.dismissTransientLiveActivity()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if let hub = transient.targetHubSection {
                model.selectedHubSection = hub
            }
            if let tab = transient.targetTab {
                model.activeTab = tab
            }
            model.dismissTransientLiveActivity()
            onExpand()
        }
    }

    @ViewBuilder
    private var persistentLiveActivityCard: some View {
        let isEyeBreak = model.healthService.isEyeBreakDue
        let task = isEyeBreak ? nil : model.activeLiveNudgeTask
        let event = (isEyeBreak || task != nil) ? nil : model.activeLiveNudgeEvent

        let title = isEyeBreak ? "20-20-20 Eye Break" : (task?.title ?? event?.title ?? "Up Next")
        let subtitle: String = {
            if isEyeBreak {
                return "Look 20 ft · \(model.healthService.eyeRestSecondsRemaining)s"
            }
            if let due = task?.dueDate {
                return Self.eventTimeFormatter.string(from: due)
            }
            if let event {
                return event.statusLabel(relativeTo: Date())
            }
            return "Active nudge"
        }()

        let joinURL = isEyeBreak ? nil : (event?.meetingURL ?? task?.detectedMeetingURL)
        let joinTitle: String = {
            if let service = event?.meetingServiceLabel {
                return "Join \(service)"
            }
            if let url = joinURL {
                return "Join \(MeetingLinkExtractor.serviceLabel(for: url))"
            }
            return "Join Call"
        }()

        HStack(spacing: 9) {
            Button(action: onExpand) {
                OwlBadgeView(
                    size: 32,
                    isFocusing: model.timer.state == .running,
                    isHovering: model.isHoveringNotch,
                    pulse: model.lastTaskCompletedPulse,
                    animationsEnabled: model.settings.owlAnimationEnabled,
                    showAlertDot: true
                )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onExpand()
                }

                HStack(spacing: 6) {
                    Button {
                        model.snoozeActiveNudge(minutes: 5)
                    } label: {
                        Label("5 min", systemImage: "zzz")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    if let joinURL {
                        Button {
                            model.joinMeeting(url: joinURL, title: title)
                        } label: {
                            Label(joinTitle, systemImage: "video.fill")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(NotchTheme.peachAction, in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            _ = model.openOrCreateMeetingNote(title: title, switchToNotes: true)
                            onExpand()
                        } label: {
                            Image(systemName: "note.text")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.88))
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Open Meeting Prep Note")

                        Button {
                            model.activeTab = .mirror
                            model.updateMirrorActivation()
                            onExpand()
                        } label: {
                            Image(systemName: "person.crop.viewfinder")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(NotchTheme.skyWave)
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.14), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Pre-Call Camera Check")
                    } else {
                        Button {
                            model.completeActiveNudge()
                        } label: {
                            Label("Done", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 3)
                                .background(NotchTheme.peachAction, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Expanded Drawer Header & Body

    private var expandedContent: some View {
        ZStack {
            VStack(spacing: 10) {
                headerBar
                Divider().overlay(Color.white.opacity(0.08))
                tabBody
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            if let overlay = model.activeUtilityOverlay {
                Color.black.opacity(0.45)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .onTapGesture {
                        model.activeUtilityOverlay = nil
                    }

                switch overlay {
                case .wrapUp:
                    WrapUpOverlayView(model: model) {
                        model.activeUtilityOverlay = nil
                    }
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                case .diagnostics:
                    DiagnosticsOverlayView(
                        model: model,
                        onDismiss: {
                            model.activeUtilityOverlay = nil
                        },
                        onCollapseAndPreview: {
                            onCollapse()
                        }
                    )
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
        }
        .animation(.easeOut(duration: 0.16), value: model.activeUtilityOverlay)
    }

    private var headerBar: some View {
        HStack(spacing: 7) {
            Button(action: onShowOwlMenu) {
                HStack(spacing: 6) {
                    OwlBadgeView(
                        size: 23,
                        isFocusing: model.timer.state == .running,
                        isHovering: model.isHoveringNotch || isHoveringHeaderOwl,
                        pulse: model.lastTaskCompletedPulse,
                        animationsEnabled: model.settings.owlAnimationEnabled
                    )

                    Text("NotchNest")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.95))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(isHoveringHeaderOwl ? 0.09 : 0.0))
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isHoveringHeaderOwl = hovering
            }
            .help("NotchNest Menu (Pin, Settings, Quit)")

            // Unified quick utility capsule matching the screenshot toolbar
            HStack(spacing: 3) {
                Button {
                    model.activeUtilityOverlay = nil
                    model.activeTab = (model.activeTab == .clips) ? .today : .clips
                    model.updateMirrorActivation()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("Clips")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        if !model.clips.isEmpty {
                            Text("\(model.clips.count)")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 0.5)
                                .background(Color.black.opacity(0.28), in: Capsule())
                        }
                    }
                    .foregroundStyle(model.activeTab == .clips ? .black : .white.opacity(0.85))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule()
                            .fill(model.activeTab == .clips ? NotchTheme.sagePaper : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help("Clips & Screenshots")

                toolbarCapsuleIcon(
                    systemName: "person.crop.viewfinder",
                    isActive: model.activeTab == .mirror,
                    activeTint: NotchTheme.skyWave,
                    helpText: "Pre-call Camera Mirror"
                ) {
                    model.activeUtilityOverlay = nil
                    model.activeTab = (model.activeTab == .mirror) ? .today : .mirror
                    model.updateMirrorActivation()
                }

                toolbarCapsuleIcon(
                    systemName: "moon.fill",
                    isActive: model.activeUtilityOverlay == .wrapUp,
                    activeTint: NotchTheme.lavenderSoft,
                    helpText: "Daily Wrap Up & Plan Tomorrow"
                ) {
                    model.activeUtilityOverlay = (model.activeUtilityOverlay == .wrapUp) ? nil : .wrapUp
                }

                toolbarCapsuleIcon(
                    systemName: model.settings.isWideDrawer ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    isActive: model.settings.isWideDrawer,
                    activeTint: NotchTheme.sagePaper,
                    helpText: model.settings.isWideDrawer ? "Standard Drawer Size" : "Expand Wide Drawer"
                ) {
                    model.settings.isWideDrawer.toggle()
                }

                toolbarCapsuleIcon(
                    systemName: "ladybug",
                    isActive: model.activeUtilityOverlay == .diagnostics,
                    activeTint: NotchTheme.peachAction,
                    helpText: "Diagnostics & Quick Tools"
                ) {
                    model.activeUtilityOverlay = (model.activeUtilityOverlay == .diagnostics) ? nil : .diagnostics
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.07), in: Capsule())

            Spacer(minLength: 4)

            if model.timer.state != .idle {
                Button {
                    model.activeUtilityOverlay = nil
                    model.activeTab = .timer
                    model.updateMirrorActivation()
                } label: {
                    HStack(spacing: 5) {
                        Text(model.timer.formattedRemaining)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                        AnimatedWaveformView(
                            isActive: model.timer.state == .running,
                            barColor: NotchTheme.skyWave,
                            barWidth: 2,
                            maxHeight: 10,
                            spacing: 1.5
                        )
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.09), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 2) {
                ForEach(NotchTab.primaryTabs) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.06), in: Capsule())

            iconButton(
                systemName: model.isPinned ? "pin.fill" : "pin",
                tint: model.isPinned ? NotchTheme.peachAction : .white.opacity(0.68),
                helpText: model.isPinned ? "Unpin drawer" : "Pin drawer open"
            ) {
                model.isPinned.toggle()
            }

            iconButton(
                systemName: "gearshape",
                tint: model.activeTab == .settings ? NotchTheme.sagePaper : .white.opacity(0.7),
                helpText: "Settings"
            ) {
                model.activeUtilityOverlay = nil
                model.activeTab = (model.activeTab == .settings) ? .today : .settings
                model.updateMirrorActivation()
            }

            iconButton(
                systemName: "xmark",
                tint: .white.opacity(0.7),
                helpText: "Collapse (Esc)"
            ) {
                onCollapse()
            }
        }
        .frame(height: 28)
    }

    private func toolbarCapsuleIcon(
        systemName: String,
        isActive: Bool,
        activeTint: Color,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isActive ? activeTint : .white.opacity(0.76))
                .frame(width: 22, height: 21)
                .background(
                    Circle()
                        .fill(isActive ? Color.white.opacity(0.12) : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func tabButton(for tab: NotchTab) -> some View {
        let isSelected = model.activeTab == tab
        return Button {
            model.activeUtilityOverlay = nil
            model.activeTab = tab
            model.updateMirrorActivation()
        } label: {
            Text(tab.title)
                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
                .padding(.horizontal, 6.5)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? NotchTheme.elevatedSurface : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private func iconButton(
        systemName: String,
        tint: Color,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    @ViewBuilder
    private var tabBody: some View {
        switch model.activeTab {
        case .today:
            TodayTabView(model: model, onRequestFocus: onRequestFocus)
        case .week:
            WeekTabView(model: model, onRequestFocus: onRequestFocus)
        case .hub:
            HubTabView(model: model, onRequestFocus: onRequestFocus, onCollapse: onCollapse)
        case .timer:
            TimerTabView(model: model)
        case .notes:
            NotesTabView(model: model, onRequestFocus: onRequestFocus)
        case .insights:
            InsightsTabView(model: model)
        case .clips:
            ClipsTabView(model: model)
        case .mirror:
            MirrorTabView(model: model)
        case .settings:
            SettingsTabView(model: model)
        }
    }
}

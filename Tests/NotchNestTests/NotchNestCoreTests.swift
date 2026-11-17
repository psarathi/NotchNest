import AppKit
import Foundation
import Testing
@testable import NotchNestCore

@Suite("NotchNestCore Tests")
struct NotchNestCoreTests {

    @Test("Virtual notch layout centers cleanly at top edge on Intel non-notched displays")
    func intelDisplayLayout() {
        let screen = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
        )
        let layout = NotchGeometry.computeLayout(for: screen, preferredCollapsedWidth: 216)

        #expect(!layout.hasHardwareNotch)
        #expect(layout.collapsedSize.width == 216)
        #expect(layout.collapsedSize.height == 29)
        #expect(layout.expandedSize.width == 780)
        #expect(layout.expandedSize.height == 448)
        #expect(layout.panelFrame.maxY == 900)
        #expect(abs(layout.panelFrame.midX - 720) < 0.01)

        let collapsedHit = layout.activeHitRectInPanel(isExpanded: false)
        #expect(collapsedHit.width == 216)
        #expect(collapsedHit.maxY == layout.panelFrame.height)

        let expandedHit = layout.activeHitRectInPanel(isExpanded: true)
        #expect(expandedHit.width == 780)
        #expect(expandedHit.height == 448)
    }

    @Test("Hardware-notched display layout accommodates physical notch width")
    func notchedDisplayLayout() {
        let screen = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaTop: 38,
            auxiliaryTopLeft: CGRect(x: 0, y: 944, width: 650, height: 38),
            auxiliaryTopRight: CGRect(x: 862, y: 944, width: 650, height: 38)
        )
        let layout = NotchGeometry.computeLayout(for: screen, preferredCollapsedWidth: 200)

        #expect(layout.hasHardwareNotch)
        // 1512 - 650 - 650 = 212 hardware notch + 88 wing padding = 300
        #expect(layout.collapsedSize.width == 300)
        #expect(layout.collapsedSize.height == 38)
    }

    @Test("Meeting link extractor prioritizes explicit URL and known conferencing hosts")
    func meetingLinkExtraction() {
        let zoom = URL(string: "https://us02web.zoom.us/j/123456789")!
        #expect(
            MeetingLinkExtractor.extractMeetingURL(
                explicitURL: zoom,
                location: "Conference Room",
                notes: nil
            ) == zoom
        )

        let meetFromNotes = MeetingLinkExtractor.extractMeetingURL(
            explicitURL: nil,
            location: "Online",
            notes: "Docs: https://example.com/agenda\nJoin call: https://meet.google.com/abc-defg-hij"
        )
        #expect(meetFromNotes?.absoluteString == "https://meet.google.com/abc-defg-hij")

        let nonMeeting = MeetingLinkExtractor.extractMeetingURL(
            explicitURL: nil,
            location: nil,
            notes: "Read https://example.com/post before lunch"
        )
        #expect(nonMeeting == nil)

        let zoomMtg = MeetingLinkExtractor.extractMeetingURL(
            explicitURL: nil,
            location: "zoommtg://zoom.us/join?confno=987654321",
            notes: nil
        )
        #expect(zoomMtg != nil)
        #expect(zoomMtg.map(MeetingLinkExtractor.serviceLabel(for:)) == "Zoom")

        let safeLink = MeetingLinkExtractor.extractMeetingURL(
            explicitURL: nil,
            location: nil,
            notes: "Join: https://nam12.safelinks.protection.outlook.com/?url=https%3A%2F%2Fus06web.zoom.us%2Fj%2F555111222"
        )
        #expect(safeLink?.host == "us06web.zoom.us")
        #expect(safeLink.map(MeetingLinkExtractor.serviceLabel(for:)) == "Zoom")
    }

    @Test("Focus timer counts down against wall clock and completes cleanly")
    @MainActor
    func focusTimerLifecycle() {
        final class ClockBox: @unchecked Sendable {
            var current = Date(timeIntervalSince1970: 1_000_000)
        }
        let clock = ClockBox()

        let engine = FocusTimerEngine(focusMinutes: 25) {
            clock.current
        }

        var completedPhase: TimerPhase?
        var completedMinutes: Int?
        engine.onPhaseComplete = { phase, mins in
            completedPhase = phase
            completedMinutes = mins
        }

        #expect(engine.state == .idle)
        #expect(engine.formattedRemaining == "25:00")

        engine.start()
        #expect(engine.state == .running)

        clock.current = clock.current.addingTimeInterval(600)
        engine.tick()
        #expect(engine.formattedRemaining == "15:00")
        #expect(abs(engine.progress - 0.4) < 0.01)

        engine.pause()
        #expect(engine.state == .paused)

        // Advancing wall clock while paused does not burn timer
        clock.current = clock.current.addingTimeInterval(300)
        engine.tick()
        #expect(engine.formattedRemaining == "15:00")

        engine.resume()
        clock.current = clock.current.addingTimeInterval(900)
        engine.tick()

        #expect(engine.state == .idle)
        #expect(completedPhase == .focus)
        #expect(completedMinutes == 25)
    }

    @Test("Persistence store round-trips tasks, notes, settings, and daily stats")
    @MainActor
    func persistenceRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchNestTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = PersistenceStore(baseDirectory: tempDir)
        let model = NotchNestModel(persistence: store, enableSystemIntegrations: false)

        model.addTask(title: "Build Intel notch app", priority: .high)
        model.addTask(title: "Test hover expansion")
        #expect(model.openTaskCount == 2)

        model.toggleTask(model.tasks[0].id)
        #expect(model.openTaskCount == 1)

        let noteID = model.notes[0].id
        model.updateNoteBody(noteID, body: "First line title\nDetails here")
        model.settings.collapsedWidth = 240

        let reloaded = NotchNestModel(persistence: PersistenceStore(baseDirectory: tempDir), enableSystemIntegrations: false)
        #expect(reloaded.tasks.count == 2)
        #expect(reloaded.openTaskCount == 1)
        #expect(reloaded.notes[0].body == "First line title\nDetails here")
        #expect(reloaded.settings.collapsedWidth == 240)
    }

    @Test("Clips filter accepts recent images/videos and skips hidden or old files")
    func clipsFiltering() {
        let now = Date()
        let cutoff = now.addingTimeInterval(-3600)

        #expect(ClipsFilter.isCaptureCandidate(
            url: URL(fileURLWithPath: "/tmp/Screenshot 2026-11-15.png"),
            createdAt: now,
            cutoffDate: cutoff
        ))
        #expect(!ClipsFilter.isCaptureCandidate(
            url: URL(fileURLWithPath: "/tmp/.DS_Store"),
            createdAt: now,
            cutoffDate: cutoff
        ))
        #expect(!ClipsFilter.isCaptureCandidate(
            url: URL(fileURLWithPath: "/tmp/old.png"),
            createdAt: now.addingTimeInterval(-7200),
            cutoffDate: cutoff
        ))
        #expect(!ClipsFilter.isCaptureCandidate(
            url: URL(fileURLWithPath: "/tmp/archive.zip"),
            createdAt: now,
            cutoffDate: cutoff
        ))
    }

    @Test("Natural language parser extracts day, time, project tag, priority, and recurrence")
    func naturalLanguageParsing() {
        let cal = Calendar(identifier: .gregorian)
        var refComps = DateComponents()
        refComps.year = 2026
        refComps.month = 11
        refComps.day = 15
        refComps.hour = 10
        refComps.minute = 0
        let ref = cal.date(from: refComps)!

        let parsed = NaturalLanguageTaskParser.parse(
            "Prep slides for design review tomorrow 5:30pm #Work high priority every weekday",
            referenceDate: ref,
            calendar: cal
        )

        #expect(parsed.title == "Prep slides for design review")
        #expect(parsed.scheduledBucket == .tomorrow)
        #expect(parsed.projectTag == "Work")
        #expect(parsed.priority == .high)
        #expect(parsed.recurrence == .weekdays)
        #expect(parsed.hasStructuredMetadata)
        #expect(parsed.dueDate != nil)
        if let due = parsed.dueDate {
            #expect(cal.component(.day, from: due) == 16)
            #expect(cal.component(.hour, from: due) == 17)
            #expect(cal.component(.minute, from: due) == 30)
        }
        #expect(parsed.previewSummary(relativeTo: ref, calendar: cal)?.contains("Tomorrow, 5:30 PM") == true)
    }

    @Test("Live activity nudge, snooze, week move, note conversion, and insights tracking")
    @MainActor
    func workflowAndInsights() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchNestWorkflowTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = NotchNestModel(persistence: PersistenceStore(baseDirectory: tempDir), enableSystemIntegrations: false)

        // Task due in 5 minutes triggers Live Activity pill until snoozed
        model.addTask(title: "Join sync", bucket: .today, dueDate: Date().addingTimeInterval(300))
        #expect(model.showsLiveActivityPill)
        #expect(model.activeLiveNudgeTask?.title == "Join sync")

        model.snoozeActiveNudge(minutes: 5)
        #expect(!model.showsLiveActivityPill)

        // Week kanban reschedule & edit/delete
        let taskID = model.tasks[0].id
        model.moveTask(taskID, to: .tomorrow)
        #expect(model.tasks(in: .tomorrow).count == 1)
        #expect(model.tasks(in: .today).isEmpty)

        model.updateTask(taskID, title: "Updated call", priority: .high, bucket: .inbox)
        #expect(model.tasks(in: .inbox).first?.title == "Updated call")
        #expect(model.tasks(in: .inbox).first?.priority == .high)

        model.deleteTask(taskID)
        #expect(model.tasks.isEmpty)

        // Soundscape selection starts & switches preview cleanly when timer idle
        model.selectSoundscape(.ocean)
        #expect(model.settings.focusSoundscape == .ocean)
        #expect(model.isAmbientPreviewActive)
        model.selectSoundscape(.none)
        #expect(!model.isAmbientPreviewActive)

        // Note-to-task extraction
        let noteID = model.notes[0].id
        model.updateNoteBody(noteID, body: "- Call mom\n- Review PR #Work")
        let created = model.convertNoteLinesToTasks(noteID)
        #expect(created == 2)
        #expect(model.tasks(in: .today).count == 2)

        // Completion updates Insights history
        model.toggleTask(model.tasks(in: .today)[0].id)
        #expect(model.totalCompletedTasksMetric >= 1)
        #expect(model.currentStreakDays >= 1)
        // Wide layout expansion
        let screen = ScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875)
        )
        let wideLayout = NotchGeometry.computeLayout(for: screen, preferredCollapsedWidth: 188, isWideDrawer: true)
        #expect(wideLayout.expandedSize.width == 940)
        #expect(wideLayout.expandedSize.height == 520)

        // Full 7-day week columns & day-specific mid-week scheduling (no lump onto last day)
        let columns = model.weekPlanColumns()
        #expect(columns.count == 9) // Inbox + 7 days + Later

        let thursdayKey = model.dayKey(forDayOffset: 4)!
        let thursdayCol = columns[5] // index 0 = inbox, 1 = today(+0), 5 = +4
        #expect(thursdayCol.dayKey == thursdayKey)

        model.addParsedTask("Dentist checkup", defaultBucket: thursdayCol.bucket, defaultDayKey: thursdayCol.dayKey)
        #expect(model.tasks(forColumn: thursdayCol).contains(where: { $0.title == "Dentist checkup" }))
        #expect(model.tasks(forColumn: .later).isEmpty)

        let wednesdayParsed = NaturalLanguageTaskParser.parse(
            "Review slides Wednesday",
            referenceDate: Date(),
            calendar: Calendar.current
        )
        #expect(wednesdayParsed.title == "Review slides")
        #expect(wednesdayParsed.scheduledDayKey != nil)

        // Day activity dot & Wrap-up Move to Tomorrow
        let today = Date()
        model.addTask(title: "Evening sync https://us02web.zoom.us/j/12345", bucket: .today, dueDate: today)
        #expect(model.dayHasActivity(today))
        #expect(model.timedTasks(on: today).first?.detectedMeetingURL?.host == "us02web.zoom.us")
        let movedCount = model.moveIncompleteTodayToTomorrow()
        #expect(movedCount == 2)
        #expect(model.tasks(in: .tomorrow).count == 2)
    }

    @Test("Focus audio engine starts, switches soundscapes, and stops without actor-isolation traps")
    @MainActor
    func focusAudioLifecycle() async {
        let engine = FocusAudioEngine()
        for sound in [FocusSoundscape.rain, .brownNoise, .ocean, .cafe] {
            engine.update(soundscape: sound, shouldPlay: true, volume: 0.35)
            try? await Task.sleep(for: .milliseconds(120))
        }
        engine.stop()
        #expect(!engine.isPlaying)
    }

    @Test("Window snap zone geometry maps AppKit and Accessibility frames cleanly")
    func windowSnapGeometry() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 862)
        let primaryMaxY: CGFloat = 900 // 38pt menu bar

        let leftHalfAppKit = WindowSnapService.targetAppKitFrame(for: .leftHalf, visibleFrame: visible)
        #expect(leftHalfAppKit == CGRect(x: 0, y: 0, width: 720, height: 862))

        let leftHalfAX = WindowSnapService.accessibilityFrame(for: .leftHalf, visibleFrame: visible, primaryScreenMaxY: primaryMaxY)
        #expect(leftHalfAX == CGRect(x: 0, y: 38, width: 720, height: 862))

        let bottomRightAppKit = WindowSnapService.targetAppKitFrame(for: .bottomRightQuarter, visibleFrame: visible)
        #expect(bottomRightAppKit == CGRect(x: 720, y: 0, width: 720, height: 431))

        let bottomRightAX = WindowSnapService.accessibilityFrame(for: .bottomRightQuarter, visibleFrame: visible, primaryScreenMaxY: primaryMaxY)
        #expect(bottomRightAX == CGRect(x: 720, y: 469, width: 720, height: 431))

        let rightThird = WindowSnapService.targetAppKitFrame(for: .rightThird, visibleFrame: visible)
        #expect(rightThird.minX == 960)
        #expect(rightThird.width == 480)
    }

    @Test("Health wellbeing service persists water, breaks, mindful minutes, and eye-break state")
    @MainActor
    func healthWellbeingPersistence() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchNestHealthTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = PersistenceStore(baseDirectory: tempDir)
        let service = HealthWellbeingService(persistence: store)
        defer { service.stop() }

        service.adjustWater(3)
        service.adjustWater(-1)
        service.recordBreak(mindfulMinutes: 4)
        service.triggerEyeBreakNow()

        #expect(service.stats.waterGlasses == 2)
        #expect(service.stats.breaksTaken == 1)
        #expect(service.stats.mindfulMinutes == 4)
        #expect(service.stats.streakDays == 1)
        #expect(service.isEyeBreakDue)

        service.completeEyeBreak()
        #expect(!service.isEyeBreakDue)
        #expect(service.stats.breaksTaken == 2)

        let reloaded = HealthWellbeingService(persistence: PersistenceStore(baseDirectory: tempDir))
        defer { reloaded.stop() }
        #expect(reloaded.stats.waterGlasses == 2)
        #expect(reloaded.stats.breaksTaken == 2)
        #expect(reloaded.stats.mindfulMinutes == 4)
    }

    @Test("ScreenTime category classification groups apps accurately")
    func screenTimeCategories() {
        #expect(ScreenTimeService.classifyCategory(bundleID: "com.apple.dt.Xcode", name: "Xcode") == "Development")
        #expect(ScreenTimeService.classifyCategory(bundleID: "com.google.Chrome", name: "Google Chrome") == "Browser")
        #expect(ScreenTimeService.classifyCategory(bundleID: "us.zoom.xos", name: "zoom.us") == "Communication")
        #expect(ScreenTimeService.classifyCategory(bundleID: "com.spotify.client", name: "Spotify") == "Media & Design")
        #expect(ScreenTimeService.classifyCategory(bundleID: "com.apple.Notes", name: "Notes") == "Productivity")
    }

    @Test("Drop action executor archives files to Zip and converts images to JPG and PNG")
    func dropActionArchiveAndConvert() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchNestDropTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a tiny 8x8 PNG via AppKit bitmap rep
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 8,
            pixelsHigh: 8,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let pngData = rep.representation(using: .png, properties: [:])!
        let samplePNG = tempDir.appendingPathComponent("sample.png")
        try pngData.write(to: samplePNG)

        let jpgOutputs = try DropActionExecutor.convertImages([samplePNG], to: .jpeg, fileExtension: "jpg")
        #expect(jpgOutputs.count == 1)
        #expect(jpgOutputs[0].pathExtension == "jpg")
        #expect(FileManager.default.fileExists(atPath: jpgOutputs[0].path))

        let zipURL = try DropActionExecutor.createZipArchive(from: [samplePNG, jpgOutputs[0]])
        #expect(zipURL.pathExtension == "zip")
        #expect(FileManager.default.fileExists(atPath: zipURL.path))
    }

    @Test("AppSettings preserves backward-compatible decoding and hub settings round-trip")
    func settingsBackwardCompatibility() throws {
        // Simulate older persisted JSON lacking newer AppSettings keys
        let legacyJSON = Data(#"{"hoverToExpand":false,"focusMinutes":45}"#.utf8)
        let decodedLegacy = try JSONDecoder().decode(AppSettings.self, from: legacyJSON)
        #expect(decodedLegacy.hoverToExpand == false)
        #expect(decodedLegacy.focusMinutes == 45)
        #expect(decodedLegacy.showMediaInNotch == true)
        #expect(decodedLegacy.hideInScreenCapture == false)
        #expect(decodedLegacy.weatherUnit == .fahrenheit)

        var custom = AppSettings()
        custom.hideInScreenCapture = true
        custom.preventSleepEnabled = true
        custom.weatherCity = "Tokyo"
        custom.weatherUnit = .celsius
        custom.appLanguage = .ja
        custom.snapOnTopEdgeDrag = true

        let encoded = try JSONEncoder().encode(custom)
        let roundTripped = try JSONDecoder().decode(AppSettings.self, from: encoded)
        #expect(roundTripped == custom)
    }

    @Test("Transient Live Activity popups activate collapsed notch pill and respect settings")
    @MainActor
    func transientLiveActivities() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchNestLiveActivityTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = NotchNestModel(persistence: PersistenceStore(baseDirectory: tempDir), enableSystemIntegrations: false)
        defer { model.shutdown() }

        #expect(!model.showsLiveActivityPill)

        model.postTransientLiveActivity(
            TransientLiveActivity(
                category: .bluetooth,
                title: "AirPods Pro Connected",
                subtitle: "Battery 88%",
                badgeText: "88%",
                symbolName: "airpodspro"
            )
        )
        #expect(model.transientLiveActivity?.category == .bluetooth)
        #expect(model.showsLiveActivityPill)

        model.dismissTransientLiveActivity()
        #expect(model.transientLiveActivity == nil)
        #expect(!model.showsLiveActivityPill)

        model.settings.showTransientLiveActivities = false
        model.postTransientLiveActivity(
            TransientLiveActivity(
                category: .systemHUD,
                title: "Never Sleep On",
                subtitle: "Keeping awake",
                symbolName: "cup.and.saucer.fill"
            )
        )
        #expect(model.transientLiveActivity == nil)
    }

    @Test("Media playback parses Spotify notification payloads and AppleScript descriptors cleanly")
    func mediaPlaybackParsing() {
        let playing = MediaPlaybackService.parseNotificationUserInfo(
            appName: "Spotify",
            userInfo: [
                "Player State": "Playing",
                "Name": "The Model - 2009 Remaster",
                "Artist": "Kraftwerk",
                "Album": "The Man-Machine (2009 Remaster)",
                "Artwork URL": "https://i.scdn.co/image/test"
            ]
        )
        #expect(playing?.info.appName == "Spotify")
        #expect(playing?.info.title == "The Model - 2009 Remaster")
        #expect(playing?.info.artist == "Kraftwerk")
        #expect(playing?.info.isPlaying == true)
        #expect(playing?.artworkURL == "https://i.scdn.co/image/test")

        let stopped = MediaPlaybackService.parseNotificationUserInfo(
            appName: "Spotify",
            userInfo: ["Player State": "Stopped", "Name": "Track"]
        )
        #expect(stopped == nil)

        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(boolean: true), at: 1)
        list.insert(NSAppleEventDescriptor(string: "Autobahn"), at: 2)
        list.insert(NSAppleEventDescriptor(string: "Kraftwerk"), at: 3)
        list.insert(NSAppleEventDescriptor(string: "Autobahn"), at: 4)
        list.insert(NSAppleEventDescriptor(string: "https://i.scdn.co/image/art"), at: 5)
        let parsedDesc = MediaPlaybackService.parseAppleScriptDescriptor(list, appName: "Spotify")
        #expect(parsedDesc?.info.isPlaying == true)
        #expect(parsedDesc?.info.title == "Autobahn")
        #expect(parsedDesc?.artworkURL == "https://i.scdn.co/image/art")
    }

    @Test("YouTube Music payload parser, player preference round-trip, and workspace focus seed work cleanly")
    @MainActor
    func youTubeMusicAndWorkspaceTypingFocus() throws {
        let richJSON = #"{"playing":true,"t":"Midnight City","a":"M83 • Hurry Up, We're Dreaming","alb":"Hurry Up","art":"https://lh3.googleusercontent.com/cover"}"#
        let rich = MediaPlaybackService.parseYouTubeMusicPayload(tabTitle: "Midnight City - YouTube Music", jsJSON: richJSON)
        #expect(rich?.info.appName == "YouTube Music")
        #expect(rich?.info.title == "Midnight City")
        #expect(rich?.info.artist == "M83")
        #expect(rich?.info.isPlaying == true)
        #expect(rich?.artworkURL == "https://lh3.googleusercontent.com/cover")
        #expect(rich?.hasRichMetadata == true)

        let titleOnly = MediaPlaybackService.parseYouTubeMusicPayload(tabTitle: "Time - Hans Zimmer - YouTube Music", jsJSON: nil)
        #expect(titleOnly?.info.title == "Time - Hans Zimmer")
        #expect(titleOnly?.hasRichMetadata == false)

        let homepage = MediaPlaybackService.parseYouTubeMusicPayload(tabTitle: "YouTube Music", jsJSON: nil)
        #expect(homepage == nil)

        var settings = AppSettings()
        settings.preferredMusicPlayer = .youTubeMusic
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded.preferredMusicPlayer == .youTubeMusic)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchNestFocusSeedTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = NotchNestModel(persistence: PersistenceStore(baseDirectory: tempDir), enableSystemIntegrations: false)
        defer { model.shutdown() }
        let startNonce = model.workspaceFocusRequestNonce
        model.requestWorkspaceInputFocus(seed: "c")
        model.requestWorkspaceInputFocus(seed: "a")
        #expect(model.workspaceFocusRequestNonce == startNonce + 2)
        #expect(model.pendingWorkspaceTypedSeed == "ca")
    }

    @Test("Collapsed media control zone excludes hover-to-expand while keeping left title interactive")
    func collapsedControlExclusionZone() {
        let hitRect = CGRect(x: 400, y: 500, width: 188, height: 30)

        // Right-wing Play/Pause & Next zone should NOT auto-expand
        let rightControlPoint = CGPoint(x: 545, y: 515)
        #expect(NotchGeometry.isPointInCollapsedControlExclusionZone(
            point: rightControlPoint,
            hitRect: hitRect,
            hasMediaControls: true,
            hasLiveActivity: false
        ))

        // Left Owl / track-title zone CAN still expand after dwell
        let leftTitlePoint = CGPoint(x: 430, y: 515)
        #expect(!NotchGeometry.isPointInCollapsedControlExclusionZone(
            point: leftTitlePoint,
            hitRect: hitRect,
            hasMediaControls: true,
            hasLiveActivity: false
        ))

        // Live activity card bottom button row excludes hover-expand
        let liveRect = CGRect(x: 350, y: 460, width: 286, height: 64)
        #expect(NotchGeometry.isPointInCollapsedControlExclusionZone(
            point: CGPoint(x: 450, y: 472),
            hitRect: liveRect,
            hasMediaControls: false,
            hasLiveActivity: true
        ))
        #expect(!NotchGeometry.isPointInCollapsedControlExclusionZone(
            point: CGPoint(x: 450, y: 512),
            hitRect: liveRect,
            hasMediaControls: false,
            hasLiveActivity: true
        ))
    }
}

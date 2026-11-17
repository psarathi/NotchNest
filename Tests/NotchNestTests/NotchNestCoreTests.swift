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
        #expect(layout.expandedSize.width == 940)
        #expect(layout.expandedSize.height == 478)
        #expect(layout.panelFrame.maxY == 900)
        #expect(abs(layout.panelFrame.midX - 720) < 0.01)

        let collapsedHit = layout.activeHitRectInPanel(isExpanded: false)
        #expect(collapsedHit.width == 216)
        #expect(collapsedHit.maxY == layout.panelFrame.height)

        let expandedHit = layout.activeHitRectInPanel(isExpanded: true)
        #expect(expandedHit.width == 940)
        #expect(expandedHit.height == 478)
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
        #expect(wideLayout.expandedSize.width == 1040)
        #expect(wideLayout.expandedSize.height == 540)

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

    @Test("Drop actions run Vision OCR text extraction and image compression")
    func ocrAndImageCompression() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchNestPhase1DropTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Render high-contrast text onto an oversized 2200x600 bitmap for both OCR & Compress tests
        let width = 2200
        let height = 600
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 160),
            .foregroundColor: NSColor.black
        ]
        NSString(string: "NOTCHNEST").draw(at: NSPoint(x: 180, y: 200), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()

        let pngURL = tempDir.appendingPathComponent("ocr-sample.png")
        try rep.representation(using: .png, properties: [:])!.write(to: pngURL)

        let recognized = try DropActionExecutor.recognizeText(from: [pngURL])
        #expect(recognized.uppercased().contains("NOTCHNEST"))

        let compressed = try DropActionExecutor.compressImages([pngURL], maxDimension: 1200, jpegQuality: 0.72)
        #expect(compressed.outputs.count == 1)
        #expect(FileManager.default.fileExists(atPath: compressed.outputs[0].path))
        #expect(compressed.compressedBytes > 0)
        #expect(compressed.outputs[0].lastPathComponent.contains("-compressed"))
    }

    @Test("Meeting handoff pauses ambient audio, creates deduplicated prep notes, and tracks media timing")
    @MainActor
    func meetingHandoffAndMediaTiming() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchNestHandoffTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = NotchNestModel(persistence: PersistenceStore(baseDirectory: tempDir), enableSystemIntegrations: false)
        defer { model.shutdown() }

        model.selectSoundscape(.rain)
        #expect(model.isAmbientPreviewActive)

        let note1 = model.openOrCreateMeetingNote(title: "Design Review", switchToNotes: false)
        let note2 = model.openOrCreateMeetingNote(title: "Design Review", switchToNotes: false)
        #expect(note1.id == note2.id)
        #expect(note1.body.contains("## Agenda"))

        model.prepareMeetingHandoff(title: "Sprint Sync", createNote: true)
        #expect(!model.isAmbientPreviewActive)
        #expect(model.notes.contains(where: { $0.title.contains("Sprint Sync") }))

        // Spotify millisecond duration normalization vs Apple Music seconds
        let spotifyList = NSAppleEventDescriptor.list()
        spotifyList.insert(NSAppleEventDescriptor(boolean: true), at: 1)
        spotifyList.insert(NSAppleEventDescriptor(string: "Track"), at: 2)
        spotifyList.insert(NSAppleEventDescriptor(string: "Artist"), at: 3)
        spotifyList.insert(NSAppleEventDescriptor(string: "Album"), at: 4)
        spotifyList.insert(NSAppleEventDescriptor(string: ""), at: 5)
        spotifyList.insert(NSAppleEventDescriptor(double: 120.0), at: 6)
        spotifyList.insert(NSAppleEventDescriptor(double: 240000.0), at: 7)
        let parsedSpotify = MediaPlaybackService.parseAppleScriptDescriptor(spotifyList, appName: "Spotify")
        #expect(parsedSpotify?.info.elapsedSeconds == 120.0)
        #expect(parsedSpotify?.info.durationSeconds == 240.0)
        #expect(parsedSpotify?.info.progressFraction == 0.5)

        let ytmJSON = #"{"playing":true,"t":"Clip","a":"Creator","alb":"","art":"","pos":30.0,"dur":120.0}"#
        let parsedYTM = MediaPlaybackService.parseYouTubeMusicPayload(tabTitle: "Clip - YouTube Music", jsJSON: ytmJSON)
        #expect(parsedYTM?.info.elapsedSeconds == 30.0)
        #expect(parsedYTM?.info.durationSeconds == 120.0)
        #expect(parsedYTM?.info.progressFraction == 0.25)
    }

    @Test("Universal Workspace command prefixes parse strictly without hijacking normal tasks")
    func workspaceQuickCommandParsing() {
        #expect(WorkspaceQuickCommand.parse("note: Buy filter cartridges") == .appendNote("Buy filter cartridges"))
        #expect(WorkspaceQuickCommand.parse("N: Sync API schema") == .appendNote("Sync API schema"))
        #expect(WorkspaceQuickCommand.parse("25m focus") == .startFocus(minutes: 25))
        #expect(WorkspaceQuickCommand.parse("focus 45") == .startFocus(minutes: 45))
        #expect(WorkspaceQuickCommand.parse("focus 15 min") == .startFocus(minutes: 15))
        #expect(WorkspaceQuickCommand.parse("tr es: Good morning") == .translate(targetLanguage: "Spanish", text: "Good morning"))
        #expect(WorkspaceQuickCommand.parse("translate ja: Thank you") == .translate(targetLanguage: "Japanese", text: "Thank you"))
        #expect(WorkspaceQuickCommand.parse("tr: Bonjour") == .translate(targetLanguage: nil, text: "Bonjour"))
        #expect(WorkspaceQuickCommand.parse("snap left") == .snapWindow(.leftHalf))
        #expect(WorkspaceQuickCommand.parse("snap right half") == .snapWindow(.rightHalf))
        #expect(WorkspaceQuickCommand.parse("snap max") == .snapWindow(.maximize))
        #expect(WorkspaceQuickCommand.parse("snap bottom right") == .snapWindow(.bottomRightQuarter))

        // Normal task phrases must NOT be hijacked as commands
        #expect(WorkspaceQuickCommand.parse("Focus on design slides") == nil)
        #expect(WorkspaceQuickCommand.parse("25m focus on Q4 roadmap") == nil)
        #expect(WorkspaceQuickCommand.parse("Note about deployment tomorrow") == nil)
        #expect(WorkspaceQuickCommand.parse("Translate API docs tomorrow") == nil)
        #expect(WorkspaceQuickCommand.parse("Snap photos at the park") == nil)
        #expect(WorkspaceQuickCommand.parse("focus 0") == nil)
    }

    @Test("Clipboard history filters sensitive sources, deduplicates, pins, persists, and generates QR codes")
    @MainActor
    func clipboardHistoryAndQR() {
        #expect(ClipboardHistoryService.isSensitivePasteboard(
            types: [NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"), .string],
            frontmostBundleID: "com.apple.Safari"
        ))
        #expect(ClipboardHistoryService.isSensitivePasteboard(
            types: [NSPasteboard.PasteboardType("org.nspasteboard.TransientType")],
            frontmostBundleID: nil
        ))
        #expect(ClipboardHistoryService.isSensitivePasteboard(
            types: [.string],
            frontmostBundleID: "com.1password.1password"
        ))
        #expect(ClipboardHistoryService.isSensitivePasteboard(
            types: [.string],
            frontmostBundleID: "com.apple.Passwords"
        ))
        #expect(!ClipboardHistoryService.isSensitivePasteboard(
            types: [.string],
            frontmostBundleID: "com.apple.Safari"
        ))

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchNestClipboardTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = PersistenceStore(baseDirectory: tempDir)
        let service = ClipboardHistoryService(persistence: store, maxUnpinnedEntries: 2)

        service.recordText("  https://github.com/psarathi/NotchNest  ")
        service.recordText("Alpha snippet")
        service.recordText("Beta snippet")
        #expect(service.entries.count == 2)
        #expect(service.entries[0].text == "Beta snippet")
        #expect(service.entries[1].text == "Alpha snippet")

        // Pin Alpha, then add another unpinned item: pinned item survives cap!
        service.togglePin(service.entries[1].id)
        service.recordText("https://example.org/docs")
        #expect(service.entries.count == 3)
        #expect(service.entries.first?.isPinned == true)
        #expect(service.entries.contains(where: { $0.isURL && $0.detectedURL?.host == "example.org" }))

        // Reload from disk verifies persistence round-trip
        let reloaded = ClipboardHistoryService(persistence: store, maxUnpinnedEntries: 2)
        #expect(reloaded.entries.count == 3)
        #expect(reloaded.entries.first?.text == "Alpha snippet")
        reloaded.clearUnpinned()
        #expect(reloaded.entries.count == 1)

        // Offline QR code image generation
        let qr = ClipboardHistoryService.qrCodeImage(for: "https://github.com/psarathi/NotchNest", size: 160)
        #expect(qr != nil)
        #expect((qr?.tiffRepresentation?.count ?? 0) > 100)
        #expect(ClipboardHistoryService.qrCodeImage(for: "   ") == nil)
    }

    @Test("Model executes Workspace quick commands and decodes AppSettings defaults")
    @MainActor
    func modelCommandExecutionAndSettingsCompatibility() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchNestCommands-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = NotchNestModel(persistence: PersistenceStore(baseDirectory: tempDir), enableSystemIntegrations: false)
        defer { model.shutdown() }

        let executedNote = model.executeWorkspaceCommand(.appendNote("Review mic mute shortcut"))
        #expect(executedNote)
        let selectedNote = model.notes.first(where: { $0.id == model.selectedNoteID })
        #expect(selectedNote?.body.contains("Review mic mute shortcut") == true)

        let executedFocus = model.executeWorkspaceCommand(.startFocus(minutes: 15))
        #expect(executedFocus)
        #expect(model.timer.state == .running)
        #expect(model.timer.phase == .focus)
        #expect(model.timer.remainingSeconds == 15 * 60)

        let executedTranslate = model.executeWorkspaceCommand(.translate(targetLanguage: "Spanish", text: "Good evening"))
        #expect(executedTranslate)
        #expect(model.devHubService.translationInput == "Good evening")
        #expect(model.devHubService.translationTargetLanguage == "Spanish")
        #expect(model.activeTab == .hub)
        #expect(model.selectedHubSection == .devAI)

        // Backward-compatibility check when older settings JSON lacks Phase 2 keys
        let legacyData = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: legacyData)
        #expect(decoded.clipboardHistoryEnabled == true)
        #expect(decoded.showMicIndicatorInNotch == true)
    }

    @Test("Per-task countdown durations parse from NL, preserve remaining time on task switch, and complete cleanly")
    @MainActor
    func perTaskCountdownTimers() {
        let ref = Date(timeIntervalSince1970: 1_760_000_000)

        let nlWithDuration = NaturalLanguageTaskParser.parse(
            "Prep slides for design review 45m #Work !high",
            referenceDate: ref
        )
        #expect(nlWithDuration.targetMinutes == 45)
        #expect(nlWithDuration.projectTag == "Work")
        #expect(nlWithDuration.priority == .high)
        #expect(nlWithDuration.title == "Prep slides for design review")

        // Relative "in 20m" must stay a due-date offset rather than target duration
        let nlWithRelativeDue = NaturalLanguageTaskParser.parse(
            "Call Sam in 20m",
            referenceDate: ref
        )
        #expect(nlWithRelativeDue.targetMinutes == nil)
        #expect(nlWithRelativeDue.dueDate == ref.addingTimeInterval(20 * 60))

        let soonTask = TaskItem(title: "Pay electricity bill", dueDate: ref.addingTimeInterval(42 * 60))
        #expect(soonTask.dueCountdownLabel(relativeTo: ref) == "in 42m")

        let farTask = TaskItem(title: "Next week", dueDate: ref.addingTimeInterval(8 * 3600))
        #expect(farTask.dueCountdownLabel(relativeTo: ref) == nil)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchNestTaskTimers-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = NotchNestModel(persistence: PersistenceStore(baseDirectory: tempDir), enableSystemIntegrations: false)
        defer { model.shutdown() }

        model.addParsedTask("Prep slides 45m #Work", defaultBucket: .today)
        model.addParsedTask("Pay bill 15m #Home", defaultBucket: .today)

        let slides = model.tasks.first(where: { $0.title == "Prep slides" })!
        let bill = model.tasks.first(where: { $0.title == "Pay bill" })!
        #expect(slides.targetMinutes == 45)
        #expect(bill.targetMinutes == 15)

        model.selectFocusTask(slides.id)
        #expect(model.timer.formattedRemaining == "45:00")
        #expect(model.activeFocusTaskID == slides.id)

        // Simulate partially running slides countdown and switching to bill
        model.timer.configure(totalSeconds: 45 * 60, remainingSeconds: 30 * 60, phase: .focus)
        model.selectFocusTask(bill.id)
        #expect(model.timer.formattedRemaining == "15:00")
        #expect(model.taskRemainingSeconds[slides.id] == TimeInterval(30 * 60))

        // Switching back restores slides at 30:00
        model.selectFocusTask(slides.id)
        #expect(model.timer.formattedRemaining == "30:00")

        // Updating duration sets targetMinutes and resets clock cleanly
        model.setFocusDuration(minutes: 60, for: slides.id)
        #expect(model.tasks.first(where: { $0.id == slides.id })?.targetMinutes == 60)
        #expect(model.timer.formattedRemaining == "60:00")

        // Completing active focus task marks task completed & resets focus link
        model.completeActiveFocusTask()
        #expect(model.tasks.first(where: { $0.id == slides.id })?.isCompleted == true)
        #expect(model.activeFocusTaskID == nil)
    }

    @Test("Daily Notepad creates a fresh note per day while preserving previous days")
    @MainActor
    func dailyNotepadRollover() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchNestDailyNoteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = PersistenceStore(baseDirectory: tempDir)
        let cal = Calendar.current
        let today = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let todayKey = DailyFocusStats.todayKey(for: today)
        let yesterdayKey = DailyFocusStats.todayKey(for: yesterday)

        // Seed yesterday's note with content + an empty stale shell
        store.saveNotes([
            NoteEntry(title: "Lead landing page", body: "Lead landing page\nAsk Sam", updatedAt: yesterday, dailyDayKey: yesterdayKey),
            NoteEntry(title: "Scratchpad", body: "   ", updatedAt: yesterday)
        ])

        let model = NotchNestModel(persistence: store, enableSystemIntegrations: false)
        defer { model.shutdown() }

        let todaysNote = model.ensureTodayDailyNote(now: today, calendar: cal)
        #expect(todaysNote.dailyDayKey == todayKey)
        #expect(model.selectedNoteID == todaysNote.id)
        #expect(todaysNote.body.isEmpty)

        // Yesterday's non-empty note is preserved; yesterday's empty shell was cleaned up
        #expect(model.notes.count == 2)
        #expect(model.notes.contains(where: { $0.dailyDayKey == yesterdayKey && $0.body.contains("Lead landing page") }))
        #expect(!model.notes.contains(where: { $0.title == "Scratchpad" }))
    }

    @Test("Pre-due reminder countdown auto-starts on window entry, stays pauseable, and decodes display settings")
    @MainActor
    func preDueReminderCountdownAndSettings() throws {
        let cal = Calendar(identifier: .gregorian)
        let ref = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 16, minute: 48))!

        let parsed = NaturalLanguageTaskParser.parse(
            "Submit expenses at 5pm remind 15m before #Work",
            referenceDate: ref,
            calendar: cal
        )
        #expect(parsed.reminderLeadMinutes == 15)
        #expect(parsed.projectTag == "Work")
        #expect(parsed.title == "Submit expenses")
        #expect(parsed.dueDate != nil)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchNestPreDueTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let model = NotchNestModel(persistence: PersistenceStore(baseDirectory: tempDir), enableSystemIntegrations: false)
        defer { model.shutdown() }

        // Far-future task whose 15m window has NOT started yet (due in 45m)
        model.addTask(
            title: "Evening sync",
            dueDate: ref.addingTimeInterval(45 * 60),
            reminderLeadMinutes: 15
        )
        #expect(model.evaluatePreDueReminders(now: ref) == nil)
        #expect(model.timer.state == .idle)

        // Urgent task due in 12m with 15m lead reminder -> already inside pre-due window
        model.addTask(
            title: "Submit expenses",
            dueDate: ref.addingTimeInterval(12 * 60),
            reminderLeadMinutes: 15
        )
        let urgentTask = model.tasks.first(where: { $0.title == "Submit expenses" })!
        let triggered = model.evaluatePreDueReminders(now: ref)
        #expect(triggered?.id == urgentTask.id)
        #expect(model.timer.state == .running)
        #expect(model.activeFocusTaskID == urgentTask.id)
        #expect(model.activeCountdownSourceIsReminder == true)
        #expect(model.timer.remainingSeconds >= 11 * 60 && model.timer.remainingSeconds <= 12 * 60)

        // Pausing stays paused and does not re-trigger
        model.toggleFocusPlayPause()
        #expect(model.timer.state == .paused)
        #expect(model.evaluatePreDueReminders(now: ref) == nil)
        #expect(model.timer.state == .paused)

        // Default & custom AppSettings round-trip
        let legacyDecoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(legacyDecoded.collapsedDisplayMode == .automatic)
        #expect(legacyDecoded.expandedCountdownStyle == .bottomRail)
        #expect(legacyDecoded.showExpandedVitals == true)

        model.settings.collapsedDisplayMode = .vitals
        model.settings.expandedCountdownStyle = .headerPill
        model.settings.showExpandedVitals = false
        let reloaded = NotchNestModel(persistence: PersistenceStore(baseDirectory: tempDir), enableSystemIntegrations: false)
        defer { reloaded.shutdown() }
        #expect(reloaded.settings.collapsedDisplayMode == .vitals)
        #expect(reloaded.settings.expandedCountdownStyle == .headerPill)
        #expect(reloaded.settings.showExpandedVitals == false)
    }
}

import AppKit
import NotchNestCore
import SwiftUI

struct TodayTabView: View {
    @Bindable var model: NotchNestModel
    let onRequestFocus: () -> Void

    @State private var draftTitle = ""
    @State private var newPriority: TaskPriority = .normal
    @State private var showCompleted = true
    @State private var dayOffset = 0
    @State private var selectedCalendarDate = Calendar.current.startOfDay(for: Date())
    @State private var editingTaskID: UUID?
    @State private var editTitle = ""
    @State private var editPriority: TaskPriority = .normal
    @State private var editBucket: TaskBucket = .today
    @State private var editDayKey: String?
    @FocusState private var isAddingFocused: Bool

    private static let dateHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    private static let leaveTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let timelineHourFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f
    }()

    private static let timelinePeriodFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "a"
        return f
    }()

    private static let dayInitialFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEEE"
        return f
    }()

    private var parsedPreview: ParsedTaskDraft? {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let draft = NaturalLanguageTaskParser.parse(
            trimmed,
            defaultBucket: model.bucket(forDayOffset: dayOffset),
            defaultDayKey: model.dayKey(forDayOffset: dayOffset)
        )
        return draft.hasStructuredMetadata ? draft : nil
    }

    var body: some View {
        HStack(spacing: 11) {
            sageTasksCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            rightCalendarAndFocusColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if model.isExpanded && model.activeTab == .today && NSApp.keyWindow != nil {
                focusWorkspaceInputBox()
            }
        }
        .onChange(of: model.workspaceFocusRequestNonce) { _, _ in
            focusWorkspaceInputBox()
        }
    }

    private func focusWorkspaceInputBox() {
        guard editingTaskID == nil else { return }
        if !model.pendingWorkspaceTypedSeed.isEmpty {
            draftTitle += model.pendingWorkspaceTypedSeed
            model.pendingWorkspaceTypedSeed = ""
        }
        onRequestFocus()
        isAddingFocused = true
        DispatchQueue.main.async {
            if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                let end = (textView.string as NSString).length
                textView.setSelectedRange(NSRange(location: end, length: 0))
            }
        }
    }

    // MARK: - Signature Sage Green Today Card

    private var currentTaskBoardTitle: String {
        switch dayOffset {
        case ..<0: return "Inbox"
        case 0: return "Today's tasks"
        case 1: return "Tomorrow's tasks"
        default:
            let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            return "\(Self.dateHeaderFormatter.string(from: day)) tasks"
        }
    }

    private var currentPillDateLabel: String {
        if dayOffset < 0 { return "Backlog" }
        let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
        return Self.dateHeaderFormatter.string(from: day)
    }

    private var sageTasksCard: some View {
        let dayTasks = model.tasks(forDayOffset: dayOffset)
        let openCount = dayTasks.filter { !$0.isCompleted }.count
        let doneCount = dayTasks.filter { $0.isCompleted }.count
        let visibleTasks = showCompleted ? dayTasks : dayTasks.filter { !$0.isCompleted }

        return VStack(alignment: .leading, spacing: 8) {
            // Sage task board header (< date selector > + Wrap-up)
            HStack(spacing: 6) {
                Text(currentTaskBoardTitle)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.sageInk)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Button {
                    model.activeUtilityOverlay = .wrapUp
                } label: {
                    Image(systemName: "moon.stars")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NotchTheme.sageInk.opacity(0.72))
                        .frame(width: 22, height: 22)
                        .background(Color.black.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Daily Wrap Up")

                HStack(spacing: 3) {
                    Button {
                        dayOffset = max(-1, dayOffset - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(NotchTheme.sageInk.opacity(dayOffset <= -1 ? 0.25 : 0.7))
                            .frame(width: 18, height: 20)
                    }
                    .buttonStyle(.plain)
                    .disabled(dayOffset <= -1)

                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(currentPillDateLabel)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(NotchTheme.sageInk)
                    .onTapGesture {
                        dayOffset = 0
                    }

                    Button {
                        dayOffset = min(6, dayOffset + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(NotchTheme.sageInk.opacity(dayOffset >= 6 ? 0.25 : 0.7))
                            .frame(width: 18, height: 20)
                    }
                    .buttonStyle(.plain)
                    .disabled(dayOffset >= 6)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.06), in: Capsule())
            }

            // Counter pills + utilities
            HStack(spacing: 6) {
                Text("To do \(openCount)")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(NotchTheme.sageBadgeFill, in: Capsule())

                Button {
                    showCompleted.toggle()
                } label: {
                    Text("Completed \(doneCount)")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.sageInk.opacity(showCompleted ? 0.85 : 0.45))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Toggle completed tasks")

                Spacer()

                if doneCount > 0 {
                    Button("Clear") {
                        model.clearCompletedTasks()
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NotchTheme.sageMuted)
                    .buttonStyle(.plain)
                }

                if model.settings.syncReminders {
                    Button {
                        Task { await model.syncWithReminders() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(NotchTheme.sageBadgeFill)
                    }
                    .buttonStyle(.plain)
                    .help("Sync with Reminders (NotchNest list)")
                }
            }

            Divider()
                .overlay(Color.black.opacity(0.11))

            // Task list
            if visibleTasks.isEmpty {
                VStack(spacing: 7) {
                    Spacer()
                    OwlMascotView(size: 28, isFocusing: false, isHovering: false, pulse: false, animationsEnabled: false)
                        .opacity(0.75)
                    Text("Clear slate here — type or tap the mic below.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(NotchTheme.sageMuted)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(spacing: 0) {
                        ForEach(visibleTasks) { item in
                            sageTaskRow(item)

                            if item.id != visibleTasks.last?.id {
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(height: 1)
                                    .overlay(
                                        Line()
                                            .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                                            .foregroundStyle(Color.black.opacity(0.12))
                                    )
                                    .padding(.vertical, 3)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            // Natural-language preview bar above quick entry
            if let summary = parsedPreview?.previewSummary() {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchTheme.sageBadgeFill)
                    Text(summary)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(NotchTheme.sageInk.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 4)
            } else if let voiceErr = model.voiceCapture.errorMessage {
                Text(voiceErr)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.85))
                    .lineLimit(1)
                    .padding(.horizontal, 4)
            }

            // Quick add + Voice dictation bar
            HStack(spacing: 7) {
                Button {
                    newPriority = (newPriority == .high) ? .normal : .high
                } label: {
                    Image(systemName: newPriority == .high ? "flag.fill" : "plus")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(newPriority == .high ? .orange : NotchTheme.sageMuted)
                }
                .buttonStyle(.plain)
                .help("Toggle high priority")

                TextField("Add a task… (e.g. Call mom tomorrow 5pm #Personal)", text: $draftTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(NotchTheme.sageInk)
                    .focused($isAddingFocused)
                    .onTapGesture {
                        onRequestFocus()
                        isAddingFocused = true
                    }
                    .onSubmit {
                        submitDraftTask()
                    }

                Button {
                    onRequestFocus()
                    model.voiceCapture.onTranscriptUpdated = { text in
                        draftTitle = text
                    }
                    Task {
                        await model.voiceCapture.toggleRecording()
                    }
                } label: {
                    if model.voiceCapture.isRecording {
                        HStack(spacing: 4) {
                            AnimatedWaveformView(
                                isActive: true,
                                barColor: NotchTheme.coralAlert,
                                barWidth: 2,
                                maxHeight: 11
                            )
                            Text("Stop")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(NotchTheme.coralAlert)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.10), in: Capsule())
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(NotchTheme.sageMuted)
                            .padding(4)
                    }
                }
                .buttonStyle(.plain)
                .help("Dictate task with voice")

                Button(action: submitDraftTask) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            draftTitle.trimmingCharacters(in: .whitespaces).isEmpty
                                ? NotchTheme.sageInk.opacity(0.25)
                                : NotchTheme.sageBadgeFill
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(NotchTheme.sageInputFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
        }
        .padding(12)
        .background(NotchTheme.sagePaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func sageTaskRow(_ item: TaskItem) -> some View {
        if editingTaskID == item.id {
            TaskInlineEditorRow(
                title: $editTitle,
                priority: $editPriority,
                bucket: $editBucket,
                dayKey: $editDayKey,
                columns: model.weekPlanColumns(),
                onRequestFocus: onRequestFocus,
                onSave: {
                    model.updateTask(
                        item.id,
                        title: editTitle,
                        priority: editPriority,
                        bucket: editBucket,
                        dayKey: editDayKey
                    )
                    editingTaskID = nil
                },
                onCancel: {
                    editingTaskID = nil
                },
                onDelete: {
                    editingTaskID = nil
                    model.deleteTask(item.id)
                },
                isDarkSurface: false
            )
        } else {
            let isFocusedTask = model.activeFocusTaskID == item.id && model.timer.state != .idle
            let isPinnedNudge = model.pinnedLiveActivityTaskID == item.id

            HStack(alignment: .center, spacing: 6) {
                Button {
                    model.toggleTask(item.id)
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(item.isCompleted ? NotchTheme.mintComplete : NotchTheme.sageInk.opacity(0.62))
                        .frame(width: 22, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(item.isCompleted ? NotchTheme.sageMuted.opacity(0.65) : NotchTheme.sageInk)
                        .strikethrough(item.isCompleted, color: NotchTheme.sageMuted.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if item.dueDate != nil || item.projectTag != nil || item.priority == .high || item.recurrence != .none || item.focusedMinutes > 0 || item.detectedMeetingURL != nil {
                        HStack(spacing: 5) {
                            if let time = item.formattedDueTime() {
                                Label(time, systemImage: "clock")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(NotchTheme.sageMuted)
                            }
                            if item.focusedMinutes > 0 {
                                Text("Focused · \(item.focusedMinutes)m")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(NotchTheme.sageMuted)
                            }
                            if item.priority == .high && !item.isCompleted {
                                Label("High", systemImage: "flag.fill")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(Color(red: 0.72, green: 0.25, blue: 0.14))
                            }
                            if let tag = item.projectTag {
                                Text(tag)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(NotchTheme.sageBadgeFill)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.black.opacity(0.08), in: Capsule())
                            }
                            if let rec = item.recurrence.label {
                                Label(rec, systemImage: "repeat")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(NotchTheme.sageMuted)
                            }
                            if let joinURL = item.detectedMeetingURL {
                                Button {
                                    NSWorkspace.shared.open(joinURL)
                                } label: {
                                    Label("Join \(MeetingLinkExtractor.serviceLabel(for: joinURL))", systemImage: "video.fill")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1.5)
                                        .background(NotchTheme.sageBadgeFill, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    beginEditing(item)
                }

                Spacer(minLength: 4)

                if !item.isCompleted {
                    Button {
                        model.pinTaskAsLiveNudge(item.id)
                    } label: {
                        Image(systemName: isPinnedNudge ? "bell.badge.fill" : "bell")
                            .font(.system(size: 10.5))
                            .foregroundStyle(isPinnedNudge ? NotchTheme.peachAction : NotchTheme.sageMuted.opacity(0.75))
                            .frame(width: 20, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Pin Live Activity nudge in notch")

                    Button {
                        model.startFocus(on: item.id)
                        model.activeTab = .timer
                    } label: {
                        Image(systemName: isFocusedTask ? "pause.fill" : "play.fill")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(isFocusedTask ? .white : NotchTheme.sageInk.opacity(0.75))
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(isFocusedTask ? NotchTheme.sageBadgeFill : Color.black.opacity(0.08))
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Start focus timer for this task")
                }

                Button {
                    beginEditing(item)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(NotchTheme.sageMuted.opacity(0.8))
                        .frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit task")

                TaskActionsMenu(
                    model: model,
                    item: item,
                    iconColor: NotchTheme.sageMuted.opacity(0.85),
                    onStartEdit: { beginEditing(item) }
                )

                Button {
                    model.deleteTask(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchTheme.sageMuted.opacity(0.8))
                        .frame(width: 20, height: 22)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Delete task")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isFocusedTask ? Color.black.opacity(0.10) : Color.clear)
            )
            .contextMenu {
                Button("Edit Task") { beginEditing(item) }
                Button(item.priority == .high ? "Normal Priority" : "High Priority") {
                    model.toggleTaskPriority(item.id)
                }
                Menu("Move to") {
                    ForEach(TaskBucket.allCases) { bucket in
                        Button(bucket.title) { model.moveTask(item.id, to: bucket) }
                    }
                }
                Divider()
                Button("Delete Task", role: .destructive) {
                    model.deleteTask(item.id)
                }
            }
        }
    }

    private func beginEditing(_ item: TaskItem) {
        editingTaskID = item.id
        editTitle = item.title
        editPriority = item.priority
        editBucket = item.scheduledBucket
        editDayKey = item.scheduledDayKey
    }

    private func submitDraftTask() {
        model.voiceCapture.stopRecording()
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let targetBucket = model.bucket(forDayOffset: dayOffset)
        let targetDayKey = model.dayKey(forDayOffset: dayOffset)
        model.addParsedTask(
            trimmed,
            defaultBucket: targetBucket,
            defaultDayKey: targetDayKey,
            priorityOverride: newPriority
        )
        draftTitle = ""
        newPriority = .normal
    }

    // MARK: - Right Misty Steel-Blue 7-Day Calendar & Compact Focus

    private var rightCalendarAndFocusColumn: some View {
        VStack(spacing: 10) {
            steelBlueCalendarCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            focusCompactCard
        }
    }

    private var weekDaysWindow: [Date] {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: startToday) }
    }

    private var steelBlueCalendarCard: some View {
        let cal = Calendar.current
        let dayEvents = model.events(on: selectedCalendarDate)
        let dayTimedTasks = model.timedTasks(on: selectedCalendarDate)

        return VStack(alignment: .leading, spacing: 9) {
            // Top handle bar + 7-day selector strip for the calendar card
            VStack(spacing: 7) {
                Capsule()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: 22, height: 3)

                HStack(spacing: 0) {
                    ForEach(weekDaysWindow, id: \.self) { day in
                        let isSelected = cal.isDate(day, inSameDayAs: selectedCalendarDate)
                        let isToday = cal.isDateInToday(day)
                        let hasDot = model.dayHasActivity(day)
                        let dayNum = cal.component(.day, from: day)

                        Button {
                            selectedCalendarDate = day
                        } label: {
                            VStack(spacing: 3) {
                                Text(Self.dayInitialFormatter.string(from: day))
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(NotchTheme.steelBlueMuted)

                                ZStack {
                                    if isSelected {
                                        Circle()
                                            .fill(NotchTheme.steelBlueSelectedCircle)
                                    } else if isToday {
                                        Circle()
                                            .stroke(NotchTheme.steelBlueInk.opacity(0.55), lineWidth: 1.2)
                                    }

                                    Text("\(dayNum)")
                                        .font(.system(size: 12.5, weight: isSelected ? .bold : .semibold, design: .rounded))
                                        .foregroundStyle(isSelected ? .white : NotchTheme.steelBlueInk)
                                }
                                .frame(width: 26, height: 26)

                                Circle()
                                    .fill(NotchTheme.steelBlueInk.opacity(hasDot ? 0.65 : 0.0))
                                    .frame(width: 3.5, height: 3.5)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Optional calendar authorization prompt banner (non-blocking)
            if model.eventKit.calendarAuth == .notDetermined {
                HStack(spacing: 8) {
                    Text("Connect Apple Calendar for meetings & Zoom links")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(NotchTheme.steelBlueInk)
                        .lineLimit(1)
                    Spacer()
                    Button("Connect") {
                        Task { _ = await model.eventKit.requestCalendarAccess() }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(NotchTheme.steelBlueSelectedCircle, in: Capsule())
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            } else if model.eventKit.calendarAuth == .denied {
                HStack(spacing: 8) {
                    Text("Calendar permission off in System Settings")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(NotchTheme.steelBlueInk)
                    Spacer()
                    Button("Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(NotchTheme.steelBlueSelectedCircle, in: Capsule())
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
            }

            // Chronological Day Timeline combining Calendar Events + Timed Reminders/Tasks
            if dayEvents.isEmpty && dayTimedTasks.isEmpty {
                VStack(spacing: 5) {
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.system(size: 18))
                        .foregroundStyle(NotchTheme.steelBlueMuted.opacity(0.7))
                    Text("No scheduled meetings or timed reminders on this day")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.steelBlueMuted)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(buildTimelineEntries(events: dayEvents, tasks: dayTimedTasks)) { entry in
                            timelineRow(entry)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(11)
        .background(NotchTheme.steelBluePaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private enum TimelineEntry: Identifiable {
        case event(CalendarEventItem)
        case task(TaskItem)

        var id: String {
            switch self {
            case .event(let e): return "event-\(e.id)"
            case .task(let t): return "task-\(t.id.uuidString)"
            }
        }

        var sortDate: Date {
            switch self {
            case .event(let e): return e.startDate
            case .task(let t): return t.dueDate ?? .distantFuture
            }
        }
    }

    private func buildTimelineEntries(events: [CalendarEventItem], tasks: [TaskItem]) -> [TimelineEntry] {
        (events.map(TimelineEntry.event) + tasks.map(TimelineEntry.task))
            .sorted { $0.sortDate < $1.sortDate }
    }

    @ViewBuilder
    private func timelineRow(_ entry: TimelineEntry) -> some View {
        switch entry {
        case .event(let event):
            HStack(spacing: 8) {
                if event.isAllDay {
                    Text("All\nday")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTheme.steelBlueMuted)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 36, alignment: .trailing)
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Self.timelineHourFormatter.string(from: event.startDate))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.steelBlueInk)
                        Text(Self.timelinePeriodFormatter.string(from: event.startDate))
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(NotchTheme.steelBlueMuted)
                    }
                    .frame(width: 36, alignment: .trailing)
                }

                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(NotchTheme.steelBlueInk)
                            .lineLimit(1)

                        HStack(spacing: 4) {
                            Text("\(event.calendarTitle) · \(event.durationMinutes) min")
                                .font(.system(size: 10))
                                .foregroundStyle(NotchTheme.steelBlueMuted)
                                .lineLimit(1)

                            if let travelMins = event.travelTimeMinutes, let leaveDate = event.leaveByDate {
                                Label(
                                    "\(travelMins)m · Leave \(Self.leaveTimeFormatter.string(from: leaveDate))",
                                    systemImage: "car.fill"
                                )
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(NotchTheme.steelBlueSelectedCircle)
                            }
                        }
                    }

                    Spacer(minLength: 4)

                    if let meetingURL = event.meetingURL {
                        Button {
                            NSWorkspace.shared.open(meetingURL)
                        } label: {
                            Label("Join \(event.meetingServiceLabel ?? "Call")", systemImage: "video.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(NotchTheme.steelBlueSelectedCircle, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(NotchTheme.steelBlueRowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

        case .task(let task):
            HStack(spacing: 8) {
                if let due = task.dueDate {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Self.timelineHourFormatter.string(from: due))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.steelBlueInk)
                        Text(Self.timelinePeriodFormatter.string(from: due))
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(NotchTheme.steelBlueMuted)
                    }
                    .frame(width: 36, alignment: .trailing)
                }

                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(task.isCompleted ? NotchTheme.steelBlueMuted.opacity(0.65) : NotchTheme.steelBlueInk)
                            .strikethrough(task.isCompleted)
                            .lineLimit(1)

                        Text(task.projectTag.map { "Reminder · #\($0)" } ?? "Reminder")
                            .font(.system(size: 10))
                            .foregroundStyle(NotchTheme.steelBlueMuted)
                    }

                    Spacer(minLength: 4)

                    if let joinURL = task.detectedMeetingURL {
                        Button {
                            NSWorkspace.shared.open(joinURL)
                        } label: {
                            Label("Join \(MeetingLinkExtractor.serviceLabel(for: joinURL))", systemImage: "video.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(NotchTheme.steelBlueSelectedCircle, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        model.toggleTask(task.id)
                    } label: {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(task.isCompleted ? NotchTheme.mintComplete : NotchTheme.steelBlueInk.opacity(0.65))
                            .frame(width: 22, height: 22)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(NotchTheme.steelBlueRowFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var focusCompactCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.activeFocusTask?.title ?? model.timer.phase.label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(NotchTheme.lavenderSoft)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(model.timer.formattedRemaining)
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)

                        if model.timer.state == .running || model.audioEngine.isPlaying {
                            AnimatedWaveformView(
                                isActive: true,
                                barColor: NotchTheme.skyWave,
                                barWidth: 2,
                                maxHeight: 11
                            )
                        }
                    }
                }

                Spacer()

                Button {
                    model.toggleFocusPlayPause()
                } label: {
                    Image(systemName: model.timer.state == .running ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 28, height: 28)
                        .background(NotchTheme.skyWave, in: Circle())
                }
                .buttonStyle(.plain)

                if model.timer.state != .idle {
                    Button {
                        model.resetFocusTimer()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 24, height: 24)
                            .background(Color.white.opacity(0.09), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 4) {
                ForEach(FocusSoundscape.allCases) { sound in
                    let selected = model.settings.focusSoundscape == sound
                    Button {
                        model.selectSoundscape(sound)
                    } label: {
                        Text(sound.label)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(selected ? .black : .white.opacity(0.76))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(selected ? NotchTheme.lavenderSoft : Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(NotchTheme.lavenderCard, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(NotchTheme.lavenderAccent.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

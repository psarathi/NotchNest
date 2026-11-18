import AppKit
import NotchNestCore
import SwiftUI

private enum WorkspaceDictationTarget: Equatable {
    case taskInput
    case notepad(noteID: UUID, baseBody: String)
}

struct TodayTabView: View {
    @Bindable var model: NotchNestModel
    let onRequestFocus: () -> Void

    @State private var draftTitle = ""
    @State private var newPriority: TaskPriority = .normal
    @State private var showCompleted = true
    @State private var sortMode: TaskSortMode = .manual
    @State private var dayOffset = 0
    @State private var selectedCalendarDate = Calendar.current.startOfDay(for: Date())
    @State private var editingTaskID: UUID?
    @State private var editTitle = ""
    @State private var editPriority: TaskPriority = .normal
    @State private var editBucket: TaskBucket = .today
    @State private var editDayKey: String?
    @State private var editTargetMinutes: Int?
    @State private var editDueDate: Date?
    @State private var editReminderLeadMinutes: Int?
    @State private var dictationTarget: WorkspaceDictationTarget?
    @State private var notepadFeedback: String?
    @State private var notepadController = RichTextEditorController()

    @FocusState private var isAddingFocused: Bool
    @State private var isNotepadFocused: Bool = false

    private static let dateHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
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

    private var parsedCommandPreview: WorkspaceQuickCommand? {
        WorkspaceQuickCommand.parse(draftTitle)
    }

    private var parsedPreview: ParsedTaskDraft? {
        guard parsedCommandPreview == nil else { return nil }
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
        GeometryReader { geo in
            let gap: CGFloat = 9
            let usable = max(560, geo.size.width - gap * 3)
            let tasksW = usable * 0.275
            let focusW = usable * 0.215
            let notepadW = usable * 0.225
            let calendarW = usable * 0.285

            HStack(spacing: gap) {
                sageTasksCard
                    .frame(width: tasksW)
                    .frame(maxHeight: .infinity)

                lavenderFocusCard
                    .frame(width: focusW)
                    .frame(maxHeight: .infinity)

                yellowNotepadCard
                    .frame(width: notepadW)
                    .frame(maxHeight: .infinity)

                steelBlueCalendarCard
                    .frame(width: calendarW)
                    .frame(maxHeight: .infinity)
            }
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
        isNotepadFocused = false
        isAddingFocused = true
        DispatchQueue.main.async {
            if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                let end = (textView.string as NSString).length
                textView.setSelectedRange(NSRange(location: end, length: 0))
            }
        }
    }

    // MARK: - Column 1: Signature Matte Sage Green Tasks

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

    private func sortedDayTasks(_ source: [TaskItem]) -> [TaskItem] {
        switch sortMode {
        case .manual:
            return source
        case .priority:
            return source.sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                if lhs.priority != rhs.priority { return lhs.priority == .high }
                return lhs.createdAt > rhs.createdAt
            }
        case .dueTime:
            return source.sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                switch (lhs.dueDate, rhs.dueDate) {
                case (.some(let l), .some(let r)): return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                default: return lhs.createdAt > rhs.createdAt
                }
            }
        case .duration:
            return source.sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                let lDur = lhs.targetMinutes ?? 0
                let rDur = rhs.targetMinutes ?? 0
                if lDur != rDur { return lDur > rDur }
                return lhs.createdAt > rhs.createdAt
            }
        }
    }

    private var sageTasksCard: some View {
        let dayTasks = model.tasks(forDayOffset: dayOffset)
        let openCount = dayTasks.filter { !$0.isCompleted }.count
        let doneCount = dayTasks.filter { $0.isCompleted }.count
        let filtered = showCompleted ? dayTasks : dayTasks.filter { !$0.isCompleted }
        let visibleTasks = sortedDayTasks(filtered)

        return VStack(alignment: .leading, spacing: 7) {
            // Header + date navigation
            HStack(spacing: 4) {
                Text(currentTaskBoardTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.sageInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Button {
                    model.activeUtilityOverlay = .wrapUp
                } label: {
                    Image(systemName: "moon.stars")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchTheme.sageInk.opacity(0.68))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Daily Wrap Up")

                Spacer(minLength: 2)

                HStack(spacing: 2) {
                    Button {
                        dayOffset = max(-1, dayOffset - 1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(NotchTheme.sageInk.opacity(dayOffset <= -1 ? 0.25 : 0.7))
                            .frame(width: 15, height: 18)
                    }
                    .buttonStyle(.plain)
                    .disabled(dayOffset <= -1)

                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9, weight: .semibold))
                        Text(currentPillDateLabel)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(NotchTheme.sageInk)
                    .onTapGesture {
                        dayOffset = 0
                    }

                    Button {
                        dayOffset = min(6, dayOffset + 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(NotchTheme.sageInk.opacity(dayOffset >= 6 ? 0.25 : 0.7))
                            .frame(width: 15, height: 18)
                    }
                    .buttonStyle(.plain)
                    .disabled(dayOffset >= 6)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.06), in: Capsule())
            }

            // Counter pills
            HStack(spacing: 5) {
                Text("To do \(openCount)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(NotchTheme.sageBadgeFill, in: Capsule())

                Button {
                    showCompleted.toggle()
                } label: {
                    Text("Completed \(doneCount)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(NotchTheme.sageInk.opacity(showCompleted ? 0.85 : 0.45))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.black.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Toggle completed tasks")

                Spacer(minLength: 2)

                if doneCount > 0 {
                    Button("Clear") {
                        model.clearCompletedTasks()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchTheme.sageMuted)
                    .buttonStyle(.plain)
                }

                if model.settings.syncReminders {
                    Button {
                        Task { await model.syncWithReminders() }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(NotchTheme.sageBadgeFill)
                    }
                    .buttonStyle(.plain)
                    .help("Sync with Apple Reminders")
                }
            }

            dottedSeparator

            // Task list
            if visibleTasks.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    OwlMascotView(size: 24, isFocusing: false, isHovering: false, pulse: false, animationsEnabled: false)
                        .opacity(0.75)
                    Text("Clear slate here — add a task below.")
                        .font(.system(size: 11, weight: .medium))
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
                                dottedSeparator
                                    .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            // Natural-language & quick-command preview bar above quick entry
            if let command = parsedCommandPreview {
                HStack(spacing: 4) {
                    Image(systemName: "command.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchTheme.sageBadgeFill)
                    Text(command.previewLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchTheme.sageInk.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 3)
            } else if let summary = parsedPreview?.previewSummary() {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(NotchTheme.sageBadgeFill)
                    Text(summary)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.sageInk.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 3)
            } else if let voiceErr = model.voiceCapture.errorMessage, dictationTarget == .taskInput {
                Text(voiceErr)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.red.opacity(0.85))
                    .lineLimit(1)
                    .padding(.horizontal, 3)
            }

            dottedSeparator

            // Quick add + Voice dictation + Sort row
            HStack(spacing: 5) {
                HStack(spacing: 5) {
                    Button {
                        newPriority = (newPriority == .high) ? .normal : .high
                    } label: {
                        Image(systemName: newPriority == .high ? "flag.fill" : "plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(newPriority == .high ? .orange : NotchTheme.sageMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle high priority")

                    TextField("Add a task or command…", text: $draftTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.sageInk)
                        .focused($isAddingFocused)
                        .help("Add a task (e.g. Prep slides 45m tomorrow 5pm #Work) or command (timer tea 4m, focus 25m, break 5m, mute mic, clear done)")
                        .onTapGesture {
                            onRequestFocus()
                            isNotepadFocused = false
                            isAddingFocused = true
                        }
                        .onSubmit {
                            submitDraftTask()
                        }

                    Button {
                        onRequestFocus()
                        dictationTarget = .taskInput
                        model.voiceCapture.onTranscriptUpdated = { text in
                            draftTitle = text
                        }
                        Task {
                            await model.voiceCapture.toggleRecording()
                        }
                    } label: {
                        if model.voiceCapture.isRecording && dictationTarget == .taskInput {
                            AnimatedWaveformView(
                                isActive: true,
                                barColor: NotchTheme.coralAlert,
                                barWidth: 1.8,
                                maxHeight: 10
                            )
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 10.5))
                                .foregroundStyle(NotchTheme.sageMuted)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Dictate task with voice")

                    if !draftTitle.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button(action: submitDraftTask) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(NotchTheme.sageBadgeFill)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(NotchTheme.sageInputFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )

                Menu {
                    ForEach(TaskSortMode.allCases) { mode in
                        Button {
                            sortMode = mode
                        } label: {
                            HStack {
                                Text(mode.label)
                                if sortMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text(sortMode == .manual ? "Sort" : sortMode.label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(NotchTheme.sageMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Sort tasks (Default, Priority, Due Time, Duration)")
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NotchTheme.sagePaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var dottedSeparator: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 1)
            .overlay(
                Line()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .foregroundStyle(Color.black.opacity(0.13))
            )
    }

    @ViewBuilder
    private func sageTaskRow(_ item: TaskItem) -> some View {
        if editingTaskID == item.id {
            TaskInlineEditorRow(
                title: $editTitle,
                priority: $editPriority,
                bucket: $editBucket,
                dayKey: $editDayKey,
                targetMinutes: $editTargetMinutes,
                dueDate: $editDueDate,
                reminderLeadMinutes: $editReminderLeadMinutes,
                columns: model.weekPlanColumns(),
                onRequestFocus: onRequestFocus,
                onSave: {
                    model.updateTask(
                        item.id,
                        title: editTitle,
                        priority: editPriority,
                        bucket: editBucket,
                        dayKey: editDayKey,
                        updateTargetMinutes: true,
                        targetMinutes: editTargetMinutes,
                        updateDueDate: true,
                        dueDate: editDueDate,
                        updateReminderLeadMinutes: true,
                        reminderLeadMinutes: editReminderLeadMinutes
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
            let isLinkedTask = model.activeFocusTaskID == item.id
            let isRunningHere = isLinkedTask && model.timer.state == .running
            let savedRemaining = model.taskRemainingSeconds[item.id]
            let isPausedCountdown = (isLinkedTask && model.timer.state == .paused) || (!isLinkedTask && savedRemaining != nil)
            let dueCountdown = item.dueCountdownLabel()

            HStack(alignment: .center, spacing: 5) {
                Button {
                    model.toggleTask(item.id)
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundStyle(item.isCompleted ? NotchTheme.mintComplete : NotchTheme.sageInk.opacity(0.62))
                        .frame(width: 20, height: 20)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(item.isCompleted ? NotchTheme.sageMuted.opacity(0.65) : NotchTheme.sageInk)
                        .strikethrough(item.isCompleted, color: NotchTheme.sageMuted.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if item.dueDate != nil || item.projectTag != nil || item.priority == .high || item.recurrence != .none || item.focusedMinutes > 0 || item.targetMinutes != nil || isLinkedTask || savedRemaining != nil || item.detectedMeetingURL != nil {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                if isRunningHere {
                                    HStack(spacing: 3) {
                                        Image(systemName: "timer")
                                            .font(.system(size: 8.5, weight: .bold))
                                        Text(model.timer.formattedRemaining)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    }
                                    .lineLimit(1)
                                    .fixedSize()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5.5)
                                    .padding(.vertical, 1.5)
                                    .background(NotchTheme.sageBadgeFill, in: Capsule())
                                } else if isPausedCountdown {
                                    let rem = isLinkedTask ? model.timer.remainingSeconds : (savedRemaining ?? 0)
                                    HStack(spacing: 3) {
                                        Image(systemName: "pause.circle.fill")
                                            .font(.system(size: 8.5))
                                        Text(Self.formatCountdown(rem))
                                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    }
                                    .lineLimit(1)
                                    .fixedSize()
                                    .foregroundStyle(NotchTheme.sageBadgeFill)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.black.opacity(0.08), in: Capsule())
                                } else if let targetMins = item.targetMinutes {
                                    HStack(spacing: 2.5) {
                                        Image(systemName: "timer")
                                            .font(.system(size: 8.5))
                                        Text("\(targetMins)m")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .lineLimit(1)
                                    .fixedSize()
                                    .foregroundStyle(NotchTheme.sageMuted)
                                }

                                if item.focusedMinutes > 0 {
                                    Text("Focused · \(item.focusedMinutes)m")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(NotchTheme.sageMuted)
                                        .lineLimit(1)
                                        .fixedSize()
                                }

                                if item.priority == .high && !item.isCompleted {
                                    HStack(spacing: 2.5) {
                                        Image(systemName: "flag.fill")
                                            .font(.system(size: 8.5))
                                        Text("High")
                                            .font(.system(size: 9, weight: .semibold))
                                    }
                                    .lineLimit(1)
                                    .fixedSize()
                                    .foregroundStyle(Color(red: 0.65, green: 0.22, blue: 0.14))
                                }

                                if let time = item.formattedDueTime() {
                                    let leadShort = item.reminderLeadMinutes.map { $0 == 0 ? " · at due" : " · -\($0)m" } ?? ""
                                    let countdownPart = dueCountdown.map { " (\($0))" } ?? ""
                                    HStack(spacing: 2.5) {
                                        Image(systemName: item.reminderLeadMinutes != nil ? "bell.badge" : "bell")
                                            .font(.system(size: 8.5))
                                        Text("\(time)\(countdownPart)\(leadShort)")
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .lineLimit(1)
                                    .fixedSize()
                                    .foregroundStyle(NotchTheme.sageMuted)
                                }

                                if let tag = item.projectTag {
                                    HStack(spacing: 2.5) {
                                        Image(systemName: "briefcase")
                                            .font(.system(size: 8.5))
                                        Text(tag)
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .lineLimit(1)
                                    .fixedSize()
                                    .foregroundStyle(NotchTheme.sageMuted)
                                }

                                if let rec = item.recurrence.label {
                                    HStack(spacing: 2.5) {
                                        Image(systemName: "repeat")
                                            .font(.system(size: 8.5))
                                        Text(rec)
                                            .font(.system(size: 9, weight: .medium))
                                    }
                                    .lineLimit(1)
                                    .fixedSize()
                                    .foregroundStyle(NotchTheme.sageMuted)
                                }

                                if let joinURL = item.detectedMeetingURL {
                                    Button {
                                        model.joinMeeting(url: joinURL, title: item.title)
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "video.fill")
                                                .font(.system(size: 8.5))
                                            Text(MeetingLinkExtractor.serviceLabel(for: joinURL))
                                                .font(.system(size: 9, weight: .bold))
                                        }
                                        .lineLimit(1)
                                        .fixedSize()
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(NotchTheme.sageBadgeFill, in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    beginEditing(item)
                }

                Spacer(minLength: 2)

                if !item.isCompleted {
                    Button {
                        model.toggleFocus(on: item.id)
                    } label: {
                        Image(systemName: isRunningHere ? "pause.fill" : "play.fill")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(isRunningHere ? .white : NotchTheme.sageInk.opacity(0.68))
                            .frame(width: 18, height: 18)
                            .background(
                                Circle()
                                    .fill(isRunningHere ? NotchTheme.sageBadgeFill : Color.black.opacity(0.06))
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(isRunningHere ? "Pause task countdown" : "Start countdown for this task")
                }

                Button {
                    beginEditing(item)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.sageMuted.opacity(0.75))
                        .frame(width: 17, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit task")

                TaskActionsMenu(
                    model: model,
                    item: item,
                    iconColor: NotchTheme.sageMuted.opacity(0.8),
                    onStartEdit: { beginEditing(item) }
                )
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isLinkedTask ? Color.black.opacity(0.08) : Color.clear)
            )
        }
    }

    private func beginEditing(_ item: TaskItem) {
        editingTaskID = item.id
        editTitle = item.title
        editPriority = item.priority
        editBucket = item.scheduledBucket
        editDayKey = item.scheduledDayKey
        editTargetMinutes = item.targetMinutes
        editDueDate = item.dueDate
        editReminderLeadMinutes = item.reminderLeadMinutes
    }

    private func submitDraftTask() {
        if dictationTarget == .taskInput {
            model.voiceCapture.stopRecording()
            dictationTarget = nil
        }
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let command = WorkspaceQuickCommand.parse(trimmed) {
            model.executeWorkspaceCommand(command)
            draftTitle = ""
            newPriority = .normal
            return
        }

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

    private static func formatCountdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Column 2: Matte Pastel Lavender Focus Countdown Card

    private var lavenderFocusCard: some View {
        let openTasks = model.tasks.filter { !$0.isCompleted }
        let linkedTask = model.activeFocusTask
        let isRunning = model.timer.state == .running
        let statusLabel: String = {
            switch model.timer.state {
            case .running:
                return model.timer.phase == .shortBreak ? "Break" : "Focusing"
            case .paused:
                return "Paused"
            case .idle:
                return model.timer.phase == .shortBreak ? "Break Ready" : "Ready"
            }
        }()

        return VStack(spacing: 0) {
            Capsule()
                .fill(Color.black.opacity(0.16))
                .frame(width: 22, height: 3)
                .padding(.bottom, 10)

            // Task selector dropdown matching screenshot top pill
            Menu {
                Button {
                    model.selectFocusTask(nil)
                } label: {
                    HStack {
                        Text("Free focus (\(model.settings.focusMinutes)m)")
                        if linkedTask == nil { Image(systemName: "checkmark") }
                    }
                }

                if !openTasks.isEmpty {
                    Divider()
                    ForEach(openTasks) { task in
                        Button {
                            model.selectFocusTask(task.id)
                        } label: {
                            let label = task.targetMinutes.map { "\(task.title) (\($0)m)" } ?? task.title
                            HStack {
                                Text(label)
                                if linkedTask?.id == task.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(linkedTask?.title ?? "Free focus")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTheme.lavenderInk)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(NotchTheme.lavenderPaperMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity)
                .background(NotchTheme.lavenderPaperPill, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)

            Spacer(minLength: 10)

            // Dot-Matrix Digital Countdown Clock
            DotMatrixClockView(
                timeString: model.timer.formattedRemaining,
                dotColor: NotchTheme.lavenderInk
            )
            .frame(height: 36)

            Text(statusLabel)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(NotchTheme.lavenderPaperMuted)
                .padding(.top, 7)

            // Progress hairline
            GeometryReader { barGeo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.10))
                        .frame(height: 1.5)
                    Capsule()
                        .fill(NotchTheme.lavenderInk.opacity(0.65))
                        .frame(width: max(0, barGeo.size.width * model.timer.progress), height: 1.5)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 14)
            .padding(.top, 14)

            // Primary Start / Pause + Complete / Reset buttons
            HStack(spacing: 8) {
                Button {
                    model.toggleFocusPlayPause()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isRunning ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(isRunning ? "Pause" : (model.timer.state == .paused ? "Resume" : "Start"))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7.5)
                    .background(NotchTheme.lavenderPaperButton, in: Capsule())
                }
                .buttonStyle(.plain)

                if linkedTask != nil {
                    Button {
                        model.completeActiveFocusTask()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NotchTheme.lavenderInk)
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Complete linked task and log focus time")
                } else {
                    Button {
                        model.resetFocusTimer()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NotchTheme.lavenderInk)
                            .frame(width: 28, height: 28)
                            .background(Color.black.opacity(0.10), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset countdown timer")
                }
            }
            .padding(.top, 14)

            if linkedTask != nil && model.timer.state != .idle {
                Button {
                    model.resetFocusTimer()
                } label: {
                    Text("Reset")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(NotchTheme.lavenderPaperMuted)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }

            Spacer(minLength: 10)

            // Footer: Set time + sound mute/selector
            HStack(spacing: 8) {
                Menu {
                    let currentMins = model.effectiveFocusMinutes(for: linkedTask)
                    ForEach([10, 15, 25, 30, 45, 60, 90], id: \.self) { mins in
                        Button {
                            model.setFocusDuration(minutes: mins, for: linkedTask?.id)
                        } label: {
                            HStack {
                                Text("\(mins) minutes")
                                if currentMins == mins {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button("+5 minutes") {
                        model.setFocusDuration(minutes: currentMins + 5, for: linkedTask?.id)
                    }
                    Button("-5 minutes") {
                        model.setFocusDuration(minutes: max(1, currentMins - 5), for: linkedTask?.id)
                    }
                    if linkedTask != nil {
                        Divider()
                        Button("Open Full Focus View") {
                            model.activeTab = .timer
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Set time")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundStyle(NotchTheme.lavenderPaperMuted)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Set countdown duration for \(linkedTask?.title ?? "Focus")")

                Spacer()

                Menu {
                    ForEach(FocusSoundscape.allCases) { sound in
                        Button {
                            model.selectSoundscape(sound)
                        } label: {
                            HStack {
                                Text(sound.label)
                                if model.settings.focusSoundscape == sound {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button(model.isAmbientPreviewActive ? "Stop Preview" : "Preview Audio") {
                        model.toggleAmbientPreview()
                    }
                } label: {
                    Image(systemName: model.settings.focusSoundscape == .none ? "speaker.slash" : "speaker.wave.2")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.lavenderPaperMuted)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Focus soundscape (\(model.settings.focusSoundscape.label))")
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(NotchTheme.lavenderPaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Column 3: Warm Matte Sand Yellow Inline Notepad

    private var yellowNotepadCard: some View {
        let noteIndex = model.selectedNoteIndex
        let note = noteIndex.map { model.notes[$0] }
        let noteBody = note?.body ?? ""
        let wordCount = noteBody
            .split { $0.isWhitespace || $0.isNewline }
            .count

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                Capsule()
                    .fill(Color.black.opacity(0.16))
                    .frame(width: 22, height: 3)
                Spacer()
            }
            .padding(.bottom, 2)

            // Header row: icon + Notepad selector + utility actions
            HStack(spacing: 5) {
                Menu {
                    ForEach(model.notes) { entry in
                        Button {
                            model.selectedNoteID = entry.id
                        } label: {
                            HStack {
                                Text(dropdownLabel(for: entry))
                                if entry.id == note?.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        model.addNote()
                        onRequestFocus()
                        isNotepadFocused = true
                        notepadController.focus()
                    } label: {
                        Label("New Note", systemImage: "plus")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NotchTheme.yellowInk.opacity(0.75))
                        Text(displayNoteTitle(note))
                            .font(.system(size: 13.5, weight: .bold, design: .rounded))
                            .foregroundStyle(NotchTheme.yellowInk)
                            .lineLimit(1)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                Spacer()

                Menu {
                    if let note {
                        Button("Convert Lines to Tasks") {
                            let added = model.convertNoteLinesToTasks(note.id)
                            notepadFeedback = added > 0 ? "+\(added) tasks" : "No lines"
                            Task {
                                try? await Task.sleep(for: .seconds(1.8))
                                notepadFeedback = nil
                            }
                        }
                        Button("Copy Note") {
                            model.copyNoteToPasteboard(note)
                        }
                        Divider()
                    }
                    Button("New Note") {
                        model.addNote()
                        onRequestFocus()
                        isNotepadFocused = true
                        notepadController.focus()
                    }
                    Button("Open Notes Library") {
                        model.activeTab = .notes
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NotchTheme.yellowMuted)
                        .frame(width: 20, height: 20)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Note actions")
            }

            let displayedDate = note?.dailyDayKey.flatMap { DailyFocusStats.date(fromDayKey: $0) }
                ?? note?.updatedAt
                ?? Date()
            HStack(spacing: 6) {
                Text(Self.fullDateFormatter.string(from: displayedDate))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NotchTheme.yellowMuted)

                if let feedback = notepadFeedback ?? model.autoConvertedNoteBanner {
                    Text(feedback)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(NotchTheme.yellowInk)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(NotchTheme.yellowPillFill, in: Capsule())
                }
            }

            ZStack(alignment: .topLeading) {
                if noteBody.isEmpty {
                    Text("Notes, bullets (- ), or '! ' / '[] ' for auto-todos…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(NotchTheme.yellowMuted.opacity(0.65))
                        .padding(.top, 4)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }

                if let note {
                    RichTextNoteView(
                        noteID: note.id,
                        plainText: note.body,
                        rtfData: note.rtfData,
                        inkColor: NotchTheme.yellowInkNS,
                        baseFontSize: 11.5,
                        controller: notepadController,
                        onRequestFocus: {
                            onRequestFocus()
                            isAddingFocused = false
                        },
                        onFocusChange: { focused in
                            isNotepadFocused = focused
                        },
                        onContentChange: { newPlain, newRTF, commitLastLine in
                            model.updateNoteBody(
                                note.id,
                                body: newPlain,
                                rtfData: newRTF,
                                commitTodoPrefixes: commitLastLine
                            )
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            RichTextFormatBar(
                controller: notepadController,
                inkColor: NotchTheme.yellowInk,
                mutedColor: NotchTheme.yellowMuted,
                activePillColor: NotchTheme.yellowPillFill,
                compact: true,
                onActionComplete: {
                    onRequestFocus()
                    notepadController.focus()
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            dottedSeparator

            // Word count + voice dictation footer
            HStack(spacing: 6) {
                Label("\(wordCount) \(wordCount == 1 ? "word" : "words")", systemImage: "text.alignleft")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(NotchTheme.yellowMuted)

                Spacer()

                Button {
                    guard let note else { return }
                    onRequestFocus()
                    let isCurrentlyRecordingNote: Bool
                    if case .notepad(let activeID, _) = dictationTarget, activeID == note.id, model.voiceCapture.isRecording {
                        isCurrentlyRecordingNote = true
                    } else {
                        isCurrentlyRecordingNote = false
                    }

                    if isCurrentlyRecordingNote {
                        model.voiceCapture.stopRecording()
                        dictationTarget = nil
                    } else {
                        let base = note.body
                        let prefix = base.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? ""
                            : (base.hasSuffix("\n") ? base : base + "\n")
                        dictationTarget = .notepad(noteID: note.id, baseBody: prefix)
                        model.voiceCapture.onTranscriptUpdated = { spoken in
                            model.updateNoteBody(note.id, body: prefix + spoken)
                        }
                        Task {
                            await model.voiceCapture.toggleRecording()
                        }
                    }
                } label: {
                    let recordingHere: Bool = {
                        if case .notepad = dictationTarget, model.voiceCapture.isRecording {
                            return true
                        }
                        return false
                    }()
                    if recordingHere {
                        AnimatedWaveformView(
                            isActive: true,
                            barColor: NotchTheme.coralAlert,
                            barWidth: 1.8,
                            maxHeight: 10
                        )
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(NotchTheme.yellowMuted)
                            .frame(width: 20, height: 20)
                    }
                }
                .buttonStyle(.plain)
                .help("Dictate into Notepad")
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NotchTheme.yellowPaper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func displayNoteTitle(_ note: NoteEntry?) -> String {
        guard let note else { return "Notepad" }
        let title = note.title
        if note.dailyDayKey == DailyFocusStats.todayKey() || title.isEmpty || title == "Daily Notepad" || title == "Scratchpad" || title.hasPrefix("Daily ") {
            return "Notepad"
        }
        return title
    }

    private func dropdownLabel(for entry: NoteEntry) -> String {
        let baseTitle = entry.title.isEmpty ? "Untitled" : entry.title
        if let dayKey = entry.dailyDayKey,
           let date = DailyFocusStats.date(fromDayKey: dayKey) {
            let dateStr = Self.dateHeaderFormatter.string(from: date)
            return baseTitle.contains(dateStr) ? baseTitle : "\(dateStr) · \(baseTitle)"
        }
        return baseTitle
    }

    // MARK: - Column 4: Misty Steel-Blue 7-Day Calendar

    private var weekDaysWindow: [Date] {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: startToday) }
    }

    private var steelBlueCalendarCard: some View {
        let cal = Calendar.current
        let dayEvents = model.events(on: selectedCalendarDate)
        let dayTimedTasks = model.timedTasks(on: selectedCalendarDate)
        let now = Date()
        let heroEventID = dayEvents.first(where: { !$0.isAllDay && $0.endDate > now && $0.meetingURL != nil })?.id
            ?? dayEvents.first(where: { !$0.isAllDay && $0.endDate > now })?.id

        return VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 6) {
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
                            VStack(spacing: 2.5) {
                                Text(Self.dayInitialFormatter.string(from: day))
                                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
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
                                        .font(.system(size: 11.5, weight: isSelected ? .bold : .semibold, design: .rounded))
                                        .foregroundStyle(isSelected ? .white : NotchTheme.steelBlueInk)
                                }
                                .frame(width: 23, height: 23)

                                Circle()
                                    .fill(NotchTheme.steelBlueInk.opacity(hasDot ? 0.65 : 0.0))
                                    .frame(width: 3, height: 3)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if model.eventKit.calendarAuth == .notDetermined {
                HStack(spacing: 6) {
                    Text("Connect Apple Calendar for meetings")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.steelBlueInk)
                        .lineLimit(1)
                    Spacer()
                    Button("Connect") {
                        Task { _ = await model.eventKit.requestCalendarAccess() }
                    }
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(NotchTheme.steelBlueSelectedCircle, in: Capsule())
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else if model.eventKit.calendarAuth == .denied {
                HStack(spacing: 6) {
                    Text("Calendar permission off")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(NotchTheme.steelBlueInk)
                    Spacer()
                    Button("Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(NotchTheme.steelBlueSelectedCircle, in: Capsule())
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if dayEvents.isEmpty && dayTimedTasks.isEmpty {
                VStack(spacing: 5) {
                    Spacer()
                    Image(systemName: "calendar")
                        .font(.system(size: 18))
                        .foregroundStyle(NotchTheme.steelBlueMuted.opacity(0.7))
                    Text("No scheduled meetings or timed reminders on this day")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(NotchTheme.steelBlueMuted)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 6) {
                        ForEach(buildTimelineEntries(events: dayEvents, tasks: dayTimedTasks)) { entry in
                            timelineRow(entry, heroEventID: heroEventID, now: now)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            dottedSeparator

            // Calendar status footer matching screenshot
            HStack(spacing: 7) {
                HStack(spacing: 4) {
                    Image(systemName: model.eventKit.calendarAuth == .authorized ? "checkmark.circle" : "calendar.badge.exclamationmark")
                        .font(.system(size: 10, weight: .semibold))
                    Text(model.eventKit.calendarAuth == .authorized ? "Connected" : "Not Connected")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(NotchTheme.steelBlueMuted)

                Spacer()

                Button {
                    model.eventKit.refreshEvents()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchTheme.steelBlueMuted)
                }
                .buttonStyle(.plain)
                .help("Refresh calendar events")

                Button {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(NotchTheme.steelBlueMuted)
                }
                .buttonStyle(.plain)
                .help("Open Apple Calendar")

                Menu {
                    Button("Refresh Events") {
                        model.eventKit.refreshEvents()
                    }
                    Button("Open Hub Dashboard") {
                        model.activeTab = .hub
                    }
                    if model.settings.syncReminders {
                        Button("Sync Reminders") {
                            Task { await model.syncWithReminders() }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(NotchTheme.steelBlueMuted)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    private func timelineRow(_ entry: TimelineEntry, heroEventID: String?, now: Date) -> some View {
        switch entry {
        case .event(let event):
            let isHero = event.id == heroEventID
            HStack(alignment: .top, spacing: 6) {
                if event.isAllDay {
                    Text("All\nday")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(NotchTheme.steelBlueMuted)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 30, alignment: .trailing)
                } else {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Self.timelineHourFormatter.string(from: event.startDate))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.steelBlueInk)
                        Text(Self.timelinePeriodFormatter.string(from: event.startDate))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(NotchTheme.steelBlueMuted)
                    }
                    .frame(width: 30, alignment: .trailing)
                    .padding(.top, 2)
                }

                if isHero {
                    VStack(alignment: .leading, spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            Text("\(event.statusLabel(relativeTo: now)) · \(event.calendarTitle)")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.68))
                                .lineLimit(1)

                            if let travelMins = event.travelTimeMinutes, let leaveDate = event.leaveByDate {
                                Label(
                                    "\(travelMins)m · Leave \(Self.leaveTimeFormatter.string(from: leaveDate))",
                                    systemImage: "car.fill"
                                )
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(NotchTheme.skyWave)
                            }
                        }

                        if let meetingURL = event.meetingURL {
                            HStack(spacing: 6) {
                                Button {
                                    model.joinMeeting(url: meetingURL, title: event.title)
                                } label: {
                                    Label("Join \(event.meetingServiceLabel ?? "Meet")", systemImage: "video.fill")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.14), in: Capsule())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    model.activeTab = .mirror
                                    model.updateMirrorActivation()
                                } label: {
                                    Image(systemName: "person.crop.viewfinder")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.82))
                                        .frame(width: 24, height: 24)
                                        .background(Color.white.opacity(0.12), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Pre-call Camera Check")

                                Button {
                                    _ = model.openOrCreateMeetingNote(title: event.title, date: event.startDate, switchToNotes: false)
                                    notepadFeedback = "Prep Ready"
                                    Task {
                                        try? await Task.sleep(for: .seconds(1.8))
                                        notepadFeedback = nil
                                    }
                                } label: {
                                    Image(systemName: "note.text")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.82))
                                        .frame(width: 24, height: 24)
                                        .background(Color.white.opacity(0.12), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Load Meeting Prep Note into Notepad")
                            }
                        }
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NotchTheme.calendarHeroCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    HStack(spacing: 5) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(NotchTheme.steelBlueInk)
                                .lineLimit(1)

                            Text("\(event.calendarTitle) · \(event.durationMinutes) min")
                                .font(.system(size: 9.5))
                                .foregroundStyle(NotchTheme.steelBlueMuted)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 2)

                        if let meetingURL = event.meetingURL {
                            Button {
                                model.joinMeeting(url: meetingURL, title: event.title)
                            } label: {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 9.5, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(NotchTheme.steelBlueSelectedCircle, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Join \(event.meetingServiceLabel ?? "Call")")
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6.5)
                    .background(NotchTheme.steelBlueRowFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }

        case .task(let task):
            HStack(spacing: 6) {
                if let due = task.dueDate {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Self.timelineHourFormatter.string(from: due))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.steelBlueInk)
                        Text(Self.timelinePeriodFormatter.string(from: due))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(NotchTheme.steelBlueMuted)
                    }
                    .frame(width: 30, alignment: .trailing)
                } else {
                    Text("Task")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(NotchTheme.steelBlueMuted)
                        .frame(width: 30, alignment: .trailing)
                }

                HStack(spacing: 5) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(task.isCompleted ? NotchTheme.steelBlueMuted : NotchTheme.steelBlueInk)
                            .strikethrough(task.isCompleted)
                            .lineLimit(1)

                        let sub = task.dueCountdownLabel(relativeTo: now).map { "Due \($0)" }
                            ?? (task.projectTag.map { "Task · #\($0)" } ?? "Scheduled task")
                        Text(sub)
                            .font(.system(size: 9.5))
                            .foregroundStyle(NotchTheme.steelBlueMuted)
                    }

                    Spacer(minLength: 2)

                    if let joinURL = task.detectedMeetingURL {
                        Button {
                            model.joinMeeting(url: joinURL, title: task.title)
                        } label: {
                            Label("Join", systemImage: "video.fill")
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(NotchTheme.steelBlueSelectedCircle, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        model.toggleTask(task.id)
                    } label: {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 14))
                            .foregroundStyle(task.isCompleted ? NotchTheme.mintComplete : NotchTheme.steelBlueInk.opacity(0.65))
                            .frame(width: 20, height: 20)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6.5)
                .background(NotchTheme.steelBlueRowFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }
}

// MARK: - Crisp 5x7 Dot-Matrix Clock Display

private struct DotMatrixClockView: View {
    let timeString: String
    let dotColor: Color

    private static let glyphs: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ":": ["00", "01", "01", "00", "01", "01", "00"]
    ]

    var body: some View {
        Canvas { context, size in
            let chars = Array(timeString)
            let colsPerChar: [Int] = chars.map { Self.glyphs[$0]?.first?.count ?? 5 }
            let charGapCols: CGFloat = 1.6
            let totalCols = CGFloat(colsPerChar.reduce(0, +)) + charGapCols * CGFloat(max(0, chars.count - 1))
            let totalRows: CGFloat = 7

            let step = min(size.width / max(1, totalCols), size.height / totalRows)
            let dotDiameter = max(2.2, step * 0.72)
            let renderedWidth = totalCols * step
            let originX = (size.width - renderedWidth) / 2
            let originY = (size.height - (totalRows * step)) / 2

            var colOffset: CGFloat = 0
            for (index, ch) in chars.enumerated() {
                let rows = Self.glyphs[ch] ?? Self.glyphs["0"]!
                for (rIdx, rowStr) in rows.enumerated() {
                    for (cIdx, bit) in rowStr.enumerated() where bit == "1" {
                        let cx = originX + (colOffset + CGFloat(cIdx) + 0.5) * step
                        let cy = originY + (CGFloat(rIdx) + 0.5) * step
                        let rect = CGRect(
                            x: cx - dotDiameter / 2,
                            y: cy - dotDiameter / 2,
                            width: dotDiameter,
                            height: dotDiameter
                        )
                        context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    }
                }
                colOffset += CGFloat(colsPerChar[index]) + charGapCols
            }
        }
        .accessibilityLabel(timeString)
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

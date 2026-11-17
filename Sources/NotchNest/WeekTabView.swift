import AppKit
import NotchNestCore
import SwiftUI

struct WeekTabView: View {
    @Bindable var model: NotchNestModel
    let onRequestFocus: () -> Void

    @State private var addingColumnID: String?
    @State private var inlineDraft = ""
    @State private var targetedColumnID: String?
    @State private var scrollAnchorIndex = 0
    @State private var editingTaskID: UUID?
    @State private var editTitle = ""
    @State private var editPriority: TaskPriority = .normal
    @State private var editBucket: TaskBucket = .today
    @State private var editDayKey: String?
    @State private var editTargetMinutes: Int?
    @State private var editDueDate: Date?
    @State private var editReminderLeadMinutes: Int?
    @FocusState private var inlineFieldFocused: Bool

    private static let dayNumberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    var body: some View {
        let columns = model.weekPlanColumns()

        return ScrollViewReader { scrollProxy in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Upcoming")
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(weekRangeLabel)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.48))

                    Spacer()

                    Text("Scroll across all 7 days · Drag tasks to reschedule")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.42))

                    HStack(spacing: 4) {
                        Button {
                            scrollAnchorIndex = max(0, scrollAnchorIndex - 2)
                            if columns.indices.contains(scrollAnchorIndex) {
                                withAnimation(.easeInOut(duration: 0.24)) {
                                    scrollProxy.scrollTo(columns[scrollAnchorIndex].id, anchor: .leading)
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(scrollAnchorIndex > 0 ? 0.85 : 0.35))
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Scroll left")

                        Button {
                            scrollAnchorIndex = min(max(0, columns.count - 1), scrollAnchorIndex + 2)
                            if columns.indices.contains(scrollAnchorIndex) {
                                withAnimation(.easeInOut(duration: 0.24)) {
                                    scrollProxy.scrollTo(columns[scrollAnchorIndex].id, anchor: .leading)
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.white.opacity(scrollAnchorIndex < columns.count - 1 ? 0.85 : 0.35))
                                .frame(width: 22, height: 22)
                                .background(Color.white.opacity(0.08), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Scroll right through full week")
                    }
                }

                GeometryReader { geo in
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(spacing: 12) {
                            ForEach(columns) { column in
                                kanbanColumn(for: column, allColumns: columns)
                                    .frame(width: 274, height: max(220, geo.size.height - 8))
                                    .id(column.id)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var weekRangeLabel: String {
        let today = Date()
        let end = Calendar.current.date(byAdding: .day, value: 6, to: today) ?? today
        return "\(Self.dayNumberFormatter.string(from: today)) – \(Self.dayNumberFormatter.string(from: end))"
    }

    private func columnTitle(for column: WeekPlanColumn) -> String {
        switch column {
        case .inbox:
            return "Inbox"
        case .day(_, let date, let offset):
            if offset == 0 { return "Today" }
            if offset == 1 { return "Tomorrow" }
            return Self.weekdayFormatter.string(from: date)
        case .later:
            return "Later"
        }
    }

    private func columnSubtitle(for column: WeekPlanColumn) -> String? {
        switch column {
        case .inbox:
            return nil
        case .day(_, let date, _):
            return Self.dayNumberFormatter.string(from: date)
        case .later:
            return "Next week+"
        }
    }

    private func isTodayColumn(_ column: WeekPlanColumn) -> Bool {
        if case .day(_, _, let offset) = column {
            return offset == 0
        }
        return false
    }

    @ViewBuilder
    private func kanbanColumn(for column: WeekPlanColumn, allColumns: [WeekPlanColumn]) -> some View {
        let isToday = isTodayColumn(column)
        let columnTasks = model.tasks(forColumn: column)
        let isTargeted = targetedColumnID == column.id

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                if case .inbox = column {
                    Image(systemName: "tray")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Text(columnTitle(for: column))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(isToday ? NotchTheme.sageInk : .white.opacity(0.92))

                if let sub = columnSubtitle(for: column) {
                    Text(sub)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(isToday ? NotchTheme.sageMuted : .white.opacity(0.48))
                }

                Spacer()

                Text("\(columnTasks.filter { !$0.isCompleted }.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(isToday ? NotchTheme.sageInk.opacity(0.75) : .white.opacity(0.65))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        isToday ? Color.black.opacity(0.08) : Color.white.opacity(0.08),
                        in: Capsule()
                    )
            }

            Divider()
                .overlay(isToday ? Color.black.opacity(0.10) : Color.white.opacity(0.08))

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 5) {
                    ForEach(columnTasks) { item in
                        kanbanTaskCard(item, isTodayColumn: isToday, allColumns: allColumns)
                    }
                }
                .padding(.vertical, 1)
            }

            Spacer(minLength: 0)

            if addingColumnID == column.id {
                HStack(spacing: 5) {
                    TextField("Task title…", text: $inlineDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(isToday ? NotchTheme.sageInk : .white)
                        .focused($inlineFieldFocused)
                        .onSubmit {
                            submitInlineTask(into: column)
                        }

                    Button {
                        submitInlineTask(into: column)
                    } label: {
                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isToday ? NotchTheme.sageInk : Color.amberGlow)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    isToday ? NotchTheme.sageInputFill : Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8)
                )
            } else {
                Button {
                    addingColumnID = column.id
                    inlineDraft = ""
                    onRequestFocus()
                    inlineFieldFocused = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("Add task")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(isToday ? NotchTheme.sageMuted : .white.opacity(0.58))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isToday ? NotchTheme.sagePaper : NotchTheme.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isTargeted
                        ? NotchTheme.skyWave
                        : (isToday ? Color.clear : Color.white.opacity(0.08)),
                    lineWidth: isTargeted ? 1.5 : 1
                )
        )
        .dropDestination(for: String.self) { droppedIDs, _ in
            var handled = false
            for rawID in droppedIDs {
                if let uuid = UUID(uuidString: rawID) {
                    model.moveTask(uuid, toColumn: column)
                    handled = true
                }
            }
            return handled
        } isTargeted: { hovering in
            targetedColumnID = hovering ? column.id : (targetedColumnID == column.id ? nil : targetedColumnID)
        }
    }

    @ViewBuilder
    private func kanbanTaskCard(_ item: TaskItem, isTodayColumn: Bool, allColumns: [WeekPlanColumn]) -> some View {
        if editingTaskID == item.id {
            TaskInlineEditorRow(
                title: $editTitle,
                priority: $editPriority,
                bucket: $editBucket,
                dayKey: $editDayKey,
                targetMinutes: $editTargetMinutes,
                dueDate: $editDueDate,
                reminderLeadMinutes: $editReminderLeadMinutes,
                columns: allColumns,
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
                isDarkSurface: !isTodayColumn
            )
        } else {
            HStack(alignment: .top, spacing: 5) {
                Button {
                    model.toggleTask(item.id)
                } label: {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(
                            item.isCompleted
                                ? NotchTheme.mintComplete
                                : (isTodayColumn ? NotchTheme.sageInk.opacity(0.55) : .white.opacity(0.45))
                        )
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(
                            item.isCompleted
                                ? (isTodayColumn ? NotchTheme.sageMuted.opacity(0.6) : .white.opacity(0.4))
                                : (isTodayColumn ? NotchTheme.sageInk : .white.opacity(0.92))
                        )
                        .strikethrough(item.isCompleted)
                        .lineLimit(2)

                    if item.dueDate != nil || item.projectTag != nil || item.recurrence != .none || item.detectedMeetingURL != nil {
                        HStack(spacing: 4) {
                            if let time = item.formattedDueTime() {
                                Text(time)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(isTodayColumn ? NotchTheme.sageMuted : .white.opacity(0.55))
                            }
                            if let tag = item.projectTag {
                                Text("#\(tag)")
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(isTodayColumn ? NotchTheme.sageBadgeFill : NotchTheme.lavenderSoft)
                            }
                            if let rec = item.recurrence.label {
                                Text(rec)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(isTodayColumn ? NotchTheme.sageMuted : .white.opacity(0.45))
                            }
                            if let joinURL = item.detectedMeetingURL {
                                Button {
                                    model.joinMeeting(url: joinURL, title: item.title)
                                } label: {
                                    Label("Join \(MeetingLinkExtractor.serviceLabel(for: joinURL))", systemImage: "video.fill")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(isTodayColumn ? .white : .black)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(isTodayColumn ? NotchTheme.sageBadgeFill : NotchTheme.peachAction, in: Capsule())
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

                Spacer(minLength: 2)

                if !item.isCompleted {
                    Button {
                        model.startFocus(on: item.id)
                        model.activeTab = .timer
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8.5))
                            .foregroundStyle(isTodayColumn ? NotchTheme.sageMuted : .white.opacity(0.5))
                            .frame(width: 18, height: 18)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Focus on this task")
                }

                TaskActionsMenu(
                    model: model,
                    item: item,
                    iconColor: isTodayColumn ? NotchTheme.sageMuted.opacity(0.85) : .white.opacity(0.55),
                    onStartEdit: { beginEditing(item) }
                )

                Button {
                    model.deleteTask(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(isTodayColumn ? NotchTheme.sageMuted.opacity(0.75) : .white.opacity(0.45))
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Delete task")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isTodayColumn ? NotchTheme.sageRowFill : Color.white.opacity(0.045))
            )
            .contextMenu {
                Button("Edit Task") { beginEditing(item) }
                Button("Delete Task", role: .destructive) { model.deleteTask(item.id) }
            }
            .draggable(item.id.uuidString)
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

    private func submitInlineTask(into column: WeekPlanColumn) {
        let trimmed = inlineDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            addingColumnID = nil
            return
        }
        model.addParsedTask(trimmed, defaultBucket: column.bucket, defaultDayKey: column.dayKey)
        inlineDraft = ""
        addingColumnID = nil
    }
}

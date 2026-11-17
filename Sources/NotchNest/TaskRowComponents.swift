import NotchNestCore
import SwiftUI

struct TaskActionsMenu: View {
    @Bindable var model: NotchNestModel
    let item: TaskItem
    let iconColor: Color
    let onStartEdit: () -> Void

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()

    var body: some View {
        Menu {
            Button {
                onStartEdit()
            } label: {
                Label("Edit Task", systemImage: "pencil")
            }

            if !item.isCompleted {
                Button {
                    model.startFocus(on: item.id)
                    if model.activeTab != .today {
                        model.activeTab = .timer
                    }
                } label: {
                    Label("Focus on Task", systemImage: "play.fill")
                }

                Menu("Set Countdown") {
                    ForEach([15, 25, 45, 60, 90], id: \.self) { mins in
                        Button("\(mins) min") {
                            model.setFocusDuration(minutes: mins, for: item.id)
                        }
                    }
                }

                Menu("Pre-Due Reminder") {
                    Button("None") {
                        model.updateTask(
                            item.id,
                            title: item.title,
                            updateReminderLeadMinutes: true,
                            reminderLeadMinutes: nil
                        )
                    }
                    Divider()
                    ForEach([0, 5, 10, 15, 30], id: \.self) { mins in
                        Button(mins == 0 ? "At due time" : "\(mins) min before") {
                            let resolvedDue = item.dueDate ?? Date().addingTimeInterval(3600)
                            model.updateTask(
                                item.id,
                                title: item.title,
                                updateDueDate: item.dueDate == nil,
                                dueDate: resolvedDue,
                                updateReminderLeadMinutes: true,
                                reminderLeadMinutes: mins
                            )
                        }
                    }
                }

                Button {
                    model.pinTaskAsLiveNudge(item.id)
                } label: {
                    Label(
                        model.pinnedLiveActivityTaskID == item.id ? "Unpin Live Nudge" : "Pin Live Nudge",
                        systemImage: "bell.badge"
                    )
                }
            }

            Button {
                model.toggleTaskPriority(item.id)
            } label: {
                Label(
                    item.priority == .high ? "Normal Priority" : "High Priority",
                    systemImage: item.priority == .high ? "flag.slash" : "flag.fill"
                )
            }

            Menu("Move to") {
                ForEach(model.weekPlanColumns()) { column in
                    Button {
                        model.moveTask(item.id, toColumn: column)
                    } label: {
                        Text(label(for: column))
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                model.deleteTask(item.id)
            } label: {
                Label("Delete Task", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func label(for column: WeekPlanColumn) -> String {
        switch column {
        case .inbox:
            return "Inbox"
        case .day(_, let date, let offset):
            if offset == 0 { return "Today" }
            if offset == 1 { return "Tomorrow" }
            return Self.dayFmt.string(from: date)
        case .later:
            return "Later"
        }
    }
}

struct TaskInlineEditorRow: View {
    @Binding var title: String
    @Binding var priority: TaskPriority
    @Binding var bucket: TaskBucket
    @Binding var dayKey: String?
    @Binding var targetMinutes: Int?
    @Binding var dueDate: Date?
    @Binding var reminderLeadMinutes: Int?
    let columns: [WeekPlanColumn]
    let onRequestFocus: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    let isDarkSurface: Bool
    @FocusState private var isFocused: Bool

    private static let durationOptions: [Int?] = [nil, 15, 25, 45, 60]
    private static let reminderOptions: [(String, Int?)] = [
        ("Off", nil),
        ("At due", 0),
        ("5m", 5),
        ("10m", 10),
        ("15m", 15),
        ("30m", 30)
    ]

    private static let shortDayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Edit task…", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isDarkSurface ? .white : NotchTheme.sageInk)
                    .focused($isFocused)
                    .onAppear {
                        onRequestFocus()
                        isFocused = true
                    }
                    .onSubmit {
                        onSave()
                    }

                Button {
                    priority = (priority == .high) ? .normal : .high
                } label: {
                    Image(systemName: priority == .high ? "flag.fill" : "flag")
                        .font(.system(size: 10.5))
                        .foregroundStyle(priority == .high ? .orange : (isDarkSurface ? .white.opacity(0.6) : NotchTheme.sageMuted))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Toggle priority")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10.5))
                        .foregroundStyle(NotchTheme.coralAlert)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete task")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(columns) { col in
                        let selected = isColumnSelected(col)
                        Button {
                            bucket = col.bucket
                            dayKey = col.dayKey
                        } label: {
                            Text(chipTitle(for: col))
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(
                                    selected
                                        ? .white
                                        : (isDarkSurface ? .white.opacity(0.68) : NotchTheme.sageInk.opacity(0.75))
                                )
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(
                                    Capsule()
                                        .fill(
                                            selected
                                                ? NotchTheme.sageBadgeFill
                                                : (isDarkSurface ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    Text("Timer:")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isDarkSurface ? .white.opacity(0.55) : NotchTheme.sageMuted)
                        .lineLimit(1)
                        .fixedSize()

                    ForEach(Self.durationOptions.indices, id: \.self) { idx in
                        let option = Self.durationOptions[idx]
                        let selected = targetMinutes == option
                        Button {
                            targetMinutes = option
                        } label: {
                            Text(option.map { "\($0)m" } ?? "Auto")
                                .font(.system(size: 9.5, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(
                                    selected
                                        ? .white
                                        : (isDarkSurface ? .white.opacity(0.68) : NotchTheme.sageInk.opacity(0.75))
                                )
                                .padding(.horizontal, 6.5)
                                .padding(.vertical, 2.5)
                                .background(
                                    Capsule()
                                        .fill(
                                            selected
                                                ? NotchTheme.sageBadgeFill
                                                : (isDarkSurface ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let currentDue = dueDate {
                HStack(spacing: 5) {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { currentDue },
                            set: { dueDate = $0 }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .controlSize(.mini)
                    .fixedSize()
                    .colorScheme(isDarkSurface ? .dark : .light)

                    Spacer(minLength: 2)

                    Button {
                        dueDate = nil
                        reminderLeadMinutes = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(isDarkSurface ? .white.opacity(0.55) : NotchTheme.sageMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Clear due date")
                }
            }

            HStack(spacing: 6) {
                if dueDate != nil {
                    Menu {
                        ForEach(Self.reminderOptions.indices, id: \.self) { idx in
                            let opt = Self.reminderOptions[idx]
                            Button {
                                reminderLeadMinutes = opt.1
                            } label: {
                                HStack {
                                    Text(opt.0 == "Off" ? "No reminder" : (opt.0 == "At due" ? "At due time" : "\(opt.0) before"))
                                    if reminderLeadMinutes == opt.1 {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        let remLabel = reminderLeadMinutes.map { $0 == 0 ? "At due" : "\($0)m before" } ?? "Remind: Off"
                        HStack(spacing: 3) {
                            Image(systemName: "bell.badge")
                                .font(.system(size: 9))
                            Text(remLabel)
                                .font(.system(size: 9.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .fixedSize()
                        .foregroundStyle(
                            reminderLeadMinutes != nil
                                ? .white
                                : (isDarkSurface ? .white.opacity(0.75) : NotchTheme.sageInk)
                        )
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(
                                    reminderLeadMinutes != nil
                                        ? NotchTheme.sageBadgeFill
                                        : (isDarkSurface ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                                )
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                } else {
                    Button {
                        let nextHour = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
                        dueDate = nextHour
                        if reminderLeadMinutes == nil {
                            reminderLeadMinutes = 15
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 9))
                            Text("Due & Remind")
                                .font(.system(size: 9.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .fixedSize()
                        .foregroundStyle(isDarkSurface ? .white.opacity(0.78) : NotchTheme.sageInk.opacity(0.82))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(isDarkSurface ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 4)

                Button("Cancel", action: onCancel)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(isDarkSurface ? .white.opacity(0.68) : NotchTheme.sageMuted)
                    .buttonStyle(.plain)

                Button("Save", action: onSave)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(NotchTheme.peachAction, in: Capsule())
                    .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isDarkSurface ? Color.white.opacity(0.08) : Color.black.opacity(0.09))
        )
    }

    private func isColumnSelected(_ col: WeekPlanColumn) -> Bool {
        switch col {
        case .inbox:
            return bucket == .inbox && dayKey == nil
        case .day(let key, _, _):
            return dayKey == key
        case .later:
            return bucket == .upcoming && dayKey == nil
        }
    }

    private func chipTitle(for col: WeekPlanColumn) -> String {
        switch col {
        case .inbox: return "Inbox"
        case .day(_, let date, let offset):
            if offset == 0 { return "Today" }
            if offset == 1 { return "Tmr" }
            return Self.shortDayFmt.string(from: date)
        case .later: return "Later"
        }
    }
}

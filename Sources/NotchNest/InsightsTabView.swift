import NotchNestCore
import SwiftUI

struct InsightsTabView: View {
    @Bindable var model: NotchNestModel
    @State private var hoveredDayKey: String?

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                metricCard(
                    title: "Tasks completed",
                    value: "\(model.totalCompletedTasksMetric)",
                    subtitle: "\(model.todayCompletedCount) done today",
                    icon: "checkmark.circle.fill",
                    accent: NotchTheme.mintComplete
                )

                metricCard(
                    title: "Focus time",
                    value: formattedFocusHours(model.totalFocusedMinutesMetric),
                    subtitle: "\(model.focusStats.completedSessions) sessions today",
                    icon: "flame.fill",
                    accent: NotchTheme.peachAction
                )

                metricCard(
                    title: "Current streak",
                    value: "\(model.currentStreakDays)d",
                    subtitle: model.currentStreakDays > 0 ? "Active momentum" : "Complete a task today",
                    icon: "sparkles",
                    accent: NotchTheme.skyWave
                )

                metricCard(
                    title: "Best focus hour",
                    value: model.bestFocusHourRangeLabel,
                    subtitle: "Peak session window",
                    icon: "clock.fill",
                    accent: NotchTheme.lavenderSoft
                )
            }

            weeklyChartCard
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            screenTimeFooterCard
        }
    }

    private var screenTimeFooterCard: some View {
        let totalSecs = model.screenTimeService.stats.totalSeconds
        let categories = model.screenTimeService.categoryTotals.prefix(3)
        return HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NotchTheme.skyWave)

            Text("Screen Time Today:")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            Text(formattedFocusHours(max(0, totalSecs / 60)))
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            ForEach(Array(categories), id: \.category) { cat in
                Text("\(cat.category) \(max(1, cat.seconds / 60))m")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }

            Spacer()

            Button("Open Screen Time →") {
                model.selectedHubSection = .screenTime
                model.activeTab = .hub
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(NotchTheme.sagePaper)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func metricCard(
        title: String,
        value: String,
        subtitle: String,
        icon: String,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
            }

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var weeklyChartCard: some View {
        let records = model.recent7DayRecords
        let maxTasks = max(4, records.map(\.completedTasks).max() ?? 4)
        let maxFocus = max(30, records.map(\.focusedMinutes).max() ?? 30)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("7-Day Rhythm")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                HStack(spacing: 12) {
                    legendDot(color: NotchTheme.sagePaper, label: "Tasks done")
                    legendDot(color: NotchTheme.skyWave, label: "Focus mins")
                }
            }

            HStack(alignment: .bottom, spacing: 14) {
                ForEach(records) { record in
                    let isToday = record.dayKey == DailyFocusStats.todayKey()
                    let isHovered = hoveredDayKey == record.dayKey
                    let taskHeight = max(4, CGFloat(record.completedTasks) / CGFloat(maxTasks) * 92)
                    let focusHeight = max(4, CGFloat(record.focusedMinutes) / CGFloat(maxFocus) * 92)

                    VStack(spacing: 6) {
                        Spacer(minLength: 0)

                        if isHovered || record.completedTasks > 0 || record.focusedMinutes > 0 {
                            Text("\(record.completedTasks)t · \(record.focusedMinutes)m")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(isHovered ? 0.95 : 0.6))
                        }

                        HStack(alignment: .bottom, spacing: 4) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(NotchTheme.sagePaper.opacity(record.completedTasks > 0 ? 0.95 : 0.16))
                                .frame(width: 14, height: taskHeight)

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(NotchTheme.skyWave.opacity(record.focusedMinutes > 0 ? 0.92 : 0.16))
                                .frame(width: 14, height: focusHeight)
                        }
                        .frame(height: 96, alignment: .bottom)

                        Text(shortDayLabel(for: record.dayKey))
                            .font(.system(size: 10.5, weight: isToday ? .bold : .medium, design: .rounded))
                            .foregroundStyle(isToday ? NotchTheme.sagePaper : .white.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isHovered ? Color.white.opacity(0.05) : Color.clear)
                    )
                    .onHover { hovering in
                        hoveredDayKey = hovering ? record.dayKey : (hoveredDayKey == record.dayKey ? nil : hoveredDayKey)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func shortDayLabel(for key: String) -> String {
        guard let date = DailyFocusStats.date(fromDayKey: key) else { return key }
        return Self.weekdayFormatter.string(from: date)
    }

    private func formattedFocusHours(_ totalMinutes: Int) -> String {
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }
}

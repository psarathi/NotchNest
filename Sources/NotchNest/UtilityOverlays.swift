import AppKit
import CoreLocation
import NotchNestCore
import SwiftUI

struct WrapUpOverlayView: View {
    @Bindable var model: NotchNestModel
    let onDismiss: () -> Void

    @State private var reflection = ""
    @State private var statusMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Daily Wrap Up", systemImage: "moon.stars.fill")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.lavenderSoft)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                summaryChip(value: "\(model.todayCompletedCount)", label: "Done today", tint: NotchTheme.mintComplete)
                summaryChip(value: "\(model.todayOpenCount)", label: "Remaining", tint: NotchTheme.peachAction)
                summaryChip(value: "\(model.focusStats.focusedMinutes)m", label: "Focused", tint: NotchTheme.skyWave)
            }

            HStack(spacing: 8) {
                Button {
                    let moved = model.moveIncompleteTodayToTomorrow()
                    statusMessage = moved > 0 ? "Moved \(moved) open task(s) to Tomorrow." : "No open Today tasks to move."
                } label: {
                    Label("Move open to Tomorrow", systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(NotchTheme.sagePaper, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    let pulled = model.carryOverIncompleteToToday()
                    statusMessage = pulled > 0 ? "Pulled \(pulled) earlier task(s) into Today." : "Nothing older to carry over."
                } label: {
                    Label("Pull earlier tasks", systemImage: "arrow.uturn.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.09), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Quick reflection (saved to Daily Notepad)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))

                HStack(spacing: 6) {
                    TextField("How did today go? One win or note for tomorrow…", text: $reflection)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                        .onSubmit {
                            saveReflection()
                        }

                    Button("Save") {
                        saveReflection()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(NotchTheme.peachAction, in: Capsule())
                    .buttonStyle(.plain)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NotchTheme.sagePaper)
            }
        }
        .padding(16)
        .frame(width: 430)
        .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(NotchTheme.lavenderAccent.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 22, y: 8)
    }

    private func summaryChip(value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private func saveReflection() {
        let trimmed = reflection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let note = model.notes.first else { return }
        let stamp = DailyFocusStats.todayKey()
        let prefix = note.body.isEmpty ? "" : "\n\n"
        model.updateNoteBody(note.id, body: "\(note.body)\(prefix)[\(stamp) Wrap-up] \(trimmed)")
        reflection = ""
        statusMessage = "Saved reflection to Daily Notepad."
    }
}

struct DiagnosticsOverlayView: View {
    @Bindable var model: NotchNestModel
    let onDismiss: () -> Void
    var onCollapseAndPreview: (() -> Void)? = nil
    @State private var nudgeNote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("NotchNest Diagnostics", systemImage: "ladybug.fill")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(NotchTheme.peachAction)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 5) {
                diagRow("Architecture", "Intel x86_64 Clean-Room Build")
                diagRow("Calendar Events Loaded", "\(model.eventKit.upcomingEvents.count) upcoming (7-day window)")
                diagRow("Zoom/Call Links Found", "\(model.eventKit.upcomingEvents.filter { $0.meetingURL != nil }.count) event(s)")
                diagRow("Audio Engine", model.audioEngine.isPlaying ? "Playing (\(model.audioEngine.activeSoundscape.label))" : "Idle (\(model.settings.focusSoundscape.label))")
                diagRow("Drawer Mode", model.settings.isWideDrawer ? "Wide (940 × 520)" : "Standard (780 × 448)")
                diagRow("Location Auth", locationAuthLabel)
            }
            .padding(10)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                Button {
                    if let firstOpen = model.tasks.first(where: { !$0.isCompleted }) {
                        model.pinTaskAsLiveNudge(firstOpen.id)
                        nudgeNote = "Pinned \"\(firstOpen.title)\" — collapse drawer to inspect Live Activity pill."
                    } else {
                        nudgeNote = "Add an open task first to pin a Live Activity nudge."
                    }
                } label: {
                    Label("Pin Test Nudge", systemImage: "bell.badge")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(NotchTheme.peachAction, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    model.activeUtilityOverlay = nil
                    model.triggerLiveActivityPreview()
                    onCollapseAndPreview?()
                } label: {
                    Label("Preview Live Activity", systemImage: "sparkles.rectangle.stack")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(NotchTheme.skyWave, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    model.eventKit.refreshEvents()
                    nudgeNote = "Refreshed 7-day Calendar & Reminders."
                } label: {
                    Label("Refresh Calendar", systemImage: "arrow.clockwise")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.09), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    NSWorkspace.shared.open(model.persistence.baseDirectory)
                } label: {
                    Label("Data Folder", systemImage: "folder")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(NotchTheme.sagePaper)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.09), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if let nudgeNote {
                Text(nudgeNote)
                    .font(.system(size: 10.5))
                    .foregroundStyle(NotchTheme.sagePaper)
            }
        }
        .padding(16)
        .frame(width: 440)
        .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.55), radius: 22, y: 8)
    }

    private var locationAuthLabel: String {
        switch CLLocationManager().authorizationStatus {
        case .authorized, .authorizedAlways: return "Authorized"
        case .denied, .restricted: return "Denied"
        case .notDetermined: return "Not Requested"
        @unknown default: return "Unknown"
        }
    }

    private func diagRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

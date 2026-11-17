import NotchNestCore
import SwiftUI

struct TimerTabView: View {
    @Bindable var model: NotchNestModel

    private let focusPresets = [15, 25, 45, 60]
    private let breakPresets = [5, 10, 15]

    var body: some View {
        HStack(spacing: 14) {
            ringView
                .frame(width: 224)

            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 6) {
                    phaseButton(.focus)
                    phaseButton(.shortBreak)
                    Spacer()

                    Menu {
                        Button("No linked task") {
                            model.selectFocusTask(nil)
                        }
                        Divider()
                        ForEach(model.tasks.filter { !$0.isCompleted }) { task in
                            Button {
                                model.selectFocusTask(task.id)
                            } label: {
                                if let mins = task.targetMinutes {
                                    Text("\(task.title) (\(mins)m)")
                                } else {
                                    Text(task.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "target")
                                .font(.system(size: 10.5))
                            Text(model.activeFocusTask?.title ?? "Link a task")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(model.activeFocusTask != nil ? NotchTheme.sagePaper : .white.opacity(0.7))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    .menuStyle(.borderlessButton)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(model.timer.phase == .focus ? "Focus duration" : "Break duration")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))

                    HStack(spacing: 6) {
                        ForEach(model.timer.phase == .focus ? focusPresets : breakPresets, id: \.self) { mins in
                            let selected = Int(round(model.timer.totalDuration / 60)) == mins
                            Button("\(mins)m") {
                                model.timer.configure(minutes: mins, phase: model.timer.phase)
                                model.syncAmbientAudio()
                            }
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(selected ? .black : .white.opacity(0.82))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(selected ? NotchTheme.skyWave : Color.white.opacity(0.08))
                            )
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        model.toggleFocusPlayPause()
                    } label: {
                        Label(
                            model.timer.state == .running ? "Pause" : (model.timer.state == .paused ? "Resume" : "Start Focus"),
                            systemImage: model.timer.state == .running ? "pause.fill" : "play.fill"
                        )
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(NotchTheme.skyWave, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        model.resetFocusTimer()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Ambient Focus Soundscapes
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("Focus soundscapes")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))

                        AnimatedWaveformView(
                            isActive: model.audioEngine.isPlaying,
                            barColor: NotchTheme.skyWave,
                            barWidth: 2.5,
                            maxHeight: 11
                        )

                        Spacer()

                        Button {
                            model.toggleAmbientPreview()
                        } label: {
                            Text(model.isAmbientPreviewActive ? "Stop Preview" : "Preview")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(model.isAmbientPreviewActive ? NotchTheme.peachAction : NotchTheme.skyWave)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 6) {
                        ForEach(FocusSoundscape.allCases) { sound in
                            let selected = model.settings.focusSoundscape == sound
                            Button {
                                model.selectSoundscape(sound)
                            } label: {
                                Label(sound.label, systemImage: sound.systemImage)
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(selected ? .black : .white.opacity(0.82))
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(selected ? NotchTheme.lavenderSoft : Color.white.opacity(0.07))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "speaker.wave.1")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                        Slider(value: $model.settings.focusSoundVolume, in: 0.05...1.0)
                            .tint(NotchTheme.skyWave)
                            .controlSize(.mini)
                        Image(systemName: "speaker.wave.3")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(9)
                .background(NotchTheme.lavenderCard, in: RoundedRectangle(cornerRadius: 12))

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    statPill(
                        icon: "flame.fill",
                        value: "\(model.focusStats.completedSessions)",
                        label: "sessions today"
                    )
                    statPill(
                        icon: "clock.fill",
                        value: "\(model.focusStats.focusedMinutes)m",
                        label: "focused"
                    )
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
    }

    private var ringView: some View {
        let accent: Color = model.timer.phase == .focus ? NotchTheme.skyWave : NotchTheme.mintComplete

        return ZStack {
            Circle()
                .stroke(Color.white.opacity(0.08), lineWidth: 11)

            Circle()
                .trim(from: 0, to: model.timer.progress)
                .stroke(
                    accent,
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: model.timer.progress)

            VStack(spacing: 5) {
                Text(model.timer.phase.label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.3)
                    .foregroundStyle(accent)

                Text(model.timer.formattedRemaining)
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)

                if let activeTask = model.activeFocusTask {
                    Text(activeTask.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(NotchTheme.sagePaper)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                } else {
                    Text(model.timer.state == .running ? "In flow" : (model.timer.state == .paused ? "Paused" : "Ready"))
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity)
        .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func phaseButton(_ phase: TimerPhase) -> some View {
        let selected = model.timer.phase == phase
        return Button(phase.label) {
            let mins = (phase == .focus) ? model.settings.focusMinutes : model.settings.shortBreakMinutes
            model.timer.configure(minutes: mins, phase: phase)
            model.syncAmbientAudio()
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(selected ? .black : .white.opacity(0.75))
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(selected ? NotchTheme.skyWave : Color.white.opacity(0.07), in: Capsule())
        .buttonStyle(.plain)
    }

    private func statPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10.5))
                .foregroundStyle(NotchTheme.peachAction)
            Text(value)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06), in: Capsule())
    }
}

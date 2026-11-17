import AppKit
import NotchNestCore
import SwiftUI

struct HubTabView: View {
    @Bindable var model: NotchNestModel
    let onRequestFocus: () -> Void
    var onCollapse: (() -> Void)? = nil

    @State private var copiedTranslation = false

    private let languages = [
        "English", "Spanish", "French", "German",
        "Japanese", "Chinese", "Korean", "Hindi", "Portuguese", "Italian"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            subSectionBar

            Group {
                switch model.selectedHubSection {
                case .overview:
                    overviewBentoGrid
                case .health:
                    healthWellbeingView
                case .screenTime:
                    screenTimeView
                case .devAI:
                    devAndAIView
                case .snap:
                    snapZonesView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            if model.weatherService.snapshot == nil {
                model.refreshWeather(force: true)
            }
            if model.selectedHubSection == .devAI {
                model.devHubService.refreshAll(settings: model.settings)
            }
            model.snapService.refreshTrustStatus()
        }
        .onChange(of: model.selectedHubSection) { _, newValue in
            if newValue == .devAI {
                model.devHubService.refreshAll(settings: model.settings)
            } else if newValue == .snap {
                model.snapService.refreshTrustStatus()
            }
        }
    }

    // MARK: - Sub-navigation Bar

    private var subSectionBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                ForEach(HubSection.allCases) { section in
                    let isSelected = model.selectedHubSection == section
                    Button {
                        model.selectedHubSection = section
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 10, weight: .semibold))
                            Text(section.title)
                                .font(.system(size: 10.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                        }
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isSelected ? NotchTheme.elevatedSurface : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.05), in: Capsule())

            Spacer()

            if model.settings.preventSleepEnabled {
                HStack(spacing: 4) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: 9.5))
                    Text("Awake")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(Color.amberGlow)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.amberGlow.opacity(0.14), in: Capsule())
            }

            if let battery = model.systemService.batteryPercent {
                HStack(spacing: 4) {
                    Image(systemName: model.systemService.isCharging ? "battery.100.bolt" : "battery.75")
                        .font(.system(size: 10))
                        .foregroundStyle(battery <= 20 ? NotchTheme.coralAlert : NotchTheme.mintComplete)
                    Text("\(battery)%")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.06), in: Capsule())
            }
        }
    }

    // MARK: - 1. Overview Bento Grid

    private var overviewBentoGrid: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    mediaBentoCard
                        .frame(maxWidth: .infinity)
                    weatherBentoCard
                        .frame(maxWidth: .infinity)
                }

                HStack(alignment: .top, spacing: 10) {
                    launcherAndTogglesCard
                        .frame(maxWidth: .infinity)
                    systemAndDayProgressCard
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)
        }
    }

    private var mediaBentoCard: some View {
        let track = model.mediaService.currentTrack
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if let artData = track?.artworkData, let nsImg = NSImage(data: artData) {
                    Image(nsImage: nsImg)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: track?.isPlaying == true
                                        ? [NotchTheme.peachAction.opacity(0.85), Color.purple.opacity(0.75)]
                                        : [NotchTheme.elevatedSurface, NotchTheme.cardSurface],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)
                        Image(systemName: track?.isPlaying == true ? "music.note" : "waveform")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(track?.title ?? "Nothing Playing")
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let app = track?.appName {
                            Text(app)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(NotchTheme.peachAction)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(NotchTheme.peachAction.opacity(0.16), in: Capsule())
                        }
                    }

                    Text(track.map { $0.artist.isEmpty ? "Ready" : $0.artist }
                        ?? (model.mediaService.automationError
                            ?? "Open \(model.settings.preferredMusicPlayer == .automatic ? "Spotify, Music, or YouTube Music" : model.settings.preferredMusicPlayer.label)."))
                        .font(.system(size: 10.5))
                        .foregroundStyle(model.mediaService.automationError != nil && track == nil ? NotchTheme.coralAlert : .white.opacity(0.58))
                        .lineLimit(track == nil && model.mediaService.automationError != nil ? 2 : 1)
                }

                Spacer(minLength: 4)

                AnimatedWaveformView(
                    isActive: track?.isPlaying == true || model.audioEngine.isPlaying,
                    barColor: NotchTheme.peachAction,
                    barWidth: 2.5,
                    maxHeight: 16,
                    spacing: 2
                )
            }

            HStack(spacing: 8) {
                Button {
                    model.mediaService.previousTrack()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 28, height: 24)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    model.mediaService.togglePlayPause()
                } label: {
                    Image(systemName: track?.isPlaying == true ? "pause.fill" : "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 24)
                        .background(NotchTheme.peachAction, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    model.mediaService.nextTrack()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 28, height: 24)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Menu {
                    ForEach(MusicPlayerPreference.allCases) { pref in
                        Button {
                            model.settings.preferredMusicPlayer = pref
                        } label: {
                            if model.settings.preferredMusicPlayer == pref {
                                Label(pref.label, systemImage: "checkmark")
                            } else {
                                Text(pref.label)
                            }
                        }
                    }
                    Divider()
                    Button("Open \(model.settings.preferredMusicPlayer == .automatic ? "YouTube Music" : model.settings.preferredMusicPlayer.label)") {
                        model.mediaService.openPreferredPlayer()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 9.5))
                        Text(model.settings.preferredMusicPlayer.shortLabel)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(NotchTheme.sagePaper)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                if track == nil {
                    Button {
                        model.mediaService.openPreferredPlayer()
                    } label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 24, height: 24)
                            .background(NotchTheme.sagePaper, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Open \(model.settings.preferredMusicPlayer == .automatic ? "YouTube Music" : model.settings.preferredMusicPlayer.label)")
                }

                Button {
                    model.toggleAmbientPreview()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.audioEngine.isPlaying ? "speaker.wave.2.fill" : "speaker.slash")
                            .font(.system(size: 9.5))
                        Text(model.settings.focusSoundscape.label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(model.audioEngine.isPlaying ? NotchTheme.skyWave : .white.opacity(0.68))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if model.mediaService.youTubeMusicNeedsJSHint {
                Text("Tip: In Chrome, enable View → Developer → Allow JavaScript from Apple Events for full artist, art & live play state.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(2)
            }
        }
        .padding(11)
        .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var weatherBentoCard: some View {
        let snap = model.weatherService.snapshot
        let gradColors: [Color] = (snap?.isDaylight ?? true)
            ? [Color(red: 0.14, green: 0.27, blue: 0.45), Color(red: 0.08, green: 0.14, blue: 0.24)]
            : [Color(red: 0.11, green: 0.13, blue: 0.27), Color(red: 0.06, green: 0.07, blue: 0.14)]

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: snap?.conditionSymbol ?? "cloud.sun.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.amberGlow)

                Text(snap?.locationName ?? (model.settings.weatherCity.isEmpty ? "Local Weather" : model.settings.weatherCity))
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer()

                Button {
                    model.settings.weatherUnit = (model.settings.weatherUnit == .fahrenheit) ? .celsius : .fahrenheit
                } label: {
                    Text(model.settings.weatherUnit.label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.14), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    model.refreshWeather(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            if let snap {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Int(round(snap.currentTemp)))°")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(snap.conditionDescription)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.88))
                        Text("H \(Int(round(snap.highTemp)))° · L \(Int(round(snap.lowTemp)))° · Wind \(Int(round(snap.windSpeed)))")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.66))
                    }
                    Spacer()
                }

                HStack(spacing: 6) {
                    ForEach(snap.hourly.prefix(5)) { point in
                        VStack(spacing: 2) {
                            Text(point.hourLabel)
                                .font(.system(size: 8.5))
                                .foregroundStyle(.white.opacity(0.65))
                            Image(systemName: WeatherSnapshot.symbol(code: point.weatherCode, isDay: snap.isDaylight))
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.88))
                            Text("\(Int(round(point.temperature)))°")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            } else if model.weatherService.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 58)
            } else {
                Text(model.weatherService.errorText ?? "Set your city in Settings -> Weather & Wellbeing or click refresh.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.68))
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            }
        }
        .padding(11)
        .background(
            LinearGradient(colors: gradColors, startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var launcherAndTogglesCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Launcher & Quick Toggles")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                Text("\(model.systemService.installedApps.count) apps")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.45))
            }

            if !model.systemService.installedApps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.systemService.installedApps.prefix(10)) { app in
                            Button {
                                NSWorkspace.shared.open(app.url)
                                onCollapse?()
                            } label: {
                                VStack(spacing: 3) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 26, height: 26)
                                    Text(app.name)
                                        .font(.system(size: 8.5, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .lineLimit(1)
                                }
                                .frame(width: 44)
                            }
                            .buttonStyle(.plain)
                            .help("Launch \(app.name)")
                        }
                    }
                }
            }

            Divider().overlay(Color.white.opacity(0.08))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                quickToggleTile(
                    title: "Never Sleep",
                    icon: "cup.and.saucer.fill",
                    isActive: model.settings.preventSleepEnabled,
                    accent: Color.amberGlow
                ) {
                    model.togglePreventSleep()
                }

                quickToggleTile(
                    title: "Screen Privacy",
                    icon: model.settings.hideInScreenCapture ? "eye.slash.fill" : "eye.fill",
                    isActive: model.settings.hideInScreenCapture,
                    accent: NotchTheme.lavenderSoft
                ) {
                    model.settings.hideInScreenCapture.toggle()
                }

                quickToggleTile(
                    title: "Dark Mode",
                    icon: "circle.lefthalf.filled",
                    isActive: false,
                    accent: NotchTheme.skyWave
                ) {
                    model.toggleDarkModeWithHUD()
                }

                quickToggleTile(
                    title: "Lock Screen",
                    icon: "lock.fill",
                    isActive: false,
                    accent: NotchTheme.coralAlert
                ) {
                    model.systemService.lockScreen()
                }
            }
        }
        .padding(11)
        .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func quickToggleTile(
        title: String,
        icon: String,
        isActive: Bool,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isActive ? .black : accent)
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(isActive ? .black : .white.opacity(0.88))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isActive ? accent : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private var systemAndDayProgressCard: some View {
        let dayFrac = model.dayProgressFraction()
        let pctLeft = max(0, min(100, Int(round((1.0 - dayFrac) * 100))))

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Day Progress & System HUD")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                Text("\(pctLeft)% day left")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NotchTheme.sagePaper)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.09))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [NotchTheme.sagePaper, NotchTheme.skyWave],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, geo.size.width * dayFrac))
                }
            }
            .frame(height: 7)

            Text("\"\(model.healthService.dailyQuote)\"")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
                .italic()
                .lineLimit(1)

            HStack(spacing: 6) {
                systemMetricPill(label: "CPU", value: "\(Int(round(model.systemService.cpuUsagePercent)))%")
                systemMetricPill(
                    label: "RAM",
                    value: String(format: "%.0f/%.0fG", model.systemService.memoryUsedGB, model.systemService.memoryTotalGB)
                )
                systemMetricPill(
                    label: "Disk",
                    value: String(format: "%.0fG free", model.systemService.diskFreeGB)
                )
            }

            if !model.systemService.bluetoothDevices.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.systemService.bluetoothDevices) { dev in
                            HStack(spacing: 4) {
                                Image(systemName: dev.systemImage)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(NotchTheme.skyWave)
                                Text(dev.name)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)
                                Text("\(dev.percent)%")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundStyle(dev.percent <= 20 ? NotchTheme.coralAlert : NotchTheme.mintComplete)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color.white.opacity(0.06), in: Capsule())
                        }
                    }
                }
            } else {
                Text("No Bluetooth accessory batteries reporting right now.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(11)
        .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func systemMetricPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 2. Health & Wellbeing

    private var healthWellbeingView: some View {
        let health = model.healthService
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily Wellbeing Rings")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Last break: \(health.lastBreakSummary()) · Streak: \(health.stats.streakDays)d")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()

                    Toggle(
                        "20-20-20 Eye Break",
                        isOn: Binding(
                            get: { model.settings.eyeBreakReminderEnabled },
                            set: { model.settings.eyeBreakReminderEnabled = $0 }
                        )
                    )
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 10.5))
                }

                HStack(spacing: 12) {
                    healthRingCard(
                        title: "Breaks",
                        value: "\(health.stats.breaksTaken)/\(health.stats.breaksGoal)",
                        progress: health.breaksProgress,
                        color: NotchTheme.peachAction
                    ) {
                        HStack(spacing: 4) {
                            smallPillButton(label: "+1 Break", tint: NotchTheme.peachAction) {
                                health.recordBreak()
                            }
                            if model.settings.eyeBreakReminderEnabled {
                                Text(health.eyeBreakCountdownText)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }

                    healthRingCard(
                        title: "Water",
                        value: "\(health.stats.waterGlasses)/\(health.stats.waterGoal)",
                        progress: health.waterProgress,
                        color: NotchTheme.skyWave
                    ) {
                        HStack(spacing: 6) {
                            smallPillButton(label: "−", tint: .white.opacity(0.2)) {
                                health.adjustWater(-1)
                            }
                            smallPillButton(label: "+1 Glass", tint: NotchTheme.skyWave) {
                                health.adjustWater(1)
                            }
                        }
                    }

                    healthRingCard(
                        title: "Mindful",
                        value: "\(health.stats.mindfulMinutes)/\(health.stats.mindfulGoal)m",
                        progress: health.mindfulProgress,
                        color: NotchTheme.mintComplete
                    ) {
                        smallPillButton(label: "+2m", tint: NotchTheme.mintComplete) {
                            health.addMindfulMinutes(2)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Box Breathing (4-4-4-4)")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Text("Cycles: \(health.breathingCyclesCompleted)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(NotchTheme.sagePaper.opacity(0.18))
                                .frame(width: 56, height: 56)
                            Circle()
                                .fill(NotchTheme.sagePaper.opacity(0.75))
                                .frame(width: 52, height: 52)
                                .scaleEffect(health.isBreathingActive ? health.breathingPhase.targetScale : 0.6)
                                .animation(.easeInOut(duration: 3.6), value: health.breathingPhase)
                            Text("\(health.breathingPhaseSecondsRemaining)s")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(.black)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(health.isBreathingActive ? health.breathingPhase.rawValue : "Paused")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Slow nasal inhale, gentle hold, even exhale.")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.58))

                            Button(health.isBreathingActive ? "Stop Breathing" : "Start Guided Breath") {
                                health.toggleBreathing()
                            }
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(NotchTheme.sagePaper, in: Capsule())
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                }
                .padding(11)
                .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    let stretch = health.currentStretch
                    HStack {
                        Label(stretch.title, systemImage: "figure.cooldown")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(NotchTheme.sagePaper)
                        Spacer()
                        Text("\(stretch.durationSeconds)s")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    Text(stretch.instruction)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.74))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button("Next Stretch") {
                            health.nextStretch()
                        }
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .buttonStyle(.plain)

                        Spacer()

                        Button("Log Break") {
                            health.recordBreak()
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(NotchTheme.peachAction, in: Capsule())
                        .buttonStyle(.plain)
                    }
                }
                .padding(11)
                .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .frame(width: 310)
        }
    }

    private func healthRingCard<Footer: View>(
        title: String,
        value: String,
        progress: Double,
        color: Color,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.20), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.35), value: progress)

                VStack(spacing: 1) {
                    Text(value)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(title)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: 72, height: 72)

            footer()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
    }

    private func smallPillButton(label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
            .buttonStyle(.plain)
    }

    // MARK: - 3. Screen Time

    private var screenTimeView: some View {
        let totalSecs = max(1, model.screenTimeService.stats.totalSeconds)
        let categories = model.screenTimeService.categoryTotals
        let ranked = model.screenTimeService.rankedApps

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's Active Time")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        Text(formatDuration(model.screenTimeService.stats.totalSeconds))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(model.screenTimeService.stats.appSwitches)")
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundStyle(NotchTheme.skyWave)
                        Text("app switches")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                Text("Categories")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                if categories.isEmpty {
                    Text("Tracking starts automatically as you work across macOS apps.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.5))
                } else {
                    ForEach(categories, id: \.category) { row in
                        let frac = Double(row.seconds) / Double(totalSecs)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(row.category)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                Spacer()
                                Text(formatDuration(row.seconds))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.08))
                                    Capsule()
                                        .fill(categoryColor(row.category))
                                        .frame(width: max(4, geo.size.width * frac))
                                }
                            }
                            .frame(height: 5)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 245)
            .frame(maxHeight: .infinity)
            .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Top Applications")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                if ranked.isEmpty {
                    VStack(spacing: 6) {
                        Spacer()
                        Image(systemName: "hourglass")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.35))
                        Text("No foreground usage samples collected yet today.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 6) {
                            ForEach(ranked.prefix(16)) { app in
                                HStack(spacing: 8) {
                                    appIcon(for: app.bundleID)
                                        .frame(width: 20, height: 20)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(app.name)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(app.category)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }

                                    Spacer()

                                    let pct = Int(round(Double(app.seconds) / Double(totalSecs) * 100))
                                    Text("\(app.formattedDuration) · \(pct)%")
                                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.82))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    @ViewBuilder
    private func appIcon(for bundleID: String) -> some View {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app.fill")
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Development": return NotchTheme.skyWave
        case "Browser": return NotchTheme.peachAction
        case "Communication": return NotchTheme.mintComplete
        case "Media & Design": return NotchTheme.lavenderSoft
        case "Productivity": return NotchTheme.sagePaper
        default: return .white.opacity(0.55)
        }
    }

    private func formatDuration(_ secs: Int) -> String {
        let mins = secs / 60
        let hrs = mins / 60
        let rem = mins % 60
        if hrs > 0 { return "\(hrs)h \(rem)m" }
        if mins > 0 { return "\(mins)m" }
        return "\(secs)s"
    }

    // MARK: - 4. Dev & AI + Quick Translator

    private var devAndAIView: some View {
        let dev = model.devHubService
        return HStack(alignment: .top, spacing: 12) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("Local AI Agents & IDEs")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Button("Scan") {
                            dev.refreshAll(settings: model.settings)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchTheme.sagePaper)
                        .buttonStyle(.plain)
                    }

                    if dev.aiSessions.isEmpty {
                        Text("No active AI CLI/IDE processes detected (`claude`, `codex`, Cursor, Zed, Ollama).")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.48))
                    } else {
                        ForEach(dev.aiSessions) { session in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(session.isBusy ? NotchTheme.peachAction : NotchTheme.mintComplete)
                                    .frame(width: 6, height: 6)
                                Text(session.name)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text(session.isBusy ? String(format: "Busy %.0f%%", session.cpuPercent) : session.kind)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.08))

                    HStack {
                        Text("GitHub PR Review Queue")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        if dev.isLoadingGitHub {
                            ProgressView().controlSize(.mini)
                        }
                    }

                    if let err = dev.githubError {
                        Text(err).font(.system(size: 10)).foregroundStyle(NotchTheme.coralAlert)
                    } else if dev.githubPRs.isEmpty {
                        Button("Configure GitHub repos / token in Settings →") {
                            model.activeTab = .settings
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .buttonStyle(.plain)
                    } else {
                        ForEach(dev.githubPRs.prefix(6)) { pr in
                            Button {
                                NSWorkspace.shared.open(pr.url)
                            } label: {
                                HStack(spacing: 6) {
                                    Text("#\(pr.number)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(NotchTheme.skyWave)
                                    Text(pr.title)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(pr.repo.split(separator: "/").last.map(String.init) ?? "")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.white.opacity(0.45))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.08))

                    HStack {
                        Text("Jira Sprint Issues")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        if dev.isLoadingJira {
                            ProgressView().controlSize(.mini)
                        }
                    }

                    if let err = dev.jiraError {
                        Text(err).font(.system(size: 10)).foregroundStyle(NotchTheme.coralAlert)
                    } else if dev.jiraIssues.isEmpty {
                        Button("Configure Jira URL / API token in Settings →") {
                            model.activeTab = .settings
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                        .buttonStyle(.plain)
                    } else {
                        ForEach(dev.jiraIssues.prefix(6)) { issue in
                            Button {
                                NSWorkspace.shared.open(issue.url)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(issue.key)
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(NotchTheme.peachAction)
                                    Text(issue.summary)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(issue.status)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.white.opacity(0.55))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Quick Translator", systemImage: "character.bubble")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(model.settings.translatorProvider.label)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }

                HStack {
                    Picker("To", selection: Binding(
                        get: { model.devHubService.translationTargetLanguage },
                        set: { model.devHubService.translationTargetLanguage = $0 }
                    )) {
                        ForEach(languages, id: \.self) { lang in
                            Text(lang).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 10.5))

                    Spacer()

                    Button {
                        Task { await model.devHubService.translate(settings: model.settings) }
                    } label: {
                        HStack(spacing: 4) {
                            if model.devHubService.isTranslating {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10))
                            }
                            Text("Translate")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(NotchTheme.sagePaper, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.devHubService.isTranslating)
                }

                TextEditor(
                    text: Binding(
                        get: { model.devHubService.translationInput },
                        set: { model.devHubService.translationInput = $0 }
                    )
                )
                .font(.system(size: 11.5))
                .foregroundStyle(.white)
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 82)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                .onTapGesture {
                    onRequestFocus()
                }

                if let err = model.devHubService.translationError {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundStyle(NotchTheme.coralAlert)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Result")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        if !model.devHubService.translationOutput.isEmpty {
                            Button(copiedTranslation ? "Copied" : "Copy") {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(model.devHubService.translationOutput, forType: .string)
                                copiedTranslation = true
                                Task {
                                    try? await Task.sleep(for: .seconds(1.4))
                                    copiedTranslation = false
                                }
                            }
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(NotchTheme.sagePaper)
                            .buttonStyle(.plain)
                        }
                    }

                    ScrollView(.vertical, showsIndicators: false) {
                        Text(model.devHubService.translationOutput.isEmpty
                            ? "Translated text appears here."
                            : model.devHubService.translationOutput)
                            .font(.system(size: 11.5))
                            .foregroundStyle(model.devHubService.translationOutput.isEmpty ? .white.opacity(0.35) : .white.opacity(0.92))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
                }
            }
            .padding(11)
            .frame(width: 280)
            .frame(maxHeight: .infinity)
            .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - 5. Window Snap Zones

    private var snapZonesView: some View {
        let snap = model.snapService
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Click a zone to snap \(snap.lastTargetAppName ?? "the active app window")")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(snap.lastStatusMessage ?? "Arrange windows into halves, thirds, quarters, or centered focus.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                Toggle("Snap on top-edge drag", isOn: $model.settings.snapOnTopEdgeDrag)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 10.5))

                if snap.isAccessibilityTrusted {
                    Text("Accessibility On")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(NotchTheme.mintComplete)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(NotchTheme.mintComplete.opacity(0.14), in: Capsule())
                } else {
                    Button("Grant Accessibility") {
                        snap.requestAccessibilityPrompt()
                        snap.openAccessibilitySettings()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(NotchTheme.peachAction, in: Capsule())
                    .buttonStyle(.plain)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                ForEach(SnapZone.allCases) { zone in
                    snapTile(zone: zone)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func snapTile(zone: SnapZone) -> some View {
        let previewRect = WindowSnapService.targetAppKitFrame(
            for: zone,
            visibleFrame: CGRect(x: 0, y: 0, width: 1, height: 1)
        )
        return Button {
            _ = model.snapWindow(to: zone)
        } label: {
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
                            )

                        RoundedRectangle(cornerRadius: 3.5)
                            .fill(NotchTheme.skyWave.opacity(0.75))
                            .frame(
                                width: max(8, previewRect.width * (geo.size.width - 6)),
                                height: max(8, previewRect.height * (geo.size.height - 6))
                            )
                            .offset(
                                x: 3 + previewRect.minX * (geo.size.width - 6),
                                y: -(3 + previewRect.minY * (geo.size.height - 6))
                            )
                    }
                }
                .frame(height: 36)

                Text(zone.title)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            .padding(7)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

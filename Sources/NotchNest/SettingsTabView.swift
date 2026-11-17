import AppKit
import CoreLocation
import NotchNestCore
import SwiftUI

struct SettingsTabView: View {
    @Bindable var model: NotchNestModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    behaviorCard
                    integrationsCard
                }

                devAICard

                HStack {
                    Text("NotchNest · ⌘1–⌘6 tabs · ⌥S snooze · Esc close")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.45))
                    Spacer()
                    Button("Open Data Folder") {
                        NSWorkspace.shared.open(model.persistence.baseDirectory)
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NotchTheme.sagePaper)
                    .buttonStyle(.plain)

                    Text("·")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.white.opacity(0.3))

                    Button("Quit NotchNest") {
                        NSApp.terminate(nil)
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(NotchTheme.coralAlert)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notch & Workspace")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))

            Toggle("Hover top center to expand", isOn: $model.settings.hoverToExpand)
            Toggle("Show Live Activity nudges", isOn: $model.settings.showLiveActivityNudge)
            Toggle("Show Media / Bluetooth / HUD popups", isOn: $model.settings.showTransientLiveActivities)
            Toggle("Show Now Playing in notch", isOn: $model.settings.showMediaInNotch)
            Toggle("Show focus timer beside notch", isOn: $model.settings.showTimerInNotch)
            Toggle("Show next meeting in notch", isOn: $model.settings.showNextEventInNotch)
            Toggle("Hide notch in screen recordings", isOn: $model.settings.hideInScreenCapture)
            Toggle("Prevent Mac from sleeping", isOn: $model.settings.preventSleepEnabled)
            Toggle("Snap window on top-edge drag", isOn: $model.settings.snapOnTopEdgeDrag)
            Toggle("Animate owl mascot", isOn: $model.settings.owlAnimationEnabled)
            Toggle("Enable global shortcut", isOn: $model.settings.globalShortcutEnabled)
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                )
            )

            Picker("Hotkey", selection: $model.settings.shortcutStyle) {
                ForEach(GlobalShortcutStyle.allCases, id: \.self) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .font(.system(size: 10.5))

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Collapsed pill width")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                    Spacer()
                    Text("\(Int(model.settings.collapsedWidth)) pt")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Slider(value: $model.settings.collapsedWidth, in: 176...290, step: 4)
                    .tint(NotchTheme.sagePaper)
            }

            Picker("Display", selection: $model.settings.displayMode) {
                ForEach(DisplaySelectionMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 11))

            Picker("Music player", selection: $model.settings.preferredMusicPlayer) {
                ForEach(MusicPlayerPreference.allCases) { player in
                    Text(player.label).tag(player)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 11))

            Picker("Language", selection: $model.settings.appLanguage) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Text(lang.label).tag(lang)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 11))
        }
        .font(.system(size: 11.5))
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var integrationsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus, Sync & Permissions")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))

            Toggle("Watch Desktop screenshots (Clips)", isOn: $model.settings.watchScreenshots)
            Toggle("Two-way Apple Reminders sync", isOn: Binding(
                get: { model.settings.syncReminders },
                set: { newValue in
                    model.settings.syncReminders = newValue
                    if newValue {
                        Task { await model.syncWithReminders() }
                    }
                }
            ))
            Toggle("Timer completion chime", isOn: $model.settings.soundEnabled)
            Toggle("Pause music when joining calls", isOn: $model.settings.autoPauseMediaOnJoin)
            Toggle("Create meeting note on Join", isOn: $model.settings.createMeetingNoteOnJoin)
            Toggle("20-20-20 eye break reminder", isOn: $model.settings.eyeBreakReminderEnabled)

            HStack(spacing: 6) {
                TextField("Weather city (default: San Francisco)", text: $model.settings.weatherCity)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 10.5))

                Picker("", selection: $model.settings.weatherUnit) {
                    ForEach(WeatherUnit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
                .labelsHidden()
                .frame(width: 58)
            }

            Stepper(
                "Bedtime target: \(model.settings.bedtimeHour):00",
                value: $model.settings.bedtimeHour,
                in: 18...24
            )

            Picker("Focus sound", selection: $model.settings.focusSoundscape) {
                ForEach(FocusSoundscape.allCases) { sound in
                    Text(sound.label).tag(sound)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 11))

            Stepper(
                "Focus: \(model.settings.focusMinutes)m",
                value: $model.settings.focusMinutes,
                in: 5...90,
                step: 5
            )
            Stepper(
                "Break: \(model.settings.shortBreakMinutes)m",
                value: $model.settings.shortBreakMinutes,
                in: 1...30,
                step: 1
            )

            Divider().overlay(Color.white.opacity(0.08))

            VStack(alignment: .leading, spacing: 5) {
                permissionRow(
                    title: "Calendar",
                    granted: model.eventKit.calendarAuth == .authorized
                ) {
                    Task { _ = await model.eventKit.requestCalendarAccess() }
                }
                permissionRow(
                    title: "Reminders",
                    granted: model.eventKit.reminderAuth == .authorized
                ) {
                    Task { await model.syncWithReminders() }
                }
                permissionRow(
                    title: "Voice & Mic",
                    granted: model.voiceCapture.authState == .authorized
                ) {
                    Task { _ = await model.voiceCapture.requestPermissions() }
                }
                permissionRow(
                    title: "Camera Mirror",
                    granted: model.cameraMirror.authState == .authorized
                ) {
                    Task { await model.cameraMirror.requestAndStart() }
                }
                permissionRow(
                    title: "Maps Travel Time",
                    granted: CLLocationManager().authorizationStatus == .authorized
                        || CLLocationManager().authorizationStatus == .authorizedAlways
                ) {
                    model.refreshTravelTimes()
                }
                permissionRow(
                    title: "Accessibility (Snap Zones)",
                    granted: model.snapService.isAccessibilityTrusted
                ) {
                    model.snapService.requestAccessibilityPrompt()
                    model.snapService.openAccessibilitySettings()
                }
            }
        }
        .font(.system(size: 11.5))
        .toggleStyle(.switch)
        .controlSize(.mini)
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func permissionRow(title: String, granted: Bool, onEnable: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            if granted {
                Text("Allowed")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(NotchTheme.mintComplete)
            } else {
                Button("Grant") {
                    onEnable()
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(NotchTheme.peachAction, in: Capsule())
                .buttonStyle(.plain)
            }
        }
    }

    private var devAICard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Dev & AI Integrations (GitHub, Jira & Translator)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
                Spacer()
                Button("Refresh Dev Hub") {
                    model.devHubService.refreshAll(settings: model.settings)
                }
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(NotchTheme.sagePaper, in: Capsule())
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    TextField("GitHub repos (owner/repo, owner2/repo2)", text: $model.settings.githubRepos)
                        .textFieldStyle(.roundedBorder)
                    SecureField("GitHub Personal Access Token (optional)", text: $model.settings.githubToken)
                        .textFieldStyle(.roundedBorder)
                    TextField("Jira Base URL (https://org.atlassian.net)", text: $model.settings.jiraBaseURL)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 6) {
                        TextField("Jira Email", text: $model.settings.jiraEmail)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Jira API Token", text: $model.settings.jiraToken)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Picker("Translator", selection: $model.settings.translatorProvider) {
                        ForEach(TranslatorProvider.allCases, id: \.self) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Ollama Endpoint (http://localhost:11434)", text: $model.settings.translatorEndpoint)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model (e.g. llama3.2 or gpt-4o-mini)", text: $model.settings.translatorModel)
                        .textFieldStyle(.roundedBorder)
                    SecureField("OpenAI API Key (when using OpenAI)", text: $model.settings.openAIKey)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .font(.system(size: 10.5))
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(NotchTheme.cardSurface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

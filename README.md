# NotchNest

An original, clean-room **Universal (`arm64` Apple Silicon + `x86_64` Intel) native** macOS utility built with Swift 6, SwiftUI, and AppKit that turns the top center of any display into an interactive productivity and system hub.

## Features
- **Virtual & Hardware Notch Adaptive**: Centers a dark curved notch pill in the menu bar on non-notched Intel Macs and external displays, and adapts cleanly on hardware-notched MacBooks.
- **Configurable Collapsed & Expanded Notch UI**:
  - **Collapsed Display Modes**: Choose what sits in the collapsed notch (`Auto (Smart)`, `Music Player`, `Task Countdown`, `Next Meeting`, `Mac Vitals`, or `Minimal`) via Settings or the Owl menu.
  - **Due Dates, Pre-Due Auto-Countdowns & Pauseable Controls**: Attach due dates & reminder lead times (`At due`, `5m`, `10m`, `15m`, `30m before`, or `remind 15m before` in NL input) so tasks auto-start a pauseable countdown on window entry, shown in both the collapsed pill (with hover `⏸`/`▶`) and expanded drawer.
  - **Stacked Micro-Timers**: Run parallel quick countdowns (`timer tea 4m`, `t: tea 4m`, `tea 4m timer`, or `+ Timer` presets) alongside any primary Focus timer, with persistent pause/resume/dismiss controls across the collapsed pill, telemetry bar, and Focus tab.
  - **Momentum-Damped Scroll-Wheel Notch Gestures**: Scroll vertically over the collapsed notch pill to step system volume (`±5%`) or swipe horizontally with hysteresis to skip tracks (when Music is active) or cycle collapsed display modes, filtering inertial trackpad coasting.
  - **Clever Expanded Telemetry (`Bottom Rail` default, `Slim HUD Strip`, or `Header Pill`)**: Surfaces color-coded `CPU`, `RAM`, `Battery`, and `Disk` chips whenever the notch is expanded (one-click jump to **Hub**).
- **Persistent & Transient Live Activities**:
  - **Calendar & Tasks**: Upcoming non-all-day meetings with automatic Zoom / Google Meet / Teams / Webex join buttons + optional call handoff (pause media / pre-call camera preview / meeting note), leave-by travel-time hints, pinned tasks, and 20-20-20 eye-break reminders (`⌥S` snooze).
  - **Focus Guard & System Popups**: Gentle distraction nudges during active Focus sessions when dwelling in off-task apps past your configured delay (with allowlist, optional browser guard, and 1-click `Snooze 20m`), collapsed notch Now Playing hover controls (**Play/Pause** & **Next**), Bluetooth batteries, Mic Mute Guard (`⌥M` + notch muted badge), Never Sleep & Screen Privacy toggles, Window Snap feedback, Focus completion, and Screen Unlock summaries.
- **Workspace (4-Column Matte Bento)**:
  - **Today's Tasks (Sage Green)**: Daily/date-navigable task list with `Sort` (`Default`, `Priority`, `Due Time`, `Duration`), per-task target countdown durations (`45m`), natural-language task parsing (`Prep slides 45m tomorrow 5pm #Work`), universal quick commands (`note:`, `25m focus`, `tr es:`, `snap left`), voice dictation, and optional Apple Reminders sync.
  - **Focus Countdown (Pastel Lavender)**: Dedicated Workspace countdown card with task dropdown selector, crisp dot-matrix digital clock (`45:00`), `Start`/`Pause`, task completion `✓`, `Set time` presets, and Focus soundscape control.
  - **Notepad (Warm Yellow)**: Rich-text inline scratchpad right inside Workspace (`Bold` `⌘B`, `Italic` `⌘I`, `Underline` `⌘U`, strikethrough, headings, `- `/`• ` bullets, numbered lists, `RTF` persistence), word counter, note switcher, voice dictation, line-to-task extraction, and automatic special-prefix Todo creation (`! `, `!! `, `[] `, `[ ] `, `todo: `, `/todo `, `@todo ` + Enter).
  - **Calendar (Misty Steel-Blue)**: 7-day selector, relative meeting countdowns (`In 1 hr 18 min`), one-click Zoom/Meet/Teams/Webex launch, camera check, and meeting note prep.
- **Week Planner**: Horizontally scrollable 9-column Kanban (`Inbox`, 7 upcoming days, `Later`) with day-specific scheduling and inline task editing.
- **Hub (`⌘3`)**:
  - **Dashboard Bento**: Media controller supporting **YouTube Music** (Chrome / Chrome PWA / Safari), **Spotify**, **Apple Music**, or **Auto** with interactive track scrubber and CoreAudio output selector/volume control; live **Open-Meteo** weather (`°F`/`°C`, hourly outlook); installed app launcher; **Quick Toggles** (`Never Sleep`, `Screen Privacy`, `Dark Mode`, `Lock Screen`, `Mic Mute · ⌥M`); system HUD; and bedtime day-progress bar.
  - **Health & Wellbeing**: Daily rings (`Breaks`, `Water −/+`, `Mindful mins`), guided 4-4-4-4 box breathing timer, desk stretch library, and 20-20-20 eye-break countdown.
  - **Screen Time**: Foreground app time tracker, category breakdown, ranked apps list, and app-switch counters.
  - **Dev & AI**: Local IDE/CLI agent process monitor, GitHub PR review queue, Jira sprint issues, and quick text translator via local **Ollama** or **OpenAI**.
  - **Window Snap Zones**: Accessibility (`AXUIElement`) window snapping (`Halves`, `Thirds`, `Quarters`, `Maximize`, `Center 70%`) plus optional drag-to-top-edge snapping.
- **Focus & Ambient Soundscapes**: Drift-free Pomodoro timer with synthesized procedural soundscapes (`Rain`, `Brown Noise`, `Ocean`, `Cafe`) via `AVAudioEngine`.
- **Clips, Clipboard History & QR Tray**: Watches your macOS screenshot folder, supports direct file drop actions (`Shelf`, `Copy Text (OCR)` via Apple `Vision`, `Compress`, `AirDrop`, `Zip`, `To PNG`, `To JPG`, `Finder`, `Trash`, `Eject`), and keeps a searchable text/URL clipboard ring (filtering password managers & concealed types) with Pin, Open URL, Translate, and offline QR code sharing.
- **Notes, Mirror & Insights**: Rich-text multi-note scratchpad (`B`/`I`/`U`/`S`/`H`/`</>`, smart bullet & numbered lists, and `! ` / `[] ` auto-todo extraction) with one-click task extraction, on-demand pre-call `AVFoundation` camera mirror, and 7-day completion/focus analytics.
- **Shortcuts & Privacy**: `⌥Space` / `⌥N` global toggle, `⌥M` mic mute inside NotchNest, `⌘1`–`⌘6` tabs, `⌘,` Settings, `⌥S` snooze, `Esc` close, `⌘Q` quit, plus `NSWindow.SharingType.none` capture hiding.

## Build & Run

```bash
# Run unit tests natively (Apple Silicon or Intel)
swift test --disable-sandbox

# Build release .app bundle for the current Mac's native architecture (arm64 or x86_64)
./scripts/build_app.sh release

# Or build a Universal (arm64 + x86_64) .app bundle for both M-series and Intel Macs
./scripts/build_app.sh release universal

# Verify code signature & launch
codesign --verify --deep --strict build/NotchNest.app
open build/NotchNest.app
```

When copying an ad-hoc signed `NotchNest.app` to another Mac via AirDrop or Finder, strip Gatekeeper quarantine once before launching:

```bash
xattr -cr /Applications/NotchNest.app
open /Applications/NotchNest.app
```

## License
Released under the [MIT License](LICENSE).

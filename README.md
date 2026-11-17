# NotchNest

An original, clean-room **Intel (`x86_64`) native** macOS utility built with Swift 6, SwiftUI, and AppKit that turns the top center of any display into an interactive productivity and system hub.

## Features
- **Virtual & Hardware Notch Adaptive**: Centers a dark curved notch pill in the menu bar on non-notched Intel Macs and external displays, and adapts cleanly on hardware-notched MacBooks.
- **Persistent & Transient Live Activities**:
  - **Calendar & Tasks**: Upcoming non-all-day meetings with automatic Zoom / Google Meet / Teams / Webex join buttons + optional call handoff (pause media / pre-call camera preview / meeting note), leave-by travel-time hints, pinned tasks, and 20-20-20 eye-break reminders (`⌥S` snooze).
  - **Media, Bluetooth, System HUD, Pomodoro & Unlock**: Collapsed notch Now Playing strip with hover-safe inline **Play/Pause** & **Next** controls, plus transient popups for track changes, Bluetooth gear batteries, Mic Mute Guard (`⌥M` + notch muted badge), Never Sleep & Screen Privacy toggles, Window Snap feedback, Focus completion, and Screen Unlock summaries.
- **Workspace (Today)**: Sage-green daily task board with inline editing, natural-language task parsing (`tomorrow 5pm #Work`), universal quick-command prefixes (`note:`, `25m focus`, `tr es:`, `snap left`), automatic typing focus on Workspace, optional voice dictation, optional two-way Apple Reminders sync, and a 7-day misty steel-blue Calendar timeline.
- **Week Planner**: Horizontally scrollable 9-column Kanban (`Inbox`, 7 upcoming days, `Later`) with day-specific scheduling and inline task editing.
- **Hub (`⌘3`)**:
  - **Dashboard Bento**: Media controller supporting **YouTube Music** (Chrome / Chrome PWA / Safari), **Spotify**, **Apple Music**, or **Auto** with interactive track scrubber and CoreAudio output selector/volume control; live **Open-Meteo** weather (`°F`/`°C`, hourly outlook); installed app launcher; **Quick Toggles** (`Never Sleep`, `Screen Privacy`, `Dark Mode`, `Lock Screen`, `Mic Mute · ⌥M`); system HUD; and bedtime day-progress bar.
  - **Health & Wellbeing**: Daily rings (`Breaks`, `Water −/+`, `Mindful mins`), guided 4-4-4-4 box breathing timer, desk stretch library, and 20-20-20 eye-break countdown.
  - **Screen Time**: Foreground app time tracker, category breakdown, ranked apps list, and app-switch counters.
  - **Dev & AI**: Local IDE/CLI agent process monitor, GitHub PR review queue, Jira sprint issues, and quick text translator via local **Ollama** or **OpenAI**.
  - **Window Snap Zones**: Accessibility (`AXUIElement`) window snapping (`Halves`, `Thirds`, `Quarters`, `Maximize`, `Center 70%`) plus optional drag-to-top-edge snapping.
- **Focus & Ambient Soundscapes**: Drift-free Pomodoro timer with synthesized procedural soundscapes (`Rain`, `Brown Noise`, `Ocean`, `Cafe`) via `AVAudioEngine`.
- **Clips, Clipboard History & QR Tray**: Watches your macOS screenshot folder, supports direct file drop actions (`Shelf`, `Copy Text (OCR)` via Apple `Vision`, `Compress`, `AirDrop`, `Zip`, `To PNG`, `To JPG`, `Finder`, `Trash`, `Eject`), and keeps a searchable text/URL clipboard ring (filtering password managers & concealed types) with Pin, Open URL, Translate, and offline QR code sharing.
- **Notes, Mirror & Insights**: Persistent multi-note scratchpad with one-click task extraction, on-demand pre-call `AVFoundation` camera mirror, and 7-day completion/focus analytics.
- **Shortcuts & Privacy**: `⌥Space` / `⌥N` global toggle, `⌥M` mic mute inside NotchNest, `⌘1`–`⌘6` tabs, `⌘,` Settings, `⌥S` snooze, `Esc` close, `⌘Q` quit, plus `NSWindow.SharingType.none` capture hiding.

## Build & Run

```bash
# Run unit tests (x86_64)
swift test --disable-sandbox --arch x86_64

# Build release x86_64 .app bundle at build/NotchNest.app
./scripts/build_app.sh release

# Verify code signature & launch
codesign --verify --deep --strict build/NotchNest.app
open build/NotchNest.app
```

## License
Released under the [MIT License](LICENSE).

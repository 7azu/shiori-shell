import "./services"
import "./bar"
import "./dropdowns"
import "./pickers"
import "./settings"
import "./windows"
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

ShellRoot {
    Component.onCompleted: {
        AppLauncherState.loadApps();
        MusicPickerState.loadSongs();
        WallpaperPickerState.loadWallpapers();
        ClipboardState.refresh();
        // Create the visualizer service early, so cava has settled when the audio dropdown opens
        CavaService.warmUp();
        // Terminals fade in sync on a wallpaper change (scripts/term_colors.py)
        TerminalColorFade.warmUp();
        // Window borders + shadows too (hyprctl eval, mapping as in hypr/modules/looks.lua)
        HyprlandColorFade.warmUp();
        // Cursor too (~/.config/wal/cursor/cursor-fade.py, intermediate themes for Hyprland)
        CursorColorFade.warmUp();
        // Register the Bluetooth pairing agent right away (otherwise incoming pairings fail)
        BluetoothState.warmUp();
    }

    GlobalShortcut {
        name: "toggle_clipboard"
        onPressed: ClipboardState.toggle()
    }

    GlobalShortcut {
        name: "toggle_trash"
        onPressed: TrashState.toggle()
    }

    GlobalShortcut {
        name: "toggle_calculator"
        description: "Toggle Calculator"
        onPressed: CalculatorState.toggle()
    }

    IpcHandler {
        target: "calculator"
        function toggle(): void { CalculatorState.toggle(); }
        function open(): void { CalculatorState.isOpen = true; }
        function close(): void { CalculatorState.close(); }
    }

    CalculatorWindow {}

    // Settings window (settings/SettingsWindow.qml): Super + , the gear in the bar, the gear in a dropdown
    GlobalShortcut {
        name: "toggle_settings"
        description: "Toggle Settings"
        onPressed: SettingsState.toggle()
    }

    IpcHandler {
        target: "settings"
        function toggle(): void { SettingsState.toggle(); }
        // page: system, appearance, desktop, bar, folders, sync, languages, icons, addons ("" = last one)
        function open(page: string): void { SettingsState.openAt(page); }
        function close(): void { SettingsState.close(); }
        function isOpen(): bool { return SettingsState.open; }
    }

    SettingsWindow {}

    // "Identify" on the Displays page: the name of each monitor big on it for a moment
    DisplayIdentify {}

    // Volume keys / volume knob of the keyboard: show the popup, max. 100 %
    GlobalShortcut {
        name: "volume_up"
        onPressed: VolumeSliderState.stepSystemVolume(0.05)
    }

    GlobalShortcut {
        name: "volume_down"
        onPressed: VolumeSliderState.stepSystemVolume(-0.05)
    }

    // Airplane mode: switch Wi-Fi and Bluetooth together through the existing modules.
    GlobalShortcut {
        name: "toggle_airplane_mode"
        onPressed: {
            if (airplaneCooldown.running || WifiState.radioSwitching)
                return;
            const enable = !(WifiState.radioOn || BluetoothState.enabled);
            WifiState.setRadio(enable);
            BluetoothState.setEnabled(enable);
            airplaneCooldown.start();
        }
    }

    Timer {
        id: airplaneCooldown
        interval: 1000
    }

    // Night light and keep awake (bar icon "screen"): no keys by default, bind them on the Shortcuts page
    GlobalShortcut {
        name: "toggle_night_light"
        onPressed: NightLight.toggle()
    }

    GlobalShortcut {
        name: "toggle_keep_awake"
        onPressed: KeepAwake.toggle()
    }

    IpcHandler {
        target: "screen"
        // mode: off, auto, on
        function nightLight(mode: string): void { NightLight.setMode(mode); }
        function nightLightMode(): string { return NightLight.mode; }
        // minutes: 0 = off, -1 = until turned off
        function keepAwake(minutes: int): void { KeepAwake.set(minutes); }
        function isAwake(): bool { return KeepAwake.active; }
    }

    // Brightness keys use the same service as the slider in the battery dropdown.
    GlobalShortcut {
        name: "brightness_down"
        onPressed: BrightnessState.step(-0.10)
    }

    GlobalShortcut {
        name: "brightness_up"
        onPressed: BrightnessState.step(0.10)
    }

    // VPN picker open/close (Hyprland: hl.dsp.global("quickshell:toggle_vpn"))
    GlobalShortcut {
        name: "toggle_vpn"
        description: "Toggle VPN Picker"
        onPressed: VpnPickerState.toggle()
    }

    GlobalShortcut {
        name: "toggle_language"
        onPressed: LanguageAudioState.toggle()
    }

    GlobalShortcut {
        name: "toggle_launcher"
        onPressed: AppLauncherState.toggle()
    }

    GlobalShortcut {
        name: "toggle_wallpaper"
        onPressed: WallpaperPickerState.toggle()
    }

    GlobalShortcut {
        name: "toggle_music_picker"
        description: "Toggle Music Picker"
        onPressed: MusicPickerState.toggle()
    }

    // Task manager (AppPicker) open/close (Hyprland: hl.dsp.global("quickshell:toggle_task_manager"))
    GlobalShortcut {
        name: "toggle_task_manager"
        description: "Toggle Task Manager"
        onPressed: PickerManager.toggle("apps")
    }

    // Bluetooth picker open/close (Hyprland: hl.dsp.global("quickshell:toggle_bluetooth"))
    GlobalShortcut {
        name: "toggle_bluetooth"
        description: "Toggle Bluetooth"
        onPressed: BluetoothState.toggle()
    }

    // Wi-Fi picker open/close (Hyprland: hl.dsp.global("quickshell:toggle_wifi"))
    GlobalShortcut {
        name: "toggle_wifi"
        description: "Toggle Wi-Fi"
        onPressed: WifiState.toggle()
    }

    GlobalShortcut {
        name: "toggle_media"
        description: "Toggle Media Picker"
        onPressed: PickerManager.toggle("media")
    }

    // Calendar open/close (Hyprland: hl.dsp.global("quickshell:toggle_calendar"))
    GlobalShortcut {
        name: "toggle_calendar"
        description: "Toggle Calendar"
        onPressed: BarState.calendarToggleRequested()
    }

    // Notification center open/close (Hyprland: hl.dsp.global("quickshell:toggle_notifications"))
    GlobalShortcut {
        name: "toggle_notifications"
        description: "Toggle Notification Center"
        onPressed: NotificationState.toggle()
    }

    // Screenshot with the editor (Hyprland: hl.dsp.global("quickshell:screenshot_edit"))
    GlobalShortcut {
        name: "screenshot_edit"
        description: "Take and edit a screenshot"
        onPressed: ScreenshotEditorState.startCapture()
    }

    // Images from yazi: scripts/open_image.sh calls "qs ipc call imageEditor open <path>". If the editor is already
    // open (maybe on another workspace), it moves here and shows the image
    IpcHandler {
        function open(path: string): void {
            if (ScreenshotEditorState.isOpen && ScreenshotEditorState.folderMode)
                imageEditor.adopt(path);
            else
                ScreenshotEditorState.openFolderFile(path);
        }

        // For tests: close without asking, query the state
        function close(): void {
            ScreenshotEditorState.close();
        }

        function isOpen(): bool {
            return ScreenshotEditorState.isOpen;
        }

        target: "imageEditor"
    }

    // Videos from yazi: scripts/open_video.sh calls "qs ipc call videoEditor open <path>" (open: move it here)
    IpcHandler {
        function open(path: string): void {
            if (VideoEditorState.isOpen)
                videoEditor.adopt(path);
            else
                VideoEditorState.open(path);
        }

        // For tests: close without asking (also stops the player), query the state
        function close(): void {
            VideoEditorState.close();
        }

        function isOpen(): bool {
            return VideoEditorState.isOpen;
        }

        target: "videoEditor"
    }

    // Show/hide the bar from outside (like a click on the top screen edge):
    //   qs ipc call bar toggle | qs ipc call bar set true|false | qs ipc call bar isVisible
    IpcHandler {
        function toggle(): void {
            BarState.barVisible = !BarState.barVisible;
        }

        function set(visible: bool): void {
            BarState.barVisible = visible;
        }

        function isVisible(): bool {
            return BarState.barVisible;
        }

        target: "bar"
    }

    // Move the bar to the next monitor (Hyprland: hl.dsp.global("quickshell:move_bar"))
    GlobalShortcut {
        name: "move_bar"
        description: "Move bar to next monitor"
        onPressed: MachineConfig.moveBar(Quickshell.screens, 1)
    }

    AnimatedWallpaper {
    }

    // Music visualizer at the bottom edge of workspace 1 (terminal stage, hypr/modules/home.lua)
    DesktopVisualizer {
    }

    // Power menu -> lock screen: transition on the monitors without the menu
    LockTransition {
    }

    // Ink transition on a wallpaper change (above the wallpapers, below the windows)
    InkBloom {
    }

    // Smooth change of the wallpaper animation when the bar moves to another monitor
    AnimMoveFade {
    }

    // Color change of Vesktop and OBS on a wallpaper change: still-image crossfade (SnapshotColorFade)
    AppColorFade {
    }

    PickerWindow {
    }

    WorkspaceOverview {
    }

    // Once, not per monitor
    PowerMenu {
    }

    ScreenshotEditor {
        id: imageEditor
    }

    VideoEditor {
        id: videoEditor
    }

    // Japanese tool: video player (subtitles only exist there)
    LanguageVideoPlayer {
    }

    // Always exactly ONE bar: the monitor comes from MachineConfig
    // (saved choice, otherwise the leftmost monitor).
    Variants {
        model: MachineConfig.barTargets(Quickshell.screens)
        delegate: Item {
            required property var modelData

            MainBar {
                screen: modelData
            }

            // Small toasts at the top right (the center itself is a morph of the bar)
            NotificationToasts {
                screen: modelData
            }

            TriggerZone {
                screen: modelData
            }

            VolumeTriggerZone {
                screen: modelData
            }

            // Replaces VpnDropDown, AudioDropdown and StatsDropdown
            DropdownHost {
                screen: modelData
            }

            VolumeSliderPopup {
                screen: modelData
            }

        }

    }

}

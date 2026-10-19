# OutputRanker — specification

**Tagline:** Rank your audio inputs and outputs so the Mac always picks your best connected device, with a volume HUD.

**Category:** Audio

**Inspired by (paid):** BetterAudio ($10 one-time)

**Frameworks:** SwiftUI, AppKit, CoreAudio, Carbon, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: BetterAudio is a menu bar audio tool that offers quick switching of input and output devices, a priority system for ordering devices, a global volume slider, media key control and a customizable on-screen HUD. Its full version is a one-time 10 dollar purchase with a free tier, and it competes with the pricier SoundSource and free tools like Fader and FineTune, which shows people keep looking for a better audio switcher than the built-in Sound settings. Our clean-room OutputRanker covers just the device priority and quick switching part, without per-app volume or audio taps.

Feature set: two ranked lists (outputs and inputs) that the user reorders by dragging, automatic switching so the highest ranked connected device becomes the system default whenever devices appear or disappear, a manual override that holds until the next device change, remembered volume per device restored on switch, a menu with one-click manual switching, an optional ignore flag for devices like virtual drivers, an on-screen HUD showing the device name and volume after switching, and global hotkeys to cycle outputs and inputs. About 400 to 600 lines.

UI spec: a MenuBarExtra menu showing the current output and input with checkmarks, a list of connected devices to click, a toggle for Auto Switch, and Settings and Quit. A Settings window with two tabs: Outputs and Inputs, each a reorderable list with a connected dot, a hide checkbox, and a remembered volume label. A third tab holds hotkeys, HUD options (show HUD, duration, position) and launch at login. The HUD is a borderless rounded panel that fades after about 1.5 seconds. Empty state: a device that has never been seen is added automatically to the bottom of the list when first detected. The list keeps disconnected devices in place greyed out so rank is preserved.

Technical approach: CoreAudio device enumeration using kAudioHardwarePropertyDevices, stable identification via kAudioDevicePropertyDeviceUID, transport type to flag built-in, Bluetooth, USB and virtual devices, and stream configuration to classify input versus output. Add a property listener on the device list and on the default device properties. When the list changes, compute the highest ranked connected, non-ignored device and set it with AudioObjectSetPropertyData on kAudioHardwarePropertyDefaultOutputDevice, and the default input and system output properties as well. Debounce events by about 300 milliseconds since devices often appear in bursts. Store the user-chosen override flag and clear it on the next device list change. Save and restore the volume per UID with the virtual main volume property. Hotkeys use Carbon RegisterEventHotKey. Persist ranks as arrays of UID strings in UserDefaults. Launch at login via SMAppService. No privacy permission is needed.

Edge cases: avoid infinite loops where our own default change triggers a listener, so ignore events for a short window after a programmatic change. Bluetooth headsets that expose both a hands-free and a high quality profile may appear as two devices, so let the user rank them separately and mention this in the UI. Aggregate or multi-output devices are treated like any other device. If a ranked device fails to become default, try the next one. Removing the current device while the override is on should fall back to ranking. Inputs and outputs have separate overrides. If the user disables Auto Switch, the app only offers manual switching and never changes anything by itself.

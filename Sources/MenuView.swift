import SwiftUI

/// The menu bar dropdown: current devices with checkmarks, one-click switching, Auto Switch, Settings and Quit.
struct MenuView: View {
    @EnvironmentObject private var ranker: DeviceRanker
    @AppStorage("autoSwitch") private var autoSwitch = true
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ForEach(AudioScope.allCases) { scope in
            Section(scope == .output ? "Output" : "Input") {
                ForEach(ranker.connectedDevices(scope)) { dev in
                    Button {
                        ranker.select(dev, scope)
                    } label: {
                        if dev.uid == ranker.currentUID[scope] {
                            Label(title(dev, scope), systemImage: "checkmark")
                        } else {
                            Text(title(dev, scope))
                        }
                    }
                }
            }
        }
        Divider()
        Toggle("Auto Switch", isOn: $autoSwitch)
            .onChange(of: autoSwitch) { ranker.autoSwitchChanged() }
        Button("Settings…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Button("Support / Donate ❤️") { openDonationPage() }
        Divider()
        Button("Quit OutputRanker") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func title(_ dev: AudioDevice, _ scope: AudioScope) -> String {
        var text = dev.name
        if ranker.ignored.contains(dev.uid) { text += " (hidden)" }
        if dev.uid == ranker.currentUID[scope], ranker.override[scope] == true { text += " — manual" }
        return text
    }
}

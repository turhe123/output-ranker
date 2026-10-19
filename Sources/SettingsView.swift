import ServiceManagement
import SwiftUI

/// Settings window with ranked Outputs/Inputs tabs and a General tab.
struct SettingsView: View {
    var body: some View {
        TabView {
            RankListView(scope: .output).tabItem { Label("Outputs", systemImage: "speaker.wave.2") }
            RankListView(scope: .input).tabItem { Label("Inputs", systemImage: "mic") }
            GeneralSettingsView().tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding()
        .frame(width: 520, height: 460)
    }
}

/// A drag-to-reorder priority list for one scope; disconnected devices stay in place, greyed out.
struct RankListView: View {
    @EnvironmentObject private var ranker: DeviceRanker
    let scope: AudioScope

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drag to reorder. The highest connected device that isn't hidden becomes the default.")
                .font(.callout)
            List {
                ForEach(ranker.ranks[scope] ?? [], id: \.self) { uid in
                    row(uid)
                }
                .onMove { ranker.move(scope, from: $0, to: $1) }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            Text("Tip: Bluetooth headsets may appear twice (hands-free and high quality). Rank each one separately.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func row(_ uid: String) -> some View {
        let dev = ranker.device(uid)
        let isConnected = dev?.supports(scope) == true
        HStack {
            Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
            Circle().fill(isConnected ? Color.green : Color.gray.opacity(0.4)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(ranker.displayName(uid))
                    if uid == ranker.currentUID[scope] {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                }
                Text(dev?.transport ?? "Disconnected").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let vol = ranker.rememberedVolume(uid, scope) {
                Text("\(Int((vol * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
            Toggle("Hide", isOn: Binding(get: { ranker.ignored.contains(uid) },
                                         set: { ranker.setIgnored(uid, $0) }))
                .toggleStyle(.checkbox)
        }
        .opacity(isConnected ? 1 : 0.45)
        .contextMenu {
            if !isConnected { Button("Forget Device") { ranker.forget(uid, scope) } }
        }
    }
}

/// Hotkeys, HUD and launch-at-login options plus the donation button.
struct GeneralSettingsView: View {
    @AppStorage("hotkeysEnabled") private var hotkeysEnabled = true
    @AppStorage("outputKey") private var outputKey = "O"
    @AppStorage("inputKey") private var inputKey = "I"
    @AppStorage("showHUD") private var showHUD = true
    @AppStorage("hudDuration") private var hudDuration = 1.5
    @AppStorage("hudPosition") private var hudPosition = "bottom"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private let keys = HotKeyManager.letters.keys.sorted()

    var body: some View {
        Form {
            Section("Hotkeys") {
                Toggle("Enable global hotkeys", isOn: $hotkeysEnabled)
                Picker("Cycle outputs: ⌃⌥⌘", selection: $outputKey) { ForEach(keys, id: \.self) { Text($0) } }
                Picker("Cycle inputs: ⌃⌥⌘", selection: $inputKey) { ForEach(keys, id: \.self) { Text($0) } }
            }
            .onChange(of: hotkeysEnabled) { HotKeyManager.shared.reload() }
            .onChange(of: outputKey) { HotKeyManager.shared.reload() }
            .onChange(of: inputKey) { HotKeyManager.shared.reload() }

            Section("HUD") {
                Toggle("Show HUD after switching", isOn: $showHUD)
                Slider(value: $hudDuration, in: 0.5...5, step: 0.5) {
                    Text("Duration: \(hudDuration, specifier: "%.1f") s")
                }
                Picker("Position", selection: $hudPosition) {
                    Text("Top").tag("top")
                    Text("Center").tag("center")
                    Text("Bottom").tag("bottom")
                }
                Button("Preview HUD") {
                    HUDController.shared.show(name: "OutputRanker", scope: .output, volume: 0.6)
                }
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { setLaunchAtLogin(launchAtLogin) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }

            Section {
                Button("Support / Donate ❤️") { openDonationPage() }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription). Check System Settings › General › Login Items."
        }
    }
}

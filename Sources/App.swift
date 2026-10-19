import AppKit
import SwiftUI

/// Opens the project's donation page.
func openDonationPage() {
    NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
}

/// Boots the device ranker and hotkeys once the app has launched.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            DeviceRanker.shared.start()
            HotKeyManager.shared.reload()
        }
    }
}

/// Menu-bar-only app: a MenuBarExtra for quick switching plus a Settings window.
@main
struct OutputRankerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var ranker = DeviceRanker.shared

    var body: some Scene {
        MenuBarExtra("OutputRanker", systemImage: "hifispeaker.2.fill") {
            MenuView().environmentObject(ranker)
        }
        .menuBarExtraStyle(.menu)

        Window("OutputRanker Settings", id: "settings") {
            SettingsView().environmentObject(ranker)
        }
        .windowResizability(.contentSize)
    }
}

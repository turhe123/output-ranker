import AudioToolbox
import CoreAudio
import Foundation

/// Owns the ranked device lists, watches CoreAudio for changes and picks the best default device.
@MainActor
final class DeviceRanker: ObservableObject {
    static let shared = DeviceRanker()

    @Published private(set) var connected: [AudioDevice] = []
    @Published private(set) var ranks: [AudioScope: [String]] = [:]
    @Published private(set) var names: [String: String] = [:]
    @Published private(set) var ignored: Set<String> = []
    @Published private(set) var volumes: [String: Float] = [:]
    @Published private(set) var currentUID: [AudioScope: String] = [:]
    @Published private(set) var override: [AudioScope: Bool] = [:]

    private let defaults = UserDefaults.standard
    private var debounce: Task<Void, Never>?
    private var suppressUntil = Date.distantPast
    private var listenerTokens: [() -> Void] = []
    private var volumeTokens: [AudioScope: () -> Void] = [:]

    var autoSwitch: Bool { defaults.bool(forKey: "autoSwitch") }

    private init() {
        defaults.register(defaults: ["autoSwitch": true, "showHUD": true, "hudDuration": 1.5,
                                     "hudPosition": "bottom", "hotkeysEnabled": true,
                                     "outputKey": "O", "inputKey": "I"])
        for scope in AudioScope.allCases { ranks[scope] = defaults.stringArray(forKey: "rank.\(scope.rawValue)") ?? [] }
        names = defaults.dictionary(forKey: "names") as? [String: String] ?? [:]
        ignored = Set(defaults.stringArray(forKey: "ignored") ?? [])
        volumes = (defaults.dictionary(forKey: "volumes") as? [String: Double] ?? [:]).mapValues { Float($0) }
    }

    /// Installs CoreAudio listeners and performs the initial scan.
    func start() {
        let sys = CoreAudioBridge.system
        listenerTokens.append(CoreAudioBridge.listen(sys, CoreAudioBridge.address(kAudioHardwarePropertyDevices)) { [weak self] in
            self?.scheduleDeviceChange()
        })
        for scope in AudioScope.allCases {
            listenerTokens.append(CoreAudioBridge.listen(sys, CoreAudioBridge.address(scope.defaultSelector)) { [weak self] in
                self?.defaultChanged(scope)
            })
        }
        rescan(isDeviceChange: false)
        if autoSwitch { AudioScope.allCases.forEach { applyRanking($0, showHUD: false) } }
    }

    // MARK: Queries

    func device(_ uid: String) -> AudioDevice? { connected.first { $0.uid == uid } }

    func connectedDevices(_ scope: AudioScope) -> [AudioDevice] {
        (ranks[scope] ?? []).compactMap { device($0) }.filter { $0.supports(scope) }
    }

    func displayName(_ uid: String) -> String { names[uid] ?? uid }

    // MARK: Event handling

    private func scheduleDeviceChange() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.handleDeviceListChange()
        }
    }

    private func handleDeviceListChange() {
        let before = Set(connected.map(\.uid))
        rescan(isDeviceChange: true)
        let arrived = Set(connected.map(\.uid)).subtracting(before)
        for scope in AudioScope.allCases {
            // An override holds only while its device stays and nothing new appears for that scope.
            let current = currentUID[scope].flatMap(device)
            let newForScope = arrived.contains { device($0)?.supports(scope) == true }
            if override[scope] == true, current != nil, !newForScope { continue }
            override[scope] = false
            if autoSwitch { applyRanking(scope, showHUD: true) }
        }
    }

    private func defaultChanged(_ scope: AudioScope) {
        refreshCurrent()
        // Changes we didn't make (e.g. System Settings) count as a manual override.
        if Date() > suppressUntil { override[scope] = true }
    }

    private func rescan(isDeviceChange: Bool) {
        connected = CoreAudioBridge.devices()
        // First run: seed each empty list with the current default so we don't switch away from it.
        for scope in AudioScope.allCases where (ranks[scope] ?? []).isEmpty {
            let id = CoreAudioBridge.defaultDevice(scope)
            if let dev = connected.first(where: { $0.id == id }) { ranks[scope] = [dev.uid] }
        }
        for dev in connected {
            names[dev.uid] = dev.name
            for scope in AudioScope.allCases where dev.supports(scope) && !(ranks[scope] ?? []).contains(dev.uid) {
                ranks[scope, default: []].append(dev.uid)
            }
        }
        persist()
        refreshCurrent()
    }

    private func refreshCurrent() {
        for scope in AudioScope.allCases {
            let id = CoreAudioBridge.defaultDevice(scope)
            let uid = connected.first { $0.id == id }?.uid
            if currentUID[scope] != uid { currentUID[scope] = uid; watchVolume(scope) }
        }
    }

    /// Tracks the volume of the current default device so it can be restored later.
    private func watchVolume(_ scope: AudioScope) {
        volumeTokens[scope]?()
        volumeTokens[scope] = nil
        guard let uid = currentUID[scope], let dev = device(uid) else { return }
        rememberVolume(dev, scope)
        let addr = CoreAudioBridge.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope.caScope)
        volumeTokens[scope] = CoreAudioBridge.listen(dev.id, addr) { [weak self] in self?.rememberVolume(dev, scope) }
    }

    private func rememberVolume(_ dev: AudioDevice, _ scope: AudioScope) {
        guard Date() > suppressUntil, let vol = CoreAudioBridge.volume(dev.id, scope) else { return }
        volumes["\(scope.rawValue):\(dev.uid)"] = vol
        defaults.set(volumes.mapValues { Double($0) }, forKey: "volumes")
    }

    func rememberedVolume(_ uid: String, _ scope: AudioScope) -> Float? { volumes["\(scope.rawValue):\(uid)"] }

    // MARK: Switching

    /// Makes the highest-ranked connected, non-ignored device the default, falling back down the list on failure.
    func applyRanking(_ scope: AudioScope, showHUD: Bool) {
        for dev in connectedDevices(scope) where !ignored.contains(dev.uid) {
            if dev.uid == currentUID[scope] { return }
            if activate(dev, scope, showHUD: showHUD) { return }
        }
    }

    /// User-initiated switch from the menu or a hotkey; sets the override flag.
    func select(_ dev: AudioDevice, _ scope: AudioScope) {
        if activate(dev, scope, showHUD: true) { override[scope] = true }
    }

    /// Cycles to the next connected, non-ignored device in rank order.
    func cycle(_ scope: AudioScope) {
        let list = connectedDevices(scope).filter { !ignored.contains($0.uid) }
        guard !list.isEmpty else { return }
        let idx = list.firstIndex { $0.uid == currentUID[scope] } ?? -1
        select(list[(idx + 1) % list.count], scope)
    }

    @discardableResult
    private func activate(_ dev: AudioDevice, _ scope: AudioScope, showHUD: Bool) -> Bool {
        suppressUntil = Date().addingTimeInterval(1.0)
        guard CoreAudioBridge.setDefault(dev.id, scope) else { return false }
        if let vol = rememberedVolume(dev.uid, scope) { CoreAudioBridge.setVolume(dev.id, scope, vol) }
        refreshCurrent()
        if showHUD, defaults.bool(forKey: "showHUD") {
            HUDController.shared.show(name: dev.name, scope: scope, volume: CoreAudioBridge.volume(dev.id, scope))
        }
        return true
    }

    // MARK: Editing

    func move(_ scope: AudioScope, from: IndexSet, to: Int) {
        ranks[scope, default: []].move(fromOffsets: from, toOffset: to)
        persist()
        if autoSwitch, override[scope] != true { applyRanking(scope, showHUD: false) }
    }

    func setIgnored(_ uid: String, _ value: Bool) {
        if value { ignored.insert(uid) } else { ignored.remove(uid) }
        persist()
    }

    func forget(_ uid: String, _ scope: AudioScope) {
        ranks[scope]?.removeAll { $0 == uid }
        persist()
    }

    func autoSwitchChanged() {
        guard autoSwitch else { return }
        AudioScope.allCases.forEach { override[$0] = false; applyRanking($0, showHUD: true) }
    }

    private func persist() {
        for (scope, list) in ranks { defaults.set(list, forKey: "rank.\(scope.rawValue)") }
        defaults.set(names, forKey: "names")
        defaults.set(Array(ignored), forKey: "ignored")
    }
}

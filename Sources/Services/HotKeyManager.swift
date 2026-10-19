import Carbon
import Foundation

/// Registers global ⌃⌥⌘ hotkeys via Carbon's RegisterEventHotKey to cycle outputs and inputs.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()
    static let letters: [String: Int] = [
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E, "F": kVK_ANSI_F,
        "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
        "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R,
        "S": kVK_ANSI_S, "T": kVK_ANSI_T, "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
        "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
    ]
    private var refs: [EventHotKeyRef] = []
    private var handlerInstalled = false

    /// Re-registers hotkeys from the current UserDefaults settings.
    func reload() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "hotkeysEnabled") else { return }
        installHandler()
        let mods = UInt32(controlKey | optionKey | cmdKey)
        for (index, key) in ["outputKey", "inputKey"].enumerated() {
            guard let code = Self.letters[defaults.string(forKey: key) ?? ""] else { continue }
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x4F52_4B52), id: UInt32(index))
            if RegisterEventHotKey(UInt32(code), mods, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr,
               let ref { refs.append(ref) }
        }
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let scope: AudioScope = hotKeyID.id == 0 ? .output : .input
            DispatchQueue.main.async { MainActor.assumeIsolated { DeviceRanker.shared.cycle(scope) } }
            return noErr
        }
        handlerInstalled = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, nil, nil) == noErr
    }
}

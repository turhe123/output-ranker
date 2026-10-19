import AudioToolbox
import CoreAudio
import Foundation

/// Direction of an audio device: playback (output) or recording (input).
enum AudioScope: String, CaseIterable, Identifiable {
    case output, input
    var id: String { rawValue }
    var title: String { self == .output ? "Output" : "Input" }
    var caScope: AudioObjectPropertyScope {
        self == .output ? kAudioObjectPropertyScopeOutput : kAudioObjectPropertyScopeInput
    }
    var defaultSelector: AudioObjectPropertySelector {
        self == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
    }
}

/// A snapshot of one connected CoreAudio device.
struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: String
    let hasOutput: Bool
    let hasInput: Bool

    func supports(_ scope: AudioScope) -> Bool { scope == .output ? hasOutput : hasInput }
}

/// Thin, failure-tolerant wrapper around the CoreAudio HAL C API.
enum CoreAudioBridge {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Enumerates every device exposed by kAudioHardwarePropertyDevices.
    static func devices() -> [AudioDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let out = channelCount(id, .output) > 0, inp = channelCount(id, .input) > 0
            guard out || inp else { return nil }
            return AudioDevice(id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? uid,
                               transport: transportName(id), hasOutput: out, hasInput: inp)
        }
    }

    static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    /// Sums channels from kAudioDevicePropertyStreamConfiguration to classify input vs output.
    static func channelCount(_ id: AudioDeviceID, _ scope: AudioScope) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope.caScope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func transportName(_ id: AudioDeviceID) -> String {
        var addr = address(kAudioDevicePropertyTransportType)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return "Unknown" }
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: return "Built-in"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return "Bluetooth"
        case kAudioDeviceTransportTypeUSB: return "USB"
        case kAudioDeviceTransportTypeVirtual: return "Virtual"
        case kAudioDeviceTransportTypeAggregate: return "Aggregate"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "Display"
        case kAudioDeviceTransportTypeAirPlay: return "AirPlay"
        case kAudioDeviceTransportTypeThunderbolt: return "Thunderbolt"
        default: return "Other"
        }
    }

    static func defaultDevice(_ scope: AudioScope) -> AudioDeviceID? {
        var addr = address(scope.defaultSelector)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    /// Sets the default device; for outputs also moves the system (alert) output.
    @discardableResult
    static func setDefault(_ id: AudioDeviceID, _ scope: AudioScope) -> Bool {
        var target = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = address(scope.defaultSelector)
        guard AudioObjectSetPropertyData(system, &addr, 0, nil, size, &target) == noErr else { return false }
        if scope == .output {
            var sysAddr = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
            _ = AudioObjectSetPropertyData(system, &sysAddr, 0, nil, size, &target)
        }
        return defaultDevice(scope) == id
    }

    static func volume(_ id: AudioDeviceID, _ scope: AudioScope) -> Float? {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope.caScope)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func setVolume(_ id: AudioDeviceID, _ scope: AudioScope, _ volume: Float) {
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope.caScope)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(id, &addr),
              AudioObjectIsPropertySettable(id, &addr, &settable) == noErr, settable.boolValue else { return }
        var value = Float32(min(max(volume, 0), 1))
        _ = AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    /// Registers a main-queue listener; returns a token that removes it.
    static func listen(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress,
                       _ handler: @escaping @MainActor () -> Void) -> () -> Void {
        var a = addr
        let block: AudioObjectPropertyListenerBlock = { _, _ in MainActor.assumeIsolated { handler() } }
        guard AudioObjectAddPropertyListenerBlock(object, &a, .main, block) == noErr else { return {} }
        return { var r = addr; _ = AudioObjectRemovePropertyListenerBlock(object, &r, .main, block) }
    }
}

import Foundation
import CoreAudio
import CoreGraphics

/// Exposes system volume (CoreAudio) and display brightness (DisplayServices,
/// private — dlsym, graceful degradation) as observable properties.
final class SystemControls: ObservableObject {
    static let shared = SystemControls()

    @Published var volume: Float = 0
    @Published var brightness: Float = 0
    @Published private(set) var brightnessAvailable = false

    private init() {
        volume = readVolume()
        if let b = readBrightness() {
            brightness = b
            brightnessAvailable = true
        }
    }

    // MARK: - Volume (CoreAudio public API)

    private func defaultOutputDevice() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private func readVolume() -> Float {
        let device = defaultOutputDevice()
        var vol: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        // 0x766d7663 = 'vmvc' = kAudioHardwareServiceDeviceProperty_VirtualMasterVolume
        var addr = AudioObjectPropertyAddress(
            mSelector: 0x766d7663,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &vol)
        return vol
    }

    func setVolume(_ value: Float) {
        let device = defaultOutputDevice()
        var vol = value
        let size = UInt32(MemoryLayout<Float32>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: 0x766d7663,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(device, &addr, 0, nil, size, &vol)
        DispatchQueue.main.async { self.volume = value }
    }

    // MARK: - Brightness (DisplayServices, private — dlsym)

    private typealias GetBrightFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private lazy var getFn: GetBrightFn? = {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                            "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(p, to: GetBrightFn.self)
    }()

    private lazy var setFn: SetBrightFn? = {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2),
                            "DisplayServicesSetBrightness") else { return nil }
        return unsafeBitCast(p, to: SetBrightFn.self)
    }()

    private func readBrightness() -> Float? {
        guard let fn = getFn else { return nil }
        var v: Float = 0
        guard fn(CGMainDisplayID(), &v) == 0 else { return nil }
        return v
    }

    func setBrightness(_ value: Float) {
        guard let fn = setFn else { return }
        _ = fn(CGMainDisplayID(), value)
        DispatchQueue.main.async { self.brightness = value }
    }

    func refreshFromSystem() {
        volume = readVolume()
        if let b = readBrightness() { brightness = b }
    }
}

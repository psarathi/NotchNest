import AppKit
import AudioToolbox
import CoreAudio
import Darwin
import Foundation
import IOKit.ps
import IOKit.pwr_mgt
import Observation

public struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    public let id: UInt32
    public let name: String
    public let isDefault: Bool

    public var systemImage: String {
        let lower = name.lowercased()
        if lower.contains("airpod") { return "airpodspro" }
        if lower.contains("headphone") || lower.contains("beats") || lower.contains("sony") || lower.contains("bose") {
            return "headphones"
        }
        if lower.contains("hdmi") || lower.contains("display") || lower.contains("studio") {
            return "display"
        }
        return "hifispeaker.fill"
    }
}

public struct BluetoothGearBattery: Identifiable, Equatable, Sendable {
    public var id: String { "\(name)-\(percent)" }
    public var name: String
    public var percent: Int
    public var kind: String

    public init(name: String, percent: Int, kind: String) {
        self.name = name
        self.percent = percent
        self.kind = kind
    }

    public var systemImage: String {
        let lower = (name + " " + kind).lowercased()
        if lower.contains("airpod") { return "airpodspro" }
        if lower.contains("headphone") || lower.contains("beats") || lower.contains("sony") { return "headphones" }
        if lower.contains("mouse") { return "computermouse" }
        if lower.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
        if lower.contains("keyboard") { return "keyboard" }
        return "wave.3.right.circle"
    }
}

public struct InstalledAppItem: Identifiable, Equatable, Sendable {
    public var id: String { url.path }
    public var name: String
    public var url: URL

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

/// Samples live macOS CPU, RAM, storage, battery, Bluetooth device batteries, Prevent-Sleep assertion, and installed apps.
@MainActor
@Observable
public final class SystemAndPowerService {
    public private(set) var cpuUsagePercent: Double = 0
    public private(set) var memoryUsedGB: Double = 0
    public private(set) var memoryTotalGB: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    public private(set) var diskFreeGB: Double = 0
    public private(set) var diskTotalGB: Double = 0
    public private(set) var batteryPercent: Int?
    public private(set) var isCharging: Bool = false
    public private(set) var bluetoothDevices: [BluetoothGearBattery] = []
    public private(set) var installedApps: [InstalledAppItem] = []
    public private(set) var outputDevices: [AudioOutputDevice] = []
    public private(set) var systemVolume: Double = 0.5
    public private(set) var isSystemMuted: Bool = false
    public private(set) var isPreventSleepActive: Bool = false

    public var onBluetoothEvent: (@MainActor (BluetoothGearBattery, Bool) -> Void)?
    public var onLowBattery: (@MainActor (Int) -> Void)?

    private var lastCPUTicks: (user: UInt64, sys: UInt64, idle: UInt64, nice: UInt64)?
    private var powerAssertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var pollTimer: Timer?
    private var hasSeededBluetooth = false
    private var knownBluetoothNames: Set<String> = []
    private var warnedLowBluetoothNames: Set<String> = []
    private var warnedLowSystemBattery = false

    public init() {}

    public func startMonitoring() {
        refreshMetrics()
        refreshAppsIfNeeded()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshMetrics()
            }
        }
    }

    public func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
        setPreventSleep(false)
    }

    public func refreshMetrics() {
        updateCPU()
        updateMemory()
        updateDisk()
        updateBattery()
        refreshBluetoothBatteries()
        refreshAudioRouting()
    }

    public func refreshAppsIfNeeded() {
        guard installedApps.isEmpty else { return }
        Task.detached(priority: .utility) {
            let apps = Self.scanInstalledApplications()
            await MainActor.run { [weak self] in
                self?.installedApps = apps
            }
        }
    }

    public func setPreventSleep(_ enabled: Bool) {
        if enabled {
            guard !hasAssertion else {
                isPreventSleepActive = true
                return
            }
            var assertionID: IOPMAssertionID = 0
            let reason = "NotchNest Never Sleep toggle" as CFString
            let status = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason,
                &assertionID
            )
            if status == kIOReturnSuccess {
                powerAssertionID = assertionID
                hasAssertion = true
                isPreventSleepActive = true
            }
        } else {
            if hasAssertion {
                IOPMAssertionRelease(powerAssertionID)
                powerAssertionID = 0
                hasAssertion = false
            }
            isPreventSleepActive = false
        }
    }

    public func lockScreen() {
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["displaysleepnow"]
            try? process.run()
        }
    }

    public func toggleDarkMode() {
        Task.detached(priority: .userInitiated) {
            let script = NSAppleScript(
                source: #"tell application "System Events" to tell appearance preferences to set dark mode to not dark mode"#
            )
            var err: NSDictionary?
            script?.executeAndReturnError(&err)
        }
    }

    // MARK: - Mach / IOKit Samplers

    private func updateCPU() {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCPUInfo: mach_msg_type_number_t = 0
        let err = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCPUInfo
        )
        guard err == KERN_SUCCESS, let cpuInfo else { return }
        defer {
            let size = vm_size_t(MemoryLayout<integer_t>.stride * Int(numCPUInfo))
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)
        }

        var user: UInt64 = 0
        var sys: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0

        for i in 0..<Int(numCPUs) {
            let base = i * Int(CPU_STATE_MAX)
            user += UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_USER)]))
            sys += UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_SYSTEM)]))
            idle += UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_IDLE)]))
            nice += UInt64(UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_NICE)]))
        }

        if let prev = lastCPUTicks {
            let dUser = user &- prev.user
            let dSys = sys &- prev.sys
            let dIdle = idle &- prev.idle
            let dNice = nice &- prev.nice
            let total = dUser + dSys + dIdle + dNice
            if total > 0 {
                let busy = Double(dUser + dSys + dNice)
                cpuUsagePercent = min(100, max(0, (busy / Double(total)) * 100.0))
            }
        }
        lastCPUTicks = (user, sys, idle, nice)
    }

    private func updateMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }
        var kernelPageSize: vm_size_t = 4096
        host_page_size(mach_host_self(), &kernelPageSize)
        let pageSize = Double(kernelPageSize)
        let usedBytes = Double(UInt64(stats.active_count) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * pageSize
        memoryUsedGB = usedBytes / 1_073_741_824.0
    }

    private func updateDisk() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let vals = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
           let avail = vals.volumeAvailableCapacityForImportantUsage,
           let total = vals.volumeTotalCapacity {
            diskFreeGB = Double(avail) / 1_000_000_000.0
            diskTotalGB = Double(total) / 1_000_000_000.0
        }
    }

    private func updateBattery() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return
        }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let cap = desc[kIOPSCurrentCapacityKey] as? Int {
                batteryPercent = cap
            }
            if let charging = desc[kIOPSIsChargingKey] as? Bool {
                isCharging = charging
            }
            if let cap = batteryPercent, !isCharging, cap <= 15 {
                if !warnedLowSystemBattery {
                    warnedLowSystemBattery = true
                    onLowBattery?(cap)
                }
            } else {
                warnedLowSystemBattery = false
            }
        }
    }

    private func refreshBluetoothBatteries() {
        Task.detached(priority: .utility) {
            let devices = Self.queryBluetoothBatteries()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.bluetoothDevices = devices
                let currentNames = Set(devices.map(\.name))
                if !self.hasSeededBluetooth {
                    self.hasSeededBluetooth = true
                    self.knownBluetoothNames = currentNames
                    for dev in devices where dev.percent <= 20 {
                        self.warnedLowBluetoothNames.insert(dev.name)
                    }
                    return
                }

                for dev in devices {
                    if !self.knownBluetoothNames.contains(dev.name) {
                        self.onBluetoothEvent?(dev, dev.percent <= 20)
                        if dev.percent <= 20 {
                            self.warnedLowBluetoothNames.insert(dev.name)
                        }
                    } else if dev.percent <= 20 && !self.warnedLowBluetoothNames.contains(dev.name) {
                        self.warnedLowBluetoothNames.insert(dev.name)
                        self.onBluetoothEvent?(dev, true)
                    } else if dev.percent > 25 {
                        self.warnedLowBluetoothNames.remove(dev.name)
                    }
                }
                self.knownBluetoothNames = currentNames
            }
        }
    }

    nonisolated private static func queryBluetoothBatteries() -> [BluetoothGearBattery] {
        var found: [BluetoothGearBattery] = []
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-r", "-c", "AppleDeviceManagementHIDEventService", "-l"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let blocks = text.components(separatedBy: "+-o ")
        for block in blocks {
            guard let pct = extractInt(key: "\"BatteryPercent\" =", in: block) else { continue }
            let name = extractString(key: "\"Product\" =", in: block) ?? "Bluetooth Accessory"
            let transport = extractString(key: "\"Transport\" =", in: block) ?? "Bluetooth"
            if transport.localizedCaseInsensitiveContains("Bluetooth") || !name.isEmpty {
                let item = BluetoothGearBattery(name: name, percent: pct, kind: transport)
                if !found.contains(where: { $0.name == item.name }) {
                    found.append(item)
                }
            }
        }
        return found
    }

    nonisolated private static func extractInt(key: String, in block: String) -> Int? {
        for line in block.components(separatedBy: .newlines) where line.contains(key) {
            let rhs = line.components(separatedBy: "=").last?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let val = Int(rhs) {
                return val
            }
        }
        return nil
    }

    nonisolated private static func extractString(key: String, in block: String) -> String? {
        for line in block.components(separatedBy: .newlines) where line.contains(key) {
            if let rhs = line.components(separatedBy: "=").last {
                return rhs.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
            }
        }
        return nil
    }

    nonisolated private static func scanInstalledApplications() -> [InstalledAppItem] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]
        var items: [InstalledAppItem] = []
        var seen: Set<String> = []
        for root in roots {
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents where url.pathExtension.lowercased() == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                if seen.insert(name).inserted {
                    items.append(InstalledAppItem(name: name, url: url))
                }
            }
        }
        return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - CoreAudio Output Routing & Volume

    public func refreshAudioRouting() {
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultID: AudioDeviceID = kAudioObjectUnknown
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        _ = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            0,
            nil,
            &defaultSize,
            &defaultID
        )

        var devicesAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devicesSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr,
            0,
            nil,
            &devicesSize
        ) == noErr, devicesSize > 0 else {
            return
        }

        let count = Int(devicesSize) / MemoryLayout<AudioDeviceID>.stride
        var ids = [AudioDeviceID](repeating: kAudioObjectUnknown, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr,
            0,
            nil,
            &devicesSize,
            &ids
        ) == noErr else {
            return
        }

        var found: [AudioOutputDevice] = []
        for devID in ids where devID != kAudioObjectUnknown {
            guard Self.deviceHasOutputChannels(devID) else { continue }
            guard let name = Self.audioDeviceName(devID), !name.isEmpty else { continue }
            found.append(AudioOutputDevice(id: devID, name: name, isDefault: devID == defaultID))
        }
        outputDevices = found

        if defaultID != kAudioObjectUnknown {
            systemVolume = Double(Self.readVolume(deviceID: defaultID))
            isSystemMuted = Self.readMuted(deviceID: defaultID)
        }
    }

    public func selectOutputDevice(_ deviceID: UInt32) {
        var target = AudioDeviceID(deviceID)
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            0,
            nil,
            UInt32(MemoryLayout<AudioDeviceID>.size),
            &target
        )
        refreshAudioRouting()
    }

    public func setSystemVolume(_ level: Double) {
        let clamped = Float32(min(1.0, max(0.0, level)))
        systemVolume = Double(clamped)
        guard let devID = currentDefaultOutputDeviceID() else { return }

        var virtualAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutable = clamped
        if AudioObjectHasProperty(devID, &virtualAddr) {
            _ = AudioObjectSetPropertyData(devID, &virtualAddr, 0, nil, UInt32(MemoryLayout<Float32>.size), &mutable)
        } else {
            for channel in [UInt32(0), UInt32(1), UInt32(2)] {
                var chAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyVolumeScalar,
                    mScope: kAudioObjectPropertyScopeOutput,
                    mElement: channel
                )
                if AudioObjectHasProperty(devID, &chAddr) {
                    _ = AudioObjectSetPropertyData(devID, &chAddr, 0, nil, UInt32(MemoryLayout<Float32>.size), &mutable)
                }
            }
        }
    }

    public func toggleSystemMute() {
        guard let devID = currentDefaultOutputDeviceID() else { return }
        let nextMuted: UInt32 = isSystemMuted ? 0 : 1
        var val = nextMuted
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectHasProperty(devID, &muteAddr) {
            _ = AudioObjectSetPropertyData(devID, &muteAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &val)
            isSystemMuted = (nextMuted == 1)
        } else if nextMuted == 1 {
            setSystemVolume(0)
            isSystemMuted = true
        }
        refreshAudioRouting()
    }

    private func currentDefaultOutputDeviceID() -> AudioDeviceID? {
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var devID: AudioDeviceID = kAudioObjectUnknown
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            0,
            nil,
            &size,
            &devID
        ) == noErr, devID != kAudioObjectUnknown else {
            return nil
        }
        return devID
    }

    private static func deviceHasOutputChannels(_ devID: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(devID, &addr, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size) else {
            return false
        }
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        let bufList = raw.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(devID, &addr, 0, nil, &size, bufList) == noErr else {
            return false
        }
        let buffers = UnsafeMutableAudioBufferListPointer(bufList)
        return buffers.contains { $0.mNumberChannels > 0 }
    }

    private static func audioDeviceName(_ devID: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfName: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(devID, &addr, 0, nil, &size, &cfName) == noErr else {
            return nil
        }
        return cfName?.takeRetainedValue() as String?
    }

    private static func readVolume(deviceID: AudioDeviceID) -> Float32 {
        var virtualAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var vol: Float32 = 0.5
        var size = UInt32(MemoryLayout<Float32>.size)
        if AudioObjectHasProperty(deviceID, &virtualAddr),
           AudioObjectGetPropertyData(deviceID, &virtualAddr, 0, nil, &size, &vol) == noErr {
            return vol
        }
        for ch in [UInt32(0), UInt32(1)] {
            var chAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: ch
            )
            if AudioObjectHasProperty(deviceID, &chAddr),
               AudioObjectGetPropertyData(deviceID, &chAddr, 0, nil, &size, &vol) == noErr {
                return vol
            }
        }
        return vol
    }

    private static func readMuted(deviceID: AudioDeviceID) -> Bool {
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(deviceID, &muteAddr),
           AudioObjectGetPropertyData(deviceID, &muteAddr, 0, nil, &size, &muted) == noErr {
            return muted != 0
        }
        return false
    }
}

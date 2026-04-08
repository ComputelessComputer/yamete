import CoreFoundation
import Foundation
import IOKit
import IOKit.hid

final class MotionMonitor: @unchecked Sendable {
    var onStateChange: (@Sendable (MotionBackendState) -> Void)?
    var onSnapshot: (@Sendable (MotionSnapshot) -> Void)?
    var onImpact: (@Sendable (ImpactEvent) -> Void)?

    private let lock = NSLock()
    private var settings: DetectionSettings
    private var processor: MotionProcessor
    private var latestGyro = TimedVector(timestamp: 0, vector: .zero)
    private var lastSnapshotTimestamp = 0.0
    private var session: AppleSPUSession?

    init(settings: DetectionSettings) {
        self.settings = settings
        self.processor = MotionProcessor(settings: settings)
    }

    func update(settings: DetectionSettings) {
        lock.lock()
        self.settings = settings
        processor.update(settings: settings)
        session?.sampleRate = settings.sampleRate
        lock.unlock()
    }

    func start() {
        stop(notify: false)

        let session = AppleSPUSession(sampleRate: settings.sampleRate)
        session.onState = { [weak self] state in
            self?.onStateChange?(state)
        }
        session.onAccel = { [weak self] sample in
            self?.handleAccel(sample)
        }
        session.onGyro = { [weak self] sample in
            self?.handleGyro(sample)
        }

        lock.lock()
        self.session = session
        self.latestGyro = TimedVector(timestamp: 0, vector: .zero)
        self.lastSnapshotTimestamp = 0
        self.processor = MotionProcessor(settings: settings)
        lock.unlock()

        session.start()
    }

    func stop(notify: Bool = true) {
        lock.lock()
        let session = self.session
        self.session = nil
        lock.unlock()

        session?.stop()
        if notify {
            onStateChange?(.stopped("Sensor capture stopped. Preview Test Slap still works."))
        }
    }

    private func handleGyro(_ sample: TimedVector) {
        lock.withLock {
            latestGyro = sample
        }
    }

    private func handleAccel(_ sample: TimedVector) {
        let outcome: (snapshot: MotionSnapshot, impact: ImpactEvent?, shouldPublish: Bool) = lock.withLock {
            let gyro = latestGyro.vector
            let result = processor.process(accel: sample.vector, gyro: gyro, timestamp: sample.timestamp)
            let shouldPublish = sample.timestamp - lastSnapshotTimestamp >= 0.05
            if shouldPublish {
                lastSnapshotTimestamp = sample.timestamp
            }
            return (result.0, result.1, shouldPublish)
        }

        if outcome.shouldPublish {
            onSnapshot?(outcome.snapshot)
        }
        if let impact = outcome.impact {
            onImpact?(impact)
        }
    }
}

private final class AppleSPUSession: @unchecked Sendable {
    var onState: (@Sendable (MotionBackendState) -> Void)?
    var onAccel: (@Sendable (TimedVector) -> Void)?
    var onGyro: (@Sendable (TimedVector) -> Void)?

    var sampleRate: Int

    private let lock = NSLock()
    private let timebase = MachTimebase()
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var stopRequested = false
    private var exitSignal = DispatchSemaphore(value: 0)
    private var devices: [ManagedDevice] = []
    private var accelDecimationCounter = 0
    private var gyroDecimationCounter = 0

    init(sampleRate: Int) {
        self.sampleRate = max(25, min(sampleRate, 400))
    }

    func start() {
        lock.lock()
        guard thread == nil else {
            lock.unlock()
            return
        }
        stopRequested = false
        exitSignal = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            self?.run()
        }
        thread.name = "yamete.apple-spu"
        thread.qualityOfService = .userInitiated
        self.thread = thread
        lock.unlock()
        thread.start()
    }

    func stop() {
        let runLoop = lock.withLock { () -> CFRunLoop? in
            stopRequested = true
            return self.runLoop
        }

        if let runLoop {
            CFRunLoopStop(runLoop)
        }

        _ = exitSignal.wait(timeout: .now() + 2)

        lock.lock()
        thread = nil
        self.runLoop = nil
        lock.unlock()
    }

    private func run() {
        defer {
            cleanupDevices()
            exitSignal.signal()
        }

        let discoveredSensors = SensorDiscovery.probe()
        guard discoveredSensors.hasAccelerometer else {
            onState?(.unavailable("No Apple SPU accelerometer was detected. The rewritten Yamete backend currently targets compatible Apple Silicon MacBook models only."))
            return
        }

        wakeDrivers()

        let openedDevices = openDevices()
        devices = openedDevices

        guard devices.contains(where: { $0.kind == .accelerometer }) else {
            if geteuid() != 0 {
                onState?(.needsRoot("The Apple SPU sensor exists, but live access requires root privileges. Launch the app binary from a root shell to enable real impacts."))
            } else {
                onState?(.failed("Yamete found the Apple SPU sensor but could not open it for streaming."))
            }
            return
        }

        let advertisedRate = Int(round(800 / Double(decimation)))
        onState?(.running("Streaming Apple SPU motion data at roughly \(advertisedRate) Hz."))

        let currentRunLoop = CFRunLoopGetCurrent()
        lock.withLock {
            runLoop = currentRunLoop
        }

        while !shouldStop {
            _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.25, false)
        }
    }

    private var shouldStop: Bool {
        lock.withLock { stopRequested }
    }

    private var decimation: Int {
        max(1, Int(round(800 / Double(sampleRate))))
    }

    private func wakeDrivers() {
        forEachService(named: "AppleSPUHIDDriver") { service in
            let properties: [(String, NSNumber)] = [
                ("SensorPropertyReportingState", 1),
                ("SensorPropertyPowerState", 1),
                ("ReportInterval", 1_000),
            ]

            for (key, value) in properties {
                IORegistryEntrySetCFProperty(service, key as CFString, value)
            }
        }
    }

    private func openDevices() -> [ManagedDevice] {
        var devices: [ManagedDevice] = []

        forEachService(named: "AppleSPUHIDDevice") { service in
            guard let kind = SensorKind(service: service) else {
                return
            }

            guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else {
                return
            }

            let openResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard openResult == kIOReturnSuccess else {
                return
            }

            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportBufferSize)
            buffer.initialize(repeating: 0, count: reportBufferSize)

            let context = Unmanaged.passRetained(DeviceContext(session: self, kind: kind)).toOpaque()
            IOHIDDeviceRegisterInputReportWithTimeStampCallback(
                device,
                buffer,
                reportBufferSize,
                Self.reportCallback,
                context
            )
            IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

            devices.append(ManagedDevice(ref: device, kind: kind, buffer: buffer, context: context))
        }

        return devices
    }

    private func cleanupDevices() {
        let runLoop = lock.withLock { self.runLoop }

        for device in devices {
            if let runLoop {
                IOHIDDeviceUnscheduleFromRunLoop(device.ref, runLoop, CFRunLoopMode.defaultMode.rawValue)
            }
            IOHIDDeviceClose(device.ref, IOOptionBits(kIOHIDOptionsTypeNone))
            device.buffer.deinitialize(count: reportBufferSize)
            device.buffer.deallocate()
            Unmanaged<DeviceContext>.fromOpaque(device.context).release()
        }

        devices.removeAll(keepingCapacity: false)
        accelDecimationCounter = 0
        gyroDecimationCounter = 0
    }

    private func handleReport(kind: SensorKind, report: UnsafeMutablePointer<UInt8>, length: CFIndex, timestamp: UInt64) {
        guard length == imuReportLength else {
            return
        }

        switch kind {
        case .accelerometer:
            accelDecimationCounter += 1
            guard accelDecimationCounter >= decimation else {
                return
            }
            accelDecimationCounter = 0
        case .gyroscope:
            gyroDecimationCounter += 1
            guard gyroDecimationCounter >= decimation else {
                return
            }
            gyroDecimationCounter = 0
        }

        let vector = Vector3(
            x: Double(int32LE(report, offset: imuDataOffset)) / imuScale,
            y: Double(int32LE(report, offset: imuDataOffset + 4)) / imuScale,
            z: Double(int32LE(report, offset: imuDataOffset + 8)) / imuScale
        )
        let timedVector = TimedVector(
            timestamp: timebase.seconds(for: timestamp),
            vector: vector
        )

        switch kind {
        case .accelerometer:
            onAccel?(timedVector)
        case .gyroscope:
            onGyro?(timedVector)
        }
    }
}

private extension AppleSPUSession {
    static let reportCallback: IOHIDReportWithTimeStampCallback = { context, _, _, _, _, report, reportLength, timeStamp in
        guard let context else {
            return
        }

        let deviceContext = Unmanaged<DeviceContext>.fromOpaque(context).takeUnretainedValue()
        deviceContext.session.handleReport(
            kind: deviceContext.kind,
            report: report,
            length: reportLength,
            timestamp: timeStamp
        )
    }
}

private struct SensorDiscovery {
    let hasAccelerometer: Bool
    let hasGyroscope: Bool

    static func probe() -> Self {
        var hasAccelerometer = false
        var hasGyroscope = false

        forEachService(named: "AppleSPUHIDDevice") { service in
            guard let kind = SensorKind(service: service) else {
                return
            }

            switch kind {
            case .accelerometer:
                hasAccelerometer = true
            case .gyroscope:
                hasGyroscope = true
            }
        }

        return Self(hasAccelerometer: hasAccelerometer, hasGyroscope: hasGyroscope)
    }
}

private final class DeviceContext {
    unowned let session: AppleSPUSession
    let kind: SensorKind

    init(session: AppleSPUSession, kind: SensorKind) {
        self.session = session
        self.kind = kind
    }
}

private struct ManagedDevice {
    let ref: IOHIDDevice
    let kind: SensorKind
    let buffer: UnsafeMutablePointer<UInt8>
    let context: UnsafeMutableRawPointer
}

private struct TimedVector: Sendable {
    let timestamp: TimeInterval
    let vector: Vector3
}

private struct MachTimebase {
    private let scaleToSeconds: Double

    init() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        scaleToSeconds = Double(info.numer) / Double(info.denom) * 1e-9
    }

    func seconds(for machAbsoluteTime: UInt64) -> TimeInterval {
        Double(machAbsoluteTime) * scaleToSeconds
    }
}

private enum SensorKind {
    case accelerometer
    case gyroscope

    init?(service: io_registry_entry_t) {
        let usagePage = integerProperty(named: "PrimaryUsagePage", service: service)
        let usage = integerProperty(named: "PrimaryUsage", service: service)

        switch (usagePage, usage) {
        case (0xFF00, 3):
            self = .accelerometer
        case (0xFF00, 9):
            self = .gyroscope
        default:
            return nil
        }
    }
}

private let imuReportLength: CFIndex = 22
private let imuDataOffset = 6
private let imuScale = 65_536.0
private let reportBufferSize: CFIndex = 4_096

private func forEachService(named className: String, body: (io_registry_entry_t) -> Void) {
    guard let matching = IOServiceMatching(className) else {
        return
    }

    var iterator: io_iterator_t = 0
    let result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
    guard result == KERN_SUCCESS else {
        return
    }
    defer {
        IOObjectRelease(iterator)
    }

    while true {
        let service = IOIteratorNext(iterator)
        guard service != 0 else {
            break
        }

        body(service)
        IOObjectRelease(service)
    }
}

private func integerProperty(named key: String, service: io_registry_entry_t) -> Int? {
    guard let property = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
        return nil
    }

    if CFGetTypeID(property) == CFNumberGetTypeID() {
        var value: Int32 = 0
        if CFNumberGetValue((property as! CFNumber), .sInt32Type, &value) {
            return Int(value)
        }
    }

    return nil
}

private func int32LE(_ buffer: UnsafeMutablePointer<UInt8>, offset: Int) -> Int32 {
    let value = UInt32(buffer[offset])
        | (UInt32(buffer[offset + 1]) << 8)
        | (UInt32(buffer[offset + 2]) << 16)
        | (UInt32(buffer[offset + 3]) << 24)
    return Int32(bitPattern: value)
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

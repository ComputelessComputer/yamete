import Foundation

struct Vector3: Sendable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Self(x: 0, y: 0, z: 0)

    var magnitude: Double {
        sqrt((x * x) + (y * y) + (z * z))
    }
}

struct OrientationEstimate: Sendable {
    var roll: Double
    var pitch: Double
    var yaw: Double
}

struct MotionSnapshot: Sendable {
    let timestamp: TimeInterval
    let accel: Vector3
    let gyro: Vector3
    let dynamic: Vector3
    let dynamicMagnitude: Double
    let sampleRate: Double
    let orientation: OrientationEstimate?
}

struct DetectionSettings: Sendable, Equatable {
    var impactThreshold: Double
    var cooldown: TimeInterval
    var sampleRate: Int
}

struct ImpactEvent: Sendable {
    let timestamp: Date
    let amplitude: Double
    let severity: String
}

enum MotionBackendState: Sendable, Equatable {
    case stopped(String)
    case running(String)
    case needsRoot(String)
    case unavailable(String)
    case failed(String)

    var description: String {
        switch self {
        case let .stopped(message),
             let .running(message),
             let .needsRoot(message),
             let .unavailable(message),
             let .failed(message):
            return message
        }
    }

    var label: String {
        switch self {
        case .unavailable:
            return "Unsupported Hardware"
        case .failed:
            return "Sensor Error"
        default:
            return "Apple SPU IMU"
        }
    }

    var supportsLiveCapture: Bool {
        switch self {
        case .stopped, .running:
            return true
        case .needsRoot, .unavailable, .failed:
            return false
        }
    }

    var isRunning: Bool {
        if case .running = self {
            return true
        }
        return false
    }
}

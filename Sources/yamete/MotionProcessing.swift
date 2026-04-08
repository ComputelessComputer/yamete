import Foundation

struct MotionProcessor {
    private(set) var settings: DetectionSettings
    private var highPass = HighPassFilter(alpha: 0.95)
    private var sampleRateTracker = SampleRateTracker()
    private var orientationFilter = MahonyFilter()
    private var lastImpactTimestamp = -Double.infinity

    init(settings: DetectionSettings) {
        self.settings = settings
    }

    mutating func update(settings: DetectionSettings) {
        self.settings = settings
    }

    mutating func process(accel: Vector3, gyro: Vector3, timestamp: TimeInterval) -> (MotionSnapshot, ImpactEvent?) {
        let dynamic = highPass.filter(accel)
        let rateSample = sampleRateTracker.record(timestamp: timestamp)
        let dt = rateSample?.delta ?? (1 / Double(max(settings.sampleRate, 1)))
        let sampleRate = rateSample?.rate ?? Double(settings.sampleRate)
        let orientation = orientationFilter.update(accel: accel, gyroDegrees: gyro, dt: dt)

        let dynamicMagnitude = dynamic.magnitude
        var impact: ImpactEvent?
        if dynamicMagnitude >= settings.impactThreshold,
           timestamp - lastImpactTimestamp >= settings.cooldown {
            lastImpactTimestamp = timestamp
            impact = ImpactEvent(
                timestamp: Date(),
                amplitude: dynamicMagnitude,
                severity: severity(for: dynamicMagnitude)
            )
        }

        return (
            MotionSnapshot(
                timestamp: timestamp,
                accel: accel,
                gyro: gyro,
                dynamic: dynamic,
                dynamicMagnitude: dynamicMagnitude,
                sampleRate: sampleRate,
                orientation: orientation
            ),
            impact
        )
    }

    private func severity(for amplitude: Double) -> String {
        if amplitude >= settings.impactThreshold * 3 {
            return "SLAM"
        }
        if amplitude >= settings.impactThreshold * 2 {
            return "HIT"
        }
        return "TAP"
    }
}

private struct HighPassFilter {
    let alpha: Double
    private var previousRaw = Vector3.zero
    private var previousOutput = Vector3.zero
    private var isReady = false

    init(alpha: Double) {
        self.alpha = alpha
    }

    mutating func filter(_ input: Vector3) -> Vector3 {
        guard isReady else {
            previousRaw = input
            previousOutput = .zero
            isReady = true
            return .zero
        }

        let output = Vector3(
            x: alpha * (previousOutput.x + input.x - previousRaw.x),
            y: alpha * (previousOutput.y + input.y - previousRaw.y),
            z: alpha * (previousOutput.z + input.z - previousRaw.z)
        )

        previousRaw = input
        previousOutput = output
        return output
    }
}

private struct SampleRateTracker {
    private(set) var lastTimestamp: TimeInterval?
    private(set) var smoothedRate: Double?

    mutating func record(timestamp: TimeInterval) -> (rate: Double, delta: TimeInterval)? {
        guard let lastTimestamp else {
            self.lastTimestamp = timestamp
            return nil
        }

        let delta = max(timestamp - lastTimestamp, 0.000_001)
        let instantRate = 1 / delta
        let rate = (smoothedRate ?? instantRate) * 0.85 + instantRate * 0.15

        self.lastTimestamp = timestamp
        self.smoothedRate = rate
        return (rate, delta)
    }
}

private struct MahonyFilter {
    private var quaternion = Quaternion.identity
    private var integral = Vector3.zero
    private var isInitialized = false
    private let proportionalGain = 1.0
    private let integralGain = 0.05

    mutating func update(accel: Vector3, gyroDegrees: Vector3, dt: TimeInterval) -> OrientationEstimate? {
        let accelMagnitude = accel.magnitude
        guard accelMagnitude >= 0.3 else {
            return isInitialized ? quaternion.orientation : nil
        }

        let accelNorm = Vector3(
            x: accel.x / accelMagnitude,
            y: accel.y / accelMagnitude,
            z: accel.z / accelMagnitude
        )

        if !isInitialized {
            let pitch = atan2(-accelNorm.x, -accelNorm.z)
            let roll = atan2(accelNorm.y, -accelNorm.z)
            quaternion = Quaternion(roll: roll, pitch: pitch, yaw: 0)
            isInitialized = true
            return quaternion.orientation
        }

        let constrainedDelta = min(max(dt, 1 / 800), 0.2)

        var gyro = Vector3(
            x: gyroDegrees.x * .pi / 180,
            y: gyroDegrees.y * .pi / 180,
            z: gyroDegrees.z * .pi / 180
        )

        let estimatedGravity = quaternion.gravityVector
        let error = Vector3(
            x: accelNorm.y * (-estimatedGravity.z) - accelNorm.z * (-estimatedGravity.y),
            y: accelNorm.z * (-estimatedGravity.x) - accelNorm.x * (-estimatedGravity.z),
            z: accelNorm.x * (-estimatedGravity.y) - accelNorm.y * (-estimatedGravity.x)
        )

        integral = Vector3(
            x: integral.x + integralGain * error.x * constrainedDelta,
            y: integral.y + integralGain * error.y * constrainedDelta,
            z: integral.z + integralGain * error.z * constrainedDelta
        )

        gyro = Vector3(
            x: gyro.x + proportionalGain * error.x + integral.x,
            y: gyro.y + proportionalGain * error.y + integral.y,
            z: gyro.z + proportionalGain * error.z + integral.z
        )

        quaternion.integrate(gyro: gyro, deltaTime: constrainedDelta)
        return quaternion.orientation
    }
}

private struct Quaternion {
    var w: Double
    var x: Double
    var y: Double
    var z: Double

    static let identity = Self(w: 1, x: 0, y: 0, z: 0)

    init(w: Double, x: Double, y: Double, z: Double) {
        self.w = w
        self.x = x
        self.y = y
        self.z = z
    }

    init(roll: Double, pitch: Double, yaw: Double) {
        let cp = cos(pitch * 0.5)
        let sp = sin(pitch * 0.5)
        let cr = cos(roll * 0.5)
        let sr = sin(roll * 0.5)
        let cy = cos(yaw * 0.5)
        let sy = sin(yaw * 0.5)

        self.init(
            w: cr * cp * cy + sr * sp * sy,
            x: sr * cp * cy - cr * sp * sy,
            y: cr * sp * cy + sr * cp * sy,
            z: cr * cp * sy - sr * sp * cy
        )
    }

    var gravityVector: Vector3 {
        Vector3(
            x: 2 * (x * z - w * y),
            y: 2 * (w * x + y * z),
            z: w * w - x * x - y * y + z * z
        )
    }

    var orientation: OrientationEstimate {
        let roll = atan2(2 * (w * x + y * z), 1 - 2 * ((x * x) + (y * y))) * 180 / .pi
        let pitchArgument = max(-1.0, min(1.0, 2 * (w * y - z * x)))
        let pitch = asin(pitchArgument) * 180 / .pi
        let yaw = atan2(2 * (w * z + x * y), 1 - 2 * ((y * y) + (z * z))) * 180 / .pi

        return OrientationEstimate(roll: roll, pitch: pitch, yaw: yaw)
    }

    mutating func integrate(gyro: Vector3, deltaTime: TimeInterval) {
        let halfStep = 0.5 * deltaTime
        let delta = Quaternion(
            w: (-x * gyro.x - y * gyro.y - z * gyro.z) * halfStep,
            x: (w * gyro.x + y * gyro.z - z * gyro.y) * halfStep,
            y: (w * gyro.y - x * gyro.z + z * gyro.x) * halfStep,
            z: (w * gyro.z + x * gyro.y - y * gyro.x) * halfStep
        )

        w += delta.w
        x += delta.x
        y += delta.y
        z += delta.z
        normalize()
    }

    private mutating func normalize() {
        let length = sqrt((w * w) + (x * x) + (y * y) + (z * z))
        guard length > 0 else {
            self = .identity
            return
        }

        w /= length
        x /= length
        y /= length
        z /= length
    }
}

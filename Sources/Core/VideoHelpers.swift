import Foundation

// Pure-logic helpers for the v1.7 video / tracking / motion / align flags.
//
// Vision-framework calls live in Analyzer; everything here is plain Swift so
// it can be exercised by the AugeCore test suite without a runtime image.

// MARK: - --every <duration>

public enum IntervalParser {
    /// Parse strings like `"1s"`, `"500ms"`, `"2.5s"`, `"1m"`, or bare `"3"`
    /// (seconds) into a Double of seconds. Returns nil for malformed input or
    /// non-positive values.
    public static func parse(_ input: String) -> Double? {
        let s = input.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty else { return nil }

        if let raw = Double(s), raw > 0, raw.isFinite {
            return raw
        }

        let (number, unit): (String, String) = {
            if s.hasSuffix("ms") { return (String(s.dropLast(2)), "ms") }
            if s.hasSuffix("s")  { return (String(s.dropLast(1)), "s") }
            if s.hasSuffix("m")  { return (String(s.dropLast(1)), "m") }
            return (s, "")
        }()

        guard !number.isEmpty, let value = Double(number), value > 0, value.isFinite else { return nil }
        switch unit {
        case "ms": return value / 1000.0
        case "s":  return value
        case "m":  return value * 60.0
        default:   return nil
        }
    }
}

// MARK: - --bbox x,y,w,h parsing

public enum BBoxString {
    public static func parse(_ input: String) -> BoundingBox? {
        let parts = input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4 else { return nil }
        guard
            let x = Double(parts[0]),
            let y = Double(parts[1]),
            let w = Double(parts[2]),
            let h = Double(parts[3])
        else { return nil }
        // bbox lives in Vision normalized coords: 0..1 inclusive, bottom-left origin.
        guard (0...1).contains(x), (0...1).contains(y) else { return nil }
        guard w > 0, h > 0, w <= 1, h <= 1 else { return nil }
        guard x + w <= 1.0 + 1e-6, y + h <= 1.0 + 1e-6 else { return nil }
        return BoundingBox(x: x, y: y, width: w, height: h)
    }
}

// MARK: - Optical-flow summary

public struct OpticalFlowSummary: Codable, Sendable {
    public let averageMagnitude: Double
    public let maxMagnitude: Double
    public let dominantAngleRadians: Double
    public let dominantAngleDegrees: Double
    public let sampleCount: Int
    public init(averageMagnitude: Double, maxMagnitude: Double,
                dominantAngleRadians: Double, dominantAngleDegrees: Double,
                sampleCount: Int) {
        self.averageMagnitude = averageMagnitude
        self.maxMagnitude = maxMagnitude
        self.dominantAngleRadians = dominantAngleRadians
        self.dominantAngleDegrees = dominantAngleDegrees
        self.sampleCount = sampleCount
    }

    /// Summarize a stream of (dx, dy) flow vectors into a single direction +
    /// magnitude report. Dominant angle is the angle of the **mean** vector
    /// (not the mean of per-vector angles, which loses sign), so opposing
    /// vectors cancel out — that's the right behaviour for "what is the global
    /// camera/scene motion".
    public static func summarize(vectors: [(Double, Double)]) -> OpticalFlowSummary {
        if vectors.isEmpty {
            return OpticalFlowSummary(
                averageMagnitude: 0, maxMagnitude: 0,
                dominantAngleRadians: 0, dominantAngleDegrees: 0, sampleCount: 0
            )
        }
        var sumMag = 0.0
        var maxMag = 0.0
        var sumDx = 0.0
        var sumDy = 0.0
        for (dx, dy) in vectors {
            let m = (dx * dx + dy * dy).squareRoot()
            sumMag += m
            if m > maxMag { maxMag = m }
            sumDx += dx
            sumDy += dy
        }
        let count = vectors.count
        let avg = sumMag / Double(count)
        let meanX = sumDx / Double(count)
        let meanY = sumDy / Double(count)
        let angleR: Double
        if abs(meanX) < 1e-12 && abs(meanY) < 1e-12 {
            angleR = 0.0
        } else {
            angleR = atan2(meanY, meanX)
        }
        return OpticalFlowSummary(
            averageMagnitude: avg,
            maxMagnitude: maxMag,
            dominantAngleRadians: angleR,
            dominantAngleDegrees: angleR * 180.0 / .pi,
            sampleCount: count
        )
    }
}

// MARK: - Registration transform (--align)

public struct RegistrationTransform: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case translation
        case homography
    }
    public let matrix: [Double]    // 3×3 row-major (always 9 entries)
    public let kind: Kind

    public var isIdentity: Bool {
        guard matrix.count == 9 else { return false }
        let target: [Double] = [1,0,0, 0,1,0, 0,0,1]
        for i in 0..<9 {
            if abs(matrix[i] - target[i]) > 1e-9 { return false }
        }
        return true
    }

    public init(matrix: [Double], kind: Kind) {
        self.matrix = matrix
        self.kind = kind
    }
}

// MARK: - Result types

public struct VideoFrameResult: Codable, Sendable {
    public let time: Double                 // seconds from the start
    public let ocr: [String]
    public let classifications: [ClassificationResult]
    public init(time: Double, ocr: [String], classifications: [ClassificationResult]) {
        self.time = time
        self.ocr = ocr
        self.classifications = classifications
    }
}

public struct VideoResult: Codable, Sendable {
    public let durationSeconds: Double
    public let frameCount: Int
    public let frames: [VideoFrameResult]
    public init(durationSeconds: Double, frames: [VideoFrameResult]) {
        self.durationSeconds = durationSeconds
        self.frameCount = frames.count
        self.frames = frames
    }
}

public struct TrackedFrame: Codable, Sendable {
    public let file: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let confidence: Double
    public init(file: String, x: Double, y: Double, width: Double, height: Double, confidence: Double) {
        self.file = file
        self.x = x; self.y = y; self.width = width; self.height = height
        self.confidence = confidence
    }
}

public struct TrackResult: Codable, Sendable {
    public let initial: BoundingBox
    public let frameCount: Int
    public let frames: [TrackedFrame]
    public init(initial: BoundingBox, frames: [TrackedFrame]) {
        self.initial = initial
        self.frameCount = frames.count
        self.frames = frames
    }
}

public struct MotionResult: Codable, Sendable {
    public let summary: OpticalFlowSummary
    public init(summary: OpticalFlowSummary) {
        self.summary = summary
    }
}

public struct AlignResult: Codable, Sendable {
    public let transform: RegistrationTransform
    public let isIdentity: Bool
    public init(transform: RegistrationTransform, isIdentity: Bool) {
        self.transform = transform
        self.isIdentity = isIdentity
    }
}

public struct Trajectory: Codable, Sendable {
    public let detected: [PointResult]
    public let projected: [PointResult]
    public let equationCoefficients: [Double]
    public init(detected: [PointResult], projected: [PointResult], equationCoefficients: [Double]) {
        self.detected = detected
        self.projected = projected
        self.equationCoefficients = equationCoefficients
    }
}

public struct TrajectoryResult: Codable, Sendable {
    public let count: Int
    public let trajectories: [Trajectory]
    public init(trajectories: [Trajectory]) {
        self.count = trajectories.count
        self.trajectories = trajectories
    }
}

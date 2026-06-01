// VideoHelpersTests.swift
// TDD for v1.7 video + tracking + motion + align parsers and summary logic.
// All Vision-framework integration lives in Analyzer; the pieces tested here
// are pure Swift so they live in AugeCore.

import Foundation
import AugeCore

func runVideoHelpersTests() {

    // MARK: --every duration parsing (IntervalParser)

    test("IntervalParser.parse: bare seconds") {
        try assertEqual(IntervalParser.parse("1s"), 1.0)
        try assertEqual(IntervalParser.parse("2.5s"), 2.5)
    }

    test("IntervalParser.parse: milliseconds") {
        try assertEqual(IntervalParser.parse("500ms"), 0.5)
        try assertEqual(IntervalParser.parse("1000ms"), 1.0)
    }

    test("IntervalParser.parse: minutes") {
        try assertEqual(IntervalParser.parse("1m"), 60.0)
        try assertEqual(IntervalParser.parse("0.5m"), 30.0)
    }

    test("IntervalParser.parse: integer seconds without unit treated as seconds") {
        try assertEqual(IntervalParser.parse("3"), 3.0)
    }

    test("IntervalParser.parse: invalid string returns nil") {
        try assertNil(IntervalParser.parse(""))
        try assertNil(IntervalParser.parse("abc"))
        try assertNil(IntervalParser.parse("1x"))
    }

    test("IntervalParser.parse: rejects zero or negative") {
        try assertNil(IntervalParser.parse("0s"))
        try assertNil(IntervalParser.parse("-1s"))
    }

    test("IntervalParser.parse: rejects non-finite values") {
        try assertNil(IntervalParser.parse("inf"))
        try assertNil(IntervalParser.parse("infinity"))
        try assertNil(IntervalParser.parse("nan"))
        try assertNil(IntervalParser.parse("infs"))
        try assertNil(IntervalParser.parse("infms"))
    }

    // MARK: --bbox parsing

    test("BBoxString.parse: standard four-comma form") {
        let bb = BBoxString.parse("0.1,0.2,0.3,0.4")!
        try assertEqual(bb.x, 0.1)
        try assertEqual(bb.y, 0.2)
        try assertEqual(bb.width, 0.3)
        try assertEqual(bb.height, 0.4)
    }

    test("BBoxString.parse: trims whitespace around values") {
        let bb = BBoxString.parse("  0.1 ,  0.2 ,0.3,0.4 ")!
        try assertEqual(bb.x, 0.1)
        try assertEqual(bb.y, 0.2)
        try assertEqual(bb.width, 0.3)
        try assertEqual(bb.height, 0.4)
    }

    test("BBoxString.parse: rejects fewer than 4 values") {
        try assertNil(BBoxString.parse("0.1,0.2,0.3"))
    }

    test("BBoxString.parse: rejects more than 4 values") {
        try assertNil(BBoxString.parse("0.1,0.2,0.3,0.4,0.5"))
    }

    test("BBoxString.parse: rejects non-numeric") {
        try assertNil(BBoxString.parse("a,b,c,d"))
    }

    test("BBoxString.parse: rejects out-of-range values") {
        try assertNil(BBoxString.parse("1.5,0.2,0.3,0.4"))
        try assertNil(BBoxString.parse("0.1,-0.2,0.3,0.4"))
        try assertNil(BBoxString.parse("0.1,0.2,1.5,0.4"))
    }

    test("BBoxString.parse: rejects zero-area bbox") {
        try assertNil(BBoxString.parse("0.1,0.2,0,0.4"))
        try assertNil(BBoxString.parse("0.1,0.2,0.3,0"))
    }

    // MARK: optical flow summary

    test("OpticalFlowSummary: empty input is zero motion") {
        let s = OpticalFlowSummary.summarize(vectors: [])
        try assertEqual(s.averageMagnitude, 0.0)
        try assertEqual(s.maxMagnitude, 0.0)
        try assertEqual(s.dominantAngleRadians, 0.0)
        try assertEqual(s.sampleCount, 0)
    }

    test("OpticalFlowSummary: pure rightward motion → angle 0, magnitude 1") {
        let s = OpticalFlowSummary.summarize(vectors: [(1, 0), (1, 0), (1, 0)])
        try assertTrue(abs(s.averageMagnitude - 1.0) < 1e-9)
        try assertTrue(abs(s.maxMagnitude - 1.0) < 1e-9)
        try assertTrue(abs(s.dominantAngleRadians) < 1e-9)
        try assertEqual(s.sampleCount, 3)
    }

    test("OpticalFlowSummary: pure upward motion → angle ≈ π/2") {
        let s = OpticalFlowSummary.summarize(vectors: [(0, 1), (0, 1)])
        try assertTrue(abs(s.dominantAngleRadians - .pi / 2) < 1e-9)
    }

    test("OpticalFlowSummary: opposing vectors cancel out, magnitude stays") {
        let s = OpticalFlowSummary.summarize(vectors: [(1, 0), (-1, 0)])
        try assertTrue(abs(s.averageMagnitude - 1.0) < 1e-9)
        // averaged vector is (0, 0); angle is undefined — we default to 0.
        try assertEqual(s.dominantAngleRadians, 0.0)
    }

    test("OpticalFlowSummary: angle in degrees is derived") {
        let s = OpticalFlowSummary.summarize(vectors: [(0, 1)])
        try assertTrue(abs(s.dominantAngleDegrees - 90.0) < 1e-9)
    }

    // MARK: registration transform formatting

    test("RegistrationTransform: identity flagged") {
        let t = RegistrationTransform(matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1], kind: .translation)
        try assertTrue(t.isIdentity)
    }

    test("RegistrationTransform: non-identity") {
        let t = RegistrationTransform(matrix: [1, 0, 5, 0, 1, 10, 0, 0, 1], kind: .translation)
        try assertFalse(t.isIdentity)
    }

    // MARK: Result types

    test("VideoFrameResult includes time + ocr") {
        let f = VideoFrameResult(time: 0.5, ocr: ["hello"], classifications: [])
        try assertEqual(f.time, 0.5)
        try assertEqual(f.ocr.first, "hello")
    }

    test("TrackedFrame: stores per-frame bbox + confidence") {
        let t = TrackedFrame(file: "frame_001.png", x: 0.1, y: 0.2, width: 0.3, height: 0.4, confidence: 0.9)
        try assertEqual(t.file, "frame_001.png")
        try assertEqual(t.confidence, 0.9)
    }

    test("TrackResult round-trips Codable") {
        let r = TrackResult(
            initial: AugeCore.BoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            frames: [
                TrackedFrame(file: "a.png", x: 0.1, y: 0.2, width: 0.3, height: 0.4, confidence: 0.99),
                TrackedFrame(file: "b.png", x: 0.12, y: 0.21, width: 0.3, height: 0.4, confidence: 0.95),
            ]
        )
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(TrackResult.self, from: data)
        try assertEqual(decoded.frames.count, 2)
        try assertEqual(decoded.initial.x, 0.1)
    }

    test("MotionResult round-trips") {
        let r = MotionResult(summary: OpticalFlowSummary(
            averageMagnitude: 0.5, maxMagnitude: 1.0,
            dominantAngleRadians: .pi/4, dominantAngleDegrees: 45,
            sampleCount: 100
        ))
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(MotionResult.self, from: data)
        try assertEqual(decoded.summary.sampleCount, 100)
    }

    test("AlignResult round-trips") {
        let t = RegistrationTransform(matrix: [1, 0, 5, 0, 1, 10, 0, 0, 1], kind: .translation)
        let r = AlignResult(transform: t, isIdentity: false)
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(AlignResult.self, from: data)
        try assertEqual(decoded.transform.matrix.count, 9)
    }

    test("TrajectoryResult counts trajectories") {
        let traj = Trajectory(detected: [
            PointResult(x: 0.1, y: 0.2),
            PointResult(x: 0.15, y: 0.25),
        ], projected: [], equationCoefficients: [0.5, 0.1, 0.0])
        let r = TrajectoryResult(trajectories: [traj])
        try assertEqual(r.count, 1)
    }

    // MARK: formatters

    test("formatMotion mentions direction in degrees") {
        let s = OpticalFlowSummary(averageMagnitude: 1.5, maxMagnitude: 3, dominantAngleRadians: .pi/2, dominantAngleDegrees: 90, sampleCount: 1000)
        let out = ResultFormatter.formatMotion(MotionResult(summary: s))
        try assertTrue(out.contains("90"))
        try assertTrue(out.contains("1.5"))
    }

    test("formatAlign identity case") {
        let t = RegistrationTransform(matrix: [1, 0, 0, 0, 1, 0, 0, 0, 1], kind: .translation)
        let out = ResultFormatter.formatAlign(AlignResult(transform: t, isIdentity: true))
        try assertTrue(out.contains("identity"))
    }

    test("formatAlign non-identity case mentions kind") {
        let t = RegistrationTransform(matrix: [1, 0, 5, 0, 1, 10, 0, 0, 1], kind: .translation)
        let out = ResultFormatter.formatAlign(AlignResult(transform: t, isIdentity: false))
        try assertTrue(out.contains("translation"))
    }

    test("formatTrack mentions frame count") {
        let r = TrackResult(
            initial: AugeCore.BoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            frames: [
                TrackedFrame(file: "a.png", x: 0.1, y: 0.2, width: 0.3, height: 0.4, confidence: 0.9),
                TrackedFrame(file: "b.png", x: 0.12, y: 0.21, width: 0.3, height: 0.4, confidence: 0.85),
                TrackedFrame(file: "c.png", x: 0.14, y: 0.22, width: 0.3, height: 0.4, confidence: 0.80),
            ]
        )
        let s = ResultFormatter.formatTrack(r)
        try assertTrue(s.contains("3 frames"))
    }

    test("formatTrajectories empty case") {
        try assertEqual(ResultFormatter.formatTrajectories(TrajectoryResult(trajectories: [])), "0 trajectories detected")
    }
}

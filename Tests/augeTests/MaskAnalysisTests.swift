// MaskAnalysisTests.swift
// TDD for v1.5 mask post-processing: from a raw mask byte buffer (one byte per pixel,
// 0 = background, non-zero = foreground), compute coverage %, axis-aligned bounding
// box of foreground in Vision-normalized coords (0..1, bottom-left origin), and
// connected-component regions (for splitting a single persons-mask into multiple
// person blobs).

import Foundation
import AugeCore

func runMaskAnalysisTests() {

    // MARK: coverage

    test("coverage: empty mask is 0") {
        let pixels = [UInt8](repeating: 0, count: 16)
        let cov = MaskAnalysis.coverage(width: 4, height: 4, pixels: pixels)
        try assertEqual(cov, 0.0)
    }

    test("coverage: fully filled mask is 1.0") {
        let pixels = [UInt8](repeating: 255, count: 16)
        let cov = MaskAnalysis.coverage(width: 4, height: 4, pixels: pixels)
        try assertEqual(cov, 1.0)
    }

    test("coverage: half-filled mask is 0.5") {
        var pixels = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 { pixels[i] = 255 }
        let cov = MaskAnalysis.coverage(width: 4, height: 4, pixels: pixels)
        try assertEqual(cov, 0.5)
    }

    test("coverage: non-zero counts even when < 255") {
        // threshold defaults to 1 → any non-zero is foreground
        let pixels: [UInt8] = [1, 0, 0, 0, 0, 0, 0, 0]
        let cov = MaskAnalysis.coverage(width: 4, height: 2, pixels: pixels)
        try assertEqual(cov, 0.125)
    }

    test("coverage: respects custom threshold") {
        // pixels are 100 and 200, threshold 150 → only 200 counts
        let pixels: [UInt8] = [100, 200, 100, 200]
        let cov = MaskAnalysis.coverage(width: 2, height: 2, pixels: pixels, threshold: 150)
        try assertEqual(cov, 0.5)
    }

    // MARK: bounding box

    test("boundingBox: empty mask returns nil") {
        let pixels = [UInt8](repeating: 0, count: 16)
        try assertNil(MaskAnalysis.boundingBox(width: 4, height: 4, pixels: pixels))
    }

    test("boundingBox: single pixel at top-left becomes Vision-coord bbox at top-left") {
        // 4x4 mask, only pixel (col=0, row=0) is foreground (i.e. top-left of image).
        // Vision uses bottom-left origin: top-left pixel maps to y near 1.
        var pixels = [UInt8](repeating: 0, count: 16)
        pixels[0] = 255
        let bb = MaskAnalysis.boundingBox(width: 4, height: 4, pixels: pixels)!
        // pixel covers x in [0, 0.25), y in [0.75, 1.0) in Vision coords
        try assertEqual(bb.x, 0.0)
        try assertEqual(bb.width, 0.25)
        try assertEqual(bb.y, 0.75)
        try assertEqual(bb.height, 0.25)
        try assertEqual(bb.pixelCount, 1)
    }

    test("boundingBox: single pixel at bottom-right") {
        // 4x4 mask, only pixel (col=3, row=3) is foreground (bottom-right of image).
        // Vision: bottom-right → x near 1, y near 0.
        var pixels = [UInt8](repeating: 0, count: 16)
        pixels[15] = 255
        let bb = MaskAnalysis.boundingBox(width: 4, height: 4, pixels: pixels)!
        try assertEqual(bb.x, 0.75)
        try assertEqual(bb.width, 0.25)
        try assertEqual(bb.y, 0.0)
        try assertEqual(bb.height, 0.25)
        try assertEqual(bb.pixelCount, 1)
    }

    test("boundingBox: full mask covers full unit rect") {
        let pixels = [UInt8](repeating: 1, count: 16)
        let bb = MaskAnalysis.boundingBox(width: 4, height: 4, pixels: pixels)!
        try assertEqual(bb.x, 0.0)
        try assertEqual(bb.y, 0.0)
        try assertEqual(bb.width, 1.0)
        try assertEqual(bb.height, 1.0)
        try assertEqual(bb.pixelCount, 16)
    }

    test("boundingBox: rectangular blob in the middle") {
        // 6x4 mask (width=6, height=4). Fill cols 2..3 across rows 1..2 (top-origin).
        var pixels = [UInt8](repeating: 0, count: 24)
        for row in 1...2 { for col in 2...3 { pixels[row * 6 + col] = 1 } }
        let bb = MaskAnalysis.boundingBox(width: 6, height: 4, pixels: pixels)!
        // cols 2..3 → x = 2/6, width = 2/6
        try assertTrue(abs(bb.x - 2.0/6.0) < 1e-9)
        try assertTrue(abs(bb.width - 2.0/6.0) < 1e-9)
        // rows 1..2 → y_top = 1, y_bot = 2 → Vision y = (4 - 1 - 2)/4 = 1/4, height = 2/4
        try assertTrue(abs(bb.y - 1.0/4.0) < 1e-9)
        try assertTrue(abs(bb.height - 2.0/4.0) < 1e-9)
        try assertEqual(bb.pixelCount, 4)
    }

    // MARK: connected components

    test("connectedComponents: empty mask yields no components") {
        let pixels = [UInt8](repeating: 0, count: 16)
        let comps = MaskAnalysis.connectedComponents(width: 4, height: 4, pixels: pixels)
        try assertEqual(comps.count, 0)
    }

    test("connectedComponents: one filled square is one component") {
        var pixels = [UInt8](repeating: 0, count: 16)
        for r in 0..<2 { for c in 0..<2 { pixels[r * 4 + c] = 1 } }
        let comps = MaskAnalysis.connectedComponents(width: 4, height: 4, pixels: pixels)
        try assertEqual(comps.count, 1)
        try assertEqual(comps[0].pixelCount, 4)
    }

    test("connectedComponents: two separated blobs yield two components") {
        // 5x1 mask: pixels [1, 0, 0, 1, 1] → blob A=col0 (1px), blob B=cols 3,4 (2px)
        let pixels: [UInt8] = [1, 0, 0, 1, 1]
        let comps = MaskAnalysis.connectedComponents(width: 5, height: 1, pixels: pixels)
        try assertEqual(comps.count, 2)
        // Components are returned sorted by pixelCount descending → bigger first.
        try assertEqual(comps[0].pixelCount, 2)
        try assertEqual(comps[1].pixelCount, 1)
    }

    test("connectedComponents: diagonal pixels are NOT connected (4-connectivity)") {
        // 2x2 mask: [1, 0,
        //           0, 1] → two separate components, not one.
        let pixels: [UInt8] = [1, 0, 0, 1]
        let comps = MaskAnalysis.connectedComponents(width: 2, height: 2, pixels: pixels)
        try assertEqual(comps.count, 2)
    }

    test("connectedComponents: minPixels filters tiny noise") {
        // [1, 0, 0, 1, 1] → blob of 1, blob of 2. With minPixels=2 → only the 2-px blob.
        let pixels: [UInt8] = [1, 0, 0, 1, 1]
        let comps = MaskAnalysis.connectedComponents(width: 5, height: 1, pixels: pixels, minPixels: 2)
        try assertEqual(comps.count, 1)
        try assertEqual(comps[0].pixelCount, 2)
    }

    test("connectedComponents: bbox is per-component") {
        // 5x1: blob A col=0 (x in [0, 0.2)), blob B cols=3..4 (x in [0.6, 1.0))
        let pixels: [UInt8] = [1, 0, 0, 1, 1]
        let comps = MaskAnalysis.connectedComponents(width: 5, height: 1, pixels: pixels)
        // sorted by pixelCount desc → B then A
        try assertTrue(abs(comps[0].x - 0.6) < 1e-9)
        try assertTrue(abs(comps[0].width - 0.4) < 1e-9)
        try assertTrue(abs(comps[1].x - 0.0) < 1e-9)
        try assertTrue(abs(comps[1].width - 0.2) < 1e-9)
    }

    test("connectedComponents: handles a 100x100 mask without stack overflow") {
        // Iterative flood-fill must NOT use recursion. Spot-check a moderately
        // big fully-filled mask: one giant component of 10_000 pixels.
        let pixels = [UInt8](repeating: 1, count: 10_000)
        let comps = MaskAnalysis.connectedComponents(width: 100, height: 100, pixels: pixels)
        try assertEqual(comps.count, 1)
        try assertEqual(comps[0].pixelCount, 10_000)
    }

    test("connectedComponents: area is foreground fraction") {
        // 4x4: one 4-px blob at top-left. Area = 4/16 = 0.25.
        var pixels = [UInt8](repeating: 0, count: 16)
        for r in 0..<2 { for c in 0..<2 { pixels[r * 4 + c] = 1 } }
        let comps = MaskAnalysis.connectedComponents(width: 4, height: 4, pixels: pixels)
        try assertTrue(abs(comps[0].area - 0.25) < 1e-9)
    }

    // MARK: Subject + PersonsMask result types

    test("SubjectInstance round-trips Codable") {
        let s = SubjectInstance(index: 1, area: 0.25, x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(SubjectInstance.self, from: data)
        try assertEqual(decoded.index, 1)
        try assertEqual(decoded.area, 0.25)
        try assertEqual(decoded.x, 0.1)
    }

    test("SubjectResult counts instances") {
        let r = SubjectResult(coverage: 0.5, instances: [
            SubjectInstance(index: 1, area: 0.3, x: 0, y: 0, width: 0.5, height: 0.5),
            SubjectInstance(index: 2, area: 0.2, x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ])
        try assertEqual(r.count, 2)
    }

    test("PersonsMaskResult counts blobs") {
        let r = PersonsMaskResult(coverage: 0.3, instances: [
            SubjectInstance(index: 1, area: 0.3, x: 0, y: 0, width: 0.5, height: 0.5),
        ])
        try assertEqual(r.count, 1)
    }

    test("formatSubject empty → no subjects detected") {
        let r = SubjectResult(coverage: 0, instances: [])
        try assertEqual(ResultFormatter.formatSubject(r), "0 subjects detected")
    }

    test("formatSubject mentions count and coverage") {
        let r = SubjectResult(coverage: 0.42, instances: [
            SubjectInstance(index: 1, area: 0.42, x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        ])
        let s = ResultFormatter.formatSubject(r)
        try assertTrue(s.contains("1 subject"))
        try assertTrue(s.contains("42"))  // 42% coverage
    }

    test("formatPersonsMask empty → no person pixels") {
        let r = PersonsMaskResult(coverage: 0, instances: [])
        try assertEqual(ResultFormatter.formatPersonsMask(r), "no person pixels detected")
    }

    test("formatPersonsMask shows coverage and region count") {
        let r = PersonsMaskResult(coverage: 0.35, instances: [
            SubjectInstance(index: 1, area: 0.20, x: 0, y: 0, width: 0.5, height: 0.5),
            SubjectInstance(index: 2, area: 0.15, x: 0.5, y: 0, width: 0.5, height: 0.5),
        ])
        let s = ResultFormatter.formatPersonsMask(r)
        try assertTrue(s.contains("35"))   // 35% coverage
        try assertTrue(s.contains("2 region"))
    }

    test("markdownSubject empty case") {
        let r = SubjectResult(coverage: 0, instances: [])
        try assertEqual(ResultFormatter.markdownSubject(r), "**0 subjects detected**")
    }

    test("markdownSubject lists each instance") {
        let r = SubjectResult(coverage: 0.5, instances: [
            SubjectInstance(index: 1, area: 0.3, x: 0.0, y: 0.0, width: 0.5, height: 0.5),
            SubjectInstance(index: 2, area: 0.2, x: 0.5, y: 0.5, width: 0.5, height: 0.5),
        ])
        let md = ResultFormatter.markdownSubject(r)
        try assertTrue(md.contains("subject 1"))
        try assertTrue(md.contains("subject 2"))
    }

    test("markdownPersonsMask shows region details") {
        let r = PersonsMaskResult(coverage: 0.2, instances: [
            SubjectInstance(index: 1, area: 0.2, x: 0.1, y: 0.1, width: 0.3, height: 0.3),
        ])
        let md = ResultFormatter.markdownPersonsMask(r)
        try assertTrue(md.contains("region 1"))
        try assertTrue(md.contains("20%"))
    }
}

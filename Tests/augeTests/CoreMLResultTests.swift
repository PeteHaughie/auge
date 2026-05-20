// CoreMLResultTests.swift
// TDD for v1.6 --model: uniform JSON envelope that lets VNClassificationObservation,
// VNRecognizedObjectObservation (detection w/ bbox), and VNCoreMLFeatureValueObservation
// all round-trip through one Codable schema.

import Foundation
import AugeCore

func runCoreMLResultTests() {

    // MARK: shape

    test("CoreMLResult: empty result encodes type=classification") {
        let r = CoreMLResult(
            modelName: "test.mlmodelc",
            observationType: .classification,
            classifications: [],
            detections: [],
            features: []
        )
        let data = try JSONEncoder().encode(r)
        let s = String(data: data, encoding: .utf8) ?? ""
        try assertTrue(s.contains("\"classification\""))
    }

    test("CoreMLClassification round-trips") {
        let c = CoreMLClassification(label: "cat", confidence: 0.87)
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(CoreMLClassification.self, from: data)
        try assertEqual(decoded.label, "cat")
        try assertEqual(decoded.confidence, 0.87)
    }

    test("CoreMLDetection round-trips with bbox") {
        let d = CoreMLDetection(label: "person", confidence: 0.9, x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let data = try JSONEncoder().encode(d)
        let decoded = try JSONDecoder().decode(CoreMLDetection.self, from: data)
        try assertEqual(decoded.label, "person")
        try assertEqual(decoded.width, 0.3)
    }

    test("CoreMLFeature truncates the sample to <= sampleLimit and reports full count") {
        let big = (0..<1000).map { Double($0) }
        let f = CoreMLFeature.fromVector(name: "logits", shape: [1, 1000], elementType: "float", values: big)
        try assertEqual(f.elementCount, 1000)
        try assertTrue(f.sample.count <= 16)
        try assertEqual(f.sample.first, 0.0)
    }

    test("CoreMLFeature passes small vectors through unchanged") {
        let small = [1.0, 2.0, 3.0]
        let f = CoreMLFeature.fromVector(name: "x", shape: [3], elementType: "double", values: small)
        try assertEqual(f.sample.count, 3)
        try assertEqual(f.sample[1], 2.0)
        try assertEqual(f.elementCount, 3)
    }

    // MARK: formatters

    test("formatCoreML(classification) shows top labels") {
        let r = CoreMLResult(
            modelName: "ImageNetV3.mlmodelc",
            observationType: .classification,
            classifications: [
                CoreMLClassification(label: "tabby cat", confidence: 0.72),
                CoreMLClassification(label: "tiger cat", confidence: 0.12),
            ],
            detections: [], features: []
        )
        let s = ResultFormatter.formatCoreML(r)
        try assertTrue(s.contains("tabby cat"))
        try assertTrue(s.contains("72%"))
        try assertTrue(s.contains("ImageNetV3"))
    }

    test("formatCoreML(detection) shows bboxes") {
        let r = CoreMLResult(
            modelName: "yolo.mlmodelc",
            observationType: .detection,
            classifications: [],
            detections: [
                CoreMLDetection(label: "car", confidence: 0.95, x: 0.1, y: 0.2, width: 0.3, height: 0.4),
                CoreMLDetection(label: "person", confidence: 0.81, x: 0.5, y: 0.5, width: 0.2, height: 0.4),
            ],
            features: []
        )
        let s = ResultFormatter.formatCoreML(r)
        try assertTrue(s.contains("car"))
        try assertTrue(s.contains("person"))
        try assertTrue(s.contains("95%"))
        try assertTrue(s.contains("bbox"))
    }

    test("formatCoreML(feature) shows shape and sample") {
        let r = CoreMLResult(
            modelName: "embed.mlmodelc",
            observationType: .feature,
            classifications: [], detections: [],
            features: [
                CoreMLFeature.fromVector(name: "embedding", shape: [1, 4], elementType: "float", values: [1.0, 2.0, 3.0, 4.0])
            ]
        )
        let s = ResultFormatter.formatCoreML(r)
        try assertTrue(s.contains("embedding"))
        try assertTrue(s.contains("shape=[1, 4]"))
    }

    test("formatCoreML empty result") {
        let r = CoreMLResult(
            modelName: "any.mlmodelc",
            observationType: .classification,
            classifications: [], detections: [], features: []
        )
        let s = ResultFormatter.formatCoreML(r)
        try assertTrue(s.contains("no observations"))
    }

    test("markdownCoreML classification yields bullet list") {
        let r = CoreMLResult(
            modelName: "m.mlmodelc",
            observationType: .classification,
            classifications: [
                CoreMLClassification(label: "dog", confidence: 0.5),
            ],
            detections: [], features: []
        )
        let md = ResultFormatter.markdownCoreML(r)
        try assertTrue(md.contains("**dog**"))
        try assertTrue(md.contains("50%"))
    }

    test("markdownCoreML detection mentions bboxes") {
        let r = CoreMLResult(
            modelName: "yolo.mlmodelc",
            observationType: .detection,
            classifications: [],
            detections: [
                CoreMLDetection(label: "car", confidence: 0.9, x: 0.0, y: 0.0, width: 0.5, height: 0.5)
            ],
            features: []
        )
        let md = ResultFormatter.markdownCoreML(r)
        try assertTrue(md.contains("car"))
        try assertTrue(md.contains("0.000"))
    }

    test("ModelPath.expandsToCompiledModel returns same path when already .mlmodelc") {
        let kind = ModelPath.classify("/path/to/m.mlmodelc")
        try assertEqual(kind, ModelPath.Kind.compiled)
    }

    test("ModelPath classifies .mlmodel as source") {
        try assertEqual(ModelPath.classify("/path/to/m.mlmodel"), ModelPath.Kind.source)
    }

    test("ModelPath classifies anything else as invalid") {
        try assertEqual(ModelPath.classify("/path/to/m.txt"), ModelPath.Kind.invalid)
        try assertEqual(ModelPath.classify("/no/ext"), ModelPath.Kind.invalid)
    }
}

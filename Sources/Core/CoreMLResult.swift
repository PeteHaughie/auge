import Foundation

// Uniform output schema for `--model custom.mlmodel`.
//
// VNCoreMLRequest produces three observation kinds depending on the model:
//   - VNClassificationObservation     → label + confidence
//   - VNRecognizedObjectObservation   → label + confidence + bounding box
//   - VNCoreMLFeatureValueObservation → raw multi-array / dictionary / image
//
// Rather than emit a different JSON shape per observation kind, we collapse
// all three into one envelope and tag it with `observationType`. Downstream
// consumers can branch on that tag and read whichever array is non-empty.

public enum CoreMLObservationType: String, Codable, Sendable {
    case classification
    case detection
    case feature
}

public struct CoreMLClassification: Codable, Sendable {
    public let label: String
    public let confidence: Double
    public init(label: String, confidence: Double) {
        self.label = label
        self.confidence = confidence
    }
}

public struct CoreMLDetection: Codable, Sendable {
    public let label: String
    public let confidence: Double
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(label: String, confidence: Double,
                x: Double, y: Double, width: Double, height: Double) {
        self.label = label
        self.confidence = confidence
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public struct CoreMLFeature: Codable, Sendable {
    public let name: String
    public let shape: [Int]
    public let elementType: String
    public let sample: [Double]
    public let elementCount: Int

    public static let sampleLimit = 16

    public init(name: String, shape: [Int], elementType: String, sample: [Double], elementCount: Int) {
        self.name = name
        self.shape = shape
        self.elementType = elementType
        self.sample = sample
        self.elementCount = elementCount
    }

    public static func fromVector(name: String, shape: [Int], elementType: String, values: [Double]) -> CoreMLFeature {
        let sampled = Array(values.prefix(sampleLimit))
        return CoreMLFeature(
            name: name, shape: shape, elementType: elementType,
            sample: sampled, elementCount: values.count
        )
    }
}

public struct CoreMLResult: Codable, Sendable {
    public let modelName: String
    public let observationType: CoreMLObservationType
    public let classifications: [CoreMLClassification]
    public let detections: [CoreMLDetection]
    public let features: [CoreMLFeature]

    public init(modelName: String,
                observationType: CoreMLObservationType,
                classifications: [CoreMLClassification],
                detections: [CoreMLDetection],
                features: [CoreMLFeature]) {
        self.modelName = modelName
        self.observationType = observationType
        self.classifications = classifications
        self.detections = detections
        self.features = features
    }

    enum CodingKeys: String, CodingKey {
        case modelName        = "model"
        case observationType  = "observation_type"
        case classifications
        case detections
        case features
    }
}

// MARK: - Path classification

public enum ModelPath {
    public enum Kind: Equatable {
        case source       // .mlmodel — must be compiled
        case compiled     // .mlmodelc — load directly
        case invalid      // not a model file
    }

    public static func classify(_ path: String) -> Kind {
        let lowered = path.lowercased()
        if lowered.hasSuffix(".mlmodelc") { return .compiled }
        if lowered.hasSuffix(".mlmodel")  { return .source }
        return .invalid
    }
}

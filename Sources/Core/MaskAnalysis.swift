import Foundation

// Post-processing for binary masks emitted by Vision (CVPixelBuffer rendered to a
// width×height byte buffer, top-origin). All bounding boxes returned use Vision's
// normalized 0..1 bottom-left-origin convention so they round-trip cleanly with
// the rest of the JSON envelope.

public struct MaskBoundingBox: Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let pixelCount: Int
    public init(x: Double, y: Double, width: Double, height: Double, pixelCount: Int) {
        self.x = x; self.y = y; self.width = width; self.height = height
        self.pixelCount = pixelCount
    }
}

public struct MaskComponent: Sendable {
    public let pixelCount: Int
    public let area: Double
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(pixelCount: Int, area: Double,
                x: Double, y: Double, width: Double, height: Double) {
        self.pixelCount = pixelCount
        self.area = area
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public enum MaskAnalysis {
    public static func coverage(width: Int, height: Int, pixels: [UInt8], threshold: UInt8 = 1) -> Double {
        guard width > 0, height > 0, pixels.count == width * height else { return 0 }
        let total = width * height
        var fg = 0
        for p in pixels where p >= threshold { fg += 1 }
        return Double(fg) / Double(total)
    }

    public static func boundingBox(width: Int, height: Int, pixels: [UInt8], threshold: UInt8 = 1) -> MaskBoundingBox? {
        guard width > 0, height > 0, pixels.count == width * height else { return nil }
        var minCol = Int.max, maxCol = Int.min
        var minRow = Int.max, maxRow = Int.min
        var count = 0
        for row in 0..<height {
            let base = row * width
            for col in 0..<width {
                if pixels[base + col] >= threshold {
                    count += 1
                    if col < minCol { minCol = col }
                    if col > maxCol { maxCol = col }
                    if row < minRow { minRow = row }
                    if row > maxRow { maxRow = row }
                }
            }
        }
        if count == 0 { return nil }
        let w = Double(width), h = Double(height)
        let x = Double(minCol) / w
        let bw = Double(maxCol - minCol + 1) / w
        // Vision uses bottom-origin: flip the row range.
        let y = Double(height - 1 - maxRow) / h
        let bh = Double(maxRow - minRow + 1) / h
        return MaskBoundingBox(x: x, y: y, width: bw, height: bh, pixelCount: count)
    }

    /// Iterative 4-connectivity flood-fill. Returns components sorted by pixelCount descending.
    public static func connectedComponents(
        width: Int,
        height: Int,
        pixels: [UInt8],
        threshold: UInt8 = 1,
        minPixels: Int = 1
    ) -> [MaskComponent] {
        guard width > 0, height > 0, pixels.count == width * height else { return [] }
        let total = width * height
        var visited = [Bool](repeating: false, count: total)
        var result: [MaskComponent] = []
        var queue = [Int]()
        queue.reserveCapacity(min(total, 4096))

        for startIdx in 0..<total {
            if visited[startIdx] { continue }
            if pixels[startIdx] < threshold {
                visited[startIdx] = true
                continue
            }
            // BFS.
            queue.removeAll(keepingCapacity: true)
            queue.append(startIdx)
            visited[startIdx] = true
            var head = 0
            var minCol = Int.max, maxCol = Int.min
            var minRow = Int.max, maxRow = Int.min
            var count = 0
            while head < queue.count {
                let idx = queue[head]
                head += 1
                let row = idx / width
                let col = idx % width
                count += 1
                if col < minCol { minCol = col }
                if col > maxCol { maxCol = col }
                if row < minRow { minRow = row }
                if row > maxRow { maxRow = row }
                // 4-neighbours
                if col > 0 {
                    let n = idx - 1
                    if !visited[n] && pixels[n] >= threshold {
                        visited[n] = true; queue.append(n)
                    } else { visited[n] = true }
                }
                if col + 1 < width {
                    let n = idx + 1
                    if !visited[n] && pixels[n] >= threshold {
                        visited[n] = true; queue.append(n)
                    } else if pixels[n] < threshold {
                        visited[n] = true
                    }
                }
                if row > 0 {
                    let n = idx - width
                    if !visited[n] && pixels[n] >= threshold {
                        visited[n] = true; queue.append(n)
                    } else if pixels[n] < threshold {
                        visited[n] = true
                    }
                }
                if row + 1 < height {
                    let n = idx + width
                    if !visited[n] && pixels[n] >= threshold {
                        visited[n] = true; queue.append(n)
                    } else if pixels[n] < threshold {
                        visited[n] = true
                    }
                }
            }
            if count < minPixels { continue }
            let wF = Double(width), hF = Double(height)
            let bx = Double(minCol) / wF
            let bw = Double(maxCol - minCol + 1) / wF
            let by = Double(height - 1 - maxRow) / hF
            let bh = Double(maxRow - minRow + 1) / hF
            let area = Double(count) / Double(total)
            result.append(MaskComponent(
                pixelCount: count, area: area,
                x: bx, y: by, width: bw, height: bh
            ))
        }
        result.sort { $0.pixelCount > $1.pixelCount }
        return result
    }
}

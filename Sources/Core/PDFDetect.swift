import Foundation

/// Pure-logic PDF detection via magic bytes.
public enum PDFDetect {
    /// PDF magic header: `%PDF-` (first 5 bytes of every PDF file).
    public static let magic: [UInt8] = [0x25, 0x50, 0x44, 0x46, 0x2D]

    /// Returns true if the byte buffer starts with the PDF magic header.
    public static func isPDF(_ data: Data) -> Bool {
        guard data.count >= magic.count else { return false }
        return data.prefix(magic.count).elementsEqual(magic)
    }

    /// Returns true if the file at the given path is a PDF (by magic bytes, not extension).
    /// Scans the first 1 KB so PDFs with a few leading bytes before `%PDF-` are still
    /// recognized (the spec tolerates this), keeping the cheap offset-0 check as a fast path.
    public static func isPDF(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1024) else { return false }
        if isPDF(data) { return true }
        return data.range(of: Data(magic)) != nil
    }
}

import Foundation

public enum ImageSource {
    private static let supportedExtensions: Set<String> = [
        "png", "jpg", "jpeg", "tiff", "tif", "bmp", "gif", "heic", "heif", "pdf"
    ]

    /// Container formats handled via AVFoundation frame sampling (--video, per-frame --ocr/--classify).
    /// Single source of truth shared with the Analyzer's video dispatch.
    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv"]

    public static func isSupportedExtension(_ ext: String) -> Bool {
        supportedExtensions.contains(ext.lowercased())
    }

    public static func isVideoExtension(_ ext: String) -> Bool {
        videoExtensions.contains(ext.lowercased())
    }

    public static func extensionFrom(path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? nil : ext
    }

    public static func validatePath(_ path: String, allowVideo: Bool = false) -> Result<URL, AugeError> {
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
            return .failure(.fileNotFound(path))
        }
        guard let ext = extensionFrom(path: path),
              isSupportedExtension(ext) || (allowVideo && isVideoExtension(ext)) else {
            return .failure(.unsupportedFormat(extensionFrom(path: path) ?? "unknown"))
        }
        return .success(url)
    }
}

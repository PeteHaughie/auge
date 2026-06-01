// ============================================================================
// JSON.swift — JSON encoding helpers
// Part of auge — Apple Vision from the command line
// ============================================================================

import Foundation
import AugeCore

/// Encode a value to a JSON string.
/// - Parameters:
///   - value: Any Encodable value
///   - pretty: If true, use pretty-printed formatting (default).
///             If false, use compact single-line format.
/// - Returns: JSON string, or "{}" if encoding fails.
func jsonString(_ value: some Encodable, pretty: Bool = true) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.keyEncodingStrategy = .convertToSnakeCase
    if pretty { encoder.outputFormatting.insert(.prettyPrinted) }
    do {
        let data = try encoder.encode(value)
        guard let str = String(data: data, encoding: .utf8) else {
            throw AugeError.unknown("could not decode JSON output as UTF-8")
        }
        return str
    } catch {
        // Fail loud rather than emitting a fake-success "{}" — honesty over silence.
        printError("failed to encode JSON output: \(error.localizedDescription)")
        exit(exitRuntimeError)
    }
}

import Foundation
import os

// One shared logger so every Print-via-Xcode line is prefixed and filterable.
// In Xcode's console, filter on "OHB" to see app diagnostics only.
//
// Usage:
//   Log.ui("home appeared")
//   Log.net("GET /sessions → 200 in 320ms")
//   Log.warn("upload failed: \(error)")
enum Log {
    private static let logger = Logger(subsystem: "com.openhouseboss.app", category: "OHB")

    static func ui(_ msg: String, file: String = #fileID, line: Int = #line) {
        logger.log("[UI] \(msg, privacy: .public) (\(file, privacy: .public):\(line, privacy: .public))")
    }

    static func net(_ msg: String, file: String = #fileID, line: Int = #line) {
        logger.log("[NET] \(msg, privacy: .public) (\(file, privacy: .public):\(line, privacy: .public))")
    }

    static func warn(_ msg: String, file: String = #fileID, line: Int = #line) {
        logger.warning("[WARN] \(msg, privacy: .public) (\(file, privacy: .public):\(line, privacy: .public))")
    }
}

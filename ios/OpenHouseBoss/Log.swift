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

    static func ui(_ msg: @autoclosure () -> String,
                   file: String = #fileID, line: Int = #line) {
        let location = "\(file):\(line)"
        logger.log("[UI] \(msg()) (\(location))")
    }

    static func net(_ msg: @autoclosure () -> String,
                    file: String = #fileID, line: Int = #line) {
        let location = "\(file):\(line)"
        logger.log("[NET] \(msg()) (\(location))")
    }

    static func warn(_ msg: @autoclosure () -> String,
                     file: String = #fileID, line: Int = #line) {
        let location = "\(file):\(line)"
        logger.warning("[WARN] \(msg()) (\(location))")
    }
}

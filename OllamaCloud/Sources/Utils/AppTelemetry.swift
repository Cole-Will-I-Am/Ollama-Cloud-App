import Foundation
import os.log

enum AppTelemetry {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.colecantcode.ollamacloud",
        category: "telemetry"
    )

    static func track(_ event: String, metadata: [String: String] = [:]) {
        let suffix = metadata
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        if suffix.isEmpty {
            logger.log("\(event, privacy: .public)")
        } else {
            logger.log("\(event, privacy: .public) \(suffix, privacy: .public)")
        }
    }
}

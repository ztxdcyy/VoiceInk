import Foundation

final class PermissionDebugLogger {
    static let shared = PermissionDebugLogger()

    private let queue = DispatchQueue(label: "com.voiceink.permission.logger")
    private let logFileURL: URL

    private init() {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Voiceink", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logFileURL = logsDir.appendingPathComponent("permission.log")
    }

    func log(_ message: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(message)"
        print("[Voiceink][Permission] \(line)")

        queue.async { [logFileURL] in
            guard let data = (line + "\n").data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }

    var path: String { logFileURL.path }
}

import Foundation
import os

/// Stamp diagnostics. File is in the sandbox container so a later session can
/// `cat` it without Console.app:
/// `~/Library/Containers/com.epsalmond.fujikage.quicklook/Data/Library/Logs/stamp.log`
enum StampLog {
    static let logger = Logger(subsystem: "com.epsalmond.fujikage.quicklook", category: "stamp")

    static var fileURL: URL {
        let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = lib.appendingPathComponent("Logs", isDirectory: true)
        return dir.appendingPathComponent("stamp.log")
    }

    static func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        append("notice", message)
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        append("error", message)
    }

    private static let lock = NSLock()

    private static func append(_ level: String, _ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue,
           size > 512_000
        {
            try? FileManager.default.removeItem(at: url)
        }
        if FileManager.default.fileExists(atPath: url.path) {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

extension Error {
    var stampDetail: String {
        let ns = self as NSError
        var parts = ["\(ns.domain)#\(ns.code)", ns.localizedDescription]
        if let path = ns.userInfo[NSFilePathErrorKey] as? String {
            parts.append(path)
        }
        if let under = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            parts.append("underlying \(under.domain)#\(under.code) \(under.localizedDescription)")
        }
        return parts.joined(separator: " | ")
    }
}

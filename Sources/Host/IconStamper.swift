import AppKit
import Darwin
import Foundation

enum IconStampError: Error, LocalizedError {
    case setIconFailed(URL)
    case markerFailed(URL)
    case appleDouble(URL)
    case denied(String)
    case noRAF

    var errorDescription: String? {
        switch self {
        case .setIconFailed(let url):
            return "Finder refused to set an icon on \(url.lastPathComponent)."
        case .markerFailed(let url):
            return "Could not write the FujikageQL stamp marker on \(url.lastPathComponent)."
        case .appleDouble(let url):
            return "Stamping \(url.lastPathComponent) created a ._\(url.lastPathComponent) sidecar. RAF bytes were not changed."
        case .denied(let reason):
            return reason
        case .noRAF:
            return "No .raf files in this folder."
        }
    }
}

struct StampReport: Sendable {
    var stamped = 0
    var alreadyStamped = 0
    var cleared = 0
    var skipped = 0
    var notOurs = 0
    var failed = 0
    var appleDouble = 0
    var cancelled = false
    var failedFiles: [String] = []
    var notes: [String] = []

    var summary: String {
        var parts: [String] = []
        if stamped > 0 { parts.append("stamped \(stamped)") }
        if alreadyStamped > 0 { parts.append("already stamped \(alreadyStamped)") }
        if cleared > 0 { parts.append("cleared \(cleared)") }
        if skipped > 0 { parts.append("skipped \(skipped)") }
        if notOurs > 0 { parts.append("not ours \(notOurs)") }
        if failed > 0 {
            let shown = failedFiles.prefix(3).joined(separator: ", ")
            if shown.isEmpty {
                parts.append("failed \(failed)")
            } else if failedFiles.count > 3 {
                parts.append("failed \(failed) (\(shown), …)")
            } else {
                parts.append("failed \(failed) (\(shown))")
            }
        }
        if appleDouble > 0 { parts.append("._ sidecars \(appleDouble)") }
        if cancelled { parts.append("stopped") }
        if parts.isEmpty { return "Nothing to do." }
        return parts.joined(separator: ", ") + "."
    }
}

struct StampProgress: Equatable, Sendable {
    var listing: Bool
    var current: Int
    var total: Int
    var filename: String

    static let listing = StampProgress(listing: true, current: 0, total: 0, filename: "")

    var label: String {
        if listing { return "Listing RAF files…" }
        let width = max(3, String(total).count)
        let numbers = String(format: "Processing %0\(width)d/%d", current, total)
        if filename.isEmpty { return numbers }
        return numbers + "  " + filename
    }
}

/// File-system probes the stamper needs to observe side effects of
/// `NSWorkspace.setIcon`. Tests substitute these to simulate a volume that
/// answers a stamp with a `._` AppleDouble file.
struct StampIO: Sendable {
    var sidecarExists: @Sendable (URL) -> Bool
    var removeIcon: @Sendable (URL) -> Bool = { url in
        NSWorkspace.shared.setIcon(nil, forFile: url.path, options: [])
    }

    static let live = StampIO(sidecarExists: { url in
        FileManager.default.fileExists(atPath: IconStampPolicy.appleDoubleSidecar(for: url).path)
    })
}

enum IconStamper {
    static let queue = DispatchQueue(
        label: "com.epsalmond.fujikage.quicklook.stamp",
        qos: .userInitiated
    )

    static func rafFiles(
        in root: URL,
        denylist: [String],
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            if isCancelled() { break }
            guard IconStampPolicy.isRAF(url) else { continue }
            if IconStampPolicy.isDenied(url, prefixes: denylist) {
                continue
            }
            files.append(url)
        }
        return files
    }

    /// Stamps one file to learn whether the volume answers with a `._`
    /// sidecar. A file that already carries an icon proves nothing about the
    /// volume, so it is skipped. On a sidecar the stamp is rolled back.
    static func probe(file url: URL, io: StampIO = .live) throws -> StampDisposition {
        if io.sidecarExists(url) {
            return .deny(IconStampError.appleDouble(url).localizedDescription)
        }
        if IconStampPolicy.hasCustomIcon(at: url) {
            return .allow
        }
        let created = try applyStamp(to: url, io: io)
        if created {
            guard removeStamp(from: url, io: io) else {
                throw IconStampError.denied(
                    "Could not remove the icon on \(url.lastPathComponent) after the volume created a ._ sidecar. Clear can retry."
                )
            }
            try? FileManager.default.removeItem(at: IconStampPolicy.appleDoubleSidecar(for: url))
            return .deny(IconStampError.appleDouble(url).localizedDescription)
        }
        return .allow
    }

    static func probeVolume(_ files: [URL], io: StampIO = .live) throws {
        var lastOpenError: Error?
        for file in files.prefix(8) {
            do {
                if case .deny(let reason) = try probe(file: file, io: io) {
                    throw IconStampError.denied(reason)
                }
                return
            } catch let err as IconStampError {
                if case .denied = err { throw err }
                lastOpenError = err
                StampLog.error("probe \(file.lastPathComponent) \(err.stampDetail)")
            } catch {
                lastOpenError = error
                StampLog.error("probe \(file.lastPathComponent) \(error.stampDetail)")
            }
        }
        if let lastOpenError {
            StampLog.error("probe skipped, continuing \(lastOpenError.stampDetail)")
        }
    }

    static func stamp(
        files: [URL],
        denylist: [String],
        allowSidecars: Bool,
        io: StampIO = .live,
        progress: (@Sendable (Int, Int, String) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) -> StampReport {
        var report = StampReport()
        let total = files.count
        for (index, url) in files.enumerated() {
            if isCancelled?() == true {
                report.cancelled = true
                break
            }
            progress?(index + 1, total, url.lastPathComponent)
            if IconStampPolicy.isDenied(url, prefixes: denylist) {
                report.skipped += 1
                continue
            }
            if IconStampPolicy.hasCustomIcon(at: url) {
                report.alreadyStamped += 1
                continue
            }
            do {
                let created = try applyStamp(to: url, io: io)
                if created {
                    report.appleDouble += 1
                    if !allowSidecars {
                        if removeStamp(from: url, io: io) {
                            try? FileManager.default.removeItem(at: IconStampPolicy.appleDoubleSidecar(for: url))
                        } else {
                            report.notes.append("Could not remove the icon on \(url.lastPathComponent). Clear can retry.")
                        }
                        report.failed += 1
                        report.failedFiles.append(url.lastPathComponent)
                        report.notes.append("Stopped at \(url.lastPathComponent): ._ sidecar. Enable sidecars for this folder to keep going.")
                        break
                    }
                }
                report.stamped += 1
            } catch {
                report.failed += 1
                report.failedFiles.append(url.lastPathComponent)
                report.notes.append("\(url.lastPathComponent): \(error.localizedDescription)")
                StampLog.error("stamp \(url.lastPathComponent) \(error.stampDetail)")
            }
        }
        return report
    }

    static func clear(
        files: [URL],
        denylist: [String],
        io: StampIO = .live,
        progress: (@Sendable (Int, Int, String) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) -> StampReport {
        var report = StampReport()
        let total = files.count
        for (index, url) in files.enumerated() {
            if isCancelled?() == true {
                report.cancelled = true
                break
            }
            progress?(index + 1, total, url.lastPathComponent)
            if IconStampPolicy.isDenied(url, prefixes: denylist) {
                report.skipped += 1
                continue
            }
            // Only undo what we did. A custom icon without our marker came
            // from somewhere else (Finder, another tool) and stays.
            guard let marker = IconStampPolicy.stampMarker(at: url) else {
                if IconStampPolicy.hasCustomIcon(at: url) { report.notOurs += 1 }
                continue
            }
            if removeStamp(from: url, io: io) {
                report.cleared += 1
                if marker == .iconAndSidecar {
                    let sidecar = IconStampPolicy.appleDoubleSidecar(for: url)
                    if FileManager.default.fileExists(atPath: sidecar.path) {
                        try? FileManager.default.removeItem(at: sidecar)
                    }
                }
            } else {
                report.failed += 1
                report.failedFiles.append(url.lastPathComponent)
            }
        }
        return report
    }

    /// Sets the icon and the provenance marker. Returns whether the volume
    /// answered by creating a `._` sidecar; the marker records that so Clear
    /// knows the sidecar is ours to delete.
    private static func applyStamp(to url: URL, io: StampIO) throws -> Bool {
        let jpeg = try RAFEmbeddedJPEG.jpegData(from: url)
        guard let cg = RAFEmbeddedJPEG.thumbnailImage(fromJPEG: jpeg, maxPixelSize: 1024) else {
            throw RAFEmbeddedJPEGError.notJPEG
        }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        let existed = io.sidecarExists(url)
        return try withOwnerWrite(url) {
            guard NSWorkspace.shared.setIcon(image, forFile: url.path, options: []) else {
                throw IconStampError.setIconFailed(url)
            }
            let created = io.sidecarExists(url) && !existed
            guard IconStampPolicy.setStampMarker(created ? .iconAndSidecar : .icon, at: url) else {
                _ = NSWorkspace.shared.setIcon(nil, forFile: url.path, options: [])
                throw IconStampError.markerFailed(url)
            }
            return created
        }
    }

    /// Removes the icon and the marker. Does not touch sidecars.
    @discardableResult
    private static func removeStamp(from url: URL, io: StampIO) -> Bool {
        withOwnerWrite(url) {
            guard io.removeIcon(url) else { return false }
            IconStampPolicy.removeStampMarker(at: url)
            return true
        }
    }

    /// AirDrop (sharingd) lands files as 0444. setIcon writes FinderInfo +
    /// ResourceFork xattrs, which need owner-write. Restore the original mode
    /// so the data-fork policy stays untouched.
    static func withOwnerWrite<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
        try url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return try body() }
            var st = stat()
            guard stat(path, &st) == 0 else { return try body() }
            let original = st.st_mode
            guard original & mode_t(S_IWUSR) == 0 else { return try body() }
            if chmod(path, original | mode_t(S_IWUSR)) != 0 {
                let err = errno
                StampLog.error("chmod +w \(url.lastPathComponent) errno=\(err)")
            }
            defer { _ = chmod(path, original) }
            return try body()
        }
    }
}

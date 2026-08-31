import AppKit
import Darwin
import XCTest
@testable import FujikageQL

final class IconStamperTests: XCTestCase {
    func testStampDoesNotRewriteRAFBytesAndSecondPassSkips() throws {
        let url = try writeRAF(in: try makeTempDir("stamp"))
        let before = try Data(contentsOf: url)

        let first = IconStamper.stamp(files: [url], denylist: [], allowSidecars: false)
        XCTAssertEqual(first.failed, 0, first.notes.joined(separator: "; "))
        XCTAssertEqual(first.stamped, 1)
        XCTAssertEqual(first.alreadyStamped, 0)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertTrue(IconStampPolicy.hasCustomIcon(at: url))
        XCTAssertEqual(IconStampPolicy.stampMarker(at: url), .icon)

        let second = IconStamper.stamp(files: [url], denylist: [], allowSidecars: false)
        XCTAssertEqual(second.stamped, 0)
        XCTAssertEqual(second.alreadyStamped, 1)
        XCTAssertEqual(second.failed, 0)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testStampSkipsWhenFinderInfoAlreadyHasCustomIcon() throws {
        let url = try writeRAF(in: try makeTempDir("skip"), width: 8, height: 8)
        var info = Data(count: 32)
        info[8] = 0x04
        try setXAttr("com.apple.FinderInfo", info, at: url)
        XCTAssertTrue(IconStampPolicy.hasCustomIcon(at: url))

        let before = try Data(contentsOf: url)
        let report = IconStamper.stamp(files: [url], denylist: [], allowSidecars: false)
        XCTAssertEqual(report.alreadyStamped, 1)
        XCTAssertEqual(report.stamped, 0)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testStampHonorsDenylist() throws {
        let dir = try makeTempDir("deny")
        let url = try writeRAF(in: dir)
        let report = IconStamper.stamp(files: [url], denylist: [dir.path], allowSidecars: false)
        XCTAssertEqual(report.skipped, 1)
        XCTAssertEqual(report.stamped, 0)
        XCTAssertFalse(IconStampPolicy.hasCustomIcon(at: url))
    }

    func testClearRemovesOnlyOurIcon() throws {
        let dir = try makeTempDir("clear")
        let ours = try writeRAF(in: dir, name: "DSCF0001.RAF")
        let theirs = try writeRAF(in: dir, name: "DSCF0002.RAF")
        let bare = try writeRAF(in: dir, name: "DSCF0003.RAF")

        XCTAssertEqual(IconStamper.stamp(files: [ours], denylist: [], allowSidecars: false).stamped, 1)
        // Someone else's icon: Finder-style, no marker.
        let cg = try XCTUnwrap(RAFEmbeddedJPEG.thumbnailImage(fromJPEG: try makeJPEG(width: 8, height: 8), maxPixelSize: 8))
        let foreign = NSImage(cgImage: cg, size: NSSize(width: 8, height: 8))
        XCTAssertTrue(NSWorkspace.shared.setIcon(foreign, forFile: theirs.path, options: []))
        XCTAssertTrue(IconStampPolicy.hasCustomIcon(at: theirs))
        XCTAssertNil(IconStampPolicy.stampMarker(at: theirs))

        let report = IconStamper.clear(files: [ours, theirs, bare], denylist: [])
        XCTAssertEqual(report.cleared, 1)
        XCTAssertEqual(report.notOurs, 1)
        XCTAssertEqual(report.failed, 0)
        XCTAssertEqual(report.summary, "cleared 1, not ours 1.")
        XCTAssertFalse(IconStampPolicy.hasCustomIcon(at: ours))
        XCTAssertNil(IconStampPolicy.stampMarker(at: ours))
        XCTAssertTrue(IconStampPolicy.hasCustomIcon(at: theirs), "foreign icon must survive Clear")
    }

    func testClearDeletesSidecarOnlyWhenMarkerSaysWeCreatedIt() throws {
        let dir = try makeTempDir("sidecar")
        let keep = try writeRAF(in: dir, name: "DSCF0001.RAF")
        let drop = try writeRAF(in: dir, name: "DSCF0002.RAF")
        let keepSidecar = IconStampPolicy.appleDoubleSidecar(for: keep)
        let dropSidecar = IconStampPolicy.appleDoubleSidecar(for: drop)
        try Data([0x00, 0x05, 0x16, 0x07]).write(to: keepSidecar)
        try Data([0x00, 0x05, 0x16, 0x07]).write(to: dropSidecar)
        XCTAssertEqual(IconStamper.stamp(files: [keep, drop], denylist: [], allowSidecars: true).stamped, 2)
        // On APFS the stamp never creates a sidecar, so force the marker states.
        XCTAssertTrue(IconStampPolicy.setStampMarker(.icon, at: keep))
        XCTAssertTrue(IconStampPolicy.setStampMarker(.iconAndSidecar, at: drop))

        let report = IconStamper.clear(files: [keep, drop], denylist: [])
        XCTAssertEqual(report.cleared, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: keepSidecar.path), "pre-existing sidecar must survive")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dropSidecar.path))
    }

    /// Simulates FAT/NFS: the volume has a `._` sidecar exactly when the file
    /// carries a custom icon, because that is where the icon xattrs went.
    private func sidecarAppearsAfterStamp() -> StampIO {
        StampIO(sidecarExists: { IconStampPolicy.hasCustomIcon(at: $0) })
    }

    func testStampRollsBackAndStopsOnSidecarWhenNotAllowed() throws {
        let dir = try makeTempDir("rollback")
        let first = try writeRAF(in: dir, name: "DSCF0001.RAF")
        let second = try writeRAF(in: dir, name: "DSCF0002.RAF")
        let report = IconStamper.stamp(
            files: [first, second],
            denylist: [],
            allowSidecars: false,
            io: sidecarAppearsAfterStamp()
        )
        XCTAssertEqual(report.stamped, 0)
        XCTAssertEqual(report.failed, 1)
        XCTAssertEqual(report.appleDouble, 1)
        XCTAssertEqual(report.failedFiles, ["DSCF0001.RAF"])
        XCTAssertTrue(report.notes.first?.contains("sidecar") == true, report.notes.joined())
        XCTAssertFalse(IconStampPolicy.hasCustomIcon(at: first), "rolled back")
        XCTAssertNil(IconStampPolicy.stampMarker(at: first))
        XCTAssertFalse(IconStampPolicy.hasCustomIcon(at: second), "stopped before the second file")
    }

    func testStampRecordsSidecarInMarkerWhenAllowed() throws {
        let url = try writeRAF(in: try makeTempDir("allowed"))
        let report = IconStamper.stamp(
            files: [url],
            denylist: [],
            allowSidecars: true,
            io: StampIO(sidecarExists: { _ in true })  // existed before too: not created
        )
        XCTAssertEqual(report.stamped, 1)
        XCTAssertEqual(report.appleDouble, 0)
        XCTAssertEqual(IconStampPolicy.stampMarker(at: url), .icon)

        let created = try writeRAF(in: try makeTempDir("allowed2"))
        let report2 = IconStamper.stamp(
            files: [created],
            denylist: [],
            allowSidecars: true,
            io: sidecarAppearsAfterStamp()
        )
        XCTAssertEqual(report2.stamped, 1)
        XCTAssertEqual(report2.appleDouble, 1)
        XCTAssertEqual(IconStampPolicy.stampMarker(at: created), .iconAndSidecar)
    }

    func testProbeDeniesVolumeThatMakesSidecarsAndRollsBack() throws {
        let url = try writeRAF(in: try makeTempDir("probe"))
        guard case .deny(let reason) = try IconStamper.probe(file: url, io: sidecarAppearsAfterStamp()) else {
            return XCTFail("expected deny")
        }
        XCTAssertTrue(reason.contains("._"))
        XCTAssertFalse(IconStampPolicy.hasCustomIcon(at: url))
        XCTAssertNil(IconStampPolicy.stampMarker(at: url))
    }

    func testProbeAllowsCleanVolumeAndLeavesStampInPlace() throws {
        let url = try writeRAF(in: try makeTempDir("probe-ok"))
        XCTAssertEqual(try IconStamper.probe(file: url), .allow)
        XCTAssertEqual(IconStampPolicy.stampMarker(at: url), .icon)
        XCTAssertEqual(try IconStamper.probe(file: url), .allow, "already stamped file short-circuits")
    }

    func testProbeVolumeThrowsDeniedOnSidecarVolume() throws {
        let dir = try makeTempDir("probe-vol")
        let files = try (1...3).map { try writeRAF(in: dir, name: "DSCF000\($0).RAF") }
        XCTAssertThrowsError(try IconStamper.probeVolume(files, io: sidecarAppearsAfterStamp())) { error in
            guard case IconStampError.denied? = error as? IconStampError else {
                return XCTFail("expected denied, got \(error)")
            }
        }
    }

    func testRafFilesSkipsSidecarsDenylistAndPackages() throws {
        let root = try makeTempDir("walk")
        let nested = root.appendingPathComponent("2026/07", isDirectory: true)
        let denied = root.appendingPathComponent("2026/08", isDirectory: true)
        let package = root.appendingPathComponent("Library.photoslibrary", isDirectory: true)
        for dir in [nested, denied, package] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let a = try writeRAF(in: nested, name: "a.RAF")
        let b = try writeRAF(in: nested, name: "b.raf")
        _ = try writeRAF(in: denied, name: "c.RAF")
        _ = try writeRAF(in: package, name: "d.RAF")
        try Data().write(to: nested.appendingPathComponent("._a.RAF"))
        try Data().write(to: nested.appendingPathComponent("e.jpg"))

        let found = IconStamper.rafFiles(in: root, denylist: [denied.path])
        XCTAssertEqual(Set(found.map(\.lastPathComponent)), Set([a, b].map(\.lastPathComponent)))
    }

    func testStampDetailIncludesDomainAndCode() {
        let err = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoPermissionError,
            userInfo: [
                NSLocalizedDescriptionKey: "The file couldn’t be opened.",
                NSFilePathErrorKey: "/tmp/x.RAF",
                NSUnderlyingErrorKey: NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(EACCES),
                    userInfo: [NSLocalizedDescriptionKey: "Permission denied"]
                ),
            ]
        )
        XCTAssertTrue(err.stampDetail.contains("NSCocoaErrorDomain#257"))
        XCTAssertTrue(err.stampDetail.contains("/tmp/x.RAF"))
        XCTAssertTrue(err.stampDetail.contains("NSPOSIXErrorDomain"))
    }

    func testReportSummary() {
        var report = StampReport()
        XCTAssertEqual(report.summary, "Nothing to do.")
        report.alreadyStamped = 71
        XCTAssertEqual(report.summary, "already stamped 71.")
        report.stamped = 2
        XCTAssertEqual(report.summary, "stamped 2, already stamped 71.")
        report.cancelled = true
        XCTAssertEqual(report.summary, "stamped 2, already stamped 71, stopped.")
        XCTAssertEqual(StampReport(cancelled: true).summary, "stopped.")

        var failed = StampReport()
        failed.failed = 3
        failed.failedFiles = ["_DSF9497.RAF", "_DSF9498.RAF", "_DSF9499.RAF"]
        XCTAssertEqual(failed.summary, "failed 3 (_DSF9497.RAF, _DSF9498.RAF, _DSF9499.RAF).")
        failed.failed = 4
        failed.failedFiles.append("_DSF9500.RAF")
        XCTAssertEqual(failed.summary, "failed 4 (_DSF9497.RAF, _DSF9498.RAF, _DSF9499.RAF, …).")
    }

    func testStampReadOnlyAirDropStyleFileRestoresMode() throws {
        let url = try writeRAF(in: try makeTempDir("ro"))
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        let before = try Data(contentsOf: url)

        let first = IconStamper.stamp(files: [url], denylist: [], allowSidecars: false)
        XCTAssertEqual(first.failed, 0, first.notes.joined(separator: "; "))
        XCTAssertEqual(first.stamped, 1)
        XCTAssertTrue(IconStampPolicy.hasCustomIcon(at: url))
        XCTAssertEqual(IconStampPolicy.stampMarker(at: url), .icon)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(posixMode(url), 0o444)

        let cleared = IconStamper.clear(files: [url], denylist: [])
        XCTAssertEqual(cleared.failed, 0)
        XCTAssertEqual(cleared.cleared, 1)
        XCTAssertFalse(IconStampPolicy.hasCustomIcon(at: url))
        XCTAssertNil(IconStampPolicy.stampMarker(at: url))
        XCTAssertEqual(posixMode(url), 0o444)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func testProgressLabelPadsToAtLeastThreeDigits() {
        XCTAssertEqual(StampProgress.listing.label, "Listing RAF files…")
        XCTAssertEqual(
            StampProgress(listing: false, current: 3, total: 100, filename: "").label,
            "Processing 003/100"
        )
        XCTAssertEqual(
            StampProgress(listing: false, current: 3, total: 100, filename: "a.RAF").label,
            "Processing 003/100  a.RAF"
        )
        XCTAssertEqual(
            StampProgress(listing: false, current: 12, total: 1000, filename: "").label,
            "Processing 0012/1000"
        )
    }

    func testCancelStopsBeforeLaterFiles() throws {
        let dir = try makeTempDir("cancel")
        let urls = try (1...3).map { try writeRAF(in: dir, name: "DSCF000\($0).RAF") }

        final class Seen: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func set(_ n: Int) {
                lock.lock()
                value = n
                lock.unlock()
            }
            func get() -> Int {
                lock.lock()
                defer { lock.unlock() }
                return value
            }
        }
        let seen = Seen()
        let report = IconStamper.stamp(
            files: urls,
            denylist: [],
            allowSidecars: false,
            progress: { current, _, _ in seen.set(current) },
            isCancelled: { seen.get() >= 1 }
        )
        XCTAssertTrue(report.cancelled)
        XCTAssertEqual(report.stamped, 1)
        XCTAssertTrue(IconStampPolicy.hasCustomIcon(at: urls[0]))
        XCTAssertFalse(IconStampPolicy.hasCustomIcon(at: urls[1]))
        XCTAssertFalse(IconStampPolicy.hasCustomIcon(at: urls[2]))
    }
}

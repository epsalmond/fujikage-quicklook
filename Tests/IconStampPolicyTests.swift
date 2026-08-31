import XCTest
@testable import FujikageQL

final class IconStampPolicyTests: XCTestCase {
    func testLocalAPFSIsAllowed() {
        let kind = IconStampPolicy.kind(fstype: "apfs", isLocal: true, isFileProvider: false)
        XCTAssertEqual(kind, .localApple)
        XCTAssertEqual(IconStampPolicy.disposition(for: kind), .allow)
    }

    func testNFSIsDeniedUntilSidecarsEnabled() {
        let kind = IconStampPolicy.kind(fstype: "nfs", isLocal: false, isFileProvider: false)
        XCTAssertEqual(kind, .nfs)
        guard case .deny(let reason) = IconStampPolicy.disposition(for: kind) else {
            return XCTFail("expected deny")
        }
        XCTAssertTrue(reason.contains("NFS"))
    }

    func testSMBRequiresProbe() {
        let kind = IconStampPolicy.kind(fstype: "smbfs", isLocal: false, isFileProvider: false)
        XCTAssertEqual(kind, .smb)
        XCTAssertEqual(IconStampPolicy.disposition(for: kind), .probeRequired)
    }

    func testFATIsDenied() {
        let kind = IconStampPolicy.kind(fstype: "exfat", isLocal: true, isFileProvider: false)
        XCTAssertEqual(kind, .fat)
        guard case .deny = IconStampPolicy.disposition(for: kind) else {
            return XCTFail("expected deny")
        }
    }

    func testFileProviderWinsOverLocalAPFS() {
        let kind = IconStampPolicy.kind(fstype: "apfs", isLocal: true, isFileProvider: true)
        XCTAssertEqual(kind, .fileProvider)
    }

    func testAppleDoubleSidecarName() {
        let url = URL(fileURLWithPath: "/Volumes/tank/raw/DSCF0001.RAF")
        XCTAssertEqual(
            IconStampPolicy.appleDoubleSidecar(for: url).lastPathComponent,
            "._DSCF0001.RAF"
        )
        XCTAssertTrue(IconStampPolicy.isAppleDoubleName("._DSCF0001.RAF"))
        XCTAssertFalse(IconStampPolicy.isRAF(URL(fileURLWithPath: "/tmp/._DSCF0001.RAF")))
        XCTAssertTrue(IconStampPolicy.isRAF(URL(fileURLWithPath: "/tmp/DSCF0001.RAF")))
    }

    func testDenylistIsPrefix() {
        let file = URL(fileURLWithPath: "/Volumes/tank/raw/2026/a.RAF")
        XCTAssertTrue(IconStampPolicy.isDenied(file, prefixes: ["/Volumes/tank/raw"]))
        XCTAssertFalse(IconStampPolicy.isDenied(file, prefixes: ["/Volumes/tank/raw2"]))
        XCTAssertFalse(IconStampPolicy.isDenied(file, prefixes: [""]))
        XCTAssertTrue(IconStampPolicy.isDenied(file, prefixes: ["  /Volumes/tank/raw/2026  "]))
        XCTAssertTrue(IconStampPolicy.isDenied(file, prefixes: ["/volumes/TANK/raw/"]), "case-insensitive, like default APFS")
        XCTAssertTrue(IconStampPolicy.isDenied(file, prefixes: ["/Volumes/tank/raw/2026/a.RAF"]), "exact file match")
        XCTAssertTrue(
            IconStampPolicy.isDenied(
                URL(fileURLWithPath: "/Users/eric/Pictures/2026/07/a.RAF"),
                prefixes: ["/Users/eric/Pictures/2026/07"]
            )
        )
        XCTAssertFalse(
            IconStampPolicy.isDenied(
                URL(fileURLWithPath: "/Users/eric/Pictures/2026/08/a.RAF"),
                prefixes: ["/Users/eric/Pictures/2026/07"]
            )
        )
    }

    func testFinderInfoCustomIconFlagIsBigEndianHasCustomIcon() {
        var info = Data(count: 32)
        XCTAssertFalse(IconStampPolicy.hasCustomIcon(finderInfo: info))
        info[8] = 0x04
        info[9] = 0x00
        XCTAssertTrue(IconStampPolicy.hasCustomIcon(finderInfo: info))
        info[8] = 0x00
        info[9] = 0x04
        XCTAssertFalse(IconStampPolicy.hasCustomIcon(finderInfo: info))
    }

    func testStampMarkerRoundTrip() throws {
        let file = try makeTempDir("marker").appendingPathComponent("a.RAF")
        try Data().write(to: file)
        XCTAssertNil(IconStampPolicy.stampMarker(at: file))
        XCTAssertTrue(IconStampPolicy.setStampMarker(.iconAndSidecar, at: file))
        XCTAssertEqual(IconStampPolicy.stampMarker(at: file), .iconAndSidecar)
        try setXAttr("com.epsalmond.fujikage.stamp", Data("garbage".utf8), at: file)
        XCTAssertNil(IconStampPolicy.stampMarker(at: file), "unknown value reads as no marker")
        IconStampPolicy.removeStampMarker(at: file)
        XCTAssertNil(IconStampPolicy.stampMarker(at: file))
    }

    func testStampableFolderRejectsFilesAndPackages() throws {
        let dir = try makeTempDir("folder")
        XCTAssertTrue(IconStampPolicy.isStampableFolder(dir))
        let package = dir.appendingPathComponent("Lib.photoslibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        XCTAssertFalse(IconStampPolicy.isStampableFolder(package))
        let file = dir.appendingPathComponent("a.RAF")
        try Data().write(to: file)
        XCTAssertFalse(IconStampPolicy.isStampableFolder(file))
    }
}

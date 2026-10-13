import CoreGraphics
import XCTest
@testable import FujikageQL

final class RAFEmbeddedJPEGTests: XCTestCase {
    func testLocationReadsBigEndianOffsetAndLength() throws {
        let jpeg = try makeJPEG(width: 8, height: 4)
        let raf = makeRAF(jpeg: jpeg)
        let location = try RAFEmbeddedJPEG.location(
            inHeader: Data(raf.prefix(RAFEmbeddedJPEG.headerByteCount)),
            fileSize: UInt64(raf.count)
        )
        XCTAssertEqual(location.offset, 0x94)
        XCTAssertEqual(location.byteCount, jpeg.count)
    }

    func testExtractReturnsOnlyTheJPEGRange() throws {
        let jpeg = try makeJPEG(width: 16, height: 10)
        let url = try writeTempRAF(makeRAF(jpeg: jpeg, trailingByteCount: 1_048_576))
        let extracted = try RAFEmbeddedJPEG.jpegData(from: url)
        XCTAssertEqual(extracted, jpeg)
        XCTAssertEqual(RAFEmbeddedJPEG.displaySize(ofJPEG: extracted), CGSize(width: 16, height: 10))
    }

    func testDisplaySizeSwapsForRotatedOrientations() throws {
        for orientation in 1...8 {
            let jpeg = try makeJPEG(width: 16, height: 10, orientation: orientation)
            let expected = (5...8).contains(orientation)
                ? CGSize(width: 10, height: 16)
                : CGSize(width: 16, height: 10)
            XCTAssertEqual(RAFEmbeddedJPEG.displaySize(ofJPEG: jpeg), expected, "orientation \(orientation)")
        }
    }

    func testRejectsMissingMagic() {
        var header = Data(count: RAFEmbeddedJPEG.headerByteCount)
        header.writeUInt32BE(0x94, at: RAFEmbeddedJPEG.jpegOffsetAt)
        header.writeUInt32BE(100, at: RAFEmbeddedJPEG.jpegLengthAt)
        XCTAssertThrowsError(try RAFEmbeddedJPEG.location(inHeader: header, fileSize: 1024)) { error in
            XCTAssertEqual(error as? RAFEmbeddedJPEGError, .missingMagic)
        }
    }

    func testRejectsShortHeader() {
        XCTAssertThrowsError(try RAFEmbeddedJPEG.location(inHeader: Data(count: 8))) { error in
            XCTAssertEqual(error as? RAFEmbeddedJPEGError, .headerTooShort(8))
        }
    }

    func testRejectsZeroOffsetAndLength() {
        XCTAssertThrowsError(
            try RAFEmbeddedJPEG.location(inHeader: rafHeader(offset: 0, length: 100), fileSize: 1024)
        ) { error in
            XCTAssertEqual(error as? RAFEmbeddedJPEGError, .invalidJPEGOffset(0))
        }
        XCTAssertThrowsError(
            try RAFEmbeddedJPEG.location(inHeader: rafHeader(offset: 0x94, length: 0), fileSize: 1024)
        ) { error in
            XCTAssertEqual(error as? RAFEmbeddedJPEGError, .invalidJPEGLength(0))
        }
    }

    func testRejectsRangePastEOF() {
        let header = rafHeader(offset: 0x94, length: 500)
        XCTAssertThrowsError(try RAFEmbeddedJPEG.location(inHeader: header, fileSize: 0xA0)) { error in
            XCTAssertEqual(
                error as? RAFEmbeddedJPEGError,
                .rangeExceedsFile(offset: 0x94, length: 500, fileSize: 0xA0)
            )
        }
    }

    func testRejectsOversizedJPEGHeaderAndAllowsSupportedBoundary() throws {
        let limit = RAFEmbeddedJPEG.maximumJPEGByteCount
        let supported = try RAFEmbeddedJPEG.location(
            inHeader: rafHeader(offset: 0x94, length: limit),
            fileSize: UInt64(limit) + 0x94
        )
        XCTAssertEqual(supported.byteCount, Int(limit))
        for length in [limit + 1, UInt32.max] {
            XCTAssertThrowsError(try RAFEmbeddedJPEG.location(
                inHeader: rafHeader(offset: 0x94, length: length),
                fileSize: UInt64(length) + 0x94
            )) { error in
                XCTAssertEqual(error as? RAFEmbeddedJPEGError, .jpegTooLarge(length))
            }
        }
    }

    func testRejectsOversizedJPEGInSparseRAFWhoseRangeFitsEOF() throws {
        let offset: UInt32 = 0x94
        let length = UInt32.max
        let url = try writeTempRAF(rafHeader(offset: offset, length: length))
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        // A valid SOI and EOF-fitting range must still fail before allocating.
        try handle.write(contentsOf: Data([0xFF, 0xD8]))
        try handle.truncate(atOffset: UInt64(offset) + UInt64(length))
        XCTAssertThrowsError(try RAFEmbeddedJPEG.jpegData(from: url)) { error in
            XCTAssertEqual(error as? RAFEmbeddedJPEGError, .jpegTooLarge(length))
        }
    }

    func testRejectsNonJPEGPayload() throws {
        var payload = Data(repeating: 0xAA, count: 64)
        payload[0] = 0x00
        payload[1] = 0x00
        let url = try writeTempRAF(makeRAF(jpeg: payload))
        XCTAssertThrowsError(try RAFEmbeddedJPEG.jpegData(from: url)) { error in
            XCTAssertEqual(error as? RAFEmbeddedJPEGError, .notJPEG)
        }
    }

    func testFileWhoseDeclaredJPEGPastEOFFails() throws {
        let jpeg = try makeJPEG(width: 8, height: 8)
        var raf = makeRAF(jpeg: jpeg, trailingByteCount: 0)
        raf.writeUInt32BE(UInt32(jpeg.count + 50), at: RAFEmbeddedJPEG.jpegLengthAt)
        let url = try writeTempRAF(raf)
        XCTAssertThrowsError(try RAFEmbeddedJPEG.jpegData(from: url)) { error in
            guard case .rangeExceedsFile? = error as? RAFEmbeddedJPEGError else {
                return XCTFail("expected rangeExceedsFile, got \(error)")
            }
        }
    }

    func testThumbnailFitsInsideMaxPixelSize() throws {
        let jpeg = try makeJPEG(width: 64, height: 32)
        let image = try XCTUnwrap(RAFEmbeddedJPEG.thumbnailImage(fromJPEG: jpeg, maxPixelSize: 16))
        XCTAssertLessThanOrEqual(max(image.width, image.height), 16)
    }

    func testAspectFit() {
        XCTAssertEqual(
            RAFEmbeddedJPEG.aspectFit(CGSize(width: 64, height: 32), in: CGSize(width: 16, height: 16)),
            CGSize(width: 16, height: 8)
        )
        XCTAssertEqual(
            RAFEmbeddedJPEG.aspectFit(.zero, in: CGSize(width: 16, height: 16)),
            CGSize(width: 16, height: 16)
        )
    }

    /// Real camera file. `FUJIKAGE_TEST_RAF=/path/to/DSCF0001.RAF make test`.
    /// Skips when unset; fails, not skips, when set but unreadable.
    func testExtractsJPEGFromRealRAF() throws {
        guard let path = ProcessInfo.processInfo.environment["FUJIKAGE_TEST_RAF"], !path.isEmpty else {
            throw XCTSkip("FUJIKAGE_TEST_RAF not set")
        }
        let url = URL(fileURLWithPath: path)
        XCTAssertTrue(FileManager.default.isReadableFile(atPath: url.path), "\(path) is not readable")
        let jpeg = try RAFEmbeddedJPEG.jpegData(from: url)
        XCTAssertTrue(RAFEmbeddedJPEG.isJPEG(jpeg))
        let size = try XCTUnwrap(RAFEmbeddedJPEG.displaySize(ofJPEG: jpeg))
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
    }

    private func writeTempRAF(_ data: Data) throws -> URL {
        let url = try makeTempDir("raf").appendingPathComponent("DSCF0001.RAF")
        try data.write(to: url)
        return url
    }
}

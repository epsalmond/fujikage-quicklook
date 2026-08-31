import CoreGraphics
import Darwin
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import FujikageQL

enum FixtureError: Error {
    case context, image, destination, finalize, path
}

/// A synthetic RAF: magic + big-endian offset/length at 0x54/0x58, the JPEG at
/// `jpegOffset`, then `trailingByteCount` of zeros standing in for the CFA payload.
func makeRAF(
    jpeg: Data,
    jpegOffset: UInt32 = 0x94,
    trailingByteCount: Int = 256
) -> Data {
    var data = Data(count: Int(jpegOffset) + jpeg.count + trailingByteCount)
    let magic = Data(RAFEmbeddedJPEG.magic.utf8)
    data.replaceSubrange(0..<magic.count, with: magic)
    data.writeUInt32BE(jpegOffset, at: RAFEmbeddedJPEG.jpegOffsetAt)
    data.writeUInt32BE(UInt32(jpeg.count), at: RAFEmbeddedJPEG.jpegLengthAt)
    data.replaceSubrange(Int(jpegOffset)..<(Int(jpegOffset) + jpeg.count), with: jpeg)
    return data
}

func rafHeader(offset: UInt32, length: UInt32) -> Data {
    var header = Data(count: RAFEmbeddedJPEG.headerByteCount)
    let magic = Data(RAFEmbeddedJPEG.magic.utf8)
    header.replaceSubrange(0..<magic.count, with: magic)
    header.writeUInt32BE(offset, at: RAFEmbeddedJPEG.jpegOffsetAt)
    header.writeUInt32BE(length, at: RAFEmbeddedJPEG.jpegLengthAt)
    return header
}

func makeJPEG(width: Int, height: Int, orientation: Int? = nil) throws -> Data {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw FixtureError.context }
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else { throw FixtureError.image }
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data, UTType.jpeg.identifier as CFString, 1, nil
    ) else { throw FixtureError.destination }
    var properties: [CFString: Any] = [:]
    if let orientation {
        properties[kCGImagePropertyOrientation] = orientation
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw FixtureError.finalize }
    return data as Data
}

extension XCTestCase {
    /// Fresh directory under the (APFS) container tmp, removed at teardown.
    func makeTempDir(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fkql-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    /// Writes a synthetic RAF with a small embedded JPEG.
    func writeRAF(in dir: URL, name: String = "DSCF0001.RAF", width: Int = 16, height: Int = 10) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try makeRAF(jpeg: try makeJPEG(width: width, height: height)).write(to: url)
        return url
    }
}

func posixMode(_ url: URL) -> Int {
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    return (attrs?[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

func setXAttr(_ name: String, _ value: Data, at url: URL) throws {
    try url.withUnsafeFileSystemRepresentation { path in
        guard let path else { throw FixtureError.path }
        let rc = value.withUnsafeBytes { raw in
            setxattr(path, name, raw.baseAddress, value.count, 0, 0)
        }
        XCTAssertEqual(rc, 0, "setxattr \(name) errno=\(errno)")
    }
}

extension Data {
    mutating func writeUInt32BE(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(truncatingIfNeeded: value >> 24)
        self[offset + 1] = UInt8(truncatingIfNeeded: value >> 16)
        self[offset + 2] = UInt8(truncatingIfNeeded: value >> 8)
        self[offset + 3] = UInt8(truncatingIfNeeded: value)
    }
}

import CoreGraphics
import Foundation
import ImageIO

/// Range-reads the full-size embedded JPEG from a Fujifilm RAF.
///
/// Layout matches exiftool `Image::ExifTool::FujiFilm::RAFHeader` in
/// `FujiFilm.pm` and dcraw `parse_fuji`: magic `FUJIFILMCCD-RAW` at byte 0,
/// JPEG offset as big-endian u32 at 0x54, JPEG length as big-endian u32 at
/// 0x58. The JPEG itself is an Exif JFIF (camera-applied film simulation)
/// and is what Finder should show.
///
/// Only the 0x5C-byte header and the JPEG range are read, so a compressed
/// RAF on a network share does not pull the CFA payload.
public enum RAFEmbeddedJPEG: Sendable {
    public static let magic = "FUJIFILMCCD-RAW"
    public static let jpegOffsetAt = 0x54
    public static let jpegLengthAt = 0x58
    public static let headerByteCount = 0x5C

    public struct Location: Equatable, Sendable {
        public let offset: UInt64
        public let byteCount: Int

        public var endOffset: UInt64 { offset + UInt64(byteCount) }
    }

    public static func location(inHeader header: Data, fileSize: UInt64? = nil) throws -> Location {
        guard header.count >= headerByteCount else {
            throw RAFEmbeddedJPEGError.headerTooShort(header.count)
        }

        let magicData = Data(magic.utf8)
        guard header.starts(with: magicData) else {
            throw RAFEmbeddedJPEGError.missingMagic
        }

        let offset = header.uInt32BE(at: jpegOffsetAt)
        let length = header.uInt32BE(at: jpegLengthAt)

        guard offset > 0 else {
            throw RAFEmbeddedJPEGError.invalidJPEGOffset(offset)
        }
        guard length > 0 else {
            throw RAFEmbeddedJPEGError.invalidJPEGLength(length)
        }

        let location = Location(offset: UInt64(offset), byteCount: Int(length))
        if let fileSize, location.endOffset > fileSize {
            throw RAFEmbeddedJPEGError.rangeExceedsFile(
                offset: location.offset,
                length: UInt64(location.byteCount),
                fileSize: fileSize
            )
        }
        return location
    }

    public static func jpegData(from url: URL) throws -> Data {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try jpegData(from: handle)
    }

    public static func jpegData(from handle: FileHandle) throws -> Data {
        let header = try readExactly(handle, count: headerByteCount)
        let fileSize = try handle.seekToEnd()
        let location = try location(inHeader: header, fileSize: fileSize)
        try handle.seek(toOffset: location.offset)
        let jpeg = try readExactly(handle, count: location.byteCount)
        guard isJPEG(jpeg) else {
            throw RAFEmbeddedJPEGError.notJPEG
        }
        return jpeg
    }

    public static func isJPEG(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0xFF && data[data.startIndex + 1] == 0xD8
    }

    /// Pixel size after applying Exif orientation (the size Quick Look should use).
    public static func displaySize(ofJPEG data: Data) -> CGSize? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = props[kCGImagePropertyPixelWidth as String] as? Int,
              let height = props[kCGImagePropertyPixelHeight as String] as? Int
        else {
            return nil
        }

        let orientation = props[kCGImagePropertyOrientation as String] as? Int ?? 1
        if (5...8).contains(orientation) {
            return CGSize(width: height, height: width)
        }
        return CGSize(width: width, height: height)
    }

    public static func thumbnailImage(fromJPEG data: Data, maxPixelSize: CGFloat) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let pixelSize = max(Int(maxPixelSize.rounded(.down)), 1)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    public static func aspectFit(_ size: CGSize, in maxSize: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, maxSize.width > 0, maxSize.height > 0 else {
            return maxSize
        }
        let scale = min(maxSize.width / size.width, maxSize.height / size.height)
        return CGSize(
            width: max(floor(size.width * scale), 1),
            height: max(floor(size.height * scale), 1)
        )
    }

    static func readExactly(_ handle: FileHandle, count: Int) throws -> Data {
        var data = Data()
        data.reserveCapacity(count)
        while data.count < count {
            let remaining = count - data.count
            guard let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty else {
                throw RAFEmbeddedJPEGError.truncatedRead(expected: count, actual: data.count)
            }
            data.append(chunk)
        }
        return data
    }
}

public enum RAFEmbeddedJPEGError: Error, Equatable, Sendable, LocalizedError {
    case headerTooShort(Int)
    case missingMagic
    case invalidJPEGOffset(UInt32)
    case invalidJPEGLength(UInt32)
    case rangeExceedsFile(offset: UInt64, length: UInt64, fileSize: UInt64)
    case truncatedRead(expected: Int, actual: Int)
    case notJPEG

    public var errorDescription: String? {
        switch self {
        case .headerTooShort(let count):
            return "RAF header is too short (\(count) bytes)."
        case .missingMagic:
            return "File is not a Fujifilm RAF (missing FUJIFILMCCD-RAW magic)."
        case .invalidJPEGOffset(let offset):
            return "RAF embedded JPEG offset is invalid (\(offset))."
        case .invalidJPEGLength(let length):
            return "RAF embedded JPEG length is invalid (\(length))."
        case .rangeExceedsFile(let offset, let length, let fileSize):
            return "RAF embedded JPEG range \(offset)..<\(offset + length) exceeds file size \(fileSize)."
        case .truncatedRead(let expected, let actual):
            return "RAF read truncated (expected \(expected) bytes, got \(actual))."
        case .notJPEG:
            return "RAF embedded preview is not a JPEG."
        }
    }
}

extension Data {
    /// Caller guarantees `offset + 4 <= count`.
    func uInt32BE(at offset: Int) -> UInt32 {
        precondition(count >= offset + 4)
        return UInt32(self[startIndex + offset]) << 24
            | UInt32(self[startIndex + offset + 1]) << 16
            | UInt32(self[startIndex + offset + 2]) << 8
            | UInt32(self[startIndex + offset + 3])
    }
}

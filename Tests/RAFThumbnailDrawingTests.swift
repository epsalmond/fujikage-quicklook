import CoreGraphics
import XCTest
@testable import FujikageQL

final class RAFThumbnailDrawingTests: XCTestCase {
    func testPortraitAndLandscapeFillCoreGraphicsBitmapsAtEveryBackingScale() throws {
        for size in [CGSize(width: 96, height: 128), CGSize(width: 128, height: 96)] {
            for scale in 1...3 {
                try assertFilled(size: size, scale: scale, scaledCoordinates: false)
            }
        }
    }

    func testDrawingAlsoFillsBitmapWhenContextAlreadyUsesPointCoordinates() throws {
        for size in [CGSize(width: 96, height: 128), CGSize(width: 128, height: 96)] {
            try assertFilled(size: size, scale: 2, scaledCoordinates: true)
        }
    }

    private func assertFilled(size: CGSize, scale: Int, scaledCoordinates: Bool) throws {
        let jpeg = try makeJPEG(width: Int(size.width), height: Int(size.height))
        let image = try XCTUnwrap(RAFEmbeddedJPEG.thumbnailImage(fromJPEG: jpeg, maxPixelSize: 128))
        let width = Int(size.width) * scale
        let height = Int(size.height) * scale
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            if scaledCoordinates {
                context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            }
            XCTAssertTrue(RAFThumbnailDrawing.draw(image, in: context))
        }
        // Transparent margins exposed the tiny-corner failure on Retina Macs.
        // Inspect the whole returned bitmap, including each of its corners.
        let transparentPixels = stride(from: 3, to: pixels.count, by: 4)
            .filter { pixels[$0] != 255 }.count
        XCTAssertEqual(
            transparentPixels, 0,
            "\(width)×\(height), scale \(scale), point coordinates \(scaledCoordinates)"
        )
    }
}

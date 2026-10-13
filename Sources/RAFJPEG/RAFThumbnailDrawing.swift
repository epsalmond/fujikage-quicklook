import CoreGraphics

enum RAFThumbnailDrawing {
    /// Quick Look scales the bitmap to the request's backing scale. Its
    /// Core Graphics callback must fill that bitmap, rather than a point-sized
    /// rectangle in its lower-left corner.
    static func draw(_ image: CGImage, in context: CGContext) -> Bool {
        guard context.width > 0, context.height > 0 else { return false }
        let pixels = CGRect(x: 0, y: 0, width: context.width, height: context.height)
        let bounds = context.convertToUserSpace(pixels)
        context.interpolationQuality = .high
        context.draw(image, in: bounds)
        return true
    }
}

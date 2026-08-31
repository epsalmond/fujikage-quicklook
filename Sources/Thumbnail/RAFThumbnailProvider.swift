import CoreGraphics
import Foundation
import os
import QuickLookThumbnailing

private let log = Logger(subsystem: "com.epsalmond.fujikage.quicklook", category: "thumbnail")

@objc(RAFThumbnailProvider)
final class RAFThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let path = request.fileURL.path
        log.notice("thumbnail request \(path, privacy: .public)")
        do {
            let jpeg = try RAFEmbeddedJPEG.jpegData(from: request.fileURL)
            let maxPixel = max(request.maximumSize.width, request.maximumSize.height) * request.scale
            guard let image = RAFEmbeddedJPEG.thumbnailImage(fromJPEG: jpeg, maxPixelSize: maxPixel) else {
                handler(nil, RAFEmbeddedJPEGError.notJPEG)
                return
            }
            let imageSize = CGSize(width: image.width, height: image.height)
            let contextSize = RAFEmbeddedJPEG.aspectFit(imageSize, in: request.maximumSize)
            let reply = QLThumbnailReply(contextSize: contextSize, drawing: { context in
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(origin: .zero, size: contextSize))
                return true
            })
            reply.extensionBadge = "RAF"
            handler(reply, nil)
        } catch {
            log.error("thumbnail failed: \(error.localizedDescription, privacy: .public)")
            handler(nil, error)
        }
    }
}

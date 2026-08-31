import QuickLookUI
import UniformTypeIdentifiers

final class RAFPreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let jpeg = try RAFEmbeddedJPEG.jpegData(from: request.fileURL)
        let size = RAFEmbeddedJPEG.displaySize(ofJPEG: jpeg) ?? CGSize(width: 800, height: 600)
        return QLPreviewReply(dataOfContentType: .jpeg, contentSize: size) { _ in
            jpeg
        }
    }
}

import AppKit
import SwiftUI

enum FolderDrop {
    static var optionHeld: Bool {
        NSEvent.modifierFlags.contains(.option)
    }

    static func foldersFromDragPasteboard() -> [URL] {
        let urls = NSPasteboard(name: .drag).readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return urls.filter { IconStampPolicy.isStampableFolder($0) }
    }
}

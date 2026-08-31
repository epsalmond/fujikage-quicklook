import Darwin
import Foundation

/// `kHasCustomIcon` in `FileInfo.finderFlags`. FinderInfo xattr is big-endian.
private let finderInfoCustomIconFlag: UInt16 = 0x0400
private let finderInfoFlagOffset = 8
private let finderInfoXAttr = "com.apple.FinderInfo"

/// Provenance for Clear. Written next to the icon so Clear only removes icons
/// FujikageQL put there, and only deletes a `._` sidecar it created.
private let stampMarkerXAttr = "com.epsalmond.fujikage.stamp"

enum StampMarker: String, Equatable, Sendable {
    case icon
    case iconAndSidecar = "icon+sidecar"
}

enum VolumeKind: Equatable, Sendable {
    case localApple
    case fat
    case nfs
    case smb
    case fileProvider
    case otherRemote
    case unknown
}

enum StampDisposition: Equatable, Sendable {
    case allow
    case deny(String)
    case probeRequired
}

enum IconStampPolicy {
    static func kind(fstype: String, isLocal: Bool, isFileProvider: Bool) -> VolumeKind {
        if isFileProvider { return .fileProvider }
        switch fstype.lowercased() {
        case "apfs", "hfs":
            return isLocal ? .localApple : .otherRemote
        case "exfat", "msdos", "fat", "fat32":
            return .fat
        case "nfs", "nfs4":
            return .nfs
        case "smbfs", "smb", "cifs":
            return .smb
        case "afpfs", "webdav", "fuse", "osxfuse", "macfuse":
            return .otherRemote
        default:
            if isLocal { return .unknown }
            return .otherRemote
        }
    }

    static func disposition(for kind: VolumeKind) -> StampDisposition {
        switch kind {
        case .localApple:
            return .allow
        case .fat:
            return .deny("FAT/exFAT stores Finder icons as ._ sidecar files.")
        case .nfs:
            return .deny(
                "NFS from macOS usually writes ._ AppleDouble files, not ZFS xattrs. SMB with vfs_fruit is the protocol that stores Finder metadata in ZFS xattrs."
            )
        case .fileProvider:
            return .deny("File Provider volumes often strip Finder xattrs.")
        case .smb, .otherRemote, .unknown:
            return .probeRequired
        }
    }

    static func appleDoubleSidecar(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("._" + url.lastPathComponent)
    }

    static func isAppleDoubleName(_ name: String) -> Bool {
        name.hasPrefix("._")
    }

    static func isRAF(_ url: URL) -> Bool {
        !isAppleDoubleName(url.lastPathComponent) && url.pathExtension.lowercased() == "raf"
    }

    static func isDenied(_ url: URL, prefixes: [String]) -> Bool {
        let path = url.standardizedFileURL.path
        return prefixes.contains { prefix in
            let trimmed = (prefix as NSString).standardizingPath
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            if path.caseInsensitiveCompare(trimmed) == .orderedSame { return true }
            let dir = trimmed.hasSuffix("/") ? trimmed : trimmed + "/"
            return path.lowercased().hasPrefix(dir.lowercased())
        }
    }

    static func isStampableFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    static func hasCustomIcon(finderInfo data: Data) -> Bool {
        guard data.count >= finderInfoFlagOffset + 2 else { return false }
        let flags = UInt16(data[data.startIndex + finderInfoFlagOffset]) << 8
            | UInt16(data[data.startIndex + finderInfoFlagOffset + 1])
        return flags & finderInfoCustomIconFlag != 0
    }

    static func hasCustomIcon(at url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            var buf = [UInt8](repeating: 0, count: 32)
            let n = getxattr(path, finderInfoXAttr, &buf, buf.count, 0, 0)
            guard n >= finderInfoFlagOffset + 2 else { return false }
            return hasCustomIcon(finderInfo: Data(buf.prefix(Int(n))))
        } ?? false
    }

    static func stampMarker(at url: URL) -> StampMarker? {
        url.withUnsafeFileSystemRepresentation { path -> StampMarker? in
            guard let path else { return nil }
            var buf = [UInt8](repeating: 0, count: 64)
            let n = getxattr(path, stampMarkerXAttr, &buf, buf.count, 0, 0)
            guard n > 0, let raw = String(bytes: buf.prefix(Int(n)), encoding: .utf8) else { return nil }
            return StampMarker(rawValue: raw)
        }
    }

    @discardableResult
    static func setStampMarker(_ marker: StampMarker, at url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            let bytes = Array(marker.rawValue.utf8)
            return setxattr(path, stampMarkerXAttr, bytes, bytes.count, 0, 0) == 0
        } ?? false
    }

    static func removeStampMarker(at url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            _ = removexattr(path, stampMarkerXAttr, 0)
        }
    }
}

import Darwin
import Foundation

struct VolumeFacts: Equatable, Sendable {
    var fstype: String
    var isLocal: Bool
    var isReadOnly: Bool
    /// Path heuristic (`/Library/CloudStorage/`, `.fileprovider`); there is no
    /// resource key that says "File Provider volume".
    var isFileProvider: Bool
    var kind: VolumeKind
    var disposition: StampDisposition

    var summary: String {
        var parts = [fstype]
        parts.append(isLocal ? "local" : "remote")
        if isReadOnly { parts.append("read-only") }
        if isFileProvider { parts.append("File Provider") }
        return parts.joined(separator: ", ")
    }

    static func inspect(_ url: URL) -> VolumeFacts {
        let values = try? url.resourceValues(forKeys: [
            .volumeIsLocalKey,
            .volumeIsReadOnlyKey,
        ])
        let fstype = fileSystemTypeName(at: url) ?? "unknown"
        let isLocal = values?.volumeIsLocal ?? false
        let isReadOnly = values?.volumeIsReadOnly ?? false
        let path = url.path
        let isFileProvider = path.contains("/Library/CloudStorage/")
            || path.contains(".fileprovider")
        let kind = IconStampPolicy.kind(
            fstype: fstype,
            isLocal: isLocal,
            isFileProvider: isFileProvider
        )
        var disposition = IconStampPolicy.disposition(for: kind)
        if isReadOnly {
            disposition = .deny("Volume is read-only.")
        }
        return VolumeFacts(
            fstype: fstype,
            isLocal: isLocal,
            isReadOnly: isReadOnly,
            isFileProvider: isFileProvider,
            kind: kind,
            disposition: disposition
        )
    }
}

private func fileSystemTypeName(at url: URL) -> String? {
    url.withUnsafeFileSystemRepresentation { path in
        guard let path else { return nil }
        var stats = statfs()
        guard statfs(path, &stats) == 0 else { return nil }
        return withUnsafeBytes(of: stats.f_fstypename) { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                return nil
            }
            return String(cString: base)
        }
    }
}
